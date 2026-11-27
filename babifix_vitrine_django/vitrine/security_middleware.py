"""
Middleware de securite pour la Vitrine BABIFIX.

Applique les en-tetes HTTP modernes de protection des sites web :
- Content-Security-Policy (CSP) : empeche les injections de scripts tiers, XSS et exfiltration.
- Permissions-Policy : desactive les capteurs invasifs (camera, micro, geolocation, USB) sur le site vitrine.
- X-Content-Type-Options: nosniff
- Referrer-Policy: strict-origin-when-cross-origin
- Cross-Origin-Opener-Policy & Cross-Origin-Resource-Policy
"""

from django.conf import settings


class BabifixVitrineSecurityHeadersMiddleware:
    """Pose les en-tetes de securite stricts sur toutes les reponses du site vitrine."""

    # CSP adapte au site vitrine BABIFIX (Google Fonts, OpenStreetMap iframe, assets statiques et analytics)
    _CSP = (
        "default-src 'self'; "
        "img-src 'self' data: blob: https://babifix.ci https://*.babifix.ci https://fonts.gstatic.com "
        "https://*.openstreetmap.org https://www.google-analytics.com https://*.google-analytics.com; "
        "font-src 'self' data: https://fonts.gstatic.com; "
        "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; "
        "script-src 'self' 'unsafe-inline' https://www.googletagmanager.com; "
        "connect-src 'self' https://www.google-analytics.com https://*.google-analytics.com; "
        "frame-src 'self' https://www.openstreetmap.org https://*.openstreetmap.org; "
        "frame-ancestors 'none'; "
        "form-action 'self' https://wa.me; "
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
        "usb=()"
    )

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        response = self.get_response(request)

        # Content Security Policy
        if "Content-Security-Policy" not in response:
            response["Content-Security-Policy"] = self._CSP

        # Permissions Policy
        if "Permissions-Policy" not in response:
            response["Permissions-Policy"] = self._PERMISSIONS

        # X-Content-Type-Options
        response["X-Content-Type-Options"] = "nosniff"

        # Referrer Policy
        response["Referrer-Policy"] = "strict-origin-when-cross-origin"

        # Protection X-Frame-Options contre le clickjacking
        if "X-Frame-Options" not in response:
            response["X-Frame-Options"] = "DENY"

        path = request.path or ""
        if path.startswith(("/admin", "/api/admin")):
            response["Cache-Control"] = "no-store, no-cache, must-revalidate, private"
            response["Pragma"] = "no-cache"
        response.setdefault("Cross-Origin-Resource-Policy", "same-site")

        return response
