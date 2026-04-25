import json
from urllib.parse import parse_qs

from channels.generic.websocket import AsyncWebsocketConsumer

from .auth import verify_token
from .models import UserProfile


class ClientEventsConsumer(AsyncWebsocketConsumer):
    """
    Flux temps réel pour apps client & prestataire (JWT) :
    nouveau prestataire approuvé, actualités publiées, etc.
    Groupe : babifix_client_events
    """

    group_name = 'babifix_client_events'

    async def connect(self):
        token = None
        
        # Method 1: Authorization header (PRIVILEGED - recommended)
        auth_header = self.scope.get('headers', {}).get(b'authorization', b'').decode()
        if auth_header.startswith('Bearer '):
            token = auth_header[7:].strip()
        
        # Method 2: Sec-WebSocket-Protocol header
        if not token:
            protocols = self.scope.get('headers', {}).get(b'sec-websocket-protocol', b'').decode()
            if protocols.startswith('BABIFIX '):
                token = protocols[7:].strip()
        
        # Method 3: Query string token (DEPRECATED - only for backward compatibility)
        if not token:
            qs = parse_qs(self.scope.get('query_string', b'').decode())
            token = (qs.get('token') or [''])[0].strip()
        
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
        await self.send(
            text_data=json.dumps(
                {
                    'type': 'system.connected',
                    'payload': {'message': 'Connecte au flux client BABIFIX'},
                }
            )
        )

    async def disconnect(self, code):
        await self.channel_layer.group_discard(self.group_name, self.channel_name)

    async def client_notify(self, event):
        await self.send(
            text_data=json.dumps(
                {
                    'type': event['event_type'],
                    'payload': event.get('payload') or {},
                }
            )
        )


class PrestataireEventsConsumer(AsyncWebsocketConsumer):
    """
    WebSocket pour l’app prestataire : JWT en query ?token=...
    Groupe : babifix_prestataire_<user_id>
    """

    async def connect(self):
        token = None
        
        # Method 1: Authorization header (PRIVILEGED - recommended)
        auth_header = self.scope.get('headers', {}).get(b'authorization', b'').decode()
        if auth_header.startswith('Bearer '):
            token = auth_header[7:].strip()
        
        # Method 2: Sec-WebSocket-Protocol header
        if not token:
            protocols = self.scope.get('headers', {}).get(b'sec-websocket-protocol', b'').decode()
            if protocols.startswith('BABIFIX '):
                token = protocols[7:].strip()
        
        # Method 3: Query string token (DEPRECATED - only for backward compatibility)
        if not token:
            qs = parse_qs(self.scope.get('query_string', b'').decode())
            token = (qs.get('token') or [''])[0].strip()
        
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
        await self.send(
            text_data=json.dumps(
                {
                    'type': 'system.connected',
                    'payload': {'message': 'Connecte au flux prestataire BABIFIX'},
                }
            )
        )

    async def disconnect(self, code):
        if hasattr(self, 'group_name'):
            await self.channel_layer.group_discard(self.group_name, self.channel_name)

    async def prestataire_notify(self, event):
        await self.send(
            text_data=json.dumps(
                {
                    'type': event['event_type'],
                    'payload': event.get('payload') or {},
                }
            )
        )


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
        await self.send(
            text_data=json.dumps(
                {
                    'type': 'system.connected',
                    'payload': {'message': 'Connecte au flux temps reel BABIFIX'},
                }
            )
        )

    async def disconnect(self, code):
        await self.channel_layer.group_discard(self.group_name, self.channel_name)

    async def admin_notify(self, event):
        """Message émis par group_send depuis realtime.broadcast_admin_event."""
        await self.send(
            text_data=json.dumps(
                {
                    'type': event['event_type'],
                    'payload': event.get('payload') or {},
                }
            )
        )
