"""
ASGI : HTTP Django (ThreadPool multi-threads concurrent) + WebSocket Channels.

Remplace l'execution mono-thread par defaut (`sync_to_async(thread_sensitive=True)`)
de `get_asgi_application()` par un pool borne de threads WSGI afin qu'une page Admin
ou une requete lente ne bloque jamais les endpoints API mobiles ni les webhooks.
"""
from __future__ import annotations

import asyncio
import logging
import os
from concurrent.futures import ThreadPoolExecutor
from tempfile import SpooledTemporaryFile

from asgiref.sync import AsyncToSync
from asgiref.wsgi import WsgiToAsgiInstance
from channels.auth import AuthMiddlewareStack
from channels.routing import ProtocolTypeRouter, URLRouter
from django.core.wsgi import get_wsgi_application
from django.db import close_old_connections

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")

logger = logging.getLogger("django.request")

_HTTP_WORKERS = max(2, min(12, int(os.getenv("BABIFIX_HTTP_THREADS", "6"))))
_HTTP_EXECUTOR = ThreadPoolExecutor(
    max_workers=_HTTP_WORKERS,
    thread_name_prefix="babifix-http",
)


class _ConcurrentWsgiToAsgiInstance(WsgiToAsgiInstance):
    """Execute la vue WSGI dans _HTTP_EXECUTOR sans verrou global thread_sensitive."""

    async def run_wsgi_app(self, body):
        loop = asyncio.get_running_loop()
        await loop.run_in_executor(_HTTP_EXECUTOR, self._run_wsgi_sync, body)

    def _run_wsgi_sync(self, body):
        close_old_connections()
        try:
            try:
                environ = self.build_environ(self.scope, body)
            except ValueError:
                self.sync_send(
                    {
                        "type": "http.response.start",
                        "status": 400,
                        "headers": [(b"content-type", b"text/plain")],
                    }
                )
                self.sync_send(
                    {
                        "type": "http.response.body",
                        "body": b"Bad Request: Too many duplicate headers",
                    }
                )
                return

            bytes_sent = 0
            for output in self.wsgi_application(environ, self.start_response):
                if not self.response_started:
                    self.response_started = True
                    self.sync_send(self.response_start)
                if self.response_content_length is not None:
                    bytes_allowed = self.response_content_length - bytes_sent
                    if len(output) > bytes_allowed:
                        output = output[:bytes_allowed]
                self.sync_send(
                    {"type": "http.response.body", "body": output, "more_body": True}
                )
                bytes_sent += len(output)
                if bytes_sent == self.response_content_length:
                    break
            if not self.response_started:
                self.response_started = True
                self.sync_send(self.response_start)
            self.sync_send({"type": "http.response.body"})
        finally:
            close_old_connections()


class ConcurrentWsgiToAsgi:
    """Adaptateur ASGI -> WSGI multi-threads compatible WebSockets Channels."""

    def __init__(self, wsgi_application, duplicate_header_limit=100):
        self.wsgi_application = wsgi_application
        self.duplicate_header_limit = duplicate_header_limit

    async def __call__(self, scope, receive, send):
        instance = _ConcurrentWsgiToAsgiInstance(
            self.wsgi_application,
            self.duplicate_header_limit,
        )
        if scope["type"] != "http":
            raise ValueError("WSGI wrapper received a non-HTTP scope")
        instance.scope = scope
        with SpooledTemporaryFile(max_size=65536) as body:
            while True:
                message = await receive()
                if message["type"] != "http.request":
                    raise ValueError("WSGI wrapper received a non-HTTP-request message")
                body.write(message.get("body", b""))
                if not message.get("more_body"):
                    break
            body.seek(0)
            instance.sync_send = AsyncToSync(send)
            await instance.run_wsgi_app(body)


class CatchCancelledErrorMiddleware:
    """ASGI middleware : attrape CancelledError quand le client ferme la connexion."""

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        try:
            await self.app(scope, receive, send)
        except asyncio.CancelledError:
            logger.debug("Requete annulee (CancelledError) : connexion fermee par le client.")
        except Exception:
            logger.exception("Erreur ASGI non geree")
            raise


django_wsgi_app = get_wsgi_application()
django_asgi_app = CatchCancelledErrorMiddleware(ConcurrentWsgiToAsgi(django_wsgi_app))

from adminpanel.routing import websocket_urlpatterns  # noqa: E402

application = ProtocolTypeRouter(
    {
        "http": django_asgi_app,
        "websocket": AuthMiddlewareStack(URLRouter(websocket_urlpatterns)),
    }
)
