from django.conf import settings


def site_globals(request):
    """Variables disponibles dans tous les templates vitrine."""
    return {
        # ID de mesure Google Analytics 4 (G-XXXXXXXXXX), depuis l'env.
        # L'analytics ne se charge QUE si l'utilisateur accepte les cookies.
        "ga_id": getattr(settings, "GA_MEASUREMENT_ID", ""),
    }
