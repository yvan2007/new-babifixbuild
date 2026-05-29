"""
Middleware de sécurité BABIFIX.

Ajoute des en-têtes HTTP que Django ne pose pas par défaut :
- Content-Security-Policy : limite XSS, injection de scripts tiers, exfiltration.
- Permissions-Policy     : désactive caméra/micro/geolocation/USB pour les pages
                           web (les apps Flutter natives ne sont pas concernées).
- Cross-Origin-Resource-Policy : empêche d'inclure nos ressources depuis une
                                 origine tierce.

Ces réponses sont posées sur tout le HTML servi par Django (admin + dashboard
+ vitrine + endpoints API si HTML). Pour les réponses JSON, certains entêtes
restent inoffensifs.
"""
from __future__ import annotations

from django.conf import settings


class BabifixSecurityHeadersMiddleware:
    """Pose les en-têtes manquants après le passage de SecurityMiddleware."""

    # Politique CSP — strict mais compatible avec :
    # - Google Fonts (vitrine) ;
    # - les images statiques BABIFIX (logo, payment-logos) ;
    # - le tableau de bord admin (inline styles autorisés via 'unsafe-inline').
    _CSP = (
        "default-src 'self'; "
        "img-src 'self' data: https://babifix.ci https://*.babifix.ci https://fonts.gstatic.com; "
        "font-src 'self' data: https://fonts.gstatic.com; "
        "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; "
        "script-src 'self' 'unsafe-inline'; "
        "connect-src 'self' https://babifix.ci https://*.babifix.ci wss: https:; "
        "frame-ancestors 'none'; "
        "form-action 'self'; "
        "base-uri 'self'; "
        "object-src 'none'; "
        "upgrade-insecure-requests"
    )

    _PERMISSIONS = (
        "accelerometer=(), "
        "autoplay=(), "
        "camera=(), "
        "display-capture=(), "
        "encrypted-media=(), "
        "fullscreen=(self), "
        "geolocation=(), "
        "gyroscope=(), "
        "magnetometer=(), "
        "microphone=(), "
        "midi=(), "
        "payment=(), "
        "picture-in-picture=(), "
        "publickey-credentials-get=(), "
        "screen-wake-lock=(), "
        "sync-xhr=(self), "
        "usb=(), "
        "xr-spatial-tracking=()"
    )

    def __init__(self, get_response):
        self.get_response = get_response
        # En dev on relâche un peu pour permettre `localhost:5173` etc.
        env = getattr(settings, "_BABIFIX_ENV", None)
        self._is_dev = bool(getattr(settings, "DEBUG", False)) or env == "development"

    def __call__(self, request):
        response = self.get_response(request)

        # Ne pas écraser si une vue a explicitement posé son CSP.
        if "Content-Security-Policy" not in response:
            response["Content-Security-Policy"] = self._CSP
        if "Permissions-Policy" not in response:
            response["Permissions-Policy"] = self._PERMISSIONS
        # Politique COEP/CORP : empêche le hotlinking de nos ressources.
        response.setdefault("Cross-Origin-Resource-Policy", "same-site")
        # Cache-Control pour les pages d'admin sensibles : pas de cache public.
        path = request.path or ""
        if path.startswith(("/admin", "/api/admin", "/dashboard")):
            response["Cache-Control"] = "no-store, no-cache, must-revalidate, private"
            response["Pragma"] = "no-cache"
        return response
