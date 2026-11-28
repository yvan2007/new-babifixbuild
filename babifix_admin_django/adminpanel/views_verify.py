"""Verification publique cryptographique des cartes Wallet (Prestataire, Client, Vitrine)."""

from __future__ import annotations

import hashlib
import hmac

from django.conf import settings
from django.http import JsonResponse
from django.shortcuts import render
from django.views.decorators.http import require_GET

from .models import Provider, Reservation, User, UserProfile


def _qr_signing_key() -> bytes:
    raw = (getattr(settings, "SECRET_KEY", "") or "babifix-qr-key").strip()
    return f"babifix-wallet-qr:{raw}".encode("utf-8")


def sign_wallet_qr_code(kind: str, object_id: int | str) -> str:
    """Genere un identifiant public signe non devinable (ex: '12-a1b2c3d4e5')."""
    msg = f"{kind}:{object_id}".encode("utf-8")
    sig = hmac.new(_qr_signing_key(), msg, hashlib.sha256).hexdigest()[:10]
    return f"{object_id}-{sig}"


def build_wallet_qr_url(kind: str, object_id: int | str, request=None) -> str:
    """Construit l'URL officielle scannable pour une carte Wallet ou Bouclier."""
    code = sign_wallet_qr_code(kind, object_id)
    path = f"/verify/{kind}/{code}/"
    if request is not None:
        try:
            return request.build_absolute_uri(path)
        except Exception:
            pass
    base = "https://new-babifixbuild.onrender.com"
    return f"{base}{path}"


def _verify_wallet_qr_code(kind: str, code: str) -> str | None:
    """Valide le HMAC du QR code sans exposer ni accepter un ID arbitraire forge."""
    parts = (code or "").strip().split("-", 1)
    if len(parts) != 2:
        return None
    obj_id, sig = parts[0].strip(), parts[1].strip().lower()
    if not obj_id or not sig:
        return None
    expected = sign_wallet_qr_code(kind, obj_id).split("-", 1)[1]
    if hmac.compare_digest(expected, sig):
        return obj_id
    return None


@require_GET
def public_verify_qr_card(request, kind: str, code: str):
    """Page et API publique de verification de carte Wallet/Bouclier au scan QR.

    Strictement conforme Loi ivoirienne n° 2013-450 : aucune donnee personnelle
    sensible (telephone, CNI, email, adresse exacte) n'est jamais exposee.
    """
    clean_kind = (kind or "").strip().lower()
    wants_json = (
        request.GET.get("format") == "json"
        or "application/json" in (request.headers.get("Accept") or "").lower()
    )

    data = {
        "valid": False,
        "kind": clean_kind,
        "badge": "Code invalide",
        "title": "Verification impossible",
        "subtitle": "Ce code QR ne correspond pas a une carte officielle BABIFIX active.",
        "kyc_verified": False,
        "details": [],
        "code_public": code[:40],
    }

    if clean_kind == "demo":
        tier = (code or "gold").strip().lower()
        tier_label = "Pro Gold (8 %)" if "gold" in tier else ("Pro Silver (13 %)" if "silver" in tier else "Standard (18 %)")
        data = {
            "valid": True,
            "kind": "demo",
            "badge": "CARTE OFFICIELLE BABIFIX (DEMO VITRINE)",
            "title": "Certification Wallet & Sequestre BABIFIX",
            "subtitle": f"Exemple de carte verifiee - Palier {tier_label}",
            "kyc_verified": True,
            "details": [
                ("Identite & KYC", "CNI et selfie controles avant visibilite client"),
                ("Protection Sequestre", "Fonds cantonnes jusqu'a validation OTP des travaux"),
                ("Canaux de paiement", "Wave, Orange Money, MTN MoMo, Moov Money & Especes"),
                ("Conformite", "Loi ivoirienne n° 2013-450 · Abidjan, Cote d'Ivoire"),
            ],
            "code_public": f"BFX-DEMO-{tier[:12].upper()}",
        }
    elif clean_kind in ("pro", "provider", "prestataire"):
        obj_id = _verify_wallet_qr_code("pro", code)
        prov = Provider.objects.select_related("category").filter(pk=int(obj_id), is_deleted=False).first() if (obj_id and obj_id.isdigit()) else None
        if prov:
            kyc_ok = (prov.kyc_status == "approved") or bool(
                prov.statut == Provider.Status.VALID and (prov.cni_recto_url or prov.cni_url or prov.kyc_cni_recto_url)
            )
            is_valid_prov = prov.statut == Provider.Status.VALID
            tier = (prov.premium_tier or "standard").upper() if prov.is_premium else "STANDARD"
            rating_txt = f"{float(prov.average_rating or 0):.1f}/5 ({int(prov.rating_count or 0)} avis)" if prov.rating_count else "Nouveau prestataire"
            name_parts = (prov.nom or "Artisan").strip().split()
            public_name = name_parts[0] + (f" {name_parts[1][:1]}." if len(name_parts) > 1 else "")
            data = {
                "valid": is_valid_prov,
                "kind": "pro",
                "badge": "PRESTATAIRE VERIFIE BABIFIX" if (is_valid_prov and kyc_ok) else ("COMPTE ACTIF · KYC EN COURS" if is_valid_prov else "DOSSIER EN VERIFICATION"),
                "title": public_name,
                "subtitle": f"{(prov.category.nom if prov.category_id else prov.specialite) or 'Artisan multi-services'} · {prov.ville or 'Cote d Ivoire'}",
                "kyc_verified": kyc_ok,
                "details": [
                    ("Statut compte", prov.statut),
                    ("Dossier CNI / KYC", "Verifie et conforme" if kyc_ok else "En attente de pieces/validation"),
                    ("Palier Wallet", tier),
                    ("Note moyenne", rating_txt),
                    ("Fiabilite plateforme", f"{int(getattr(prov, 'fiabilite_score', 100) or 100)} / 100"),
                ],
                "code_public": f"BFX-PRO-{prov.pk:05d}",
            }
    elif clean_kind == "client":
        obj_id = _verify_wallet_qr_code("client", code)
        u = User.objects.filter(pk=int(obj_id), is_active=True).first() if (obj_id and obj_id.isdigit()) else None
        prof = UserProfile.objects.filter(user=u, role=UserProfile.Role.CLIENT).first() if u else None
        if u and prof:
            missions_cnt = Reservation.objects.filter(client_user=u, statut="Terminee").count()
            pts = int(getattr(prof, "points_fidelite", 0) or 0)
            tier = "Bouclier Or" if (pts >= 500 or missions_cnt >= 10) else ("Bouclier Argent" if (pts >= 150 or missions_cnt >= 3) else "Bouclier Actif")
            raw_name = (u.get_full_name() or u.username or "Client").strip().split()
            public_name = raw_name[0] + (f" {raw_name[1][:1]}." if len(raw_name) > 1 else "")
            data = {
                "valid": bool(prof.active),
                "kind": "client",
                "badge": "MEMBRE BOUCLIER BABIFIX ACTIF",
                "title": public_name,
                "subtitle": f"Niveau {tier} · Protection Sequestre active",
                "kyc_verified": True,
                "details": [
                    ("Protection", "Paiement securise sous sequestre et arbitrage < 24 h"),
                    ("Statut Bouclier", tier),
                    ("Missions terminees", str(missions_cnt)),
                    ("Points fidelite", f"{pts} pts"),
                ],
                "code_public": f"BFX-CLI-{u.pk:05d}",
            }

    if wants_json:
        return JsonResponse(data, status=200 if data["valid"] else 404)
    return render(
        request,
        "adminpanel/verify_wallet_qr.html",
        {"qr": data},
        status=200 if data["valid"] else 404,
    )
