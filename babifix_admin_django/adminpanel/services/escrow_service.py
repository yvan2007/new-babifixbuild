"""EscrowService — orchestration paiement BABIFIX (Phase F).

Règle métier confirmée par le porteur du projet :

1. Quand le client accepte un devis, il DOIT verser un acompte avant que le
   prestataire ne démarre l'intervention.

2. Deux stratégies selon `Reservation.payment_type` :

   * **ESPECES (cash)** : l'acompte est exactement la **commission** de la
     plateforme (`Devis.commission_montant` = 18 % du sous-total). Ce
     montant est versé en Mobile Money via GeniusPay et constitue
     immédiatement un `PlatformRevenue` (c'est notre part finale). Le solde
     (82 %) sera donné en cash au prestataire en main à main à la fin du
     chantier. La plateforme n'a plus rien à libérer à la confirmation.

   * **MOBILE_MONEY** : l'acompte est le **total du devis** (`total_ttc`).
     L'argent reste en escrow (compte plateforme) jusqu'à la confirmation
     client. À la confirmation, on libère `net_prestataire` (82 %) dans le
     wallet du prestataire et on enregistre `commission_montant` (18 %) en
     PlatformRevenue.

3. **AUCUN fonds ne quitte la plateforme avant `client_confirme_prestation_at`.**
   En particulier le wallet prestataire n'est jamais crédité au moment du
   paiement initial — uniquement à `release_funds()`.

4. Idempotence : `release_funds` est sûr d'être appelé plusieurs fois (il
   regarde `funds_released_at`).
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from decimal import Decimal
from typing import Optional

from django.db import transaction
from django.utils import timezone

logger = logging.getLogger(__name__)

# B12 — Montant minimum acceptable en Mobile Money (limite GeniusPay 200 XOF).
# Si la commission cash devait être < ce seuil, on prélève ce minimum à la
# place ; le surplus (différence entre minimum et commission réelle) est
# tracé via `EscrowQuote.cash_minimum_surplus` puis reversé au prestataire
# à la confirmation pour qu'aucune partie ne soit lésée.
MIN_ONLINE_PAYMENT_XOF = Decimal("500")

# Mobile Money : part payée en acompte à la réservation (le reste = solde
# payé en ligne à la fin, avant la confirmation des travaux).
MOBILE_DEPOSIT_RATE = Decimal("0.30")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def _notify_provider_funds_received(reservation, net_amount: float) -> None:
    """Prévient le prestataire que son argent est arrivé : push + e-mail.

    Le push passe par `_schedule` qui brande automatiquement « BABIFIX PRO »
    et ne cible que l'app prestataire.
    """
    if not getattr(reservation, "prestataire_user_id", None) or net_amount <= 0:
        return
    montant_txt = f"{net_amount:,.0f}".replace(",", " ")

    # 1) Push notification (app prestataire)
    try:
        from adminpanel.push_dispatch import _schedule
        _schedule(
            [reservation.prestataire_user_id],
            "Argent reçu",
            f"{montant_txt} FCFA crédités sur votre wallet pour {reservation.reference}.",
            {"type": "wallet.credited", "reference": reservation.reference},
        )
    except Exception:
        logger.warning("notif push presta (funds) échouée %s", reservation.reference, exc_info=True)

    # 2) E-mail de confirmation de versement (expéditeur « BABIFIX »)
    try:
        from django.contrib.auth.models import User
        from .views_extra import send_babifix_email_html

        presta = User.objects.filter(pk=reservation.prestataire_user_id).first()
        if not (presta and presta.email):
            return
        nom = presta.get_full_name() or presta.username
        html = f"""
        <div style="font-family:Arial,sans-serif;max-width:520px;margin:auto">
          <h2 style="color:#0B1B34">BABIFIX — Versement reçu</h2>
          <p>Bonjour {nom},</p>
          <p>Bonne nouvelle : <strong>{montant_txt} FCFA</strong> (net après commission)
          viennent d'être crédités sur votre wallet BABIFIX pour la prestation
          <strong>{reservation.reference}</strong>.</p>
          <p>Vous pouvez demander un retrait depuis l'application
          <strong>BABIFIX PRO</strong> → Mon Wallet.</p>
          <p style="color:#64748b;font-size:13px">Merci de votre confiance.<br>L'équipe BABIFIX</p>
        </div>
        """
        send_babifix_email_html(
            to_email=presta.email,
            subject=f"BABIFIX : Versement reçu ({montant_txt} FCFA)",
            html_content=html,
        )
    except Exception:
        logger.warning("e-mail presta (funds) échoué %s", reservation.reference, exc_info=True)


def _latest_devis(reservation):
    """Devis ACCEPTE le plus récent, sinon ENVOYE, sinon None."""
    from adminpanel.models import Devis

    qs = Devis.objects.filter(reservation=reservation).order_by("-created_at")
    accepted = qs.filter(statut=Devis.Statut.ACCEPTE).first()
    if accepted:
        return accepted
    return qs.filter(statut=Devis.Statut.ENVOYE).first()


def _reste_apres_caution(reservation, devis) -> Decimal:
    """total_ttc du devis − caution/transport déjà versé (si déduite).

    Base de calcul de la commission ET du net prestataire. La remise
    fidélité n'intervient JAMAIS ici : elle est absorbée par BABIFIX sur SA
    propre part, jamais en réduisant ce que touche le prestataire (cf.
    `_reconciled_commission_net`).
    """
    total = Decimal(str(getattr(devis, "total_ttc", 0) or 0))
    if getattr(reservation, "caution_deduite", False):
        caution = Decimal(str(getattr(reservation, "caution_montant", 0) or 0))
        reste = total - caution
    else:
        reste = total
    return reste if reste > 0 else Decimal("0")


def _reconciled_commission_net(reservation, devis):
    """Commission BABIFIX (brute) et net prestataire, sur le reste APRÈS
    caution UNIQUEMENT — jamais après remise fidélité (celle-ci ne doit
    jamais réduire le net du prestataire, elle est absorbée par BABIFIX ;
    voir `_platform_commission_nette` pour ce qui est réellement comptabilisé
    en revenu plateforme).

    Remplace toute lecture directe de `devis.commission_montant` /
    `devis.net_prestataire` : ces deux champs sont figés au moment de l'envoi
    du devis et ne sont JAMAIS recalculés après une déduction de caution —
    les utiliser tels quels aurait versé au prestataire un montant faux (et
    prélevé une commission BABIFIX sur de l'argent déjà réglé séparément via
    la caution).

    Retourne (reste_apres_caution, commission_brute, net_presta).
    """
    reste = _reste_apres_caution(reservation, devis)
    try:
        rate = Decimal(str(devis.commission_rate or 18)) / Decimal("100")
    except Exception:
        rate = Decimal("0.18")
    commission = (reste * rate).quantize(Decimal("1"))
    net = reste - commission
    if net < 0:
        net = Decimal("0")
    return reste, commission, net


def _total_client_du(reservation, devis) -> Decimal:
    """Total réellement dû par le CLIENT via l'escrow = reservation.montant.

    `reservation.montant` est fixé à l'ACCEPTATION du devis et vaut déjà
    total_ttc − caution/transport éventuel (réglé à part, à la visite) −
    remise fidélité éventuelle (absorbée par BABIFIX). C'est la SEULE source
    de vérité pour ce que le client doit encore régler via l'escrow.

    BUG CORRIGÉ : cette fonction ne soustrayait QUE la remise fidélité du
    total brut du devis, en ignorant complètement la caution déjà versée.
    Résultat concret : un client ayant déjà payé 3 000 F de caution sur un
    devis de 5 000 F se voyait redemander une commission ET un reste calculés
    sur les 5 000 F complets (comme si rien n'avait encore été payé), au lieu
    des 2 000 F réellement dus. Le reçu (déjà corrigé) affichait le bon
    montant, mais l'écran de PAIEMENT (ce service) affichait l'ancien, faux —
    d'où les deux montants contradictoires vus par le client.
    """
    reste = Decimal(str(getattr(reservation, "montant", 0) or 0))
    if reste > 0:
        return reste
    # Repli : devis pas encore accepté (montant non initialisé).
    reste_avant_remise = _reste_apres_caution(reservation, devis)
    remise = Decimal(str(getattr(reservation, "remise_fidelite", 0) or 0))
    reste = reste_avant_remise - remise
    return reste if reste > 0 else Decimal("0")


# NB : l'absorption de la remise fidélité par BABIFIX (commission nette
# de revenu = commission brute − remise) est déjà actée par une écriture
# PlatformRevenue négative séparée dans `release_funds` (le presta, lui,
# touche toujours `net` inchangé, calculé sans la remise via
# `_reconciled_commission_net` ci-dessus).


@dataclass
class EscrowQuote:
    """Ce que le client doit verser maintenant pour démarrer l'intervention."""

    strategy: str  # "CASH_COMMISSION_ONLY" | "MOBILE_FULL"
    amount_due: Decimal  # montant à payer EN LIGNE (XOF entier)
    commission_montant: Decimal  # commission plateforme
    net_prestataire: Decimal  # ce que touchera le presta
    total_devis: Decimal  # total devis (référence affichage)
    cash_remainder: Decimal  # solde à payer cash au presta (0 si mobile)
    devis_id: Optional[int]
    devis_reference: str
    # B12 — Surplus prélevé en plus de la commission cash pour respecter
    # MIN_ONLINE_PAYMENT_XOF. Sera reversé au prestataire à la confirmation.
    cash_minimum_surplus: Decimal = Decimal("0")
    # Taux RÉEL (ex. 18) utilisé par _reconciled_commission_net. Sans ce
    # champ, le client devait reconstituer le taux en divisant
    # commission_montant (calculée sur le RESTE après caution) par
    # total_devis (le total BRUT) → un pourcentage faux (ex. 13 % au lieu
    # de 18 %) dès qu'une caution avait été déduite.
    commission_rate: int = 18


# ---------------------------------------------------------------------------
# Service
# ---------------------------------------------------------------------------
class EscrowService:
    """Orchestration paiement initial + libération à la confirmation."""

    # ---------- Calcul du montant à payer ----------------------------------
    @staticmethod
    def quote(reservation) -> EscrowQuote:
        """Calcule l'acompte requis selon la stratégie de la réservation."""
        from adminpanel.models import Reservation

        devis = _latest_devis(reservation)
        if devis is None:
            return EscrowQuote(
                strategy="UNKNOWN",
                amount_due=Decimal("0"),
                commission_montant=Decimal("0"),
                net_prestataire=Decimal("0"),
                total_devis=Decimal("0"),
                cash_remainder=Decimal("0"),
                devis_id=None,
                devis_reference="",
            )

        total = Decimal(str(devis.total_ttc or 0))  # total du devis (référence d'affichage)
        # RECONCILIÉ : commission et net calculés sur le RESTE réellement dû
        # (net de la caution déjà versée), pas sur `total` brut.
        reste, commission, net = _reconciled_commission_net(reservation, devis)

        cash_minimum_surplus = Decimal("0")
        if reservation.payment_type == Reservation.PaymentType.ESPECES:
            strategy = "CASH_COMMISSION_ONLY"
            amount_due = commission
            # B12 — Force le minimum acceptable Mobile Money. Si la
            # commission seule est trop faible (devis < ~2 800 FCFA),
            # on prélève le minimum et on note le surplus pour le
            # reverser au presta à la confirmation.
            if amount_due > 0 and amount_due < MIN_ONLINE_PAYMENT_XOF:
                cash_minimum_surplus = MIN_ONLINE_PAYMENT_XOF - amount_due
                amount_due = MIN_ONLINE_PAYMENT_XOF
            cash_remainder = net - cash_minimum_surplus
            if cash_remainder < 0:
                cash_remainder = Decimal("0")
        else:
            # Mobile Money en deux temps : 30 % d'acompte à la réservation,
            # puis 70 % de solde à la fin (avant confirmation). Tout reste en
            # escrow jusqu'à la confirmation client (release_funds).
            montant_verse = Decimal(str(reservation.montant_verse or 0))
            # ATTENTION : `reste` (calculé plus haut) exclut délibérément la
            # remise fidélité — c'est la base de la commission/du net presta,
            # que la remise ne doit jamais réduire. Ce que le CLIENT règle,
            # lui, doit bien inclure la remise : `_total_client_du` est la
            # seule source correcte ici (reste ET remise).
            total_client = _total_client_du(reservation, devis)
            if not reservation.acompte_valide:
                strategy = "MOBILE_DEPOSIT"  # phase 1 : acompte
                amount_due = (total_client * MOBILE_DEPOSIT_RATE).quantize(Decimal("1"))
            else:
                strategy = "MOBILE_REMAINDER"  # phase 2 : solde restant
                amount_due = total_client - montant_verse
            if amount_due < 0:
                amount_due = Decimal("0")
            # B12 — garde-fou montant minimum GeniusPay (sans dépasser le total).
            if amount_due > 0 and amount_due < MIN_ONLINE_PAYMENT_XOF:
                amount_due = MIN_ONLINE_PAYMENT_XOF
                if amount_due > total:
                    amount_due = total
            cash_remainder = Decimal("0")

        return EscrowQuote(
            strategy=strategy,
            amount_due=amount_due.quantize(Decimal("1")),
            commission_montant=commission,
            net_prestataire=net,
            total_devis=total,
            cash_remainder=cash_remainder.quantize(Decimal("1")),
            devis_id=devis.id,
            devis_reference=devis.reference,
            cash_minimum_surplus=cash_minimum_surplus.quantize(Decimal("1")),
            commission_rate=int(devis.commission_rate or 18),
        )

    # ---------- Hook webhook GeniusPay -------------------------------------
    @staticmethod
    @transaction.atomic
    def mark_escrow_received(payment) -> dict:
        """Appelé par le webhook GeniusPay quand un paiement est validé.

        Ne crédite JAMAIS le wallet du prestataire.

        - Cash (acompte = commission) : enregistre directement en
          `PlatformRevenue` (c'est notre part finale) et marque
          `commission_collected_at`.
        - Mobile (paiement total) : marque l'acompte comme reçu en escrow,
          met à jour `montant_verse` et `acompte_valide`. Aucune écriture
          dans `PlatformRevenue` ni dans le wallet presta : on attendra la
          confirmation client (`release_funds`).
        """
        from adminpanel.models import PlatformRevenue, Reservation

        reservation = getattr(payment, "reservation", None)
        if not reservation:
            logger.warning(
                "mark_escrow_received: payment %s has no reservation", payment.pk
            )
            return {"error": "no_reservation"}

        gross = Decimal(str(payment.montant or 0))
        if gross <= 0:
            return {"error": "amount_zero"}

        reservation.montant_verse = (reservation.montant_verse or Decimal("0")) + gross
        reservation.acompte_valide = True
        if not reservation.cash_client_declared_at:
            reservation.cash_client_declared_at = timezone.now()
        # Met à jour le reste dû (utile au flux Mobile 30 %/70 % : après
        # l'acompte il reste 70 % à payer en ligne avant la confirmation).
        _devis_total = _latest_devis(reservation)
        _total_due = (
            _total_client_du(reservation, _devis_total)
            if _devis_total
            else reservation.montant_verse
        )
        reservation.montant_restant = max(Decimal("0"), _total_due - reservation.montant_verse)
        update_fields = [
            "montant_verse",
            "acompte_valide",
            "cash_client_declared_at",
            "montant_restant",
        ]

        if reservation.payment_type == Reservation.PaymentType.ESPECES:
            # La commission reste bloquée en escrow jusqu'à la confirmation
            # client + cash handover complet. On ne crée PAS PlatformRevenue
            # ici — ce sera fait dans release_funds.
            devis = _latest_devis(reservation)
            commission_due = (
                _reconciled_commission_net(reservation, devis)[1] if devis else gross
            )
            if commission_due > gross:
                commission_due = gross
            # On conserve le montant de la commission pour release_funds
            reservation.cash_flow_status = Reservation.CashFlowStatus.PENDING_ADMIN
            update_fields.append("cash_flow_status")
            surplus = gross - commission_due
            if surplus > 0:
                logger.info(
                    "EscrowService: surplus cash %s FCFA mis en escrow pour %s",
                    surplus,
                    reservation.reference,
                )
            logger.info(
                "EscrowService: commission cash %s FCFA bloquée en escrow pour %s "
                "(libérée à la confirmation client)",
                commission_due,
                reservation.reference,
            )
        else:
            # Mobile : tout est en escrow plateforme, rien n'est encore acquis.
            reservation.cash_flow_status = Reservation.CashFlowStatus.PENDING_ADMIN
            update_fields.append("cash_flow_status")
            logger.info(
                "EscrowService: escrow mobile %s FCFA bloqué pour %s",
                gross,
                reservation.reference,
            )

        reservation.save(update_fields=update_fields)

        # Notif temps réel
        try:
            from asgiref.sync import async_to_sync
            from channels.layers import get_channel_layer

            layer = get_channel_layer()
            if layer:
                async_to_sync(layer.group_send)(
                    f"reservation_{reservation.pk}",
                    {
                        "type": "reservation_event",
                        "event_type": "escrow.received",
                        "payload": {
                            "reference": reservation.reference,
                            "montant_verse": float(reservation.montant_verse),
                            "payment_type": reservation.payment_type,
                        },
                    },
                )
        except Exception as exc:
            logger.debug("WS escrow.received skipped: %s", exc)

        return {
            "ok": True,
            "strategy": (
                "CASH_COMMISSION_ONLY"
                if reservation.payment_type == Reservation.PaymentType.ESPECES
                else "MOBILE_FULL"
            ),
            "montant_verse": float(reservation.montant_verse),
        }

    # ---------- Libération à la confirmation client ------------------------
    @staticmethod
    @transaction.atomic
    def release_funds(reservation) -> dict:
        """Libère les fonds après confirmation client.

        Idempotent : si `funds_released_at` est déjà set, retourne
        immédiatement.

        - Mobile : crédite le wallet presta de `net_prestataire`, enregistre
          la commission en `PlatformRevenue`.
        - Cash : rien à libérer (commission déjà encaissée, solde déjà payé
          main à main). On marque juste `funds_released_at`.
        """
        from adminpanel.models import (
            PlatformRevenue,
            Provider,
            Reservation,
            WalletTransaction,
        )

        if getattr(reservation, "funds_released_at", None):
            return {"ok": True, "already_released": True}

        # SÉCURITÉ ARGENT : un litige ouvert GÈLE le versement. Les fonds ne
        # bougent qu'après résolution admin (resolve_dispute) qui lève le flag.
        if getattr(reservation, "dispute_ouverte", False):
            logger.info(
                "release_funds: litige ouvert pour %s — versement gelé",
                reservation.reference,
            )
            return {"error": "dispute_open", "held": True}

        if not reservation.client_confirme_prestation_at:
            return {"error": "client_not_confirmed"}

        devis = _latest_devis(reservation)
        if devis is None:
            logger.warning(
                "release_funds: aucune devis pour %s — abort",
                reservation.reference,
            )
            return {"error": "no_devis"}

        # RECONCILIÉ : commission et net calculés sur le reste réellement dû
        # (net de la caution). Point le plus critique : c'est CE net qui est
        # réellement versé au wallet du prestataire ci-dessous.
        _, commission, net = _reconciled_commission_net(reservation, devis)

        result = {
            "ok": True,
            "released_to_provider": 0.0,
            "platform_revenue": 0.0,
            "strategy": (
                "CASH_COMMISSION_ONLY"
                if reservation.payment_type == Reservation.PaymentType.ESPECES
                else "MOBILE_FULL"
            ),
        }

        if reservation.payment_type == Reservation.PaymentType.ESPECES:
            # La commission était bloquée en escrow depuis l'acompte.
            # On la reconnaît maintenant comme revenu plateforme.
            montant_verse = Decimal(str(reservation.montant_verse or 0))
            commission_due = commission if montant_verse >= commission else montant_verse
            PlatformRevenue.objects.create(
                amount_fcfa=commission_due,
                source=PlatformRevenue.Source.COMMISSION,
                reference=reservation.reference,
                description=(
                    f"Commission libérée à la confirmation — {reservation.reference}"
                ),
            )
            result["platform_revenue"] = float(commission_due)
            # B12 — Surplus éventuel (devis très petit) reversé au presta
            surplus = montant_verse - commission_due
            if surplus > 0:
                provider = reservation.assigned_provider
                if not provider and reservation.prestataire_user_id:
                    provider = Provider.objects.filter(
                        user_id=reservation.prestataire_user_id
                    ).first()
                if provider:
                    prov = Provider.objects.select_for_update().get(pk=provider.pk)
                    prov.solde_fcfa = (
                        prov.solde_fcfa or Decimal("0")
                    ) + surplus.quantize(Decimal("1"))
                    prov.save(update_fields=["solde_fcfa"])
                    WalletTransaction.objects.create(
                        provider=prov,
                        tx_type="credit",
                        amount_fcfa=surplus.quantize(Decimal("1")),
                        reference=reservation.reference,
                        description=(
                            f"Surplus minimum MM reversé — {reservation.reference}"
                        ),
                        status="success",
                    )
                    result["released_to_provider"] = float(surplus)
                    logger.info(
                        "EscrowService.release_funds: cash %s — surplus %s "
                        "reversé au presta",
                        reservation.reference,
                        surplus,
                    )
                else:
                    logger.warning(
                        "release_funds cash surplus: provider introuvable pour %s",
                        reservation.reference,
                    )
            else:
                logger.info(
                    "EscrowService.release_funds: cash %s — commission %s "
                    "reconnue, net déjà en main à main.",
                    reservation.reference,
                    commission_due,
                )
        else:
            # Mobile : la plateforme libère le net vers le wallet presta et
            # acte la commission en PlatformRevenue.
            # Sécurité argent : ne rien libérer tant que le TOTAL dû par le client
            # (acompte 30 % + solde 70 %, MOINS la remise fidélité absorbée par
            # BABIFIX) n'a pas été encaissé en escrow.
            total_due = _total_client_du(reservation, devis)
            montant_verse = Decimal(str(reservation.montant_verse or 0))
            if montant_verse + Decimal("1") < total_due:  # tolérance arrondi 1 XOF
                logger.info(
                    "release_funds: solde non payé pour %s (versé %s / %s) — gelé",
                    reservation.reference, montant_verse, total_due,
                )
                return {"error": "remainder_not_paid", "held": True}
            provider = reservation.assigned_provider
            if not provider and reservation.prestataire_user_id:
                provider = Provider.objects.filter(
                    user_id=reservation.prestataire_user_id
                ).first()
            if not provider:
                logger.warning(
                    "release_funds: aucun provider pour %s", reservation.reference
                )
                return {"error": "no_provider"}

            prov = Provider.objects.select_for_update().get(pk=provider.pk)
            prov.solde_fcfa = (prov.solde_fcfa or Decimal("0")) + net
            prov.save(update_fields=["solde_fcfa"])

            # Taux RÉEL prélevé (reflète le tarif premium du prestataire, ex.
            # 8 % en GOLD) au lieu d'un « 18 % » figé dans le libellé.
            _gross = (net or Decimal("0")) + (commission or Decimal("0"))
            _pct = int(round((commission / _gross) * 100)) if _gross else 18
            WalletTransaction.objects.create(
                provider=prov,
                tx_type="credit",
                amount_fcfa=net,
                reference=reservation.reference,
                description=(
                    f"Libération escrow — {reservation.reference} "
                    f"(net après commission {_pct} %)"
                ),
                status="success",
            )
            WalletTransaction.objects.create(
                provider=prov,
                tx_type="commission",
                amount_fcfa=commission,
                reference=reservation.reference,
                description=(
                    f"Commission BABIFIX {_pct} % prélevée — {reservation.reference}"
                ),
                status="success",
            )
            PlatformRevenue.objects.create(
                amount_fcfa=commission,
                source=PlatformRevenue.Source.COMMISSION,
                reference=reservation.reference,
                description=(
                    f"Commission 18 % libérée à la confirmation — {reservation.reference}"
                ),
            )

            # Fidélité : BABIFIX ABSORBE la remise offerte au client → écriture
            # NÉGATIVE qui vient réduire son revenu (le presta a touché son net
            # plein). Revenu net BABIFIX = commission − remise.
            _remise_fid = Decimal(str(reservation.remise_fidelite or 0))
            if _remise_fid > 0:
                PlatformRevenue.objects.create(
                    amount_fcfa=(-_remise_fid),
                    source=PlatformRevenue.Source.COMMISSION,
                    reference=reservation.reference,
                    description=(
                        f"Remise fidélité offerte au client — {reservation.reference}"
                    ),
                )

            result["released_to_provider"] = float(net)
            result["platform_revenue"] = float(commission - (reservation.remise_fidelite or 0))
            result["provider_balance"] = float(prov.solde_fcfa)

            # Notif temps réel
            try:
                from asgiref.sync import async_to_sync
                from channels.layers import get_channel_layer

                layer = get_channel_layer()
                if layer:
                    async_to_sync(layer.group_send)(
                        f"prestataire_{prov.user_id}",
                        {
                            "type": "prestataire_notify",
                            "event_type": "wallet.credited",
                            "payload": {
                                "solde_fcfa": float(prov.solde_fcfa),
                                "net": float(net),
                                "commission": float(commission),
                                "reference": reservation.reference,
                            },
                        },
                    )
            except Exception as exc:
                logger.debug("WS wallet.credited skipped: %s", exc)

        reservation.funds_released_at = timezone.now()
        reservation.solde_valide = True
        reservation.cash_flow_status = Reservation.CashFlowStatus.VALIDATED
        reservation.save(
            update_fields=["funds_released_at", "solde_valide", "cash_flow_status"]
        )

        # Prestation menée à terme : bonus de fiabilité (permissif, best-effort).
        try:
            from adminpanel.services.reliability_service import ReliabilityService
            ReliabilityService.on_completion(reservation)
        except Exception:
            logger.debug("reliability on_completion skipped", exc_info=True)

        # Prévenir le PRESTATAIRE que son argent est arrivé : push (BABIFIX PRO)
        # + e-mail de confirmation de versement.
        try:
            _notify_provider_funds_received(
                reservation, float(result.get("released_to_provider") or 0)
            )
        except Exception:
            logger.warning(
                "release_funds: notification presta échouée %s",
                reservation.reference, exc_info=True,
            )

        logger.info(
            "EscrowService.release_funds: %s — strategy=%s released=%s commission=%s",
            reservation.reference,
            result["strategy"],
            result.get("released_to_provider"),
            result.get("platform_revenue"),
        )
        return result

    # ---------- Résolution d'un litige (décision admin) --------------------
    @staticmethod
    @transaction.atomic
    def resolve_dispute(reservation, decision: str) -> dict:
        """Applique la décision d'un litige sur les fonds.

        - RELEASE (Libérer paiement) : on lève le gel et on verse le net au
          prestataire (release_funds).
        - REFUND (Rembourser client) : aucun versement au presta ; on inscrit
          le montant dû au client (`refund_owed_fcfa`, payé ensuite par l'admin)
          et la réservation passe Annulée.
        - SPLIT (Partage partiel) : 50 % au prestataire (wallet), 50 % dû au
          client en remboursement.
        Lève toujours `dispute_ouverte`. Idempotent via `funds_released_at`.
        """
        from adminpanel.models import (
            Provider,
            Reservation,
            WalletTransaction,
        )

        d = (decision or "").strip().upper()
        is_release = d in ("RELEASE", "LIBERER PAIEMENT", "LIBÉRER PAIEMENT")
        is_refund = d in ("REFUND", "REMBOURSER CLIENT")
        is_split = d in ("SPLIT", "PARTAGE PARTIEL", "PARTAGE")

        if not (is_release or is_refund or is_split):
            return {"error": "decision_inconnue", "decision": decision}

        devis = _latest_devis(reservation)
        net = (
            _reconciled_commission_net(reservation, devis)[2]
            if devis else Decimal("0")
        )
        paid = Decimal(str(reservation.montant_verse or 0))

        # ── Libérer au prestataire ──────────────────────────────────────────
        if is_release:
            reservation.dispute_ouverte = False
            if not reservation.client_confirme_prestation_at:
                reservation.client_confirme_prestation_at = timezone.now()
            reservation.save(
                update_fields=["dispute_ouverte", "client_confirme_prestation_at"]
            )
            res = EscrowService.release_funds(reservation)
            res["action"] = "release"
            return res

        # ── Rembourser le client (rien au presta) ───────────────────────────
        if is_refund:
            refund_amount = paid if paid > 0 else Decimal(str(reservation.montant or 0))
            reservation.dispute_ouverte = False
            reservation.funds_released_at = timezone.now()  # bloque tout versement futur
            reservation.refund_owed_fcfa = refund_amount
            reservation.cash_flow_status = Reservation.CashFlowStatus.REFUSED
            reservation.statut = Reservation.Status.CANCELLED
            reservation.save(
                update_fields=[
                    "dispute_ouverte",
                    "funds_released_at",
                    "refund_owed_fcfa",
                    "cash_flow_status",
                    "statut",
                ]
            )
            logger.info(
                "resolve_dispute REFUND: %s — %s FCFA dûs au client",
                reservation.reference, refund_amount,
            )
            return {"action": "refund", "ok": True, "refund_owed": float(refund_amount)}

        # ── Partage 50/50 ───────────────────────────────────────────────────
        half_net = (net / 2).quantize(Decimal("1"))
        half_refund = (paid / 2).quantize(Decimal("1"))
        provider = reservation.assigned_provider
        if not provider and reservation.prestataire_user_id:
            provider = Provider.objects.filter(
                user_id=reservation.prestataire_user_id
            ).first()
        credited = Decimal("0")
        if provider and half_net > 0:
            prov = Provider.objects.select_for_update().get(pk=provider.pk)
            prov.solde_fcfa = (prov.solde_fcfa or Decimal("0")) + half_net
            prov.save(update_fields=["solde_fcfa"])
            WalletTransaction.objects.create(
                provider=prov,
                tx_type="credit",
                amount_fcfa=half_net,
                reference=reservation.reference,
                description=f"Partage litige (50%) — {reservation.reference}",
                status="success",
            )
            credited = half_net
        reservation.dispute_ouverte = False
        reservation.funds_released_at = timezone.now()
        reservation.refund_owed_fcfa = half_refund
        reservation.save(
            update_fields=["dispute_ouverte", "funds_released_at", "refund_owed_fcfa"]
        )
        logger.info(
            "resolve_dispute SPLIT: %s — presta +%s, client remboursé %s",
            reservation.reference, credited, half_refund,
        )
        return {
            "action": "split",
            "ok": True,
            "to_provider": float(credited),
            "refund_owed": float(half_refund),
        }

    # ---------- Remboursement client automatique (payout GeniusPay) --------
    @staticmethod
    def _client_payout_target(reservation):
        """Téléphone + opérateur Mobile Money pour rembourser le client.

        Téléphone : numéro vérifié (UserProfile.phone_e164) du client.
        Opérateur : celui utilisé pour la réservation (mobile_money_operator).
        """
        from adminpanel.models import UserProfile

        phone = ""
        if reservation.client_user_id:
            prof = UserProfile.objects.filter(
                user_id=reservation.client_user_id
            ).first()
            if prof and prof.phone_e164:
                phone = prof.phone_e164.strip()
        operator = (reservation.mobile_money_operator or "").strip()
        return phone, operator

    @staticmethod
    def process_client_refund(reservation) -> dict:
        """Verse automatiquement au client le montant qui lui est dû
        (`refund_owed_fcfa`) via un payout GeniusPay. Pro & sécurisé :
        claim de statut pour éviter tout double versement, remboursement
        confirmé par webhook `payout.*`."""
        from adminpanel.models import Reservation
        from adminpanel.geniuspay import geniuspay_send_payout

        # Phase 1 — claim atomique
        with transaction.atomic():
            res = Reservation.objects.select_for_update().get(pk=reservation.pk)
            owed = Decimal(str(res.refund_owed_fcfa or 0))
            if owed <= 0 or res.refund_paid_at is not None:
                return {"ok": True, "skip": "nothing_owed_or_already_paid"}
            if res.refund_status in ("processing", "paid"):
                return {"ok": True, "skip": "already_" + res.refund_status}
            phone, operator = EscrowService._client_payout_target(res)
            if not phone or not operator:
                res.refund_status = "manual"  # infos MoMo manquantes → admin manuel
                res.save(update_fields=["refund_status"])
                logger.warning(
                    "process_client_refund: %s — tel/opérateur client manquant "
                    "→ remboursement manuel",
                    res.reference,
                )
                return {"error": "missing_client_mobile_money", "manual": True}
            res.refund_status = "processing"
            res.save(update_fields=["refund_status"])
            ref = res.reference
            client_name = res.client or "Client BABIFIX"

        ext_ref = f"REFUND-{ref}"
        result = geniuspay_send_payout(
            amount=owed,
            phone=phone,
            operator=operator,
            recipient_name=client_name,
            reference=ext_ref,
            description=f"Remboursement litige BABIFIX — {ref}",
        )

        if not result.get("ok"):
            with transaction.atomic():
                res = Reservation.objects.select_for_update().get(pk=reservation.pk)
                res.refund_status = "failed"
                res.save(update_fields=["refund_status"])
            logger.error(
                "process_client_refund: échec payout %s — %s",
                ref, result.get("error"),
            )
            EscrowService._notify_client_refund(reservation.pk, ok=False)
            return {"error": "payout_failed", "detail": result.get("error")}

        with transaction.atomic():
            res = Reservation.objects.select_for_update().get(pk=reservation.pk)
            res.refund_reference = result.get("external_reference") or ext_ref
            if result.get("status") == "completed":
                res.refund_status = "paid"
                res.refund_paid_at = timezone.now()
            else:
                res.refund_status = "processing"
            res.save(
                update_fields=["refund_reference", "refund_status", "refund_paid_at"]
            )
        if res.refund_status == "paid":
            EscrowService._notify_client_refund(reservation.pk, ok=True)
        logger.info(
            "process_client_refund: %s → %s (ref=%s)",
            ref, res.refund_status, res.refund_reference,
        )
        return {"ok": True, "status": res.refund_status, "reference": res.refund_reference}

    @staticmethod
    def handle_refund_payout_webhook(*, external_reference: str, success: bool) -> dict:
        """Confirme/échoue un remboursement client suite au webhook payout.*."""
        from adminpanel.models import Reservation

        res = Reservation.objects.filter(refund_reference=external_reference).first()
        if not res:
            return {"error": "refund_not_found"}
        if success:
            if res.refund_status != "paid":
                res.refund_status = "paid"
                res.refund_paid_at = timezone.now()
                res.save(update_fields=["refund_status", "refund_paid_at"])
                EscrowService._notify_client_refund(res.pk, ok=True)
            return {"ok": True, "status": "paid"}
        if res.refund_status != "failed":
            res.refund_status = "failed"
            res.save(update_fields=["refund_status"])
            EscrowService._notify_client_refund(res.pk, ok=False)
        return {"ok": True, "status": "failed"}

    @staticmethod
    def _notify_client_refund(reservation_pk: int, ok: bool) -> None:
        from adminpanel.models import Reservation

        res = Reservation.objects.filter(pk=reservation_pk).first()
        if not res or not res.client_user_id:
            return
        try:
            from adminpanel.push_dispatch import _schedule

            if ok:
                title = "BABIFIX — Remboursement effectué"
                body = (
                    f"Votre remboursement de {res.refund_owed_fcfa:,.0f} FCFA "
                    f"(litige {res.reference}) a été versé sur votre compte Mobile Money."
                )
                ev = "refund.completed"
            else:
                title = "BABIFIX — Remboursement en traitement"
                body = (
                    f"Votre remboursement (litige {res.reference}) sera traité "
                    f"manuellement par notre équipe sous peu."
                )
                ev = "refund.failed"
            _schedule([res.client_user_id], title, body, {"type": ev, "reference": res.reference})
        except Exception as exc:
            logger.warning("notify client refund failed: %s", exc)
