from django.urls import path

from .consumers import AdminEventsConsumer, ClientEventsConsumer, PrestataireEventsConsumer

websocket_urlpatterns = [
    path('ws/admin/events/', AdminEventsConsumer.as_asgi()),
    path('ws/client/events/', ClientEventsConsumer.as_asgi()),
    path('ws/prestataire/events/', PrestataireEventsConsumer.as_asgi()),
]
