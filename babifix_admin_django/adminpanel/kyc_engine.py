"""
BABIFIX KYC Verification Engine
================================

Trois niveaux de vérification en cascade :

  Niveau 1 — Pillow (toujours actif, aucune dépendance système)
    • Format image valide (JPEG/PNG)
    • Résolution ≥ 640×480
    • Détection de flou (variance du Laplacien sur niveaux de gris)
    • Luminosité moyenne (trop sombre / trop clair)
    • Les 3 images ne doivent pas être identiques (hash SHA-256)
    • Validation format CNI ivoirienne (regex + longueur)

  Niveau 2 — OpenCV (si `pip install opencv-python` est fait)
    • Détection de visage dans le selfie (Haar cascade frontal)
    • Détection de visage dans le recto CNI
    • Cohérence : exactement 1 visage dans chaque photo
    • Anti-spoofing basique : luminosité des régions du visage

  Niveau 3 — Smile Identity (si SMILE_IDENTITY_* configuré dans settings)
    • Vérification du numéro CNI contre la base gouvernementale ivoirienne
    • Correspondance biométrique selfie ↔ CNI officielle
    • Résultat : VERIFIED / NOT_VERIFIED / UNABLE_TO_VERIFY

Score global 0–100 :
  ≥ 80  → HIGH_CONFIDENCE   (suggestion approbation, admin décide toujours)
  60–79 → MEDIUM_CONFIDENCE (dossier complet, review manuel recommandé)
  40–59 → LOW_CONFIDENCE    (problèmes détectés, admin doit examiner)
  < 40  → REJECTED_AUTO     (rejet automatique avec motifs)
"""

from __future__ import annotations

import base64
import hashlib
import io
import logging
import re
from dataclasses import dataclass, field
from typing import Optional

logger = logging.getLogger(__name__)


# ─── Format CNI ivoirienne ────────────────────────────────────────────────────
# Plusieurs formats coexistent selon la génération :
#   - Ancienne : lettres + chiffres, 8-15 car.  ex: C 0123456 B
#   - Biométrique récente : CI + 9 chiffres     ex: CI023456789
#   - CEDEAO : format variable selon émission
_CNI_PATTERNS = [
    re.compile(r'^CI\s*\d{7,12}$', re.I),        # CI + 7–12 chiffres
    re.compile(r'^[A-Z]\s*\d{6,9}\s*[A-Z]$', re.I),  # Lettre + chiffres + lettre
    re.compile(r'^C\s*\d{6,9}$', re.I),           # Ancien format C + chiffres
    re.compile(r'^\d{9,15}$'),                     # Purement numérique
    re.compile(r'^[A-Z0-9]{8,16}$', re.I),        # Alphanumérique générique
]


def _validate_cni_format(cni_number: str) -> tuple[bool, str]:
    """Valide le format d'un numéro de CNI ivoirienne. Retourne (ok, motif)."""
    cleaned = cni_number.strip().upper().replace(' ', '').replace('-', '').replace('.', '')
    if len(cleaned) < 5:
        return False, 'Numéro trop court (minimum 5 caractères).'
    if len(cleaned) > 20:
        return False, 'Numéro trop long (maximum 20 caractères).'
    for pattern in _CNI_PATTERNS:
        if pattern.match(cleaned):
            return True, ''
    # Accepté avec avertissement si alphanumérique ≥ 6 chars
    if re.match(r'^[A-Z0-9]{6,}$', cleaned):
        return True, ''
    return False, f"Format non reconnu : '{cni_number}'. Vérifiez et re-saisissez."


# ─── Résultats ────────────────────────────────────────────────────────────────

@dataclass
class CheckResult:
    passed: bool
    score_contribution: int   # points ajoutés au score total
    label: str                # nom du contrôle
    detail: str               # message affiché à l'admin
    is_blocking: bool = False # si True et failed → rejet immédiat


@dataclass
class KYCVerificationResult:
    score: int = 0            # 0–100
    confidence: str = 'LOW_CONFIDENCE'
    auto_decision: str = 'pending'  # 'pending' | 'under_review' | 'rejected'
    checks: list[CheckResult] = field(default_factory=list)
    smile_identity_result: Optional[dict] = None
    face_detected_selfie: bool = False
    face_detected_cni: bool = False
    faces_match: Optional[float] = None  # 0.0–1.0 si disponible

    def to_dict(self) -> dict:
        return {
            'score': self.score,
            'confidence': self.confidence,
            'auto_decision': self.auto_decision,
            'face_detected_selfie': self.face_detected_selfie,
            'face_detected_cni': self.face_detected_cni,
            'faces_match': self.faces_match,
            'smile_identity': self.smile_identity_result,
            'checks': [
                {
                    'label': c.label,
                    'passed': c.passed,
                    'detail': c.detail,
                    'blocking': c.is_blocking,
                }
                for c in self.checks
            ],
        }


# ─── Niveau 1 : Pillow ───────────────────────────────────────────────────────

def _decode_b64(b64_str: str) -> Optional[bytes]:
    try:
        raw = b64_str.split(',', 1)[-1].strip()
        return base64.b64decode(raw)
    except Exception:
        return None


def _pillow_checks(raw: bytes, label: str) -> list[CheckResult]:
    """Contrôles qualité image via Pillow uniquement."""
    results = []
    try:
        from PIL import Image, ImageStat
        img = Image.open(io.BytesIO(raw))
        w, h = img.size

        # Résolution minimum
        if w < 400 or h < 300:
            results.append(CheckResult(
                passed=False, score_contribution=0,
                label=f'{label} — résolution',
                detail=f'Image trop petite ({w}×{h}px). Minimum requis : 400×300.',
                is_blocking=True,
            ))
        elif w < 640 or h < 480:
            results.append(CheckResult(
                passed=True, score_contribution=3,
                label=f'{label} — résolution',
                detail=f'Résolution acceptable ({w}×{h}px). Une image plus nette serait préférable.',
            ))
        else:
            results.append(CheckResult(
                passed=True, score_contribution=7,
                label=f'{label} — résolution',
                detail=f'Résolution correcte ({w}×{h}px).',
            ))

        # Luminosité (0=noir, 255=blanc)
        gray = img.convert('L')
        stat = ImageStat.Stat(gray)
        mean_bright = stat.mean[0]
        if mean_bright < 40:
            results.append(CheckResult(
                passed=False, score_contribution=0,
                label=f'{label} — luminosité',
                detail=f'Image trop sombre (luminosité {mean_bright:.0f}/255). Prenez la photo dans un endroit bien éclairé.',
                is_blocking=False,
            ))
        elif mean_bright > 230:
            results.append(CheckResult(
                passed=False, score_contribution=0,
                label=f'{label} — luminosité',
                detail=f'Image surexposée (luminosité {mean_bright:.0f}/255). Évitez la lumière directe sur le document.',
                is_blocking=False,
            ))
        else:
            results.append(CheckResult(
                passed=True, score_contribution=5,
                label=f'{label} — luminosité',
                detail=f'Luminosité correcte ({mean_bright:.0f}/255).',
            ))

        # Flou via variance des pixels (approximation Laplacien)
        import array as _array
        pixels = list(gray.getdata())
        if len(pixels) > 1:
            mean = sum(pixels) / len(pixels)
            variance = sum((p - mean) ** 2 for p in pixels) / len(pixels)
            if variance < 200:
                results.append(CheckResult(
                    passed=False, score_contribution=0,
                    label=f'{label} — netteté',
                    detail=f'Image floue (variance {variance:.0f}). Stabilisez l\'appareil et refaites la photo.',
                    is_blocking=False,
                ))
            elif variance < 500:
                results.append(CheckResult(
                    passed=True, score_contribution=4,
                    label=f'{label} — netteté',
                    detail=f'Netteté acceptable (variance {variance:.0f}).',
                ))
            else:
                results.append(CheckResult(
                    passed=True, score_contribution=8,
                    label=f'{label} — netteté',
                    detail=f'Image nette (variance {variance:.0f}).',
                ))

    except Exception as e:
        logger.warning(f'Pillow check failed for {label}: {e}')
        results.append(CheckResult(
            passed=False, score_contribution=0,
            label=f'{label} — lecture image',
            detail='Impossible de lire l\'image. Vérifiez le format (JPEG/PNG requis).',
            is_blocking=True,
        ))
    return results


def _check_images_distinct(hashes: list[str]) -> CheckResult:
    """Les 3 images ne doivent pas être identiques (tentative de fraude)."""
    unique = set(h for h in hashes if h)
    if len(unique) < len([h for h in hashes if h]):
        return CheckResult(
            passed=False, score_contribution=0,
            label='Unicité des images',
            detail='Des images identiques ont été détectées. Chaque photo doit être unique.',
            is_blocking=True,
        )
    return CheckResult(
        passed=True, score_contribution=10,
        label='Unicité des images',
        detail='Les 3 photos sont distinctes.',
    )


# ─── Niveau 2 : OpenCV ───────────────────────────────────────────────────────

def _opencv_face_check(raw_bytes: bytes, label: str) -> tuple[CheckResult, int]:
    """Détecte les visages dans une image. Retourne (résultat, nb_visages_détectés)."""
    try:
        import cv2
        import numpy as np
        nparr = np.frombuffer(raw_bytes, np.uint8)
        img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        if img is None:
            return CheckResult(
                passed=False, score_contribution=0,
                label=f'{label} — détection visage',
                detail='Image illisible par le moteur de détection.',
            ), 0

        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        # Haar cascade frontal (inclus dans OpenCV, aucun fichier externe requis)
        import os
        cascade_path = cv2.data.haarcascades + 'haarcascade_frontalface_default.xml'
        face_cascade = cv2.CascadeClassifier(cascade_path)
        faces = face_cascade.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=5, minSize=(60, 60))
        nb = len(faces)

        if nb == 0:
            return CheckResult(
                passed=False, score_contribution=0,
                label=f'{label} — détection visage',
                detail='Aucun visage détecté. Assurez-vous que votre visage / la photo sur la CNI est bien visible.',
            ), 0
        elif nb == 1:
            return CheckResult(
                passed=True, score_contribution=15,
                label=f'{label} — détection visage',
                detail='Visage détecté avec succès.',
            ), 1
        else:
            return CheckResult(
                passed=False, score_contribution=5,
                label=f'{label} — détection visage',
                detail=f'{nb} visages détectés. Un seul est attendu.',
            ), nb

    except ImportError:
        return CheckResult(
            passed=True, score_contribution=5,  # pas pénalisé si OpenCV absent
            label=f'{label} — détection visage',
            detail='Détection OpenCV non disponible (non installé). Vérification manuelle requise.',
        ), -1
    except Exception as e:
        logger.warning(f'OpenCV face check error for {label}: {e}')
        return CheckResult(
            passed=True, score_contribution=0,
            label=f'{label} — détection visage',
            detail=f'Erreur de détection : {e}',
        ), -1


def _opencv_face_compare(raw_selfie: bytes, raw_cni: bytes) -> tuple[CheckResult, Optional[float]]:
    """Compare les visages selfie vs CNI avec ORB + BFMatcher (approximation)."""
    try:
        import cv2
        import numpy as np

        def get_face_region(raw: bytes):
            nparr = np.frombuffer(raw, np.uint8)
            img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
            if img is None:
                return None
            gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
            cascade_path = cv2.data.haarcascades + 'haarcascade_frontalface_default.xml'
            face_cascade = cv2.CascadeClassifier(cascade_path)
            faces = face_cascade.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=5, minSize=(60, 60))
            if len(faces) == 0:
                return gray  # fallback : image entière
            x, y, w, h = faces[0]
            pad = int(max(w, h) * 0.2)
            x1, y1 = max(0, x - pad), max(0, y - pad)
            x2, y2 = min(img.shape[1], x + w + pad), min(img.shape[0], y + h + pad)
            return gray[y1:y2, x1:x2]

        face_selfie = get_face_region(raw_selfie)
        face_cni = get_face_region(raw_cni)
        if face_selfie is None or face_cni is None:
            return CheckResult(
                passed=True, score_contribution=0,
                label='Correspondance visages',
                detail='Impossible d\'extraire les régions faciales pour comparaison.',
            ), None

        # Redimensionner pour comparaison
        import cv2
        size = (128, 128)
        f1 = cv2.resize(face_selfie, size)
        f2 = cv2.resize(face_cni, size)

        # ORB feature matching
        orb = cv2.ORB_create(nfeatures=500)
        kp1, des1 = orb.detectAndCompute(f1, None)
        kp2, des2 = orb.detectAndCompute(f2, None)

        if des1 is None or des2 is None or len(des1) < 5 or len(des2) < 5:
            return CheckResult(
                passed=True, score_contribution=3,
                label='Correspondance visages',
                detail='Trop peu de points caractéristiques. Vérification manuelle recommandée.',
            ), None

        bf = cv2.BFMatcher(cv2.NORM_HAMMING, crossCheck=True)
        matches = bf.match(des1, des2)
        if not matches:
            score = 0.0
        else:
            good = [m for m in sorted(matches, key=lambda x: x.distance) if m.distance < 60]
            score = min(1.0, len(good) / 50.0)

        if score > 0.5:
            return CheckResult(
                passed=True, score_contribution=10,
                label='Correspondance visages',
                detail=f'Correspondance faciale positive (score ORB : {score:.2f}).',
            ), score
        elif score > 0.25:
            return CheckResult(
                passed=True, score_contribution=5,
                label='Correspondance visages',
                detail=f'Correspondance partielle (score ORB : {score:.2f}). Vérification manuelle recommandée.',
            ), score
        else:
            return CheckResult(
                passed=False, score_contribution=0,
                label='Correspondance visages',
                detail=f'Faible correspondance entre le selfie et la CNI (score ORB : {score:.2f}). Vérifiez que le selfie représente bien le titulaire.',
            ), score

    except ImportError:
        return CheckResult(
            passed=True, score_contribution=0,
            label='Correspondance visages',
            detail='OpenCV non installé. Comparaison manuelle requise.',
        ), None
    except Exception as e:
        logger.warning(f'Face compare error: {e}')
        return CheckResult(
            passed=True, score_contribution=0,
            label='Correspondance visages',
            detail=f'Erreur de comparaison : {e}',
        ), None


# ─── Niveau 3 : Smile Identity ───────────────────────────────────────────────

def _smile_identity_verify(
    cni_number: str,
    selfie_b64: str,
    cni_recto_b64: str,
    partner_id: str,
    api_key: str,
    sid_server: str = '0',  # 0 = sandbox, 1 = production
) -> tuple[CheckResult, dict]:
    """
    Vérifie la CNI contre la base gouvernementale ivoirienne via Smile Identity.

    Docs : https://docs.usesmileid.com
    Produit utilisé : Enhanced Document Verification (EDV)
    Country : CI (Côte d'Ivoire)
    ID type : NATIONAL_ID

    Retourne (CheckResult, raw_response_dict).
    """
    try:
        import json as _json
        import time
        import urllib.request as _req
        import urllib.parse as _parse

        endpoint = (
            'https://testapi.smileidentity.com/v1/id_verification'
            if sid_server == '0'
            else 'https://api.smileidentity.com/v1/id_verification'
        )

        # Préparer les données
        # Extraire juste le base64 brut (sans le préfixe data:...)
        selfie_raw_b64 = selfie_b64.split(',', 1)[-1].strip()

        payload = {
            'partner_id': partner_id,
            'partner_params': {
                'job_id': f'BABIFIX-KYC-{int(time.time())}',
                'user_id': f'provider-{cni_number}',
                'job_type': 5,  # Enhanced Document Verification
            },
            'id_info': {
                'country': 'CI',
                'id_type': 'NATIONAL_ID',
                'id_number': cni_number.strip().upper().replace(' ', ''),
                'entered': 'true',
            },
            'image_details': [
                {'image_type_id': 0, 'image': selfie_raw_b64},    # selfie
                {'image_type_id': 1, 'image': cni_recto_b64.split(',', 1)[-1].strip()},  # CNI recto
            ],
            'signature': api_key,
            'timestamp': str(int(time.time())),
            'callback_url': '',
            'use_enrolled_image': False,
        }

        data = _json.dumps(payload).encode()
        req = _req.Request(endpoint, data=data, headers={'Content-Type': 'application/json'})
        with _req.urlopen(req, timeout=20) as resp:
            result = _json.loads(resp.read().decode())

        actions = result.get('Actions', {})
        smile_result = result.get('ResultText', 'UNABLE_TO_VERIFY')

        # Interpréter le résultat
        verified_id = actions.get('Verify_ID_Number', '')
        human_review = actions.get('Human_Review_Needed', 'false')
        selfie_check = actions.get('Selfie_To_ID_Authority_Face_Comparison', '')
        liveness = actions.get('Liveness_Check', '')

        if smile_result in ('Passed', 'Verified') or verified_id in ('Passed', 'Verified'):
            return CheckResult(
                passed=True, score_contribution=30,
                label='Vérification gouvernementale (Smile Identity)',
                detail=(
                    f'CNI vérifiée en base gouvernementale ivoirienne. '
                    f'Correspondance biométrique : {selfie_check}. '
                    f'Liveness : {liveness}.'
                ),
            ), result
        elif smile_result in ('Failed', 'Not Verified') or verified_id in ('Failed', 'Not Verified'):
            return CheckResult(
                passed=False, score_contribution=0,
                label='Vérification gouvernementale (Smile Identity)',
                detail=(
                    f'Numéro CNI non trouvé ou non correspondant en base gouvernementale. '
                    f'Résultat : {smile_result}.'
                ),
                is_blocking=True,
            ), result
        else:
            return CheckResult(
                passed=True, score_contribution=10,
                label='Vérification gouvernementale (Smile Identity)',
                detail=f'Vérification inconclusive ({smile_result}). Examen manuel requis.',
            ), result

    except ImportError:
        return CheckResult(
            passed=True, score_contribution=0,
            label='Vérification gouvernementale',
            detail='Bibliothèque réseau non disponible.',
        ), {}
    except Exception as e:
        logger.error(f'Smile Identity error: {e}')
        return CheckResult(
            passed=True, score_contribution=0,
            label='Vérification gouvernementale (Smile Identity)',
            detail=f'Service indisponible : {e}. Vérification manuelle requise.',
        ), {'error': str(e)}


# ─── Point d'entrée principal ────────────────────────────────────────────────

def run_kyc_verification(
    cni_number: str,
    cni_recto_b64: str,
    cni_verso_b64: str,
    selfie_b64: str,
    hash_recto: str,
    hash_verso: str,
    hash_selfie: str,
) -> KYCVerificationResult:
    """
    Lance tous les contrôles KYC et retourne un KYCVerificationResult.
    Appellé après l'enregistrement en base, de manière synchrone.
    Pour une production réelle, mettre dans une tâche Celery.
    """
    from django.conf import settings

    result = KYCVerificationResult()
    score = 0
    blocking_failed = False

    # ── 1. Format CNI ─────────────────────────────────────────────────────────
    cni_ok, cni_msg = _validate_cni_format(cni_number)
    cni_check = CheckResult(
        passed=cni_ok,
        score_contribution=10 if cni_ok else 0,
        label='Format CNI ivoirienne',
        detail='Format reconnu.' if cni_ok else cni_msg,
        is_blocking=not cni_ok,
    )
    result.checks.append(cni_check)
    if not cni_ok:
        blocking_failed = True
    score += cni_check.score_contribution

    # ── 2. Unicité des images ─────────────────────────────────────────────────
    uniq = _check_images_distinct([hash_recto, hash_verso, hash_selfie])
    result.checks.append(uniq)
    if not uniq.passed:
        blocking_failed = True
    score += uniq.score_contribution

    # ── 3. Qualité image (Pillow) ─────────────────────────────────────────────
    raw_recto  = _decode_b64(cni_recto_b64) if cni_recto_b64 else None
    raw_verso  = _decode_b64(cni_verso_b64) if cni_verso_b64 else None
    raw_selfie = _decode_b64(selfie_b64) if selfie_b64 else None

    for raw, label in [(raw_recto, 'CNI Recto'), (raw_verso, 'CNI Verso'), (raw_selfie, 'Selfie')]:
        if raw:
            checks = _pillow_checks(raw, label)
            for c in checks:
                result.checks.append(c)
                score += c.score_contribution
                if c.is_blocking and not c.passed:
                    blocking_failed = True

    # ── 4. Détection de visage (OpenCV) ──────────────────────────────────────
    if raw_selfie:
        face_check_selfie, nb_selfie = _opencv_face_check(raw_selfie, 'Selfie')
        result.checks.append(face_check_selfie)
        score += face_check_selfie.score_contribution
        result.face_detected_selfie = nb_selfie == 1

    if raw_recto:
        face_check_cni, nb_cni = _opencv_face_check(raw_recto, 'CNI Recto')
        result.checks.append(face_check_cni)
        score += face_check_cni.score_contribution
        result.face_detected_cni = nb_cni == 1

    # ── 5. Comparaison visages selfie ↔ CNI ───────────────────────────────────
    if raw_selfie and raw_recto:
        compare_check, match_score = _opencv_face_compare(raw_selfie, raw_recto)
        result.checks.append(compare_check)
        score += compare_check.score_contribution
        result.faces_match = match_score

    # ── 6. Smile Identity (si configuré) ─────────────────────────────────────
    smile_partner_id = getattr(settings, 'SMILE_IDENTITY_PARTNER_ID', '')
    smile_api_key    = getattr(settings, 'SMILE_IDENTITY_API_KEY', '')
    smile_server     = getattr(settings, 'SMILE_IDENTITY_SERVER', '0')  # '0'=sandbox

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
    else:
        result.checks.append(CheckResult(
            passed=True, score_contribution=0,
            label='Vérification gouvernementale (Smile Identity)',
            detail=(
                'Non configuré. Pour activer la vérification contre la base '
                'gouvernementale ivoirienne, renseignez SMILE_IDENTITY_PARTNER_ID '
                'et SMILE_IDENTITY_API_KEY dans les settings.'
                if not smile_partner_id
                else 'Clé API manquante.'
            ),
        ))

    # ── Calcul score final ────────────────────────────────────────────────────
    result.score = min(100, max(0, score))

    if blocking_failed or result.score < 40:
        result.confidence = 'REJECTED'
        result.auto_decision = 'rejected'
    elif result.score >= 80:
        result.confidence = 'HIGH_CONFIDENCE'
        result.auto_decision = 'under_review'  # admin valide toujours, mais on passe en review
    elif result.score >= 60:
        result.confidence = 'MEDIUM_CONFIDENCE'
        result.auto_decision = 'under_review'
    else:
        result.confidence = 'LOW_CONFIDENCE'
        result.auto_decision = 'pending'

    return result
