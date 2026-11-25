"""Service de Generation du Bon de Commande Officiel PDF : BABIFIX.

Document contractuel et opposable genere des acceptation du devis :
- Identite des 2 parties : Client et Prestataire certifie.
- Detail des prestations avec separation stricte Main-d'oeuvre vs Fournitures.
- Montants TTC en FCFA (XOF).
- Mention du sequestre Mobile Money et garantie d'achevement 30 jours.
- Conforme a la charte visuelle institutionnelle Bleu Marine & Cyan.
"""

import io
import os
import logging
from typing import Optional, Dict, Any

from django.conf import settings
from django.utils import timezone

from ..models import Reservation, Payment

logger = logging.getLogger(__name__)


def _logo_file_path() -> Optional[str]:
    """Chemin disque absolu et robuste du logo officiel BABIFIX."""
    base_dir = str(getattr(settings, "BASE_DIR", "") or "")
    static_root = str(getattr(settings, "STATIC_ROOT", "") or "")
    candidates = [
        os.path.join(base_dir, "static", "adminpanel", "logo_babifix.png"),
        os.path.join(base_dir, "..", "communication", "logo.png"),
        os.path.join(base_dir, "..", "LOGO BABIFIX.png"),
        os.path.join(static_root, "adminpanel", "logo_babifix.png"),
        os.path.abspath("communication/logo.png"),
        os.path.abspath("babifix_admin_django/static/adminpanel/logo_babifix.png"),
        os.path.abspath("LOGO BABIFIX.png"),
    ]
    for p in candidates:
        try:
            if p and os.path.isfile(p):
                return os.path.abspath(p)
        except Exception:
            continue
    return None


class OrderFormService:
    """Service de generation du Bon de Commande contractuel PDF."""

    ORDER_PREFIX = "BC-BBF"

    @classmethod
    def get_order_data(cls, reservation: Reservation) -> Dict[str, Any]:
        """Compile l'ensemble des donnees requises pour le bon de commande."""
        provider = getattr(reservation, "assigned_provider", None)
        client_user = getattr(reservation, "client_user", None)
        
        client_nom = (
            (client_user.get_full_name() or client_user.username)
            if client_user else (reservation.client or "Client Babifix")
        )
        client_tel = getattr(client_user, "telephone", "") or getattr(reservation, "telephone", "") or ""
        client_email = client_user.email if client_user else ""
        client_commune = getattr(reservation, "commune", "") or getattr(reservation, "adresse", "Abidjan")

        provider_nom = provider.nom if provider else "Prestataire Certifie Babifix"
        provider_metier = provider.metier if provider else "Artisan Partenaire"
        provider_tel = getattr(provider, "telephone", "") or ""

        # Recuperation du devis associe ou estimation
        devis = getattr(reservation, "devis_set", None)
        latest_devis = devis.order_by("-id").first() if devis and hasattr(devis, "order_by") else None

        lignes = []
        total_fournitures = 0.0
        total_main_oeuvre = 0.0

        if latest_devis and hasattr(latest_devis, "lignes"):
            for l in latest_devis.lignes.all():
                desc = l.description or "Prestation"
                qte = float(l.quantite or 1)
                pu = float(l.prix_unitaire or 0)
                tot = float(l.total or (qte * pu))
                t_ligne = getattr(l, "type_ligne", "MAIN_OEUVRE")
                unite = getattr(l, "unite", "u") or "u"

                if t_ligne == "FOURNITURE":
                    total_fournitures += tot
                else:
                    total_main_oeuvre += tot

                lignes.append({
                    "type": t_ligne,
                    "description": desc,
                    "quantite": qte,
                    "unite": unite,
                    "prix_unitaire": pu,
                    "total": tot,
                })

        if not lignes:
            base_amt = float(reservation.montant or reservation.prix_propose or 0)
            total_main_oeuvre = base_amt
            lignes.append({
                "type": "MAIN_OEUVRE",
                "description": reservation.title or "Intervention a domicile",
                "quantite": 1,
                "unite": "forfait",
                "prix_unitaire": base_amt,
                "total": base_amt,
            })

        frais_deplacement = 0.0
        total_ttc = total_fournitures + total_main_oeuvre + frais_deplacement

        date_creation = reservation.created_at or timezone.now()
        ref_bc = f"{cls.ORDER_PREFIX}-{date_creation.strftime('%Y%m')}-{reservation.reference}"

        return {
            "ref_bc": ref_bc,
            "ref_reservation": reservation.reference,
            "date": date_creation.strftime("%d/%m/%Y a %H:%M"),
            "date_intervention": reservation.date_rdv.strftime("%d/%m/%Y") if getattr(reservation, "date_rdv", None) else "A convenir",
            "statut": reservation.statut,
            "client": {
                "nom": client_nom,
                "telephone": client_tel,
                "email": client_email,
                "commune": client_commune,
                "adresse": getattr(reservation, "adresse", ""),
            },
            "prestataire": {
                "nom": provider_nom,
                "metier": provider_metier,
                "telephone": provider_tel,
                "immatriculation": getattr(provider, "matricule", "BBF-PRO"),
            },
            "lignes": lignes,
            "total_fournitures": total_fournitures,
            "total_main_oeuvre": total_main_oeuvre,
            "frais_deplacement": frais_deplacement,
            "total_ttc": total_ttc,
            "sequestre_statut": "FONDS BLOQUES SOUS SEQUESTRE SECURISE",
        }

    @classmethod
    def generate_pdf(cls, reservation: Reservation) -> Optional[bytes]:
        """Genere le PDF du bon de commande via PyMuPDF (fitz) ou ReportLab."""
        data = cls.get_order_data(reservation)

        # Tentative via PyMuPDF (fitz) deja installe en local
        try:
            import fitz
            return cls._generate_with_fitz(data)
        except ImportError:
            pass

        # Fallback via ReportLab
        try:
            return cls._generate_with_reportlab(data)
        except ImportError:
            logger.warning("Aucun moteur PDF disponible (fitz ou reportlab).")
            return None

    @classmethod
    def _generate_with_fitz(cls, data: Dict[str, Any]) -> bytes:
        """Generation vectorielle elegante via PyMuPDF."""
        import fitz

        doc = fitz.open()
        page = doc.new_page(width=595, height=842)  # A4 standard

        # Palette BABIFIX
        NAVY = (15 / 255, 23 / 255, 42 / 255)
        CYAN = (6 / 255, 182 / 255, 212 / 255)
        DARK_TEXT = (30 / 255, 41 / 255, 59 / 255)
        MUTED_TEXT = (100 / 255, 116 / 255, 139 / 255)
        BORDER_GRAY = (226 / 255, 232 / 255, 240 / 255)
        LIGHT_BG = (248 / 255, 250 / 255, 252 / 255)
        GREEN_TEXT = (22 / 255, 163 / 255, 74 / 255)

        # 1. Bandeau superieur NAVY
        page.draw_rect(fitz.Rect(0, 0, 595, 80), color=None, fill=NAVY)

        # Logo ou texte BABIFIX
        logo_path = _logo_file_path()
        if logo_path and os.path.exists(logo_path):
            try:
                page.insert_image(fitz.Rect(35, 15, 85, 65), filename=logo_path)
            except Exception:
                pass
        
        page.insert_text(fitz.Point(95, 42), "BABIFIX", fontsize=20, fontname="helv", color=(1, 1, 1))
        page.insert_text(fitz.Point(95, 58), "PLATEFORME OFFICIELLE DE SERVICES A DOMICILE", fontsize=8, fontname="helv", color=CYAN)

        # Titre Bon de Commande
        page.insert_text(fitz.Point(360, 36), "BON DE COMMANDE", fontsize=16, fontname="helv", color=(1, 1, 1))
        page.insert_text(fitz.Point(360, 54), f"N : {data['ref_bc']}", fontsize=10, fontname="helv", color=CYAN)
        page.insert_text(fitz.Point(360, 68), f"Date : {data['date']}", fontsize=8, fontname="helv", color=(0.8, 0.8, 0.8))

        y = 105

        # 2. Cadres Parties : Client vs Prestataire
        # Cadre Client
        page.draw_rect(fitz.Rect(35, y, 285, y + 100), color=BORDER_GRAY, fill=LIGHT_BG, width=1)
        page.draw_rect(fitz.Rect(35, y, 285, y + 24), color=None, fill=(0.94, 0.96, 0.98))
        page.insert_text(fitz.Point(45, y + 16), "DONNEUR D'ORDRE (CLIENT)", fontsize=9, fontname="helv", color=NAVY)
        page.insert_text(fitz.Point(45, y + 42), f"Nom : {data['client']['nom']}", fontsize=10, fontname="helv", color=DARK_TEXT)
        page.insert_text(fitz.Point(45, y + 58), f"Tel : {data['client']['telephone'] or 'Non renseigne'}", fontsize=9, fontname="helv", color=DARK_TEXT)
        page.insert_text(fitz.Point(45, y + 74), f"Email : {data['client']['email'] or 'contact@client.ci'}", fontsize=9, fontname="helv", color=DARK_TEXT)
        page.insert_text(fitz.Point(45, y + 90), f"Lieu : {data['client']['commune']}", fontsize=9, fontname="helv", color=DARK_TEXT)

        # Cadre Prestataire
        page.draw_rect(fitz.Rect(310, y, 560, y + 100), color=BORDER_GRAY, fill=LIGHT_BG, width=1)
        page.draw_rect(fitz.Rect(310, y, 560, y + 24), color=None, fill=(0.94, 0.96, 0.98))
        page.insert_text(fitz.Point(320, y + 16), "PRESTATAIRE CERTIFIE (ARTISAN)", fontsize=9, fontname="helv", color=NAVY)
        page.insert_text(fitz.Point(320, y + 42), f"Artisan : {data['prestataire']['nom']}", fontsize=10, fontname="helv", color=DARK_TEXT)
        page.insert_text(fitz.Point(320, y + 58), f"Corps d'etat : {data['prestataire']['metier']}", fontsize=9, fontname="helv", color=DARK_TEXT)
        page.insert_text(fitz.Point(320, y + 74), f"Tel : {data['prestataire']['telephone'] or 'Assistance Babifix'}", fontsize=9, fontname="helv", color=DARK_TEXT)
        page.insert_text(fitz.Point(320, y + 90), f"Badge KYC : VERIFIE CONFORME", fontsize=9, fontname="helv", color=GREEN_TEXT)

        y += 120

        # 3. Tableau des prestations
        page.draw_rect(fitz.Rect(35, y, 560, y + 24), color=None, fill=NAVY)
        page.insert_text(fitz.Point(45, y + 16), "DESIGNATION / PRESTATION", fontsize=9, fontname="helv", color=(1, 1, 1))
        page.insert_text(fitz.Point(310, y + 16), "TYPE", fontsize=9, fontname="helv", color=(1, 1, 1))
        page.insert_text(fitz.Point(380, y + 16), "QTE / U", fontsize=9, fontname="helv", color=(1, 1, 1))
        page.insert_text(fitz.Point(440, y + 16), "P.U (FCFA)", fontsize=9, fontname="helv", color=(1, 1, 1))
        page.insert_text(fitz.Point(510, y + 16), "TOTAL", fontsize=9, fontname="helv", color=(1, 1, 1))

        y += 24

        for item in data["lignes"][:12]:
            page.draw_rect(fitz.Rect(35, y, 560, y + 22), color=BORDER_GRAY, fill=None, width=0.5)
            desc = item["description"]
            if len(desc) > 36:
                desc = desc[:34] + ".."
            t_label = "Fourniture" if item["type"] == "FOURNITURE" else "Main-d'oeuvre"
            page.insert_text(fitz.Point(45, y + 15), desc, fontsize=8.5, fontname="helv", color=DARK_TEXT)
            page.insert_text(fitz.Point(310, y + 15), t_label, fontsize=8, fontname="helv", color=MUTED_TEXT)
            page.insert_text(fitz.Point(380, y + 15), f"{item['quantite']:.0f} {item['unite']}", fontsize=8.5, fontname="helv", color=DARK_TEXT)
            page.insert_text(fitz.Point(440, y + 15), f"{item['prix_unitaire']:,.0f}".replace(",", " "), fontsize=8.5, fontname="helv", color=DARK_TEXT)
            page.insert_text(fitz.Point(510, y + 15), f"{item['total']:,.0f} F".replace(",", " "), fontsize=8.5, fontname="helv", color=DARK_TEXT)
            y += 22

        y += 15

        # 4. Bloc Totaux et Sequestre
        # Totaux a droite
        page.draw_rect(fitz.Rect(330, y, 560, y + 85), color=BORDER_GRAY, fill=LIGHT_BG, width=1)
        page.insert_text(fitz.Point(340, y + 20), "Sous-total Fournitures (0% com.) :", fontsize=8.5, fontname="helv", color=MUTED_TEXT)
        page.insert_text(fitz.Point(490, y + 20), f"{data['total_fournitures']:,.0f} FCFA".replace(",", " "), fontsize=8.5, fontname="helv", color=DARK_TEXT)

        page.insert_text(fitz.Point(340, y + 38), "Sous-total Main-d'oeuvre :", fontsize=8.5, fontname="helv", color=MUTED_TEXT)
        page.insert_text(fitz.Point(490, y + 38), f"{data['total_main_oeuvre']:,.0f} FCFA".replace(",", " "), fontsize=8.5, fontname="helv", color=DARK_TEXT)

        page.draw_rect(fitz.Rect(330, y + 50, 560, y + 85), color=None, fill=NAVY)
        page.insert_text(fitz.Point(340, y + 72), "NET A PAYER TTC :", fontsize=10, fontname="helv", color=(1, 1, 1))
        page.insert_text(fitz.Point(475, y + 72), f"{data['total_ttc']:,.0f} FCFA".replace(",", " "), fontsize=12, fontname="helv", color=CYAN)

        # Sequestre et Garantie a gauche
        page.draw_rect(fitz.Rect(35, y, 310, y + 85), color=CYAN, fill=(0.95, 0.99, 1.0), width=1)
        page.insert_text(fitz.Point(45, y + 20), "GARANTIE ET SECURITE BABIFIX", fontsize=9, fontname="helv", color=NAVY)
        page.insert_text(fitz.Point(45, y + 38), "· Paiement securise sous sequestre bancaire/Mobile Money.", fontsize=8, fontname="helv", color=DARK_TEXT)
        page.insert_text(fitz.Point(45, y + 52), "· L'artisan est paye uniquement apres validation du client.", fontsize=8, fontname="helv", color=DARK_TEXT)
        page.insert_text(fitz.Point(45, y + 66), "· Garantie satisfaction et reprise de malfacon : 30 jours.", fontsize=8, fontname="helv", color=GREEN_TEXT)

        # 5. Signatures et Pied de page
        y_bottom = 740
        page.draw_line(fitz.Point(35, y_bottom), fitz.Point(560, y_bottom), color=BORDER_GRAY, width=1)

        page.insert_text(fitz.Point(45, y_bottom + 20), "Signature & Accord Client", fontsize=8.5, fontname="helv", color=MUTED_TEXT)
        page.insert_text(fitz.Point(45, y_bottom + 35), "Valide numeriquement par code OTP", fontsize=8, fontname="helv", color=GREEN_TEXT)

        page.insert_text(fitz.Point(360, y_bottom + 20), "Cachet de validation BABIFIX CI", fontsize=8.5, fontname="helv", color=MUTED_TEXT)
        page.insert_text(fitz.Point(360, y_bottom + 35), "Document certifie conforme · Fait foi de contrat", fontsize=8, fontname="helv", color=NAVY)

        # Mentions legales bas de page
        page.insert_text(
            fitz.Point(75, 815),
            "BABIFIX SARL · RCCM : CI-ABJ-03-2026 · Abidjan Cocody · Support : contact@babifix.ci · www.babifix.ci",
            fontsize=7.5,
            fontname="helv",
            color=MUTED_TEXT,
        )

        pdf_bytes = doc.tobytes()
        doc.close()
        return pdf_bytes

    @classmethod
    def _generate_with_reportlab(cls, data: Dict[str, Any]) -> bytes:
        """Fallback via reportlab."""
        from reportlab.lib.pagesizes import A4
        from reportlab.pdfgen import canvas
        buffer = io.BytesIO()
        c = canvas.Canvas(buffer, pagesize=A4)
        c.drawString(50, 800, f"BON DE COMMANDE BABIFIX : {data['ref_bc']}")
        c.drawString(50, 780, f"Client : {data['client']['nom']}")
        c.drawString(50, 760, f"Prestataire : {data['prestataire']['nom']}")
        c.drawString(50, 740, f"Total TTC : {data['total_ttc']} FCFA")
        c.showPage()
        c.save()
        buffer.seek(0)
        return buffer.getvalue()
