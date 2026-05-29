"""Seed demo reservations for Flutter client app."""

from decimal import Decimal

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand
from adminpanel.models import Client, Provider, Reservation


class Command(BaseCommand):
    help = "Seed demo reservations for client app testing"

    def handle(self, *args, **options):
        User = get_user_model()

        # Get the client user
        client = Client.objects.filter(email="kouayavana18@gmail.com").first()
        if not client:
            self.stdout.write(self.style.WARNING("[--] Client kouayavana18 not found"))
            return

        reservations = [
            {
                "reference": "DEMO-RES-001",
                "client": client.nom,
                "prestataire": "Kone Mariam",
                "montant": Decimal("15000.00"),
                "statut": Reservation.Status.DONE,
                "title": "Menage complet appartement",
            },
            {
                "reference": "DEMO-RES-002",
                "client": client.nom,
                "prestataire": "Fofana Ibrahim",
                "montant": Decimal("25000.00"),
                "statut": Reservation.Status.DEVIS_ENVOYE,
                "title": "Installation electrique bureau",
            },
            {
                "reference": "DEMO-RES-003",
                "client": client.nom,
                "prestataire": "Konan Jean",
                "montant": Decimal("8000.00"),
                "statut": Reservation.Status.IN_PROGRESS,
                "title": "Petit menage hebdomadaire",
            },
            {
                "reference": "DEMO-RES-004",
                "client": client.nom,
                "prestataire": "TRAORE Amara",
                "montant": Decimal("45000.00"),
                "statut": Reservation.Status.WAITING_CLIENT,
                "title": "Installation climatiseur split",
            },
        ]

        count = 0
        for data in reservations:
            obj, created = Reservation.objects.get_or_create(
                reference=data["reference"],
                defaults={
                    "client": data["client"],
                    "prestataire": data["prestataire"],
                    "montant": data["montant"],
                    "statut": data["statut"],
                    "title": data["title"],
                },
            )
            if created:
                count += 1
                self.stdout.write(f"[OK] Created: {data['reference']}")
            else:
                self.stdout.write(f"[--] Exists: {data['reference']}")

        self.stdout.write(
            self.style.SUCCESS(f"\n[OK] {count} demo reservations created")
        )
        self.stdout.write(
            f"[OK] Total reservations for {client.nom}: {Reservation.objects.filter(client=client.nom).count()}"
        )
