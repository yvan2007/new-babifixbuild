"""
Watcher GeniusPay — ping toutes les N minutes pour détecter le retour
de la sandbox après maintenance, puis notifier (console + Notification
système + log).

Usage :
    python manage.py watch_geniuspay --interval 300

L'option --interval est en secondes (défaut 300 = 5 min). Au retour de
l'API, le script :
  1. Logue le timestamp en ASCII art dans le terminal
  2. Crée une Notification BABIFIX visible dans le panel admin
  3. Optionnel : envoie un email de notif si EMAIL_ADMIN configuré
"""
import time
import logging
import os
from datetime import datetime
from django.core.management.base import BaseCommand
from django.conf import settings

logger = logging.getLogger(__name__)


class Command(BaseCommand):
    help = "Surveille la sandbox GeniusPay et notifie son retour."

    def add_arguments(self, parser):
        parser.add_argument(
            "--interval",
            type=int,
            default=300,
            help="Intervalle entre 2 pings (secondes). Défaut : 300.",
        )
        parser.add_argument(
            "--mode",
            choices=["sandbox", "live"],
            default="sandbox",
            help="Cible à surveiller. Défaut : sandbox.",
        )
        parser.add_argument(
            "--max-iterations",
            type=int,
            default=0,
            help="Nombre max de pings (0 = infini). Défaut : 0.",
        )

    def handle(self, *args, **opts):
        import urllib.request
        import urllib.error

        interval = max(30, opts["interval"])
        max_iter = opts["max_iterations"]
        mode = opts["mode"]

        url = "https://pay.genius.ci/api/v1/merchant/balance"
        pk = os.getenv(
            "GENIUSPAY_PUBLIC_KEY",
            getattr(settings, "GENIUSPAY_PUBLIC_KEY", ""),
        )
        sk = os.getenv(
            "GENIUSPAY_SECRET_KEY",
            getattr(settings, "GENIUSPAY_SECRET_KEY", ""),
        )

        is_sandbox_key = pk.startswith("pk_sandbox_")
        if mode == "sandbox" and not is_sandbox_key:
            self.stdout.write(self.style.WARNING(
                "⚠️  Vos clés en .env sont 'live' mais vous surveillez la "
                "sandbox. Le test va échouer en 401 même si la sandbox "
                "fonctionne."
            ))

        self.stdout.write("=" * 70)
        self.stdout.write(self.style.NOTICE(
            f"  GENIUSPAY WATCHER — mode={mode}  interval={interval}s"
        ))
        self.stdout.write(self.style.NOTICE(
            f"  Endpoint : {url}"
        ))
        self.stdout.write(self.style.NOTICE(
            f"  Démarré à {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
        ))
        self.stdout.write("=" * 70)
        self.stdout.write("")

        iteration = 0
        last_status = None
        consecutive_503 = 0

        while max_iter == 0 or iteration < max_iter:
            iteration += 1
            now = datetime.now().strftime("%H:%M:%S")

            try:
                req = urllib.request.Request(
                    url,
                    headers={
                        "X-API-Key": pk,
                        "X-API-Secret": sk,
                        "Accept": "application/json",
                    },
                )
                resp = urllib.request.urlopen(req, timeout=10)
                status = resp.getcode()
                ctype = resp.headers.get("Content-Type", "")
                body_head = resp.read(200).decode(errors="replace")
                resp.close()
            except urllib.error.HTTPError as e:
                status = e.code
                ctype = e.headers.get("Content-Type", "") if e.headers else ""
                body_head = e.read(200).decode(errors="replace") if e else ""
            except Exception as e:
                status = -1
                ctype = ""
                body_head = f"EXC: {e}"

            is_json = "json" in (ctype or "").lower()
            is_html = "html" in (ctype or "").lower()
            is_back = status == 200 or (status in (401, 403) and is_json)

            if is_back and last_status not in (None, status):
                self._notify_back(status, ctype, body_head)
                # Reset compteur
                consecutive_503 = 0
            elif status == 503 or is_html:
                consecutive_503 += 1

            # Affichage compact
            badge = self.style.SUCCESS("● UP    ") if is_back else \
                    self.style.WARNING(" 503    ") if status == 503 else \
                    self.style.ERROR("  KO    ")
            self.stdout.write(
                f"[{now}] iter #{iteration:4d}  {badge}  status={status:3d}  "
                f"ctype={(ctype or '-')[:30]:30s}  body={body_head[:60]}"
            )

            last_status = status

            if max_iter and iteration >= max_iter:
                break

            try:
                time.sleep(interval)
            except KeyboardInterrupt:
                self.stdout.write("\n  Interrompu par l'utilisateur.")
                break

        self.stdout.write("")
        self.stdout.write(self.style.NOTICE(
            f"Total: {iteration} pings  /  {consecutive_503} 503 consécutifs"
        ))

    def _notify_back(self, status, ctype, body_head):
        """Émet une notification (et tente un email si configuré)."""
        from adminpanel.models import Notification
        from django.contrib.auth.models import User

        self.stdout.write("")
        self.stdout.write("=" * 70)
        self.stdout.write(self.style.SUCCESS(
            "🎉  GENIUSPAY EST DE NOUVEAU EN LIGNE !"
        ))
        self.stdout.write(self.style.SUCCESS(
            f"    HTTP {status}  |  Content-Type: {ctype}"
        ))
        self.stdout.write("=" * 70)

        # Crée des notifs admin pour les superusers
        try:
            admins = User.objects.filter(is_superuser=True)
            for a in admins:
                Notification.objects.create(
                    user=a,
                    title="✅ GeniusPay sandbox revenue en ligne",
                    body=f"L'API GeniusPay répond à nouveau (HTTP {status}). "
                         "Vous pouvez relancer les tests Mobile Money.",
                    notif_type="system",
                    reference="GENIUSPAY_BACK",
                )
            self.stdout.write(self.style.SUCCESS(
                f"  {admins.count()} admin(s) notifié(s)"
            ))
        except Exception as exc:
            logger.warning("notify_back failed: %s", exc)

        # Email optionnel
        try:
            from django.core.mail import send_mail
            email = os.getenv("EMAIL_ADMIN") or getattr(
                settings, "EMAIL_ADMIN", "")
            if email:
                send_mail(
                    "✅ GeniusPay sandbox de retour",
                    f"L'API GeniusPay vient de répondre à nouveau "
                    f"(HTTP {status}, Content-Type: {ctype}).\n\n"
                    "Relancez vos tests Mobile Money quand vous le pouvez.\n\n"
                    "— BABIFIX Watcher",
                    None,
                    [email],
                    fail_silently=True,
                )
                self.stdout.write(self.style.SUCCESS(
                    f"  Email envoyé à {email}"
                ))
        except Exception:
            pass
