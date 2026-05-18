"""GeoMatchingService — tri et filtrage géographique adaptatif (proximité).

Logique métier validée par le porteur de projet :

1. **Rayon adaptatif** : 5 km → 15 → 30 → 50. On commence serré ; si on a
   moins de `min_results` prestataires, on élargit. Garantit qu'on
   trouve toujours quelqu'un, mais privilégie la proximité.

2. **Boost "même ville"** : un prestataire dont `ville` (insensible à
   la casse) matche celle du client passe devant un prestataire à
   distance comparable mais dans une autre ville.

3. **Fallback sans GPS** : si le client n'a pas fourni `lat/lon`, on
   utilise sa ville (profil ou paramètre `client_city`) comme seul
   critère géo. Les prestataires de cette ville passent en premier.

4. **Aucun prestataire sans coordonnées n'est exclu** : ils sont relégués
   en fin de liste, sans rayon dur, pour ne pas vider l'écran si la
   base n'a pas de géocodage complet.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Iterable, Optional


# Rayon par défaut + paliers d'élargissement adaptatif (en km)
ADAPTIVE_RADII_KM = [5, 15, 30, 50]
MIN_RESULTS_FOR_TIGHT_RADIUS = 3


@dataclass
class GeoCandidate:
    """Wrapper léger autour d'un Provider, enrichi de la distance + score."""

    provider: object
    distance_km: Optional[float]
    same_city: bool
    score: float

    def to_dict_extra(self) -> dict:
        """Champs additionnels à mélanger dans la réponse JSON."""
        return {
            "distance_km": round(self.distance_km, 2) if self.distance_km is not None else None,
            "same_city": self.same_city,
            "geo_score": round(self.score, 3),
        }


def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Distance entre deux points GPS (formule Haversine, en km)."""
    R = 6371.0
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = (
        math.sin(dlat / 2) ** 2
        + math.cos(math.radians(lat1))
        * math.cos(math.radians(lat2))
        * math.sin(dlon / 2) ** 2
    )
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def _normalize_city(city: str | None) -> str:
    if not city:
        return ""
    return (
        city.lower()
        .strip()
        .replace("'", "")
        .replace("é", "e")
        .replace("è", "e")
        .replace("ê", "e")
        .replace("ô", "o")
        .replace("à", "a")
        .replace("â", "a")
        .replace("î", "i")
        .replace("-", " ")
    )


def _score(distance_km: Optional[float], same_city: bool,
           base_rating: float, radius_cap_km: float) -> float:
    """Score composite : proximité (60%) + ville (25%) + note (15%).

    Retourne une valeur dans [0, 1]. Plus haut = meilleur match.
    """
    # Proximité : 1.0 à 0 km, 0.0 au rayon cap, linéaire
    if distance_km is None:
        proximity = 0.1  # pénalité pour absence de GPS, mais pas exclu
    elif distance_km <= 0:
        proximity = 1.0
    elif distance_km >= radius_cap_km:
        proximity = 0.0
    else:
        proximity = max(0.0, 1.0 - (distance_km / radius_cap_km))

    city_bonus = 1.0 if same_city else 0.0

    # Note normalisée 0..1 (5 étoiles max)
    rating_norm = max(0.0, min(1.0, float(base_rating or 0) / 5.0))

    return 0.60 * proximity + 0.25 * city_bonus + 0.15 * rating_norm


def rank_providers(
    providers: Iterable,
    *,
    client_lat: Optional[float] = None,
    client_lon: Optional[float] = None,
    client_city: Optional[str] = None,
    explicit_radius_km: Optional[float] = None,
    min_results: int = MIN_RESULTS_FOR_TIGHT_RADIUS,
) -> list[GeoCandidate]:
    """Trie une liste de Providers selon la proximité du client.

    - Si `client_lat`/`client_lon` fournis : calcule distance Haversine
      et applique le rayon adaptatif (sauf si `explicit_radius_km` est
      passé, auquel cas on l'utilise tel quel).
    - Si pas de coordonnées mais `client_city` : boost ville uniquement,
      pas de distance.
    - Si rien : tri par note descendante (fallback total).

    Retourne une liste de GeoCandidate ordonnée du plus pertinent au
    moins pertinent.
    """
    providers = list(providers)
    norm_client_city = _normalize_city(client_city)
    has_gps = client_lat is not None and client_lon is not None

    # Première passe : calcul distance + same_city
    candidates: list[GeoCandidate] = []
    for p in providers:
        d = None
        if has_gps and getattr(p, "latitude", None) and getattr(p, "longitude", None):
            try:
                d = haversine_km(
                    float(client_lat), float(client_lon),
                    float(p.latitude), float(p.longitude),
                )
            except (TypeError, ValueError):
                d = None
        same_city = bool(
            norm_client_city
            and _normalize_city(getattr(p, "ville", "")) == norm_client_city
        )
        candidates.append(GeoCandidate(
            provider=p,
            distance_km=d,
            same_city=same_city,
            score=0.0,  # rempli plus bas
        ))

    # Sans aucun critère géo → tri par note pur
    if not has_gps and not norm_client_city:
        candidates.sort(
            key=lambda c: (
                -float(getattr(c.provider, "average_rating", 0) or 0),
                -int(getattr(c.provider, "rating_count", 0) or 0),
            )
        )
        for c in candidates:
            c.score = 0.15 * (float(getattr(c.provider, "average_rating", 0) or 0) / 5.0)
        return candidates

    # Rayon adaptatif : on essaye d'abord 5 km, puis 15, 30, 50.
    radii = (
        [explicit_radius_km] if explicit_radius_km else list(ADAPTIVE_RADII_KM)
    )
    chosen_radius = radii[-1]  # par défaut le plus large

    if has_gps:
        for r in radii:
            in_radius = [
                c for c in candidates
                if c.distance_km is not None and c.distance_km <= r
            ]
            if len(in_radius) >= min_results:
                chosen_radius = r
                break

    # Calcul du score avec le rayon retenu + boost premium par tier.
    # Bronze x1.10, Silver x1.30, Gold x1.60 — ne dépasse jamais 1.0
    # (clamp pour garder la métrique 0..1).
    _PREMIUM_BOOST = {"bronze": 1.10, "silver": 1.30, "gold": 1.60}
    for c in candidates:
        base_score = _score(
            c.distance_km,
            c.same_city,
            float(getattr(c.provider, "average_rating", 0) or 0),
            chosen_radius if has_gps else max(ADAPTIVE_RADII_KM),
        )
        tier = (getattr(c.provider, "premium_tier", "") or "").lower()
        is_premium = bool(getattr(c.provider, "is_premium", False))
        boost = _PREMIUM_BOOST.get(tier, 1.0) if is_premium else 1.0
        c.score = min(1.0, base_score * boost)

    # Tri final : score desc → ville même desc → note desc
    candidates.sort(
        key=lambda c: (
            -c.score,
            -1 if c.same_city else 0,
            -float(getattr(c.provider, "average_rating", 0) or 0),
        )
    )
    return candidates
