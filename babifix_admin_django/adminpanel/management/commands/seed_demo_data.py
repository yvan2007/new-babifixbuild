"""
Usage: python manage.py seed_demo_data

Crée des données de démo pour tester BABIFIX:
- Comptes utilisateurs (client, prestataire, admin)
- Prestataires avec categories
- Reservations avec differents statuts
- Clients
- Payments
- Notifications
- Categories (deja importees via import_babifix_categories)
"""

from decimal import Decimal

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand

from adminpanel.models import (
    Category,
    Client,
    Notification,
    Payment,
    Provider,
    Reservation,
    SystemSetting,
    UserProfile,
)


class Command(BaseCommand):
    help = "Seed demo data for testing (clients, prestataires, reservations, etc.)"

    def handle(self, *args, **options):
        User = get_user_model()

        # ── System settings ────────────────────────────────────────────────
        SystemSetting.objects.get_or_create(pk=1)

        self.stdout.write("[OK] System settings")

        # ── Demo users ─────────────────────────────────────────────────────
        demo_accounts = [
            ("client_demo", "client123", UserProfile.Role.CLIENT),
            ("prestataire_demo", "prest123", UserProfile.Role.PRESTATAIRE),
            ("admin_demo", "admin123", UserProfile.Role.ADMIN),
        ]

        for username, password, role in demo_accounts:
            user, created = User.objects.get_or_create(
                username=username,
                defaults={"is_active": True},
            )
            if created:
                user.set_password(password)
                user.save(update_fields=["password"])
                self.stdout.write(f"  Created user: {username}")
            else:
                self.stdout.write(f"  User exists: {username}")

            profile, _ = UserProfile.objects.get_or_create(
                user=user, defaults={"role": role, "active": True}
            )

        # ── Categories ─────────────────────────────────────────────────────
        cats = list(Category.objects.filter(actif=True)[:5])
        self.stdout.write(f"[OK] {len(cats)} active categories")

        # ── Prestataires ───────────────────────────────────────────────────
        providers_data = [
            ("Konan Jean", "Menage", "Abidjan - Cocody", 5000, Provider.Status.VALID),
            (
                "Kone Mariam",
                "Plomberie & dépannage sanitaire",
                "Abidjan - Plateau",
                8000,
                Provider.Status.PENDING,
            ),
            (
                "Fofana Ibrahim",
                "Électricité & mise aux normes",
                "Abidjan - Yopougon",
                7500,
                Provider.Status.VALID,
            ),
            (
                "Diallo Fatou",
                "Peinture & décoration intérieure",
                "Abidjan - Marcory",
                6000,
                Provider.Status.VALID,
            ),
            (
                "TRAORE Amara",
                "Climatisation & ventilation",
                "Abidjan - Abobo",
                10000,
                Provider.Status.VALID,
            ),
        ]

        for i, (nom, spec, ville, tarif, statut) in enumerate(providers_data):
            cat = cats[i % len(cats)] if cats else None
            Provider.objects.get_or_create(
                nom=nom,
                defaults={
                    "specialite": spec,
                    "ville": ville,
                    "tarif_horaire": tarif,
                    "statut": statut,
                    "category": cat,
                    "bio": f"Prestataire expert en {spec} depuis 5 ans",
                },
            )
        self.stdout.write(f"[OK] {len(providers_data)} prestataires")

        # ── Clients ────────────────────────────────────────────────────────
        clients_data = [
            ("Akouabi Paul", "akouabi@email.ci", "Abidjan"),
            ("Bamba Claire", "bamba@email.ci", "Abidjan"),
            ("Coulibaly Thomas", "coulibaly@email.ci", "Bouaké"),
            ("Kouassi Marie", "kouassi@email.ci", "Abidjan"),
            ("Soro Jean", "soro@email.ci", "Daloa"),
            ("Doumbia Awa", "doumbia@email.ci", "Abidjan"),
            ("Koné Fatou", "kone.f@email.ci", "Yamoussoukro"),
            ("Sakho Moussa", "sakho@email.ci", "San-Pédro"),
        ]

        for nom, email, ville in clients_data:
            Client.objects.get_or_create(
                email=email,
                defaults={
                    "nom": nom,
                    "ville": ville,
                    "reservations": 0,
                    "depense": Decimal("0.00"),
                },
            )
        self.stdout.write(f"[OK] {len(clients_data)} clients")

        # ── Reservations (Devis flow) ──────────────────────────────────────
        reservations_data = [
            # [ref, client, prestataire, montant, statut, title]
            (
                "RES-2026-001",
                "Akouabi Paul",
                "Konan Jean",
                Decimal("15000.00"),
                Reservation.Status.DONE,
                "Menage complet apartamento",
            ),
            (
                "RES-2026-002",
                "Bamba Claire",
                "Kone Mariam",
                Decimal("25000.00"),
                Reservation.Status.DEVIS_ENVOYE,
                "Fuite d'eau salle de bain",
            ),
            (
                "RES-2026-003",
                "Coulibaly Thomas",
                "Fofana Ibrahim",
                Decimal("8000.00"),
                Reservation.Status.DEVIS_ENVOYE,
                "Installation prises electriques",
            ),
            (
                "RES-2026-004",
                "Kouassi Marie",
                "Konan Jean",
                Decimal("5000.00"),
                "En attente presta",
                "Menage rapide",
            ),
            (
                "RES-2026-005",
                "Soro Jean",
                "Diallo Fatou",
                Decimal("35000.00"),
                Reservation.Status.DEVIS_ACCEPTE,
                "Peinture salon + chambres",
            ),
            (
                "RES-2026-006",
                "Doumbia Awa",
                "Kone Mariam",
                Decimal("20000.00"),
                Reservation.Status.WAITING_CLIENT,
                "Devis accepted - en attente paiement",
            ),
            (
                "RES-2026-007",
                "Kone Fatou",
                "Fofana Ibrahim",
                Decimal("12000.00"),
                Reservation.Status.DONE,
                "Depannage electrique",
            ),
            (
                "RES-2026-008",
                "Sakho Moussa",
                "TRAORE Amara",
                Decimal("45000.00"),
                "Litige",
                "Installation clim",
            ),
        ]

        for ref, client, prestataire, montant, statut, title in reservations_data:
            Reservation.objects.get_or_create(
                reference=ref,
                defaults={
                    "client": client,
                    "prestataire": prestataire,
                    "montant": montant,
                    "statut": statut,
                    "title": title,
                },
            )
        self.stdout.write(f"[OK] {len(reservations_data)} reservations")

        # ── Payments ───────────────────────────────────────────────────────
        payments_data = [
            (
                "PAY-2026-001",
                "Akouabi Paul",
                "Konan Jean",
                Decimal("15000.00"),
                Decimal("1500.00"),
                Payment.State.COMPLETE,
            ),
            (
                "PAY-2026-002",
                "Soro Jean",
                "Diallo Fatou",
                Decimal("35000.00"),
                Decimal("3500.00"),
                Payment.State.PENDING,
            ),
            (
                "PAY-2026-003",
                "Koné Fatou",
                "Fofana Ibrahim",
                Decimal("12000.00"),
                Decimal("1200.00"),
                Payment.State.COMPLETE,
            ),
            (
                "PAY-2026-004",
                "Sakho Moussa",
                "TRAORE Amara",
                Decimal("45000.00"),
                Decimal("4500.00"),
                Payment.State.DISPUTE,
            ),
        ]

        for ref, client, prestataire, montant, commission, etat in payments_data:
            Payment.objects.get_or_create(
                reference=ref,
                defaults={
                    "client": client,
                    "prestataire": prestataire,
                    "montant": montant,
                    "commission": commission,
                    "etat": etat,
                },
            )
        self.stdout.write(f"[OK] {len(payments_data)} payments")

        # ── Notifications ──────────────────────────────────────────────────
        notifications_data = [
            ("Nouveau devis reçu - RES-2026-002", "Il y a 5 min"),
            ("Paiement confirmé - PAY-2026-001", "Il y a 18 min"),
            ("Demande de support - Sakho Moussa", "Il y a 42 min"),
            ("Prestataire validé: Fofana Ibrahim", "Il y a 1h"),
            ("Litige ouvert - RES-2026-008", "Il y a 2h"),
        ]

        for title, time in notifications_data:
            Notification.objects.get_or_create(
                title=title,
                defaults={"time": time},
            )
        self.stdout.write(f"[OK] {len(notifications_data)} notifications")

        self.stdout.write(self.style.SUCCESS("\n[OK] Demo data seeded successfully!"))
        self.stdout.write("\nDemo Accounts:")
        self.stdout.write("  Client:       client_demo / client123")
        self.stdout.write("  Prestataire:  prestataire_demo / prest123")
        self.stdout.write("  Admin:        admin_demo / admin123")
