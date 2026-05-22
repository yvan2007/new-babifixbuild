"""process_pending_refunds — remboursement client automatique.

Verse automatiquement aux clients les remboursements décidés en litige
(`refund_owed_fcfa` > 0, non encore payés) via un payout GeniusPay
(`EscrowService.process_client_refund`).

Automatique mais non instantané (le remboursement découle d'une décision
admin ; ce cron le verse au prochain passage). À lancer par un cron Render,
ex. toutes les 5 minutes :

    python manage.py process_pending_refunds
"""

from django.core.management.base import BaseCommand
from django.db.models import Q


class Command(BaseCommand):
    help = "Verse automatiquement les remboursements clients en attente (payout GeniusPay)."

    def add_arguments(self, parser):
        parser.add_argument("--limit", type=int, default=50)

    def handle(self, *args, **opts):
        from adminpanel.models import Reservation
        from adminpanel.services.escrow_service import EscrowService

        # Remboursements dûs, jamais payés, pas déjà en cours / manuels.
        qs = (
            Reservation.objects.filter(
                refund_owed_fcfa__gt=0, refund_paid_at__isnull=True
            )
            .filter(Q(refund_status="") | Q(refund_status__isnull=True))
            .order_by("id")[: opts.get("limit", 50)]
        )
        ids = list(qs.values_list("pk", flat=True))

        paid = pending = failed = manual = 0
        for pk in ids:
            res = Reservation.objects.get(pk=pk)
            r = EscrowService.process_client_refund(res)
            if r.get("error") == "missing_client_mobile_money":
                manual += 1
            elif r.get("error"):
                failed += 1
            elif r.get("status") == "paid":
                paid += 1
            else:
                pending += 1
            self.stdout.write(f"  remboursement résa #{pk} → {r}")

        self.stdout.write(
            self.style.SUCCESS(
                f"Remboursements : {paid} versés, {pending} en cours, "
                f"{failed} échoués, {manual} à traiter manuellement "
                f"({len(ids)} candidats)."
            )
        )
