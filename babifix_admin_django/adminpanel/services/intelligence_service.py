"""
Services d'intelligence metier BABIFIX :
- Scoring multicritere & recherche tolérante aux fautes / symptomes (SmartProviderScorer)
- Estimation de prix Abidjan & verification de coherence devis (SmartDevisAdvisor)
- Radar executif des risques operationnels & financiers admin (AdminRiskRadar)

Respecte strictement l'independance des Categories (lecture seule uniquement).
"""

from __future__ import annotations

import logging
import math
import statistics
import unicodedata
from datetime import timedelta
from difflib import SequenceMatcher
from typing import Any, Dict, Iterable, List, Optional, Tuple

from django.db.models import Avg, Count, Q
from django.utils import timezone

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Normalisation texte & expansion symptomes terrain (Cote d'Ivoire)
# ---------------------------------------------------------------------------

SYMPTOM_SYNONYMS: Dict[str, Tuple[str, ...]] = {
    # Plomberie (goutte)
    "fuite": ("plomb", "plomberie", "sanitaire", "eau", "tuyau", "robinet", "goutte"),
    "tuyau": ("plomb", "plomberie", "sanitaire", "fuite", "siphon"),
    "robinet": ("plomb", "plomberie", "sanitaire", "mitigeur", "fuite"),
    "evier": ("plomb", "plomberie", "sanitaire", "debouchage", "siphon"),
    "lavabo": ("plomb", "plomberie", "sanitaire", "siphon"),
    "wc": ("plomb", "plomberie", "toilette", "chasse", "sanitaire"),
    "toilette": ("plomb", "plomberie", "wc", "chasse", "sanitaire"),
    "chasse": ("plomb", "plomberie", "wc", "toilette"),
    "douche": ("plomb", "plomberie", "sanitaire", "chauffe-eau"),
    "chauffe": ("plomb", "plomberie", "electr", "climatisation"),
    "bouche": ("plomb", "plomberie", "debouchage", "sanitaire"),
    # Electricite (eclair)
    "courant": ("electr", "electricite", "electricien", "disjoncteur", "panne"),
    "disjoncteur": ("electr", "electricite", "tableau", "electricien"),
    "prise": ("electr", "electricite", "electricien", "interrupteur"),
    "interrupteur": ("electr", "electricite", "electricien"),
    "lumiere": ("electr", "electricite", "eclairage", "spot", "electricien"),
    "ampoule": ("electr", "electricite", "eclairage"),
    "cable": ("electr", "electricite", "electricien"),
    "court": ("electr", "electricite", "disjoncteur", "panne"),
    "saute": ("electr", "electricite", "disjoncteur"),
    # Froid & Climatisation (climatisation)
    "clim": ("climatisation", "froid", "split", "climatis"),
    "climatiseur": ("climatisation", "froid", "split"),
    "split": ("climatisation", "froid", "clim"),
    "froid": ("climatisation", "froid", "frigo", "refrigerateur"),
    "frigo": ("climatisation", "froid", "electromenager"),
    "refroidit": ("climatisation", "froid", "gaz", "recharge"),
    "gaz": ("climatisation", "froid", "recharge", "plomb"),
    # Serrurerie (cle)
    "serrure": ("serrur", "cle", "porte", "verrou"),
    "cle": ("serrur", "cle", "serrure", "ouverture"),
    "cadenas": ("serrur", "cle", "serrure"),
    "verrou": ("serrur", "cle", "serrure"),
    "coince": ("serrur", "menuis", "porte", "rabotage"),
    "bloquee": ("serrur", "menuis", "porte", "ouverture"),
    "bloque": ("serrur", "menuis", "porte", "plomb"),
    # Peinture (pinceau)
    "peindre": ("peint", "peinture", "ravalement", "enduit"),
    "mur": ("peint", "carrel", "macon", "enduit"),
    "plafond": ("peint", "electric", "etanche"),
    "fissure": ("peint", "enduit", "macon"),
    # Carrelage (carrelage)
    "carreau": ("carrel", "carrelage", "faience", "sol"),
    "carreaux": ("carrel", "carrelage", "faience", "sol"),
    "faience": ("carrel", "carrelage"),
    # Menuiserie (menuiserie)
    "porte": ("menuis", "serrur", "bois", "bloc"),
    "meuble": ("menuis", "bois", "placard", "ebeniste"),
    "placard": ("menuis", "bois", "ebeniste"),
    "bois": ("menuis", "menuiserie", "ebeniste"),
    "fenetre": ("menuis", "alu", "vitre"),
    # Menage (nettoyage)
    "menage": ("menage", "nettoy", "propre", "repassage"),
    "nettoyer": ("nettoy", "menage", "propre", "lavage"),
    "canape": ("nettoy", "menage", "lavage"),
    "tapis": ("nettoy", "menage", "lavage"),
    "vitre": ("nettoy", "menage", "lavage"),
    # Jardin / Auto / Cuisine fallback
    "jardin": ("jardin", "pelouse", "paysag", "elagage"),
    "pelouse": ("jardin", "tonte", "paysag"),
    "voiture": ("mecan", "auto", "garage", "frein"),
    "moteur": ("mecan", "auto", "panne"),
}

SLUG_TO_KEYWORDS: Dict[str, Tuple[str, ...]] = {
    "goutte": ("plomb", "fuite", "tuyau", "robinet", "evier", "wc", "toilette", "douche", "eau", "siphon", "chauffe"),
    "eclair": ("electr", "courant", "disjoncteur", "prise", "lumiere", "cable", "tableau", "interrupteur", "spot"),
    "climatisation": ("clim", "froid", "split", "gaz", "refroid"),
    "cle": ("serrur", "cle", "verrou", "cadenas", "blindee", "barillet"),
    "pinceau": ("peint", "enduit", "mur", "plafond", "facade", "ravalement"),
    "carrelage": ("carrel", "carreau", "faience", "joint", "chape"),
    "menuiserie": ("menuis", "bois", "placard", "porte", "meuble", "iroko", "rabot"),
    "nettoyage": ("menage", "nettoy", "propre", "lessivage", "canape", "tapis", "vitre", "chantier"),
    "nounou": ("nounou", "garde", "enfant", "baby", "nourrice", "bebe"),
    "soutien": ("soutien", "cours", "scolaire", "professeur", "repetiteur", "maths", "devoirs"),
    "electromenager": ("electromenager", "frigo", "refriger", "lave", "machine", "four", "congel"),
    "maconnerie": ("macon", "beton", "parpaing", "fissure", "dalle", "ciment"),
    "jardinage": ("jardin", "pelouse", "haie", "elagage", "tonte"),
    "cuisine": ("cuisin", "traiteur", "repas", "chef"),
    "demenagement": ("demenag", "carton", "manutent", "camion"),
    "beaute": ("coiff", "beaut", "tresse", "manucur", "maquill", "esthet"),
    "auto": ("mecan", "voiture", "vidange", "batterie", "frein"),
    "informatique": ("informati", "wifi", "ordinateur", "pc", "mac", "fibre", "reseau"),
}

SLUG_DEFAULT_INTERVENTION_BASELINE: Dict[str, Tuple[int, int, int, str]] = {
    # slug: (min_fcfa, median_fcfa, max_fcfa, conseil_abidjan)
    "goutte": (8000, 15000, 28000, "Inclut souvent diagnostic, petite fourniture et main-d'oeuvre courante."),
    "eclair": (8000, 16000, 32000, "Varie selon l'acces au tableau electrique et les composants a remplacer."),
    "climatisation": (12000, 22000, 45000, "Un entretien complet ou recharge gaz se situe generalement dans cette tranche."),
    "cle": (10000, 18000, 35000, "Depend du type de cylindre ou d'une ouverture simple vs serrure renforcee."),
    "pinceau": (15000, 35000, 85000, "Le cout depend de la surface en m2 et de la preparation du mur."),
    "carrelage": (15000, 35000, 75000, "Calcule selon la surface en m2, la colle et la decoupe des carreaux."),
    "menuiserie": (12000, 25000, 60000, "Ajustement/rabotage simple en bas de fourchette, fabrication ou bloc porte au-dessus."),
    "nettoyage": (10000, 20000, 45000, "Varie selon la surface du logement et le materiel d'aspiration requis."),
    "nounou": (8000, 15000, 95000, "Tarif adapte a la duree (soiree, journee, semaine ou forfait mensuel)."),
    "soutien": (6000, 15000, 70000, "Varie entre seance unitaire (2h) et pack mensuel d'accompagnement."),
    "electromenager": (10000, 22000, 50000, "Inclut diagnostic et petite piece ; compresseur/carte mere au-dessus."),
    "maconnerie": (15000, 40000, 120000, "Varie selon la surface, le ciment et la complexite du support."),
    "jardinage": (10000, 20000, 45000, "Varie selon la surface du jardin et l'evacuation des dechets verts."),
    "cuisine": (12000, 25000, 65000, "Depend du nombre de convives et de la prise en charge des courses."),
    "demenagement": (25000, 55000, 150000, "Varie selon le volume, l'etage et la distance entre communes."),
    "beaute": (8000, 15000, 35000, "Tarif a domicile selon la prestation et les produits fournis."),
    "auto": (10000, 22000, 55000, "Varie selon la vidange, le diagnostic ou les pieces de rechange."),
    "informatique": (10000, 18000, 40000, "Depannage logiciel/reseau en bas de fourchette, materiel en supplement."),
    "generique": (8000, 18000, 35000, "Fourchette indicative a Abidjan pour une intervention standard hors grosses pieces."),
}


def normalize_text(value: Any) -> str:
    """Normalise une chaine (minuscule, sans accents, espaces compacts)."""
    if not value:
        return ""
    raw = str(value).strip().lower()
    decomposed = unicodedata.normalize("NFKD", raw)
    stripped = "".join(ch for ch in decomposed if not unicodedata.combining(ch))
    cleaned = []
    for ch in stripped:
        if ch.isalnum() or ch in (" ", "-", "_"):
            cleaned.append(ch if ch not in ("-", "_") else " ")
    return " ".join("".join(cleaned).split())


def tokenize(value: Any) -> List[str]:
    norm = normalize_text(value)
    return [tok for tok in norm.split() if len(tok) >= 2]


def expand_query_tokens(query: str) -> List[str]:
    """Etend les tokens utilisateur avec des racines symptome/metier."""
    tokens = tokenize(query)
    expanded: List[str] = []
    seen = set()
    for tok in tokens:
        if tok not in seen:
            expanded.append(tok)
            seen.add(tok)
        for key, syns in SYMPTOM_SYNONYMS.items():
            if tok == key or tok.startswith(key) or (len(tok) >= 4 and key.startswith(tok)):
                for s in syns:
                    if s not in seen:
                        expanded.append(s)
                        seen.add(s)
    return expanded


def _fuzzy_token_score(token: str, target_tokens: List[str], full_target: str) -> float:
    """Retourne un score [0..1] de correspondance exacte, prefixe ou tolérante aux fautes."""
    if not token or not full_target:
        return 0.0
    if token in full_target:
        return 1.0
    best = 0.0
    tok_stem = token[:5] if len(token) >= 5 else token
    for tt in target_tokens:
        if tt.startswith(token) or token.startswith(tt):
            return 0.88
        if len(token) >= 4 and len(tt) >= 4:
            ratio = SequenceMatcher(None, token, tt).ratio()
            tt_stem = tt[:5] if len(tt) >= 5 else tt
            stem_ratio = SequenceMatcher(None, tok_stem, tt_stem).ratio()
            score = max(ratio, stem_ratio * 0.92 if len(token) >= 5 and len(tt) >= 5 else 0.0)
            if score >= 0.72 and score > best:
                best = score
    return best


def compute_provider_query_match(provider: Any, query: str) -> float:
    """
    Calcule un score de pertinence [0..100] entre une requete client
    (avec accents, fautes ou symptome libre) et un prestataire.
    """
    if not query or not query.strip():
        return 0.0

    raw_tokens = tokenize(query)
    if not raw_tokens:
        return 0.0
    expanded_tokens = expand_query_tokens(query)

    nom_n = normalize_text(getattr(provider, "nom", ""))
    spec_n = normalize_text(getattr(provider, "specialite", ""))
    ville_n = normalize_text(getattr(provider, "ville", ""))
    commune_n = normalize_text(getattr(provider, "commune_rattachement", ""))
    bio_n = normalize_text(getattr(provider, "bio", ""))
    cat_nom_n = normalize_text(
        getattr(getattr(provider, "category", None), "nom", "") if getattr(provider, "category_id", None) else ""
    )

    combined = f"{nom_n} {spec_n} {cat_nom_n} {ville_n} {commune_n} {bio_n}".strip()
    target_tokens = tokenize(combined)
    if not target_tokens:
        return 0.0

    # Score direct sur les tokens saisis par le client
    direct_hits = 0.0
    for tok in raw_tokens:
        s_nom = _fuzzy_token_score(tok, tokenize(nom_n), nom_n) * 1.15
        s_spec = _fuzzy_token_score(tok, tokenize(f"{spec_n} {cat_nom_n}"), f"{spec_n} {cat_nom_n}") * 1.10
        s_loc = _fuzzy_token_score(tok, tokenize(f"{ville_n} {commune_n}"), f"{ville_n} {commune_n}") * 1.0
        s_bio = _fuzzy_token_score(tok, tokenize(bio_n), bio_n) * 0.75
        best_tok = min(1.15, max(s_nom, s_spec, s_loc, s_bio))
        direct_hits += best_tok

    direct_ratio = direct_hits / max(1, len(raw_tokens))

    # Bonus symptome si l'utilisateur decrit la panne plutot que le nom du metier
    syn_hits = 0
    for syn in expanded_tokens:
        if syn in raw_tokens:
            continue
        if syn in combined:
            syn_hits += 1

    syn_bonus = min(0.65, syn_hits * 0.25)
    raw_score = min(100.0, (direct_ratio * 78.0) + (syn_bonus * 34.0))
    return round(raw_score, 2)


# ---------------------------------------------------------------------------
# Scoring composite prestataire + signaux operationnels en lot
# ---------------------------------------------------------------------------

class SmartProviderScorer:
    """Moteur de classement et d'explicabilite des prestataires BABIFIX."""

    BAYESIAN_PRIOR_MEAN = 4.2
    BAYESIAN_SMOOTHING_WEIGHT = 5.0

    @classmethod
    def bayesian_rating(cls, average_rating: Optional[float], rating_count: int) -> float:
        """
        Moyenne ponderee bayesienne : evite qu'un nouvel artisan avec 1 avis 5.0
        surclasse un artisan etabli avec 40 avis 4.8.
        """
        v = max(0, int(rating_count or 0))
        if v <= 0 or average_rating is None:
            return 3.85
        r = max(1.0, min(5.0, float(average_rating)))
        c = cls.BAYESIAN_SMOOTHING_WEIGHT
        m = cls.BAYESIAN_PRIOR_MEAN
        return round(((c * m) + (v * r)) / (c + v), 3)

    @classmethod
    def resolve_palier(cls, provider: Any) -> Tuple[str, str, float]:
        """Unifie artisan_tier (modele actif) et palier (legacy) sans ambiguite."""
        tier_raw = (
            getattr(provider, "artisan_tier", None)
            or getattr(provider, "palier", None)
            or "palier_1_proximite"
        )
        key = str(tier_raw).strip().lower()
        mapping = {
            "palier_3_entreprise": ("PALIER_3_ENTREPRISE", "Entreprise BTP agreee", 8.0),
            "palier_2_maitre": ("PALIER_2_MAITRE", "Maitre Artisan verifie", 6.0),
            "palier_1_proximite": ("PALIER_1_PROXIMITE", "Artisan terrain", 4.0),
        }
        return mapping.get(key, ("PALIER_1_PROXIMITE", "Artisan terrain", 4.0))

    @classmethod
    def collect_operational_metrics(cls, provider_ids: Iterable[int]) -> Dict[int, Dict[str, Any]]:
        """
        Recupere en 2 requetes groupees les signaux reels pour eviter tout N+1 :
        - nombre de chantiers actifs en cours (charge courante)
        - nombre de missions terminees (experience plateforme)
        - delai moyen de reponse au premier devis/action (minutes)
        """
        ids = [int(pid) for pid in provider_ids if pid]
        if not ids:
            return {}

        metrics: Dict[int, Dict[str, Any]] = {
            pid: {
                "active_jobs": 0,
                "completed_jobs": 0,
                "avg_response_min": None,
                "unavailable_today": False,
            }
            for pid in ids
        }

        try:
            from ..models import Devis, PrestataireUnavailability, Reservation

            today = timezone.localdate()
            unavails = set(
                PrestataireUnavailability.objects.filter(
                    provider_id__in=ids,
                    date_debut__lte=today,
                    date_fin__gte=today,
                ).values_list("provider_id", flat=True)
            )
            for pid in unavails:
                if pid in metrics:
                    metrics[pid]["unavailable_today"] = True

            active_statuses = [
                Reservation.Status.CONFIRMED,
                Reservation.Status.IN_PROGRESS,
                Reservation.Status.DEVIS_ACCEPTE,
                Reservation.Status.INTERVENTION_EN_COURS,
            ]
            done_statuses = [Reservation.Status.DONE, "DONE"]

            agg_rows = (
                Reservation.objects.filter(assigned_provider_id__in=ids)
                .values("assigned_provider_id")
                .annotate(
                    active_cnt=Count("id", filter=Q(statut__in=active_statuses)),
                    done_cnt=Count("id", filter=Q(statut__in=done_statuses)),
                )
            )
            for row in agg_rows:
                pid = row.get("assigned_provider_id")
                if pid in metrics:
                    metrics[pid]["active_jobs"] = int(row.get("active_cnt") or 0)
                    metrics[pid]["completed_jobs"] = int(row.get("done_cnt") or 0)

            recent_cutoff = timezone.now() - timedelta(days=90)
            devis_rows = (
                Devis.objects.filter(
                    prestataire_id__in=ids,
                    created_at__gte=recent_cutoff,
                )
                .exclude(statut=Devis.Statut.BROUILLON)
                .select_related("reservation")
                .values_list("prestataire_id", "created_at", "reservation__created_at")[:600]
            )
            per_provider_deltas: Dict[int, List[float]] = {}
            for pid, d_at, r_at in devis_rows:
                if d_at and r_at and d_at >= r_at:
                    diff_min = (d_at - r_at).total_seconds() / 60.0
                    if 0 <= diff_min <= 60 * 72:
                        per_provider_deltas.setdefault(pid, []).append(diff_min)

            for pid, deltas in per_provider_deltas.items():
                if deltas and pid in metrics:
                    metrics[pid]["avg_response_min"] = round(statistics.median(deltas), 1)
        except Exception as exc:
            logger.debug("SmartProviderScorer.collect_operational_metrics fallback: %s", exc)

        return metrics

    @classmethod
    def compute_profile(
        cls,
        provider: Any,
        distance_km: Optional[float] = None,
        metrics: Optional[Dict[str, Any]] = None,
        query_match_score: float = 0.0,
    ) -> Dict[str, Any]:
        """
        Calcule le profil de recommandation complet et deterministe d'un prestataire.
        """
        now = timezone.now()
        is_active_premium = False
        if getattr(provider, "is_premium", False):
            until = getattr(provider, "premium_until", None)
            if not until or until >= now:
                is_active_premium = True

        raw_tier = (getattr(provider, "premium_tier", "") or "").lower().strip()
        tier = raw_tier if (is_active_premium and raw_tier in ("gold", "silver")) else "standard"
        try:
            from .platform_config_service import get_dynamic_tier_configs
            _, _prem_cfgs = get_dynamic_tier_configs()
            _sil_pct = float(_prem_cfgs["silver"].get("visibility_boost_pct", 30) or 30)
            _gld_pct = float(_prem_cfgs["gold"].get("visibility_boost_pct", 60) or 60)
            _sil_badge = str(_prem_cfgs["silver"].get("badge", "Pro vérifié") or "Pro vérifié")
            _gld_badge = str(_prem_cfgs["gold"].get("badge", "Top") or "Top")
        except Exception:
            _sil_pct, _gld_pct = 30.0, 60.0
            _sil_badge, _gld_badge = "Pro vérifié", "Top"

        if tier == "gold":
            badge = _gld_badge if "verifie" not in _gld_badge.lower() else _gld_badge.replace("verifie", "vérifié")
            tier_rank = 2
            tier_score = round(16.0 * (_gld_pct / 60.0), 2)
            tier_radius_bonus = 5.0
        elif tier == "silver":
            badge = _sil_badge.replace("verifie", "vérifié")
            tier_rank = 1
            tier_score = round(9.0 * (_sil_pct / 30.0), 2)
            tier_radius_bonus = 3.0
        else:
            badge, tier_rank, tier_score, tier_radius_bonus = "", 0, 0.0, 0.0

        is_certified = bool(
            getattr(provider, "is_certified", False)
            or getattr(provider, "supervisor_verified_at", None)
            or getattr(provider, "supervisor_verified_by", "")
        )
        cert_score = 12.0 if is_certified else 0.0

        palier_code, palier_label, palier_score = cls.resolve_palier(provider)
        plafond_fcfa = int(getattr(provider, "plafond_intervention_fcfa", 100000) or 100000)

        rating_count = int(getattr(provider, "rating_count", 0) or 0)
        avg_rating = (
            round(float(provider.average_rating), 2)
            if (rating_count > 0 and getattr(provider, "average_rating", None) is not None)
            else 0.0
        )
        bayes = cls.bayesian_rating(avg_rating if rating_count > 0 else None, rating_count)
        rating_score = (bayes * 6.0) + min(12.0, math.log1p(rating_count) * 3.4)

        # Fiabilite REELLE depuis fiabilite_score (corrige l'ancien bug reliability_score)
        fiabilite_raw = getattr(provider, "fiabilite_score", None)
        fiabilite = float(fiabilite_raw if fiabilite_raw is not None else 100.0)
        if fiabilite >= 90.0:
            reliability_bonus = 8.0
        elif fiabilite >= 75.0:
            reliability_bonus = 3.0
        else:
            reliability_bonus = max(-22.0, (fiabilite - 75.0) * 0.65)

        m = metrics or {}
        active_jobs = int(m.get("active_jobs") or 0)
        completed_jobs = int(m.get("completed_jobs") or 0)
        avg_response_min = m.get("avg_response_min")
        unavailable_today = bool(m.get("unavailable_today"))

        workload_penalty = min(9.0, active_jobs * 2.5) + (14.0 if unavailable_today else 0.0)
        experience_bonus = min(8.0, math.log1p(completed_jobs) * 2.2)

        speed_bonus = 0.0
        if avg_response_min is not None:
            if avg_response_min <= 30:
                speed_bonus = 6.0
            elif avg_response_min <= 120:
                speed_bonus = 3.0

        if distance_km is not None:
            try:
                eff_dist = max(0.0, float(distance_km) - tier_radius_bonus)
                proximity_score = max(0.0, 26.0 - (eff_dist * 1.4))
            except (TypeError, ValueError):
                eff_dist = 9999.0
                proximity_score = 4.0
        else:
            eff_dist = 9999.0
            proximity_score = 4.0

        query_bonus = min(20.0, float(query_match_score or 0.0) * 0.20)

        elite_score = round(
            max(
                0.0,
                tier_score
                + cert_score
                + palier_score
                + rating_score
                + reliability_bonus
                + experience_bonus
                + speed_bonus
                + proximity_score
                + query_bonus
                - workload_penalty,
            ),
            2,
        )

        # Raisons lisibles cote client (max 3 tags concis sans jargon)
        reasons: List[str] = []
        if is_certified:
            reasons.append("Artisan certifie")
        if fiabilite >= 92.0 and (rating_count >= 3 or completed_jobs >= 2):
            reasons.append("Tres fiable")
        if avg_response_min is not None and avg_response_min <= 45:
            reasons.append("Reponse rapide")
        if distance_km is not None and float(distance_km) <= 4.0:
            reasons.append("Proche de vous")
        if rating_count >= 10 and avg_rating >= 4.6:
            reasons.append("Tres bien note")
        if completed_jobs >= 5:
            reasons.append(f"{completed_jobs} missions reussies")
        reasons = reasons[:3]

        return {
            "premium_tier": tier,
            "premium_badge": badge,
            "tier_rank": tier_rank,
            "is_certified": is_certified,
            "palier": palier_code,
            "palier_label": palier_label,
            "plafond_intervention_fcfa": plafond_fcfa,
            "average_rating": avg_rating if rating_count > 0 else None,
            "average_rating_num": avg_rating,
            "bayesian_rating": bayes,
            "rating_count": rating_count,
            "fiabilite_score": int(round(fiabilite)),
            "active_jobs": active_jobs,
            "completed_jobs": completed_jobs,
            "avg_response_min": avg_response_min,
            "effective_distance_km": eff_dist,
            "elite_score": elite_score,
            "trust_reasons": reasons,
        }


# ---------------------------------------------------------------------------
# Conseiller Prix Abidjan & Coherence Devis (SmartDevisAdvisor)
# ---------------------------------------------------------------------------

class SmartDevisAdvisor:
    """Fournit des fourchettes tarifaires reelles a Abidjan et des suggestions de lignes."""

    @classmethod
    def infer_slug(cls, category_id: Optional[int] = None, description: str = "") -> Tuple[str, str]:
        """Deduit la cle catalogue et le libelle metier sans modifier les Categories."""
        from ..models import Category
        from .catalogue_service import CatalogueService

        cat_name = "Intervention generale"
        if category_id:
            cat = Category.objects.filter(id=category_id).first()
            if cat:
                cat_name = cat.nom or cat_name
                slug = CatalogueService.get_slug_for_category(cat)
                if slug != "generique":
                    return slug, cat_name

        norm_desc = normalize_text(description)
        best_slug = "generique"
        best_hits = 0
        for slug, kws in SLUG_TO_KEYWORDS.items():
            hits = sum(1 for kw in kws if kw in norm_desc)
            if hits > best_hits:
                best_hits = hits
                best_slug = slug
        return best_slug, cat_name

    @classmethod
    def estimate_price_range(
        cls,
        category_id: Optional[int] = None,
        description: str = "",
        ville: str = "",
    ) -> Dict[str, Any]:
        """
        Estime une fourchette indicative FCFA (min, median, max) en combinant
        l'historique des devis acceptes/envoyes et le referentiel metier Abidjan.
        """
        from ..models import Devis
        from .catalogue_service import CATALOGUE_DATA, CatalogueService

        slug, cat_name = cls.infer_slug(category_id=category_id, description=description)
        base_min, base_med, base_max, base_tip = SLUG_DEFAULT_INTERVENTION_BASELINE.get(
            slug, SLUG_DEFAULT_INTERVENTION_BASELINE["generique"]
        )

        raw_items = (
            CatalogueService.get_catalogue_items(category_id)
            if category_id
            else [
                {"id": idx, **item}
                for idx, item in enumerate(CATALOGUE_DATA.get(slug, CATALOGUE_DATA["generique"]), start=1)
            ]
        )

        # Selectionne en priorite les lignes correspondant aux symptomes decrits
        desc_tokens = set(expand_query_tokens(description))
        scored_items: List[Tuple[int, Dict[str, Any]]] = []
        for item in raw_items:
            item_norm = normalize_text(item.get("nom", ""))
            score = sum(1 for t in desc_tokens if t in item_norm)
            scored_items.append((score, item))
        scored_items.sort(key=lambda pair: -pair[0])

        suggested_items = [pair[1] for pair in scored_items[:4]]

        # Calcule aussi une somme repere catalogue (1 MO pertinente + 1 fourniture + 1 deplacement)
        mo_prices = [int(i.get("prix", 0)) for _, i in scored_items if i.get("type_ligne") == "MAIN_OEUVRE" and i.get("prix")]
        fourn_prices = [int(i.get("prix", 0)) for _, i in scored_items if i.get("type_ligne") == "FOURNITURE" and i.get("prix")]
        dep_prices = [int(i.get("prix", 0)) for _, i in scored_items if i.get("type_ligne") == "DEPLACEMENT" and i.get("prix")]

        cat_ref_min = base_min
        cat_ref_max = base_max
        if mo_prices:
            mo_base = mo_prices[0]
            dep_base = dep_prices[0] if dep_prices else 3000
            fourn_base = fourn_prices[0] if fourn_prices else 0
            cat_ref_min = max(5000, int(round((mo_base + dep_base) / 500.0) * 500))
            cat_ref_max = max(cat_ref_min + 5000, int(round((mo_base + fourn_base + dep_base) * 1.45 / 500.0) * 500))

        # Croise avec les devis fermes reels de la plateforme
        hist_totals: List[float] = []
        try:
            qs = (
                Devis.objects.filter(
                    est_estimation=False,
                    statut__in=[Devis.Statut.ENVOYE, Devis.Statut.ACCEPTE],
                    total_ttc__gt=1000,
                )
                .select_related("reservation__assigned_provider")
                .order_by("-created_at")
            )
            if category_id:
                qs = qs.filter(reservation__assigned_provider__category_id=category_id)
            elif slug != "generique":
                kws = SLUG_TO_KEYWORDS.get(slug, ())
                q_obj = Q()
                for kw in kws[:5]:
                    q_obj |= Q(reservation__title__icontains=kw) | Q(diagnostic__icontains=kw)
                if q_obj:
                    qs = qs.filter(q_obj)

            hist_totals = [float(v) for v in qs.values_list("total_ttc", flat=True)[:60] if v]
        except Exception as exc:
            logger.debug("estimate_price_range historical query skipped: %s", exc)

        sample_count = len(hist_totals)
        if sample_count >= 5:
            hist_sorted = sorted(hist_totals)
            q25 = hist_sorted[max(0, int(len(hist_sorted) * 0.25))]
            q50 = statistics.median(hist_sorted)
            q75 = hist_sorted[min(len(hist_sorted) - 1, int(len(hist_sorted) * 0.75))]
            # Lissage 65% historique + 35% referentiel catalogue pour eviter les derives
            est_min = int(round((q25 * 0.65 + cat_ref_min * 0.35) / 500.0) * 500)
            est_med = int(round((q50 * 0.65 + ((cat_ref_min + cat_ref_max) / 2.0) * 0.35) / 500.0) * 500)
            est_max = int(round((q75 * 0.65 + cat_ref_max * 0.35) / 500.0) * 500)
            confidence = "haute"
        elif sample_count >= 2:
            q50 = statistics.median(hist_totals)
            est_min = int(round((min(hist_totals) * 0.4 + cat_ref_min * 0.6) / 500.0) * 500)
            est_med = int(round((q50 * 0.4 + base_med * 0.6) / 500.0) * 500)
            est_max = int(round((max(hist_totals) * 0.4 + cat_ref_max * 0.6) / 500.0) * 500)
            confidence = "moyenne"
        else:
            est_min = min(base_min, cat_ref_min)
            est_med = base_med
            est_max = max(base_max, cat_ref_max)
            confidence = "indicative"

        est_min = max(3000, est_min)
        est_med = max(est_min, est_med)
        est_max = max(est_med + 2000, est_max)

        return {
            "slug": slug,
            "category_name": cat_name,
            "min_fcfa": est_min,
            "median_fcfa": est_med,
            "max_fcfa": est_max,
            "confidence": confidence,
            "sample_count": sample_count,
            "ville_context": ville or "Abidjan",
            "tip": base_tip,
            "suggested_items": suggested_items,
        }

    @classmethod
    def check_devis_coherence(
        cls,
        total_ttc: float,
        category_id: Optional[int] = None,
        description: str = "",
        est_estimation: bool = False,
        plafond_fcfa: Optional[float] = None,
    ) -> Dict[str, Any]:
        """
        Verifie de facon purement informative si le montant d'un devis semble
        coherant avec les references Abidjan et le plafond de l'artisan.
        """
        bench = cls.estimate_price_range(category_id=category_id, description=description)
        amount = float(total_ttc or 0)
        if amount <= 0:
            return {
                "is_anomaly": False,
                "severity": "ok",
                "message": "",
                "benchmark": bench,
            }

        if plafond_fcfa and float(plafond_fcfa) > 0 and amount > float(plafond_fcfa) and not est_estimation:
            return {
                "is_anomaly": True,
                "severity": "warning",
                "exceeds_ceiling": True,
                "escrow_required": True,
                "price_vigilance": amount > bench["median_fcfa"] * 2.0,
                "message": (
                    f"Ce montant ({int(amount):,} FCFA) depasse votre plafond "
                    f"d'intervention actuel ({int(plafond_fcfa):,} FCFA). "
                    "Le devis reste autorise avec paiement 100 % Mobile Money sous sequestre obligatoire."
                ).replace(",", " "),
                "benchmark": bench,
            }

        if amount < bench["min_fcfa"] * 0.45:
            return {
                "is_anomaly": True,
                "severity": "info",
                "exceeds_ceiling": False,
                "escrow_required": False,
                "price_vigilance": False,
                "message": (
                    f"Tarif nettement inferieur aux constats habituels a Abidjan "
                    f"({bench['min_fcfa']:,} - {bench['max_fcfa']:,} FCFA). "
                    "Verifiez si le deplacement et les pieces sont bien comptes."
                ).replace(",", " "),
                "benchmark": bench,
            }

        if amount > bench["max_fcfa"] * 2.4 or (amount >= 30000 and amount > bench["median_fcfa"] * 2.0):
            return {
                "is_anomaly": True,
                "severity": "warning",
                "exceeds_ceiling": False,
                "escrow_required": False,
                "price_vigilance": True,
                "message": (
                    f"Montant eleve par rapport aux interventions similaires "
                    f"({bench['min_fcfa']:,} - {bench['max_fcfa']:,} FCFA). "
                    "Detaillez les lignes (main-d'oeuvre + pieces/details) pour rassurer le client."
                ).replace(",", " "),
                "benchmark": bench,
            }

        return {
            "is_anomaly": False,
            "severity": "ok",
            "exceeds_ceiling": False,
            "escrow_required": False,
            "price_vigilance": False,
            "message": "",
            "benchmark": bench,
        }


# ---------------------------------------------------------------------------
# Progression au Merite : Palier 1 -> Palier 2 Maitre (500 000 FCFA gratuit)
# ---------------------------------------------------------------------------

MERIT_TIER2_REQUIRED_JOBS = 10
MERIT_TIER2_REQUIRED_RATING = 4.5
MERIT_TIER2_PLAFOND_FCFA = 500000


def get_merit_progress(provider) -> Dict[str, Any]:
    """Calcule la progression d'un prestataire vers le Niveau 2 au merite."""
    from ..models import Dispute, Reservation

    completed_jobs = Reservation.objects.filter(
        assigned_provider=provider,
        statut__in=["Terminee", "DONE"],
    ).count()
    open_or_lost_disputes = Dispute.objects.filter(
        reservation__assigned_provider=provider,
        decision__in=[Dispute.Decision.OPEN, Dispute.Decision.REFUND],
    ).count()
    avg_rating = float(getattr(provider, "average_rating", 0) or 0)
    tier = getattr(provider, "artisan_tier", "palier_1_proximite") or "palier_1_proximite"
    eligible = (
        tier == "palier_1_proximite"
        and completed_jobs >= MERIT_TIER2_REQUIRED_JOBS
        and avg_rating >= MERIT_TIER2_REQUIRED_RATING
        and open_or_lost_disputes == 0
    )
    return {
        "current_tier": tier,
        "plafond_fcfa": float(getattr(provider, "plafond_intervention_fcfa", 100000) or 100000),
        "completed_jobs": completed_jobs,
        "required_jobs": MERIT_TIER2_REQUIRED_JOBS,
        "average_rating": round(avg_rating, 2),
        "required_rating": MERIT_TIER2_REQUIRED_RATING,
        "open_or_lost_disputes": open_or_lost_disputes,
        "eligible_for_tier2": eligible,
        "already_tier2_or_higher": tier in ("palier_2_maitre", "palier_3_entreprise"),
    }


def check_and_apply_merit_upgrade(provider) -> bool:
    """Passe automatiquement un prestataire Palier 1 au Palier 2 (500 000 FCFA)
    des 10 missions terminees >= 4.5/5 sans litige ouvert ni perdu."""
    if not provider:
        return False
    progress = get_merit_progress(provider)
    if not progress["eligible_for_tier2"]:
        return False
    try:
        from decimal import Decimal
        from ..push_dispatch import _schedule

        provider.artisan_tier = "palier_2_maitre"
        provider.plafond_intervention_fcfa = Decimal(str(MERIT_TIER2_PLAFOND_FCFA))
        provider.save(update_fields=["artisan_tier", "plafond_intervention_fcfa"])
        if provider.user_id:
            _schedule(
                [provider.user_id],
                "Felicitations : Statut Niveau 2 debloque !",
                (
                    "Grace a vos 10 missions reussies et votre note >= 4,5/5, "
                    "votre plafond d'intervention passe gratuitement a 500 000 FCFA."
                ),
                {"type": "provider.tier_upgraded", "tier": "palier_2_maitre"},
            )
        return True
    except Exception as exc:
        logger.warning("check_and_apply_merit_upgrade failed for provider %s: %s", getattr(provider, "pk", None), exc)
        return False


# ---------------------------------------------------------------------------
# Radar Executif des Risques Admin (AdminRiskRadar - Staff Uniquement)
# ---------------------------------------------------------------------------

class AdminRiskRadar:
    """Agrege les alertes intelligentes de pilotage pour l'administration uniquement."""

    @classmethod
    def build_summary(cls) -> Dict[str, Any]:
        alerts: List[Dict[str, Any]] = []
        now = timezone.now()

        try:
            from ..models import Devis, Dispute, Provider, Reservation

            # 1. Demandes clients sans reponse depuis > 2 heures
            stale_cutoff = now - timedelta(hours=2)
            stale_count = Reservation.objects.filter(
                statut=Reservation.Status.DEMANDE_ENVOYEE,
                created_at__lt=stale_cutoff,
            ).count()
            if stale_count > 0:
                alerts.append({
                    "level": "high" if stale_count >= 5 else "medium",
                    "code": "stale_requests",
                    "title": f"{stale_count} demande(s) sans reponse (> 2h)",
                    "detail": "Risque de perte client : relancer ou reaffecter un artisan disponible.",
                    "section": "reservations",
                    "count": stale_count,
                })

            # 2. Prestataires actifs dont la fiabilite passe sous 70/100
            low_rel_qs = Provider.objects.filter(
                statut=Provider.Status.VALID,
                is_deleted=False,
                fiabilite_score__lt=70,
            )
            low_rel_count = low_rel_qs.count()
            if low_rel_count > 0:
                names = ", ".join(low_rel_qs.values_list("nom", flat=True)[:3])
                alerts.append({
                    "level": "high",
                    "code": "low_reliability_providers",
                    "title": f"{low_rel_count} prestataire(s) a fiabilite critique (< 70)",
                    "detail": f"Verification superviseur conseillee : {names}.",
                    "section": "prestataires",
                    "count": low_rel_count,
                })

            # 3. Litiges actifs a arbitrer rapidement
            open_disputes = Dispute.objects.filter(
                decision=Dispute.Decision.OPEN
            ).count()
            if open_disputes > 0:
                alerts.append({
                    "level": "high" if open_disputes >= 3 else "medium",
                    "code": "open_disputes",
                    "title": f"{open_disputes} litige(s) en attente d'arbitrage",
                    "detail": "Fonds potentiellement bloques en sequestre jusqu'a resolution.",
                    "section": "litiges",
                    "count": open_disputes,
                })

            # 4. Devis recents atypiques (montants tres eleves sur 14 jours)
            recent_devis = (
                Devis.objects.filter(
                    est_estimation=False,
                    statut=Devis.Statut.ENVOYE,
                    created_at__gte=now - timedelta(days=14),
                    total_ttc__gte=250000,
                )
                .select_related("prestataire", "reservation")
                .order_by("-total_ttc")[:10]
            )
            outlier_count = 0
            for d in recent_devis:
                cat_id = d.prestataire.category_id if d.prestataire_id else None
                check = SmartDevisAdvisor.check_devis_coherence(
                    total_ttc=float(d.total_ttc or 0),
                    category_id=cat_id,
                    description=d.diagnostic or "",
                    plafond_fcfa=float(getattr(d.prestataire, "plafond_intervention_fcfa", 0) or 0),
                )
                if check["is_anomaly"] and check["severity"] == "warning":
                    outlier_count += 1
            if outlier_count > 0:
                alerts.append({
                    "level": "medium",
                    "code": "outlier_devis",
                    "title": f"{outlier_count} devis recent(s) hors norme ou hors plafond",
                    "detail": "Montant superieur au plafond artisan ou a la fourchette constatee.",
                    "section": "reservations",
                    "count": outlier_count,
                })
        except Exception as exc:
            logger.warning("AdminRiskRadar.build_summary degraded: %s", exc)

        high_cnt = sum(1 for a in alerts if a["level"] == "high")
        med_cnt = sum(1 for a in alerts if a["level"] == "medium")
        health_score = max(40, 100 - (high_cnt * 15) - (med_cnt * 6))

        return {
            "alerts": alerts,
            "alerts_count": len(alerts),
            "high_count": high_cnt,
            "health_score": health_score,
        }
