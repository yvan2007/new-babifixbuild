from django.apps import AppConfig


class AdminpanelConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "adminpanel"

    def ready(self):
        # Signaux → WebSocket admin (évite import circulaire : hook après chargement des modèles)
        import adminpanel.signals  # noqa: F401
        import adminpanel.push_dispatch  # noqa: F401
