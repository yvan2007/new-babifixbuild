"""process_pending_withdrawals — versement automatique des retraits.

Traite les retraits prestataire EN ATTENTE après un délai de sécurité
(« hold »), puis déclenche le versement Mobile Money via GeniusPay
(`WalletService.process_withdrawal`).

Le délai rend le versement **automatique mais NON instantané** (fenêtre
anti-fraude / traitement pro). À lancer par un cron Render, ex. toutes les
5 minutes :

    python manage.py process_pending_withdrawals

Variables d'env :
    WITHDRAWAL_AUTO_HOLD_MINUTES  (défaut 15) — délai avant versement auto.
"""

import os
from datetime import timedelta

from django.core.management.base import BaseCommand
from django.utils import timezone


class Command(BaseCommand):
    help = "Verse automatiquement les retraits prestataire en attente (payout GeniusPay)."

    def add_arguments(self, parser):
        parser.add_argument(
            "--hold-minutes",
            type=int,
            default=None,
            help="Délai min. avant versement (défaut: env WITHDRAWAL_AUTO_HOLD_MINUTES ou 15).",
        )
        parser.add_argument("--limit", type=int, default=50)

    def handle(self, *args, **opts):
        from adminpanel.models import WalletTransaction
        from adminpanel.services.wallet_service import WalletService

        hold = opts.get("hold_minutes")
        if hold is None:
            try:
                hold = int(os.getenv("WITHDRAWAL_AUTO_HOLD_MINUTES", "15"))
            except (TypeError, ValueError):
                hold = 15
        cutoff = timezone.now() - timedelta(minutes=hold)

        ids = list(
            WalletTransaction.objects.filter(
                tx_type="debit", status="pending", created_at__lte=cutoff
            )
            .order_by("created_at")
            .values_list("pk", flat=True)[: opts.get("limit", 50)]
        )

        sent = failed = 0
        for tx_id in ids:
            res = WalletService.process_withdrawal(tx_id)
            if res.get("ok"):
                sent += 1
            else:
                failed += 1
            self.stdout.write(f"  retrait #{tx_id} → {res}")

        self.stdout.write(
            self.style.SUCCESS(
                f"Retraits traités : {sent} versés/en cours, {failed} échoués "
                f"(hold={hold} min, {len(ids)} candidats)."
            )
        )
