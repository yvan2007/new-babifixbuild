"""
PDF Invoice Service : Generation de factures et recus officiels PDF pour BABIFIX.
Document opposable, exact financierement et conforme OHADA (Direction 3 Hybride).
"""
from __future__ import annotations

import hashlib
import io
import logging
import os
from dataclasses import dataclass
from decimal import Decimal
from typing import Any, Dict, List, Optional

from django.contrib.auth.models import User
from django.utils import timezone
from reportlab.graphics.barcode.qr import QrCodeWidget
from reportlab.graphics.shapes import Drawing
from reportlab.lib.colors import HexColor
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.pdfgen import canvas

from ..models import Payment, Provider
from .email_service import find_logo_path, format_fcfa, format_french_date

logger = logging.getLogger(__name__)


@dataclass
class InvoiceData:
    """Donnees exhaustives structurees pour la facture officielle."""
    invoice_number: str
    date_emission: str
    reservation_ref: str
    status_label: str
    is_fully_paid: bool
    is_client_view: bool
    client_name: str
    client_tel: str
    client_email: str
    client_commune: str
    client_adresse: str
    provider_name: str
    provider_metier: str
    provider_tel: str
    provider_matricule: str
    description: str
    items: List[Dict[str, Any]]
    total_fournitures: float
    total_main_oeuvre: float
    sous_total_ttc: float
    remise_devis: float
    remise_fidelite: float
    caution_montant: float
    caution_payee: bool
    caution_deduite: bool
    frais_mise_en_relation: float
    commission_pct: float
    commission_amount: float
    net_prestataire: float
    total_paid: float
    reste_a_payer: float
    acompte_montant: float
    solde_montant: float
    acompte_valide: bool
    solde_valide: bool
    payment_method: str
    ref_transaction: str


class InvoiceService:
    """Service d'emission et de certification de factures PDF pour BABIFIX."""

    INVOICE_PREFIX = "FAC"

    @classmethod
    def generate_invoice_number(cls, payment: Payment) -> str:
        """Genere un numero de facture sequentiel officiel."""
        ref_dt = getattr(payment, "created_at", None) or timezone.now()
        year = ref_dt.strftime("%Y")
        month = ref_dt.strftime("%m")
        seq = payment.id or 1
        return f"{cls.INVOICE_PREFIX}-{year}{month}-{seq:05d}"

    @classmethod
    def get_invoice_data(cls, payment: Payment, *, is_client_view: bool = True) -> Optional[InvoiceData]:
        """Compile et reconcilie l'integralite des donnees financieres de la mission."""
        res = getattr(payment, "reservation", None)
        if not res:
            return None

        provider = getattr(res, "assigned_provider", None)
        client_user = getattr(res, "client_user", None)

        client_name = (
            ((client_user.get_full_name() or client_user.username) if client_user else "")
            or (res.client or "Client BABIFIX")
        ).strip()
        client_tel = (
            getattr(client_user, "telephone", "")
            or getattr(res, "telephone", "")
            or ""
        )
        client_email = (getattr(client_user, "email", "") or "").strip()
        if not client_email and "@" in (res.client or ""):
            client_email = res.client.strip()
        client_commune = (
            getattr(res, "address_quartier", "")
            or getattr(res, "address_ville", "")
            or getattr(res, "commune", "")
            or "Cote d'Ivoire"
        )
        client_adresse = (
            getattr(res, "address_label", "")
            or getattr(res, "adresse", "")
            or client_commune
        )

        provider_name = (provider.nom if provider else "") or res.prestataire or "Prestataire Certifie BABIFIX"
        provider_metier = (
            getattr(provider, "specialite", "")
            or getattr(provider, "metier", "")
            or res.title
            or "Artisan Qualifie"
        )
        provider_tel = getattr(provider, "telephone", "") or "Assistance BABIFIX"
        provider_matricule = f"BBF-PRO-{(provider.id if provider else 1):04d}"

        devis_qs = getattr(res, "devis_set", None)
        latest_devis = None
        if devis_qs is not None and hasattr(devis_qs, "filter"):
            latest_devis = (
                devis_qs.filter(statut="ACCEPTE").order_by("-created_at").first()
                or devis_qs.filter(statut="ENVOYE").order_by("-created_at").first()
                or devis_qs.order_by("-created_at").first()
            )

        items: List[Dict[str, Any]] = []
        total_fournitures = 0.0
        total_main_oeuvre = 0.0
        remise_devis = 0.0

        if latest_devis and hasattr(latest_devis, "lignes"):
            remise_devis = float(getattr(latest_devis, "remise", 0) or 0)
            for li in latest_devis.lignes.all():
                desc = li.description or "Prestation technique"
                qte = float(li.quantite or 1)
                pu = float(li.prix_unitaire or 0)
                tot = float(li.total or (qte * pu))
                t_ligne = getattr(li, "type_ligne", "MAIN_OEUVRE")
                unite = getattr(li, "unite", "u") or "u"
                if t_ligne == "FOURNITURE":
                    total_fournitures += tot
                else:
                    total_main_oeuvre += tot
                items.append({
                    "description": desc,
                    "type": t_ligne,
                    "qty": int(qte) if qte == int(qte) else qte,
                    "unit": unite,
                    "unit_price": pu,
                    "total": tot,
                })

        montant_paye_tx = float(payment.montant or 0)
        caution_montant = float(getattr(res, "caution_montant", 0) or 0)
        caution_payee = bool(getattr(res, "caution_payee", False))
        caution_deduite = bool(getattr(res, "caution_deduite", False))
        remise_fidelite = float(getattr(res, "remise_fidelite", 0) or 0)

        if latest_devis and float(getattr(latest_devis, "total_ttc", 0) or 0) > 0:
            sous_total_ttc = float(latest_devis.total_ttc)
        else:
            raw_sum = total_fournitures + total_main_oeuvre - remise_devis
            if raw_sum > 0:
                sous_total_ttc = raw_sum
            else:
                res_m = float(res.montant or 0)
                if caution_deduite:
                    res_m += caution_montant
                sous_total_ttc = res_m or float(res.prix_propose or 0) or montant_paye_tx

        if not items:
            total_main_oeuvre = sous_total_ttc
            items.append({
                "description": res.title or f"Prestation {res.reference}",
                "type": "MAIN_OEUVRE",
                "qty": 1,
                "unit": "forfait",
                "unit_price": sous_total_ttc,
                "total": sous_total_ttc,
            })

        try:
            from ..models import PlatformConfig
            frais_mer = float(PlatformConfig.get_solo().frais_mise_en_relation_fcfa or 0) if caution_payee else 0.0
        except Exception:
            frais_mer = 500.0 if caution_payee else 0.0

        # Montant attendu sur le devis (apres deduction caution deja reglee + remise fidelite)
        caution_deduite_effectif = caution_montant if (caution_payee and caution_deduite) else 0.0
        net_devis_a_regler = max(0.0, sous_total_ttc - caution_deduite_effectif - remise_fidelite)

        solde_valide = bool(getattr(res, "solde_valide", False))
        acompte_valide = bool(getattr(res, "acompte_valide", False))

        # Ce qui a reellement ete paye sur la prestation
        if solde_valide:
            devis_deja_paye = net_devis_a_regler
        else:
            devis_deja_paye = float(getattr(res, "montant_verse", 0) or 0)
            if devis_deja_paye <= 0 and not caution_payee:
                devis_deja_paye = min(montant_paye_tx, net_devis_a_regler) if net_devis_a_regler > 0 else montant_paye_tx

        caution_reglee_val = caution_montant if caution_payee else 0.0
        total_paid = round(devis_deja_paye + caution_reglee_val)
        reste_a_payer = max(0.0, round(net_devis_a_regler - devis_deja_paye))
        is_fully_paid = solde_valide or (reste_a_payer <= 0 and total_paid > 0)

        if is_fully_paid:
            status_label = "PAYE EN INTEGRALITE"
        elif acompte_valide:
            status_label = "ACOMPTE REGLE"
        elif caution_payee:
            status_label = "CAUTION REGLEE"
        else:
            status_label = "PAIEMENT VALIDE"

        # Taux de commission reel fige sur le devis (18 / 13 / 8 %) sinon taux actif du presta
        commission_pct = 18.0
        if latest_devis and getattr(latest_devis, "commission_rate", None) is not None:
            commission_pct = float(latest_devis.commission_rate)
        elif provider is not None:
            try:
                from .wallet_service import _get_effective_commission_rate
                commission_pct = float(_get_effective_commission_rate(provider) * Decimal("100"))
            except Exception:
                commission_pct = 18.0

        assiette_comm = max(0.0, sous_total_ttc - (caution_montant if caution_payee else 0.0))
        commission_amount = round(assiette_comm * (commission_pct / 100.0))
        net_prestataire = max(0.0, round(sous_total_ttc - commission_amount))

        pm_raw = str(payment.type_paiement or res.mobile_money_operator or res.payment_type or "MOBILE_MONEY").upper()
        pm_map = {
            "MOBILE_MONEY": "Mobile Money CI",
            "ORANGE_MONEY": "Orange Money CI",
            "WAVE": "Wave Mobile Money",
            "MTN_MOMO": "MTN Mobile Money",
            "MOOV": "Moov Money CI",
            "MOOV_MONEY": "Moov Money CI",
            "ESPECES": "Especes securisees avec attestation",
            "CARTE": "Carte bancaire Visa / Mastercard",
        }
        pm_label = pm_map.get(pm_raw, "Mobile Money CI")

        ref_dt = getattr(payment, "created_at", None) or getattr(res, "prestation_terminee_at", None) or timezone.now()
        date_str = format_french_date(ref_dt, with_time=True)
        tx_ref = payment.reference_externe or payment.reference or f"TX-BBF-{payment.id:06d}"

        return InvoiceData(
            invoice_number=cls.generate_invoice_number(payment),
            date_emission=date_str,
            reservation_ref=res.reference,
            status_label=status_label,
            is_fully_paid=is_fully_paid,
            is_client_view=is_client_view,
            client_name=client_name,
            client_tel=client_tel,
            client_email=client_email,
            client_commune=client_commune,
            client_adresse=client_adresse,
            provider_name=provider_name,
            provider_metier=provider_metier,
            provider_tel=provider_tel,
            provider_matricule=provider_matricule,
            description=getattr(res, "description_probleme", "") or res.title or "Intervention a domicile",
            items=items,
            total_fournitures=total_fournitures,
            total_main_oeuvre=total_main_oeuvre,
            sous_total_ttc=sous_total_ttc,
            remise_devis=remise_devis,
            remise_fidelite=remise_fidelite,
            caution_montant=caution_montant,
            caution_payee=caution_payee,
            caution_deduite=caution_deduite,
            frais_mise_en_relation=frais_mer,
            commission_pct=commission_pct,
            commission_amount=commission_amount,
            net_prestataire=net_prestataire,
            total_paid=float(total_paid),
            reste_a_payer=float(reste_a_payer),
            acompte_montant=float(devis_deja_paye if not solde_valide else (getattr(res, "montant_verse", 0) or 0)),
            solde_montant=float(reste_a_payer),
            acompte_valide=acompte_valide,
            solde_valide=solde_valide,
            payment_method=pm_label,
            ref_transaction=tx_ref,
        )

    @classmethod
    def _draw_footer(cls, c: canvas.Canvas, W: float, data: InvoiceData, page_num: int, total_pages: int) -> None:
        BORDER_PRO = HexColor("#CBD5E1")
        NAVY_DEEP = HexColor("#0B1B34")
        MUTED_TEXT = HexColor("#64748B")
        y_footer = 14 * mm
        c.setStrokeColor(BORDER_PRO)
        c.setLineWidth(0.6)
        c.line(18 * mm, y_footer + 5 * mm, W - 18 * mm, y_footer + 5 * mm)

        c.setFillColor(NAVY_DEEP)
        c.setFont("Helvetica-Bold", 7.5)
        c.drawString(18 * mm, y_footer + 1 * mm, "BABIFIX SARL")
        c.setFont("Helvetica", 7)
        c.setFillColor(MUTED_TEXT)
        c.drawString(40 * mm, y_footer + 1 * mm, "RCCM : CI-ABJ-03-2026 · Abidjan, Cote d'Ivoire")
        c.drawRightString(W - 18 * mm, y_footer + 1 * mm, "contact@babifix.ci · www.babifix.ci")
        c.drawString(18 * mm, y_footer - 3.5 * mm, "Document genere automatiquement par le systeme securise BABIFIX · Valable sans signature manuscrite.")
        c.drawRightString(W - 18 * mm, y_footer - 3.5 * mm, f"Page {page_num} / {total_pages} · Facture #{data.invoice_number}")

    @classmethod
    def generate_pdf(cls, payment: Payment, *, is_client_view: bool = True) -> Optional[bytes]:
        """Genere le recu / facture PDF conforme Direction 3 Hybride."""
        data = cls.get_invoice_data(payment, is_client_view=is_client_view)
        if not data:
            return None

        try:
            buffer = io.BytesIO()
            c = canvas.Canvas(buffer, pagesize=A4)
            W, H = A4

            # Palette Direction 3 Hybride (zero cyan, zero degrade)
            NAVY_DEEP = HexColor("#0B1B34")
            GOLD_BRASS = HexColor("#B45309")
            EMERALD_PRO = HexColor("#0E3B2E")
            EMERALD_ACCENT = HexColor("#047857")
            TERRACOTTA = HexColor("#C2410C")
            SLATE_TEXT = HexColor("#1E293B")
            MUTED_TEXT = HexColor("#64748B")
            CARD_BG = HexColor("#F8FAFC")
            ROW_ALT_BG = HexColor("#F1F5F9")
            BORDER_PRO = HexColor("#CBD5E1")

            page1_rows = data.items[:9]
            overflow_rows = data.items[9:]
            total_pages = 2 if overflow_rows else 1

            # ── 1. EN-TETE INSTITUTIONNEL ───────────────────────────────
            header_h = 36 * mm
            c.setFillColor(NAVY_DEEP)
            c.rect(0, H - header_h, W, header_h, stroke=0, fill=1)

            # Liseré Or Laiton sobre
            c.setFillColor(GOLD_BRASS)
            c.rect(0, H - header_h - 1.2 * mm, W, 1.2 * mm, stroke=0, fill=1)

            text_x = 18 * mm
            logo_path = find_logo_path()
            if logo_path and os.path.exists(logo_path):
                try:
                    from reportlab.lib.utils import ImageReader
                    c.drawImage(
                        ImageReader(logo_path),
                        18 * mm,
                        H - header_h + 8 * mm,
                        width=18 * mm,
                        height=18 * mm,
                        mask="auto",
                        preserveAspectRatio=True,
                    )
                    text_x = 40 * mm
                except Exception:
                    text_x = 18 * mm

            c.setFillColorRGB(1, 1, 1)
            c.setFont("Helvetica-Bold", 20)
            c.drawString(text_x, H - 16 * mm, "BABIFIX")
            c.setFont("Helvetica", 8.5)
            c.setFillColor(HexColor("#CBD5E1"))
            c.drawString(text_x, H - 22 * mm, "Plateforme Officielle de Services a Domicile")
            c.drawString(text_x, H - 27 * mm, "Tiers de Confiance : Paiement Securise sous Sequestre")

            # Bloc Titre Facture & Reference (Or chaud lisible)
            c.setFillColor(HexColor("#FDE68A"))
            c.setFont("Helvetica-Bold", 12.5)
            doc_title = "RECU DE PAIEMENT" if not data.is_fully_paid else "FACTURE ACQUITTEE / RECU"
            c.drawRightString(W - 18 * mm, H - 15 * mm, doc_title)

            c.setFillColorRGB(1, 1, 1)
            c.setFont("Helvetica-Bold", 10)
            c.drawRightString(W - 18 * mm, H - 22 * mm, f"N° {data.invoice_number}")

            c.setFillColor(HexColor("#CBD5E1"))
            c.setFont("Helvetica", 8.5)
            c.drawRightString(W - 18 * mm, H - 28 * mm, f"Emis le {data.date_emission}")

            # ── 2. BANDEAU DE STATUT & REFERENCE ────────────────────────
            y_stat = H - header_h - 11 * mm
            badge_fill = EMERALD_PRO if data.is_fully_paid else TERRACOTTA
            badge_w = 56 * mm
            c.setFillColor(badge_fill)
            c.roundRect(18 * mm, y_stat - 1 * mm, badge_w, 7.5 * mm, 3.5 * mm, stroke=0, fill=1)
            c.setFillColorRGB(1, 1, 1)
            c.setFont("Helvetica-Bold", 8.2)
            c.drawCentredString(18 * mm + badge_w / 2.0, y_stat + 1.4 * mm, data.status_label)

            c.setFillColor(SLATE_TEXT)
            c.setFont("Helvetica-Bold", 8.8)
            c.drawString(78 * mm, y_stat + 1.4 * mm, "Fonds garantis par sequestre BABIFIX")
            c.setFont("Helvetica", 8)
            c.setFillColor(MUTED_TEXT)
            c.drawRightString(W - 18 * mm, y_stat + 1.4 * mm, f"Mission : {data.reservation_ref}")

            # ── 3. ENCARTS JUMEAUX : CLIENT ET PRESTATAIRE ──────────────
            y_boxes = y_stat - 36 * mm
            box_w = 83 * mm
            box_h = 32 * mm
            x_client = 18 * mm
            x_pro = W - 18 * mm - box_w

            for x_box, header_lbl, lines in (
                (
                    x_client,
                    "DONNEUR D'ORDRE (CLIENT)",
                    [
                        (data.client_name[:36], True, SLATE_TEXT),
                        (f"Tel : {data.client_tel or 'Non renseigne'}", False, MUTED_TEXT),
                        (f"Email : {(data.client_email or 'Non renseigne')[:34]}", False, MUTED_TEXT),
                        (f"Lieu : {data.client_commune[:34]}", False, MUTED_TEXT),
                    ],
                ),
                (
                    x_pro,
                    "PRESTATAIRE CERTIFIE (ARTISAN)",
                    [
                        (data.provider_name[:36], True, SLATE_TEXT),
                        (f"Metier : {data.provider_metier[:34]}", False, MUTED_TEXT),
                        (f"Tel : {data.provider_tel[:34]}", False, MUTED_TEXT),
                        (f"Matricule : {data.provider_matricule} · VERIFIE", True, EMERALD_ACCENT),
                    ],
                ),
            ):
                c.setFillColor(CARD_BG)
                c.setStrokeColor(BORDER_PRO)
                c.setLineWidth(0.8)
                c.roundRect(x_box, y_boxes, box_w, box_h, 3 * mm, stroke=1, fill=1)
                c.setFillColor(HexColor("#E2E8F0"))
                c.roundRect(x_box, y_boxes + box_h - 7 * mm, box_w, 7 * mm, 3 * mm, stroke=0, fill=1)
                c.rect(x_box, y_boxes + box_h - 7 * mm, box_w, 3 * mm, stroke=0, fill=1)
                c.setFillColor(NAVY_DEEP)
                c.setFont("Helvetica-Bold", 8.2)
                c.drawString(x_box + 3 * mm, y_boxes + box_h - 5 * mm, header_lbl)

                y_offsets = (12 * mm, 17 * mm, 22 * mm, 27 * mm)
                for (txt_val, is_bold, color_val), y_off in zip(lines, y_offsets):
                    c.setFillColor(color_val)
                    c.setFont("Helvetica-Bold" if is_bold else "Helvetica", 9.0 if y_off == 12 * mm else 7.8)
                    c.drawString(x_box + 3 * mm, y_boxes + box_h - y_off, txt_val)

            # ── 4. TABLEAU DES PRESTATIONS ──────────────────────────────
            y_table_header = y_boxes - 12 * mm
            table_w = W - 36 * mm
            c.setFillColor(NAVY_DEEP)
            c.rect(18 * mm, y_table_header, table_w, 7.5 * mm, stroke=0, fill=1)
            c.setFillColorRGB(1, 1, 1)
            c.setFont("Helvetica-Bold", 8)
            c.drawString(22 * mm, y_table_header + 2.5 * mm, "DESIGNATION DES TRAVAUX ET FOURNITURES")
            c.drawString(108 * mm, y_table_header + 2.5 * mm, "TYPE")
            c.drawString(130 * mm, y_table_header + 2.5 * mm, "QTE")
            c.drawRightString(159 * mm, y_table_header + 2.5 * mm, "P.U. (FCFA)")
            c.drawRightString(W - 22 * mm, y_table_header + 2.5 * mm, "TOTAL (FCFA)")

            y_row = y_table_header - 7.0 * mm
            row_h = 7.0 * mm
            for i, it in enumerate(page1_rows):
                if i % 2 == 1:
                    c.setFillColor(ROW_ALT_BG)
                    c.rect(18 * mm, y_row, table_w, row_h, stroke=0, fill=1)
                c.setStrokeColor(BORDER_PRO)
                c.setLineWidth(0.4)
                c.line(18 * mm, y_row, W - 18 * mm, y_row)
                c.setFillColor(SLATE_TEXT)
                c.setFont("Helvetica", 8)
                desc = str(it.get("description", "Prestation"))
                if len(desc) > 52:
                    desc = desc[:50] + ".."
                c.drawString(22 * mm, y_row + 2.2 * mm, desc)
                t_type = "Fourniture" if it.get("type") == "FOURNITURE" else "Main-d'oeuvre"
                c.setFont("Helvetica-Oblique", 7.5)
                c.setFillColor(MUTED_TEXT)
                c.drawString(108 * mm, y_row + 2.2 * mm, t_type)
                c.setFont("Helvetica", 8)
                c.setFillColor(SLATE_TEXT)
                c.drawString(130 * mm, y_row + 2.2 * mm, str(it.get("qty", 1)))
                c.drawRightString(159 * mm, y_row + 2.2 * mm, format_fcfa(it.get("unit_price", 0)))
                c.setFont("Helvetica-Bold", 8)
                c.drawRightString(W - 22 * mm, y_row + 2.2 * mm, format_fcfa(it.get("total", 0)))
                y_row -= row_h

            if overflow_rows:
                c.setFont("Helvetica-Oblique", 7.5)
                c.setFillColor(GOLD_BRASS)
                c.drawString(22 * mm, y_row + 2.0 * mm, f"... {len(overflow_rows)} ligne(s) supplementaire(s) en Page 2")
                y_row -= row_h

            c.setStrokeColor(BORDER_PRO)
            c.setLineWidth(0.8)
            c.line(18 * mm, y_row + 2 * mm, W - 18 * mm, y_row + 2 * mm)

            # ── 5. TOTAUX & ECHELONNEMENT DES REGLEMENTS ────────────────
            y_totals = y_row - 7 * mm
            pay_w = 88 * mm
            pay_h = 40 * mm
            c.setFillColor(CARD_BG)
            c.setStrokeColor(BORDER_PRO)
            c.setLineWidth(0.6)
            c.roundRect(18 * mm, y_totals - pay_h, pay_w, pay_h, 3 * mm, stroke=1, fill=1)

            c.setFillColor(NAVY_DEEP)
            c.setFont("Helvetica-Bold", 8.2)
            c.drawString(22 * mm, y_totals - 6 * mm, "SUIVI DES REGLEMENTS")

            c.setFont("Helvetica", 7.6)
            c.setFillColor(SLATE_TEXT)
            y_cursor = y_totals - 12 * mm
            if data.caution_payee:
                c.drawString(22 * mm, y_cursor, "Caution de visite :")
                c.setFillColor(EMERALD_ACCENT)
                c.setFont("Helvetica-Bold", 7.8)
                c.drawRightString(18 * mm + pay_w - 4 * mm, y_cursor, f"{format_fcfa(data.caution_montant)} FCFA · REGLEE")
                y_cursor -= 5.5 * mm

            c.setFont("Helvetica", 7.6)
            c.setFillColor(SLATE_TEXT)
            devis_paid_only = max(0.0, data.total_paid - (data.caution_montant if data.caution_payee else 0.0))
            c.drawString(22 * mm, y_cursor, "Versement prestation :")
            c.setFillColor(EMERALD_ACCENT if devis_paid_only > 0 else MUTED_TEXT)
            c.setFont("Helvetica-Bold", 7.8)
            c.drawRightString(
                18 * mm + pay_w - 4 * mm,
                y_cursor,
                f"{format_fcfa(devis_paid_only)} FCFA · {'REGLE' if devis_paid_only > 0 else 'EN ATTENTE'}",
            )
            y_cursor -= 5.5 * mm

            c.setFont("Helvetica", 7.6)
            c.setFillColor(SLATE_TEXT)
            c.drawString(22 * mm, y_cursor, "Reste a regler :")
            c.setFillColor(EMERALD_ACCENT if data.reste_a_payer <= 0 else TERRACOTTA)
            c.setFont("Helvetica-Bold", 7.8)
            c.drawRightString(
                18 * mm + pay_w - 4 * mm,
                y_cursor,
                "0 FCFA (SOLDE)" if data.reste_a_payer <= 0 else f"{format_fcfa(data.reste_a_payer)} FCFA",
            )

            c.setFont("Helvetica", 7.2)
            c.setFillColor(MUTED_TEXT)
            c.drawString(22 * mm, y_totals - 31 * mm, f"Mode : {data.payment_method[:32]}")
            c.drawString(22 * mm, y_totals - 36 * mm, f"Ref. transaction : {data.ref_transaction[:28]}")

            # Droite : Recapitulatif exact (jamais de commission exposee au client)
            tot_box_w = 78 * mm
            tot_box_x = W - 18 * mm - tot_box_w
            y_rt = y_totals - 5 * mm

            summary_lines = [
                ("Montant devis TTC :", f"{format_fcfa(data.sous_total_ttc)} FCFA", SLATE_TEXT),
            ]
            if data.remise_devis > 0:
                summary_lines.append(("Remise artisan :", f"- {format_fcfa(data.remise_devis)} FCFA", EMERALD_ACCENT))
            if data.caution_payee and data.caution_deduite:
                summary_lines.append(("Caution deja deduite :", f"- {format_fcfa(data.caution_montant)} FCFA", EMERALD_ACCENT))
            if data.remise_fidelite > 0:
                summary_lines.append(("Remise fidelite BABIFIX :", f"- {format_fcfa(data.remise_fidelite)} FCFA", EMERALD_ACCENT))
            if not data.is_client_view:
                summary_lines.append((f"Commission plateforme ({data.commission_pct:.0f} %) :", f"- {format_fcfa(data.commission_amount)} FCFA", MUTED_TEXT))
                summary_lines.append(("Net prestataire :", f"{format_fcfa(data.net_prestataire)} FCFA", EMERALD_PRO))

            for lbl_t, val_t, col_t in summary_lines[:5]:
                c.setFillColor(col_t)
                c.setFont("Helvetica", 7.8)
                c.drawString(tot_box_x, y_rt, lbl_t)
                c.setFont("Helvetica-Bold", 7.8)
                c.drawRightString(W - 18 * mm, y_rt, val_t)
                y_rt -= 5.2 * mm

            box_total_color = EMERALD_PRO if data.is_fully_paid else NAVY_DEEP
            c.setFillColor(box_total_color)
            c.roundRect(tot_box_x - 2 * mm, y_totals - 40 * mm, tot_box_w + 2 * mm, 12 * mm, 2.5 * mm, stroke=0, fill=1)
            c.setFillColorRGB(1, 1, 1)
            c.setFont("Helvetica-Bold", 8.5)
            c.drawString(tot_box_x + 2 * mm, y_totals - 35.5 * mm, "TOTAL PAYE :")
            c.setFillColor(HexColor("#FDE68A"))
            c.setFont("Helvetica-Bold", 12)
            c.drawRightString(W - 20 * mm, y_totals - 36 * mm, f"{format_fcfa(data.total_paid)} FCFA")

            # ── 6. TAMPON OFFICIEL DE CERTIFICATION & QR CODE ─────────────
            y_stamp = y_totals - 47 * mm
            verify_url = f"https://babifix.ci/verify/invoice/{data.invoice_number}?ref={data.reservation_ref}"
            qr = QrCodeWidget(verify_url)
            qr.barWidth = 22 * mm
            qr.barHeight = 22 * mm
            qr.qrVersion = 2
            d = Drawing(22 * mm, 22 * mm)
            d.add(qr)
            from reportlab.graphics import renderPDF
            renderPDF.draw(d, c, 18 * mm, y_stamp - 24 * mm)

            c.setFillColor(NAVY_DEEP)
            c.setFont("Helvetica-Bold", 8)
            c.drawString(44 * mm, y_stamp - 7 * mm, "DOCUMENT NUMERIQUE OFFICIEL CERTIFIE")
            c.setFont("Helvetica", 7.3)
            c.setFillColor(MUTED_TEXT)
            c.drawString(44 * mm, y_stamp - 12 * mm, "Scannez le QR Code pour verifier l'authenticite en direct.")
            sha_hash = hashlib.sha256(
                f"{data.invoice_number}:{data.reservation_ref}:{data.total_paid}".encode()
            ).hexdigest()[:16].upper()
            c.drawString(44 * mm, y_stamp - 17 * mm, f"Empreinte d'integrite : {sha_hash}")
            c.drawString(44 * mm, y_stamp - 22 * mm, "Conservez ce document comme justificatif comptable.")

            c.setStrokeColor(EMERALD_ACCENT if data.is_fully_paid else GOLD_BRASS)
            c.setFillColor(EMERALD_PRO if data.is_fully_paid else GOLD_BRASS)
            c.roundRect(W - 68 * mm, y_stamp - 21 * mm, 50 * mm, 17 * mm, 3 * mm, stroke=1, fill=0)
            c.setFont("Helvetica-Bold", 7.5)
            c.drawCentredString(W - 43 * mm, y_stamp - 9 * mm, "BABIFIX COTE D'IVOIRE")
            c.drawCentredString(W - 43 * mm, y_stamp - 14 * mm, data.status_label[:24])
            c.setFont("Helvetica", 6.5)
            c.drawCentredString(W - 43 * mm, y_stamp - 18.5 * mm, "ATTESTATION ELECTRONIQUE")

            cls._draw_footer(c, W, data, 1, total_pages)

            # Page 2 si plus de 9 lignes dans le devis
            if overflow_rows:
                c.showPage()
                c.setFillColor(NAVY_DEEP)
                c.rect(0, H - 22 * mm, W, 22 * mm, stroke=0, fill=1)
                c.setFillColor(GOLD_BRASS)
                c.rect(0, H - 23 * mm, W, 1 * mm, stroke=0, fill=1)
                c.setFillColorRGB(1, 1, 1)
                c.setFont("Helvetica-Bold", 12)
                c.drawString(18 * mm, H - 14 * mm, f"ANNEXE DETAIL DES PRESTATIONS · {data.invoice_number}")
                y_ov = H - 36 * mm
                for idx, it in enumerate(overflow_rows[:30]):
                    if idx % 2 == 1:
                        c.setFillColor(ROW_ALT_BG)
                        c.rect(18 * mm, y_ov, table_w, row_h, stroke=0, fill=1)
                    c.setFillColor(SLATE_TEXT)
                    c.setFont("Helvetica", 8)
                    c.drawString(22 * mm, y_ov + 2.2 * mm, str(it.get("description", ""))[:58])
                    c.drawString(130 * mm, y_ov + 2.2 * mm, str(it.get("qty", 1)))
                    c.drawRightString(159 * mm, y_ov + 2.2 * mm, format_fcfa(it.get("unit_price", 0)))
                    c.setFont("Helvetica-Bold", 8)
                    c.drawRightString(W - 22 * mm, y_ov + 2.2 * mm, format_fcfa(it.get("total", 0)))
                    y_ov -= row_h
                cls._draw_footer(c, W, data, 2, total_pages)

            c.showPage()
            c.save()
            buffer.seek(0)
            return buffer.getvalue()

        except Exception as exc:
            logger.exception("Erreur lors de la generation du recu PDF BABIFIX: %s", exc)
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
                "date": format_french_date(
                    p.reservation.prestation_terminee_at or p.created_at,
                    with_time=False,
                ) if p.reservation_id else "",
                "reservation": p.reservation.reference if p.reservation_id else "",
                "amount": float(p.montant or 0),
                "total": float(p.montant or 0),
            }
            for p in payments
        ]

    @classmethod
    def get_provider_invoices(cls, provider: Provider) -> list:
        """Lister les factures d'un prestataire avec net reel."""
        payments = Payment.objects.filter(
            reservation__assigned_provider=provider,
            etat=Payment.State.COMPLETE,
        ).select_related("reservation").order_by("-id")

        out = []
        for p in payments:
            gross = float(p.montant or 0)
            comm = float(p.commission or 0)
            out.append({
                "invoice_number": cls.generate_invoice_number(p),
                "date": format_french_date(
                    p.reservation.prestation_terminee_at or p.created_at,
                    with_time=False,
                ) if p.reservation_id else "",
                "reservation": p.reservation.reference if p.reservation_id else "",
                "client": (p.reservation.client if p.reservation_id else "") or "",
                "amount": gross,
                "commission": comm,
                "net": max(0.0, gross - comm),
            })
        return out
