"""
Backend de cache Redis resilient pour Render Free Tier.

Sur Render Free Redis (connexions limitees, veille ou micro-coupures reseau),
le backend standard `django.core.cache.backends.redis.RedisCache` leve une
exception non geree qui transforme n'importe quel endpoint en HTTP 500.

`SafeRedisCache` enveloppe `RedisCache` avec un fallback automatique et
transparent sur un `LocMemCache` local par worker en cas d'indisponibilite
Redis, evitant ainsi toute erreur 500 due au cache.
"""
from __future__ import annotations

import logging
from typing import Any

from django.core.cache.backends.locmem import LocMemCache
from django.core.cache.backends.redis import RedisCache

logger = logging.getLogger("adminpanel.cache")


class SafeRedisCache(RedisCache):
    """RedisCache avec repli transparent sur LocMemCache si Redis echoue."""

    def __init__(self, server: str, params: dict[str, Any]) -> None:
        safe_params = dict(params or {})
        options = dict(safe_params.get("OPTIONS") or {})
        options.setdefault("socket_connect_timeout", 2)
        options.setdefault("socket_timeout", 2)
        options.setdefault("retry_on_timeout", False)
        safe_params["OPTIONS"] = options
        super().__init__(server, safe_params)
        self._fallback = LocMemCache("babifix-redis-fallback", safe_params)

    def _safe(self, method_name: str, *args: Any, **kwargs: Any) -> Any:
        try:
            redis_fn = getattr(super(), method_name)
            return redis_fn(*args, **kwargs)
        except Exception as exc:
            logger.warning(
                "Cache Redis indisponible (%s), repli LocMemCache : %s",
                method_name,
                exc,
            )
            fallback_fn = getattr(self._fallback, method_name)
            return fallback_fn(*args, **kwargs)

    def get(self, key: Any, default: Any = None, version: int | None = None) -> Any:
        return self._safe("get", key, default=default, version=version)

    def set(
        self,
        key: Any,
        value: Any,
        timeout: Any = ...,
        version: int | None = None,
    ) -> None:
        kwargs: dict[str, Any] = {"version": version}
        if timeout is not ...:
            kwargs["timeout"] = timeout
        return self._safe("set", key, value, **kwargs)

    def add(
        self,
        key: Any,
        value: Any,
        timeout: Any = ...,
        version: int | None = None,
    ) -> bool:
        kwargs: dict[str, Any] = {"version": version}
        if timeout is not ...:
            kwargs["timeout"] = timeout
        return bool(self._safe("add", key, value, **kwargs))

    def delete(self, key: Any, version: int | None = None) -> bool:
        return bool(self._safe("delete", key, version=version))

    def incr(self, key: Any, delta: int = 1, version: int | None = None) -> int:
        try:
            return super().incr(key, delta=delta, version=version)
        except ValueError:
            raise
        except Exception as exc:
            logger.warning("Cache Redis indisponible (incr), repli LocMemCache : %s", exc)
            return self._fallback.incr(key, delta=delta, version=version)

    def decr(self, key: Any, delta: int = 1, version: int | None = None) -> int:
        try:
            return super().decr(key, delta=delta, version=version)
        except ValueError:
            raise
        except Exception as exc:
            logger.warning("Cache Redis indisponible (decr), repli LocMemCache : %s", exc)
            return self._fallback.decr(key, delta=delta, version=version)

    def has_key(self, key: Any, version: int | None = None) -> bool:
        return bool(self._safe("has_key", key, version=version))

    def get_many(self, keys: Any, version: int | None = None) -> dict[Any, Any]:
        return self._safe("get_many", keys, version=version)

    def set_many(
        self,
        data: dict[Any, Any],
        timeout: Any = ...,
        version: int | None = None,
    ) -> list[Any]:
        kwargs: dict[str, Any] = {"version": version}
        if timeout is not ...:
            kwargs["timeout"] = timeout
        return self._safe("set_many", data, **kwargs)

    def delete_many(self, keys: Any, version: int | None = None) -> None:
        return self._safe("delete_many", keys, version=version)

    def clear(self) -> None:
        return self._safe("clear")
