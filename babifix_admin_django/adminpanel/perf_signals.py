"""Signaux de performance DB (SQLite WAL) et invalidation ciblee du cache public."""

from __future__ import annotations

import logging

from django.core.cache import cache
from django.db.backends.signals import connection_created
from django.db.models.signals import post_delete, post_save
from django.dispatch import receiver

logger = logging.getLogger("babifix.perf")

CACHE_KEYS_PUBLIC_CATALOG = (
    "babifix:public:categories:all",
    "babifix:public:categories:client",
    "public_categories_v1",
    "public_providers_default_v1",
    "public_providers_featured_v1",
    "public_vitrine_v1",
    "public_actualites_v1",
    "babifix:public:tier_configs:v1",
    "babifix:public:platform_config:v1",
)

CACHE_KEYS_ADMIN_DASHBOARD = (
    "babifix:admin:kpi_payload:v1",
    "babifix:admin:risk_radar:v1",
    "babifix:admin:sidebar_counts:v1",
)


@receiver(connection_created)
def _configure_sqlite_wal(sender, connection, **kwargs):
    """Active le mode WAL et busy_timeout sur SQLite pour eviter database is locked."""
    if connection.vendor == "sqlite":
        try:
            with connection.cursor() as cursor:
                cursor.execute("PRAGMA journal_mode=WAL;")
                cursor.execute("PRAGMA synchronous=NORMAL;")
                cursor.execute("PRAGMA busy_timeout=5000;")
                cursor.execute("PRAGMA temp_store=MEMORY;")
                cursor.execute("PRAGMA cache_size=-16000;")
        except Exception as exc:
            logger.debug("SQLite WAL setup skipped: %s", exc)


def get_catalog_cache_version() -> int:
    """Retourne le numero de version courant des caches catalogue publics."""
    try:
        v = cache.get("babifix:catalog:ver")
        if v is None:
            cache.set("babifix:catalog:ver", 1, None)
            return 1
        return int(v)
    except Exception:
        return 1


def invalidate_public_catalog_cache(*args, **kwargs):
    """Invalide proprement les caches catalogue en incrementant la version O(1)."""
    try:
        try:
            cache.incr("babifix:catalog:ver")
        except Exception:
            cur = get_catalog_cache_version()
            cache.set("babifix:catalog:ver", cur + 1, None)
        cache.delete_many(list(CACHE_KEYS_PUBLIC_CATALOG))
    except Exception:
        pass


def invalidate_admin_dashboard_cache(*args, **kwargs):
    """Invalide les caches KPI et radar du dashboard Admin apres mutation metier."""
    try:
        cache.delete_many(list(CACHE_KEYS_ADMIN_DASHBOARD))
    except Exception:
        pass


def register_cache_invalidation():
    """Connecte les signaux ORM apres demarrage Django."""
    from .models import (
        Category,
        Client,
        Dispute,
        Notification,
        Payment,
        PlatformConfig,
        Provider,
        Rating,
        Reservation,
        SiteContent,
        SystemSetting,
        WalletTransaction,
    )

    for model_cls in (Provider, Category, SiteContent, SystemSetting, PlatformConfig):
        post_save.connect(invalidate_public_catalog_cache, sender=model_cls, weak=False)
        post_delete.connect(invalidate_public_catalog_cache, sender=model_cls, weak=False)

    for model_cls in (
        Provider,
        Reservation,
        Payment,
        Dispute,
        Client,
        Rating,
        WalletTransaction,
        Notification,
    ):
        post_save.connect(invalidate_admin_dashboard_cache, sender=model_cls, weak=False)
        post_delete.connect(invalidate_admin_dashboard_cache, sender=model_cls, weak=False)
