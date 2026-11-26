from unittest.mock import MagicMock, patch

from django.core.cache.backends.redis import RedisCache
from django.test import RequestFactory, SimpleTestCase

from adminpanel import realtime
from adminpanel.safe_cache import SafeRedisCache
from adminpanel.throttle import check_rate_limit


class ResilienceAnti500Tests(SimpleTestCase):
    def test_safe_redis_cache_falls_back_to_locmem_when_redis_fails(self):
        cache = SafeRedisCache("redis://127.0.0.1:6399/0", {})
        with patch.object(RedisCache, "get", side_effect=ConnectionError("redis down")):
            with patch.object(RedisCache, "set", side_effect=ConnectionError("redis down")):
                cache.set("k1", "valeur", 60)
                self.assertEqual(cache.get("k1"), "valeur")

    def test_check_rate_limit_never_crashes_when_cache_raises(self):
        rf = RequestFactory()
        req = rf.post("/api/auth/login")
        with patch("adminpanel.throttle.cache.get", side_effect=ConnectionError("redis down")):
            self.assertFalse(check_rate_limit(req, "login", max_requests=5, window=60))

    def test_realtime_broadcast_swallows_channel_layer_errors(self):
        broken_layer = MagicMock()

        async def _boom(*args, **kwargs):
            raise ConnectionError("redis channel down")

        broken_layer.group_send = _boom
        with patch("adminpanel.realtime.get_channel_layer", return_value=broken_layer):
            realtime.broadcast_admin_event("provider.created", {"id": 1})
            realtime.broadcast_client_event("provider.approved", {"id": 1})
            realtime.broadcast_client_user(1, "res.updated", {})
            realtime.broadcast_prestataire_user(1, "mission.new", {})
            realtime.broadcast_chat_message(1, {"text": "ok"})
