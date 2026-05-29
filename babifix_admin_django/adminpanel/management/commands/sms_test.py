"""
Test du service SMS / code de verification.

Usage :
  python manage.py sms_test                                  -> etat fournisseur
  python manage.py sms_test --phone +2250700000000 --msg "Bonjour"
  python manage.py sms_test --email test@babifix.ci --code   -> envoie un code par e-mail
"""
import os

from django.core.management.base import BaseCommand

from adminpanel.services import sms_service


class Command(BaseCommand):
    help = "Teste l'envoi SMS / code de verification (gratuit en mode console)."

    def add_arguments(self, parser):
        parser.add_argument("--phone", type=str, default=None)
        parser.add_argument("--email", type=str, default=None)
        parser.add_argument("--msg", type=str, default="Test BABIFIX SMS")
        parser.add_argument("--code", action="store_true", help="Envoyer un code de verification")

    def handle(self, *args, **opts):
        provider = os.getenv("SMS_PROVIDER", "console")
        self.stdout.write(self.style.MIGRATE_HEADING("== Service SMS =="))
        self.stdout.write(f"  Fournisseur (SMS_PROVIDER) : {provider}")
        self.stdout.write("  (console = gratuit, journalise ; whatsapp/twilio/orange = via cles env)")

        if opts["code"]:
            code = sms_service.generate_code()
            res = sms_service.send_verification_code(
                code, phone=opts["phone"], email=opts["email"]
            )
            self.stdout.write(f"\n  Code genere : {code}")
            self.stdout.write(f"  Resultat    : {res}")
            return

        if opts["phone"]:
            res = sms_service.send_sms(opts["phone"], opts["msg"])
            self.stdout.write(f"\n  Resultat : {res}")
        else:
            self.stdout.write("\n  Ajoutez --phone <num> [--msg ...] ou --email <mail> --code.")
