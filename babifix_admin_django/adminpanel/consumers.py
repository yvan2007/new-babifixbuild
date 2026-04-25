import json
import logging
from urllib.parse import parse_qs

from channels.db import database_sync_to_async
from channels.generic.websocket import AsyncWebsocketConsumer

from .auth import verify_token
from .models import Conversation, Message, UserProfile

logger = logging.getLogger(__name__)


def _extract_token(scope: dict) -> str | None:
    """
    Extrait le JWT depuis le scope ASGI (Django Channels).

    Channels stocke les headers sous forme de liste de tuples bytes, pas un dict.
    On teste 3 méthodes dans l'ordre de sécurité décroissante :
      1. Authorization: Bearer <token>      (header HTTP custom — le plus sûr)
      2. Sec-WebSocket-Protocol: BABIFIX <token>  (subprotocol standard WS)
      3. ?token=<token> dans la query string      (déprécié, visible dans les logs)
    """
    headers = dict(scope.get('headers') or [])

    # Method 1 : Authorization Bearer
    auth = headers.get(b'authorization', b'').decode('utf-8', errors='ignore')
    if auth.startswith('Bearer '):
        token = auth[7:].strip()
        if token:
            return token

    # Method 2 : Sec-WebSocket-Protocol BABIFIX <token>
    proto = headers.get(b'sec-websocket-protocol', b'').decode('utf-8', errors='ignore')
    if proto.startswith('BABIFIX '):
        token = proto[8:].strip()
        if token:
            return token

    # Method 3 : ?token= query string (backward compat — deprecated)
    qs = parse_qs(scope.get('query_string', b'').decode('utf-8', errors='ignore'))
    token = (qs.get('token') or [''])[0].strip()
    return token or None


class ClientEventsConsumer(AsyncWebsocketConsumer):
    """
    Flux temps réel pour apps client & prestataire (JWT).
    Nouveau prestataire approuvé, actualités publiées, etc.
    Groupe : babifix_client_events
    """

    group_name = 'babifix_client_events'

    async def connect(self):
        token = _extract_token(self.scope)
        if not token:
            await self.close(code=4401)
            return
        pl = verify_token(token)
        role = pl.get('role') if pl else None
        if not pl or role not in (
            UserProfile.Role.CLIENT,
            UserProfile.Role.PRESTATAIRE,
        ):
            await self.close(code=4403)
            return
        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()
        await self.send(text_data=json.dumps({
            'type': 'system.connected',
            'payload': {'message': 'Connecte au flux client BABIFIX'},
        }))

    async def disconnect(self, code):
        await self.channel_layer.group_discard(self.group_name, self.channel_name)

    async def client_notify(self, event):
        await self.send(text_data=json.dumps({
            'type': event['event_type'],
            'payload': event.get('payload') or {},
        }))


class PrestataireEventsConsumer(AsyncWebsocketConsumer):
    """
    Flux WebSocket pour l'app prestataire (JWT).
    Groupe : babifix_prestataire_<user_id>
    """

    async def connect(self):
        token = _extract_token(self.scope)
        if not token:
            await self.close(code=4401)
            return
        pl = verify_token(token)
        if not pl or pl.get('role') != UserProfile.Role.PRESTATAIRE:
            await self.close(code=4403)
            return
        try:
            uid = int(pl.get('uid'))
        except (TypeError, ValueError):
            await self.close(code=4403)
            return
        self.group_name = f'babifix_prestataire_{uid}'
        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()
        await self.send(text_data=json.dumps({
            'type': 'system.connected',
            'payload': {'message': 'Connecte au flux prestataire BABIFIX'},
        }))

    async def disconnect(self, code):
        if hasattr(self, 'group_name'):
            await self.channel_layer.group_discard(self.group_name, self.channel_name)

    async def prestataire_notify(self, event):
        await self.send(text_data=json.dumps({
            'type': event['event_type'],
            'payload': event.get('payload') or {},
        }))


class ChatConsumer(AsyncWebsocketConsumer):
    """
    WebSocket de chat en temps réel entre client et prestataire.
    URL : ws/chat/<conv_id>/
    Groupe : chat_<conv_id>

    Messages entrants (client → serveur) :
      {"type": "chat.message", "body": "...", "reply_to": <id|null>}
      {"type": "typing",       "is_typing": true|false}

    Messages sortants (serveur → client) :
      {"type": "chat.message", "message": {...}}
      {"type": "typing",       "sender_id": <id>, "is_typing": bool}
    """

    async def connect(self):
        # --- Authentification ---
        token = _extract_token(self.scope)
        if not token:
            await self.close(code=4401)
            return
        pl = verify_token(token)
        role = pl.get('role') if pl else None
        if not pl or role not in (UserProfile.Role.CLIENT, UserProfile.Role.PRESTATAIRE):
            await self.close(code=4403)
            return
        try:
            self._uid = int(pl.get('uid'))
        except (TypeError, ValueError):
            await self.close(code=4403)
            return

        # --- Vérifier accès à la conversation ---
        conv_id_raw = self.scope['url_route']['kwargs'].get('conv_id')
        try:
            conv_id = int(conv_id_raw)
        except (TypeError, ValueError):
            await self.close(code=4404)
            return

        if not await self._has_access(conv_id, self._uid):
            await self.close(code=4403)
            return

        self._conv_id = conv_id
        self.group_name = f'chat_{conv_id}'
        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()
        await self.send(text_data=json.dumps({
            'type': 'system.connected',
            'payload': {'conv_id': conv_id},
        }))

    async def disconnect(self, code):
        if hasattr(self, 'group_name'):
            await self.channel_layer.group_discard(self.group_name, self.channel_name)

    async def receive(self, text_data=None, bytes_data=None):
        if not text_data:
            return
        try:
            data = json.loads(text_data)
        except (json.JSONDecodeError, TypeError):
            return

        msg_type = data.get('type', '')

        if msg_type == 'chat.message':
            body = (data.get('body') or '').strip()
            if not body or len(body) > 5000:
                return
            reply_to_id = data.get('reply_to')
            msg = await self._save_message(self._conv_id, self._uid, body, reply_to_id)
            if msg:
                await self.channel_layer.group_send(self.group_name, {
                    'type': 'chat_message',
                    'message': msg,
                })

        elif msg_type == 'typing':
            await self.channel_layer.group_send(self.group_name, {
                'type': 'chat_typing',
                'sender_id': self._uid,
                'is_typing': bool(data.get('is_typing', False)),
            })

    # --- Group message handlers ---

    async def chat_message(self, event):
        await self.send(text_data=json.dumps({
            'type': 'chat.message',
            'message': event['message'],
        }))

    async def chat_typing(self, event):
        if event.get('sender_id') != self._uid:
            await self.send(text_data=json.dumps({
                'type': 'typing',
                'sender_id': event['sender_id'],
                'is_typing': event['is_typing'],
            }))

    # --- DB helpers ---

    @database_sync_to_async
    def _has_access(self, conv_id: int, uid: int) -> bool:
        try:
            conv = Conversation.objects.get(pk=conv_id)
            return conv.client_id == uid or conv.prestataire_id == uid
        except Conversation.DoesNotExist:
            return False

    @database_sync_to_async
    def _save_message(self, conv_id: int, uid: int, body: str, reply_to_id) -> dict | None:
        try:
            conv = Conversation.objects.get(pk=conv_id)
            reply_to = None
            if reply_to_id:
                try:
                    reply_to = Message.objects.get(pk=int(reply_to_id), conversation=conv)
                except (Message.DoesNotExist, ValueError):
                    pass
            from django.contrib.auth import get_user_model
            User = get_user_model()
            sender = User.objects.get(pk=uid)
            msg = Message.objects.create(
                conversation=conv,
                sender=sender,
                body=body,
                reply_to=reply_to,
            )
            conv.save(update_fields=['updated_at'])
            return {
                'id': msg.pk,
                'body': msg.body,
                'sender_id': uid,
                'reply_to_id': reply_to_id,
                'created_at': msg.created_at.isoformat() if hasattr(msg, 'created_at') else None,
            }
        except Exception as exc:
            logger.error('ChatConsumer._save_message error: %s', exc)
            return None


class AdminEventsConsumer(AsyncWebsocketConsumer):
    """
    Flux WebSocket réservé aux comptes staff (superuser inclus).
    Même session cookie que le dashboard Django.
    """

    group_name = 'babifix_admin_events'

    async def connect(self):
        user = self.scope.get('user')
        if not user or not user.is_authenticated:
            await self.close(code=4401)
            return
        if not user.is_staff:
            await self.close(code=4403)
            return
        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()
        await self.send(text_data=json.dumps({
            'type': 'system.connected',
            'payload': {'message': 'Connecte au flux temps reel BABIFIX'},
        }))

    async def disconnect(self, code):
        await self.channel_layer.group_discard(self.group_name, self.channel_name)

    async def admin_notify(self, event):
        await self.send(text_data=json.dumps({
            'type': event['event_type'],
            'payload': event.get('payload') or {},
        }))
