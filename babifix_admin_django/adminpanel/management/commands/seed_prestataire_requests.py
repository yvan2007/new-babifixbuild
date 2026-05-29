"""Seed demo requests for Flutter prestataire app testing."""

from decimal import Decimal

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand
from adminpanel.models import Provider, Reservation, Payment


class Command(BaseCommand):
    help = "Seed demo requests for prestataire app testing"

    def handle(self, *args, **options):
        User = get_user_model()

        # Get the prestataire user
        provider = Provider.objects.filter(user__username="horzonzh").first()
        if not provider:
            self.stdout.write(self.style.WARNING("[--] Prestataire horzonzh not found"))
            return

        requests = [
            {
                "reference": "DEMO-REQ-001",
                "client": "Akouabi Paul",
                "prestataire": provider.nom,
                "montant": Decimal("25000.00"),
                "statut": Reservation.Status.DEMANDE_ENVOYEE,
                "title": "Fuite d eau importante",
            },
            {
                "reference": "DEMO-REQ-002",
                "client": "Bamba Claire",
                "prestataire": provider.nom,
                "montant": Decimal("15000.00"),
                "statut": Reservation.Status.DEVIS_ENVOYE,
                "title": "Robinet qui fuit",
            },
            {
                "reference": "DEMO-REQ-003",
                "client": "Coulibaly Thomas",
                "prestataire": provider.nom,
                "montant": Decimal("0.00"),
                "statut": Reservation.Status.IN_PROGRESS,
                "title": "Debouchage canalisation",
            },
            {
                "reference": "DEMO-REQ-004",
                "client": "Kouassi Marie",
                "prestataire": provider.nom,
                "montant": Decimal("35000.00"),
                "statut": Reservation.Status.DEVIS_ACCEPTE,
                "title": "Remplacement chauffe-eau",
            },
            {
                "reference": "DEMO-REQ-005",
                "client": "Doumbia Awa",
                "prestataire": provider.nom,
                "montant": Decimal("12000.00"),
                "statut": Reservation.Status.DONE,
                "title": "Petite reparation",
            },
        ]

        count = 0
        for data in requests:
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

                # Create payment for completed/reserved ones
                if data["statut"] in [
                    Reservation.Status.DONE,
                    Reservation.Status.DEVIS_ACCEPTE,
                ]:
                    Payment.objects.get_or_create(
                        reference=f"PAY-{data['reference']}",
                        defaults={
                            "client": data["client"],
                            "prestataire": provider.nom,
                            "montant": data["montant"],
                            "commission": data["montant"] * Decimal("0.18"),
                            "etat": Payment.State.PENDING,
                        },
                    )
            else:
                self.stdout.write(f"[--] Exists: {data['reference']}")

        self.stdout.write(
            self.style.SUCCESS(
                f"\n[OK] {count} demo requests created for {provider.nom}"
            )
        )
