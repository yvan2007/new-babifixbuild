"""
Matching Service : algorithme de scoring unifie pour la recommandation et le dispatch
de prestataires BABIFIX.

Criteres reels pris en compte :
1. Proximite GPS Haversine (avec rayon adaptatif 5 -> 15 -> 30 -> 50 km) ou ville normalisee
2. Disponibilite reelle : flag `disponible` + creneaux `PrestataireAvailabilitySlot` + absences `PrestataireUnavailability`
3. Qualite bayesienne (`average_rating`, `rating_count`) + certification superviseur
4. Fiabilite operationnelle (`fiabilite_score`), charge en cours (`active_jobs`), experience et rapidite de reponse
5. Pertinence metier / symptomes (`compute_provider_query_match`) et adequation budget (`price_max`)
6. Boost abonnement verifie et non expire (`Standard 1.0`, `Silver 1.3`, `Gold 1.6`)
"""

from __future__ import annotations

import logging
import math
from dataclasses import dataclass, field
from datetime import datetime
from typing import Optional

from django.db.models import Q
from django.utils import timezone

from ..models import (
    PlatformConfig,
    PrestataireAvailabilitySlot,
    PrestataireUnavailability,
    Provider,
    Reservation,
)
from .geo_matching_service import ADAPTIVE_RADII_KM, _normalize_city, haversine_km
from .intelligence_service import SmartProviderScorer, compute_provider_query_match

logger = logging.getLogger(__name__)


@dataclass
class MatchingCriteria:
    """Criteres de recherche et de scoring d'un prestataire."""

    category_id: Optional[int] = None
    query: str = ""
    lat: Optional[float] = None
    lon: Optional[float] = None
    client_city: str = ""
    radius_km: Optional[float] = 50.0
    adaptive_radius: bool = True
    price_max: Optional[float] = None
    target_dt: Optional[datetime] = None
    required_skills: list = field(default_factory=list)
    only_available: bool = True


@dataclass
class ProviderScore:
    """Resultat complet et explicable du matching pour un prestataire."""

    provider: Provider
    score: float
    distance_km: Optional[float]
    reasons: list
    same_city: bool = False
    availability_score: float = 1.0
    tier: str = "standard"
    commission_pct: int = 18
    breakdown: dict = field(default_factory=dict)


class MatchingService:
    """Moteur central de recommandation et d'affectation intelligente."""

    WEIGHT_PROXIMITY = 0.28
    WEIGHT_RATING = 0.24
    WEIGHT_AVAILABILITY = 0.20
    WEIGHT_RELIABILITY = 0.16
    WEIGHT_PRICE = 0.12

    @classmethod
    def recommend_providers(
        cls,
        criteria: MatchingCriteria,
        limit: int = 10,
    ) -> list[ProviderScore]:
        """Recommande les meilleurs prestataires selon les criteres reels."""
        qs = Provider.objects.filter(
            statut=Provider.Status.VALID,
            is_deleted=False,
        ).select_related("category", "user")

        if criteria.only_available:
            qs = qs.filter(disponible=True)

        if criteria.category_id:
            qs = qs.filter(category_id=criteria.category_id)

        providers = list(qs)
        if not providers:
            return []

        query_text = (criteria.query or "").strip()
        if not query_text and criteria.required_skills:
            query_text = " ".join(str(s) for s in criteria.required_skills if s)

        q_scores = {}
        if query_text:
            matched = []
            for p in providers:
                qm = compute_provider_query_match(p, query_text)
                if qm >= 18.0 or not criteria.category_id:
                    matched.append((p, qm))
            if matched:
                # Si une categorie est deja strictement filtree et rien ne depasse 18,
                # on garde la liste categorie mais on applique le bonus texte.
                above = [(p, qm) for p, qm in matched if qm >= 18.0]
                if above:
                    providers = [p for p, _ in above]
                    q_scores = {p.id: qm for p, qm in above}
                else:
                    q_scores = {p.id: qm for p, qm in matched}

        provider_ids = [p.id for p in providers]
        metrics_map = SmartProviderScorer.collect_operational_metrics(provider_ids)
        target_dt = criteria.target_dt or timezone.localtime()
        avail_map = cls._collect_availability_map(provider_ids, target_dt)

        cfg = PlatformConfig.get_solo()
        gating_active = bool(getattr(cfg, "fiabilite_gating_actif", False))
        gating_threshold = int(getattr(cfg, "fiabilite_seuil", 40) or 40)

        has_gps = criteria.lat is not None and criteria.lon is not None
        norm_city = _normalize_city(criteria.client_city)

        # Calcul initial des distances
        pre_items = []
        for p in providers:
            dist = None
            if has_gps and p.latitude is not None and p.longitude is not None:
                try:
                    dist = haversine_km(
                        float(criteria.lat),
                        float(criteria.lon),
                        float(p.latitude),
                        float(p.longitude),
                    )
                except (TypeError, ValueError):
                    dist = None
            same_city = bool(norm_city and _normalize_city(p.ville) == norm_city)
            pre_items.append((p, dist, same_city))

        # Rayon adaptatif : 5 -> 15 -> 30 -> 50 km
        effective_radius = float(criteria.radius_km or ADAPTIVE_RADII_KM[-1])
        if has_gps and criteria.adaptive_radius:
            effective_radius = float(ADAPTIVE_RADII_KM[-1])
            for step in ADAPTIVE_RADII_KM:
                in_step = [
                    it for it in pre_items if it[1] is not None and it[1] <= step
                ]
                if len(in_step) >= min(3, limit):
                    effective_radius = float(step)
                    break

        scored: list[ProviderScore] = []
        for p, dist, same_city in pre_items:
            if (
                has_gps
                and dist is not None
                and not criteria.adaptive_radius
                and criteria.radius_km is not None
                and dist > float(criteria.radius_km)
            ):
                continue

            avail_info = avail_map.get(p.id, {})
            score_avail = cls._score_availability(p, avail_info)
            # Exclure les indisponibles complets si filtre actif
            if criteria.only_available and avail_info.get("is_unavailable_on_date"):
                continue

            score_prox = cls._calculate_proximity_score(dist, effective_radius, same_city)
            score_rating = cls._calculate_rating_score(p)
            score_rel = cls._calculate_reliability_score(p, metrics_map.get(p.id), gating_active, gating_threshold)
            score_price = cls._calculate_price_score(p, criteria.price_max)

            base_01 = (
                score_prox * cls.WEIGHT_PROXIMITY
                + score_rating * cls.WEIGHT_RATING
                + score_avail * cls.WEIGHT_AVAILABILITY
                + score_rel * cls.WEIGHT_RELIABILITY
                + score_price * cls.WEIGHT_PRICE
            )
            query_bonus_01 = min(0.18, float(q_scores.get(p.id, 0.0)) / 500.0)
            boost = cls._premium_boost(p)
            tier = cls._resolved_tier(p)
            commission_pct = 8 if tier == "gold" else (13 if tier == "silver" else 18)

            final_score = round((base_01 + query_bonus_01) * boost * 100.0, 2)

            reasons = cls._build_reasons(
                p=p,
                dist=dist,
                same_city=same_city,
                avail_info=avail_info,
                metrics=metrics_map.get(p.id) or {},
                price_max=criteria.price_max,
                tier=tier,
            )

            breakdown = {
                "proximity": round(score_prox * 100),
                "rating": round(score_rating * 100),
                "availability": round(score_avail * 100),
                "reliability": round(score_rel * 100),
                "price_fit": round(score_price * 100),
                "query_bonus": round(query_bonus_01 * 100, 1),
                "premium_multiplier": boost,
                "active_jobs": int((metrics_map.get(p.id) or {}).get("active_jobs") or 0),
                "completed_jobs": int((metrics_map.get(p.id) or {}).get("completed_jobs") or 0),
                "avg_response_min": (metrics_map.get(p.id) or {}).get("avg_response_min"),
                "effective_radius_km": effective_radius if has_gps else None,
            }

            scored.append(
                ProviderScore(
                    provider=p,
                    score=final_score,
                    distance_km=round(dist, 2) if dist is not None else None,
                    reasons=reasons,
                    same_city=same_city,
                    availability_score=round(score_avail, 2),
                    tier=tier,
                    commission_pct=commission_pct,
                    breakdown=breakdown,
                )
            )

        scored.sort(
            key=lambda x: (
                -x.score,
                -1 if x.same_city else 0,
                x.distance_km if x.distance_km is not None else 9999.0,
            )
        )
        return scored[:limit]

    @classmethod
    def recommend_for_reservation(
        cls,
        reservation: Reservation,
        limit: int = 5,
    ) -> list[ProviderScore]:
        """Recommande les meilleurs artisans pour une reservation donnee (dispatch admin ou client)."""
        q_text = " ".join(
            part
            for part in [
                getattr(reservation, "title", "") or "",
                getattr(reservation, "description_probleme", "") or "",
            ]
            if part
        ).strip()

        cat_id = None
        if reservation.assigned_provider_id and getattr(reservation.assigned_provider, "category_id", None):
            cat_id = reservation.assigned_provider.category_id

        price_max = None
        for val in (getattr(reservation, "prix_propose", None), getattr(reservation, "montant", None)):
            try:
                amt = float(val or 0)
                if amt > 0:
                    price_max = amt
                    break
            except (TypeError, ValueError):
                pass

        target_dt = timezone.localtime()
        city = (
            getattr(reservation, "address_quartier", "")
            or getattr(reservation, "address_ville", "")
            or ""
        )
        criteria = MatchingCriteria(
            category_id=cat_id,
            query=q_text,
            lat=getattr(reservation, "latitude", None),
            lon=getattr(reservation, "longitude", None),
            client_city=city,
            adaptive_radius=True,
            price_max=price_max,
            target_dt=target_dt,
            only_available=True,
        )
        results = cls.recommend_providers(criteria, limit=limit)
        if getattr(reservation, "is_urgent", False) and results:
            # En urgence, la proximite immediate (<10km) et la reactivite priment encore davantage
            results.sort(
                key=lambda x: (
                    0 if (x.distance_km is not None and x.distance_km <= 8.0) else 1,
                    -x.score,
                )
            )
        if not results and cat_id:
            # Elargir sans filtre categorie stricte si aucun prestataire libre dans la categorie
            criteria.category_id = None
            results = cls.recommend_providers(criteria, limit=limit)
        return results

    @classmethod
    def _collect_availability_map(cls, provider_ids: list[int], target_dt: datetime) -> dict[int, dict]:
        """Charge en 2 requetes les creneaux et indisponibilites reels."""
        info: dict[int, dict] = {
            pid: {
                "is_unavailable_on_date": False,
                "has_slots": False,
                "matches_time_slot": False,
                "matches_day": False,
            }
            for pid in provider_ids
        }
        if not provider_ids:
            return info

        target_date = target_dt.date() if isinstance(target_dt, datetime) else target_dt
        weekday = target_date.weekday()
        target_time = target_dt.time() if isinstance(target_dt, datetime) else None

        unavails = set(
            PrestataireUnavailability.objects.filter(
                provider_id__in=provider_ids,
                date_debut__lte=target_date,
                date_fin__gte=target_date,
            ).values_list("provider_id", flat=True)
        )
        for pid in unavails:
            if pid in info:
                info[pid]["is_unavailable_on_date"] = True

        slots = PrestataireAvailabilitySlot.objects.filter(
            provider_id__in=provider_ids,
            actif=True,
        ).values_list("provider_id", "jour_semaine", "heure_debut", "heure_fin")

        for pid, jour, h_deb, h_fin in slots:
            if pid not in info:
                continue
            info[pid]["has_slots"] = True
            if jour == weekday:
                info[pid]["matches_day"] = True
                if target_time and h_deb <= target_time <= h_fin:
                    info[pid]["matches_time_slot"] = True

        return info

    @classmethod
    def _score_availability(cls, provider: Provider, avail_info: dict) -> float:
        if avail_info.get("is_unavailable_on_date"):
            return 0.10
        if not provider.disponible:
            return 0.05
        if avail_info.get("has_slots"):
            if avail_info.get("matches_time_slot"):
                return 1.0
            if avail_info.get("matches_day"):
                return 0.80
            return 0.55
        return 0.90 if provider.disponible else 0.05

    @classmethod
    def _calculate_proximity_score(
        cls,
        distance_km: Optional[float],
        radius_km: float,
        same_city: bool = False,
    ) -> float:
        city_boost = 0.15 if same_city else 0.0
        if distance_km is None:
            return min(1.0, 0.35 + (0.45 if same_city else 0.0))
        if distance_km <= 2.0:
            base = 1.0
        elif distance_km <= 5.0:
            base = 0.88
        elif distance_km <= 10.0:
            base = 0.72
        else:
            cap = max(10.0, float(radius_km or 50.0))
            base = max(0.05, 1.0 - (distance_km / cap))
        return min(1.0, base + city_boost)

    @classmethod
    def _resolved_tier(cls, provider: Provider) -> str:
        if not getattr(provider, "is_premium", False):
            return "standard"
        until = getattr(provider, "premium_until", None)
        if until and until < timezone.now():
            return "standard"
        tier = (getattr(provider, "premium_tier", "") or "").lower().strip()
        return tier if tier in ("silver", "gold") else "standard"

    @classmethod
    def _premium_boost(cls, provider: Provider) -> float:
        try:
            from .provider_subscription_service import ProviderSubscriptionService

            return float(ProviderSubscriptionService.visibility_multiplier(provider))
        except Exception:
            tier = cls._resolved_tier(provider)
            return 1.6 if tier == "gold" else (1.3 if tier == "silver" else 1.0)

    @classmethod
    def _calculate_rating_score(cls, provider: Provider) -> float:
        rc = int(getattr(provider, "rating_count", 0) or 0)
        avg = getattr(provider, "average_rating", None)
        bayes = SmartProviderScorer.bayesian_rating(avg if rc > 0 else None, rc)
        return max(0.0, min(1.0, (bayes - 1.0) / 4.0))

    @classmethod
    def _calculate_reliability_score(
        cls,
        provider: Provider,
        metrics: Optional[dict],
        gating_active: bool,
        gating_threshold: int,
    ) -> float:
        fiab = float(getattr(provider, "fiabilite_score", 100) or 100)
        rel = max(0.0, min(1.0, fiab / 100.0))
        if gating_active and fiab < gating_threshold:
            rel *= 0.35
        m = metrics or {}
        active_jobs = int(m.get("active_jobs") or 0)
        completed_jobs = int(m.get("completed_jobs") or 0)
        avg_resp = m.get("avg_response_min")
        if active_jobs > 0:
            rel = max(0.1, rel - min(0.35, active_jobs * 0.08))
        if completed_jobs >= 5:
            rel = min(1.0, rel + min(0.12, math.log1p(completed_jobs) * 0.03))
        if avg_resp is not None and avg_resp <= 30:
            rel = min(1.0, rel + 0.08)
        if getattr(provider, "is_certified", False):
            rel = min(1.0, rel + 0.10)
        return round(rel, 3)

    @classmethod
    def _calculate_availability_score(cls, provider: Provider, target_dt: Optional[datetime] = None) -> float:
        dt = target_dt or timezone.localtime()
        amap = cls._collect_availability_map([provider.id], dt)
        return cls._score_availability(provider, amap.get(provider.id, {}))

    @classmethod
    def _calculate_price_score(cls, provider: Provider, price_max: Optional[float]) -> float:
        if price_max is None or price_max <= 0:
            return 0.65
        tarif = getattr(provider, "tarif_horaire", None)
        if tarif is None or tarif <= 0:
            return 0.60
        tarif_f = float(tarif)
        if tarif_f <= price_max * 0.75:
            return 1.0
        if tarif_f <= price_max:
            return 0.80
        if tarif_f <= price_max * 1.25:
            return 0.45
        return 0.15

    @classmethod
    def _build_reasons(
        cls,
        *,
        p: Provider,
        dist: Optional[float],
        same_city: bool,
        avail_info: dict,
        metrics: dict,
        price_max: Optional[float],
        tier: str,
    ) -> list[str]:
        reasons = []
        if tier == "gold":
            reasons.append("Abonnement Pro Gold (x1.6)")
        elif tier == "silver":
            reasons.append("Abonnement Pro Silver (x1.3)")
        if getattr(p, "is_certified", False):
            reasons.append("Artisan certifie")
        if dist is not None and dist <= 5.0:
            reasons.append(f"Tres proche ({dist:.1f} km)")
        elif dist is not None and dist <= 15.0:
            reasons.append(f"Secteur proche ({dist:.1f} km)")
        elif same_city:
            reasons.append(f"Meme zone ({p.ville})")
        if avail_info.get("matches_time_slot"):
            reasons.append("Creneau libre maintenant")
        elif p.disponible:
            reasons.append("Disponible")
        avg = float(getattr(p, "average_rating", 0) or 0)
        rc = int(getattr(p, "rating_count", 0) or 0)
        if rc > 0 and avg >= 4.5:
            reasons.append(f"Note {avg:.1f}/5 ({rc} avis)")
        fiab = int(getattr(p, "fiabilite_score", 100) or 100)
        if fiab >= 92:
            reasons.append(f"Fiabilite {fiab}%")
        avg_resp = metrics.get("avg_response_min")
        if avg_resp is not None and avg_resp <= 45:
            reasons.append(f"Reponse ~{int(avg_resp)} min")
        if price_max and p.tarif_horaire and float(p.tarif_horaire) <= float(price_max):
            reasons.append("Dans le budget")
        return reasons[:5]

    @classmethod
    def get_top_provider(
        cls,
        category_id: Optional[int],
        lat: Optional[float] = None,
        lon: Optional[float] = None,
    ) -> Optional[Provider]:
        """Retourne le meilleur prestataire pour une categorie et une position."""
        criteria = MatchingCriteria(
            category_id=category_id,
            lat=lat,
            lon=lon,
            radius_km=50.0,
        )
        results = cls.recommend_providers(criteria, limit=1)
        return results[0].provider if results else None
