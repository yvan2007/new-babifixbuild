from django.apps import AppConfig
from django.db.backends.signals import connection_created


def _enable_sqlite_wal(sender, connection, **kwargs):
    if connection.vendor == "sqlite":
        try:
            with connection.cursor() as cursor:
                cursor.execute("PRAGMA journal_mode=WAL;")
                cursor.execute("PRAGMA synchronous=NORMAL;")
                cursor.execute("PRAGMA busy_timeout=5000;")
                cursor.execute("PRAGMA cache_size=-8000;")
        except Exception:
            pass


class VitrineConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "vitrine"

    def ready(self):
        connection_created.connect(_enable_sqlite_wal, weak=False)
