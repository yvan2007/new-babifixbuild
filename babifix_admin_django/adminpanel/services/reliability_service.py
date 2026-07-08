"""ReliabilityService — score de fiabilité + détection d'annulations suspectes.

Phase 4, mode **PERMISSIF** : on met à jour un score indicatif (0–100, démarre à
100) et on flague les annulations suspectes (anti-désintermédiation). AUCUN
blocage n'est appliqué ici — la visibilité, les quotas ou le prépaiement pourront
s'appuyer sur ce signal plus tard, une fois qu'il aura fait ses preuves.

Tout est best-effort et enveloppé de try/except : la fiabilité ne doit JAMAIS
casser une annulation ou une fin de prestation.
"""
from __future__ import annotations

import logging

logger = logging.getLogger(__name__)


def _clamp(v) -> int:
    return max(0, min(100, int(v)))


class ReliabilityService:
    # Deltas volontairement petits (permissif) — on n'assomme pas les honnêtes.
    COMPLETION_BONUS_PRESTA = 2
    COMPLETION_BONUS_CLIENT = 1
    CLIENT_SUSPICIOUS_CANCEL = -8   # annulation après déblocage adresse
    CLIENT_LATE_CANCEL = -4         # annulation après acceptation
    PRESTA_NOSHOW = -12             # caution payée mais visite jamais faite
    PRESTA_LATE_CANCEL = -8

    # ------------------------------------------------------------------ helpers
    @staticmethod
    def _adjust_provider(provider, delta: int) -> None:
        if not provider or not delta:
            return
        provider.fiabilite_score = _clamp((provider.fiabilite_score or 100) + delta)
        provider.save(update_fields=["fiabilite_score"])

    @staticmethod
    def _adjust_client(user_id, delta: int) -> None:
        if not user_id or not delta:
            return
        from adminpanel.models import UserProfile
        prof = UserProfile.objects.filter(user_id=user_id).first()
        if not prof:
            return
        prof.fiabilite_score = _clamp((prof.fiabilite_score or 100) + delta)
        prof.save(update_fields=["fiabilite_score"])

    # ------------------------------------------------------------------ events
    @classmethod
    def on_completion(cls, reservation) -> None:
        """Prestation terminée : petit bonus au presta et au client."""
        try:
            cls._adjust_provider(
                reservation.assigned_provider, cls.COMPLETION_BONUS_PRESTA
            )
            cls._adjust_client(
                reservation.client_user_id, cls.COMPLETION_BONUS_CLIENT
            )
        except Exception:
            logger.warning(
                "reliability on_completion failed for %s",
                getattr(reservation, "reference", "?"),
                exc_info=True,
            )

    @classmethod
    def on_cancellation(cls, reservation, *, by: str, stage: str) -> None:
        """Met à jour les scores et flague les annulations suspectes.

        `by` : "CLIENT" | "PRESTATAIRE". `stage` : before_devis / after_devis /
        after_accept / after_start / completed (fourni par CancellationService).
        """
        try:
            # Adresse débloquée si la caution est payée OU si on a dépassé
            # l'acceptation du devis (le presta connaît alors l'adresse exacte).
            address_unlocked = bool(
                getattr(reservation, "caution_payee", False)
            ) or stage in ("after_accept", "after_start")

            suspicious = False
            if by == "CLIENT":
                if (
                    address_unlocked
                    and not getattr(reservation, "visite_effectuee", False)
                    and stage != "completed"
                ):
                    # Annulation juste après avoir obtenu l'adresse, sans visite
                    # ni prestation = soupçon de contournement.
                    suspicious = True
                    cls._adjust_client(
                        reservation.client_user_id, cls.CLIENT_SUSPICIOUS_CANCEL
                    )
                elif stage in ("after_accept", "after_start"):
                    cls._adjust_client(
                        reservation.client_user_id, cls.CLIENT_LATE_CANCEL
                    )
            elif by == "PRESTATAIRE":
                if (
                    getattr(reservation, "caution_payee", False)
                    and not getattr(reservation, "visite_effectuee", False)
                ):
                    cls._adjust_provider(
                        reservation.assigned_provider, cls.PRESTA_NOSHOW
                    )
                elif stage in ("after_accept", "after_start"):
                    cls._adjust_provider(
                        reservation.assigned_provider, cls.PRESTA_LATE_CANCEL
                    )

            if suspicious and not reservation.annulation_suspecte:
                reservation.annulation_suspecte = True
                reservation.save(update_fields=["annulation_suspecte"])
                cls._log_repeat_pattern(reservation)
        except Exception:
            logger.warning(
                "reliability on_cancellation failed for %s",
                getattr(reservation, "reference", "?"),
                exc_info=True,
            )

    @staticmethod
    def _log_repeat_pattern(reservation) -> None:
        """Alerte si le même couple client+prestataire cumule des annulations
        suspectes (motif de désintermédiation répété)."""
        from adminpanel.models import Reservation

        cu = reservation.client_user_id
        prov_id = reservation.assigned_provider_id
        if not cu or not prov_id:
            return
        count = Reservation.objects.filter(
            client_user_id=cu,
            assigned_provider_id=prov_id,
            annulation_suspecte=True,
        ).count()
        if count >= 2:
            logger.warning(
                "MOTIF SUSPECT (désintermédiation ?) : client=%s presta=%s → "
                "%s annulations suspectes",
                cu, prov_id, count,
            )
