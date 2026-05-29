"""
BABIFIX — Nouvelles fonctionnalités v2
  1.  GET  /api/client/reservations               — historique réservations client
  2.  GET  /api/client/reservations/<ref>          — détail réservation + statut temps réel
  3.  POST /api/client/reservations/<ref>/cancel   — annulation réservation
  4.  POST /api/client/reservations/<ref>/dispute  — ouvrir un litige
  5.  POST /api/auth/forgot-password               — demande reset mot de passe
  6.  POST /api/auth/reset-password                — confirmer reset avec token
  7.  POST /api/auth/refresh                       — refresh token JWT
  8.  GET  /api/auth/verify-email/<token>          — confirmer email
  9.  PATCH /api/prestataire/profile               — modifier profil prestataire
  10. GET  /api/prestataire/portfolio              — galerie réalisations prestataire
  11. POST /api/prestataire/portfolio              — ajouter photo réalisation
  12. DELETE /api/prestataire/portfolio/<idx>      — supprimer photo réalisation
  13. POST /api/prestataire/reservations/<ref>/rate-client — noter le client
  14. GET  /api/client/notifications               — notifications persistantes client
  15. POST /api/admin/push-broadcast               — push notif manuelle tous users
"""

import json
import logging
import re
import secrets
import uuid
from datetime import timedelta

from django.contrib.auth.models import User
from django.db import transaction
from django.http import JsonResponse
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_GET, require_http_methods

from .auth import (
    create_refresh_token,
    create_token,
    require_api_auth,
    verify_refresh_token,
    verify_token,
)
from .models import (
    DeviceToken,
    Dispute,
    Notification,
    Provider,
    Rating,
    Reservation,
    UserProfile,
    recalc_provider_rating_stats,
)
from .push_dispatch import _schedule

logger = logging.getLogger(__name__)


# ─────────────────────────────────────────────────────────────────────────────
# Helpers internes
# ─────────────────────────────────────────────────────────────────────────────


def _res_to_dict(res: Reservation, uid: int) -> dict:
    """Sérialise une Reservation pour l'API client."""
    has_rating = hasattr(res, "rating") and res.rating is not None
    return {
        "id": res.pk,
        "reference": res.reference,
        "title": res.title or res.reference,
        "prestataire": res.prestataire,
        "prestataire_id": res.assigned_provider_id,
        "montant": res.montant,
        "statut": res.statut,
        "payment_type": res.payment_type,
        "mobile_money_operator": res.mobile_money_operator,
        "address_label": res.address_label,
        "client_message": res.client_message,
        "cash_flow_status": res.cash_flow_status,
        "dispute_ouverte": res.dispute_ouverte,
        "can_cancel": res.statut
        in ("En attente", "Confirmee", "DEMANDE_ENVOYEE", "DEVIS_EN_COURS", "DEVIS_ENVOYE"),
        "can_rate": res.statut == "Terminee" and not has_rating,
        "can_dispute": res.statut in ("Terminee", "En cours")
        and not res.dispute_ouverte,
        "rated": has_rating,
        "rating_note": res.rating.note if has_rating else None,
    }


def _get_res_for_client(reference: str, uid: int):
    try:
        return Reservation.objects.select_related("assigned_provider", "rating").get(
            reference=reference, client_user_id=uid
        )
    except Reservation.DoesNotExist:
        return None


# ─────────────────────────────────────────────────────────────────────────────
# 1. GET /api/client/reservations — historique
# ─────────────────────────────────────────────────────────────────────────────
@require_GET
@require_api_auth(["client", "admin"])
def api_client_reservations_list(request):
    """Liste toutes les réservations du client connecté, du plus récent au plus ancien."""
    uid = request.api_user_id
    statut_filter = request.GET.get("statut", "")  # optionnel : ?statut=En attente
    qs = (
        Reservation.objects.filter(client_user_id=uid)
        .select_related("assigned_provider", "rating")
        .order_by("-pk")
    )
    if statut_filter:
        qs = qs.filter(statut=statut_filter)
    return JsonResponse({"reservations": [_res_to_dict(r, uid) for r in qs]})


# ─────────────────────────────────────────────────────────────────────────────
# 2. GET /api/client/reservations/<ref> — détail
# ─────────────────────────────────────────────────────────────────────────────
@require_GET
@require_api_auth(["client", "admin"])
def api_client_reservation_detail(request, reference):
    uid = request.api_user_id
    res = _get_res_for_client(reference, uid)
    if not res:
        return JsonResponse({"error": "not_found"}, status=404)
    return JsonResponse(_res_to_dict(res, uid))


# ─────────────────────────────────────────────────────────────────────────────
# 3. POST /api/client/reservations/<ref>/cancel — annuler
# ─────────────────────────────────────────────────────────────────────────────
@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["client", "admin"])
def api_client_cancel_reservation(request, reference):
    uid = request.api_user_id
    res = _get_res_for_client(reference, uid)
    if not res:
        return JsonResponse({"error": "not_found"}, status=404)
    if res.statut not in (
        "En attente",
        "Confirmee",
        "DEMANDE_ENVOYEE",
        "DEVIS_EN_COURS",
        "DEVIS_ENVOYE",
    ):
        return JsonResponse(
            {"error": "cannot_cancel", "statut": res.statut}, status=400
        )
    with transaction.atomic():
        res.statut = Reservation.Status.CANCELLED
        res.save(update_fields=["statut"])
        # Notifier le prestataire
        if res.prestataire_user_id:
            Notification.objects.create(
                title=f"Réservation {reference} annulée par le client",
                user_id=res.prestataire_user_id,
            )
    if res.prestataire_user_id:
        _schedule(
            user_ids=[res.prestataire_user_id],
            title="Réservation annulée",
            body=f"Le client a annulé la réservation {reference}.",
            data={"type": "reservation_cancelled", "reference": reference},
        )
    return JsonResponse({"ok": True, "statut": res.statut})


# ─────────────────────────────────────────────────────────────────────────────
# 4. POST /api/client/reservations/<ref>/dispute — ouvrir un litige
# ─────────────────────────────────────────────────────────────────────────────
@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["client", "admin"])
def api_client_open_dispute(request, reference):
    uid = request.api_user_id
    res = _get_res_for_client(reference, uid)
    if not res:
        return JsonResponse({"error": "not_found"}, status=404)
    if res.dispute_ouverte:
        return JsonResponse({"error": "dispute_already_open"}, status=400)
    if res.statut not in ("Terminee", "En cours"):
        return JsonResponse(
            {"error": "cannot_dispute", "statut": res.statut}, status=400
        )
    try:
        payload = json.loads(request.body or b"{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)
    motif = str(payload.get("motif", "") or "").strip()
    if not motif:
        return JsonResponse({"error": "motif_required"}, status=400)
    ref_litige = f"LIT-{uuid.uuid4().hex[:8].upper()}"
    with transaction.atomic():
        Dispute.objects.create(
            reference=ref_litige,
            motif=motif[:200],
            client=res.client,
            prestataire=res.prestataire,
            priorite=Dispute.Priority.MEDIUM,
            decision=Dispute.Decision.OPEN,
            reservation=res,
        )
        res.dispute_ouverte = True
        res.save(update_fields=["dispute_ouverte"])
        Notification.objects.create(title=f"Nouveau litige {ref_litige} — {reference}")
    return JsonResponse({"ok": True, "litige_reference": ref_litige})


# ─────────────────────────────────────────────────────────────────────────────
# 5. POST /api/auth/forgot-password — demander un reset
# ─────────────────────────────────────────────────────────────────────────────
@csrf_exempt
@require_http_methods(["POST"])
def api_auth_forgot_password(request):
    try:
        payload = json.loads(request.body or b"{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)
    email = str(payload.get("email", "") or "").strip().lower()
    if not email:
        return JsonResponse({"error": "email_required"}, status=400)
    # Toujours répondre ok pour ne pas révéler si l'email existe
    user = User.objects.filter(email__iexact=email).first()
    if user:
        token = secrets.token_urlsafe(32)
        profile, _ = UserProfile.objects.get_or_create(
            user=user, defaults={"role": "client"}
        )
        profile.reset_token = token
        profile.reset_token_created_at = timezone.now()
        profile.save(update_fields=["reset_token", "reset_token_created_at"])
        # Email transactionnel
        _send_reset_email(user.email, token)
    return JsonResponse(
        {"ok": True, "message": "Si cet email existe, un lien a été envoyé."}
    )


def _send_verification_email(to_email: str, token: str) -> None:
    from django.core.mail import send_mail
    from django.conf import settings

    try:
        send_mail(
            subject="Confirmez votre email BABIFIX",
            message=(
                f"Bonjour,\n\n"
                f"Merci de vous être inscrit sur BABIFIX.\n"
                f"Pour confirmer votre email, utilisez ce code dans l'application :\n\n"
                f"{token}\n\n"
                f"L'équipe BABIFIX | contact@babifix.ci"
            ),
            from_email=getattr(settings, "DEFAULT_FROM_EMAIL", "contact@babifix.ci"),
            recipient_list=[to_email],
            fail_silently=True,
        )
    except Exception as exc:
        logger.warning("Verify email non envoyé (%s) : %s", to_email, exc)


def _send_reset_email(to_email: str, token: str) -> None:
    from django.core.mail import send_mail
    from django.conf import settings

    reset_link = f"babifix://reset-password?token={token}"
    try:
        send_mail(
            subject="Réinitialisation de votre mot de passe BABIFIX",
            message=(
                f"Bonjour,\n\n"
                f"Vous avez demandé à réinitialiser votre mot de passe BABIFIX.\n\n"
                f"Utilisez ce token dans l'application :\n{token}\n\n"
                f"Ce lien expire dans 30 minutes.\n\n"
                f"Si vous n'êtes pas à l'origine de cette demande, ignorez cet email.\n\n"
                f"L'équipe BABIFIX | contact@babifix.ci"
            ),
            from_email=getattr(settings, "DEFAULT_FROM_EMAIL", "contact@babifix.ci"),
            recipient_list=[to_email],
            fail_silently=True,
        )
    except Exception as exc:
        logger.warning("Reset email non envoyé (%s) : %s", to_email, exc)


# ─────────────────────────────────────────────────────────────────────────────
# 6. POST /api/auth/reset-password — confirmer le reset
# ─────────────────────────────────────────────────────────────────────────────
@csrf_exempt
@require_http_methods(["POST"])
def api_auth_reset_password(request):
    try:
        payload = json.loads(request.body or b"{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)
    token = str(payload.get("token", "") or "").strip()
    new_password = str(payload.get("new_password", "") or "").strip()
    if not token or not new_password:
        return JsonResponse({"error": "token_and_new_password_required"}, status=400)
    if len(new_password) < 6:
        return JsonResponse({"error": "password_too_short"}, status=400)
    profile = (
        UserProfile.objects.filter(reset_token=token).select_related("user").first()
    )
    if not profile:
        return JsonResponse({"error": "invalid_token"}, status=400)
    # Vérifier expiration (30 min)
    if profile.reset_token_created_at:
        age = (timezone.now() - profile.reset_token_created_at).total_seconds()
        if age > 1800:
            return JsonResponse({"error": "token_expired"}, status=400)
    user = profile.user
    user.set_password(new_password)
    user.save()
    profile.reset_token = ""
    profile.reset_token_created_at = None
    profile.save(update_fields=["reset_token", "reset_token_created_at"])
    return JsonResponse(
        {"ok": True, "message": "Mot de passe réinitialisé avec succès."}
    )


# ─────────────────────────────────────────────────────────────────────────────
# 7. POST /api/auth/refresh — renouveler le token
# ─────────────────────────────────────────────────────────────────────────────
@csrf_exempt
@require_http_methods(["POST"])
def api_auth_refresh_token(request):
    refresh_token = ""
    try:
        payload = json.loads(request.body or b"{}")
    except json.JSONDecodeError:
        payload = {}

    refresh_token = str(payload.get("refresh", "") or "").strip()
    token_payload = verify_refresh_token(refresh_token) if refresh_token else None

    if not token_payload:
        auth_header = request.headers.get("Authorization", "")
        if not auth_header.startswith("Bearer "):
            return JsonResponse({"error": "missing_token"}, status=401)
        old_token = auth_header.split(" ", 1)[1].strip()
        token_payload = verify_token(old_token)
    if not token_payload:
        return JsonResponse({"error": "invalid_or_expired_token"}, status=401)
    uid = token_payload.get("uid")
    role = token_payload.get("role")
    new_token = create_token(uid, role)
    new_refresh = create_refresh_token(uid, role)
    return JsonResponse(
        {"token": new_token, "access": new_token, "refresh": new_refresh, "role": role}
    )


# ─────────────────────────────────────────────────────────────────────────────
# 8. GET /api/auth/verify-email/<token> — confirmer l'email
# ─────────────────────────────────────────────────────────────────────────────
@require_GET
def api_auth_verify_email(request, token):
    profile = (
        UserProfile.objects.filter(email_verify_token=token)
        .select_related("user")
        .first()
    )
    if not profile:
        return JsonResponse({"error": "invalid_token"}, status=400)
    profile.email_verified = True
    profile.email_verify_token = ""
    profile.save(update_fields=["email_verified", "email_verify_token"])
    return JsonResponse({"ok": True, "message": "Email vérifié avec succès."})


# ─────────────────────────────────────────────────────────────────────────────
# 9. DELETE /api/auth/delete-account — supprimer son compte (loi CI n°2013-450)
# ─────────────────────────────────────────────────────────────────────────────
@csrf_exempt
@require_http_methods(["DELETE"])
@require_api_auth(["client", "prestataire"])
def api_auth_delete_account(request):
    uid = request.api_user_id
    try:
        user = User.objects.get(id=uid)
    except User.DoesNotExist:
        return JsonResponse({"error": "user_not_found"}, status=404)

    try:
        payload = json.loads(request.body.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)

    confirmation = str(payload.get("confirmation", "")).strip().lower()
    if confirmation != "supprimer":
        return JsonResponse(
            {
                "error": "confirmation_required",
                "message": 'Envoyer {"confirmation": "supprimer"} pour confirmer',
            },
            status=400,
        )

    user.is_active = False
    user.save(update_fields=["is_active"])

    profile = getattr(user, "profile", None)
    if profile:
        profile.active = False
        profile.save(update_fields=["active"])

    DeviceToken.objects.filter(user=user).delete()
    Notification.objects.filter(user=user).delete()

    return JsonResponse({"ok": True, "message": "Compte supprimé avec succès."})


# ─────────────────────────────────────────────────────────────────────────────
# 9. PATCH /api/prestataire/profile — modifier profil
# ─────────────────────────────────────────────────────────────────────────────
@csrf_exempt
@require_http_methods(["PATCH", "GET"])
@require_api_auth(["prestataire", "admin"])
def api_prestataire_profile_update(request):
    uid = request.api_user_id
    try:
        provider = Provider.objects.get(user_id=uid)
    except Provider.DoesNotExist:
        return JsonResponse({"error": "provider_not_found"}, status=404)
    if request.method == "GET":
        return JsonResponse(
            {
                "id": provider.pk,
                "nom": provider.nom,
                "specialite": provider.specialite,
                "ville": provider.ville,
                "bio": provider.bio,
                "tarif_horaire": float(provider.tarif_horaire)
                if provider.tarif_horaire
                else None,
                "years_experience": provider.years_experience,
                "disponible": provider.disponible,
                "statut": provider.statut,
                "average_rating": provider.average_rating,
                "rating_count": provider.rating_count,
                "photo_portrait_url": provider.photo_portrait_url,
            }
        )
    # PATCH
    try:
        payload = json.loads(request.body or b"{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)
    update_fields = []
    allowed = {"nom", "specialite", "ville", "bio", "tarif_horaire", "years_experience"}
    for field in allowed:
        if field in payload and payload[field] is not None:
            val = payload[field]
            if field == "tarif_horaire":
                try:
                    val = float(val)
                    if val < 0:
                        continue
                except (TypeError, ValueError):
                    continue
            elif field == "years_experience":
                try:
                    val = int(val)
                    if val < 0:
                        continue
                except (TypeError, ValueError):
                    continue
            elif isinstance(val, str):
                val = val.strip()[:500]
            setattr(provider, field, val)
            update_fields.append(field)
    # Photo portrait — base64 → fichier sur disque
    portrait = payload.get("photo_portrait_url", "") or payload.get("photo_portrait_b64", "")
    if portrait and isinstance(portrait, str) and portrait.startswith("data:image/"):
        from .views import _decode_and_save_media
        saved = _decode_and_save_media(portrait, "portraits", "portrait")
        if saved:
            provider.photo_portrait_url = saved
            update_fields.append("photo_portrait_url")
    if update_fields:
        provider.save(update_fields=update_fields)
    return JsonResponse(
        {
            "ok": True,
            "updated": update_fields,
            "statut": provider.statut,
        }
    )


# ─────────────────────────────────────────────────────────────────────────────
# 10-12. Portfolio prestataire (galerie réalisations)
# ─────────────────────────────────────────────────────────────────────────────
@csrf_exempt
@require_http_methods(["GET", "POST"])
@require_api_auth(["prestataire", "admin"])
def api_prestataire_portfolio(request):
    uid = request.api_user_id
    try:
        provider = Provider.objects.get(user_id=uid)
    except Provider.DoesNotExist:
        return JsonResponse({"error": "provider_not_found"}, status=404)
    if request.method == "GET":
        photos = provider.portfolio_photos or []
        return JsonResponse({"photos": photos, "count": len(photos)})
    # POST — ajouter une photo
    try:
        payload = json.loads(request.body or b"{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)
    photo = str(payload.get("photo", "") or "").strip()
    caption = str(payload.get("caption", "") or "").strip()[:200]
    if not photo or not photo.startswith("data:image/"):
        return JsonResponse({"error": "photo_data_url_required"}, status=400)
    if len(photo) > 800_000:
        return JsonResponse({"error": "photo_too_large"}, status=400)
    photos = list(provider.portfolio_photos or [])
    if len(photos) >= 12:
        return JsonResponse({"error": "max_12_photos"}, status=400)
    # Sauvegarder l'image sur disque plutôt qu'en base64 en DB
    from .views import _decode_and_save_media
    photo_url = _decode_and_save_media(photo, f"portfolio/{provider.id}", "realisation")
    if not photo_url:
        photo_url = photo  # fallback base64 si échec
    entry = {"photo": photo_url, "caption": caption, "added_at": timezone.now().isoformat()}
    photos.append(entry)
    provider.portfolio_photos = photos
    provider.save(update_fields=["portfolio_photos"])
    return JsonResponse({"ok": True, "count": len(photos), "photo_url": photo_url})


@csrf_exempt
@require_http_methods(["DELETE"])
@require_api_auth(["prestataire", "admin"])
def api_prestataire_portfolio_delete(request, idx):
    uid = request.api_user_id
    try:
        provider = Provider.objects.get(user_id=uid)
    except Provider.DoesNotExist:
        return JsonResponse({"error": "provider_not_found"}, status=404)
    photos = list(provider.portfolio_photos or [])
    try:
        photos.pop(int(idx))
    except (IndexError, ValueError):
        return JsonResponse({"error": "invalid_index"}, status=400)
    provider.portfolio_photos = photos
    provider.save(update_fields=["portfolio_photos"])
    return JsonResponse({"ok": True, "count": len(photos)})


# ─────────────────────────────────────────────────────────────────────────────
# 13. POST /api/prestataire/reservations/<ref>/rate-client — noter le client
# ─────────────────────────────────────────────────────────────────────────────
@csrf_exempt
@require_http_methods(["GET", "POST"])
@require_api_auth(["prestataire", "admin"])
def api_prestataire_rate_client(request, reference):
    uid = request.api_user_id
    try:
        res = Reservation.objects.get(reference=reference)
    except Reservation.DoesNotExist:
        return JsonResponse({"error": "not_found"}, status=404)
    if request.api_role != "admin" and res.prestataire_user_id != uid:
        prov = Provider.objects.filter(user_id=uid).first()
        if not prov or res.assigned_provider_id != prov.pk:
            return JsonResponse({"error": "forbidden"}, status=403)
    if res.statut != "Terminee":
        return JsonResponse({"error": "reservation_not_completed"}, status=400)
    if request.method == "GET":
        existing = ClientRating.objects.filter(reservation=res).first()
        if existing:
            return JsonResponse(
                {
                    "rated": True,
                    "note": existing.note,
                    "commentaire": existing.commentaire,
                }
            )
        return JsonResponse({"rated": False})
    # POST
    if ClientRating.objects.filter(reservation=res).exists():
        return JsonResponse({"error": "already_rated"}, status=400)
    try:
        payload = json.loads(request.body or b"{}")
        note = int(payload.get("note", 0))
    except (json.JSONDecodeError, TypeError, ValueError):
        return JsonResponse({"error": "invalid_json"}, status=400)
    if note < 1 or note > 5:
        return JsonResponse({"error": "note_1_to_5"}, status=400)
    commentaire = str(payload.get("commentaire", "") or "")[:1000]
    ClientRating.objects.create(
        reservation=res,
        prestataire_user_id=uid,
        client_user=res.client_user,
        note=note,
        commentaire=commentaire,
    )
    return JsonResponse({"ok": True})


# ─────────────────────────────────────────────────────────────────────────────
# 14. GET /api/client/notifications — liste notifications persistantes
# ─────────────────────────────────────────────────────────────────────────────
@require_GET
@require_api_auth(["client", "prestataire", "admin"])
def api_user_notifications(request):
    uid = request.api_user_id
    qs = Notification.objects.filter(user_id=uid).order_by("-created_at")[:50]
    data = [
        {
            "id": n.pk,
            "title": n.title,
            "body": n.body,
            "type": n.notif_type,
            "reference": n.reference,
            "lu": n.lu,
            "created_at": n.created_at.isoformat(),
        }
        for n in qs
    ]
    return JsonResponse(
        {"notifications": data, "unread": sum(1 for n in data if not n["lu"])}
    )


@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["client", "prestataire", "admin"])
def api_user_notifications_mark_read(request):
    uid = request.api_user_id
    try:
        payload = json.loads(request.body or b"{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)
    ids = payload.get("ids", [])
    if ids:
        Notification.objects.filter(pk__in=ids, user_id=uid).update(lu=True)
    else:
        Notification.objects.filter(user_id=uid, lu=False).update(lu=True)
    return JsonResponse({"ok": True})


# ─────────────────────────────────────────────────────────────────────────────
# 15. POST /api/admin/push-broadcast — push manuelle vers tous les users
# ─────────────────────────────────────────────────────────────────────────────
@csrf_exempt
@require_http_methods(["POST"])
def api_admin_push_broadcast(request):
    from django.contrib.auth.decorators import login_required

    if not (request.user and request.user.is_authenticated and request.user.is_staff):
        return JsonResponse({"error": "admin_required"}, status=403)
    try:
        payload = json.loads(request.body or b"{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)
    title = str(payload.get("title", "") or "").strip()
    body = str(payload.get("body", "") or "").strip()
    target_role = (
        str(payload.get("role", "") or "").strip().lower()
    )  # '', 'client', 'prestataire'
    if not title or not body:
        return JsonResponse({"error": "title_and_body_required"}, status=400)
    qs = DeviceToken.objects.select_related("user")
    if target_role in ("client", "prestataire"):
        qs = qs.filter(user__profile__role=target_role)
    user_ids = list(qs.values_list("user_id", flat=True).distinct())
    if user_ids:
        _schedule(
            user_ids=user_ids,
            title=title,
            body=body,
            data={"type": "broadcast", "role": target_role},
        )
    # Créer une notification persistante pour chaque user ciblé
    notifs = [
        Notification(
            title=title,
            body=body,
            notif_type="broadcast",
            user_id=uid,
        )
        for uid in user_ids
    ]
    Notification.objects.bulk_create(notifs, ignore_conflicts=True)
    return JsonResponse({"ok": True, "sent_to": len(user_ids)})


# ─────────────────────────────────────────────────────────────────────────────
# 16. GET /api/client/prestataires/<id>/portfolio — galerie publique
# ─────────────────────────────────────────────────────────────────────────────
@require_GET
def api_provider_portfolio_public(request, provider_id):
    try:
        provider = Provider.objects.get(pk=provider_id, statut=Provider.Status.VALID)
    except Provider.DoesNotExist:
        return JsonResponse({"error": "not_found"}, status=404)
    photos = [
        {"photo": p.get("photo", ""), "caption": p.get("caption", "")}
        for p in (provider.portfolio_photos or [])
    ]
    return JsonResponse({"provider_id": provider_id, "photos": photos})


# ─────────────────────────────────────────────────────────────────────────────
# Modèles inline pour ClientRating (note prestataire → client)
# Ces classes sont utilisées ici directement sans migration séparée
# (voir models_v2.py pour la définition complète)
# ─────────────────────────────────────────────────────────────────────────────


def _get_client_rating_model():
    """Lazy import pour éviter les imports circulaires."""
    from .models_v2 import ClientRating

    return ClientRating


# Patch pour la vue rate-client
ClientRating = None


def _init_client_rating():
    global ClientRating
    try:
        from .models_v2 import ClientRating as CR

        ClientRating = CR
    except ImportError:
        pass


_init_client_rating()
