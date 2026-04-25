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
        year = payment.paid_at.strftime("%Y") if payment.paid_at else "0000"
        # Sequence simple - en prod, utiliser une table de sequence
        seq = payment.id or 1
        return f"{cls.INVOICE_PREFIX}-{year}-{seq:05d}"
    
    @classmethod
    def get_invoice_data(cls, payment: Payment) -> Optional[InvoiceData]:
        """Recupere les donnees pour la facture."""
        if not payment.reservation:
            return None
        
        res = payment.reservation
        client = res.client
        provider = res.provider
        
        # Calculer les items
        items = []
        
        # Frais de main d'oeuvre
        items.append({
            "description": f"Intervention - {res.title}",
            "qty": 1,
            "unit_price": float(res.prix_propose or 0),
            "total": float(res.prix_propose or 0),
        })
        
        # Calcul commission (18% par defaut)
        base_amount = float(res.prix_propose or 0)
        commission_pct = 18.0
        commission_amount = base_amount * (commission_pct / 100)
        total_paid = float(payment.amount)
        
        return InvoiceData(
            invoice_number=cls.generate_invoice_number(payment),
            date=payment.paid_at.strftime("%d/%m/%Y") if payment.paid_at else "",
            client_name=client.get_full_name() or client.username,
            client_email=client.email or "",
            provider_name=provider.nom if provider else "BABIFIX",
            provider_address=provider.adresse if provider else "",
            reservation_ref=res.reference,
            intervention_date=res.updated_at.strftime("%d/%m/%Y") if res.updated_at else "",
            description=res.description or res.title,
            items=items,
            subtotal=base_amount,
            commission_pct=commission_pct,
            commission_amount=commission_amount,
            total_paid=total_paid,
            payment_method=payment.payment_method or "ESPECES",
        )
    
    @classmethod
    def generate_pdf(cls, payment: Payment) -> Optional[bytes]:
        """Genere un PDF de la facture.
        
        Utilise ReportLab ou WeasyPrint en production.
        En dev, retourne un PDF minimal.
        """
        data = cls.get_invoice_data(payment)
        if not data:
            return None
        
        # Import dynamique pour eviter dependance obligatoire
        try:
            from reportlab.lib.pagesizes import A4
            from reportlab.pdfgen import canvas
            from reportlab.lib.units import mm
            
            buffer = io.BytesIO()
            c = canvas.Canvas(buffer, pagesize=A4)
            width, height = A4
            
            # En-tete
            c.setFont("Helvetica-Bold", 18)
            c.drawString(20*mm, height - 30*mm, "FACTURE")
            
            c.setFont("Helvetica", 10)
            c.drawString(20*mm, height - 45*mm, f"Numero: {data.invoice_number}")
            c.drawString(20*mm, height - 52*mm, f"Date: {data.date}")
            
            # Client
            c.drawString(120*mm, height - 30*mm, "Client:")
            c.drawString(120*mm, height - 37*mm, data.client_name)
            c.drawString(120*mm, height - 44*mm, data.client_email)
            
            # Prestataire
            c.drawString(20*mm, height - 65*mm, "Prestataire:")
            c.drawString(20*mm, height - 72*mm, data.provider_name)
            c.drawString(20*mm, height - 79*mm, data.provider_address)
            
            # Reference reservation
            c.drawString(120*mm, height - 65*mm, "Reservation:")
            c.drawString(120*mm, height - 72*mm, data.reservation_ref)
            
            # Tableau des produits
            y = height - 110*mm
            c.setFont("Helvetica-Bold", 10)
            c.drawString(20*mm, y, "Description")
            c.drawString(100*mm, y, "Qte")
            c.drawString(120*mm, y, "Prix unit.")
            c.drawString(155*mm, y, "Total")
            
            y -= 10*mm
            c.setFont("Helvetica", 9)
            for item in data.items:
                c.drawString(20*mm, y, item["description"][:40])
                c.drawString(100*mm, y, str(item["qty"]))
                c.drawString(120*mm, y, f"{item['unit_price']:.0f} CFA")
                c.drawString(155*mm, y, f"{item['total']:.0f} CFA")
                y -= 8*mm
            
            # Totaux
            y -= 15*mm
            c.drawString(120*mm, y, "Sous-total:")
            c.drawString(155*mm, y, f"{data.subtotal:.0f} CFA")
            
            y -= 8*mm
            c.drawString(120*mm, y, f"Commission ({data.commission_pct}%):")
            c.drawString(155*mm, y, f"-{data.commission_amount:.0f} CFA")
            
            y -= 10*mm
            c.setFont("Helvetica-Bold", 12)
            c.drawString(120*mm, y, "Total paye:")
            c.drawString(155*mm, y, f"{data.total_paid:.0f} CFA")
            
            # Methode de paiement
            y -= 15*mm
            c.setFont("Helvetica", 8)
            c.drawString(20*mm, y, f"Paiement: {data.payment_method}")
            
            # Pied de page
            c.setFont("Helvetica", 8)
            c.drawString(20*mm, 20*mm, "BABIFIX - contact@babifix.ci - www.babifix.ci")
            
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
    def get_client_invoices(cls, user: User) -> list:
        """Lister les factures d'un client."""
        payments = Payment.objects.filter(
            reservation__client=user,
            etat=Payment.State.COMPLETE,
        ).order_by("-paid_at")
        
        return [
            {
                "invoice_number": cls.generate_invoice_number(p),
                "date": p.paid_at.strftime("%d/%m/%Y") if p.paid_at else "",
                "reservation": p.reservation.reference if p.reservation else "",
                "amount": float(p.amount),
                "total": float(p.amount),
            }
            for p in payments
        ]
    
    @classmethod
    def get_provider_invoices(cls, provider: Provider) -> list:
        """Lister les factures d'un prestataire."""
        payments = Payment.objects.filter(
            provider=provider,
            etat=Payment.State.COMPLETE,
        ).order_by("-paid_at")
        
        return [
            {
                "invoice_number": cls.generate_invoice_number(p),
                "date": p.paid_at.strftime("%d/%m/%Y") if p.paid_at else "",
                "reservation": p.reservation.reference if p.reservation else "",
                "client": p.reservation.client.username if p.reservation else "",
                "amount": float(p.amount),
                "net": float(p.amount) * 0.82,  # Apres commission
            }
            for p in payments
        ]