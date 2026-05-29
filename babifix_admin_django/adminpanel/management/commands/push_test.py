"""
Diagnostic et test des notifications push (FCM).

Usage :
  python manage.py push_test                 → affiche l'état de la configuration FCM
  python manage.py push_test --user 5        → envoie une notif de test à l'utilisateur 5
  python manage.py push_test --user 5 --title "Coucou" --body "Test BABIFIX"
"""
from django.core.management.base import BaseCommand

from adminpanel.fcm_backend import firebase_status, send_push_to_user_ids
from adminpanel.models import DeviceToken


class Command(BaseCommand):
    help = "Diagnostique la configuration FCM et envoie une notification de test."

    def add_arguments(self, parser):
        parser.add_argument("--user", type=int, default=None, help="ID utilisateur destinataire")
        parser.add_argument("--title", type=str, default="BABIFIX — Test push")
        parser.add_argument("--body", type=str, default="Si vous voyez ceci, les push fonctionnent ✅")

    def handle(self, *args, **opts):
        st = firebase_status()
        self.stdout.write(self.style.MIGRATE_HEADING("== Configuration FCM =="))
        self.stdout.write(f"  SDK firebase-admin installé : {st['sdk_installed']}")
        self.stdout.write(f"  Variable d'env définie       : {st['credentials_env_set']}")
        self.stdout.write(f"  Fichier de clé existe        : {st['credentials_file_exists']}")
        self.stdout.write(f"  Chemin                       : {st['credentials_path'] or '(non défini)'}")
        ready = st["ready"]
        self.stdout.write(
            self.style.SUCCESS("  -> FCM PRET (les push peuvent partir)")
            if ready
            else self.style.ERROR(
                "  -> FCM NON CONFIGURE : definissez FIREBASE_CREDENTIALS_JSON_PATH "
                "vers le JSON de compte de service Firebase."
            )
        )

        total_tokens = DeviceToken.objects.count()
        self.stdout.write(f"\n  Appareils enregistrés (total) : {total_tokens}")
        if total_tokens == 0:
            self.stdout.write(
                self.style.WARNING(
                    "  Aucun appareil : ouvrez l'app mobile, connectez-vous et acceptez "
                    "les notifications pour enregistrer un token."
                )
            )

        user_id = opts.get("user")
        if not user_id:
            self.stdout.write("\nAjoutez --user <id> pour envoyer une notification de test.")
            return

        n = DeviceToken.objects.filter(user_id=user_id).count()
        self.stdout.write(f"\n== Envoi de test à l'utilisateur {user_id} ({n} appareil(s)) ==")
        result = send_push_to_user_ids(
            [user_id], opts["title"], opts["body"], {"type": "test", "route": "/"}
        )
        self.stdout.write(str(result))
        if result.get("sent"):
            self.stdout.write(self.style.SUCCESS(f"OK: {result['sent']} notification(s) envoyee(s)."))
        else:
            self.stdout.write(self.style.ERROR(f"ECHEC: rien envoye - raison : {result.get('reason')}"))
