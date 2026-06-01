"""Seed test data : réservation + devis entre kouayavana18 (presta) et kouayavana19 (client)."""

from decimal import Decimal

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand
from django.utils import timezone

from adminpanel.models import Client, Devis, LigneDevis, Provider, Reservation


class Command(BaseCommand):
    help = "Seed réservation + devis entre kouayavana18 (presta) et kouayavana19 (client)"

    def handle(self, *args, **options):
        User = get_user_model()

        # --- Prestataire : kouayavana18 ---
        presta_user = User.objects.filter(username="kouayavana18").first()
        if not presta_user:
            self.stdout.write(self.style.ERROR("User kouayavana18 introuvable"))
            return
        provider = Provider.objects.filter(user=presta_user).first()
        if not provider:
            self.stdout.write(self.style.ERROR("Provider kouayavana18 introuvable"))
            return
        self.stdout.write(f"[OK] Prestataire : {provider.nom} (id={provider.id})")

        # --- Client : kouayavana19 ---
        client_user = User.objects.filter(email="kouayavana19@gmail.com").first()
        if not client_user:
            self.stdout.write(self.style.ERROR("User kouayavana19 introuvable"))
            return
        client = Client.objects.filter(email=client_user.email).first()
        if not client:
            self.stdout.write(self.style.ERROR("Client kouayavana19 introuvable"))
            return
        self.stdout.write(f"[OK] Client : {client.nom} (id={client.id})")

        # --- Mise à jour coordonnées Grand-Bassam pour le provider ---
        if not provider.latitude or not provider.longitude:
            provider.latitude = 5.2118
            provider.longitude = -3.7374
            provider.save(update_fields=["latitude", "longitude"])
            self.stdout.write("[OK] Coordonnées GPS provider -> Grand-Bassam")

        # --- Réservation ---
        ref = "TEST-RES-001"
        reservation, created = Reservation.objects.get_or_create(
            reference=ref,
            defaults={
                "title": "Réparation fuite robinet cuisine",
                "client": client.nom,
                "client_user": client_user,
                "prestataire": provider.nom,
                "prestataire_user_id": presta_user.id,
                "assigned_provider": provider,
                "montant": Decimal("25000.00"),
                "statut": Reservation.Status.DEVIS_ENVOYE,
                "payment_type": Reservation.PaymentType.MOBILE_MONEY,
                "mobile_money_operator": Reservation.MobileMoneyOperator.ORANGE_MONEY,
                "latitude": 5.3100,
                "longitude": -3.9800,
                "address_label": "Cocody, Angré, Abidjan",
                "address_ville": "Abidjan",
                "address_quartier": "Angré",
                "description_probleme": (
                    "Le robinet de l'évier de la cuisine fuit au niveau du col de cygne. "
                    "L'eau coule en continu même quand il est fermé. "
                    "Le joint semble usé. Besoin de réparation urgente."
                ),
                "is_urgent": True,
                "client_message": "Bonjour, j'ai besoin d'un plombier pour réparer ma fuite d'eau. Merci.",
            },
        )
        if created:
            self.stdout.write(f"[OK] Réservation créée : {ref}")
        else:
            # Mise à jour si existante
            reservation.statut = Reservation.Status.DEVIS_ENVOYE
            reservation.montant = Decimal("25000.00")
            reservation.description_probleme = (
                "Le robinet de l'évier de la cuisine fuit au niveau du col de cygne. "
                "L'eau coule en continu même quand il est fermé."
            )
            reservation.save(
                update_fields=["statut", "montant", "description_probleme"]
            )
            self.stdout.write(f"[OK] Réservation mise à jour : {ref}")

        # --- Devis associé ---
        devis_ref = None
        devis = reservation.devis_set.first()
        if not devis:
            devis = Devis(
                reservation=reservation,
                prestataire=provider,
                diagnostic=(
                    "Joint de robinet défectueux (joint torque 15mm). "
                    "Nécessite remplacement joint + nettoyage du tamis aérateur. "
                    "Vérification pression arrivée d'eau."
                ),
                date_proposee=timezone.now().date() + timezone.timedelta(days=2),
                heure_debut=timezone.datetime.strptime("08:00", "%H:%M").time(),
                heure_fin=timezone.datetime.strptime("10:00", "%H:%M").time(),
                commission_rate=18,
                note_prestataire="Intervention prévue en matinée. Prévoir accès au compteur d'eau.",
                validite_jours=7,
                statut=Devis.Statut.ENVOYE,
            )
            devis.save()
            devis_ref = devis.reference
            self.stdout.write(f"[OK] Devis créé : {devis_ref}")
        else:
            devis.diagnostic = "Joint de robinet défectueux (joint torque 15mm)."
            devis.statut = Devis.Statut.ENVOYE
            devis.save(update_fields=["diagnostic", "statut"])
            devis_ref = devis.reference
            self.stdout.write(f"[OK] Devis mis à jour : {devis_ref}")

        # --- Lignes de devis ---
        lignes = [
            {"type": LigneDevis.TypeLigne.FOURNITURE, "desc": "Joint torque 15mm (x2)", "qty": 1, "pu": Decimal("3000.00")},
            {"type": LigneDevis.TypeLigne.FOURNITURE, "desc": "Tamis aérateur robinet", "qty": 1, "pu": Decimal("2500.00")},
            {"type": LigneDevis.TypeLigne.DEPLACEMENT, "desc": "Frais déplacement", "qty": 1, "pu": Decimal("5000.00")},
            {"type": LigneDevis.TypeLigne.MAIN_OEUVRE, "desc": "Main d'œuvre (2h)", "qty": 2, "pu": Decimal("7500.00")},
        ]
        for ligne_data in lignes:
            ligne, l_created = LigneDevis.objects.get_or_create(
                devis=devis,
                description=ligne_data["desc"],
                defaults={
                    "type_ligne": ligne_data["type"],
                    "quantite": ligne_data["qty"],
                    "prix_unitaire": ligne_data["pu"],
                },
            )
            if l_created:
                self.stdout.write(f"  [OK]   Ligne : {ligne.description} = {ligne.total} FCFA")
            else:
                self.stdout.write(f"  [--]   Ligne existante : {ligne.description}")

        # Forcer recalcul totaux du devis
        devis.save()
        self.stdout.write(f"\n[OK] Sous-total : {devis.sous_total} FCFA")
        self.stdout.write(f"[OK] Commission (18%) : {devis.commission_montant} FCFA")
        self.stdout.write(f"[OK] Total TTC : {devis.total_ttc} FCFA")

        # Lier le devis à la réservation (montant mis à jour)
        reservation.montant = devis.total_ttc
        reservation.save(update_fields=["montant"])

        # --- Résumé ---
        self.stdout.write(self.style.SUCCESS(
            "\n========== RÉSUMÉ =========="
        ))
        self.stdout.write(f"Prestataire : {provider.nom} (Grand-Bassam)")
        self.stdout.write(f"Client       : {client.nom} (Cocody, Angré)")
        self.stdout.write(f"Réservation  : {reservation.reference} — {reservation.statut}")
        self.stdout.write(f"Devis        : {devis_ref} — {devis.statut}")
        self.stdout.write(f"GPS Provider : ~{provider.latitude},{provider.longitude} (Grand-Bassam)")
        self.stdout.write(f"GPS Client   : ~{reservation.latitude},{reservation.longitude} (Cocody)")
        self.stdout.write(f"Montant      : {reservation.montant} FCFA")
        self.stdout.write("==============================")
