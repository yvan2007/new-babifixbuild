from django.apps import AppConfig


class AdminpanelConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "adminpanel"

    def ready(self):
        # Signaux -> WebSocket admin (evite import circulaire : hook apres chargement des modeles)
        import adminpanel.signals  # noqa: F401
        import adminpanel.push_dispatch  # noqa: F401
        from adminpanel.perf_signals import register_cache_invalidation

        register_cache_invalidation()
