"""
ASGI : HTTP Django + WebSocket (Django Channels) pour le panel admin temps réel.
"""
import asyncio
import logging
import os

from channels.auth import AuthMiddlewareStack
from channels.routing import ProtocolTypeRouter, URLRouter
from django.core.asgi import get_asgi_application

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')

logger = logging.getLogger('django.request')


class CatchCancelledErrorMiddleware:
    """ASGI middleware : attrape CancelledError pour éviter les logs intempestifs
    quand Daphne annule une tâche synchrone (connexion fermée par le client)."""

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        try:
            await self.app(scope, receive, send)
        except asyncio.CancelledError:
            logger.debug('Requête annulée (CancelledError) — connexion fermée par le client ou timeout.')
        except Exception:
            logger.exception('Erreur ASGI non gérée')
            raise


django_asgi_app = CatchCancelledErrorMiddleware(get_asgi_application())

from adminpanel.routing import websocket_urlpatterns  # noqa: E402

application = ProtocolTypeRouter(
    {
        'http': django_asgi_app,
        'websocket': AuthMiddlewareStack(URLRouter(websocket_urlpatterns)),
    }
)
