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


def email_welcome(user, role: str) -> None:
    """Email de bienvenue lors de l'inscription."""
    print(f"[EMAIL] email_welcome called: {user.email}, role={role}")
    if not user.email:
        print("[WARN] No user email, skipping")
        return

    is_prestataire = role == "prestataire"
    role_description = (
        "Rejoignez des milliers de prestataires certifies"
        if is_prestataire
        else "Trouvez le prestataire ideal pres de chez vous"
    )
    cta_text = (
        "Gerer mon espace prestataire" if is_prestataire else "Explorer les services"
    )

    context = {
        "username": user.username,
        "role_description": role_description,
        "is_prestataire": is_prestataire,
        "cta_text": cta_text,
        "app_url": "https://babifix.ci/app",
    }

    try:
        html_content = _render_email_template("welcome.html", context)
        print(f"[EMAIL] Template rendered: {len(html_content) if html_content else 0} chars")
        if not html_content:
            print("[ERROR] Template welcome.html empty or not found")
            return

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
        subject=f"Nouvelle demande de service — {reservation.title or reservation.reference}",
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
        subject="Votre mission BABIFIX est terminée — Évaluez votre prestataire",
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


# =============================================================================
# CRUD DISPONIBILITÉS — GET/POST /api/prestataire/availability/
# =============================================================================
@csrf_exempt
@require_api_auth(["prestataire", "admin"])
def api_prestataire_availability_crud(request):
    """CRUD des créneaux de disponibilité."""
    try:
        provider = Provider.objects.get(user=request.babifix_user)
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
        debut = payload.get("heure_debut")
        fin = payload.get("heure_fin")

        if not all([jour, debut, fin]):
            return JsonResponse(
                {"error": "jour_semaine, heure_debut, heure_fin required"}, status=400
            )

        from datetime import time

        try:
            debut_t = time.fromisoformat(debut)
            fin_t = time.fromisoformat(fin)
        except ValueError:
            return JsonResponse({"error": "invalid_time_format"}, status=400)

        slot = PrestataireAvailabilitySlot.objects.create(
            provider=provider,
            jour_semaine=int(jour),
            heure_debut=debut_t,
            heure_fin=fin_t,
            actif=True,
        )
        return JsonResponse({"id": slot.id, "ok": True}, status=201)

    elif request.method == "DELETE":
        slot_id = request.GET.get("id")
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
def api_prestataire_unavailability_crud(request):
    """CRUD des périodes d'indisponibilité."""
    try:
        provider = Provider.objects.get(user=request.babifix_user)
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

        debut = payload.get("date_debut")
        fin = payload.get("date_fin")
        motif = payload.get("motif", "")

        if not all([debut, fin]):
            return JsonResponse({"error": "date_debut, date_fin required"}, status=400)

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
        period_id = request.GET.get("id")
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
        provider = Provider.objects.get(user=request.babifix_user)
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

    payments = Payment.objects.filter(client_user=client_user).order_by("-created_at")

    data = [
        {
            "id": p.id,
            "reference": p.reference,
            "montant": p.montant,
            "etat": p.etat,
            "operator": p.mobile_money_operator,
            "reservation_reference": p.reservation.reference if p.reservation else None,
            "created_at": p.created_at.isoformat() if p.created_at else None,
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
    """Litiges pour le prestataire connecté."""
    provider = Provider.objects.filter(user_id=request.api_user_id).first()
    if not provider:
        return JsonResponse({"error": "provider_not_found"}, status=404)

    disputes = Dispute.objects.filter(provider=provider).order_by("-created_at")

    data = [
        {
            "id": d.id,
            "reference": d.reference,
            "motif": d.motif,
            "priorite": d.priorite,
            "decision": d.decision,
            "reservation_reference": d.reservation.reference if d.reservation else None,
            "created_at": d.created_at.isoformat() if d.created_at else None,
        }
        for d in disputes
    ]
    return JsonResponse({"disputes": data})


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

    subject = f"Mission terminée — {reservation.title or reservation.reference}"
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

    subject = f"Litige ouvert — Réservation {reservation.reference}"
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


def send_babifix_email_html(
    to_email: str,
    subject: str,
    html_content: str,
    attachments: list | None = None,
) -> None:
    """Envoi email HTML transactionnel BABIFIX avec fallback plain text.

    attachments: liste de tuples (filename, content, mimetype) — ex: PDF reçu.
    """
    from django.conf import settings
    from django.core.mail import EmailMultiAlternatives

    try:
        if not html_content:
            return

        import re

        plain_text = re.sub(r"<[^>]+>", "", html_content)
        plain_text = re.sub(r"\n+", "\n", plain_text).strip()

        msg = EmailMultiAlternatives(
            subject=subject,
            body=plain_text,
            from_email=getattr(
                settings, "DEFAULT_FROM_EMAIL", "BABIFIX <contact@babifix.ci>"
            ),
            to=[to_email],
        )
        msg.attach_alternative(html_content, "text/html")
        for filename, content, mimetype in (attachments or []):
            msg.attach(filename, content, mimetype)
        msg.send(fail_silently=False)
        print(f"\n[EMAIL] Sent to {to_email}: {subject}\n")
        logger.info(f"Email envoye a {to_email}: {subject}")
    except Exception as exc:
        logger.warning("Email non envoyé (%s) : %s", to_email, exc)


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

@csrf_exempt
@require_GET
def api_client_invoice_pdf(request, reference):
    """GET /api/client/invoices/<reference>/pdf/ — Télécharger le reçu PDF."""
    user, err = require_api_auth(request)
    if err:
        return err

    try:
        payment = (
            Payment.objects.select_related("reservation__client_user")
            .filter(
                reservation__reference=reference,
                reservation__client_user=user,
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
        logger.error("Erreur génération PDF reçu ref=%s: %s", reference, exc)
        return JsonResponse({"error": "Erreur génération PDF"}, status=500)

    response = HttpResponse(pdf_bytes, content_type="application/pdf")
    response["Content-Disposition"] = f'attachment; filename="recu_{invoice_number}.pdf"'
    return response


@csrf_exempt
@require_GET
def api_prestataire_invoice_pdf(request, reference):
    """GET /api/prestataire/invoices/<reference>/pdf/ — Télécharger le reçu PDF."""
    user, err = require_api_auth(request)
    if err:
        return err

    try:
        provider = Provider.objects.filter(user=user).first()
        payment = (
            Payment.objects.select_related("reservation__prestataire_user")
            .filter(
                reservation__reference=reference,
                reservation__prestataire_user=user,
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


@csrf_exempt
@require_GET
def api_client_invoices_list(request):
    """GET /api/client/invoices/ — Liste des reçus du client."""
    user, err = require_api_auth(request)
    if err:
        return err

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
@require_GET
def api_prestataire_wallet(request):
    """GET /api/prestataire/wallet/ — Solde + historique transactions."""
    user, err = require_api_auth(request)
    if err:
        return err

    provider = Provider.objects.filter(user=user).first()
    if not provider:
        return JsonResponse({"error": "Profil prestataire introuvable"}, status=404)

    from adminpanel.services.wallet_service import WalletService
    summary = WalletService.get_wallet_summary(provider.pk)
    return JsonResponse(summary, status=200)


@csrf_exempt
@require_http_methods(["POST"])
def api_prestataire_wallet_withdraw(request):
    """
    POST /api/prestataire/wallet/withdraw/
    Body JSON : {amount_fcfa, phone, operator}
    """
    user, err = require_api_auth(request)
    if err:
        return err

    provider = Provider.objects.filter(user=user).first()
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
def api_prestataire_wallet_update_info(request):
    """
    POST /api/prestataire/wallet/info/
    Body JSON : {phone, operator}
    Met à jour les infos Mobile Money du prestataire.
    """
    user, err = require_api_auth(request)
    if err:
        return err

    provider = Provider.objects.filter(user=user).first()
    if not provider:
        return JsonResponse({"error": "Profil prestataire introuvable"}, status=404)

    try:
        body = json.loads(request.body)
    except (json.JSONDecodeError, TypeError):
        return JsonResponse({"error": "JSON invalide"}, status=400)

    phone = (body.get("phone") or "").strip()
    operator = (body.get("operator") or "").strip().lower()

    valid_operators = {"mtn", "orange", "wave", "moov", ""}
    if operator not in valid_operators:
        return JsonResponse({"error": f"Opérateur invalide : {operator}"}, status=400)

    update_fields = []
    if phone:
        provider.wallet_phone = phone
        update_fields.append("wallet_phone")
    if operator:
        provider.wallet_operator = operator
        update_fields.append("wallet_operator")

    if update_fields:
        provider.save(update_fields=update_fields)

    return JsonResponse({
        "status": "ok",
        "wallet_phone": provider.wallet_phone,
        "wallet_operator": provider.wallet_operator,
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

    # Taux commission (par catégorie si disponible)
    commission_rate = 18
    if provider.category:
        from .services.referral_service import CATEGORY_COMMISSIONS
        commission_rate = CATEGORY_COMMISSIONS.get(
            (provider.category.slug or provider.category.nom or "").lower(),
            CATEGORY_COMMISSIONS["default"],
        )

    # Réduction commission selon tier premium
    premium_reduction = {"bronze": 0, "silver": 5, "gold": 10}.get(provider.premium_tier or "", 0)
    commission_effective = max(5, commission_rate - premium_reduction)

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
                "contenu": f"BABIFIX prélève une commission de {commission_effective}% sur chaque prestation réalisée via la plateforme. Ce taux inclut les frais de paiement, d'assurance et de support client.",
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
                "contenu": "Les gains nets sont crédités sur le wallet BABIFIX après confirmation du paiement client. Les retraits sont traités sous 24–72 heures ouvrées.",
            },
            {
                "titre": "Résiliation",
                "contenu": "Le prestataire peut résilier son compte à tout moment depuis les paramètres de l'app. BABIFIX se réserve le droit de suspendre un compte en cas de non-respect de la charte.",
            },
        ],
    })
