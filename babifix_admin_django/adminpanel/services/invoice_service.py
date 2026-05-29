"""
PDF Invoice Service — Generation de factures PDF
Apres paiement, le client peut telecharger sa facture.
"""
import logging
import io
from dataclasses import dataclass
from typing import Optional

from django.contrib.auth.models import User
from django.db.models import Sum
from django.utils import timezone

from ..models import Payment, Reservation, Provider

logger = logging.getLogger(__name__)


@dataclass
class InvoiceData:
    """Donnees pour la facture."""
    invoice_number: str
    date: str
    client_name: str
    client_email: str
    provider_name: str
    provider_address: str
    reservation_ref: str
    intervention_date: str
    description: str
    items: list  # [{"description", "qty", "unit_price", "total"}]
    subtotal: float
    commission_pct: float
    commission_amount: float
    total_paid: float
    payment_method: str


class InvoiceService:
    """Service de generation de factures PDF."""
    
    INVOICE_PREFIX = "FAC"
    
    @classmethod
    def generate_invoice_number(cls, payment: Payment) -> str:
        """Genere un numero de facture sequentiel."""
        from django.utils import timezone
        year = timezone.now().strftime("%Y")
        # Sequence simple - en prod, utiliser une table de sequence
        seq = payment.id or 1
        return f"{cls.INVOICE_PREFIX}-{year}-{seq:05d}"
    
    @classmethod
    def get_invoice_data(cls, payment: Payment) -> Optional[InvoiceData]:
        """Recupere les donnees pour la facture."""
        if not payment.reservation:
            return None
        
        res = payment.reservation
        provider = getattr(res, "assigned_provider", None)
        # Reservation.client est un libellé (CharField) ; le vrai compte est client_user.
        client_user = getattr(res, "client_user", None)
        client_name = (
            (client_user.get_full_name() or client_user.username)
            if client_user else (res.client or "Client")
        )
        client_email = client_user.email if client_user else ""

        montant = float(payment.montant or 0)

        # Calculer les items
        base_amount = float(res.montant or res.prix_propose or montant or 0)
        items = [{
            "description": f"Intervention - {res.title or res.reference}",
            "qty": 1,
            "unit_price": base_amount,
            "total": base_amount,
        }]

        commission_pct = 18.0
        commission_amount = base_amount * (commission_pct / 100)
        total_paid = montant or base_amount
        date_str = (
            res.prestation_terminee_at.strftime("%d/%m/%Y")
            if getattr(res, "prestation_terminee_at", None) else ""
        )

        return InvoiceData(
            invoice_number=cls.generate_invoice_number(payment),
            date=date_str,
            client_name=client_name,
            client_email=client_email,
            provider_name=provider.nom if provider else "BABIFIX",
            provider_address=getattr(provider, "adresse", "") if provider else "",
            reservation_ref=res.reference,
            intervention_date=date_str,
            description=getattr(res, "description_probleme", "") or res.title or "",
            items=items,
            subtotal=base_amount,
            commission_pct=commission_pct,
            commission_amount=commission_amount,
            total_paid=total_paid,
            payment_method=payment.type_paiement or "ESPECES",
        )
    
    @classmethod
    def generate_pdf(cls, payment: Payment) -> Optional[bytes]:
        """Génère le reçu PDF pro BABIFIX : en-tête dégradé navy→cyan,
        bandeau "PAIEMENT REÇU", section adresse structurée, tableau lignes,
        récap montant + commission Façon B (déduite côté prestataire),
        opérateur Mobile Money en évidence, footer mentions légales."""
        data = cls.get_invoice_data(payment)
        if not data:
            return None

        try:
            from reportlab.lib.pagesizes import A4
            from reportlab.pdfgen import canvas
            from reportlab.lib.units import mm
            from reportlab.lib.colors import HexColor

            # Couleurs BABIFIX
            NAVY    = HexColor("#0F172A")
            CYAN    = HexColor("#06B6D4")
            ORANGE  = HexColor("#F59E0B")
            GREEN   = HexColor("#22C55E")
            SLATE   = HexColor("#334155")
            SUB     = HexColor("#64748B")
            LIGHT   = HexColor("#F1F5F9")
            BORDER  = HexColor("#E2E8F0")

            buffer = io.BytesIO()
            c = canvas.Canvas(buffer, pagesize=A4)
            W, H = A4

            # ── HEADER avec dégradé navy → cyan ──────────────────────────
            steps = 60
            for i in range(steps):
                t = i / steps
                r = (0x0F + (0x06 - 0x0F) * t * 0.5) / 255
                g = (0x17 + (0xB6 - 0x17) * t * 0.5) / 255
                b = (0x2A + (0xD4 - 0x2A) * t * 0.5) / 255
                c.setFillColorRGB(r, g, b)
                c.rect(0, H - 38*mm + (i * 38*mm / steps), W, 38*mm / steps + 0.5, stroke=0, fill=1)

            # Logo / nom
            c.setFillColorRGB(1, 1, 1)
            c.setFont("Helvetica-Bold", 24)
            c.drawString(20*mm, H - 18*mm, "BABIFIX")
            c.setFont("Helvetica", 9)
            c.drawString(20*mm, H - 23*mm, "Services à domicile  —  Côte d'Ivoire")

            # Bandeau "Reçu de paiement"
            c.setFont("Helvetica-Bold", 13)
            c.setFillColor(HexColor("#FDE68A"))  # jaune pâle pour contraste
            c.drawRightString(W - 20*mm, H - 18*mm, "REÇU DE PAIEMENT")
            c.setFont("Helvetica", 10)
            c.setFillColorRGB(1, 1, 1)
            c.drawRightString(W - 20*mm, H - 25*mm, data.invoice_number)
            date_fr = data.date or timezone.now().strftime("%d %B %Y à %H:%M")
            c.drawRightString(W - 20*mm, H - 30*mm, date_fr)

            # ── PASTILLE STATUT « PAYÉ » ─────────────────────────────────
            c.setFillColor(GREEN)
            c.roundRect(20*mm, H - 50*mm, 35*mm, 8*mm, 4*mm, stroke=0, fill=1)
            c.setFillColorRGB(1, 1, 1)
            c.setFont("Helvetica-Bold", 10)
            c.drawCentredString(37.5*mm, H - 44.5*mm, "✓ PAYÉ")

            # ── 2 COLONNES CLIENT / PRESTATAIRE ──────────────────────────
            y_top = H - 62*mm

            def section(x, label, color):
                c.setFillColor(color)
                c.rect(x, y_top, 1.5*mm, 4*mm, stroke=0, fill=1)
                c.setFillColor(SLATE)
                c.setFont("Helvetica-Bold", 9)
                c.drawString(x + 4*mm, y_top + 1*mm, label.upper())

            section(20*mm, "Émis par", CYAN)
            section(110*mm, "Pour le compte de", ORANGE)

            c.setFillColor(NAVY)
            c.setFont("Helvetica-Bold", 11)
            c.drawString(20*mm, y_top - 6*mm, data.provider_name or "—")
            c.drawString(110*mm, y_top - 6*mm, data.client_name or "—")

            c.setFillColor(SUB)
            c.setFont("Helvetica", 9)
            c.drawString(20*mm, y_top - 11*mm, "Prestataire BABIFIX")
            c.drawString(110*mm, y_top - 11*mm, data.client_email or "")

            # ── INFOS RÉSERVATION ───────────────────────────────────────
            y_box = y_top - 24*mm
            c.setFillColor(LIGHT)
            c.roundRect(20*mm, y_box - 18*mm, W - 40*mm, 18*mm, 3*mm, stroke=0, fill=1)

            c.setFillColor(SLATE)
            c.setFont("Helvetica", 8)
            c.drawString(25*mm, y_box - 5*mm, "RÉSERVATION")
            c.drawString(80*mm, y_box - 5*mm, "DATE D'INTERVENTION")
            c.drawString(135*mm, y_box - 5*mm, "MOYEN DE PAIEMENT")

            c.setFillColor(NAVY)
            c.setFont("Helvetica-Bold", 10)
            c.drawString(25*mm, y_box - 10.5*mm, data.reservation_ref or "—")
            c.drawString(80*mm, y_box - 10.5*mm, data.intervention_date or "Non précisée")
            # Mode de paiement plus lisible
            pm_label = {
                "MOBILE_MONEY": "Mobile Money",
                "ESPECES":      "Espèces",
                "CARTE":        "Carte bancaire",
            }.get(str(data.payment_method).upper(), str(data.payment_method or "—"))
            c.drawString(135*mm, y_box - 10.5*mm, pm_label)

            # ── TABLEAU DES LIGNES ──────────────────────────────────────
            y_tab = y_box - 28*mm
            # En-tête
            c.setFillColor(NAVY)
            c.rect(20*mm, y_tab, W - 40*mm, 7*mm, stroke=0, fill=1)
            c.setFillColorRGB(1, 1, 1)
            c.setFont("Helvetica-Bold", 9)
            c.drawString(23*mm, y_tab + 2.3*mm, "DÉSIGNATION")
            c.drawString(123*mm, y_tab + 2.3*mm, "QTÉ")
            c.drawRightString(160*mm, y_tab + 2.3*mm, "P.U. (XOF)")
            c.drawRightString(W - 23*mm, y_tab + 2.3*mm, "TOTAL (XOF)")

            # Lignes
            y_row = y_tab - 7*mm
            c.setFont("Helvetica", 9.5)
            c.setFillColor(SLATE)
            for i, item in enumerate(data.items):
                if i % 2 == 1:
                    c.setFillColor(LIGHT)
                    c.rect(20*mm, y_row - 1*mm, W - 40*mm, 7*mm, stroke=0, fill=1)
                c.setFillColor(SLATE)
                desc = item["description"][:60]
                c.drawString(23*mm, y_row + 1.5*mm, desc)
                c.drawString(123*mm, y_row + 1.5*mm, str(item["qty"]))
                c.drawRightString(160*mm, y_row + 1.5*mm, f"{item['unit_price']:,.0f}".replace(",", " "))
                c.drawRightString(W - 23*mm, y_row + 1.5*mm, f"{item['total']:,.0f}".replace(",", " "))
                y_row -= 7*mm

            # ── RÉCAP TOTAUX ────────────────────────────────────────────
            y_rec = y_row - 6*mm
            c.setStrokeColor(BORDER)
            c.line(115*mm, y_rec + 3*mm, W - 20*mm, y_rec + 3*mm)

            c.setFillColor(SLATE)
            c.setFont("Helvetica", 10)
            c.drawString(120*mm, y_rec - 3*mm, "Sous-total")
            c.drawRightString(W - 23*mm, y_rec - 3*mm, f"{data.subtotal:,.0f} XOF".replace(",", " "))

            # Commission Façon B : on l'indique comme info, pas comme ajoutée
            c.setFont("Helvetica-Oblique", 8)
            c.setFillColor(SUB)
            c.drawString(120*mm, y_rec - 9*mm,
                         f"(Commission BABIFIX {data.commission_pct}% déduite côté prestataire)")

            # Total en gros, dans encart cyan large
            box_x = 115*mm
            box_w = W - 20*mm - box_x   # de 115mm jusqu'à 20mm du bord droit
            c.setFillColor(CYAN)
            c.roundRect(box_x, y_rec - 22*mm, box_w, 11*mm, 3*mm, stroke=0, fill=1)
            c.setFillColorRGB(1, 1, 1)
            c.setFont("Helvetica-Bold", 10)
            c.drawString(box_x + 4*mm, y_rec - 17.5*mm, "TOTAL PAYÉ")
            c.setFont("Helvetica-Bold", 13)
            c.drawRightString(box_x + box_w - 4*mm, y_rec - 17.5*mm,
                              f"{data.total_paid:,.0f} XOF".replace(",", " "))

            # ── PIED DE PAGE ────────────────────────────────────────────
            # Ligne de séparation
            c.setStrokeColor(BORDER)
            c.line(20*mm, 30*mm, W - 20*mm, 30*mm)

            c.setFillColor(SUB)
            c.setFont("Helvetica-Bold", 8)
            c.drawString(20*mm, 24*mm, "BABIFIX")
            c.setFont("Helvetica", 8)
            c.drawString(20*mm, 19*mm, "Plateforme de mise en relation entre clients et artisans qualifiés.")
            c.drawString(20*mm, 15*mm, "contact@babifix.ci  •  +225 27 22 00 00 00  •  www.babifix.ci  •  Abidjan, Côte d'Ivoire")

            # Mention légale
            c.setFont("Helvetica-Oblique", 7)
            c.setFillColor(HexColor("#94A3B8"))
            c.drawRightString(W - 20*mm, 19*mm, "Document généré automatiquement — fait foi sans signature.")
            c.drawRightString(W - 20*mm, 15*mm, f"Référence transaction : {payment.reference_externe or payment.reference}")

            c.showPage()
            c.save()
            buffer.seek(0)
            return buffer.getvalue()

        except ImportError:
            logger.warning("reportlab non installé — génération PDF ignorée")
            return None
        except Exception as e:
            logger.exception(f"Erreur génération PDF: {e}")
            return None
    
    @classmethod
    def get_client_invoices(cls, user: User) -> list:
        """Lister les factures d'un client."""
        payments = Payment.objects.filter(
            reservation__client_user_id=getattr(user, "id", user),
            etat=Payment.State.COMPLETE,
        ).select_related("reservation").order_by("-id")

        return [
            {
                "invoice_number": cls.generate_invoice_number(p),
                "date": (
                    p.reservation.prestation_terminee_at.strftime("%d/%m/%Y")
                    if p.reservation_id and p.reservation.prestation_terminee_at else ""
                ),
                "reservation": p.reservation.reference if p.reservation_id else "",
                "amount": float(p.montant or 0),
                "total": float(p.montant or 0),
            }
            for p in payments
        ]
    
    @classmethod
    def get_provider_invoices(cls, provider: Provider) -> list:
        """Lister les factures d'un prestataire."""
        payments = Payment.objects.filter(
            reservation__assigned_provider=provider,
            etat=Payment.State.COMPLETE,
        ).select_related("reservation").order_by("-id")

        return [
            {
                "invoice_number": cls.generate_invoice_number(p),
                "date": (
                    p.reservation.prestation_terminee_at.strftime("%d/%m/%Y")
                    if p.reservation_id and p.reservation.prestation_terminee_at else ""
                ),
                "reservation": p.reservation.reference if p.reservation_id else "",
                "client": (p.reservation.client if p.reservation_id else "") or "",
                "amount": float(p.montant or 0),
                "net": float(p.montant or 0) * 0.82,  # Apres commission
            }
            for p in payments
        ]