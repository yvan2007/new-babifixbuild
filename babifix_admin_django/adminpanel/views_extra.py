"""
BABIFIX — vues API supplémentaires (ajout sans modifier views.py principal)
  - Email transactionnels
  - Toggle disponibilité prestataire
  - CRUD disponibilités (créneaux + indisponibilités)
  - Statistiques prestataire
  - Bulk actions admin (valider/refuser en masse)
  - Journal d'audit admin
  - Export CSV étendu
  - Favoris client
  - Historique paiements
  - Litiges prestataire
"""

import builtins
import csv
import json
import logging

from django.contrib.auth.decorators import login_required
from django.db.models import Avg, Count, Q, Sum
from django.http import HttpResponse, JsonResponse, StreamingHttpResponse
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_GET, require_http_methods

from .auth import require_api_auth
from .models import (
    AdminAuditLog,
    Dispute,
    Payment,
    PrestataireAvailabilitySlot,
    PrestataireUnavailability,
    Provider,
    Reservation,
)

logger = logging.getLogger(__name__)


def _safe_print(*args, **kwargs):
    cleaned = []
    for arg in args:
        text = str(arg)
        cleaned.append(text.encode("cp1252", errors="ignore").decode("cp1252"))
    builtins.print(*cleaned, **kwargs)


print = _safe_print


from django.template.loader import render_to_string

def email_welcome(user, role: str) -> None:
    """Email de bienvenue Premium lors de l'inscription."""
    print(f"[EMAIL] email_welcome called: {user.email}, role={role}")
    if not user.email:
        print("[WARN] No user email, skipping")
        return

    is_prestataire = role == "prestataire"
    role_description = (
        "Rejoignez des milliers de prestataires certifiés"
        if is_prestataire
        else "Trouvez le prestataire idéal près de chez vous"
    )
    # Nom d'affichage propre (évite « Bienvenue, email@gmail.com »).
    display_name = (user.get_full_name() or user.username or "").strip()
    if "@" in display_name:
        display_name = display_name.split("@")[0]
    display_name = display_name.capitalize() if display_name else "bienvenue"

    html_content = render_to_string('emails/welcome.html', {
        "username": display_name,
        "role_description": role_description,
        "app_url": "https://new-babifixbuild.onrender.com",
        "is_prestataire": is_prestataire,
        "cta_text": "Accéder à mon espace" if is_prestataire
        else "Découvrir BABIFIX",
    })

    try:
        send_babifix_email_html(
            to_email=user.email,
            subject=f"Bienvenue sur BABIFIX !",
            html_content=html_content,
        )
    except Exception as exc:
        logger.warning("Email non envoyé (%s) : %s", user.email, exc)


def email_provider_accepted(provider: Provider) -> None:
    if not (provider.user and provider.user.email):
        return
    send_babifix_email(
        to_email=provider.user.email,
        subject="Votre dossier BABIFIX a été accepté !",
        body=(
            f"Bonjour {provider.nom},\n\n"
            "Bonne nouvelle ! Votre compte prestataire BABIFIX a été validé.\n"
            "Vous pouvez désormais recevoir des missions via l'application.\n\n"
            "Bienvenue dans la communauté BABIFIX — Côte d'Ivoire.\n\n"
            "L'équipe BABIFIX | contact@babifix.ci"
        ),
    )


def email_provider_refused(provider: Provider, motif: str = "") -> None:
    if not (provider.user and provider.user.email):
        return
    send_babifix_email(
        to_email=provider.user.email,
        subject="Votre dossier BABIFIX nécessite des corrections",
        body=(
            f"Bonjour {provider.nom},\n\n"
            "Après examen, notre équipe a identifié des corrections nécessaires.\n\n"
            f"Motif : {motif or 'Dossier incomplet ou non conforme.'}\n\n"
            "Vous pouvez soumettre à nouveau votre dossier depuis l'application "
            "sans recréer de compte.\n\n"
            "L'équipe BABIFIX | contact@babifix.ci"
        ),
    )


def email_new_reservation(provider: Provider, reservation: Reservation) -> None:
    if not (provider.user and provider.user.email):
        return
    send_babifix_email(
        to_email=provider.user.email,
        subject=f"Nouvelle demande de service : {reservation.title or reservation.reference}",
        body=(
            f"Bonjour {provider.nom},\n\n"
            f"Vous avez reçu une nouvelle demande de service.\n\n"
            f"Référence : {reservation.reference}\n"
            f"Client    : {reservation.client}\n"
            f"Adresse   : {reservation.address_label or 'Non précisée'}\n\n"
            "Ouvrez l'application BABIFIX Prestataire pour accepter ou décliner.\n\n"
            "L'équipe BABIFIX | contact@babifix.ci"
        ),
    )


def email_mission_completed(reservation: Reservation) -> None:
    from .models import UserProfile

    client_user = reservation.client_user
    if not (client_user and client_user.email):
        return
    send_babifix_email(
        to_email=client_user.email,
        subject="Votre mission BABIFIX est terminée : Évaluez votre prestataire",
        body=(
            f"Bonjour,\n\n"
            f'Votre mission "{reservation.title or reservation.reference}" '
            f"avec {reservation.prestataire} est marquée comme terminée.\n\n"
            "Prenez un moment pour évaluer votre prestataire dans l'application BABIFIX.\n"
            "Votre avis aide la communauté et améliore la qualité de service.\n\n"
            "L'équipe BABIFIX | contact@babifix.ci"
        ),
    )


# =============================================================================
# TOGGLE DISPONIBILITE — PATCH /api/prestataire/availability/
# =============================================================================
# TOGGLE DISPONIBILITÉ — PATCH /api/prestataire/availability/
# =============================================================================
@csrf_exempt
@require_api_auth(["prestataire", "admin"])
def api_prestataire_availability(request):
    if request.method != "PATCH":
        return JsonResponse({"error": "method_not_allowed"}, status=405)
    try:
        payload = json.loads(request.body)
    except (json.JSONDecodeError, ValueError):
        return JsonResponse({"error": "invalid_json"}, status=400)

    # Flutter envoie 'disponible', l'API documentée utilise 'is_available' — on accepte les deux
    is_available = payload.get("is_available")
    if is_available is None:
        is_available = payload.get("disponible")
    if not isinstance(is_available, bool):
        return JsonResponse(
            {"error": "is_available (or disponible) must be a boolean"}, status=400
        )

    provider = Provider.objects.filter(user_id=request.api_user_id).first()
    if not provider:
        return JsonResponse({"error": "provider_not_found"}, status=404)

    provider.disponible = is_available
    provider.save(update_fields=["disponible"])

    # Diffuser le changement en temps réel vers tous les clients connectés
    try:
        from asgiref.sync import async_to_sync
        from channels.layers import get_channel_layer

        channel_layer = get_channel_layer()
        async_to_sync(channel_layer.group_send)(
            "babifix_client_events",
            {
                "type": "client_notify",
                "event_type": "provider.availability_changed",
                "payload": {
                    "provider_id": provider.id,
                    "disponible": provider.disponible,
                },
            },
        )
    except Exception as exc:
        logger.warning("WS broadcast provider.availability_changed failed: %s", exc)

    return JsonResponse({"ok": True, "is_available": provider.disponible})


# =============================================================================
# BULK ACTIONS ADMIN — POST /api/admin/prestataires/bulk-action/
# =============================================================================
@csrf_exempt
@login_required
def api_admin_bulk_provider_action(request):
    if request.method != "POST":
        return JsonResponse({"error": "method_not_allowed"}, status=405)
    try:
        payload = json.loads(request.body)
    except (json.JSONDecodeError, ValueError):
        return JsonResponse({"error": "invalid_json"}, status=400)

    ids = payload.get("ids", [])
    action = str(payload.get("action", "")).upper()
    motif = str(payload.get("motif", "")).strip()

    if not ids or action not in ("ACCEPT", "REFUSE", "SUSPEND"):
        return JsonResponse(
            {"error": "ids (list) and action (ACCEPT|REFUSE|SUSPEND) required"},
            status=400,
        )

    providers = Provider.objects.filter(pk__in=ids)
    updated = 0

    action_type_map = {
        "ACCEPT": AdminAuditLog.ActionType.BULK_ACCEPT,
        "REFUSE": AdminAuditLog.ActionType.BULK_REFUSE,
        "SUSPEND": AdminAuditLog.ActionType.PROVIDER_SUSPENDED,
    }

    for provider in providers:
        old_statut = provider.statut
        if action == "ACCEPT":
            provider.statut = Provider.Status.VALID
            provider.save(update_fields=["statut"])
            email_provider_accepted(provider)
        elif action == "REFUSE":
            provider.statut = Provider.Status.REFUSED
            provider.refusal_reason = motif or "Dossier incomplet ou non conforme."
            provider.save(update_fields=["statut", "refusal_reason"])
            email_provider_refused(provider, motif)
        elif action == "SUSPEND":
            provider.statut = Provider.Status.SUSPENDED
            provider.save(update_fields=["statut"])

        AdminAuditLog.objects.create(
            admin_user_id=request.api_user_id,
            action=action_type_map.get(action, AdminAuditLog.ActionType.OTHER),
            target_type="Provider",
            target_id=provider.pk,
            target_label=provider.nom,
            details={"motif": motif, "old_statut": old_statut},
        )
        updated += 1

    return JsonResponse({"ok": True, "updated": updated})


# =============================================================================
# JOURNAL AUDIT — GET /api/admin/audit-log/
# =============================================================================
@login_required
@require_GET
def api_admin_audit_log(request):
    page = max(int(request.GET.get("page", 1)), 1)
    per_page = 50
    qs = AdminAuditLog.objects.select_related("admin_user").all()
    total = qs.count()
    logs = list(
        qs[(page - 1) * per_page : page * per_page].values(
            "id",
            "action",
            "target_type",
            "target_id",
            "target_label",
            "details",
            "created_at",
            "admin_user__username",
        )
    )
    return JsonResponse({"total": total, "page": page, "results": logs})


# =============================================================================
# EXPORT CSV — GET /api/admin/export/<kind>/
# =============================================================================
class _EchoWriter:
    def write(self, value):
        return value


@login_required
@require_GET
def api_admin_export_csv(request, kind):
    writer = _EchoWriter()
    if kind == "reservations":
        qs = Reservation.objects.all()
        headers = [
            "id",
            "reference",
            "client",
            "prestataire",
            "montant",
            "statut",
            "cash_flow_status",
            "payment_type",
            "mobile_money_operator",
            "address_label",
        ]

        def row_iter():
            w = csv.writer(writer)
            yield w.writerow(headers)
            for r in qs.iterator():
                yield w.writerow(
                    [
                        r.pk,
                        r.reference,
                        r.client,
                        r.prestataire,
                        r.montant,
                        r.statut,
                        r.cash_flow_status,
                        r.payment_type,
                        r.mobile_money_operator,
                        r.address_label,
                    ]
                )
    elif kind == "prestataires":
        qs = Provider.objects.all()
        headers = [
            "id",
            "nom",
            "specialite",
            "ville",
            "statut",
            "disponible",
            "tarif_horaire",
            "average_rating",
            "rating_count",
            "is_approved",
        ]

        def row_iter():
            w = csv.writer(writer)
            yield w.writerow(headers)
            for p in qs.iterator():
                yield w.writerow(
                    [
                        p.pk,
                        p.nom,
                        p.specialite,
                        p.ville,
                        p.statut,
                        p.disponible,
                        p.tarif_horaire,
                        p.average_rating,
                        p.rating_count,
                        p.is_approved,
                    ]
                )
    elif kind == "paiements":
        qs = Payment.objects.all()
        headers = [
            "id",
            "reference",
            "client",
            "prestataire",
            "montant",
            "etat",
            "type_paiement",
            "valide_par_admin",
            "reference_externe",
        ]

        def row_iter():
            w = csv.writer(writer)
            yield w.writerow(headers)
            for p in qs.iterator():
                yield w.writerow(
                    [
                        p.pk,
                        p.reference,
                        p.client,
                        p.prestataire,
                        p.montant,
                        p.etat,
                        p.type_paiement,
                        p.valide_par_admin,
                        p.reference_externe,
                    ]
                )
    else:
        return JsonResponse({"error": f"kind inconnu : {kind}"}, status=400)

    response = StreamingHttpResponse(
        row_iter(), content_type="text/csv; charset=utf-8-sig"
    )
    response["Content-Disposition"] = f'attachment; filename="babifix_{kind}.csv"'
    return response


# Exemple d'appel pour notifier la validation KYC (à intégrer dans la vue de validation admin)
def email_provider_kyc_approved(provider: Provider) -> None:
    if not (provider.user and provider.user.email):
        return

    html_content = render_to_string('emails/kyc_approved.html', {
        "provider_name": provider.nom,
        "app_url": "https://babifix.ci/app",
    })

    try:
        send_babifix_email_html(
            to_email=provider.user.email,
            subject="Profil Vérifié - Vous pouvez recevoir des clients !",
            html_content=html_content,
        )
    except Exception as exc:
        logger.warning("Email KYC non envoyé (%s) : %s", provider.user.email, exc)

# =============================================================================
# CRUD DISPONIBILITÉS — GET/POST /api/prestataire/availability/
# =============================================================================
@csrf_exempt
@require_api_auth(["prestataire", "admin"])
def api_prestataire_availability_crud(request, id=None):
    """CRUD des créneaux de disponibilité."""
    try:
        provider = Provider.objects.get(user_id=request.api_user_id)
    except Provider.DoesNotExist:
        return JsonResponse({"error": "provider_not_found"}, status=404)

    if request.method == "GET":
        slots = PrestataireAvailabilitySlot.objects.filter(
            provider=provider, actif=True
        )
        data = [
            {
                "id": s.id,
                "jour_semaine": s.jour_semaine,
                "heure_debut": s.heure_debut.isoformat(),
                "heure_fin": s.heure_fin.isoformat(),
            }
            for s in slots
        ]
        return JsonResponse({"slots": data})

    elif request.method == "POST":
        try:
            payload = json.loads(request.body)
        except (json.JSONDecodeError, ValueError):
            return JsonResponse({"error": "invalid_json"}, status=400)

        jour = payload.get("jour_semaine")
        if jour is None:
            jour = payload.get("weekday")
        debut = payload.get("heure_debut") or payload.get("start_time")
        fin = payload.get("heure_fin") or payload.get("end_time")

        # NB : jour peut valoir 0 (lundi) — surtout pas de test « falsy »
        # (0 est falsy en Python), sinon le lundi est rejeté à tort.
        if jour is None or not debut or not fin:
            return JsonResponse(
                {"error": "jour_semaine, heure_debut, heure_fin required"}, status=400
            )
        try:
            jour = int(jour)
        except (TypeError, ValueError):
            return JsonResponse({"error": "jour_semaine invalide"}, status=400)
        if jour < 0 or jour > 6:
            return JsonResponse({"error": "jour_semaine hors plage (0-6)"}, status=400)

        from datetime import time

        try:
            debut_t = time.fromisoformat(debut)
            fin_t = time.fromisoformat(fin)
        except ValueError:
            return JsonResponse({"error": "invalid_time_format"}, status=400)

        # get_or_create sur la clé unique (provider, jour_semaine, heure_debut)
        # pour éviter le crash IntegrityError si le créneau existe déjà : on le
        # réactive simplement et on met à jour l'heure de fin.
        slot, created = PrestataireAvailabilitySlot.objects.get_or_create(
            provider=provider,
            jour_semaine=int(jour),
            heure_debut=debut_t,
            defaults={"heure_fin": fin_t, "actif": True},
        )
        if not created:
            slot.heure_fin = fin_t
            slot.actif = True
            slot.save(update_fields=["heure_fin", "actif"])
        return JsonResponse(
            {"id": slot.id, "ok": True, "created": created}, status=201
        )

    elif request.method == "DELETE":
        slot_id = id or request.GET.get("id")
        if slot_id:
            PrestataireAvailabilitySlot.objects.filter(
                pk=int(slot_id), provider=provider
            ).delete()
            return JsonResponse({"ok": True})
        return JsonResponse({"error": "id required"}, status=400)

    return JsonResponse({"error": "method_not_allowed"}, status=405)


# =============================================================================
# CRUD INDISPONIBILITÉS — GET/POST /api/prestataire/unavailability/
# =============================================================================
@csrf_exempt
@require_api_auth(["prestataire", "admin"])
def api_prestataire_unavailability_crud(request, id=None):
    """CRUD des périodes d'indisponibilité."""
    try:
        provider = Provider.objects.get(user_id=request.api_user_id)
    except Provider.DoesNotExist:
        return JsonResponse({"error": "provider_not_found"}, status=404)

    if request.method == "GET":
        periods = PrestataireUnavailability.objects.filter(provider=provider)
        data = [
            {
                "id": p.id,
                "date_debut": p.date_debut.isoformat(),
                "date_fin": p.date_fin.isoformat(),
                "motif": p.motif,
            }
            for p in periods
        ]
        return JsonResponse({"periods": data})

    elif request.method == "POST":
        try:
            payload = json.loads(request.body)
        except (json.JSONDecodeError, ValueError):
            return JsonResponse({"error": "invalid_json"}, status=400)

        # Accept both French and English key names
        debut = payload.get("date_debut") or payload.get("date_from")
        fin = payload.get("date_fin") or payload.get("date_to")
        motif = payload.get("motif") or payload.get("reason", "")

        if not all([debut, fin]):
            return JsonResponse({"error": "date_debut/date_from, date_fin/date_to required"}, status=400)

        from datetime import date

        try:
            debut_d = date.fromisoformat(debut)
            fin_d = date.fromisoformat(fin)
        except ValueError:
            return JsonResponse({"error": "invalid_date_format"}, status=400)

        period = PrestataireUnavailability.objects.create(
            provider=provider,
            date_debut=debut_d,
            date_fin=fin_d,
            motif=motif[:200],
        )
        return JsonResponse({"id": period.id, "ok": True}, status=201)

    elif request.method == "DELETE":
        period_id = id or request.GET.get("id")
        if period_id:
            PrestataireUnavailability.objects.filter(
                pk=int(period_id), provider=provider
            ).delete()
            return JsonResponse({"ok": True})
        return JsonResponse({"error": "id required"}, status=400)

    return JsonResponse({"error": "method_not_allowed"}, status=405)


# =============================================================================
# STATISTIQUES PRESTATAIRE — GET /api/prestataire/stats/
# =============================================================================
@require_api_auth(["prestataire", "admin"])
@require_GET
def api_prestataire_stats(request):
    """Statistiques détaillées du prestataire connecté."""
    try:
        provider = Provider.objects.get(user_id=request.api_user_id)
    except Provider.DoesNotExist:
        return JsonResponse({"error": "provider_not_found"}, status=404)

    reservations = Reservation.objects.filter(assigned_provider=provider)

    total = reservations.count()
    terminees = reservations.filter(statut=Reservation.Status.DONE).count()
    en_cours = reservations.filter(
        statut__in=[Reservation.Status.CONFIRMED, Reservation.Status.IN_PROGRESS]
    ).count()
    en_attente = reservations.filter(statut=Reservation.Status.PENDING).count()
    annulees = reservations.filter(statut=Reservation.Status.CANCELLED).count()

    taux_completion = round((terminees / total * 100), 1) if total > 0 else 0

    # Revenus réels (somme des paiements complets)
    revenus = (
        Payment.objects.filter(
            reservation__assigned_provider=provider,
            etat=Payment.State.COMPLETE,
        ).aggregate(total=Sum("montant"))["total"]
        or 0
    )

    # Essayer de convertir en nombre si c'est une chaîne
    try:
        revenus = float(revenus)
    except (TypeError, ValueError):
        revenus = 0

    return JsonResponse(
        {
            "total_reservations": total,
            "terminees": terminees,
            "en_cours": en_cours,
            "en_attente": en_attente,
            "annulees": annulees,
            "taux_completion": taux_completion,
            "note_moyenne": provider.average_rating or 0,
            "nb_avis": provider.rating_count or 0,
            "revenus_total": revenus,
        }
    )


# =============================================================================
# FAVORIS PRESTATAIRES — GET/POST/DELETE /api/client/favorites/
# =============================================================================
@csrf_exempt
@require_api_auth(["client", "admin"])
def api_client_favorites(request):
    """Gérer les favoris du client."""
    from django.contrib.auth.models import User

    client_user_id = request.api_user_id
    client_user = User.objects.filter(id=client_user_id).first()
    if not client_user:
        return JsonResponse({"error": "auth_required"}, status=401)

    if request.method == "GET":
        from .models import ClientFavorite

        favorites = ClientFavorite.objects.filter(client=client_user).select_related(
            "provider"
        )
        data = [
            {
                "id": f.provider.id,
                "nom": f.provider.nom,
                "specialite": f.provider.specialite,
                "ville": f.provider.ville,
                "average_rating": float(f.provider.average_rating or 0),
                "tarif_horaire": float(f.provider.tarif_horaire or 0),
            }
            for f in favorites
        ]
        return JsonResponse({"favorites": data})

    elif request.method == "POST":
        try:
            payload = json.loads(request.body)
        except json.JSONDecodeError:
            return JsonResponse({"error": "invalid_json"}, status=400)

        provider_id = payload.get("provider_id")
        if not provider_id:
            return JsonResponse({"error": "provider_id_required"}, status=400)

        from .models import ClientFavorite, Provider

        try:
            provider = Provider.objects.get(
                id=provider_id, statut=Provider.Status.VALID
            )
        except Provider.DoesNotExist:
            return JsonResponse({"error": "provider_not_found"}, status=404)

        favorite, created = ClientFavorite.objects.get_or_create(
            client=client_user,
            provider=provider,
        )
        return JsonResponse({"ok": True, "added": created}, status=201)

    elif request.method == "DELETE":
        provider_id = request.GET.get("provider_id")
        if not provider_id:
            return JsonResponse({"error": "provider_id_required"}, status=400)

        from .models import ClientFavorite

        deleted = ClientFavorite.objects.filter(
            client=client_user,
            provider_id=int(provider_id),
        ).delete()
        return JsonResponse({"ok": True, "deleted": deleted[0] > 0})

    return JsonResponse({"error": "method_not_allowed"}, status=405)


# =============================================================================
# HISTORIQUE PAIEMENTS CLIENT — GET /api/client/payments/
# =============================================================================
@require_GET
@require_api_auth(["client", "admin"])
def api_client_payments(request):
    """Historique des paiements du client."""
    from django.contrib.auth.models import User

    client_user_id = request.api_user_id
    client_user = User.objects.filter(id=client_user_id).first()
    if not client_user:
        return JsonResponse({"error": "auth_required"}, status=401)

    # Payment.client est un champ string (pas un FK) — on filtre par
    # username/email du client connecté.
    payments = Payment.objects.filter(
        client__in=[client_user.username, client_user.email]
    ).order_by("-id")

    data = [
        {
            "id": p.id,
            "reference": p.reference,
            "montant": float(p.montant) if p.montant is not None else 0.0,
            "etat": p.etat,
            "type_paiement": p.type_paiement or "",
            "operator": getattr(p, "mobile_money_operator", "") or "",
            "reservation_reference": p.reservation.reference if p.reservation else None,
            "created_at": p.created_at.isoformat() if hasattr(p, "created_at") and p.created_at else None,
        }
        for p in payments
    ]
    return JsonResponse({"payments": data})


# =============================================================================
# LITIGES PRESTATAIRE — GET /api/prestataire/disputes/
# =============================================================================
@require_GET
@require_api_auth(["prestataire", "admin"])
def api_prestataire_disputes(request):
    """Litiges pour le prestataire connecté.

    Le modèle Dispute stocke `prestataire` en CharField (nom), donc on
    passe par la FK `reservation.assigned_provider` qui est fiable.
    """
    provider = Provider.objects.filter(user_id=request.api_user_id).first()
    if not provider:
        return JsonResponse({"error": "provider_not_found"}, status=404)

    disputes = (
        Dispute.objects
        .filter(reservation__assigned_provider=provider)
        .select_related("reservation")
        .order_by("-created_at")
    )

    def _serialize(d):
        res = d.reservation
        return {
            "id": d.id,
            "reference": d.reference,
            "motif": d.motif,
            "categorie": d.categorie,
            "categorie_label": d.get_categorie_display(),
            "priorite": d.priorite,
            "decision": d.decision,
            "decision_note": d.decision_note,
            "is_open": d.decision == Dispute.Decision.OPEN,
            "has_presta_response": bool(d.prestataire_response),
            "prestataire_response": d.prestataire_response,
            "photos_client_count": len(d.photos_client or []),
            "photos_prestataire_count": len(d.photos_prestataire or []),
            "client_name": d.client,
            "reservation_reference": res.reference if res else None,
            "reservation_title": (res.title if res else "") or "",
            "montant_concerne": (
                float(res.montant_verse or 0) if res else 0.0
            ),
            "created_at": d.created_at.isoformat() if d.created_at else None,
            "decided_at": d.decided_at.isoformat() if d.decided_at else None,
        }

    return JsonResponse({
        "disputes": [_serialize(d) for d in disputes],
        "count_open": sum(1 for d in disputes if d.decision == Dispute.Decision.OPEN),
    })


# =============================================================================
# LITIGE — RÉPONSE PRESTATAIRE — POST /api/prestataire/disputes/<ref>/respond/
# Permet au prestataire d'apporter sa version + ses preuves photos.
# =============================================================================
@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["prestataire", "admin"])
def api_prestataire_respond_dispute(request, dispute_ref):
    import json as _json
    provider = Provider.objects.filter(user_id=request.api_user_id).first()
    if not provider:
        return JsonResponse({"error": "provider_not_found"}, status=404)
    d = (
        Dispute.objects
        .filter(reference=dispute_ref, reservation__assigned_provider=provider)
        .first()
    )
    if not d:
        return JsonResponse({"error": "not_found"}, status=404)
    if d.decision != Dispute.Decision.OPEN:
        return JsonResponse(
            {"error": "already_resolved", "decision": d.decision}, status=409
        )

    try:
        body = _json.loads(request.body.decode("utf-8") or "{}")
    except _json.JSONDecodeError:
        body = {}

    response_text = str(body.get("response", "")).strip()[:2000]
    photos_raw = body.get("photos", []) or []
    if not isinstance(photos_raw, list):
        photos_raw = []
    photos = [
        str(p)[:600000]
        for p in photos_raw[:5]
        if isinstance(p, str) and p.startswith("data:image/")
    ]

    if not response_text and not photos:
        return JsonResponse({"error": "response_or_photos_required"}, status=400)

    from django.utils import timezone as _tz
    d.prestataire_response = response_text
    d.prestataire_response_at = _tz.now()
    if photos:
        d.photos_prestataire = photos
    d.save(update_fields=[
        "prestataire_response",
        "prestataire_response_at",
        "photos_prestataire",
    ])

    # Notif admin + message système dans le chat.
    try:
        from .services.conversation_service import post_system_event
        if d.reservation:
            post_system_event(
                d.reservation,
                event_type="dispute.presta_responded",
                body=(
                    f"Le prestataire a apporté sa version au litige "
                    f"{d.reference}."
                ),
                extra={
                    "dispute_ref": d.reference,
                    "has_photos": bool(photos),
                },
            )
    except Exception:
        pass

    try:
        from .push_dispatch import _schedule
        admin_ids = list(
            User.objects.filter(is_staff=True, is_active=True)
            .values_list("id", flat=True)
        )
        if admin_ids:
            _schedule(
                admin_ids,
                "BABIFIX — Réponse prestataire au litige",
                f"{provider.nom} a répondu au litige {d.reference}.",
                {
                    "type": "dispute.presta_responded",
                    "dispute_ref": d.reference,
                    "route": "/admin/disputes",
                },
            )
    except Exception:
        pass

    return JsonResponse({
        "ok": True,
        "dispute_reference": d.reference,
        "responded_at": d.prestataire_response_at.isoformat(),
    })


# =============================================================================
# LITIGES CLIENT — GET /api/client/disputes/
# =============================================================================
@require_GET
@require_api_auth(["client", "admin"])
def api_client_disputes(request):
    """Liste des litiges du client connecté.

    Filtrage via `reservation.client_user_id` pour cohérence avec l'auth.
    """
    uid = int(request.api_user_id)
    disputes = (
        Dispute.objects
        .filter(reservation__client_user_id=uid)
        .select_related("reservation")
        .order_by("-created_at")
    )

    def _serialize(d):
        res = d.reservation
        return {
            "id": d.id,
            "reference": d.reference,
            "motif": d.motif,
            "categorie": d.categorie,
            "categorie_label": d.get_categorie_display(),
            "priorite": d.priorite,
            "decision": d.decision,
            "decision_note": d.decision_note,
            "is_open": d.decision == Dispute.Decision.OPEN,
            "has_presta_response": bool(d.prestataire_response),
            "prestataire_response": d.prestataire_response,
            "photos_client_count": len(d.photos_client or []),
            "photos_prestataire_count": len(d.photos_prestataire or []),
            "prestataire_name": d.prestataire,
            "reservation_reference": res.reference if res else None,
            "reservation_title": (res.title if res else "") or "",
            "montant_concerne": (
                float(res.montant_verse or 0) if res else 0.0
            ),
            "created_at": d.created_at.isoformat() if d.created_at else None,
            "decided_at": d.decided_at.isoformat() if d.decided_at else None,
        }

    return JsonResponse({
        "disputes": [_serialize(d) for d in disputes],
        "count_open": sum(1 for d in disputes if d.decision == Dispute.Decision.OPEN),
    })


# =============================================================================
# FONCTIONS EMAIL MANQUANTES (TODO 2 — PARTIE 1)
# =============================================================================


def _render_email_template(template_name: str, context: dict) -> str:
    """Rend un template HTML d'email avec le contexte fourni."""
    from django.template.loader import render_to_string

    try:
        return render_to_string(f"emails/{template_name}", context)
    except Exception:
        return ""


def send_booking_done_email(reservation: "Reservation") -> None:
    """Email au client après mission terminée — invite à noter le prestataire."""
    client_user = getattr(reservation, "client_user", None)
    if not (client_user and client_user.email):
        return

    client_name = client_user.username
    if hasattr(client_user, "client_profile"):
        try:
            client_name = client_user.client_profile.nom
        except Exception:
            pass

    subject = f"Mission terminée : {reservation.title or reservation.reference}"
    date_str = ""
    if hasattr(reservation, "date_mission") and reservation.date_mission:
        date_str = reservation.date_mission.strftime("%d/%m/%Y")

    html_content = _render_email_template(
        "booking_done.html",
        {
            "client_name": client_name,
            "reservation_title": reservation.title or reservation.reference,
            "prestataire_name": reservation.prestataire,
            "montant": reservation.montant,
            "date_mission": date_str,
        },
    )

    send_babifix_email_html(
        to_email=client_user.email,
        subject=subject,
        html_content=html_content,
    )


def send_dispute_opened_email(
    reservation: "Reservation",
    description: str,
    opened_by: str,
) -> None:
    """Email à l'admin quand un litige est ouvert."""
    from django.conf import settings

    subject = f"Litige ouvert : Réservation {reservation.reference}"
    admin_url = f"https://{getattr(settings, 'ALLOWED_HOSTS', ['babifix.ci'])[0]}/admin/adminpanel/dispute/"
    html_content = _render_email_template(
        "dispute_opened.html",
        {
            "reservation_reference": reservation.reference,
            "client_name": reservation.client,
            "prestataire_name": reservation.prestataire,
            "description": description,
            "opened_by": opened_by,
            "montant": reservation.montant,
            "admin_url": admin_url,
        },
    )

    for admin_email in _get_admin_emails():
        send_babifix_email_html(
            to_email=admin_email,
            subject=subject,
            html_content=html_content,
        )


def send_newsletter_confirmation_email(email: str, confirm_url: str) -> None:
    """Email de confirmation double opt-in newsletter."""
    send_babifix_email_html(
        to_email=email,
        subject="Confirmez votre inscription à la newsletter BABIFIX",
        html_content=_render_email_template(
            "newsletter_confirmation.html",
            {
                "confirm_url": confirm_url,
            },
        ),
    )


def send_weekly_digest_email(prestataire: "Provider", stats_dict: dict) -> None:
    """Récapitulatif hebdomadaire envoyé au prestataire."""
    user_email = prestataire.user.email if prestataire.user else None
    if not user_email:
        return

    send_babifix_email_html(
        to_email=user_email,
        subject="Votre récapitulatif hebdomadaire BABIFIX",
        html_content=_render_email_template(
            "weekly_digest_prestataire.html",
            {
                "prestataire_name": prestataire.nom,
                "missions_completed": stats_dict.get("missions_completed", 0),
                "revenue": stats_dict.get("revenue", 0),
                "pending_bookings": stats_dict.get("pending_bookings", 0),
                "average_rating": stats_dict.get("average_rating", 0),
                "rating_count": stats_dict.get("rating_count", 0),
            },
        ),
    )


def send_babifix_email(to_email: str, subject: str, body: str) -> None:
    """Envoi d'un e-mail BABIFIX en texte simple.

    Wrapper autour de `send_babifix_email_html` : convertit le corps texte en
    HTML minimal (paragraphes) pour réutiliser le même transport SMTP threadé.
    (Était référencé par les e-mails transactionnels prestataire/réservation
    sans jamais être défini → les envois échouaient silencieusement.)
    """
    import html as _html

    safe = _html.escape(body or "")
    html_content = (
        '<div style="font-family:Arial,sans-serif;font-size:14px;color:#0B1B34;'
        'line-height:1.55;white-space:pre-wrap;">' + safe + "</div>"
    )
    send_babifix_email_html(to_email=to_email, subject=subject, html_content=html_content)


def send_babifix_email_html(
    to_email: str,
    subject: str,
    html_content: str,
    attachments: list | None = None,
) -> None:
    """Envoi email HTML transactionnel BABIFIX avec fallback plain text.

    attachments: liste de tuples (filename, content, mimetype) — ex: PDF reçu.
    """
    import threading

    from django.conf import settings
    from django.core.mail import EmailMultiAlternatives

    if not html_content:
        return

    import re

    plain_text = re.sub(r"<[^>]+>", "", html_content)
    plain_text = re.sub(r"\n+", "\n", plain_text).strip()
    from_email = getattr(settings, "DEFAULT_FROM_EMAIL", "BABIFIX <contact@babifix.ci>")
    _attachments = list(attachments or [])

    def _deliver() -> None:
        # Envoi SMTP exécuté dans un thread : ne bloque JAMAIS la requête HTTP
        # (sinon la latence Gmail dépasse le délai de l'app → CancelledError).
        try:
            msg = EmailMultiAlternatives(
                subject=subject,
                body=plain_text,
                from_email=from_email,
                to=[to_email],
            )
            msg.attach_alternative(html_content, "text/html")
            for filename, content, mimetype in _attachments:
                msg.attach(filename, content, mimetype)
            msg.send(fail_silently=False)
            logger.info("Email envoye a %s: %s", to_email, subject)
        except Exception as exc:  # noqa: BLE001
            logger.warning("Email non envoyé (%s) : %s", to_email, exc)

    threading.Thread(target=_deliver, daemon=True).start()


def _get_admin_emails() -> list:
    """Retourne la liste des emails des admins."""
    from django.contrib.auth.models import User

    return list(
        User.objects.filter(is_staff=True, is_active=True)
        .exclude(email="")
        .values_list("email", flat=True)
    )


# =============================================================================
# Health Check — Endpoint de monitoring pour Docker/K8s
# =============================================================================
def api_health_check(request):
    """
    Endpoint de vérification de santé du système.
    Vérifie : DB, Redis, et retourne le status.
    UTILISATION : GET /api/health/
    """
    from django.db import connection
    from django.core.cache import cache
    import redis

    status = {"status": "ok", "checks": {}}

    # Check DB
    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1")
        status["checks"]["database"] = "ok"
    except Exception as e:
        status["checks"] = {"database": str(e)}
        status["status"] = "error"

    # Check Redis
    try:
        cache.set("health_check_key", "ok", 10)
        if cache.get("health_check_key") == "ok":
            status["checks"]["redis"] = "ok"
        else:
            raise Exception("Redis value mismatch")
    except Exception as e:
        status["checks"]["redis"] = str(e)
        status["status"] = "error"

    http_status = 200 if status["status"] == "ok" else 503
    return JsonResponse(status, status=http_status)


# ---------------------------------------------------------------------------
# Reçus / Factures PDF
# ---------------------------------------------------------------------------

@require_api_auth(["client", "admin"])
@require_GET
def api_client_invoice_pdf(request, reference):
    """GET /api/client/invoices/<reference>/pdf/ — Télécharger le reçu PDF (disponible seulement après paiement complet)."""
    user_id = request.api_user_id

    try:
        payment = (
            Payment.objects.select_related("reservation__client_user")
            .filter(
                reservation__reference=reference,
                reservation__client_user_id=user_id,
                etat=Payment.State.COMPLETE,
            )
            .first()
        )
    except Exception:
        payment = None

    if not payment:
        return JsonResponse({"error": "Reçu introuvable ou accès refusé"}, status=404)

    res = payment.reservation
    # Le reçu n'est disponible qu'après paiement intégral
    if res.payment_type == "MOBILE_MONEY" and not res.solde_valide:
        return JsonResponse(
            {"error": "Le solde restant doit d'abord être payé avant d'obtenir le reçu."},
            status=400,
        )
    if res.payment_type == "ESPECES" and not res.solde_valide:
        # Pour espèces, le reçu est disponible après confirmation du cash (solde_valide = True)
        return JsonResponse(
            {"error": "Le paiement en espèces doit être confirmé par le prestataire avant d'obtenir le reçu."},
            status=400,
        )

    try:
        from adminpanel.services.invoice_service import InvoiceService

        pdf_bytes = InvoiceService.generate_pdf(payment)
        invoice_number = InvoiceService.generate_invoice_number(payment)
    except Exception as exc:
        logger.error("Erreur génération PDF reçu ref=%s: %s", reference, exc)
        return JsonResponse({"error": "Erreur génération PDF"}, status=500)

    response = HttpResponse(pdf_bytes, content_type="application/pdf")
    response["Content-Disposition"] = f'attachment; filename="recu_{invoice_number}.pdf"'
    return response


@require_api_auth(["prestataire", "admin"])
@require_GET
def api_prestataire_invoice_pdf(request, reference):
    """GET /api/prestataire/invoices/<reference>/pdf/ — Télécharger le reçu PDF."""
    user_id = request.api_user_id

    try:
        payment = (
            Payment.objects.select_related("reservation__prestataire_user")
            .filter(
                reservation__reference=reference,
                reservation__prestataire_user_id=user_id,
                etat=Payment.State.COMPLETE,
            )
            .first()
        )
    except Exception:
        payment = None

    if not payment:
        return JsonResponse({"error": "Reçu introuvable ou accès refusé"}, status=404)

    try:
        from adminpanel.services.invoice_service import InvoiceService

        pdf_bytes = InvoiceService.generate_pdf(payment)
        invoice_number = InvoiceService.generate_invoice_number(payment)
    except Exception as exc:
        logger.error("Erreur génération PDF reçu prestataire ref=%s: %s", reference, exc)
        return JsonResponse({"error": "Erreur génération PDF"}, status=500)

    response = HttpResponse(pdf_bytes, content_type="application/pdf")
    response["Content-Disposition"] = f'attachment; filename="recu_{invoice_number}.pdf"'
    return response


@require_api_auth(["client", "admin"])
@require_GET
def api_client_invoices_list(request):
    """GET /api/client/invoices/ — Liste des reçus du client."""
    from django.contrib.auth.models import User
    user_id = request.api_user_id

    user = User.objects.filter(pk=user_id).first()
    if not user:
        return JsonResponse({"error": "user_not_found"}, status=404)

    try:
        from adminpanel.services.invoice_service import InvoiceService

        invoices = InvoiceService.get_client_invoices(user)
        return JsonResponse({"invoices": invoices}, status=200)
    except Exception as exc:
        logger.error("Erreur liste reçus client: %s", exc)
        return JsonResponse({"invoices": []}, status=200)


# =============================================================================
# WALLET PRESTATAIRE
# =============================================================================

@csrf_exempt
@require_api_auth(["prestataire", "admin"])
@require_GET
def api_prestataire_wallet(request):
    """GET /api/prestataire/wallet/ — Solde + historique transactions."""
    user_id = request.api_user_id

    provider = Provider.objects.filter(user_id=user_id).first()
    if not provider:
        return JsonResponse({"error": "Profil prestataire introuvable"}, status=404)

    from adminpanel.services.wallet_service import WalletService
    summary = WalletService.get_wallet_summary(provider.pk)
    return JsonResponse(summary, status=200)


@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["prestataire", "admin"])
def api_prestataire_wallet_withdraw(request):
    """
    POST /api/prestataire/wallet/withdraw/
    Body JSON : {amount_fcfa, phone, operator}
    """
    # Anti-abus : limiter les demandes de retrait (action financière).
    from .throttle import check_rate_limit, rate_limited_response
    if check_rate_limit(request, "wallet_withdraw", max_requests=5, window=60):
        return rate_limited_response()

    user_id = request.api_user_id

    provider = Provider.objects.filter(user_id=user_id).first()
    if not provider:
        return JsonResponse({"error": "Profil prestataire introuvable"}, status=404)

    try:
        body = json.loads(request.body)
    except (json.JSONDecodeError, TypeError):
        return JsonResponse({"error": "JSON invalide"}, status=400)

    try:
        from decimal import Decimal
        amount = Decimal(str(body.get("amount_fcfa", 0)))
    except Exception:
        return JsonResponse({"error": "amount_fcfa invalide"}, status=400)

    phone = (body.get("phone") or "").strip()
    operator = (body.get("operator") or "").strip().lower()

    if not phone:
        return JsonResponse({"error": "Numéro Mobile Money requis"}, status=400)

    from adminpanel.services.wallet_service import WalletService
    result = WalletService.request_withdrawal(provider.pk, amount, phone, operator)

    if "error" in result:
        return JsonResponse(result, status=400)
    return JsonResponse(result, status=200)


@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["prestataire", "admin"])
def api_prestataire_wallet_update_info(request):
    """
    POST /api/prestataire/wallet/info/
    Body JSON : {phone, operator}
    Met à jour les infos Mobile Money du prestataire.
    """
    user_id = request.api_user_id

    provider = Provider.objects.filter(user_id=user_id).first()
    if not provider:
        return JsonResponse({"error": "Profil prestataire introuvable"}, status=404)

    try:
        body = json.loads(request.body)
    except (json.JSONDecodeError, TypeError):
        return JsonResponse({"error": "JSON invalide"}, status=400)

    def _norm_ci_phone(raw: str) -> str:
        """Numéro ivoirien : 10 chiffres (07/05/01…), indicatif +225 retiré."""
        digits = "".join(ch for ch in (raw or "") if ch.isdigit())
        if digits.startswith("225") and len(digits) == 13:
            digits = digits[3:]
        return digits

    phone = _norm_ci_phone(body.get("phone") or "")
    operator = (body.get("operator") or "").strip().lower()
    phone_2 = _norm_ci_phone(body.get("phone_2") or "")
    operator_2 = (body.get("operator_2") or "").strip().lower()

    valid_operators = {"mtn", "orange", "wave", "moov", ""}
    if operator not in valid_operators or operator_2 not in valid_operators:
        return JsonResponse({"error": "Opérateur invalide"}, status=400)

    # Numéros ivoiriens : exactement 10 chiffres.
    if phone and len(phone) != 10:
        return JsonResponse(
            {"error": "Le numéro principal doit comporter 10 chiffres."}, status=400
        )
    if phone_2 and len(phone_2) != 10:
        return JsonResponse(
            {"error": "Le numéro secondaire doit comporter 10 chiffres."}, status=400
        )

    # Les deux numéros ne peuvent pas être identiques (sinon retrait ambigu).
    if phone and phone_2 and phone == phone_2:
        return JsonResponse(
            {"error": "Les deux numéros doivent être différents."}, status=400
        )

    # Champs envoyés explicitement => on les met à jour (y compris vidage du
    # 2e numéro si l'utilisateur l'efface). On ne touche qu'aux clés présentes.
    update_fields = []
    if "phone" in body:
        provider.wallet_phone = phone
        update_fields.append("wallet_phone")
    if "operator" in body:
        provider.wallet_operator = operator
        update_fields.append("wallet_operator")
    if "phone_2" in body:
        provider.wallet_phone_2 = phone_2
        update_fields.append("wallet_phone_2")
    if "operator_2" in body:
        provider.wallet_operator_2 = operator_2
        update_fields.append("wallet_operator_2")

    if update_fields:
        provider.save(update_fields=update_fields)

    return JsonResponse({
        "status": "ok",
        "wallet_phone": provider.wallet_phone,
        "wallet_operator": provider.wallet_operator,
        "wallet_phone_2": provider.wallet_phone_2,
        "wallet_operator_2": provider.wallet_operator_2,
    }, status=200)


# ─── Programme de fidélité client ───────────────────────────────────────────
@require_api_auth(["client"])
@require_GET
def api_client_fidelite(request):
    """
    GET /api/client/fidelite/
    Retourne le niveau fidélité, les garanties, le code parrainage et les crédits.
    """
    from django.contrib.auth.models import User
    from .models import UserProfile
    from .services.referral_service import ReferralService

    user_id = request.api_user_id

    # Compter les réservations terminées
    nb_reservations = Reservation.objects.filter(
        client_user_id=user_id,
        statut="Terminee",
    ).count()

    # Niveau fidélité basé sur le nombre de missions
    if nb_reservations >= 20:
        niveau, couleur, reduction, prochainNiveau = "Platine", "#A855F7", 15, None
        prochainSeuil = None
    elif nb_reservations >= 10:
        niveau, couleur, reduction = "Or", "#F59E0B", 10
        prochainNiveau, prochainSeuil = "Platine", 20
    elif nb_reservations >= 5:
        niveau, couleur, reduction = "Argent", "#64748B", 5
        prochainNiveau, prochainSeuil = "Or", 10
    else:
        niveau, couleur, reduction = "Bronze", "#CD7F32", 0
        prochainNiveau, prochainSeuil = "Argent", 5

    # Profil et code parrainage
    try:
        user = User.objects.get(pk=user_id)
        profile, _ = UserProfile.objects.get_or_create(user=user)
        if not profile.referral_code:
            result = ReferralService.create_referral_code(user)
            referral_code = result.referral_code or ""
        else:
            referral_code = profile.referral_code
        referral_credits = float(profile.referral_credits_earned or 0)
        filleuls_count = UserProfile.objects.filter(recommended_by=user).count()
        bonus_applique = profile.referral_bonus_applied
    except Exception:
        referral_code, referral_credits, filleuls_count, bonus_applique = "", 0, 0, False

    # Points fidélité + crédit (convertible / disponible), via FideliteService.
    try:
        from django.contrib.auth.models import User as _U
        from .services.fidelite_service import FideliteService
        _pts = FideliteService.summary(_U.objects.get(pk=user_id))
    except Exception:
        _pts = {}

    return JsonResponse({
        "niveau": niveau,
        "couleur": couleur,
        "reduction_pct": reduction,
        "nb_reservations": nb_reservations,
        "prochain_niveau": prochainNiveau,
        "prochain_seuil": prochainSeuil,
        "referral_code": referral_code,
        "referral_credits": referral_credits,
        "filleuls_count": filleuls_count,
        "bonus_premiere_reservation_applique": bonus_applique,
        # Points fidélité + crédit (100 pts = 1 000 F ; utilisable en réduction).
        "points": _pts.get("points", 0),
        "valeur_point_fcfa": _pts.get("valeur_point_fcfa", 10),
        "seuil_conversion": _pts.get("seuil_conversion", 100),
        "points_convertibles": _pts.get("convertible", False),
        "credit_disponible_fcfa": _pts.get("credit_disponible_fcfa", 0.0),
        "equivalent_fcfa": _pts.get("equivalent_fcfa", 0),
        "garanties": [
            {
                "icon": "verified_rounded",
                "titre": "Prestataires vérifiés",
                "description": "Chaque prestataire est contrôlé : CNI, selfie, vidéo d'introduction et recommandations.",
            },
            {
                "icon": "shield_rounded",
                "titre": "Satisfaction garantie",
                "description": "Si vous n'êtes pas satisfait, BABIFIX prend en charge le litige et peut rembourser.",
            },
            {
                "icon": "lock_rounded",
                "titre": "Paiement sécurisé",
                "description": "Vos paiements sont protégés. L'argent n'est libéré qu'après confirmation de la prestation.",
            },
            {
                "icon": "support_agent_rounded",
                "titre": "Support 7j/7",
                "description": "Notre équipe est disponible tous les jours pour répondre à vos questions.",
            },
            {
                "icon": "star_rounded",
                "titre": "Avis certifiés",
                "description": "Seuls les clients ayant effectué une réservation peuvent laisser un avis.",
            },
        ],
    })


# ─── Contrat / Charte prestataire ────────────────────────────────────────────
# Version du contrat. À INCRÉMENTER dès qu'une clause change matériellement :
# `contrat_signe` compare cette valeur à celle signée par le prestataire, donc
# un changement de version force une NOUVELLE signature.
#
# v2.0 — ajout des clauses qui manquaient alors que le code les appliquait déjà :
#        visite/transport, séquestre, interdiction de contourner la plateforme,
#        score de fiabilité et SUSPENSION AUTOMATIQUE. On ne peut pas suspendre
#        un compte sur une règle absente du contrat signé.
CONTRAT_VERSION = "2.0"


def _platform_config():
    """Config plateforme (seuils réels). Best-effort : None si indisponible."""
    try:
        from .models import PlatformConfig
        return PlatformConfig.get_solo()
    except Exception:
        return None


def _commission_effective_pct(provider) -> int:
    """Taux RÉELLEMENT prélevé, en % entier.

    Délègue à la même source que le devis (`_get_effective_commission_rate`) pour
    que le contrat affiche EXACTEMENT ce qui est facturé.
    """
    try:
        from decimal import Decimal
        from .services.wallet_service import _get_effective_commission_rate
        frac = _get_effective_commission_rate(provider)
        return int((Decimal(str(frac)) * Decimal("100")).quantize(Decimal("1")))
    except Exception:
        return 18


def _commission_base_pct(provider) -> int:
    """Taux de base (avant réduction d'abonnement), pour l'affichage pédagogique."""
    try:
        from .services.referral_service import CATEGORY_COMMISSIONS
        if provider.category:
            slug = (provider.category.icone_slug or provider.category.nom or "").lower()
            return int(CATEGORY_COMMISSIONS.get(slug, CATEGORY_COMMISSIONS["default"]))
        return int(CATEGORY_COMMISSIONS["default"])
    except Exception:
        return 18


@require_api_auth(["prestataire"])
@require_GET
def api_prestataire_contrat(request):
    """
    GET /api/prestataire/contrat/
    Retourne la charte BABIFIX, le taux de commission et les statistiques du prestataire.
    """
    from django.contrib.auth.models import User

    user_id = request.api_user_id
    try:
        provider = Provider.objects.select_related("user", "category").get(user_id=user_id)
    except Provider.DoesNotExist:
        return JsonResponse({"error": "provider_not_found"}, status=404)

    # Taux commission : MÊME source que le devis (source unique de vérité).
    # AVANT : le contrat recalculait le taux depuis CATEGORY_COMMISSIONS sans la
    # remise dégressive par volume → il pouvait AFFICHER un taux différent de
    # celui réellement prélevé. Un contrat ne doit jamais mentir sur le prix.
    commission_effective = _commission_effective_pct(provider)
    commission_rate = _commission_base_pct(provider)
    premium_reduction = max(0, commission_rate - commission_effective)

    # Seuils réels lus depuis la config : le contrat ne peut plus diverger du code.
    cfg = _platform_config()
    frais_mer = int(getattr(cfg, "frais_mise_en_relation_fcfa", 500) or 500)
    seuil_suspension = int(getattr(cfg, "suspension_score_seuil", 20) or 20)
    max_visites_suspectes = int(getattr(cfg, "suspension_visites_suspectes", 3) or 3)

    # Stats prestataire
    nb_missions = Reservation.objects.filter(
        prestataire_user_id=user_id, statut="Terminee"
    ).count()
    nb_demandes = Reservation.objects.filter(prestataire_user_id=user_id).count()

    return JsonResponse({
        "nom": provider.nom,
        "specialite": provider.specialite,
        "ville": provider.ville,
        "commission_rate": commission_effective,
        "commission_base": commission_rate,
        "premium_reduction": premium_reduction,
        "is_premium": provider.is_premium,
        "premium_tier": provider.premium_tier or "standard",
        "is_certified": provider.is_certified,
        "certified_at": provider.certified_at.isoformat() if provider.certified_at else None,
        "nb_missions": nb_missions,
        "nb_demandes": nb_demandes,
        "average_rating": provider.average_rating,
        "rating_count": provider.rating_count,
        "clauses": [
            {
                "titre": "Engagement de qualité",
                "contenu": "Le prestataire s'engage à réaliser les prestations avec soin, dans les délais convenus et selon les standards professionnels BABIFIX.",
            },
            {
                "titre": "Commission BABIFIX",
                "contenu": (
                    f"BABIFIX prélève une commission de {commission_effective}% sur le montant "
                    "du devis de chaque prestation réalisée via la plateforme. Cette commission "
                    "est déduite de la part du prestataire : elle n'est JAMAIS ajoutée au prix "
                    "payé par le client. Elle couvre les frais de paiement, la mise en relation "
                    "et le support."
                ),
            },
            {
                "titre": "Abonnement Pro (commission réduite)",
                "contenu": (
                    f"Le taux de base est de {commission_rate}%. Un abonnement Pro le réduit : "
                    "Silver (7 500 F/mois) et Gold (15 000 F/mois) donnent un taux dégressif. "
                    "Le taux appliqué est figé au moment de l'envoi du devis et affiché dans "
                    "l'application avant chaque envoi."
                ),
            },
            {
                "titre": "Visite de diagnostic et transport",
                "contenu": (
                    "Lorsqu'une visite est nécessaire, le client règle un défraiement de "
                    "transport (plafonné à 5 000 F), qui vous est reversé À 100% : BABIFIX ne "
                    "prélève aucune commission dessus. Il vous est crédité dès que vous "
                    "déclarez la visite effectuée, même si le chantier ne se fait pas. "
                    f"BABIFIX facture séparément au client {frais_mer} F de frais de mise en "
                    "relation. Le transport est déduit du devis final : le client ne le paie "
                    "jamais deux fois. Il n'est pas remboursable, sauf litige après analyse."
                ),
            },
            {
                "titre": "Paiement sécurisé (séquestre)",
                "contenu": (
                    "Les paiements en ligne sont bloqués en séquestre : acompte de 30% à "
                    "l'acceptation du devis, solde de 70% en fin d'intervention. Les fonds "
                    "vous sont libérés sur votre wallet APRÈS confirmation de la prestation "
                    "par le client. En cas de litige ouvert, les fonds sont gelés jusqu'à "
                    "la décision de BABIFIX."
                ),
            },
            {
                "titre": "Interdiction de contourner la plateforme",
                "contenu": (
                    "Toute prestation issue d'une mise en relation BABIFIX doit être devisée "
                    "et réglée VIA la plateforme. Traiter directement avec un client rencontré "
                    "grâce à BABIFIX, notamment après une visite de diagnostic payée, sans "
                    "envoyer de devis sur l'application, constitue une faute grave."
                ),
            },
            {
                "titre": "Score de fiabilité et détection",
                "contenu": (
                    "Un score de fiabilité (0 à 100) est associé à votre compte et visible "
                    "dans l'application. Une visite payée par le client puis déclarée "
                    "effectuée SANS aucun devis envoyé est automatiquement signalée et fait "
                    "baisser ce score. Les rendez-vous non honorés le font également baisser."
                ),
            },
            {
                "titre": "Suspension automatique",
                "contenu": (
                    f"Votre compte est suspendu AUTOMATIQUEMENT si votre score de fiabilité "
                    f"descend sous {seuil_suspension}, ou si {max_visites_suspectes} visites "
                    "suspectes sont constatées. La suspension bloque la connexion et l'accès "
                    "aux demandes. La réactivation relève d'un examen par BABIFIX. Vous êtes "
                    "averti dans l'application avant d'atteindre ces seuils."
                ),
            },
            {
                "titre": "Identité et vérification",
                "contenu": "Le prestataire confirme avoir fourni des documents d'identité valides (CNI, selfie) et accepte que BABIFIX les conserve pour des vérifications réglementaires.",
            },
            {
                "titre": "Disponibilité et réactivité",
                "contenu": "Le prestataire s'engage à répondre aux demandes dans les 48 heures. Un taux de refus élevé ou une inactivité prolongée peut entraîner la suspension du compte.",
            },
            {
                "titre": "Conduite professionnelle",
                "contenu": "Le prestataire garantit un comportement respectueux envers les clients. Tout manquement constaté pourra entraîner la suspension immédiate du compte.",
            },
            {
                "titre": "Paiements et retraits",
                "contenu": "Les gains nets sont crédités sur le wallet BABIFIX après confirmation du paiement client. Les retraits vers Mobile Money sont traités sous 24–72 heures ouvrées.",
            },
            {
                "titre": "Programme de fidélité client",
                "contenu": (
                    "Les remises de fidélité accordées aux clients sont intégralement à la "
                    "charge de BABIFIX : elles sont déduites de la commission, jamais de votre "
                    "rémunération. Votre net reste identique."
                ),
            },
            {
                "titre": "Résiliation",
                "contenu": "Le prestataire peut résilier son compte à tout moment depuis les paramètres de l'app. BABIFIX se réserve le droit de suspendre un compte en cas de non-respect de la charte.",
            },
        ],
        "contrat_version": CONTRAT_VERSION,
        "contrat_accepte_at": provider.contrat_accepte_at.isoformat() if provider.contrat_accepte_at else None,
        # Signé = accepté ET dans la version EN COURS. Un changement matériel de
        # clause (ex. suspension automatique) exige une nouvelle acceptation :
        # on n'applique pas une règle à quelqu'un qui ne l'a jamais signée.
        "contrat_signe": (
            provider.contrat_accepte_at is not None
            and (provider.contrat_version or "") == CONTRAT_VERSION
        ),
        "contrat_version_signee": provider.contrat_version or "",
        "resignature_requise": (
            provider.contrat_accepte_at is not None
            and (provider.contrat_version or "") != CONTRAT_VERSION
        ),
    })


@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["prestataire"])
def api_prestataire_contrat_sign(request):
    """
    POST /api/prestataire/contrat/sign/
    Enregistre l'acceptation du contrat BABIFIX côté serveur.

    La version signée est celle du SERVEUR (CONTRAT_VERSION), jamais celle
    envoyée par le client : sinon une app obsolète (ou modifiée) pourrait
    « signer » une ancienne version et échapper aux clauses en vigueur.
    """
    from django.utils import timezone

    user_id = request.api_user_id
    try:
        provider = Provider.objects.get(user_id=user_id)
    except Provider.DoesNotExist:
        return JsonResponse({"error": "provider_not_found"}, status=404)

    version = CONTRAT_VERSION
    now = timezone.now()
    provider.contrat_accepte_at = now
    provider.contrat_version = version
    provider.save(update_fields=["contrat_accepte_at", "contrat_version"])

    return JsonResponse({
        "ok": True,
        "contrat_accepte_at": now.isoformat(),
        "contrat_version": version,
    })


# =============================================================================
# KYC — Vérification identité prestataire
# =============================================================================
@csrf_exempt
@require_http_methods(["GET"])
@require_api_auth(["prestataire"])
def api_prestataire_kyc_status(request):
    """
    GET /api/prestataire/kyc/status/
    Retourne le statut KYC du prestataire connecté.
    Réponse : { "status": "...", "rejection_reason": "..." }
    """
    from django.contrib.auth.models import User

    try:
        user = User.objects.get(id=request.api_user_id)
        provider = Provider.objects.get(user=user)
    except (User.DoesNotExist, Provider.DoesNotExist):
        return JsonResponse({"error": "provider_not_found"}, status=404)

    return JsonResponse({
        "status": provider.kyc_status,
        "rejection_reason": provider.kyc_rejection_reason or None,
    })


@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["prestataire"])
def api_prestataire_kyc_submit(request):
    """
    POST /api/prestataire/kyc/submit/
    Soumet le dossier KYC du prestataire.
    Body JSON : {
        "cni_number": "...",
        "cni_expiry": "YYYY-MM-DD",
        "cni_recto_b64": "data:image/jpeg;base64,...",
        "cni_verso_b64": "...",
        "selfie_b64": "..."
    }
    """
    from datetime import datetime
    from django.utils import timezone
    from django.contrib.auth.models import User

    try:
        user = User.objects.get(id=request.api_user_id)
        provider = Provider.objects.get(user=user)
    except (User.DoesNotExist, Provider.DoesNotExist):
        return JsonResponse({"error": "provider_not_found"}, status=404)

    try:
        payload = json.loads(request.body)
    except (json.JSONDecodeError, ValueError):
        return JsonResponse({"error": "invalid_json", "message": "Corps JSON invalide"}, status=400)

    # Extraction et validation
    cni_number = (payload.get("cni_number") or "").strip()
    cni_expiry = (payload.get("cni_expiry") or "").strip()
    cni_recto = (payload.get("cni_recto_b64") or "").strip()
    cni_verso = (payload.get("cni_verso_b64") or "").strip()
    selfie = (payload.get("selfie_b64") or "").strip()

    errors = {}
    if not cni_number:
        errors["cni_number"] = ["Ce champ est requis."]
    elif len(cni_number) < 5:
        errors["cni_number"] = ["Numéro de CNI trop court."]
    if not cni_recto:
        errors["cni_recto_b64"] = ["Photo recto requise."]
    if not cni_verso:
        errors["cni_verso_b64"] = ["Photo verso requise."]
    if not selfie:
        errors["selfie_b64"] = ["Selfie requis."]

    # Date d'expiration : requise, valide, et NON expirée (KYC strict).
    expiry_date = None
    if not cni_expiry:
        errors["cni_expiry"] = ["Cette date est requise."]
    else:
        try:
            expiry_date = datetime.strptime(cni_expiry, "%Y-%m-%d").date()
            if expiry_date <= timezone.now().date():
                errors["cni_expiry"] = [
                    "Cette pièce d'identité est expirée. Fournissez une CNI valide."
                ]
        except ValueError:
            errors["cni_expiry"] = ["Date invalide (format attendu : AAAA-MM-JJ)."]

    # Les photos doivent être de vraies images base64.
    for key, val in (
        ("cni_recto_b64", cni_recto),
        ("cni_verso_b64", cni_verso),
        ("selfie_b64", selfie),
    ):
        if val and not val.startswith("data:image/"):
            errors[key] = ["Image invalide."]

    if errors:
        return JsonResponse({"error": "validation_failed", "fields": errors}, status=400)

    # Stockage robuste : on envoie les pièces sur Cloudinary (URL persistante)
    # plutôt que de garder le base64 brut en base. Repli base64 si l'upload
    # échoue (on ne perd jamais le document).
    from .views import _decode_and_save_media

    def _store(b64: str, prefix: str) -> str:
        try:
            url = _decode_and_save_media(b64, "kyc", prefix)
            return url or b64
        except Exception:
            return b64

    # Mise à jour fournisseur
    provider.kyc_cni_number = cni_number
    provider.kyc_cni_recto_url = _store(cni_recto, "cni_recto")
    provider.kyc_cni_verso_url = _store(cni_verso, "cni_verso")
    provider.kyc_selfie_url = _store(selfie, "selfie")
    provider.kyc_status = "pending"
    provider.kyc_submitted_at = timezone.now()
    provider.kyc_cni_expiry = expiry_date

    provider.save(update_fields=[
        "kyc_cni_number", "kyc_cni_recto_url", "kyc_cni_verso_url",
        "kyc_selfie_url", "kyc_status", "kyc_submitted_at", "kyc_cni_expiry"
    ])

    return JsonResponse({
        "status": "pending",
        "message": "Dossier KYC soumis avec succès. Vérification sous 24-48h.",
    }, status=200)


# =============================================================================
# PAIEMENTS SÉCURISÉS (Acompte / Solde)
# =============================================================================
from django.utils import timezone

@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["client"])
def api_reservation_paiement_acompte(request):
    """
    POST /api/reservation/paiement-acompte/
    Le client paie l'acompte (ex: 30%). L'argent est bloqué.
    Body: { "reservation_id": 123 }
    """
    try:
        data = json.loads(request.body)
        reservation = Reservation.objects.get(
            id=data['reservation_id'],
            client_user__id=request.api_user_id,
            statut=Reservation.Status.DEVIS_ACCEPTE  # Doit être accepté
        )
    except (Reservation.DoesNotExist, KeyError):
        return JsonResponse({"error": "reservation_invalide"}, status=404)

    if reservation.acompte_valide:
        return JsonResponse({"error": "acompte_deja_verse"}, status=400)

    # Calcul de l'acompte (30% ici, ajustable selon le métier)
    taux_acompte = Decimal('0.30')
    acompte = (reservation.montant * taux_acompte).quantize(Decimal('0.01'))

    # --- SIMULATION PAIEMENT (CinetPay / GeniusPay) ---
    # Ici, vous appelez votre fournisseur de paiement.
    # Ex: succes = genius_pay.debiter(acompte, reservation.client_user)
    succes_paiement = True  # Simulé pour MVP/Démo

    if succes_paiement:
        reservation.montant_verse = acompte
        reservation.montant_restant = reservation.montant - acompte
        reservation.acompte_valide = True
        reservation.statut = Reservation.Status.DEVIS_ACCEPTE  # On garde le nommage mais logique métier OK
        reservation.save()

        # Notification au Prestataire : il peut commencer
        if reservation.assigned_provider and reservation.assigned_provider.user:
            send_push_notification(
                reservation.assigned_provider.user.id,
                "Acompte reçu - Travail autorisé",
                f"L'acompte de {acompte} FCFA est bloqué. Vous pouvez démarrer l'intervention.",
                "success"
            )

        return JsonResponse({
            "ok": True,
            "acompte": str(acompte),
            "restant": str(reservation.montant_restant),
            "statut": reservation.statut
        })
    else:
        return JsonResponse({"error": "echec_paiement"}, status=402)


@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["client"])
def api_reservation_paiement_solde(request):
    """
    POST /api/reservation/paiement-solde/
    Le client paie le solde après validation des travaux.
    Body: { "reservation_id": 123 }
    """
    try:
        data = json.loads(request.body)
        reservation = Reservation.objects.get(
            id=data['reservation_id'],
            client_user__id=request.api_user_id,
            statut=Reservation.Status.EN_ATTENTE_CLIENT  # Le presta a terminé
        )
    except (Reservation.DoesNotExist, KeyError):
        return JsonResponse({"error": "reservation_invalide"}, status=404)

    if not reservation.acompte_valide:
        return JsonResponse({"error": "versez_acompte_dabord"}, status=400)

    if reservation.solde_valide:
        return JsonResponse({"error": "deja_regle"}, status=400)

    montant_solde = reservation.montant_restant

    # --- SIMULATION PAIEMENT SOLDE ---
    succes_paiement = True  # Simulé

    if succes_paiement:
        reservation.montant_verse = reservation.montant
        reservation.montant_restant = 0
        reservation.solde_valide = True
        reservation.statut = Reservation.Status.TERMINEE
        reservation.save()

        # ICI : VRAI TRANSFERT VERS LE PRESTATAIRE (Banque/Génius/CinetPay)
        # transferer_fonds(reservation.assigned_provider, reservation.montant)

        # Notifier le Prestataire : il reçoit son argent
        if reservation.assigned_provider and reservation.assigned_provider.user:
            send_push_notification(
                reservation.assigned_provider.user.id,
                "Paiement final reçu",
                f"Félicitations ! Le solde de {montant_solde} FCFA a été payé. Fonds transférés.",
                "success"
            )

        return JsonResponse({
            "ok": True,
            "message": "Transaction totalement finalisée.",
            "statut": reservation.statut
        })
    else:
        return JsonResponse({"error": "echec_paiement_solde"}, status=402)


# =============================================================================
# RATINGS — Avis clients sur prestataire
# =============================================================================
@csrf_exempt
@require_http_methods(["GET"])
@require_api_auth(["prestataire"])
def api_prestataire_ratings(request):
    """
    GET /api/prestataire/ratings/
    Retourne la liste des avis/notes laissés par les clients pour ce prestataire.
    Réponse : { "ratings": [ { "reference", "rating", "comment", "date", "client_name" } ] }
    """
    try:
        provider = Provider.objects.get(user_id=request.api_user_id)
    except Provider.DoesNotExist:
        return JsonResponse({"error": "provider_not_found"}, status=404)

    # Récupérer tous les ratings du prestataire (via related_name='ratings' sur Rating.provider)
    ratings_qs = provider.ratings.select_related('reservation', 'client').order_by('-created_at')

    ratings_list = []
    for r in ratings_qs:
        ratings_list.append({
            "reference": r.reservation.reference if r.reservation else "",
            "rating": r.note,
            "comment": r.commentaire or "",
            "date": r.created_at.isoformat() if r.created_at else None,
            "client_name": r.client.get_full_name() if r.client else "Client",
        })

    return JsonResponse({"ratings": ratings_list})


# =============================================================================
# RATINGS — Avis clients sur prestataire
# =============================================================================
@csrf_exempt
@require_http_methods(["GET"])
@require_api_auth(["prestataire"])
def api_prestataire_ratings(request):
    """
    GET /api/prestataire/ratings/
    Retourne la liste des avis/notes laissés par les clients pour ce prestataire.
    Réponse : { "ratings": [ { "reference", "rating", "comment", "date", "client_name" } ] }
    """
    try:
        provider = Provider.objects.get(user_id=request.api_user_id)
    except Provider.DoesNotExist:
        return JsonResponse({"error": "provider_not_found"}, status=404)

    # Réservations terminées avec notation client
    from ..models import Reservation
    reservations = Reservation.objects.filter(
        assigned_provider=provider,
        statut=Reservation.Status.DONE,
    ).exclude(client_note__isnull=True).exclude(client_note="").order_by("-created_at")

    ratings = []
    for r in reservations:
        ratings.append({
            "reference": r.reference,
            "rating": r.client_rating if hasattr(r, 'client_rating') else None,  # à adapter selon le modèle
            "comment": r.client_note or "",
            "date": r.created_at.isoformat() if r.created_at else None,
            "client_name": r.client_user.nom if r.client_user else "Client",
        })

    return JsonResponse({"ratings": ratings})


# =============================================================================
# PRESTATAIRE — Historique des paiements
# =============================================================================
@csrf_exempt
@require_api_auth(["prestataire", "admin"])
@require_GET
def api_prestataire_payments_history(request):
    """
    GET /api/prestataire/payments/history/
    Retourne tous les paiements du prestataire avec détails (réservation, client, etc.).
    """
    user_id = request.api_user_id
    provider = Provider.objects.filter(user_id=user_id).first()
    if not provider:
        return JsonResponse({"error": "Profil prestataire introuvable"}, status=404)

    payments = Payment.objects.filter(prestataire=provider.nom).order_by("-created_at")[:100]
    result = []
    for pay in payments:
        res = pay.reservation
        client_name = ""
        service_title = ""
        reference = ""
        if res:
            reference = res.reference
            service_title = getattr(res, "titre", None) or getattr(res, "title", "") or ""
            if res.client_user:
                client_name = res.client_user.get_full_name() or res.client_user.username
            elif res.client:
                client_name = res.client

        raw_montant = str(pay.montant or "0").replace("€", "").replace("FCFA", "").strip()
        try:
            gross_val = float(raw_montant)
        except ValueError:
            gross_val = 0.0

        raw_commission = str(pay.commission or "0").replace("€", "").replace("FCFA", "").strip()
        try:
            commission_val = float(raw_commission)
        except ValueError:
            commission_val = 0.0

        net_val = gross_val - commission_val

        result.append({
            "id": pay.pk,
            "reference": pay.reference,
            "reservation_reference": reference,
            "client_name": client_name,
            "service_title": service_title,
            "montant_brut": int(gross_val),
            "commission": int(commission_val),
            "net": int(net_val),
            "etat": pay.etat,
            "type_paiement": pay.type_paiement,
            "date": pay.created_at.isoformat() if pay.created_at else None,
        })

    return JsonResponse({"payments": result})


@csrf_exempt
@require_http_methods(["GET", "POST"])
def api_run_reminders(request):
    """Déclenche les relances email (prestataires inactifs, devis/demandes en
    attente). À appeler par un cron externe gratuit (ex. cron-job.org) une fois
    par jour : GET /api/internal/run-reminders/?key=<CRON_SECRET>.
    Protégé par la variable d'environnement CRON_SECRET."""
    import os
    from io import StringIO
    from django.core.management import call_command

    expected = (os.getenv("CRON_SECRET", "") or "").strip()
    key = (request.GET.get("key") or request.POST.get("key") or "").strip()
    if not expected or key != expected:
        return JsonResponse({"error": "forbidden"}, status=403)
    out = StringIO()
    try:
        call_command("send_reminders", stdout=out)
    except Exception as exc:  # noqa: BLE001
        logger.exception("run-reminders a échoué")
        return JsonResponse({"error": "command_failed", "detail": str(exc)}, status=500)
    return JsonResponse({"ok": True, "result": out.getvalue().strip()})

