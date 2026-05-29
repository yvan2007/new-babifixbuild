"""
BABIFIX Pro — Vues API B2B (comptes professionnels, sites, interventions, facturation).
"""
import json
import logging

from django.contrib.auth.models import User
from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_GET

from .auth import require_api_auth
from .services.b2b_service import B2BService

logger = logging.getLogger(__name__)


def _get_account(user_id):
    from .models import ProAccount
    return ProAccount.objects.filter(user_id=user_id, actif=True).first()


def _body(request):
    try:
        return json.loads(request.body or "{}")
    except (json.JSONDecodeError, TypeError):
        return None


@require_GET
def api_pro_formules(request):
    """GET → formules BABIFIX Pro (public)."""
    return JsonResponse({"formules": B2BService.formules()}, status=200)


@csrf_exempt
@require_api_auth(["client", "admin"])
def api_pro_account(request):
    """GET → mon compte pro + sites · POST → créer un compte pro."""
    user_id = request.api_user_id

    if request.method == "GET":
        acc = _get_account(user_id)
        if not acc:
            return JsonResponse({"is_pro": False}, status=200)
        return JsonResponse({
            "is_pro": True,
            "account": B2BService.serialize_account(acc),
            "sites": [B2BService.serialize_site(s) for s in acc.sites.filter(actif=True)],
        }, status=200)

    if request.method == "POST":
        body = _body(request)
        if body is None:
            return JsonResponse({"error": "invalid_json"}, status=400)
        raison = str(body.get("raison_sociale") or "").strip()
        if not raison:
            return JsonResponse({"error": "raison_sociale_required"}, status=400)
        try:
            user = User.objects.get(pk=user_id)
        except User.DoesNotExist:
            return JsonResponse({"error": "user_not_found"}, status=404)
        result = B2BService.create_account(
            user, raison, formule=body.get("formule", "starter"),
            contact_nom=body.get("contact_nom", ""),
            contact_telephone=body.get("contact_telephone", ""),
            contact_email=body.get("contact_email", ""),
        )
        status = 200 if result.get("ok") else 400
        return JsonResponse(result, status=status)

    return JsonResponse({"error": "method_not_allowed"}, status=405)


@csrf_exempt
@require_api_auth(["client", "admin"])
def api_pro_sites(request):
    """GET → liste des sites · POST → ajouter un site."""
    acc = _get_account(request.api_user_id)
    if not acc:
        return JsonResponse({"error": "not_a_pro_account"}, status=403)

    if request.method == "GET":
        return JsonResponse(
            {"sites": [B2BService.serialize_site(s) for s in acc.sites.filter(actif=True)]},
            status=200,
        )

    if request.method == "POST":
        body = _body(request)
        if body is None:
            return JsonResponse({"error": "invalid_json"}, status=400)
        nom = str(body.get("nom") or "").strip()
        if not nom:
            return JsonResponse({"error": "nom_required"}, status=400)
        result = B2BService.add_site(
            acc, nom,
            adresse=body.get("adresse", ""),
            commune=body.get("commune", ""),
            latitude=body.get("latitude"),
            longitude=body.get("longitude"),
            contact_sur_site=body.get("contact_sur_site", ""),
            telephone_sur_site=body.get("telephone_sur_site", ""),
        )
        return JsonResponse(result, status=200 if result.get("ok") else 400)

    return JsonResponse({"error": "method_not_allowed"}, status=405)


@csrf_exempt
@require_api_auth(["client", "admin"])
def api_pro_declare_intervention(request):
    """POST → déclarer une intervention sur un site {site_id, description, montant_estime}."""
    if request.method != "POST":
        return JsonResponse({"error": "method_not_allowed"}, status=405)

    acc = _get_account(request.api_user_id)
    if not acc:
        return JsonResponse({"error": "not_a_pro_account"}, status=403)

    body = _body(request)
    if body is None:
        return JsonResponse({"error": "invalid_json"}, status=400)

    site = acc.sites.filter(pk=body.get("site_id"), actif=True).first()
    if not site:
        return JsonResponse({"error": "site_not_found"}, status=404)

    description = str(body.get("description") or "").strip()
    if not description:
        return JsonResponse({"error": "description_required"}, status=400)

    result = B2BService.declare_intervention(
        acc, site, description, montant_estime=body.get("montant_estime", 0)
    )
    return JsonResponse(result, status=200 if result.get("ok") else 400)


@csrf_exempt
@require_api_auth(["client", "admin"])
def api_pro_invoice(request):
    """GET ?periode=AAAA-MM → génère/retourne la facture mensuelle groupée."""
    acc = _get_account(request.api_user_id)
    if not acc:
        return JsonResponse({"error": "not_a_pro_account"}, status=403)

    from django.utils import timezone
    periode = request.GET.get("periode") or timezone.now().strftime("%Y-%m")
    result = B2BService.generate_monthly_invoice(acc, periode)
    return JsonResponse(result, status=200 if result.get("ok") else 400)
