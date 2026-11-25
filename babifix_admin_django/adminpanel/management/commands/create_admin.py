import os

from django.contrib.auth.models import User
from django.core.management.base import BaseCommand


class Command(BaseCommand):
    help = "Cree un superuser depuis les variables d'environnement DJANGO_SUPERUSER_EMAIL et DJANGO_SUPERUSER_PASSWORD"

    def handle(self, *args, **options):
        email = os.environ.get("DJANGO_SUPERUSER_EMAIL")
        password = os.environ.get("DJANGO_SUPERUSER_PASSWORD")

        if not email or not password:
            self.stderr.write(
                self.style.ERROR(
                    "ERREUR: Definissez DJANGO_SUPERUSER_EMAIL et DJANGO_SUPERUSER_PASSWORD dans votre .env"
                )
            )
            return

        if User.objects.filter(email=email).exists():
            self.stdout.write(self.style.WARNING(f"Admin {email} existe deja : aucune action."))
            return

        username = email.split("@")[0][:150]
        User.objects.create_superuser(
            username=username,
            email=email,
            password=password,
        )
        self.stdout.write(self.style.SUCCESS(f"Superuser cree: {email}"))
