"""Seed users for Flutter apps."""

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand
from adminpanel.models import Provider, Client, UserProfile, Category


class Command(BaseCommand):
    help = "Seed demo users for Flutter client/prestataire apps"

    def handle(self, *args, **options):
        User = get_user_model()

        # Client: kouayavana18@gmail.com
        client_user, created = User.objects.get_or_create(
            username="kouayavana18",
            defaults={"email": "kouayavana18@gmail.com", "is_active": True},
        )
        if created:
            client_user.set_password("client123")
            client_user.save()
            self.stdout.write(f"[OK] Created user: kouayavana18")

        UserProfile.objects.get_or_create(
            user=client_user,
            defaults={"role": "client", "active": True, "phone_e164": "+2250700000000"},
        )

        Client.objects.get_or_create(
            email="kouayavana18@gmail.com",
            defaults={"nom": "Kouayavana A", "ville": "Abidjan", "reservations": 0},
        )

        # Prestataire: horzonzh@gmail.com
        prest_user, created = User.objects.get_or_create(
            username="horzonzh",
            defaults={"email": "horzonzh@gmail.com", "is_active": True},
        )
        if created:
            prest_user.set_password("prest123")
            prest_user.save()
            self.stdout.write(f"[OK] Created user: horzonzh")

        UserProfile.objects.get_or_create(
            user=prest_user,
            defaults={
                "role": "prestataire",
                "active": True,
                "phone_e164": "+2250700000001",
            },
        )

        # Get a category for the provider
        cat = Category.objects.filter(actif=True).first()

        Provider.objects.get_or_create(
            user=prest_user,
            defaults={
                "nom": "Hortonzou H",
                "specialite": "Plomberie & depannage sanitaire",
                "ville": "Abidjan - Cocody",
                "tarif_horaire": 8000,
                "statut": Provider.Status.VALID,
                "bio": "Plombier expert depuis 5 ans. Intervention rapide 7j/7.",
                "category": cat,
            },
        )

        self.stdout.write(
            self.style.SUCCESS("\n[OK] Demo users seeded for Flutter apps!")
        )
        self.stdout.write("  Client app:       kouayavana18 / client123")
        self.stdout.write("  Prestataire app:  horzonzh / prest123")
