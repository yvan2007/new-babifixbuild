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
    # Deltas par défaut (permissif). Surchargés par PlatformConfig si présent.
    COMPLETION_BONUS_PRESTA = 2
    COMPLETION_BONUS_CLIENT = 1
    CLIENT_SUSPICIOUS_CANCEL = -8   # annulation après déblocage adresse
    CLIENT_LATE_CANCEL = -4         # annulation après acceptation
    PRESTA_NOSHOW = -12             # caution payée mais visite jamais faite
    PRESTA_LATE_CANCEL = -8

    @staticmethod
    def _cfg():
        """Config plateforme (deltas/gating). Best-effort : None si indispo."""
        try:
            from adminpanel.models import PlatformConfig
            return PlatformConfig.get_solo()
        except Exception:
            return None

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
            cfg = cls._cfg()
            bp = cfg.delta_completion_presta if cfg else cls.COMPLETION_BONUS_PRESTA
            bc = cfg.delta_completion_client if cfg else cls.COMPLETION_BONUS_CLIENT
            cls._adjust_provider(reservation.assigned_provider, bp)
            cls._adjust_client(reservation.client_user_id, bc)
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
            cfg = cls._cfg()
            d_susp = cfg.delta_client_annulation_suspecte if cfg else cls.CLIENT_SUSPICIOUS_CANCEL
            d_late_c = cfg.delta_client_annulation_tardive if cfg else cls.CLIENT_LATE_CANCEL
            d_noshow = cfg.delta_presta_noshow if cfg else cls.PRESTA_NOSHOW
            d_late_p = cfg.delta_presta_annulation_tardive if cfg else cls.PRESTA_LATE_CANCEL

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
                    cls._adjust_client(reservation.client_user_id, d_susp)
                elif stage in ("after_accept", "after_start"):
                    cls._adjust_client(reservation.client_user_id, d_late_c)
            elif by == "PRESTATAIRE":
                if (
                    getattr(reservation, "caution_payee", False)
                    and not getattr(reservation, "visite_effectuee", False)
                ):
                    cls._adjust_provider(reservation.assigned_provider, d_noshow)
                elif stage in ("after_accept", "after_start"):
                    cls._adjust_provider(reservation.assigned_provider, d_late_p)

            if suspicious and not reservation.annulation_suspecte:
                reservation.annulation_suspecte = True
                reservation.save(update_fields=["annulation_suspecte"])
                cls._log_repeat_pattern(reservation)

            # Radar anti-fuite : visite EFFECTUÉE (le presta a rencontré le client)
            # mais AUCUN devis envoyé → forte présomption d'arrangement hors
            # plateforme. On flague et on applique un malus au prestataire.
            cls.flag_visite_suspecte_if_leak(reservation)
        except Exception:
            logger.warning(
                "reliability on_cancellation failed for %s",
                getattr(reservation, "reference", "?"),
                exc_info=True,
            )

    @classmethod
    def flag_visite_suspecte_if_leak(cls, reservation) -> bool:
        """Radar anti-désintermédiation.

        Signale une réservation comme « visite suspecte » quand la caution est
        payée, la visite effectuée, MAIS qu'aucun devis n'a jamais été envoyé —
        cas typique d'un presta et d'un client qui s'arrangent hors plateforme
        après la visite. Applique un malus de fiabilité au prestataire.
        Idempotent. Retourne True si un nouveau flag a été posé.
        """
        try:
            if getattr(reservation, "visite_suspecte", False):
                return False
            if not getattr(reservation, "caution_payee", False):
                return False
            if not getattr(reservation, "visite_effectuee", False):
                return False
            from adminpanel.models import Devis

            a_devis = (
                Devis.objects.filter(reservation=reservation)
                .exclude(statut="BROUILLON")
                .exists()
            )
            if a_devis:
                return False

            from django.utils import timezone

            cfg = cls._cfg()
            delta = int(
                getattr(cfg, "delta_presta_visite_suspecte", -10) or -10
            ) if cfg else -10

            reservation.visite_suspecte = True
            reservation.visite_suspecte_at = timezone.now()
            reservation.visite_suspecte_motif = (
                "Caution payée + visite effectuée mais aucun devis envoyé "
                "(présomption d'arrangement hors plateforme)."
            )[:255]
            reservation.save(
                update_fields=[
                    "visite_suspecte",
                    "visite_suspecte_at",
                    "visite_suspecte_motif",
                ]
            )
            cls._adjust_provider(reservation.assigned_provider, delta)
            cls._log_repeat_pattern(reservation)
            logger.info(
                "RADAR visite suspecte : %s (malus presta %s)",
                getattr(reservation, "reference", "?"),
                delta,
            )
            return True
        except Exception:
            logger.warning("radar visite suspecte failed", exc_info=True)
            return False

    # ------------------------------------------------------------------ gating
    @classmethod
    def gating_active(cls) -> bool:
        cfg = cls._cfg()
        return bool(cfg and cfg.fiabilite_gating_actif)

    @classmethod
    def _seuil(cls) -> int:
        cfg = cls._cfg()
        return int(cfg.fiabilite_seuil) if cfg else 40

    @classmethod
    def provider_penalise(cls, provider) -> bool:
        """True si le gating est actif ET le presta est sous le seuil.
        Conséquence douce : déprioritisation dans les listes/recherche."""
        if not cls.gating_active() or not provider:
            return False
        return int(getattr(provider, "fiabilite_score", 100) or 100) < cls._seuil()

    @classmethod
    def client_prepaiement_requis(cls, user_id) -> bool:
        """True si le gating est actif ET le client est sous le seuil.
        Conséquence : l'app peut exiger un prépaiement (surface, non bloquant)."""
        if not cls.gating_active() or not user_id:
            return False
        from adminpanel.models import UserProfile
        prof = UserProfile.objects.filter(user_id=user_id).first()
        if not prof:
            return False
        return int(prof.fiabilite_score or 100) < cls._seuil()

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
