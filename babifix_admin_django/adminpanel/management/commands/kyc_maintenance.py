"""
Maintenance KYC — minimisation des données + re-vérification.

À planifier (cron / tâche quotidienne). Deux actions :

  1. PURGE des images d'identité (selfie + CNI recto/verso) des dossiers
     déjà traités (approuvés OU rejetés) depuis plus de N jours. On conserve
     le résultat, le numéro masqué et la date d'expiration — pas les images.
     → minimisation des données personnelles sensibles.

  2. RE-VÉRIFICATION : repère les prestataires approuvés dont la CNI a expiré
     et leur redemande une pièce valide (statut KYC repassé en attente).

Exemples :
    python manage.py kyc_maintenance                 # purge à 30 j + re-vérif
    python manage.py kyc_maintenance --purge-days 7  # purge plus agressive
    python manage.py kyc_maintenance --dry-run       # simulation, ne modifie rien
    python manage.py kyc_maintenance --no-reverify   # purge seule
"""
from datetime import date, timedelta

from django.core.management.base import BaseCommand
from django.utils import timezone

from adminpanel.models import Provider


class Command(BaseCommand):
    help = "Purge les images KYC traitées et re-vérifie les CNI expirées."

    def add_arguments(self, parser):
        parser.add_argument("--purge-days", type=int, default=30,
                            help="Âge (jours) après examen avant purge des images. Défaut 30.")
        parser.add_argument("--dry-run", action="store_true",
                            help="Simulation : n'écrit rien en base.")
        parser.add_argument("--no-purge", action="store_true", help="Ne pas purger.")
        parser.add_argument("--no-reverify", action="store_true",
                            help="Ne pas re-vérifier les CNI expirées.")

    def handle(self, *args, **opts):
        dry = opts["dry_run"]
        purge_days = opts["purge_days"]
        tag = "[DRY-RUN] " if dry else ""

        # ── 1. Purge des images des dossiers traités ────────────────────────
        purged = 0
        if not opts["no_purge"]:
            cutoff = timezone.now() - timedelta(days=purge_days)
            qs = Provider.objects.filter(
                kyc_status__in=("approved", "rejected"),
                kyc_reviewed_at__isnull=False,
                kyc_reviewed_at__lt=cutoff,
                kyc_documents_purged_at__isnull=True,
            )
            for prov in qs:
                if dry:
                    has = any([prov.kyc_selfie_url, prov.kyc_cni_recto_url, prov.kyc_cni_verso_url])
                    if has:
                        purged += 1
                        self.stdout.write(f"{tag}purgerait images KYC de #{prov.pk} {prov.nom}")
                else:
                    if prov.purge_kyc_documents():
                        purged += 1
            self.stdout.write(self.style.SUCCESS(
                f"{tag}Images KYC purgées : {purged} dossier(s) (> {purge_days} j)."
            ))

        # ── 2. Re-vérification des CNI expirées ─────────────────────────────
        reverified = 0
        if not opts["no_reverify"]:
            today = date.today()
            qs = Provider.objects.filter(
                kyc_status="approved",
                kyc_cni_expiry__isnull=False,
                kyc_cni_expiry__lt=today,
            )
            for prov in qs:
                reverified += 1
                if dry:
                    self.stdout.write(
                        f"{tag}CNI expirée le {prov.kyc_cni_expiry} → re-vérif #{prov.pk} {prov.nom}"
                    )
                else:
                    prov.kyc_status = "pending"
                    prov.kyc_rejection_reason = (
                        "Votre pièce d'identité a expiré. Merci d'en soumettre une à jour."
                    )
                    prov.save(update_fields=["kyc_status", "kyc_rejection_reason"])
            self.stdout.write(self.style.SUCCESS(
                f"{tag}CNI expirées repassées en re-vérification : {reverified}."
            ))

        self.stdout.write(self.style.SUCCESS(
            f"{tag}Terminé. Purges={purged}, re-vérifications={reverified}."
        ))
