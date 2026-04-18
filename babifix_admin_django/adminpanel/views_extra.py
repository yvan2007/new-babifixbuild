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

import csv
import json
import logging

from django.contrib.auth.decorators import login_required
from django.db.models import Avg, Count, Q, Sum
from django.http import JsonResponse, StreamingHttpResponse
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


# =============================================================================
# EMAIL NOTIFICATIONS BABIFIX
# =============================================================================


def send_babifix_email(to_email: str, subject: str, body: str) -> None:
    """Envoi e-mail transactionnel (configure EMAIL_* dans .env)."""
    from django.core.mail import send_mail
    from django.conf import settings

    try:
        send_mail(
            subject=subject,
            message=body,
            from_email=getattr(settings, "DEFAULT_FROM_EMAIL", "contact@babifix.ci"),
            recipient_list=[to_email],
            fail_silently=True,
        )
    except Exception as exc:
        logger.warning("Email non envoyé (%s) : %s", to_email, exc)


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


def email_welcome(user, role: str) -> None:
    """Email de bienvenue lors de l'inscription."""
    if not user.email:
        return

    role_label = "Client" if role == "client" else "Prestataire"
    is_provider = role == "prestataire"

    body = f"Bonjour {user.username},\n\nBienvenue sur BABIFIX !\n\n"

    if is_provider:
        body += (
            "Votre compte prestataire a été créé avec succès.\n"
            "Pour commencer à recevoir des missions, vous devez :\n"
            "1. Compléter votre profil (photo, bio, tarifs)\n"
            "2. Soumettre vos pièces d'identification\n"
            "3. Attendre la validation de notre équipe\n\n"
            "Téléchargez l'application BABIFIX Prestataire pour finaliser votre inscription.\n\n"
        )
    else:
        body += (
            "Votre compte client a été créé avec succès.\n"
            "Vous pouvez maintenant :\n"
            "- Rechercher des prestataires près de chez vous\n"
            "- Réserver des services en quelques clics\n"
            "- Paiement sécurisé via Mobile Money\n\n"
            "Téléchargez l'application BABIFIX Client pour profiter de tous nos services.\n\n"
        )

    body += "L'équipe BABIFIX — Côte d'Ivoire\ncontact@babifix.ci | https://babifix.ci"

    send_babifix_email(
        to_email=user.email,
        subject=f"Bienvenue sur BABIFIX ! ({role_label})",
        body=body,
    )


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

    try:
        provider = Provider.objects.get(user=request.babifix_user)
    except Provider.DoesNotExist:
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
            admin_user=request.user,
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
    try:
        client_user = request.user
    except Exception:
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
    try:
        client_user = request.user
    except Exception:
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
    try:
        provider = Provider.objects.get(user=request.user)
    except Provider.DoesNotExist:
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


def send_babifix_email_html(to_email: str, subject: str, html_content: str) -> None:
    """Envoi email HTML transactionnel BABIFIX."""
    from django.conf import settings
    from django.core.mail import EmailMultiAlternatives

    try:
        if html_content:
            msg = EmailMultiAlternatives(
                subject=subject,
                body=html_content,
                from_email=getattr(
                    settings, "DEFAULT_FROM_EMAIL", "contact@babifix.ci"
                ),
                to=[to_email],
            )
            msg.content_subtype = "html"
            msg.send(fail_silently=True)
        else:
            send_babifix_email(to_email, subject, subject)
    except Exception as exc:
        logger.warning("Email HTML non envoyé (%s) : %s", to_email, exc)


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

    from django.http import JsonResponse

    http_status = 200 if status["status"] == "ok" else 503
    return JsonResponse(status, status=http_status)
