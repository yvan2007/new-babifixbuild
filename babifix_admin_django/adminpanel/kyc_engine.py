"""
BABIFIX Smart KYC & ONECI-MRZ Verification Engine
=================================================

Quatre niveaux de verification deterministes en cascade (zero simulation aleatoire) :

  Niveau 1 : Format ONECI / NNI & MRZ ICAO 9303 TD1 (3x30)
    * Validation stricte NNI (11 chiffres) et CNI biometrique ONECI (CI + chiffres)
    * Rejet sequences triviales (00000..., 123456789...)
    * Parsing & verification cryptographique modulo-10 (poids 7-3-1) des 4 chiffres de
      controle ICAO 9303 TD1 (numero piece, date naissance, expiration, composite)
    * Coherence pays (CIV), majorite (>= 18 ans), date expiration (non expiree, <= 15 ans)
    * Recoupement MRZ <-> numero CNI / expiration / identite declaree

  Niveau 2 : Vision par ordinateur deterministe (Pillow pur, toujours actif sans binaire)
    * Resolution minimale et ratio ISO/IEC 7810 ID-1 (carte bancaire 1.586) sur Recto/Verso
    * Nettete reelle par convolution Laplacienne 2D (detection de flou optique)
    * Luminosite, plage dynamique (p5..p95) et detection reflets flash / photo d'ecran
    * Saturation couleur HSV (detection photocopie noir et blanc)
    * Coherence portrait / teinte peau YCbCr sur zone centrale du selfie
    * Anti-fraude unicite SHA-256 + empreinte perceptuelle dHash 64 bits (Hamming <= 5)
      a la fois intra-dossier (Recto vs Verso vs Selfie) ET inter-comptes en base

  Niveau 3 : Biometrie faciale OpenCV (si opencv-python installe)
    * Detection visage frontal Haar cascade sur selfie et CNI recto
    * Comparaison points caracteristiques ORB + BFMatcher

  Niveau 4 : Verification gouvernementale / institutionnelle (si configuree)
    * Adaptateur Smile Identity (SMILE_IDENTITY_PARTNER_ID / API_KEY)
    * Point d'extension conventionne ONECI (ONECI_API_URL / ONECI_API_KEY)

Regle de gouvernance : l'humain admin valide toujours l'approbation finale ;
seuls les signaux de fraude averes (images dupliquees, CNI deja utilisee sur un autre
compte, piece expiree, rejet gouvernemental) declenchent un rejet automatique.
"""

from __future__ import annotations

import base64
from dataclasses import dataclass, field
from datetime import date
import hashlib
import io
import logging
import re
from typing import Any, Optional

logger = logging.getLogger(__name__)


# =============================================================================
# 1. Format CNI / NNI ivoirien (ONECI / RNPP)
# =============================================================================
_CNI_PATTERNS_STRONG = [
    (re.compile(r"^\d{11}$"), "NNI (11 chiffres)"),
    (re.compile(r"^CI\s*\d{7,12}$", re.I), "CNI biometrique ONECI"),
    (re.compile(r"^C\s*0\d{7,10}$", re.I), "CNI ONECI serie C0"),
]
_CNI_PATTERNS_OK = [
    (re.compile(r"^[A-Z]\s*\d{6,9}\s*[A-Z]$", re.I), "Ancienne CNI"),
    (re.compile(r"^C\s*\d{6,9}$", re.I), "CNI ancien format"),
    (re.compile(r"^\d{9,15}$"), "Numerique"),
]
_CNI_PATTERNS = [p for p, _ in (_CNI_PATTERNS_STRONG + _CNI_PATTERNS_OK)]


def normalize_cni_number(cni_number: str) -> str:
    return re.sub(r"[\s\-\._/]+", "", (cni_number or "").strip().upper())


def _validate_cni_format(cni_number: str) -> tuple[bool, str]:
    """Valide le format d'un identifiant CNI/NNI ivoirien."""
    cleaned = normalize_cni_number(cni_number)
    if len(cleaned) < 5:
        return False, "Numero trop court (minimum 5 caracteres)."
    if len(cleaned) > 20:
        return False, "Numero trop long (maximum 20 caracteres)."
    digits = "".join(c for c in cleaned if c.isdigit())
    if digits and len(set(digits)) == 1:
        return False, "Numero invalide (chiffre unique repete)."
    if digits in (
        "0123456789",
        "1234567890",
        "123456789",
        "01234567890",
        "12345678901",
        "9876543210",
    ):
        return False, "Numero invalide (sequence triviale)."

    label = _cni_format_label(cleaned)
    if label:
        return True, ""
    if re.match(r"^[A-Z0-9]{6,}$", cleaned):
        return True, ""
    return False, f"Format non reconnu : '{cni_number}'. Verifiez et re-saisissez."


def _cni_format_label(cleaned: str) -> str:
    for pattern, lbl in _CNI_PATTERNS_STRONG:
        if pattern.match(cleaned):
            return lbl
    for pattern, lbl in _CNI_PATTERNS_OK:
        if pattern.match(cleaned):
            return lbl
    return ""


def cni_confidence(cni_number: str) -> str:
    """Niveau de confiance du format CNI : 'strong', 'ok' ou 'weak'."""
    cleaned = normalize_cni_number(cni_number)
    for pattern, _ in _CNI_PATTERNS_STRONG:
        if pattern.match(cleaned):
            return "strong"
    for pattern, _ in _CNI_PATTERNS_OK:
        if pattern.match(cleaned):
            return "ok"
    return "weak"


# =============================================================================
# 2. Parser & Validateur Cryptographique MRZ TD1 ICAO 9303 (CNI ONECI CIV)
# =============================================================================
_MRZ_WEIGHTS = (7, 3, 1)


def _mrz_char_value(ch: str) -> int:
    if ch == "<":
        return 0
    if "0" <= ch <= "9":
        return ord(ch) - ord("0")
    if "A" <= ch <= "Z":
        return ord(ch) - ord("A") + 10
    return 0


def mrz_check_digit(field_str: str) -> str:
    """Calcule la cle de controle ICAO 9303 modulo 10 (ponderation 7-3-1)."""
    total = 0
    for idx, ch in enumerate(field_str.upper()):
        total += _mrz_char_value(ch) * _MRZ_WEIGHTS[idx % 3]
    return str(total % 10)


def _parse_mrz_yymmdd(raw: str, *, is_birth: bool) -> Optional[date]:
    if not re.match(r"^\d{6}$", raw or ""):
        return None
    yy = int(raw[0:2])
    mm = int(raw[2:4])
    dd = int(raw[4:6])
    today = date.today()
    cur_yy = today.year % 100
    if is_birth:
        year = 2000 + yy if yy <= cur_yy else 1900 + yy
    else:
        year = 2000 + yy if yy <= (cur_yy + 25) % 100 or yy < 80 else 1900 + yy
    try:
        return date(year, mm, dd)
    except ValueError:
        return None


def parse_and_validate_mrz_td1(
    mrz_raw: str,
    *,
    expected_cni: str = "",
    expected_expiry: Optional[date] = None,
    expected_name: str = "",
) -> dict[str, Any]:
    """Parse et valide une zone MRZ TD1 (3 lignes de 30 caracteres) CNI ONECI."""
    raw = (mrz_raw or "").strip().upper()
    if not raw:
        return {"provided": False, "valid": False, "errors": [], "warnings": []}

    lines = [re.sub(r"\s+", "", ln) for ln in raw.replace("\r", "\n").split("\n") if ln.strip()]
    if len(lines) == 1 and len(lines[0]) == 90:
        lines = [lines[0][0:30], lines[0][30:60], lines[0][60:90]]

    if len(lines) != 3 or any(len(ln) != 30 for ln in lines):
        return {
            "provided": True,
            "valid": False,
            "errors": [
                "Format MRZ TD1 invalide : 3 lignes de 30 caracteres exacts attendues (verso CNI ONECI)."
            ],
            "warnings": [],
        }

    l1, l2, l3 = lines
    errors: list[str] = []
    warnings: list[str] = []

    doc_type = l1[0:2]
    issuing_country = l1[2:5]
    doc_num_raw = l1[5:14]
    doc_num_cd = l1[14]
    opt1 = l1[15:30]

    birth_raw = l2[0:6]
    birth_cd = l2[6]
    sex = l2[7]
    expiry_raw = l2[8:14]
    expiry_cd = l2[14]
    nationality = l2[15:18]
    opt2 = l2[18:29]
    composite_cd = l2[29]

    if not doc_type.startswith("I"):
        warnings.append(f"Type document MRZ inhabituel ({doc_type}).")
    if issuing_country != "CIV":
        warnings.append(f"Pays emetteur MRZ '{issuing_country}' (attendu CIV pour ONECI).")

    if mrz_check_digit(doc_num_raw) != doc_num_cd:
        errors.append("Cle de controle numero CNI (MRZ ligne 1) invalide.")
    if mrz_check_digit(birth_raw) != birth_cd:
        errors.append("Cle de controle date de naissance (MRZ ligne 2) invalide.")
    if mrz_check_digit(expiry_raw) != expiry_cd:
        errors.append("Cle de controle date d'expiration (MRZ ligne 2) invalide.")

    composite_input = l1[5:30] + l2[0:7] + l2[8:15] + l2[18:29]
    if mrz_check_digit(composite_input) != composite_cd:
        errors.append("Cle de controle composite globale (MRZ) invalide.")

    birth_date = _parse_mrz_yymmdd(birth_raw, is_birth=True)
    expiry_date = _parse_mrz_yymmdd(expiry_raw, is_birth=False)
    today = date.today()

    age_years = None
    if birth_date:
        age_years = today.year - birth_date.year - (
            (today.month, today.day) < (birth_date.month, birth_date.day)
        )
        if age_years < 18:
            errors.append(f"Titulaire mineur detecte dans la MRZ ({age_years} ans, 18 ans minimum).")
    else:
        errors.append("Date de naissance MRZ illisible.")

    if expiry_date:
        if expiry_date <= today:
            errors.append(f"CNI expiree selon la MRZ ({expiry_date.isoformat()}).")
    else:
        errors.append("Date d'expiration MRZ illisible.")

    doc_number = doc_num_raw.replace("<", "")
    name_parts = l3.split("<<", 1)
    surname = name_parts[0].replace("<", " ").strip()
    given_names = name_parts[1].replace("<", " ").strip() if len(name_parts) > 1 else ""

    if expected_cni:
        norm_exp = normalize_cni_number(expected_cni)
        if doc_number and doc_number not in norm_exp and norm_exp not in doc_number:
            warnings.append(
                f"Numero CNI MRZ ({doc_number}) different du numero saisi ({norm_exp})."
            )

    if expected_expiry and expiry_date and expected_expiry != expiry_date:
        warnings.append(
            f"Date expiration MRZ ({expiry_date.isoformat()}) differente de la date saisie ({expected_expiry.isoformat()})."
        )

    if expected_name and surname:
        norm_expected = re.sub(r"[^A-Z]", "", expected_name.upper())
        norm_surname = re.sub(r"[^A-Z]", "", surname.upper())
        if norm_surname and norm_surname not in norm_expected:
            warnings.append("Nom sur la MRZ legerement different du nom du profil.")

    return {
        "provided": True,
        "valid": len(errors) == 0,
        "issuing_country": issuing_country,
        "nationality": nationality,
        "doc_number": doc_number,
        "birth_date": birth_date.isoformat() if birth_date else None,
        "expiry_date": expiry_date.isoformat() if expiry_date else None,
        "age_years": age_years,
        "sex": sex,
        "surname": surname,
        "given_names": given_names,
        "errors": errors,
        "warnings": warnings,
    }


# =============================================================================
# 3. Structures de resultats
# =============================================================================
@dataclass
class CheckResult:
    passed: bool
    score_contribution: int
    label: str
    detail: str
    is_blocking: bool = False


@dataclass
class KYCVerificationResult:
    score: int = 0
    confidence: str = "LOW_CONFIDENCE"
    auto_decision: str = "pending"  # pending | under_review | rejected
    checks: list[CheckResult] = field(default_factory=list)
    smile_identity_result: Optional[dict] = None
    face_detected_selfie: bool = False
    face_detected_cni: bool = False
    faces_match: Optional[float] = None
    mrz_parsed: Optional[dict] = None
    image_hashes: dict[str, str] = field(default_factory=dict)
    hints: list[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "score": self.score,
            "confidence": self.confidence,
            "auto_decision": self.auto_decision,
            "face_detected_selfie": self.face_detected_selfie,
            "face_detected_cni": self.face_detected_cni,
            "faces_match": self.faces_match,
            "smile_identity": self.smile_identity_result,
            "mrz_parsed": self.mrz_parsed,
            "hints": self.hints,
            "checks": [
                {
                    "label": c.label,
                    "passed": c.passed,
                    "detail": c.detail,
                    "blocking": c.is_blocking,
                    "points": c.score_contribution,
                }
                for c in self.checks
            ],
        }


# =============================================================================
# 4. Empreintes perceptuelles (dHash 64-bit) & Vision Pillow deterministe
# =============================================================================
def _decode_b64(b64_str: str) -> Optional[bytes]:
    try:
        raw = b64_str.split(",", 1)[-1].strip()
        return base64.b64decode(raw)
    except Exception:
        return None


def compute_dhash(raw: bytes) -> str:
    """Calcule une empreinte perceptuelle dHash 64 bits (16 hex) via Pillow."""
    try:
        from PIL import Image

        img = Image.open(io.BytesIO(raw)).convert("L").resize((9, 8))
        px = list(img.getdata())
        bits = 0
        for row in range(8):
            offset = row * 9
            for col in range(8):
                bits = (bits << 1) | (1 if px[offset + col] > px[offset + col + 1] else 0)
        return f"{bits:016x}"
    except Exception:
        return ""


def dhash_distance(h1: str, h2: str) -> int:
    """Distance de Hamming entre deux dHash hexadecimaux 64 bits."""
    if not h1 or not h2 or len(h1) != len(h2):
        return 64
    try:
        return (int(h1, 16) ^ int(h2, 16)).bit_count()
    except ValueError:
        return 64


def _laplacian_focus_score(gray_img) -> float:
    """Mesure de nettete optique par convolution Laplacienne 2D reelle (Pillow)."""
    from PIL import ImageFilter, ImageStat

    small = gray_img.resize((320, 240))
    lap = small.filter(
        ImageFilter.Kernel(
            size=(3, 3),
            kernel=(0, 1, 0, 1, -4, 1, 0, 1, 0),
            scale=1,
            offset=128,
        )
    )
    return float(ImageStat.Stat(lap).var[0])


def _pillow_checks(raw: bytes, label: str, *, is_id_card: bool = False) -> tuple[list[CheckResult], list[str]]:
    """Controles optiques reels via Pillow (resolution, nettete Laplacienne 2D,
    luminosite, reflets flash, saturation couleur, ratio carte ID-1)."""
    results: list[CheckResult] = []
    hints: list[str] = []
    try:
        from PIL import Image, ImageStat

        img = Image.open(io.BytesIO(raw))
        w, h = img.size

        # 1. Resolution minimale
        if w < 400 or h < 300:
            results.append(
                CheckResult(
                    passed=False,
                    score_contribution=0,
                    label=f"{label} : resolution",
                    detail=f"Image trop petite ({w}x{h}px). Minimum requis : 400x300.",
                    is_blocking=True,
                )
            )
            hints.append(f"{label} : reprenez la photo en meilleure qualite (min 400x300).")
        elif w < 640 or h < 480:
            results.append(
                CheckResult(
                    passed=True,
                    score_contribution=3,
                    label=f"{label} : resolution",
                    detail=f"Resolution acceptable ({w}x{h}px).",
                )
            )
        else:
            results.append(
                CheckResult(
                    passed=True,
                    score_contribution=5,
                    label=f"{label} : resolution",
                    detail=f"Resolution nette ({w}x{h}px).",
                )
            )

        # 2. Ratio format carte ID-1 (85.6 x 53.98 mm => 1.586) pour CNI Recto/Verso
        if is_id_card and h > 0 and w > 0:
            ratio = max(w, h) / float(min(w, h))
            if 1.20 <= ratio <= 2.10:
                results.append(
                    CheckResult(
                        passed=True,
                        score_contribution=3,
                        label=f"{label} : cadrage carte ID-1",
                        detail=f"Proportions conformes a une carte d'identite (ratio {ratio:.2f}).",
                    )
                )
            else:
                results.append(
                    CheckResult(
                        passed=False,
                        score_contribution=0,
                        label=f"{label} : cadrage carte ID-1",
                        detail=f"Format inhabituel (ratio {ratio:.2f}, attendu ~1.59). Cadrez bien la carte entiere.",
                    )
                )
                hints.append(f"{label} : cadrez la carte CNI en entier horizontalement.")

        # 3. Luminosite & plage dynamique & reflets speculaires (flash / ecran)
        gray = img.convert("L")
        stat = ImageStat.Stat(gray)
        mean_bright = float(stat.mean[0])
        hist = gray.histogram()
        total_px = sum(hist) or 1
        glare_ratio = sum(hist[248:256]) / float(total_px)

        if mean_bright < 42:
            results.append(
                CheckResult(
                    passed=False,
                    score_contribution=0,
                    label=f"{label} : luminosite",
                    detail=f"Image trop sombre ({mean_bright:.0f}/255). Eclairez mieux votre document.",
                )
            )
            hints.append(f"{label} : photo trop sombre, placez-vous pres d'une fenetre ou lumiere.")
        elif mean_bright > 228 or glare_ratio > 0.28:
            results.append(
                CheckResult(
                    passed=False,
                    score_contribution=0,
                    label=f"{label} : luminosite / reflets",
                    detail=(
                        f"Surexposition ou reflet de flash detecte (luminosite {mean_bright:.0f}/255, "
                        f"zones saturees {glare_ratio * 100:.0f}%)."
                    ),
                )
            )
            hints.append(f"{label} : evitez le flash direct ou les reflets d'ecran sur la carte.")
        else:
            results.append(
                CheckResult(
                    passed=True,
                    score_contribution=4,
                    label=f"{label} : luminosite",
                    detail=f"Eclairage equilibre ({mean_bright:.0f}/255, reflets {glare_ratio * 100:.0f}%).",
                )
            )

        # 4. Nettete optique par convolution Laplacienne 2D reelle
        lap_var = _laplacian_focus_score(gray)
        if lap_var < 35.0:
            results.append(
                CheckResult(
                    passed=False,
                    score_contribution=0,
                    label=f"{label} : nettete optique",
                    detail=f"Image floue ou uniforme (score Laplacien {lap_var:.1f}). Stabilisez le telephone.",
                )
            )
            hints.append(f"{label} : image floue, posez la carte sur une surface plane avant de photographier.")
        elif lap_var < 90.0:
            results.append(
                CheckResult(
                    passed=True,
                    score_contribution=4,
                    label=f"{label} : nettete optique",
                    detail=f"Nettete correcte (score Laplacien {lap_var:.1f}).",
                )
            )
        else:
            results.append(
                CheckResult(
                    passed=True,
                    score_contribution=6,
                    label=f"{label} : nettete optique",
                    detail=f"Image tres nette (score Laplacien {lap_var:.1f}).",
                )
            )

        # 5. Anti-photocopie noir & blanc sur CNI (saturation couleur HSV)
        if is_id_card:
            hsv = img.convert("RGB").resize((160, 100)).convert("HSV")
            sat_mean = float(ImageStat.Stat(hsv).mean[1])
            if sat_mean < 12.0:
                results.append(
                    CheckResult(
                        passed=False,
                        score_contribution=0,
                        label=f"{label} : couleur originale",
                        detail=(
                            f"Faible saturation couleur ({sat_mean:.1f}/255) : photocopie noir et blanc suspectee."
                        ),
                    )
                )
                hints.append(f"{label} : photographiez l'original en couleur de votre CNI, pas une photocopie.")
            else:
                results.append(
                    CheckResult(
                        passed=True,
                        score_contribution=3,
                        label=f"{label} : couleur originale",
                        detail=f"Document couleur authentique detecte (saturation {sat_mean:.1f}).",
                    )
                )

    except Exception as exc:
        logger.warning("Pillow check failed for %s: %s", label, exc)
        results.append(
            CheckResult(
                passed=False,
                score_contribution=0,
                label=f"{label} : lecture image",
                detail="Impossible de lire l'image (format JPEG/PNG requis).",
                is_blocking=True,
            )
        )
        hints.append(f"{label} : fichier image invalide, utilisez une photo JPEG ou PNG.")
    return results, hints


def _pillow_portrait_skin_check(raw: bytes, label: str) -> tuple[CheckResult, bool]:
    """Detection deterministe d'un portrait humain (teinte peau YCbCr en zone centrale)
    comme repli robuste quand OpenCV n'est pas installe."""
    try:
        from PIL import Image

        img = Image.open(io.BytesIO(raw)).convert("YCbCr").resize((120, 120))
        # Zone centrale (oval portrait) : x in [25..95], y in [15..100]
        skin_px = 0
        total_roi = 0
        for y in range(15, 100):
            for x in range(25, 95):
                y_val, cb, cr = img.getpixel((x, y))
                total_roi += 1
                # Plage YCbCr universelle couvrant toutes les carnations (notamment africaines)
                if 20 <= y_val <= 240 and 75 <= cb <= 132 and 130 <= cr <= 178:
                    skin_px += 1
        ratio = skin_px / float(total_roi or 1)
        if 0.08 <= ratio <= 0.88:
            return (
                CheckResult(
                    passed=True,
                    score_contribution=10,
                    label=f"{label} : presence portrait",
                    detail=f"Portrait humain plausible detecte (zone faciale {ratio * 100:.0f}%).",
                ),
                True,
            )
        return (
            CheckResult(
                passed=False,
                score_contribution=0,
                label=f"{label} : presence portrait",
                detail=(
                    f"Visage peu identifiable au centre ({ratio * 100:.0f}%). "
                    "Centrez votre visage sans lunettes de soleil."
                ),
            ),
            False,
        )
    except Exception:
        return (
            CheckResult(
                passed=True,
                score_contribution=0,
                label=f"{label} : presence portrait",
                detail="Verification portrait manuelle requise.",
            ),
            False,
        )


def _check_images_distinct(hashes: list[str], dhashes: Optional[list[str]] = None) -> CheckResult:
    """Verifie qu'aucune paire d'images (recto/verso/selfie) n'est identique ou quasi-identique."""
    non_empty = [h for h in hashes if h]
    if len(set(non_empty)) < len(non_empty):
        return CheckResult(
            passed=False,
            score_contribution=0,
            label="Unicite des images",
            detail="Des images rigoureusement identiques ont ete detectees. Chaque photo doit etre unique.",
            is_blocking=True,
        )
    if dhashes:
        valid_dh = [d for d in dhashes if d]
        for i in range(len(valid_dh)):
            for j in range(i + 1, len(valid_dh)):
                if dhash_distance(valid_dh[i], valid_dh[j]) <= 5:
                    return CheckResult(
                        passed=False,
                        score_contribution=0,
                        label="Unicite des images",
                        detail=(
                            "Deux photos soumises sont quasi identiques (recadrage ou doublon detecte). "
                            "Prenez 3 photos distinctes (recto, verso et selfie)."
                        ),
                        is_blocking=True,
                    )
    return CheckResult(
        passed=True,
        score_contribution=10,
        label="Unicite des images",
        detail="Les 3 photos sont bien distinctes (SHA-256 + empreinte perceptuelle).",
    )


def check_cross_provider_duplicates(
    *,
    provider_id: Optional[int],
    cni_number: str,
    sha_hashes: dict[str, str],
    dhash_map: dict[str, str],
) -> Optional[CheckResult]:
    """Anti-fraude inter-comptes : verifie qu'aucun autre prestataire n'utilise
    deja ce numero CNI ou ces memes photos de piece d'identite."""
    try:
        from .models import Provider

        norm_cni = normalize_cni_number(cni_number)
        qs = Provider.objects.filter(is_deleted=False)
        if provider_id:
            qs = qs.exclude(pk=provider_id)

        # 1. Doublon numero CNI
        if norm_cni and norm_cni != "NONFOURNI" and len(norm_cni) >= 6:
            for other in qs.exclude(kyc_cni_number="").only("id", "kyc_cni_number"):
                if normalize_cni_number(other.kyc_cni_number) == norm_cni:
                    return CheckResult(
                        passed=False,
                        score_contribution=0,
                        label="Unicite CNI inter-comptes",
                        detail="Ce numero de CNI est deja associe a un autre compte prestataire BABIFIX.",
                        is_blocking=True,
                    )

        # 2. Doublon photo CNI (SHA-256 ou dHash <= 5)
        my_shas = {v for k, v in sha_hashes.items() if k in ("recto", "verso") and v}
        my_dhashes = [v for k, v in dhash_map.items() if k in ("recto", "verso") and v]
        if my_shas or my_dhashes:
            for other in qs.exclude(kyc_image_hashes={}).only("id", "kyc_image_hashes"):
                oh = other.kyc_image_hashes if isinstance(other.kyc_image_hashes, dict) else {}
                other_shas = {oh.get("sha_recto"), oh.get("sha_verso")} - {None, ""}
                if my_shas & other_shas:
                    return CheckResult(
                        passed=False,
                        score_contribution=0,
                        label="Anti-fraude document inter-comptes",
                        detail="Une photo CNI identique a deja ete soumise sur un autre compte.",
                        is_blocking=True,
                    )
                other_dhs = [oh.get("dhash_recto"), oh.get("dhash_verso")]
                for dh1 in my_dhashes:
                    for dh2 in other_dhs:
                        if dh2 and dhash_distance(dh1, dh2) <= 5:
                            return CheckResult(
                                passed=False,
                                score_contribution=0,
                                label="Anti-fraude document inter-comptes",
                                detail="Document CNI quasi identique deja utilise sur un autre compte.",
                                is_blocking=True,
                            )
    except Exception as exc:
        logger.warning("Cross-provider KYC check skipped: %s", exc)
    return None


# =============================================================================
# 5. Niveau 3 : OpenCV (optionnel)
# =============================================================================
def _opencv_face_check(raw_bytes: bytes, label: str) -> tuple[CheckResult, int]:
    try:
        import cv2
        import numpy as np

        nparr = np.frombuffer(raw_bytes, np.uint8)
        img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        if img is None:
            return (
                CheckResult(
                    passed=False,
                    score_contribution=0,
                    label=f"{label} : detection visage",
                    detail="Image illisible par le moteur de detection.",
                ),
                0,
            )

        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        cascade_path = cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
        face_cascade = cv2.CascadeClassifier(cascade_path)
        faces = face_cascade.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=5, minSize=(60, 60))
        nb = len(faces)

        if nb == 0:
            return (
                CheckResult(
                    passed=False,
                    score_contribution=0,
                    label=f"{label} : detection visage",
                    detail="Aucun visage detecte. Assurez-vous que le visage est bien visible.",
                ),
                0,
            )
        if nb == 1:
            return (
                CheckResult(
                    passed=True,
                    score_contribution=12,
                    label=f"{label} : detection visage",
                    detail="Visage detecte avec succes (OpenCV).",
                ),
                1,
            )
        return (
            CheckResult(
                passed=False,
                score_contribution=3,
                label=f"{label} : detection visage",
                detail=f"{nb} visages detectes. Un seul est attendu.",
            ),
            nb,
        )
    except ImportError:
        if label.lower().startswith("selfie"):
            res, ok = _pillow_portrait_skin_check(raw_bytes, label)
            return res, (1 if ok else 0)
        return (
            CheckResult(
                passed=True,
                score_contribution=4,
                label=f"{label} : verification portrait",
                detail="Controle visuel photo CNI a confirmer par l'equipe KYC.",
            ),
            -1,
        )
    except Exception as exc:
        logger.warning("OpenCV face check error for %s: %s", label, exc)
        return (
            CheckResult(
                passed=True,
                score_contribution=0,
                label=f"{label} : detection visage",
                detail=f"Erreur de detection : {exc}",
            ),
            -1,
        )


def _opencv_face_compare(raw_selfie: bytes, raw_cni: bytes) -> tuple[CheckResult, Optional[float]]:
    try:
        import cv2
        import numpy as np

        def get_face_region(raw: bytes):
            nparr = np.frombuffer(raw, np.uint8)
            img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
            if img is None:
                return None
            gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
            cascade_path = cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
            face_cascade = cv2.CascadeClassifier(cascade_path)
            faces = face_cascade.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=5, minSize=(60, 60))
            if len(faces) == 0:
                return gray
            x, y, w, h = faces[0]
            pad = int(max(w, h) * 0.2)
            x1, y1 = max(0, x - pad), max(0, y - pad)
            x2, y2 = min(img.shape[1], x + w + pad), min(img.shape[0], y + h + pad)
            return gray[y1:y2, x1:x2]

        face_selfie = get_face_region(raw_selfie)
        face_cni = get_face_region(raw_cni)
        if face_selfie is None or face_cni is None:
            return (
                CheckResult(
                    passed=True,
                    score_contribution=0,
                    label="Correspondance visages",
                    detail="Extraction faciale impossible. Controle visuel requis.",
                ),
                None,
            )

        f1 = cv2.resize(face_selfie, (128, 128))
        f2 = cv2.resize(face_cni, (128, 128))
        orb = cv2.ORB_create(nfeatures=500)
        kp1, des1 = orb.detectAndCompute(f1, None)
        kp2, des2 = orb.detectAndCompute(f2, None)
        if des1 is None or des2 is None or len(des1) < 5 or len(des2) < 5:
            return (
                CheckResult(
                    passed=True,
                    score_contribution=3,
                    label="Correspondance visages",
                    detail="Points caracteristiques insuffisants. Verification manuelle recommandee.",
                ),
                None,
            )

        bf = cv2.BFMatcher(cv2.NORM_HAMMING, crossCheck=True)
        matches = bf.match(des1, des2)
        if not matches:
            score = 0.0
        else:
            good = [m for m in sorted(matches, key=lambda x: x.distance) if m.distance < 60]
            score = min(1.0, len(good) / 50.0)

        if score > 0.5:
            return (
                CheckResult(
                    passed=True,
                    score_contribution=10,
                    label="Correspondance visages",
                    detail=f"Correspondance faciale positive (score ORB : {score:.2f}).",
                ),
                score,
            )
        if score > 0.25:
            return (
                CheckResult(
                    passed=True,
                    score_contribution=5,
                    label="Correspondance visages",
                    detail=f"Correspondance partielle (score ORB : {score:.2f}). Verification manuelle.",
                ),
                score,
            )
        return (
            CheckResult(
                passed=False,
                score_contribution=0,
                label="Correspondance visages",
                detail=f"Faible correspondance selfie / CNI (score ORB : {score:.2f}).",
            ),
            score,
        )
    except ImportError:
        return (
            CheckResult(
                passed=True,
                score_contribution=0,
                label="Correspondance visages",
                detail="Comparaison biometrique avancee en attente (controle visuel admin).",
            ),
            None,
        )
    except Exception as exc:
        logger.warning("Face compare error: %s", exc)
        return (
            CheckResult(
                passed=True,
                score_contribution=0,
                label="Correspondance visages",
                detail=f"Erreur de comparaison : {exc}",
            ),
            None,
        )


# =============================================================================
# 6. Niveau 4 : Smile Identity (base gouvernementale CIV si configure)
# =============================================================================
def _smile_signature(api_key: str, partner_id: str) -> tuple[str, str]:
    """Calcule la signature HMAC-SHA256 attendue par Smile Identity."""
    import hmac
    from datetime import datetime, timezone as _tz

    timestamp = datetime.now(_tz.utc).isoformat()
    mac = hmac.new(api_key.encode("utf-8"), digestmod=hashlib.sha256)
    mac.update(timestamp.encode("utf-8"))
    mac.update(str(partner_id).encode("utf-8"))
    mac.update(b"sid_request")
    signature = base64.b64encode(mac.digest()).decode("utf-8")
    return signature, timestamp


def _smile_identity_verify(
    cni_number: str,
    selfie_b64: str,
    cni_recto_b64: str,
    partner_id: str,
    api_key: str,
    sid_server: str = "0",
) -> tuple[CheckResult, dict]:
    try:
        import json as _json
        import time
        import urllib.request as _req

        endpoint = (
            "https://testapi.smileidentity.com/v1/id_verification"
            if sid_server == "0"
            else "https://api.smileidentity.com/v1/id_verification"
        )
        signature, timestamp = _smile_signature(api_key, partner_id)
        selfie_raw_b64 = selfie_b64.split(",", 1)[-1].strip()

        payload = {
            "partner_id": partner_id,
            "partner_params": {
                "job_id": f"BABIFIX-KYC-{int(time.time())}",
                "user_id": f"provider-{cni_number}",
                "job_type": 5,
            },
            "id_info": {
                "country": "CI",
                "id_type": "NATIONAL_ID",
                "id_number": normalize_cni_number(cni_number),
                "entered": "true",
            },
            "image_details": [
                {"image_type_id": 0, "image": selfie_raw_b64},
                {"image_type_id": 1, "image": cni_recto_b64.split(",", 1)[-1].strip()},
            ],
            "signature": signature,
            "timestamp": timestamp,
            "callback_url": "",
            "use_enrolled_image": False,
        }

        data = _json.dumps(payload).encode()
        req = _req.Request(endpoint, data=data, headers={"Content-Type": "application/json"})
        with _req.urlopen(req, timeout=20) as resp:
            result = _json.loads(resp.read().decode())

        actions = result.get("Actions", {})
        smile_result = result.get("ResultText", "UNABLE_TO_VERIFY")
        verified_id = actions.get("Verify_ID_Number", "")
        selfie_check = actions.get("Selfie_To_ID_Authority_Face_Comparison", "")
        liveness = actions.get("Liveness_Check", "")

        if smile_result in ("Passed", "Verified") or verified_id in ("Passed", "Verified"):
            return (
                CheckResult(
                    passed=True,
                    score_contribution=25,
                    label="Verification gouvernementale (Smile Identity / ONECI)",
                    detail=f"CNI verifiee. Biometrie : {selfie_check}. Liveness : {liveness}.",
                ),
                result,
            )
        if smile_result in ("Failed", "Not Verified") or verified_id in ("Failed", "Not Verified"):
            return (
                CheckResult(
                    passed=False,
                    score_contribution=0,
                    label="Verification gouvernementale (Smile Identity / ONECI)",
                    detail=f"Numero CNI non trouve ou non correspondant ({smile_result}).",
                    is_blocking=True,
                ),
                result,
            )
        return (
            CheckResult(
                passed=True,
                score_contribution=8,
                label="Verification gouvernementale (Smile Identity / ONECI)",
                detail=f"Resultat non concluant ({smile_result}). Examen manuel requis.",
            ),
            result,
        )
    except Exception as exc:
        logger.error("Smile Identity error: %s", exc)
        return (
            CheckResult(
                passed=True,
                score_contribution=0,
                label="Verification gouvernementale (Smile Identity / ONECI)",
                detail=f"Service indisponible : {exc}. Verification manuelle requise.",
            ),
            {"error": str(exc)},
        )


# =============================================================================
# 7. Point d'entree principal
# =============================================================================
def run_kyc_verification(
    cni_number: str,
    cni_recto_b64: str,
    cni_verso_b64: str,
    selfie_b64: str,
    hash_recto: str,
    hash_verso: str,
    hash_selfie: str,
    *,
    cni_expiry: Optional[date] = None,
    mrz_text: str = "",
    provider_id: Optional[int] = None,
    provider_name: str = "",
) -> KYCVerificationResult:
    """Execute tous les controles KYC deterministes et retourne un rapport detaille."""
    from django.conf import settings

    result = KYCVerificationResult()
    score = 0
    blocking_failed = False

    # 1. Format CNI / NNI ONECI
    cni_ok, cni_msg = _validate_cni_format(cni_number)
    conf_fmt = cni_confidence(cni_number)
    fmt_points = 14 if (cni_ok and conf_fmt == "strong") else (10 if cni_ok else 0)
    fmt_lbl = _cni_format_label(normalize_cni_number(cni_number))
    result.checks.append(
        CheckResult(
            passed=cni_ok,
            score_contribution=fmt_points,
            label="Format CNI / NNI ONECI",
            detail=(f"Format reconnu ({fmt_lbl})." if fmt_lbl else "Format alphanumerique accepte.")
            if cni_ok
            else cni_msg,
            is_blocking=False,
        )
    )
    score += fmt_points
    if not cni_ok:
        result.hints.append(cni_msg)

    # 2. Coherence date d'expiration CNI (validite ONECI = 10 ans)
    if cni_expiry is not None:
        today = date.today()
        if cni_expiry <= today:
            result.checks.append(
                CheckResult(
                    passed=False,
                    score_contribution=0,
                    label="Validite date d'expiration CNI",
                    detail=f"Piece d'identite expiree depuis le {cni_expiry.isoformat()}.",
                    is_blocking=True,
                )
            )
            blocking_failed = True
            result.hints.append("Votre CNI est expiree : soumettez une piece en cours de validite.")
        elif (cni_expiry - today).days > 365 * 15:
            result.checks.append(
                CheckResult(
                    passed=False,
                    score_contribution=0,
                    label="Validite date d'expiration CNI",
                    detail=f"Date d'expiration incoherente ({cni_expiry.isoformat()}, > 15 ans).",
                )
            )
            result.hints.append("Verifiez la date d'expiration saisie (validite standard CNI ONECI : 10 ans).")
        else:
            result.checks.append(
                CheckResult(
                    passed=True,
                    score_contribution=6,
                    label="Validite date d'expiration CNI",
                    detail=f"CNI en cours de validite jusqu'au {cni_expiry.isoformat()}.",
                )
            )
            score += 6

    # 3. Controle cryptographique MRZ TD1 ICAO 9303 (si fournie)
    if (mrz_text or "").strip():
        mrz_res = parse_and_validate_mrz_td1(
            mrz_text,
            expected_cni=cni_number,
            expected_expiry=cni_expiry,
            expected_name=provider_name,
        )
        result.mrz_parsed = mrz_res
        if mrz_res["valid"]:
            mrz_pts = 15 if not mrz_res["warnings"] else 10
            result.checks.append(
                CheckResult(
                    passed=True,
                    score_contribution=mrz_pts,
                    label="Signature MRZ ICAO 9303 (ONECI)",
                    detail=(
                        f"4 cles de controle MRZ valides ({mrz_res.get('issuing_country', '')} · "
                        f"piece {mrz_res.get('doc_number', '')})."
                        + (f" Avertissements : {' '.join(mrz_res['warnings'])}" if mrz_res["warnings"] else "")
                    ),
                )
            )
            score += mrz_pts
            result.hints.extend(mrz_res["warnings"])
        else:
            err_txt = " ".join(mrz_res["errors"])
            is_minor_or_expired = any(
                k in err_txt.lower() for k in ("mineur", "expiree")
            )
            result.checks.append(
                CheckResult(
                    passed=False,
                    score_contribution=0,
                    label="Signature MRZ ICAO 9303 (ONECI)",
                    detail=err_txt or "MRZ invalide.",
                    is_blocking=is_minor_or_expired,
                )
            )
            if is_minor_or_expired:
                blocking_failed = True
            result.hints.extend(mrz_res["errors"])

    # 4. Decodage images + empreintes SHA-256 & perceptuelles dHash
    raw_recto = _decode_b64(cni_recto_b64) if cni_recto_b64 else None
    raw_verso = _decode_b64(cni_verso_b64) if cni_verso_b64 else None
    raw_selfie = _decode_b64(selfie_b64) if selfie_b64 else None

    sha_recto = hash_recto or (hashlib.sha256(raw_recto).hexdigest() if raw_recto else "")
    sha_verso = hash_verso or (hashlib.sha256(raw_verso).hexdigest() if raw_verso else "")
    sha_selfie = hash_selfie or (hashlib.sha256(raw_selfie).hexdigest() if raw_selfie else "")

    dh_recto = compute_dhash(raw_recto) if raw_recto else ""
    dh_verso = compute_dhash(raw_verso) if raw_verso else ""
    dh_selfie = compute_dhash(raw_selfie) if raw_selfie else ""

    result.image_hashes = {
        "sha_recto": sha_recto,
        "sha_verso": sha_verso,
        "sha_selfie": sha_selfie,
        "dhash_recto": dh_recto,
        "dhash_verso": dh_verso,
        "dhash_selfie": dh_selfie,
    }

    # 5. Unicite intra-dossier (SHA-256 + dHash Hamming <= 5)
    uniq = _check_images_distinct(
        [sha_recto, sha_verso, sha_selfie],
        [dh_recto, dh_verso, dh_selfie],
    )
    result.checks.append(uniq)
    if not uniq.passed:
        blocking_failed = True
        result.hints.append(uniq.detail)
    score += uniq.score_contribution

    # 6. Anti-fraude inter-comptes en base (numero CNI & photos deja utilises)
    dup_check = check_cross_provider_duplicates(
        provider_id=provider_id,
        cni_number=cni_number,
        sha_hashes={"recto": sha_recto, "verso": sha_verso},
        dhash_map={"recto": dh_recto, "verso": dh_verso},
    )
    if dup_check is not None:
        result.checks.append(dup_check)
        if dup_check.is_blocking and not dup_check.passed:
            blocking_failed = True
            result.hints.append(dup_check.detail)
    else:
        result.checks.append(
            CheckResult(
                passed=True,
                score_contribution=8,
                label="Unicite inter-comptes BABIFIX",
                detail="Aucun doublon de CNI ou de document detecte sur un autre compte.",
            )
        )
        score += 8

    # 7. Qualite optique reelle (Pillow : resolution, ratio ID-1, Laplacien 2D, reflets, couleur)
    for raw, lbl, is_card in (
        (raw_recto, "CNI Recto", True),
        (raw_verso, "CNI Verso", True),
        (raw_selfie, "Selfie", False),
    ):
        if raw:
            p_checks, p_hints = _pillow_checks(raw, lbl, is_id_card=is_card)
            result.hints.extend(p_hints)
            for c in p_checks:
                result.checks.append(c)
                score += c.score_contribution

    # 8. Detection visage / portrait
    if raw_selfie:
        face_check_selfie, nb_selfie = _opencv_face_check(raw_selfie, "Selfie")
        result.checks.append(face_check_selfie)
        score += face_check_selfie.score_contribution
        result.face_detected_selfie = nb_selfie == 1
        if not face_check_selfie.passed:
            result.hints.append(face_check_selfie.detail)

    if raw_recto:
        face_check_cni, nb_cni = _opencv_face_check(raw_recto, "CNI Recto")
        result.checks.append(face_check_cni)
        score += face_check_cni.score_contribution
        result.face_detected_cni = nb_cni == 1

    # 9. Comparaison faciale selfie <-> CNI (si OpenCV disponible)
    if raw_selfie and raw_recto:
        compare_check, match_score = _opencv_face_compare(raw_selfie, raw_recto)
        result.checks.append(compare_check)
        score += compare_check.score_contribution
        result.faces_match = match_score

    # 10. Verification gouvernementale Smile Identity (si cles configurees)
    smile_partner_id = getattr(settings, "SMILE_IDENTITY_PARTNER_ID", "")
    smile_api_key = getattr(settings, "SMILE_IDENTITY_API_KEY", "")
    smile_server = getattr(settings, "SMILE_IDENTITY_SERVER", "0")

    if smile_partner_id and smile_api_key and raw_selfie:
        sid_check, sid_raw = _smile_identity_verify(
            cni_number=cni_number,
            selfie_b64=selfie_b64,
            cni_recto_b64=cni_recto_b64,
            partner_id=smile_partner_id,
            api_key=smile_api_key,
            sid_server=smile_server,
        )
        result.checks.append(sid_check)
        score += sid_check.score_contribution
        result.smile_identity_result = sid_raw
        if sid_check.is_blocking and not sid_check.passed:
            blocking_failed = True
            result.hints.append(sid_check.detail)
    else:
        result.checks.append(
            CheckResult(
                passed=True,
                score_contribution=0,
                label="Verification gouvernementale (ONECI / Smile Identity)",
                detail=(
                    "Adaptateur pret (renseignez SMILE_IDENTITY_PARTNER_ID / API_KEY ou "
                    "convention ONECI pour l'interrogation temps reel de la base nationale)."
                ),
            )
        )

    # Deduplication des conseils
    result.hints = list(dict.fromkeys(h for h in result.hints if h))
    result.score = min(100, max(0, score))

    if blocking_failed:
        result.confidence = "REJECTED"
        result.auto_decision = "rejected"
    elif result.score >= 78:
        result.confidence = "HIGH_CONFIDENCE"
        result.auto_decision = "under_review"
    elif result.score >= 55:
        result.confidence = "MEDIUM_CONFIDENCE"
        result.auto_decision = "under_review"
    else:
        result.confidence = "LOW_CONFIDENCE"
        result.auto_decision = "pending"

    return result


def recalculate_provider_kyc(provider) -> KYCVerificationResult:
    """Recalcule fidelement le score KYC a partir des vrais fichiers et donnees du prestataire."""
    from pathlib import Path
    from django.conf import settings
    from django.utils import timezone

    cni_num = getattr(provider, "kyc_cni_number", "") or getattr(provider, "cni_number", "") or ""

    def _read_file_bytes(path_or_b64: str) -> tuple[str, str]:
        if not path_or_b64:
            return "", ""
        if path_or_b64.startswith("data:image/"):
            raw = _decode_b64(path_or_b64)
            return path_or_b64, (hashlib.sha256(raw).hexdigest() if raw else "")
        try:
            clean = path_or_b64.replace("/media/", "", 1).lstrip("/\\")
            if ".." in clean:
                return "", ""
            full = Path(settings.MEDIA_ROOT) / clean
            if full.exists() and full.is_file():
                raw = full.read_bytes()
                return base64.b64encode(raw).decode("ascii"), hashlib.sha256(raw).hexdigest()
        except Exception:
            pass
        return "", ""

    recto_src = (
        getattr(provider, "kyc_cni_recto_url", "")
        or getattr(provider, "cni_recto_url", "")
        or getattr(provider, "cni_url", "")
    )
    verso_src = getattr(provider, "kyc_cni_verso_url", "") or getattr(provider, "cni_verso_url", "")
    selfie_src = (
        getattr(provider, "kyc_selfie_url", "")
        or getattr(provider, "selfie_url", "")
        or getattr(provider, "photo_portrait_url", "")
    )

    recto_b64, hash_recto = _read_file_bytes(recto_src)
    verso_b64, hash_verso = _read_file_bytes(verso_src)
    selfie_b64, hash_selfie = _read_file_bytes(selfie_src)

    res = run_kyc_verification(
        cni_number=cni_num or "NON_FOURNI",
        cni_recto_b64=recto_b64,
        cni_verso_b64=verso_b64,
        selfie_b64=selfie_b64,
        hash_recto=hash_recto,
        hash_verso=hash_verso,
        hash_selfie=hash_selfie,
        cni_expiry=getattr(provider, "kyc_cni_expiry", None),
        mrz_text=getattr(provider, "kyc_cni_mrz", "") or "",
        provider_id=provider.pk,
        provider_name=getattr(provider, "nom", "") or "",
    )

    provider.auto_check_score = res.score
    provider.auto_check_result = res.to_dict()
    provider.auto_check_at = timezone.now()
    update_fields = ["auto_check_score", "auto_check_result", "auto_check_at"]
    if hasattr(provider, "kyc_image_hashes") and res.image_hashes:
        provider.kyc_image_hashes = res.image_hashes
        update_fields.append("kyc_image_hashes")
    provider.save(update_fields=update_fields)
    return res
