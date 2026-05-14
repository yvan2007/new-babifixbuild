"""
PDF Invoice/Receipt Service — Generation de factures et recus PDF
Apres paiement, le client peut telecharger sa facture/recu complet.
"""
import logging
import io
from dataclasses import dataclass, field
from typing import Optional
from decimal import Decimal

from django.contrib.auth.models import User
from django.db.models import Sum
from django.utils import timezone

from ..models import Payment, Reservation, Provider, Devis, LigneDevis, SystemSetting

logger = logging.getLogger(__name__)


@dataclass
class LineItemData:
    """Une ligne de devis/facture."""
    type_ligne: str  # FOURNITURE, MAIN_OEUVRE, DEPLACEMENT, AUTRE
    description: str
    quantite: int
    prix_unitaire: float
    total: float

    @property
    def type_label(self) -> str:
        labels = {
            "FOURNITURE": "Fourniture",
            "MAIN_OEUVRE": "Main d'œuvre",
            "DEPLACEMENT": "Déplacement",
            "AUTRE": "Autre",
        }
        return labels.get(self.type_ligne, self.type_ligne)


@dataclass
class InvoiceData:
    """Donnees completes pour la facture/recu."""
    invoice_number: str
    date: str
    client_name: str
    client_email: str
    provider_name: str
    provider_specialite: str
    provider_phone: str
    reservation_ref: str
    reservation_title: str
    intervention_date: str
    diagnostic: str
    items: list  # List[LineItemData]
    subtotal: float
    commission_pct: float
    commission_amount: float
    total_paid: float
    payment_method: str
    payment_reference: str
    operator: str = ""
    provider_net: float = 0  # Prestataire part (apres commission)
    # Phase G — escrow & traçabilité
    escrow_strategy: str = ""  # "CASH_COMMISSION_ONLY" | "MOBILE_FULL"
    paid_online: float = 0     # Montant versé en ligne (acompte escrow)
    paid_cash_to_provider: float = 0  # Solde réglé main à main (cash)
    funds_released_at: str = ""
    confirmed_at: str = ""
    photos_avant: list = field(default_factory=list)
    photos_apres: list = field(default_factory=list)
    # Journal client (témoignage post-intervention)
    client_photos_avant: list = field(default_factory=list)
    client_photos_apres: list = field(default_factory=list)
    client_journal_note: str = ""


class InvoiceService:
    """Service de generation de factures et recus PDF."""

    INVOICE_PREFIX = "FAC"
    RECEIPT_PREFIX = "REC"

    @staticmethod
    def _payment_date(payment):
        """Date du paiement : `paid_at` si présent (compat), sinon
        idempotency_used_at, sinon now (pour ne pas casser le PDF si le
        modèle Payment historique n'a pas de `paid_at`)."""
        dt = (
            getattr(payment, "paid_at", None)
            or getattr(payment, "idempotency_used_at", None)
        )
        if dt:
            return dt
        return timezone.now()

    @classmethod
    def generate_invoice_number(cls, payment: Payment) -> str:
        """Genere un numero de facture sequentiel."""
        year = cls._payment_date(payment).strftime("%Y")
        seq = payment.id or 1
        return f"{cls.INVOICE_PREFIX}-{year}-{seq:05d}"

    @classmethod
    def generate_receipt_number(cls, payment: Payment) -> str:
        """Genere un numero de recu sequentiel."""
        year = cls._payment_date(payment).strftime("%Y")
        seq = payment.id or 1
        return f"{cls.RECEIPT_PREFIX}-{year}-{seq:05d}"

    @classmethod
    def _get_commission_rate(cls, payment: Payment) -> tuple:
        """Retourne (commission_pct, commission_amount)."""
        if payment.commission and payment.montant:
            montant = Decimal(str(payment.montant))
            commission = Decimal(str(payment.commission))
            if montant > 0:
                pct = float(commission / montant * 100)
                return pct, float(commission)

        # Fallback: essayer via la reservation
        if payment.reservation:
            res = payment.reservation
            if res.commission and res.montant:
                montant = Decimal(str(res.montant))
                commission = Decimal(str(res.commission))
                if montant > 0:
                    pct = float(commission / montant * 100)
                    return pct, float(commission)

            # Essayer via le devis
            devis = Devis.objects.filter(
                reservation=res, statut=Devis.Statut.ACCEPTE
            ).first()
            if devis:
                return devis.commission_rate, float(devis.commission_montant)

        # Fallback system setting
        try:
            setting = SystemSetting.objects.first()
            pct = setting.commission if setting else 18
        except Exception:
            pct = 18

        total = float(payment.montant or 0)
        amount = total * (pct / 100)
        return pct, amount

    @classmethod
    def _get_devis_items(cls, reservation: Reservation) -> list:
        """Recupere les lignes du devis accepte pour cette reservation."""
        devis = Devis.objects.filter(
            reservation=reservation, statut=Devis.Statut.ACCEPTE
        ).first()

        if not devis:
            # Fallback: essayer le dernier devis envoye
            devis = Devis.objects.filter(
                reservation=reservation
            ).order_by("-created_at").first()

        if not devis:
            return []

        items = []
        for ligne in LigneDevis.objects.filter(devis=devis).select_related("devis"):
            items.append(LineItemData(
                type_ligne=ligne.type_ligne,
                description=ligne.description,
                quantite=ligne.quantite,
                prix_unitaire=float(ligne.prix_unitaire),
                total=float(ligne.total),
            ))

        return items

    @classmethod
    def get_invoice_data(cls, payment: Payment) -> Optional[InvoiceData]:
        """Recupere les donnees completes pour la facture/recu."""
        if not payment.reservation:
            return None

        res = payment.reservation
        client_user = res.client_user
        provider = res.assigned_provider

        # Client info
        client_name = "Client"
        client_email = ""
        if client_user:
            client_name = client_user.get_full_name() or client_user.username
            client_email = client_user.email or ""

        # Provider info
        provider_name = provider.nom if provider else (res.prestataire or "BABIFIX")
        provider_specialite = provider.specialite if provider else ""
        provider_phone = ""
        if provider and provider.user:
            provider_phone = provider.user.username if provider.user.username != provider.user.email else ""

        # Lignes du devis
        items = cls._get_devis_items(res)

        # Si pas de lignes devis, fallback sur le montant reservation
        if not items:
            items.append(LineItemData(
                type_ligne="MAIN_OEUVRE",
                description=f"Intervention - {res.title or res.description_probleme or 'Service'}",
                quantite=1,
                prix_unitaire=float(res.montant or 0),
                total=float(res.montant or 0),
            ))

        # Phase G — Préférer les données du devis (vérité métier post-Phase A)
        devis_for_totals = Devis.objects.filter(
            reservation=res, statut=Devis.Statut.ACCEPTE
        ).first() or Devis.objects.filter(reservation=res).order_by("-created_at").first()

        if devis_for_totals:
            subtotal = float(devis_for_totals.total_ttc or 0)  # ce qu'a payé le client
            commission_pct = float(devis_for_totals.commission_rate or 0)
            commission_amount = float(devis_for_totals.commission_montant or 0)
            provider_net = float(devis_for_totals.net_prestataire or 0)
        else:
            commission_pct, commission_amount = cls._get_commission_rate(payment)
            subtotal = float(res.montant or 0)
            provider_net = subtotal - commission_amount

        # Total facturé au client = subtotal (par définition Phase A)
        total_paid = subtotal

        # Phase F — Décomposition selon stratégie escrow
        is_cash = res.payment_type == Reservation.PaymentType.ESPECES
        escrow_strategy = "CASH_COMMISSION_ONLY" if is_cash else "MOBILE_FULL"
        if is_cash:
            paid_online = commission_amount       # commission versée en MM
            paid_cash_to_provider = provider_net  # solde main à main
        else:
            paid_online = subtotal
            paid_cash_to_provider = 0

        # Date d'intervention
        intervention_date = ""
        if res.prestation_terminee_at:
            intervention_date = res.prestation_terminee_at.strftime("%d/%m/%Y")
        elif res.updated_at:
            intervention_date = res.updated_at.strftime("%d/%m/%Y")

        # Diagnostic
        diagnostic = ""
        devis = Devis.objects.filter(
            reservation=res, statut=Devis.Statut.ACCEPTE
        ).first()
        if devis:
            diagnostic = devis.diagnostic or ""

        # Payment method display
        method_display = {
            "ESPECES": "Espèces",
            "MOBILE_MONEY": "Mobile Money",
            "CARTE": "Carte bancaire",
        }.get(payment.type_paiement or "", payment.type_paiement or "Espèces")

        # Operator info
        operator = ""
        if payment.type_paiement == "MOBILE_MONEY" and res.mobile_money_operator:
            operator_display = {
                "ORANGE_MONEY": "Orange Money",
                "MTN_MOMO": "MTN MoMo",
                "WAVE": "Wave",
                "MOOV": "Moov Money",
            }
            operator = operator_display.get(res.mobile_money_operator, res.mobile_money_operator)

        return InvoiceData(
            invoice_number=cls.generate_invoice_number(payment),
            date=cls._payment_date(payment).strftime("%d/%m/%Y %H:%M"),
            client_name=client_name,
            client_email=client_email,
            provider_name=provider_name,
            provider_specialite=provider_specialite,
            provider_phone=provider_phone,
            reservation_ref=res.reference,
            reservation_title=res.title or "Intervention",
            intervention_date=intervention_date,
            diagnostic=diagnostic,
            items=items,
            subtotal=subtotal,
            commission_pct=commission_pct,
            commission_amount=commission_amount,
            total_paid=total_paid,
            payment_method=method_display,
            payment_reference=payment.reference,
            operator=operator,
            provider_net=provider_net,
            escrow_strategy=escrow_strategy,
            paid_online=paid_online,
            paid_cash_to_provider=paid_cash_to_provider,
            funds_released_at=(
                res.funds_released_at.strftime("%d/%m/%Y %H:%M")
                if res.funds_released_at else ""
            ),
            confirmed_at=(
                res.client_confirme_prestation_at.strftime("%d/%m/%Y %H:%M")
                if res.client_confirme_prestation_at else ""
            ),
            photos_avant=list(res.photos_avant or []),
            photos_apres=list(res.photos_apres or []),
            client_photos_avant=list(getattr(res, "client_photos_avant", []) or []),
            client_photos_apres=list(getattr(res, "client_photos_apres", []) or []),
            client_journal_note=(getattr(res, "client_journal_note", "") or "")[:5000],
        )

    @classmethod
    def generate_pdf(cls, payment: Payment, doc_type: str = "receipt") -> Optional[bytes]:
        """Genere un PDF de la facture ou du recu."""
        data = cls.get_invoice_data(payment)
        if not data:
            return None

        try:
            from reportlab.lib.pagesizes import A4
            from reportlab.pdfgen import canvas
            from reportlab.lib.units import mm
            from reportlab.lib import colors

            buffer = io.BytesIO()
            c = canvas.Canvas(buffer, pagesize=A4)
            width, height = A4

            # ── Header avec gradient bleu ──
            c.setFillColorRGB(0.04, 0.1, 0.2)  # Navy #0B1B34
            c.rect(0, height - 55*mm, width, 55*mm, fill=1, stroke=0)

            # Logo BABIFIX
            c.setFillColorRGB(0.14, 0.55, 0.86)  # Cyan
            c.setFont("Helvetica-Bold", 24)
            c.drawString(20*mm, height - 25*mm, "BABIFIX")

            # Titre document
            if doc_type == "receipt":
                doc_title = "RECU DE PAIEMENT"
            else:
                doc_title = "FACTURE"

            c.setFillColorRGB(1, 1, 1)
            c.setFont("Helvetica-Bold", 16)
            c.drawRightString(width - 20*mm, height - 25*mm, doc_title)

            c.setFont("Helvetica", 10)
            c.drawRightString(width - 20*mm, height - 35*mm, f"N° {data.invoice_number}")
            c.drawRightString(width - 20*mm, height - 42*mm, f"Date: {data.date}")

            # ── Infos Client & Prestataire ──
            y = height - 70*mm

            # Client
            c.setFillColorRGB(0.06, 0.12, 0.22)
            c.roundRect(20*mm, y - 35*mm, 75*mm, 35*mm, 3*mm, fill=1, stroke=0)
            c.setFillColorRGB(0.57, 0.64, 0.72)
            c.setFont("Helvetica-Bold", 8)
            c.drawString(25*mm, y - 5*mm, "CLIENT")
            c.setFillColorRGB(1, 1, 1)
            c.setFont("Helvetica", 10)
            c.drawString(25*mm, y - 15*mm, data.client_name)
            if data.client_email:
                c.setFont("Helvetica", 8)
                c.drawString(25*mm, y - 23*mm, data.client_email)

            # Prestataire
            c.setFillColorRGB(0.06, 0.12, 0.22)
            c.roundRect(105*mm, y - 35*mm, 85*mm, 35*mm, 3*mm, fill=1, stroke=0)
            c.setFillColorRGB(0.57, 0.64, 0.72)
            c.setFont("Helvetica-Bold", 8)
            c.drawString(110*mm, y - 5*mm, "PRESTATAIRE")
            c.setFillColorRGB(1, 1, 1)
            c.setFont("Helvetica", 10)
            c.drawString(110*mm, y - 15*mm, data.provider_name)
            if data.provider_specialite:
                c.setFont("Helvetica", 8)
                c.drawString(110*mm, y - 23*mm, data.provider_specialite)

            # ── Reference reservation ──
            y -= 50*mm
            c.setFillColorRGB(0.08, 0.16, 0.28)
            c.roundRect(20*mm, y - 10*mm, width - 40*mm, 10*mm, 2*mm, fill=1, stroke=0)
            c.setFillColorRGB(0.94, 0.94, 0.96)
            c.setFont("Helvetica", 9)
            c.drawString(25*mm, y - 6*mm, f"Reservation: {data.reservation_ref}")
            c.drawRightString(width - 25*mm, y - 6*mm, f"Intervention: {data.intervention_date}")

            # ── Tableau des lignes ──
            y -= 25*mm
            table_y = y

            # Header du tableau
            c.setFillColorRGB(0.14, 0.55, 0.86)  # Cyan header
            c.roundRect(20*mm, y - 8*mm, width - 40*mm, 8*mm, 2*mm, fill=1, stroke=0)
            c.setFillColorRGB(1, 1, 1)
            c.setFont("Helvetica-Bold", 8)
            c.drawString(25*mm, y - 5*mm, "DESIGNATION")
            c.drawString(95*mm, y - 5*mm, "TYPE")
            c.drawRightString(120*mm, y - 5*mm, "QTE")
            c.drawRightString(145*mm, y - 5*mm, "PRIX UNIT.")
            c.drawRightString(width - 25*mm, y - 5*mm, "TOTAL")

            y -= 12*mm
            c.setFont("Helvetica", 9)

            for i, item in enumerate(data.items):
                bg_color = 0.96 if i % 2 == 0 else 0.92
                c.setFillColorRGB(bg_color, bg_color, bg_color + 0.02)
                row_height = 10*mm
                c.rect(20*mm, y - row_height, width - 40*mm, row_height, fill=1, stroke=0)

                c.setFillColorRGB(0.1, 0.1, 0.15)
                c.drawString(25*mm, y - 7*mm, item.description[:40])

                c.setFillColorRGB(0.4, 0.4, 0.5)
                c.drawString(95*mm, y - 7*mm, item.type_label[:12])

                c.drawRightString(120*mm, y - 7*mm, str(item.quantite))
                c.drawRightString(145*mm, y - 7*mm, f"{item.prix_unitaire:,.0f}")
                c.drawRightString(width - 25*mm, y - 7*mm, f"{item.total:,.0f}")

                y -= row_height

            # ── Totaux ──
            y -= 10*mm
            c.setFillColorRGB(0.06, 0.12, 0.22)
            c.roundRect(110*mm, y - 30*mm, 80*mm, 30*mm, 3*mm, fill=1, stroke=0)

            c.setFont("Helvetica", 9)
            c.setFillColorRGB(0.6, 0.65, 0.75)
            c.drawString(115*mm, y - 7*mm, "Sous-total:")
            c.setFillColorRGB(1, 1, 1)
            c.drawRightString(width - 25*mm, y - 7*mm, f"{data.subtotal:,.0f} FCFA")

            c.setFillColorRGB(0.6, 0.65, 0.75)
            c.drawString(115*mm, y - 15*mm, f"Commission BABIFIX ({data.commission_pct:.0f}%):")
            c.setFillColorRGB(1, 1, 1)
            c.drawRightString(width - 25*mm, y - 15*mm, f"{data.commission_amount:,.0f} FCFA")

            # Total final avec accent cyan
            y -= 2*mm
            c.setFillColorRGB(0.14, 0.55, 0.86)
            c.rect(110*mm, y - 10*mm, 80*mm, 0.5*mm, fill=1, stroke=0)

            c.setFont("Helvetica-Bold", 11)
            c.setFillColorRGB(0.14, 0.55, 0.86)
            c.drawString(115*mm, y - 18*mm, "TOTAL PAYE:")
            c.drawRightString(width - 25*mm, y - 18*mm, f"{data.total_paid:,.0f} FCFA")

            # ── Part prestataire ──
            y -= 20*mm
            c.setFillColorRGB(0.1, 0.3, 0.15)
            c.roundRect(20*mm, y - 10*mm, width - 40*mm, 10*mm, 2*mm, fill=1, stroke=0)
            c.setFillColorRGB(0.5, 0.9, 0.6)
            c.setFont("Helvetica", 9)
            c.drawString(25*mm, y - 6*mm, f"Part prestataire: {data.provider_net:,.0f} FCFA")
            c.drawRightString(width - 25*mm, y - 6*mm, f"Commission BABIFIX: {data.commission_amount:,.0f} FCFA")

            # ── Details paiement ──
            y -= 20*mm
            c.setFillColorRGB(0.57, 0.64, 0.72)
            c.setFont("Helvetica", 8)
            c.drawString(20*mm, y, f"Mode de paiement: {data.payment_method}")
            if data.operator:
                c.drawString(90*mm, y, f"Operateur: {data.operator}")
            c.drawString(20*mm, y - 5*mm, f"Reference: {data.payment_reference}")

            # ── Diagnostic (si present) ──
            if data.diagnostic:
                y -= 15*mm
                c.setFillColorRGB(0.06, 0.12, 0.22)
                c.roundRect(20*mm, y - 20*mm, width - 40*mm, 20*mm, 3*mm, fill=1, stroke=0)
                c.setFillColorRGB(0.57, 0.64, 0.72)
                c.setFont("Helvetica-Bold", 8)
                c.drawString(25*mm, y - 5*mm, "DIAGNOSTIC")
                c.setFillColorRGB(0.8, 0.85, 0.92)
                c.setFont("Helvetica", 8)
                diag_text = data.diagnostic[:200]
                c.drawString(25*mm, y - 13*mm, diag_text)

            # ── Pied de page ──
            c.setFillColorRGB(0.04, 0.1, 0.2)
            c.rect(0, 15*mm, width, 15*mm, fill=1, stroke=0)
            c.setFillColorRGB(0.4, 0.45, 0.55)
            c.setFont("Helvetica", 7)
            c.drawString(20*mm, 20*mm, "BABIFIX - Plateforme de services a domicile")
            c.drawRightString(width - 20*mm, 20*mm, "contact@babifix.ci - www.babifix.ci")
            c.drawCentredString(width / 2, 17*mm, "Document genere automatiquement - Fait foi de recu de paiement")

            # ============================================================
            # Page 2 — Détail escrow + photos + témoignage client
            # ============================================================
            has_extra = (
                data.escrow_strategy
                or data.client_journal_note
                or data.photos_avant
                or data.photos_apres
                or data.client_photos_avant
                or data.client_photos_apres
            )
            if has_extra:
                c.showPage()
                cls._render_page_2(c, data, width, height, mm)

            c.showPage()
            c.save()

            buffer.seek(0)
            return buffer.getvalue()

        except ImportError:
            logger.warning("reportlab non installe - generation PDF ignoree")
            return None
        except Exception as e:
            logger.exception(f"Erreur generation PDF: {e}")
            return None

    @classmethod
    def _render_page_2(cls, c, data, width, height, mm):
        """Page 2 du PDF : escrow + galerie photos + témoignage client."""
        # Header navy
        c.setFillColorRGB(0.04, 0.1, 0.2)
        c.rect(0, height - 25*mm, width, 25*mm, fill=1, stroke=0)
        c.setFillColorRGB(0.14, 0.55, 0.86)
        c.setFont("Helvetica-Bold", 18)
        c.drawString(20*mm, height - 17*mm, "BABIFIX")
        c.setFillColorRGB(1, 1, 1)
        c.setFont("Helvetica-Bold", 12)
        c.drawRightString(width - 20*mm, height - 17*mm,
                          f"Detail intervention - {data.reservation_ref}")

        y = height - 35*mm

        # ---- Bloc Escrow / Mode de paiement ----
        if data.escrow_strategy:
            c.setFillColorRGB(0.95, 0.97, 1.0)
            c.roundRect(20*mm, y - 38*mm, width - 40*mm, 38*mm, 3*mm, fill=1, stroke=0)
            c.setFillColorRGB(0.14, 0.55, 0.86)
            c.setFont("Helvetica-Bold", 11)
            c.drawString(25*mm, y - 8*mm, "STRATEGIE DE PAIEMENT")

            label = (
                "Especes (commission MM + solde main a main)"
                if data.escrow_strategy == "CASH_COMMISSION_ONLY"
                else "Mobile Money (100% en escrow plateforme)"
            )
            c.setFillColorRGB(0.1, 0.15, 0.25)
            c.setFont("Helvetica", 9)
            c.drawString(25*mm, y - 16*mm, label)

            col2_x = 110*mm
            c.setFont("Helvetica", 8)
            c.setFillColorRGB(0.4, 0.45, 0.55)
            c.drawString(25*mm, y - 24*mm, "Versement en ligne :")
            c.drawString(25*mm, y - 31*mm, "Solde cash au prestataire :")
            c.drawString(col2_x, y - 24*mm, "Total devis :")
            c.drawString(col2_x, y - 31*mm, "Part prestataire (82%) :")

            c.setFillColorRGB(0.1, 0.15, 0.25)
            c.setFont("Helvetica-Bold", 9)
            c.drawRightString(105*mm, y - 24*mm, f"{data.paid_online:,.0f} FCFA")
            c.drawRightString(105*mm, y - 31*mm,
                              f"{data.paid_cash_to_provider:,.0f} FCFA")
            c.drawRightString(width - 25*mm, y - 24*mm, f"{data.subtotal:,.0f} FCFA")
            c.drawRightString(width - 25*mm, y - 31*mm,
                              f"{data.provider_net:,.0f} FCFA")

            y -= 45*mm

        # ---- Horodatages cycle ----
        if data.confirmed_at or data.funds_released_at:
            c.setFillColorRGB(0.4, 0.45, 0.55)
            c.setFont("Helvetica", 8)
            if data.confirmed_at:
                c.drawString(25*mm, y, f"Travaux confirmes par le client : {data.confirmed_at}")
                y -= 5*mm
            if data.funds_released_at:
                c.drawString(25*mm, y, f"Fonds liberes : {data.funds_released_at}")
                y -= 5*mm
            y -= 5*mm

        # ---- Galerie photos prestataire ----
        y = cls._draw_photo_strip(
            c, mm, x=20*mm, y=y, width=width - 40*mm,
            label="Photos prestataire - avant", urls=data.photos_avant,
        )
        y = cls._draw_photo_strip(
            c, mm, x=20*mm, y=y, width=width - 40*mm,
            label="Photos prestataire - apres", urls=data.photos_apres,
        )

        # ---- Galerie photos client ----
        y = cls._draw_photo_strip(
            c, mm, x=20*mm, y=y, width=width - 40*mm,
            label="Photos client - avant (temoignage)",
            urls=data.client_photos_avant,
        )
        y = cls._draw_photo_strip(
            c, mm, x=20*mm, y=y, width=width - 40*mm,
            label="Photos client - apres (temoignage)",
            urls=data.client_photos_apres,
        )

        # ---- Témoignage client (texte) ----
        if data.client_journal_note:
            note_h = 35*mm
            if y - note_h < 30*mm:
                # pas la place : nouvelle page
                c.showPage()
                cls._page_header(c, mm, width, height, data)
                y = height - 35*mm
            c.setFillColorRGB(0.94, 1.0, 0.95)
            c.roundRect(20*mm, y - note_h, width - 40*mm, note_h, 3*mm, fill=1, stroke=0)
            c.setFillColorRGB(0.13, 0.55, 0.30)
            c.setFont("Helvetica-Bold", 10)
            c.drawString(25*mm, y - 8*mm, "TEMOIGNAGE DU CLIENT")
            c.setFillColorRGB(0.1, 0.2, 0.15)
            c.setFont("Helvetica", 9)
            # Wrap simple — découpe sur 90 chars/ligne, max 4 lignes
            note = data.client_journal_note.replace("\r", " ").replace("\n", " ")
            line_y = y - 16*mm
            for line in cls._wrap(note, 95)[:5]:
                c.drawString(25*mm, line_y, line)
                line_y -= 5*mm

        # Footer page 2
        c.setFillColorRGB(0.04, 0.1, 0.2)
        c.rect(0, 15*mm, width, 15*mm, fill=1, stroke=0)
        c.setFillColorRGB(0.4, 0.45, 0.55)
        c.setFont("Helvetica", 7)
        c.drawString(20*mm, 20*mm, "BABIFIX - Detail intervention")
        c.drawRightString(width - 20*mm, 20*mm,
                          f"Reservation {data.reservation_ref}")
        c.drawCentredString(width / 2, 17*mm,
                            "Annexe au recu - photos et temoignage client")

    @staticmethod
    def _page_header(c, mm, width, height, data):
        c.setFillColorRGB(0.04, 0.1, 0.2)
        c.rect(0, height - 25*mm, width, 25*mm, fill=1, stroke=0)
        c.setFillColorRGB(0.14, 0.55, 0.86)
        c.setFont("Helvetica-Bold", 18)
        c.drawString(20*mm, height - 17*mm, "BABIFIX")
        c.setFillColorRGB(1, 1, 1)
        c.setFont("Helvetica-Bold", 12)
        c.drawRightString(width - 20*mm, height - 17*mm,
                          f"Temoignage - {data.reservation_ref}")

    @staticmethod
    def _wrap(text: str, max_len: int) -> list:
        words = text.split()
        lines, cur = [], ""
        for w in words:
            if len(cur) + 1 + len(w) > max_len:
                lines.append(cur)
                cur = w
            else:
                cur = f"{cur} {w}".strip()
        if cur:
            lines.append(cur)
        return lines

    @classmethod
    def _draw_photo_strip(cls, c, mm, *, x, y, width, label, urls):
        """Dessine une bande de jusqu'à 4 vignettes (les autres sont
        comptabilisées dans un compteur). Retourne le nouveau y."""
        if not urls:
            return y
        thumb_w = 38*mm
        thumb_h = 28*mm
        gap = 4*mm
        # label
        c.setFillColorRGB(0.4, 0.45, 0.55)
        c.setFont("Helvetica-Bold", 8)
        c.drawString(x, y, label.upper() + f"  ({len(urls)})")
        y -= 4*mm
        # bande
        from django.conf import settings as _s
        import os
        for i, u in enumerate(urls[:4]):
            tx = x + i * (thumb_w + gap)
            # bord
            c.setFillColorRGB(0.92, 0.94, 0.97)
            c.roundRect(tx, y - thumb_h, thumb_w, thumb_h, 2*mm, fill=1, stroke=0)
            # tenter d'embarquer l'image
            local_path = None
            if isinstance(u, str):
                if u.startswith("/media/"):
                    local_path = os.path.join(
                        _s.MEDIA_ROOT, u[len("/media/"):].replace("/", os.sep)
                    )
                elif u.startswith("data:image"):
                    try:
                        import base64 as _b64
                        head, _, b = u.partition(",")
                        raw = _b64.b64decode(b)
                        import tempfile
                        tmp = tempfile.NamedTemporaryFile(
                            suffix=".jpg", delete=False
                        )
                        tmp.write(raw)
                        tmp.close()
                        local_path = tmp.name
                    except Exception:
                        local_path = None
            if local_path and os.path.exists(local_path):
                try:
                    c.drawImage(
                        local_path,
                        tx, y - thumb_h, thumb_w, thumb_h,
                        preserveAspectRatio=True, mask="auto",
                    )
                except Exception:
                    c.setFillColorRGB(0.7, 0.7, 0.75)
                    c.setFont("Helvetica", 7)
                    c.drawCentredString(
                        tx + thumb_w / 2, y - thumb_h / 2, "[image]"
                    )
            else:
                c.setFillColorRGB(0.7, 0.7, 0.75)
                c.setFont("Helvetica", 7)
                c.drawCentredString(tx + thumb_w / 2, y - thumb_h / 2, "[image]")
        y -= thumb_h + 4*mm
        if len(urls) > 4:
            c.setFillColorRGB(0.5, 0.55, 0.62)
            c.setFont("Helvetica-Oblique", 7)
            c.drawString(x, y, f"+ {len(urls) - 4} autres photos non affichees")
            y -= 5*mm
        y -= 3*mm
        return y

    @classmethod
    def get_client_invoices(cls, user: User) -> list:
        """Lister les factures/recus d'un client."""
        payments = Payment.objects.filter(
            reservation__client_user=user,
            etat=Payment.State.COMPLETE,
        ).select_related("reservation").order_by("-paid_at")

        results = []
        for p in payments:
            commission_pct, commission_amount = cls._get_commission_rate(p)
            results.append({
                "invoice_number": cls.generate_invoice_number(p),
                "date": p.paid_at.strftime("%d/%m/%Y") if p.paid_at else "",
                "reservation": p.reservation.reference if p.reservation else "",
                "reservation_title": (p.reservation.title if p.reservation else "") or "Intervention",
                "amount": float(p.montant),
                "commission_amount": commission_amount,
                "commission_pct": commission_pct,
                "total": float(p.montant),
                "payment_method": p.get_type_paiement_display(),
            })

        return results

    @classmethod
    def get_provider_invoices(cls, provider: Provider) -> list:
        """Lister les factures/recus d'un prestataire."""
        payments = Payment.objects.filter(
            reservation__assigned_provider=provider,
            etat=Payment.State.COMPLETE,
        ).select_related("reservation").order_by("-paid_at")

        results = []
        for p in payments:
            commission_pct, commission_amount = cls._get_commission_rate(p)
            total = float(p.montant)
            net = total - commission_amount

            results.append({
                "invoice_number": cls.generate_invoice_number(p),
                "date": p.paid_at.strftime("%d/%m/%Y") if p.paid_at else "",
                "reservation": p.reservation.reference if p.reservation else "",
                "client": p.reservation.client if p.reservation else "",
                "amount": total,
                "commission_amount": commission_amount,
                "commission_pct": commission_pct,
                "net": net,
                "payment_method": p.get_type_paiement_display(),
            })

        return results
