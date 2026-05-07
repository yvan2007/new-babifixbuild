"""
WebSocket consumer for real-time push notifications (categories, providers).
Broadcasts updates to all connected clients when data changes.
"""

import json
from channels.generic.websocket import AsyncWebsocketConsumer
from channels.db import database_sync_to_async
from asgiref.sync import sync_to_async


class RealtimeUpdatesConsumer(AsyncWebsocketConsumer):
    """Consumer for real-time push updates (replaces polling)"""

    group_name = "babifix_client_events"

    async def connect(self):
        await self.channel_layer.group_add(self.group_name, self.channel_name)

        await self.accept()
        await self.send(
            text_data=json.dumps(
                {"type": "connected", "message": "Connecté au flux temps réel BABIFIX"}
            )
        )

    async def disconnect(self, close_code):
        await self.channel_layer.group_discard(self.group_name, self.channel_name)

    async def receive(self, text_data):
        data = json.loads(text_data)
        action = data.get("action")

        if action == "ping":
            await self.send(text_data=json.dumps({"type": "pong"}))

    async def client_notify(self, event):
        """Handle broadcasts from realtime.py (type: client.notify)"""
        await self.send(
            text_data=json.dumps({
                "type": event["event_type"],
                **event.get("payload", {}),
            })
        )

    async def categories_update(self, event):
        await self.send(
            text_data=json.dumps({
                "type": "categories_update",
                "categories": event.get("categories", []),
            })
        )

    async def providers_update(self, event):
        await self.send(
            text_data=json.dumps({
                "type": "providers_update",
                "providers": event.get("providers", []),
            })
        )

    async def new_provider(self, event):
        await self.send(
            text_data=json.dumps({
                "type": "new_provider",
                "provider": event.get("provider", {}),
            })
        )
