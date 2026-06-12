"""
Relances email BABIFIX — à lancer périodiquement (cron quotidien).

  python manage.py send_reminders

Envoie :
  1. Prestataires inactifs (pas de connexion depuis ~7 jours) → « Revenez ».
  2. Devis en attente (ENVOYE depuis ~2 jours, sans réponse) → relance le CLIENT.
  3. Demandes sans devis (DEMANDE_ENVOYEE depuis ~1 jour) → relance le PRESTATAIRE.

Anti-spam : on utilise une fenêtre temporelle (1 jour) pour qu'un même
élément ne soit relancé qu'une fois (en supposant un cron quotidien).
"""
from datetime import timedelta

from django.core.management.base import BaseCommand
from django.utils import timezone

from adminpanel.models import Devis, Reservation, UserProfile


def _send(to_email, subject, intro, cta_label, cta_note):
    if not to_email:
        return False
    try:
        from adminpanel.views_extra import send_babifix_email_html
    except Exception:
        return False
    html = f"""
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#eef2f7;font-family:Arial,sans-serif;">
      <tr><td align="center" style="padding:24px 12px;">
        <table role="presentation" width="560" cellpadding="0" cellspacing="0" style="max-width:560px;width:100%;background:#fff;border-radius:16px;overflow:hidden;">
          <tr><td align="center" bgcolor="#0B1B34" style="background:#0B1B34;padding:28px;">
            <img src="https://new-babifixbuild.onrender.com/static/adminpanel/logo_babifix.png" alt="BABIFIX" width="56" height="56" style="border-radius:12px;display:block;margin-bottom:10px;">
            <div style="color:#4CC9F0;font-weight:bold;font-size:20px;letter-spacing:2px;">BABIFIX</div>
          </td></tr>
          <tr><td style="padding:30px;color:#1a1a2e;">
            <p style="font-size:15px;line-height:1.6;color:#475569;margin:0 0 22px;">{intro}</p>
            <div style="text-align:center;margin:8px 0 6px;">
              <span style="display:inline-block;background:#4CC9F0;color:#0B1B34;font-weight:bold;padding:13px 30px;border-radius:12px;font-size:15px;">{cta_label}</span>
            </div>
            <p style="font-size:12px;color:#94a3b8;text-align:center;margin:8px 0 0;">{cta_note}</p>
          </td></tr>
          <tr><td align="center" bgcolor="#0B1B34" style="background:#0B1B34;padding:18px;color:#94a3b8;font-size:11px;">
            © 2026 BABIFIX · Abidjan, Côte d'Ivoire
          </td></tr>
        </table>
      </td></tr>
    </table>
    """
    try:
        send_babifix_email_html(to_email=to_email, subject=subject, html_content=html)
        return True
    except Exception:
        return False


class Command(BaseCommand):
    help = "Envoie les relances email (prestataires inactifs, devis en attente, demandes sans devis)."

    def handle(self, *args, **options):
        now = timezone.now()
        sent = {"inactive": 0, "devis": 0, "demande": 0}

        # ── 1. Prestataires inactifs (last_login dans la fenêtre 7-8 jours) ──
        lo, hi = now - timedelta(days=8), now - timedelta(days=7)
        inactive = UserProfile.objects.filter(
            role=UserProfile.Role.PRESTATAIRE,
            active=True,
            user__is_active=True,
            user__last_login__gte=lo,
            user__last_login__lt=hi,
        ).select_related("user")
        for prof in inactive:
            if _send(
                prof.user.email,
                "BABIFIX — De nouvelles missions vous attendent",
                "Cela fait quelques jours qu'on ne vous a pas vu sur BABIFIX. "
                "Des clients recherchent des prestataires comme vous — "
                "reconnectez-vous pour ne manquer aucune demande.",
                "Ouvrir BABIFIX Pro",
                "Plus vous êtes actif, plus vous recevez de missions.",
            ):
                sent["inactive"] += 1

        # ── 2. Devis en attente (ENVOYE depuis 2-3 jours) → relance le client ──
        lo, hi = now - timedelta(days=3), now - timedelta(days=2)
        devis_qs = Devis.objects.filter(
            statut=Devis.Statut.ENVOYE, created_at__gte=lo, created_at__lt=hi
        ).select_related("reservation", "reservation__client_user")
        for d in devis_qs:
            res = d.reservation
            client = getattr(res, "client_user", None) if res else None
            if client and client.email and _send(
                client.email,
                "BABIFIX — Un devis attend votre réponse",
                "Un prestataire vous a envoyé un devis sur BABIFIX et attend "
                "votre décision. Acceptez-le pour planifier votre intervention, "
                "ou répondez directement dans l'application.",
                "Voir mon devis",
                "Référence : " + (res.reference if res else ""),
            ):
                sent["devis"] += 1

        # ── 3. Demandes sans devis (DEMANDE_ENVOYEE depuis 1-2 jours) → presta ──
        lo, hi = now - timedelta(days=2), now - timedelta(days=1)
        demandes = Reservation.objects.filter(
            statut="DEMANDE_ENVOYEE", created_at__gte=lo, created_at__lt=hi
        ).select_related("prestataire_user")
        for res in demandes:
            presta = getattr(res, "prestataire_user", None)
            if presta and presta.email and _send(
                presta.email,
                "BABIFIX — Une demande attend votre devis",
                "Un client vous a envoyé une demande sur BABIFIX. "
                "Envoyez-lui votre devis rapidement pour augmenter vos chances "
                "de décrocher la mission.",
                "Répondre à la demande",
                "Référence : " + res.reference,
            ):
                sent["demande"] += 1

        self.stdout.write(self.style.SUCCESS(
            f"Relances envoyées — inactifs: {sent['inactive']}, "
            f"devis: {sent['devis']}, demandes: {sent['demande']}"
        ))
