"""Seed demo reservations for Flutter client app."""

from decimal import Decimal

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand
from adminpanel.models import Client, Provider, Reservation


class Command(BaseCommand):
    help = "Seed demo reservations for client app testing"

    def handle(self, *args, **options):
        User = get_user_model()

        # Le Client (table profil) — on identifie par email.
        client_email = "kouayavana18@gmail.com"
        client = Client.objects.filter(email=client_email).first()
        if not client:
            self.stdout.write(self.style.WARNING(
                f"[--] Client {client_email} not found"
            ))
            return

        # L'User (auth Django) lié — indispensable pour que les endpoints
        # client filtrant par `reservation.client_user_id == request.api_user_id`
        # renvoient bien ces résas (sinon → 403).
        client_user = User.objects.filter(email=client_email).first()
        if not client_user:
            self.stdout.write(self.style.ERROR(
                f"[KO] User auth pour {client_email} introuvable. "
                "Crée d'abord le compte via l'app ou la signup."
            ))
            return

        # Lier les prestataires si possible (FK assigned_provider).
        # Sinon on garde juste le champ texte `prestataire`.
        def _find_provider(nom: str):
            return Provider.objects.filter(nom__iexact=nom).first()

        reservations = [
            {
                "reference": "DEMO-RES-001",
                "prestataire_name": "Kone Mariam",
                "montant": Decimal("15000.00"),
                "statut": Reservation.Status.DONE,
                "title": "Menage complet appartement",
            },
            {
                "reference": "DEMO-RES-002",
                "prestataire_name": "Fofana Ibrahim",
                "montant": Decimal("25000.00"),
                "statut": Reservation.Status.DEVIS_ENVOYE,
                "title": "Installation electrique bureau",
            },
            {
                "reference": "DEMO-RES-003",
                "prestataire_name": "Konan Jean",
                "montant": Decimal("8000.00"),
                "statut": Reservation.Status.IN_PROGRESS,
                "title": "Petit menage hebdomadaire",
            },
            {
                "reference": "DEMO-RES-004",
                "prestataire_name": "TRAORE Amara",
                "montant": Decimal("45000.00"),
                "statut": Reservation.Status.WAITING_CLIENT,
                "title": "Installation climatiseur split",
            },
        ]

        count = 0
        for data in reservations:
            prov = _find_provider(data["prestataire_name"])
            defaults = {
                "client": client.nom,
                "client_user": client_user,  # FK indispensable
                "prestataire": data["prestataire_name"],
                "montant": data["montant"],
                "statut": data["statut"],
                "title": data["title"],
            }
            if prov:
                defaults["assigned_provider"] = prov
                if prov.user_id:
                    defaults["prestataire_user_id"] = prov.user_id

            obj, created = Reservation.objects.get_or_create(
                reference=data["reference"],
                defaults=defaults,
            )

            # MISE À JOUR si la FK manquait (cas seed historique).
            updated_fields = []
            if obj.client_user_id != client_user.id:
                obj.client_user = client_user
                updated_fields.append("client_user")
            if prov and obj.assigned_provider_id != prov.id:
                obj.assigned_provider = prov
                updated_fields.append("assigned_provider")
            if updated_fields:
                obj.save(update_fields=updated_fields)
                self.stdout.write(f"[FIX] {data['reference']}: {updated_fields}")

            if created:
                count += 1
                self.stdout.write(f"[OK] Created: {data['reference']}")
            elif not updated_fields:
                self.stdout.write(f"[--] Exists: {data['reference']}")

        self.stdout.write(self.style.SUCCESS(
            f"\n[OK] {count} demo reservations created"
        ))
        self.stdout.write(
            f"[OK] Total reservations linked to {client_user.email}: "
            f"{Reservation.objects.filter(client_user=client_user).count()}"
        )
