"""
B2B Service — BABIFIX Pro (syndics, entreprises, agences immobilières).

Offre hybride : abonnement mensuel récurrent (SaaS) + commission réduite sur
les interventions, facturation mensuelle groupée et SLA par formule.
"""
import logging
from decimal import Decimal

from django.db import transaction
from django.db.models import Sum, Count
from django.utils import timezone

logger = logging.getLogger(__name__)


# Formules B2B (alignées sur la proposition « BABIFIX Pro »)
PRO_FORMULES = {
    "starter": {
        "name": "Starter",
        "abonnement": 25000,   # FCFA/mois
        "commission": 10,      # %
        "sla_heures": 24,
        "sites_max": 5,
        "cible": "1 à 5 sites",
    },
    "business": {
        "name": "Business",
        "abonnement": 75000,
        "commission": 8,
        "sla_heures": 6,
        "sites_max": 20,
        "cible": "5 à 20 sites",
    },
    "enterprise": {
        "name": "Enterprise",
        "abonnement": 0,       # sur devis
        "commission": 6,       # négociée (valeur par défaut)
        "sla_heures": 2,
        "sites_max": None,     # illimité
        "cible": "20+ sites",
    },
}


class B2BService:
    """Service métier pour l'offre professionnelle BABIFIX Pro."""

    @classmethod
    def formules(cls) -> list[dict]:
        return [
            {
                "id": fid,
                "name": cfg["name"],
                "abonnement_mensuel_fcfa": cfg["abonnement"],
                "commission_pct": cfg["commission"],
                "sla_heures": cfg["sla_heures"],
                "sites_max": cfg["sites_max"],
                "cible": cfg["cible"],
            }
            for fid, cfg in PRO_FORMULES.items()
        ]

    @classmethod
    @transaction.atomic
    def create_account(cls, user, raison_sociale: str, formule: str = "starter", **extra) -> dict:
        from ..models import ProAccount

        formule = (formule or "starter").lower()
        cfg = PRO_FORMULES.get(formule, PRO_FORMULES["starter"])

        if hasattr(user, "babifix_pro_account"):
            return {"error": "already_pro", "detail": "Ce compte est déjà un compte professionnel."}

        acc = ProAccount.objects.create(
            user=user,
            raison_sociale=raison_sociale.strip()[:200],
            formule=formule,
            commission_rate=cfg["commission"],
            sla_heures=cfg["sla_heures"],
            abonnement_mensuel_fcfa=Decimal(str(cfg["abonnement"])),
            contact_nom=str(extra.get("contact_nom", "")).strip()[:120],
            contact_telephone=str(extra.get("contact_telephone", "")).strip()[:30],
            contact_email=str(extra.get("contact_email", "")).strip()[:254],
        )
        return {"ok": True, "account": cls.serialize_account(acc)}

    @classmethod
    def serialize_account(cls, acc) -> dict:
        return {
            "id": acc.id,
            "raison_sociale": acc.raison_sociale,
            "formule": acc.formule,
            "formule_label": acc.get_formule_display(),
            "commission_rate": acc.commission_rate,
            "sla_heures": acc.sla_heures,
            "abonnement_mensuel_fcfa": float(acc.abonnement_mensuel_fcfa),
            "actif": acc.actif,
            "nb_sites": acc.sites.filter(actif=True).count(),
        }

    @classmethod
    @transaction.atomic
    def add_site(cls, account, nom: str, **extra) -> dict:
        from ..models import ProSite

        cfg = PRO_FORMULES.get(account.formule, {})
        sites_max = cfg.get("sites_max")
        if sites_max is not None and account.sites.filter(actif=True).count() >= sites_max:
            return {
                "error": "sites_limit_reached",
                "detail": f"Votre formule {cfg.get('name')} est limitée à {sites_max} sites. "
                          "Passez à une formule supérieure.",
            }

        site = ProSite.objects.create(
            pro_account=account,
            nom=nom.strip()[:200],
            adresse=str(extra.get("adresse", "")).strip()[:500],
            commune=str(extra.get("commune", "")).strip()[:120],
            latitude=extra.get("latitude"),
            longitude=extra.get("longitude"),
            contact_sur_site=str(extra.get("contact_sur_site", "")).strip()[:120],
            telephone_sur_site=str(extra.get("telephone_sur_site", "")).strip()[:30],
        )
        return {"ok": True, "site": cls.serialize_site(site)}

    @classmethod
    def serialize_site(cls, site) -> dict:
        return {
            "id": site.id,
            "nom": site.nom,
            "adresse": site.adresse,
            "commune": site.commune,
            "latitude": site.latitude,
            "longitude": site.longitude,
            "contact_sur_site": site.contact_sur_site,
            "telephone_sur_site": site.telephone_sur_site,
            "actif": site.actif,
        }

    @classmethod
    @transaction.atomic
    def declare_intervention(cls, account, site, description: str, montant_estime=0) -> dict:
        """Déclare une panne/intervention sur un site → crée une réservation B2B."""
        from ..models import Reservation

        if site.pro_account_id != account.id:
            return {"error": "site_not_owned"}

        ref = f"PRO-{account.id}-{int(timezone.now().timestamp())}"
        resa = Reservation.objects.create(
            reference=ref,
            title=description.strip()[:200] or "Intervention B2B",
            client=account.raison_sociale[:120],
            prestataire="",
            montant=Decimal(str(montant_estime or 0)),
            statut=Reservation.Status.DEMANDE_ENVOYEE,
            payment_type=Reservation.PaymentType.AUTRE,
            pro_site=site,
            client_user=account.user,
            address_label=site.adresse or site.nom,
            latitude=site.latitude,
            longitude=site.longitude,
            description_probleme=description.strip()[:2000],
        )
        return {"ok": True, "reservation_reference": resa.reference, "id": resa.id}

    @classmethod
    @transaction.atomic
    def generate_monthly_invoice(cls, account, periode: str) -> dict:
        """
        Génère (ou met à jour) la facture mensuelle groupée d'un compte B2B.

        periode : 'AAAA-MM'. Agrège les interventions terminées du mois sur tous
        les sites du compte + l'abonnement mensuel récurrent.
        """
        from ..models import ProInvoice, Reservation

        try:
            year, month = (int(x) for x in periode.split("-"))
        except (ValueError, AttributeError):
            return {"error": "invalid_periode", "detail": "Format attendu : AAAA-MM"}

        start = timezone.datetime(year, month, 1, tzinfo=timezone.get_current_timezone())
        end = timezone.datetime(
            year + (month // 12), (month % 12) + 1, 1, tzinfo=timezone.get_current_timezone()
        )

        resas = Reservation.objects.filter(
            pro_site__pro_account=account,
            statut=Reservation.Status.DONE,
            prestation_terminee_at__gte=start,
            prestation_terminee_at__lt=end,
        ).select_related("pro_site")

        nb = resas.count()
        montant_interventions = sum((r.montant or Decimal("0")) for r in resas)
        abonnement = account.abonnement_mensuel_fcfa or Decimal("0")
        total = Decimal(str(montant_interventions)) + abonnement

        # Détail par site
        detail = {}
        for r in resas:
            key = r.pro_site.nom if r.pro_site else "—"
            row = detail.setdefault(key, {"site": key, "interventions": 0, "montant": 0.0})
            row["interventions"] += 1
            row["montant"] += float(r.montant or 0)

        invoice, _created = ProInvoice.objects.update_or_create(
            pro_account=account,
            periode=periode,
            defaults={
                "nombre_interventions": nb,
                "montant_interventions_fcfa": Decimal(str(montant_interventions)),
                "abonnement_fcfa": abonnement,
                "total_fcfa": total,
                "statut": ProInvoice.Statut.EMISE,
                "detail": list(detail.values()),
            },
        )
        return {
            "ok": True,
            "reference": invoice.reference,
            "periode": periode,
            "nombre_interventions": nb,
            "montant_interventions_fcfa": float(montant_interventions),
            "abonnement_fcfa": float(abonnement),
            "total_fcfa": float(total),
            "detail": list(detail.values()),
        }
