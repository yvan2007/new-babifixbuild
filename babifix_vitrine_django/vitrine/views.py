import json
import os
import urllib.error
import urllib.request

from django.conf import settings
from django.core.cache import cache
from django.core.mail import send_mail
from django.http import HttpResponse, JsonResponse
from django.shortcuts import render
from django.utils.safestring import mark_safe
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_GET, require_POST

from .models import (
    ContactInquiry,
    FAQItem,
    HeroContent,
    Lead,
    Testimonial,
    VitrineStats,
)
from .public_api import (
    fetch_admin_public_categories,
    fetch_admin_public_config,
    fetch_admin_public_vitrine,
)

# Anti-spam : max 3 messages par IP par heure
_CONTACT_RATE_LIMIT = 3
_CONTACT_RATE_WINDOW = 3600  # secondes


def _client_ip(request):
    """Extraction IP fiable contre spoofing X-Forwarded-For en rate limiting."""
    remote = (request.META.get("REMOTE_ADDR") or "127.0.0.1").strip()
    trust_proxy = bool(
        getattr(settings, "TRUST_PROXY_HEADERS", False)
        or os.getenv("RENDER_EXTERNAL_HOSTNAME", "").strip()
    )
    if trust_proxy and not getattr(settings, "DEBUG", False):
        x_forwarded = request.META.get("HTTP_X_FORWARDED_FOR", "")
        if x_forwarded:
            parts = [p.strip() for p in x_forwarded.split(",") if p.strip()]
            if parts:
                return parts[-1]
    return remote


def _contact_rate_key(request):
    return f"babifix_contact_{_client_ip(request)}"


# Illustrations SVG sur mesure par corps de métier (style éditorial Awwwards)
_TRADE_SVGS = {
    "plomberie": (
        '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.85" '
        'stroke-linecap="round" stroke-linejoin="round">'
        '<path d="M12 2.5c-2.6 3.4-5 6.1-5 9.1a5 5 0 0 0 10 0c0-3-2.4-5.7-5-9.1z" fill="currentColor" fill-opacity="0.14"/>'
        '<path d="M12 2.5c-2.6 3.4-5 6.1-5 9.1a5 5 0 0 0 10 0c0-3-2.4-5.7-5-9.1z"/>'
        '<path d="M10 12.2a2.2 2.2 0 0 0 2.2 2.2"/>'
        '<path d="M4 19.5h16"/><path d="M7 17.5v4"/><path d="M17 17.5v4"/>'
        '</svg>'
    ),
    "electricite": (
        '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.85" '
        'stroke-linecap="round" stroke-linejoin="round">'
        '<polygon points="13 2 4.5 13.5 11.5 13.5 10.5 22 19.5 10.5 12.5 10.5 13 2" fill="currentColor" fill-opacity="0.15"/>'
        '<polygon points="13 2 4.5 13.5 11.5 13.5 10.5 22 19.5 10.5 12.5 10.5 13 2"/>'
        '</svg>'
    ),
    "climatisation": (
        '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.85" '
        'stroke-linecap="round" stroke-linejoin="round">'
        '<rect x="2.5" y="4" width="19" height="8.5" rx="2.2" fill="currentColor" fill-opacity="0.12"/>'
        '<rect x="2.5" y="4" width="19" height="8.5" rx="2.2"/>'
        '<line x1="6" y1="9.5" x2="18" y2="9.5"/>'
        '<circle cx="18" cy="6.8" r="0.8" fill="currentColor"/>'
        '<path d="M6.5 15.5c0 2-1.5 3-1.5 4.5"/><path d="M12 15.5v5"/><path d="M17.5 15.5c0 2 1.5 3 1.5 4.5"/>'
        '</svg>'
    ),
    "menage": (
        '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.85" '
        'stroke-linecap="round" stroke-linejoin="round">'
        '<path d="M12 3l1.9 4.8L18.7 9.7l-4.8 1.9L12 16.4l-1.9-4.8L5.3 9.7l4.8-1.9L12 3z" fill="currentColor" fill-opacity="0.14"/>'
        '<path d="M12 3l1.9 4.8L18.7 9.7l-4.8 1.9L12 16.4l-1.9-4.8L5.3 9.7l4.8-1.9L12 3z"/>'
        '<path d="M18.5 16.5l.8 2 2 .8-2 .8-.8 2-.8-2-2-.8 2-.8.8-2z"/>'
        '<path d="M5.5 16.5l.6 1.5 1.5.6-1.5.6-.6 1.5-.6-1.5-1.5-.6 1.5-.6.6-1.5z"/>'
        '</svg>'
    ),
    "serrurerie": (
        '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.85" '
        'stroke-linecap="round" stroke-linejoin="round">'
        '<circle cx="8" cy="15" r="4.5" fill="currentColor" fill-opacity="0.14"/>'
        '<circle cx="8" cy="15" r="4.5"/>'
        '<path d="M11.2 11.8L20 3"/><path d="M16.5 6.5l2.8 2.8"/><path d="M19 4l2.5 2.5"/>'
        '<circle cx="7.5" cy="15.5" r="1" fill="currentColor"/>'
        '</svg>'
    ),
    "peinture": (
        '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.85" '
        'stroke-linecap="round" stroke-linejoin="round">'
        '<rect x="3" y="3" width="14" height="6" rx="1.8" fill="currentColor" fill-opacity="0.14"/>'
        '<rect x="3" y="3" width="14" height="6" rx="1.8"/>'
        '<path d="M17 6h2a2 2 0 0 1 2 2v2.5a2 2 0 0 1-2 2h-7a2 2 0 0 0-2 2V16"/>'
        '<rect x="8.5" y="16" width="3" height="5.5" rx="1"/>'
        '</svg>'
    ),
    "menuiserie": (
        '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.85" '
        'stroke-linecap="round" stroke-linejoin="round">'
        '<path d="M4 20V5a1 1 0 0 1 1-1h14L4 20z" fill="currentColor" fill-opacity="0.12"/>'
        '<path d="M4 20V5a1 1 0 0 1 1-1h15v16H4z"/>'
        '<path d="M8 9h4"/><path d="M8 13h7"/><path d="M8 17h10"/>'
        '</svg>'
    ),
    "jardinage": (
        '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.85" '
        'stroke-linecap="round" stroke-linejoin="round">'
        '<path d="M11 20A7 7 0 0 1 9.8 6.1C15.5 5 17 4.5 19 2c1 2 2 4.2 2 8 0 5.5-4.8 10-10 10z" fill="currentColor" fill-opacity="0.14"/>'
        '<path d="M11 20A7 7 0 0 1 9.8 6.1C15.5 5 17 4.5 19 2c1 2 2 4.2 2 8 0 5.5-4.8 10-10 10z"/>'
        '<path d="M2 21c0-3 1.9-5.4 5.1-6"/><path d="M11 20c1.5-4 4-7.5 8-10"/>'
        '</svg>'
    ),
    "electromenager": (
        '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.85" '
        'stroke-linecap="round" stroke-linejoin="round">'
        '<rect x="4" y="2.5" width="16" height="19" rx="2.2" fill="currentColor" fill-opacity="0.12"/>'
        '<rect x="4" y="2.5" width="16" height="19" rx="2.2"/>'
        '<line x1="4" y1="8" x2="20" y2="8"/>'
        '<circle cx="12" cy="14.8" r="3.5"/>'
        '<circle cx="7.5" cy="5.2" r="0.8" fill="currentColor"/><circle cx="10.5" cy="5.2" r="0.8" fill="currentColor"/>'
        '</svg>'
    ),
    "informatique": (
        '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.85" '
        'stroke-linecap="round" stroke-linejoin="round">'
        '<rect x="2.5" y="3.5" width="19" height="13" rx="2" fill="currentColor" fill-opacity="0.12"/>'
        '<rect x="2.5" y="3.5" width="19" height="13" rx="2"/>'
        '<path d="M8 20.5h8"/><path d="M12 16.5v4"/>'
        '<path d="M7.5 10l2 2 5-4.5"/>'
        '</svg>'
    ),
    "coiffure": (
        '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.85" '
        'stroke-linecap="round" stroke-linejoin="round">'
        '<circle cx="6" cy="6" r="3" fill="currentColor" fill-opacity="0.14"/>'
        '<circle cx="6" cy="18" r="3" fill="currentColor" fill-opacity="0.14"/>'
        '<circle cx="6" cy="6" r="3"/><circle cx="6" cy="18" r="3"/>'
        '<line x1="20" y1="4" x2="8.12" y2="15.88"/><line x1="14.47" y1="14.48" x2="20" y2="20"/><line x1="8.12" y1="8.12" x2="12" y2="12"/>'
        '</svg>'
    ),
    "auto": (
        '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.85" '
        'stroke-linecap="round" stroke-linejoin="round">'
        '<path d="M5 11l2-5h10l2 5" fill="currentColor" fill-opacity="0.12"/>'
        '<rect x="3" y="11" width="18" height="6" rx="2" fill="currentColor" fill-opacity="0.12"/>'
        '<path d="M5 11l2-5h10l2 5"/><rect x="3" y="11" width="18" height="6" rx="2"/>'
        '<circle cx="7" cy="17" r="2"/><circle cx="17" cy="17" r="2"/>'
        '</svg>'
    ),
}

# Catalogue éditorial de référence : enrichit les catégories de la base
# pour garantir un rendu digne d'un studio Awwwards (titres courts, sous-titres
# techniques, tags d'interventions réelles et icônes SVG dédiées).
_EDITORIAL_CATALOG = [
    {
        "match": ("plomb", "sanitaire", "goutte", "eau"),
        "short_nom": "Plomberie",
        "sub_nom": "Dépannage sanitaire & réseau d'eau",
        "phone_sub": "Dépannage sanitaire",
        "description": "Recherche de fuites, débouchage haute pression, pose de robinetterie et chauffe-eau à Abidjan.",
        "tags": ["Fuites & joints", "Débouchage", "Chauffe-eau"],
        "group": "urgence",
        "group_label": "Urgence & Eau",
        "delai": "Urgence ~30 min",
        "color": "#0284c7",
        "svg_key": "plomberie",
    },
    {
        "match": ("electr", "eclair", "courant", "luminaire"),
        "short_nom": "Électricité",
        "sub_nom": "Mise aux normes & dépannage",
        "phone_sub": "Pannes & tableaux",
        "description": "Diagnostic de court-circuit, tableaux divisionnaires CIE, prises, onduleurs et éclairage architectural.",
        "tags": ["Panne de courant", "Tableau & disjoncteur", "Câblage pro"],
        "group": "urgence",
        "group_label": "Haute & Basse Tension",
        "delai": "Urgence ~35 min",
        "color": "#d97706",
        "svg_key": "electricite",
    },
    {
        "match": ("clim", "ventil", "froid", "split"),
        "short_nom": "Climatisation",
        "sub_nom": "Entretien split, froid & ventilation",
        "phone_sub": "Split & recharge gaz",
        "description": "Nettoyage antibactérien de splits, recharge gaz R410A/R32, pose murale et maintenance préventive.",
        "tags": ["Entretien split", "Recharge gaz", "Pose & dépose"],
        "group": "urgence",
        "group_label": "Froid & Air",
        "delai": "Sous 2 heures",
        "color": "#0891b2",
        "svg_key": "climatisation",
    },
    {
        "match": ("menage", "nettoyage", "balai", "repassage"),
        "short_nom": "Ménage & Soin",
        "sub_nom": "Entretien courant & grand nettoyage",
        "phone_sub": "Entretien résidentiel",
        "description": "Entretien régulier de résidences, remise en état fin de chantier, désinfection vapeur et vitrerie.",
        "tags": ["Ménage régulier", "Fin de chantier", "Désinfection"],
        "group": "quotidien",
        "group_label": "Maison & Hygiène",
        "delai": "Créneau au choix",
        "color": "#0d9488",
        "svg_key": "menage",
    },
    {
        "match": ("serrur", "cle", "porte"),
        "short_nom": "Serrurerie",
        "sub_nom": "Ouverture fine & blindage de porte",
        "phone_sub": "Ouverture & cylindres",
        "description": "Ouverture sans destruction de portes claquées, remplacement de cylindres haute sécurité et verrous.",
        "tags": ["Porte claquée", "Cylindre blindé", "Sécurisation"],
        "group": "urgence",
        "group_label": "Accès & Sécurité",
        "delai": "Urgence ~30 min",
        "color": "#475569",
        "svg_key": "serrurerie",
    },
    {
        "match": ("peint", "pinceau", "decor", "ravalement"),
        "short_nom": "Peinture",
        "sub_nom": "Finitions intérieures & ravalement",
        "phone_sub": "Intérieur & façades",
        "description": "Préparation d'enduits lisses, mise en teinte mate ou velours, traitement anti-humidité et façades.",
        "tags": ["Enduit & lissage", "Peinture intérieure", "Anti-humidité"],
        "group": "habitat",
        "group_label": "Rénovation & Déco",
        "delai": "Devis sous 24 h",
        "color": "#7c3aed",
        "svg_key": "peinture",
    },
    {
        "match": ("menuis", "parquet", "bois", "meuble"),
        "short_nom": "Menuiserie",
        "sub_nom": "Agencement bois, portes & mobilier",
        "phone_sub": "Portes & sur-mesure",
        "description": "Ajustement de portes, pose de dressings sur mesure, réparation de charnières et montage de mobilier.",
        "tags": ["Portes & huisseries", "Dressing & placards", "Montage pro"],
        "group": "habitat",
        "group_label": "Bois & Agencement",
        "delai": "Sur rendez-vous",
        "color": "#b45309",
        "svg_key": "menuiserie",
    },
    {
        "match": ("jardin", "tondeuse", "elagage", "haie"),
        "short_nom": "Jardinage",
        "sub_nom": "Entretien paysager & taille de haies",
        "phone_sub": "Paysage & entretien",
        "description": "Tonte soignée, taille architecturale de haies, élagage sécurisé et création de massifs tropicaux.",
        "tags": ["Tonte & débroussaillage", "Taille de haies", "Élagage"],
        "group": "quotidien",
        "group_label": "Extérieurs & Verts",
        "delai": "Créneau au choix",
        "color": "#15803d",
        "svg_key": "jardinage",
    },
    {
        "match": ("electromenager", "frigo", "lave"),
        "short_nom": "Électroménager",
        "sub_nom": "Diagnostic & réparation à domicile",
        "phone_sub": "Froid & lavage",
        "description": "Dépannage de réfrigérateurs, congélateurs, lave-linge et fours avec pièces d'origine contrôlées.",
        "tags": ["Réfrigérateur", "Lave-linge", "Four & cuisson"],
        "group": "urgence",
        "group_label": "Équipement Maison",
        "delai": "Intervention ~2 h",
        "color": "#0369a1",
        "svg_key": "electromenager",
    },
    {
        "match": ("informati", "ordinateur", "domotique", "reseau"),
        "short_nom": "Informatique",
        "sub_nom": "Réseaux Wi-Fi, fibre & postes pro",
        "phone_sub": "Wi-Fi & dépannage PC",
        "description": "Optimisation couverture Wi-Fi/Mesh, configuration routeurs fibre, sécurité et dépannage Mac/PC.",
        "tags": ["Couverture Wi-Fi", "Dépannage PC/Mac", "Sauvegarde"],
        "group": "quotidien",
        "group_label": "Numérique & Réseau",
        "delai": "Sous 2 heures",
        "color": "#1d4ed8",
        "svg_key": "informatique",
    },
    {
        "match": ("coiffure", "ciseaux", "esthetique", "massage"),
        "short_nom": "Beauté & Soin",
        "sub_nom": "Coiffure, tresses & soins à domicile",
        "phone_sub": "Coiffure & esthétique",
        "description": "Prestations privées à domicile : tresses, coiffure événementielle, soins visage et manucure soignée.",
        "tags": ["Coiffure & tresses", "Soins & manucure", "Maquillage"],
        "group": "quotidien",
        "group_label": "Bien-être Privé",
        "delai": "Sur rendez-vous",
        "color": "#be185d",
        "svg_key": "coiffure",
    },
    {
        "match": ("auto", "voiture", "mecanique", "lavage"),
        "short_nom": "Auto à domicile",
        "sub_nom": "Diagnostic mécanique & detailing",
        "phone_sub": "Batterie & entretien",
        "description": "Dépannage batterie sur place, diagnostic électronique, révision courante et lavage écologique.",
        "tags": ["Batterie & démarrage", "Diagnostic OBD", "Lavage pro"],
        "group": "urgence",
        "group_label": "Mobilité & Auto",
        "delai": "Intervention ~45 min",
        "color": "#334155",
        "svg_key": "auto",
    },
]


def _enrich_vitrine_categories(raw_categories):
    """Construit la sélection éditoriale pour la vitrine et le téléphone flottant."""
    raw_list = raw_categories if isinstance(raw_categories, list) else []
    total_count = max(len(raw_list), 42)

    enriched = []
    used_specs = set()

    # 1. Associer les catégories de la base aux fiches éditoriales principales
    for spec in _EDITORIAL_CATALOG:
        matched_cat = None
        for c in raw_list:
            haystack = f"{c.get('nom', '')} {c.get('icone_slug', '')}".lower()
            if any(k in haystack for k in spec["match"]):
                matched_cat = c
                break
        idx = len(enriched) + 1
        cat_id = matched_cat.get("id", idx) if matched_cat else idx
        full_nom = matched_cat.get("nom", f"{spec['short_nom']} & {spec['sub_nom'].lower()}") if matched_cat else f"{spec['short_nom']} & {spec['sub_nom'].lower()}"
        enriched.append({
            "id": cat_id,
            "num": f"{idx:02d}",
            "nom": full_nom,
            "short_nom": spec["short_nom"],
            "sub_nom": spec["sub_nom"],
            "phone_sub": spec["phone_sub"],
            "description": (matched_cat.get("description") if matched_cat and matched_cat.get("description") else spec["description"]),
            "tags": spec["tags"],
            "search_keywords": (matched_cat.get("search_keywords", "") if matched_cat else ""),
            "regime_kyc": (matched_cat.get("regime_kyc", "STANDARD_TERRAIN") if matched_cat else "STANDARD_TERRAIN"),
            "group": spec["group"],
            "group_label": spec["group_label"],
            "delai": spec["delai"],
            "color": spec["color"],
            "svg_icon": mark_safe(_TRADE_SVGS[spec["svg_key"]]),
        })
        used_specs.add(spec["short_nom"])

    return enriched, enriched[:4], total_count


def home(request):
    message = ""
    contact_message = ""
    if request.method == "POST":
        # Formulaire contact (champs préfixés pour ne pas confondre avec la newsletter)
        if request.POST.get("contact_form"):
            # Honeypot : si le champ caché "website" est rempli, c'est un bot
            if request.POST.get("website", "").strip():
                contact_message = "Merci ! Votre message a bien été envoyé. Nous vous répondons sous 48 h."
            else:
                # Rate limiting
                rate_key = _contact_rate_key(request)
                count = cache.get(rate_key, 0)
                if count >= _CONTACT_RATE_LIMIT:
                    contact_message = "Trop de messages envoyés. Veuillez patienter avant de réessayer."
                else:
                    name = (request.POST.get("contact_name") or "").replace("\r", " ").replace("\n", " ").strip()[:120]
                    c_email = (request.POST.get("contact_email") or "").replace("\r", "").replace("\n", "").strip()[:254]
                    subject = (request.POST.get("contact_subject") or "").replace("\r", " ").replace("\n", " ").strip()[:180]
                    body = (request.POST.get("contact_message") or "").strip()[:5000]
                    from django.core.exceptions import ValidationError
                    from django.core.validators import validate_email

                    email_ok = True
                    try:
                        validate_email(c_email)
                    except ValidationError:
                        email_ok = False
                    if name and c_email and email_ok and subject and body:
                        ContactInquiry.objects.create(
                            name=name,
                            email=c_email,
                            subject=subject,
                            message=body,
                        )
                        cache.set(rate_key, count + 1, _CONTACT_RATE_WINDOW)

                        # Envoyer email à l'équipe admin
                        admin_email = settings.DEFAULT_FROM_EMAIL
                        try:
                            send_mail(
                                subject=f"[CONTACT BABIFIX] {subject}",
                                message=f"De: {name} <{c_email}>\n\n{body}",
                                from_email=admin_email,
                                recipient_list=[admin_email],
                                fail_silently=False,
                            )
                        except Exception:
                            pass  # Email échoué mais message enregistré en DB

                        contact_message = "Merci ! Votre message a bien été envoyé. Nous vous répondons sous 48 h."
                    else:
                        contact_message = (
                            "Veuillez remplir tous les champs du formulaire avec un email valide."
                        )
        else:
            email = request.POST.get("email", "").strip()
            if email:
                _, created = Lead.objects.get_or_create(email=email)
                message = (
                    "Merci, votre demande a bien ete enregistree."
                    if created
                    else "Cet email est deja inscrit."
                )
            else:
                message = "Veuillez saisir une adresse email valide."

    base_ctx = None
    if request.method == "GET":
        base_ctx = cache.get("vitrine:home:editorial_ctx_v1")

    if base_ctx is None:
        vd = fetch_admin_public_vitrine()
        cat_payload = fetch_admin_public_categories()
        raw_categories = cat_payload.get("categories") if isinstance(cat_payload, dict) else []
        if not isinstance(raw_categories, list):
            raw_categories = []
        categories, phone_categories, total_categories_count = _enrich_vitrine_categories(raw_categories)

        faq_raw = vd.get("faq")
        faq_items = faq_raw if isinstance(faq_raw, list) else []

        hero_title = (vd.get("hero_title") or "").strip() or None
        hero_subtitle = (vd.get("hero_subtitle") or "").strip() or None

        # Récupérer le contenu héros depuis la DB
        hero_db = HeroContent.objects.filter(actif=True).first()
        if hero_db:
            hero_title = hero_title or hero_db.titre
            hero_subtitle = hero_subtitle or hero_db.soustitre

        store_ios = (vd.get("store_ios_url") or "").strip()
        store_android = (vd.get("store_android_url") or "").strip()
        store_p_ios = (vd.get("store_prestataire_ios_url") or "").strip()
        store_p_android = (vd.get("store_prestataire_android_url") or "").strip()

        # Statistiques & console live : priorité absolue aux vraies données Admin
        kpis_api = vd.get("kpis") if isinstance(vd.get("kpis"), list) else []
        if kpis_api:
            stats_list = kpis_api
        else:
            stats_db = VitrineStats.objects.filter(actif=True).order_by("ordre_affichage")
            stats_list = [{"label": s.label, "value": s.valeur} for s in stats_db]
            if not stats_list:
                stats_list = [
                    {"label": "Prestataires vérifiés", "value": "0", "kind": "providers", "sub": "Synchronisation en cours"},
                    {"label": "Missions & demandes", "value": "0", "kind": "services", "sub": "Synchronisation en cours"},
                    {"label": "Note moyenne client", "value": "-- / 5", "kind": "rating", "stars": 0, "sub": "Avis ouverts après mission"},
                    {"label": "Missions sans litige", "value": "100 %", "kind": "satisfaction", "gauge_pct": 100, "sub": "Dossiers conformes"},
                ]

        # Récupérer les témoignages depuis la DB
        temoignages_db = Testimonial.objects.filter(actif=True).order_by("ordre_affichage")
        temoignages_list = [
            {
                "nom": t.nom,
                "role": t.role,
                "ville": t.ville,
                "texte": t.texte,
            }
            for t in temoignages_db
        ]
        if not temoignages_list:
            temoignages_list = [
                {
                    "nom": "Aminata Koné",
                    "role": "Particulier",
                    "ville": "Abidjan Cocody",
                    "texte": "J'ai trouvé un excellent plombier en moins de 10 minutes. Service rapide et professionnel. Je recommande à 100% !",
                },
                {
                    "nom": "Ibrahim Touré",
                    "role": "Chef d'entreprise",
                    "ville": "Bouaké",
                    "texte": "BABIFIX a révolutionné ma façon de trouver des prestataires. Fini les longues recherches, tout est simple et sécurisé.",
                },
                {
                    "nom": "Marie Koffi",
                    "role": "Électricienne · Prestataire BABIFIX",
                    "ville": "Abidjan Plateau",
                    "texte": "En tant qu'électricienne, BABIFIX m'a permis de développer ma clientèle rapidement. Les paiements sont toujours sécurisés.",
                },
            ]

        # Récupérer les FAQs depuis la DB
        faq_db = FAQItem.objects.filter(actif=True).order_by("ordre_affichage")
        faq_items = (
            [{"question": f.question, "answer": f.answer} for f in faq_db]
            if faq_db
            else faq_items
        )

        base_ctx = {
            "active_page": "home",
            "platform_cfg": fetch_admin_public_config(),
            "hero_title": hero_title,
            "hero_subtitle": hero_subtitle,
            "store_ios_client": store_ios,
            "store_android_client": store_android,
            "store_ios_prestataire": store_p_ios,
            "store_android_prestataire": store_p_android,
            "stats": stats_list,
            "live_cities": vd.get("cities") if isinstance(vd.get("cities"), list) else [],
            "live_feed": vd.get("live_feed") if isinstance(vd.get("live_feed"), list) else [],
            "live_stats": vd.get("stats") if isinstance(vd.get("stats"), dict) else {},
            "features": [
                "Sécurisé",
                "Local",
                "Simple",
                "Mobile Money",
                "Rapide",
                "Qualité garantie",
            ],
            "temoignages": temoignages_list,
            "categories": categories,
            "phone_categories": phone_categories,
            "raw_categories_json": raw_categories,
            "total_categories_count": total_categories_count,
            "admin_api_base": os.getenv(
                "BABIFIX_ADMIN_API_BASE", "http://127.0.0.1:8000"
            ).rstrip("/"),
            "faq_items": faq_items,
        }
        cache.set("vitrine:home:editorial_ctx_v1", base_ctx, 15)

    # Console live toujours fraiche (cache court 15s cote public_api)
    live_vd = fetch_admin_public_vitrine()
    live_payload = _extract_live_console_payload(live_vd, base_ctx)

    from .seo_catalog import SEO_TRADES, SEO_ZONES, build_home_jsonld, canonical_base_url

    canon_base = canonical_base_url(request)
    context = {
        **base_ctx,
        "stats": live_payload["kpis"],
        "live_kpis": live_payload["kpis"],
        "live_cities": live_payload["cities"],
        "live_feed": live_payload["live_feed"],
        "live_stats": live_payload["stats"],
        "live_cities_json": live_payload["cities"],
        "live_feed_json": live_payload["live_feed"],
        "message": message,
        "contact_message": contact_message,
        "last_email": "",
        "canonical_base": canon_base,
        "canonical_url": f"{canon_base}/",
        "home_jsonld": mark_safe(build_home_jsonld(canon_base, base_ctx.get("faq_items"))),
        "seo_trades": SEO_TRADES,
        "seo_zones": SEO_ZONES,
    }
    return render(request, "vitrine/home.html", context)


def _default_ci_cities():
    return [
        {"key": "abidjan", "name": "Abidjan", "svg_x": 755, "svg_y": 864, "label_x": 784, "label_y": 875, "anchor": "start", "color": "#4CC9F0", "is_hub": True, "providers_count": 0, "reservations_count": 0, "active_count": 0, "has_activity": False, "intensity": "standby", "pulse_sec": 0},
        {"key": "yamoussoukro", "name": "Yamoussoukro", "svg_x": 554, "svg_y": 627, "label_x": 583, "label_y": 638, "anchor": "start", "color": "#E87722", "is_hub": True, "providers_count": 0, "reservations_count": 0, "active_count": 0, "has_activity": False, "intensity": "standby", "pulse_sec": 0},
        {"key": "bouake", "name": "Bouaké", "svg_x": 594, "svg_y": 488, "label_x": 623, "label_y": 499, "anchor": "start", "color": "#10B981", "is_hub": True, "providers_count": 0, "reservations_count": 0, "active_count": 0, "has_activity": False, "intensity": "standby", "pulse_sec": 0},
        {"key": "korhogo", "name": "Korhogo", "svg_x": 498, "svg_y": 205, "label_x": 527, "label_y": 216, "anchor": "start", "color": "#4CC9F0", "is_hub": True, "providers_count": 0, "reservations_count": 0, "active_count": 0, "has_activity": False, "intensity": "standby", "pulse_sec": 0},
        {"key": "man", "name": "Man", "svg_x": 191, "svg_y": 533, "label_x": 220, "label_y": 544, "anchor": "start", "color": "#E87722", "is_hub": True, "providers_count": 0, "reservations_count": 0, "active_count": 0, "has_activity": False, "intensity": "standby", "pulse_sec": 0},
    ]


def _extract_live_console_payload(vd: dict, fallback_ctx: dict | None = None) -> dict:
    vd = vd if isinstance(vd, dict) else {}
    kpis = vd.get("kpis") if isinstance(vd.get("kpis"), list) and vd.get("kpis") else (
        fallback_ctx.get("stats") if isinstance(fallback_ctx, dict) and fallback_ctx.get("stats") else [
            {"label": "Prestataires vérifiés", "value": "0", "kind": "providers", "sub": "Réseau en synchronisation"},
            {"label": "Missions & demandes", "value": "0", "kind": "services", "sub": "Réseau en synchronisation"},
            {"label": "Note moyenne client", "value": "-- / 5", "kind": "rating", "stars": 0, "sub": "Avis ouverts après mission"},
            {"label": "Missions sans litige", "value": "100 %", "kind": "satisfaction", "gauge_pct": 100, "sub": "Dossiers conformes"},
        ]
    )
    cities = vd.get("cities") if isinstance(vd.get("cities"), list) and vd.get("cities") else _default_ci_cities()
    live_feed = vd.get("live_feed") if isinstance(vd.get("live_feed"), list) and vd.get("live_feed") else [
        {"text": "Réseau BABIFIX en Côte d'Ivoire · connexion au direct", "city_key": "abidjan", "city_name": "Abidjan", "status": "En ligne"}
    ]
    stats = vd.get("stats") if isinstance(vd.get("stats"), dict) else {}
    return {
        "stats": stats,
        "kpis": kpis,
        "cities": cities,
        "live_feed": live_feed,
        "updated_at": vd.get("updated_at") or "",
    }


@require_GET
def api_live_console(request):
    """Endpoint JSON live pour la carte Côte d'Ivoire, les pings des villes et les KPIs reels."""
    vd = fetch_admin_public_vitrine()
    return JsonResponse(_extract_live_console_payload(vd), status=200)


def _svg(path):
    return (
        '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" '
        'stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'
        + path + "</svg>"
    )


def telecharger_app_client(request):
    vd = fetch_admin_public_vitrine()
    active_app = request.GET.get("app", "client")
    if active_app not in ("client", "prestataire"):
        active_app = "client"
    client_features = [
        {"icon": _svg('<circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/>'),
         "title": "Prestataires geolocalises", "desc": "Visualisez les artisans disponibles a proximite de votre commune."},
        {"icon": _svg('<rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0110 0v4"/>'),
         "title": "Paiement sous sequestre", "desc": "Acompte protege en securite jusqu'a votre validation de fin de chantier."},
        {"icon": _svg('<path d="M9 11l3 3L22 4"/><path d="M21 12v7a2 2 0 01-2 2H5a2 2 0 01-2-2V5a2 2 0 012-2h11"/>'),
         "title": "Identites CNI controlees", "desc": "Chaque artisan presente sa piece d'identite et ses qualifications."},
        {"icon": _svg('<path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/><path d="M14 2v6h6"/>'),
         "title": "Devis et recus numeriques", "desc": "Chiffrage sur mesure avant intervention et recu PDF verifiable."},
    ]
    pro_features = [
        {"icon": _svg('<path d="M22 12h-4l-3 9L9 3l-3 9H2"/>'),
         "title": "Missions ciblees par zone", "desc": "Recevez les demandes en temps reel selon votre rayon et specialite."},
        {"icon": _svg('<rect x="2" y="5" width="20" height="14" rx="2"/><path d="M2 10h20"/>'),
         "title": "Wallet 3D & Retraits 24/7", "desc": "Consultez solde disponible et sequestre, et virez sur Mobile Money."},
        {"icon": _svg('<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>'),
         "title": "Clients et acomptes qualifies", "desc": "Aucun deplacement dans le vide : l'acompte est consigne avant travaux."},
        {"icon": _svg('<polygon points="12 2 15.1 8.3 22 9.3 17 14.1 18.2 21 12 17.8 5.8 21 7 14.1 2 9.3 8.9 8.3 12 2"/>'),
         "title": "Paliers Pro degressifs", "desc": "Passez en Silver ou Gold pour reduire votre commission et gagner en visibilite."},
    ]
    client_tiles = [
        {"svg": mark_safe(_TRADE_SVGS["plomberie"]), "t": "Plomberie"},
        {"svg": mark_safe(_TRADE_SVGS["electricite"]), "t": "Electricite"},
        {"svg": mark_safe(_TRADE_SVGS["menage"]), "t": "Menage"},
        {"svg": mark_safe(_TRADE_SVGS["jardinage"]), "t": "Jardinage"},
    ]
    pro_tiles = [
        {"svg": mark_safe(_TRADE_SVGS["climatisation"]), "t": "Devis Pro"},
        {"svg": mark_safe(_TRADE_SVGS["electromenager"]), "t": "Wallet 3D"},
        {"svg": mark_safe(_TRADE_SVGS["auto"]), "t": "Geolocalisation"},
        {"svg": mark_safe(_TRADE_SVGS["coiffure"]), "t": "Badge KYC"},
    ]
    return render(request, "vitrine/telecharger.html", {
        "active_page": "telecharger",
        "page_title": "Telecharger l'application",
        "active_app": active_app,
        "accent": "#0369A1",
        "pill": "Applications Mobiles BABIFIX",
        "heading_pre": "Vos services a domicile,",
        "heading_hl": "en quelques clics.",
        "lead": "Trouvez un prestataire verifie pres de chez vous, obtenez un "
                "devis sur mesure clair, et payez en Mobile Money avec sequestre "
                "securise jusqu'a la fin des travaux.",
        "ios_url": (vd.get("store_ios_url") or "").strip(),
        "android_url": (vd.get("store_android_url") or "").strip(),
        "prestataire_ios_url": (vd.get("store_prestataire_ios_url") or "").strip(),
        "prestataire_android_url": (vd.get("store_prestataire_android_url") or "").strip(),
        "features": pro_features if active_app == "prestataire" else client_features,
        "client_features_json": [{"title": x["title"], "desc": x["desc"], "icon": x["icon"]} for x in client_features],
        "pro_features_json": [{"title": x["title"], "desc": x["desc"], "icon": x["icon"]} for x in pro_features],
        "stats": [
            {"v": "50K+", "l": "Services realises"},
            {"v": "4.9/5", "l": "Note moyenne"},
            {"v": "100%", "l": "Paiement protege"},
        ],
        "mock_hi": "Espace Artisan Pro" if active_app == "prestataire" else "Bonjour, Abidjan",
        "mock_sub": "Badge verifie CNI · Disponible" if active_app == "prestataire" else "Quel service aujourd'hui ?",
        "mock_promo_t": "Acomptes consignes d'avance" if active_app == "prestataire" else "Paiement 100 % protege",
        "mock_promo_s": "Solde disponible des fin de mission" if active_app == "prestataire" else "Mobile Money · sequestre verifie",
        "mock_tiles": pro_tiles if active_app == "prestataire" else client_tiles,
        "client_tiles_json": [{"t": x["t"], "svg": str(x["svg"])} for x in client_tiles],
        "pro_tiles_json": [{"t": x["t"], "svg": str(x["svg"])} for x in pro_tiles],
    })


def devenir_prestataire(request):
    vd = fetch_admin_public_vitrine()
    pcfg = fetch_admin_public_config()
    return render(request, "vitrine/devenir_prestataire.html", {
        "active_page": "prestataire",
        "platform_cfg": pcfg,
        "page_title": "Devenir prestataire officiel",
        "accent": "#C2410C",
        "pill": "Programme Artisans d'Elite · Cote d'Ivoire",
        "heading_pre": "Vos competences meritent",
        "heading_hl": "le meilleur revenu d'Abidjan.",
        "lead": (
            f"Recevez des missions qualifiees pres de chez vous avec acompte consigne avant tout deplacement. "
            f"Plus vous travaillez, plus votre commission diminue (de {pcfg['std_rate']} % jusqu'a {pcfg['gold_rate']} %)."
        ),
        "ios_url": (vd.get("store_prestataire_ios_url") or "").strip(),
        "android_url": (vd.get("store_prestataire_android_url") or "").strip(),
        "features": [
            {"icon": _svg('<path d="M22 12h-4l-3 9L9 3l-3 9H2"/>'),
             "title": "Des missions regulieres", "desc": "Recevez les demandes ciblees par commune autour de vous."},
            {"icon": _svg('<line x1="12" y1="1" x2="12" y2="23"/><path d="M17 5H9.5a3.5 3.5 0 000 7h5a3.5 3.5 0 010 7H6"/>'),
             "title": "Paiement garanti", "desc": "Votre solde est verse via Wave, Orange Money ou MTN MoMo."},
            {"icon": _svg('<polygon points="12 2 15.1 8.3 22 9.3 17 14.1 18.2 21 12 17.8 5.8 21 7 14.1 2 9.3 8.9 8.3 12 2"/>'),
             "title": "Reputation & badges", "desc": "Vos avis verifies et votre niveau debloquent des avantages Pro."},
            {"icon": _svg('<path d="M3 3v18h18"/><path d="M19 9l-5 5-4-4-3 3"/>'),
             "title": "Commission degressive", "desc": f"Standard {pcfg['std_rate']} %, Pro Silver {pcfg['silver_rate']} %, Pro Gold {pcfg['gold_rate']} % selon votre activite."},
        ],
        "stats": [
            {"v": f"{pcfg['std_rate']}% a {pcfg['gold_rate']}%", "l": "Commission degressive"},
            {"v": "0 F", "l": "Inscription gratuite"},
            {"v": "24 h", "l": "Validation rapide"},
        ],
        "mock_hi": "Tableau de bord Pro", "mock_sub": "Espace artisan certifie",
        "mock_promo_t": "Wallet Pro & Sequestre", "mock_promo_s": "Gains credites des validation client",
    })


def creer_un_compte(request):
    return render(
        request,
        "vitrine/creer_un_compte.html",
        {
            "active_page": "creer_compte",
            "page_title": "Créer un compte BABIFIX",
        },
    )


_ERROR_CATALOG = {
    400: (
        "vitrine/400.html",
        "400",
        "Requête invalide.",
        "Requête incorrecte",
        "Les paramètres envoyés ne peuvent pas être traités. Vérifiez votre lien et réessayez.",
    ),
    403: (
        "vitrine/403.html",
        "403",
        "Accès refusé.",
        "Accès non autorisé",
        "Vous n'avez pas les autorisations nécessaires pour consulter cette ressource.",
    ),
    404: (
        "vitrine/404.html",
        "404",
        "Page introuvable.",
        "Page introuvable",
        "L'adresse demandée n'existe pas ou a été déplacée. Retrouvez tous nos métiers et nos services depuis l'accueil BABIFIX.",
    ),
    500: (
        "vitrine/500.html",
        "500",
        "Incident serveur.",
        "Incident serveur temporaire",
        "Une erreur inattendue est survenue de notre côté. Nos équipes techniques suivent le service, réessayez dans quelques instants.",
    ),
    502: (
        "vitrine/505.html",
        "502",
        "Passerelle HS.",
        "Passerelle temporairement indisponible",
        "La passerelle applicative n'a pas répondu à temps. Veuillez réessayer dans quelques secondes.",
    ),
    503: (
        "vitrine/505.html",
        "503",
        "Maintenance.",
        "Service momentanément indisponible",
        "Une opération de maintenance ou de mise à jour est en cours sur BABIFIX. Revenez très vite.",
    ),
    505: (
        "vitrine/505.html",
        "505",
        "Version HTTP 505.",
        "Version HTTP non prise en charge",
        "Le protocole HTTP utilisé par votre navigateur ou proxy n'est pas supporté par ce serveur.",
    ),
}


def _render_vitrine_error(request, status_code: int):
    tpl, code_str, svg_txt, title, message = _ERROR_CATALOG.get(
        status_code, _ERROR_CATALOG[404]
    )
    ctx = {
        "error_code": code_str,
        "error_svg_text": svg_txt,
        "error_title": title,
        "error_message": message,
    }
    return render(request, tpl, ctx, status=status_code)


def error_400(request, exception=None):
    return _render_vitrine_error(request, 400)


def error_403(request, exception=None):
    return _render_vitrine_error(request, 403)


def error_404(request, exception=None):
    return _render_vitrine_error(request, 404)


def error_500(request):
    try:
        return _render_vitrine_error(request, 500)
    except Exception:
        return render(request, "vitrine/_error_train.html", {
            "error_code": "500",
            "error_svg_text": "Incident serveur.",
            "error_title": "Incident serveur temporaire",
            "error_message": "Une erreur inattendue est survenue. Réessayez dans quelques instants.",
        }, status=500)


def error_preview(request, code: int):
    if code not in _ERROR_CATALOG:
        return _render_vitrine_error(request, 404)
    return _render_vitrine_error(request, code)


# =============================================================================
# API NEWSLETTER : POST /api/newsletter/subscribe/
# =============================================================================
@csrf_exempt
@require_POST
def api_newsletter_subscribe(request):
    """API d'inscription à la newsletter avec honeypot anti-spam."""
    try:
        payload = json.loads(request.body)
    except (json.JSONDecodeError, ValueError):
        return JsonResponse({"error": "invalid_json"}, status=400)

    # Honeypot - si rempli, c'est un bot
    honeypot = payload.get("website_url", "").strip()
    if honeypot:
        # Simuler un succès pour piéger le bot
        return JsonResponse({"ok": True, "message": "Inscription confirmée"})

    email = (payload.get("email") or "").replace("\r", "").replace("\n", "").strip().lower()[:254]
    from django.core.exceptions import ValidationError
    from django.core.validators import validate_email

    if not email:
        return JsonResponse({"error": "email_required"}, status=400)
    try:
        validate_email(email)
    except ValidationError:
        return JsonResponse({"error": "email_invalid"}, status=400)

    # Rate limiting par IP fiable
    ip = _client_ip(request)
    rate_key = f"newsletter_subscribe_{ip}"
    count = cache.get(rate_key, 0)
    if count >= 5:
        return JsonResponse({"error": "rate_limit_exceeded"}, status=429)

    # Enregistrer ou récupérer le lead (Lead stocke email et created_at)
    lead, created = Lead.objects.get_or_create(email=email)

    cache.set(rate_key, count + 1, 3600)  # 1h

    return JsonResponse(
        {
            "ok": True,
            "message": "Inscription confirmée"
            if created
            else "Cet email est déjà inscrit.",
        }
    )


def cgu(request):
    return render(request, "vitrine/cgu.html", {"active_page": "legal", "active_legal": "cgu"})


def confidentialite(request):
    return render(request, "vitrine/confidentialite.html", {"active_page": "legal", "active_legal": "confidentialite"})


def mentions_legales(request):
    return render(request, "vitrine/mentions_legales.html", {"active_page": "legal", "active_legal": "mentions"})


def politique_cookies(request):
    return render(request, "vitrine/politique_cookies.html", {"active_page": "legal", "active_legal": "cookies"})


def proposer_metier(request):
    """Espace communautaire : proposer / soutenir un métier manquant.

    Le contenu (liste + vote) est chargé via le proxy interne /api/public/metiers/.
    """
    return render(request, "vitrine/proposer_metier.html", {
        "active_page": "proposer_metier",
        "api_base": "",
    })


def _candidate_admin_bases():
    env_base = os.getenv("BABIFIX_ADMIN_API_BASE", "").strip().rstrip("/")
    bases = [b for b in [env_base, "http://127.0.0.1:8002", "http://127.0.0.1:8011"] if b]
    return list(dict.fromkeys(bases))


def _proxy_admin_json(path_and_query, method="GET", body_bytes=None, extra_headers=None):
    """Relais JSON generique vers l'API du backend admin BABIFIX."""
    headers = {"Content-Type": "application/json"}
    if extra_headers:
        headers.update(extra_headers)
    for base in _candidate_admin_bases():
        url = f"{base}{path_and_query}"
        req = urllib.request.Request(
            url,
            data=body_bytes,
            method=method,
            headers=headers,
        )
        try:
            with urllib.request.urlopen(req, timeout=8) as resp:
                raw = resp.read()
                ctype = resp.headers.get("Content-Type", "application/json")
                return HttpResponse(raw, status=resp.status, content_type=ctype)
        except urllib.error.HTTPError as exc:
            raw_err = exc.read()
            ctype = exc.headers.get("Content-Type", "application/json") if exc.headers else "application/json"
            return HttpResponse(raw_err, status=exc.code, content_type=ctype)
        except (urllib.error.URLError, TimeoutError, OSError):
            continue
    return None


def _is_safe_proxy_path(req_path: str) -> bool:
    """Empêche path traversal, injection CRLF et accès aux routes admin/internes via le proxy vitrine."""
    if not req_path or any(ch in req_path for ch in ("\r", "\n", "\x00", "\\")):
        return False
    norm = req_path.lower()
    if ".." in norm or "%2e%2e" in norm:
        return False
    # Le proxy vitrine est uniquement un relais public/mobile : bloquer admin et endpoints internes
    if norm.startswith(("/api/admin", "/api/internal", "/admin", "/__")):
        return False
    return True


@csrf_exempt
def api_backend_passthrough_proxy(request, subpath=""):
    """Relais transparent /health et /api/* (hors admin/interne) vers le backend admin."""
    req_path = request.path or ""
    if not _is_safe_proxy_path(req_path):
        return JsonResponse({"error": "forbidden_proxy_path"}, status=403)
    if request.method not in ("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"):
        return JsonResponse({"error": "method_not_allowed"}, status=405)
    qs = request.META.get("QUERY_STRING", "")
    if any(ch in qs for ch in ("\r", "\n", "\x00")):
        return JsonResponse({"error": "invalid_query"}, status=400)
    path_and_query = f"{req_path}?{qs}" if qs else req_path
    body_bytes = request.body if request.method in ("POST", "PUT", "PATCH", "DELETE") else None
    if body_bytes and len(body_bytes) > 5 * 1024 * 1024:
        return JsonResponse({"error": "payload_too_large"}, status=413)
    extra_headers = {}
    auth_hdr = (request.META.get("HTTP_AUTHORIZATION") or "").replace("\r", "").replace("\n", "")
    if auth_hdr:
        extra_headers["Authorization"] = auth_hdr
    ctype_hdr = (request.META.get("CONTENT_TYPE") or "").replace("\r", "").replace("\n", "")
    if ctype_hdr:
        extra_headers["Content-Type"] = ctype_hdr
    proxied = _proxy_admin_json(
        path_and_query,
        method=request.method,
        body_bytes=body_bytes,
        extra_headers=extra_headers,
    )
    if proxied is not None:
        return proxied
    return JsonResponse({"error": "backend_unreachable"}, status=503)


def media_backend_passthrough_proxy(request, subpath=""):
    """Relais binaire transparent /media/* vers le backend admin (images actualites, portraits, pieces)."""
    req_path = request.path or ""
    if not req_path.startswith("/media/") or not _is_safe_proxy_path(req_path):
        return HttpResponse(status=403)
    qs = request.META.get("QUERY_STRING", "")
    if any(ch in qs for ch in ("\r", "\n", "\x00")):
        return HttpResponse(status=400)
    path_and_query = f"{req_path}?{qs}" if qs else req_path
    for base in _candidate_admin_bases():
        url = f"{base}{path_and_query}"
        req = urllib.request.Request(url, method="GET")
        try:
            with urllib.request.urlopen(req, timeout=8) as resp:
                raw = resp.read()
                ctype = resp.headers.get("Content-Type", "application/octet-stream")
                http_resp = HttpResponse(raw, status=resp.status, content_type=ctype)
                http_resp["Access-Control-Allow-Origin"] = "*"
                http_resp["Cross-Origin-Resource-Policy"] = "cross-origin"
                http_resp["Cache-Control"] = "public, max-age=3600"
                return http_resp
        except urllib.error.HTTPError as exc:
            return HttpResponse(status=exc.code)
        except (urllib.error.URLError, TimeoutError, OSError):
            continue
    return HttpResponse(status=503)


@csrf_exempt
def api_public_metiers_proxy(request):
    """Relais interne GET/POST vers /api/public/metiers/ du backend admin BABIFIX."""
    if request.method not in ("GET", "POST"):
        return JsonResponse({"error": "method_not_allowed"}, status=405)

    body_bytes = (request.body or b"{}") if request.method == "POST" else None
    proxied = _proxy_admin_json("/api/public/metiers/", method=request.method, body_bytes=body_bytes)
    if proxied is not None:
        return proxied

    if request.method == "GET":
        return JsonResponse({"metiers": [], "seuil": 5, "offline": True})
    return JsonResponse(
        {"ok": False, "error": "Service temporairement indisponible. Réessayez bientôt."},
        status=503,
    )


def api_public_search_proxy(request):
    """Relais interne GET vers /api/public/search/ du backend admin BABIFIX."""
    if request.method != "GET":
        return JsonResponse({"error": "method_not_allowed"}, status=405)
    from urllib.parse import urlencode
    import unicodedata
    q = (request.GET.get("q") or "").strip()[:120]
    qs = f"?{urlencode({'q': q})}" if q else ""
    proxied = _proxy_admin_json(f"/api/public/search/{qs}", method="GET")
    if proxied is not None and proxied.status_code < 400:
        return proxied

    def _norm(txt):
        return "".join(
            ch for ch in unicodedata.normalize("NFD", str(txt or ""))
            if unicodedata.category(ch) != "Mn"
        ).lower()

    nq = _norm(q)
    cat_payload = fetch_admin_public_categories()
    raw_cats = cat_payload.get("categories") if isinstance(cat_payload, dict) else []
    matches = []
    if isinstance(raw_cats, list):
        for c in raw_cats:
            if not isinstance(c, dict):
                continue
            hay = _norm(f"{c.get('nom', '')} {c.get('description', '')}")
            if not nq or nq in hay:
                matches.append({
                    "id": c.get("id"),
                    "nom": c.get("nom", ""),
                    "description": c.get("description", ""),
                    "regime_kyc": c.get("regime_kyc", ""),
                })
    return JsonResponse({
        "query": q,
        "categories": matches[:12],
        "providers": [],
        "supplies": [],
        "suggest_missing_url": "/proposer-metier/",
        "offline": proxied is None,
    })


def services_index(request):
    """Annuaire SEO des metiers et communes couverts par BABIFIX en Cote d'Ivoire."""
    from .seo_catalog import (
        SEO_TRADES,
        SEO_ZONES,
        build_services_index_jsonld,
        canonical_base_url,
    )

    canon_base = canonical_base_url(request)
    return render(
        request,
        "vitrine/services_index.html",
        {
            "active_page": "services",
            "page_title": "Tous nos services a domicile en Cote d'Ivoire · BABIFIX",
            "meta_description": (
                "Decouvrez tous les metiers BABIFIX en Cote d'Ivoire : plombier, electricien, "
                "climatisation, serrurier, menage, nounou verifiee et plus a Abidjan, Cocody, Marcory, Plateau et Yopougon."
            ),
            "canonical_url": f"{canon_base}/services/",
            "canonical_base": canon_base,
            "seo_trades": SEO_TRADES,
            "seo_zones": SEO_ZONES,
            "page_jsonld": mark_safe(build_services_index_jsonld(canon_base)),
        },
    )


def _render_service_seo(request, trade_slug: str, zone_slug: str = ""):
    from .seo_catalog import (
        SEO_TRADES,
        SEO_ZONES,
        TRADES_BY_SLUG,
        ZONES_BY_SLUG,
        build_service_jsonld,
        canonical_base_url,
    )

    trade = TRADES_BY_SLUG.get((trade_slug or "").strip().lower())
    if not trade:
        return _render_vitrine_error(request, 404)

    zone = None
    if zone_slug:
        zone = ZONES_BY_SLUG.get(zone_slug.strip().lower())
        if not zone:
            return _render_vitrine_error(request, 404)

    canon_base = canonical_base_url(request)
    place = zone["name"] if zone else "Abidjan et Cote d'Ivoire"
    if zone:
        title = f"{trade['artisan_label']} a {zone['name']} · Devis & Sequestre · BABIFIX"
        meta_desc = (
            f"Besoin d'un {trade['artisan_label'].lower()} a {zone['name']} "
            f"({', '.join(zone['quartiers'][:3])}) ? Artisans CNI verifies, devis ecrit clair "
            f"et paiement securise Mobile Money sur BABIFIX."
        )
        canonical_url = f"{canon_base}/services/{trade['slug']}/{zone['slug']}/"
        h1 = f"{trade['artisan_label']} a {zone['name']}"
    else:
        title = f"{trade['name']} a domicile en Cote d'Ivoire ({trade['artisan_label']}) · BABIFIX"
        meta_desc = (
            f"Trouvez un {trade['artisan_label'].lower()} a Abidjan et en Cote d'Ivoire. "
            f"{trade['hero_subtitle']}"
        )[:160]
        canonical_url = f"{canon_base}/services/{trade['slug']}/"
        h1 = f"{trade['name']} a domicile en Cote d'Ivoire"

    related_trades = [
        TRADES_BY_SLUG[s] for s in trade.get("related_slugs", []) if s in TRADES_BY_SLUG
    ]
    nearby_zones = (
        [ZONES_BY_SLUG[s] for s in zone.get("nearby_slugs", []) if s in ZONES_BY_SLUG]
        if zone
        else SEO_ZONES[:6]
    )

    return render(
        request,
        "vitrine/service_landing.html",
        {
            "active_page": "services",
            "page_title": title,
            "meta_description": meta_desc,
            "canonical_url": canonical_url,
            "canonical_base": canon_base,
            "h1_title": h1,
            "place_label": place,
            "trade": trade,
            "zone": zone,
            "all_zones": SEO_ZONES,
            "nearby_zones": nearby_zones,
            "related_trades": related_trades,
            "page_jsonld": mark_safe(build_service_jsonld(canon_base, trade, zone)),
        },
    )


def service_detail(request, trade_slug: str):
    return _render_service_seo(request, trade_slug, "")


def service_local_detail(request, trade_slug: str, zone_slug: str):
    return _render_service_seo(request, trade_slug, zone_slug)


def robots_txt(request):
    """Indique aux moteurs de recherche quoi explorer + l'emplacement du sitemap."""
    from .seo_catalog import canonical_base_url

    base = canonical_base_url(request)
    lines = [
        "User-agent: *",
        "Allow: /",
        "Disallow: /api/",
        "Disallow: /admin/",
        "Disallow: /erreur/",
        f"Sitemap: {base}/sitemap.xml",
    ]
    return HttpResponse("\n".join(lines) + "\n", content_type="text/plain")


def sitemap_xml(request):
    """Plan du site SEO complet (pages principales + metiers + pages locales communes CI)."""
    from .seo_catalog import SEO_TRADES, SEO_ZONES, canonical_base_url, sitemap_lastmod_iso

    base = canonical_base_url(request)
    lastmod = sitemap_lastmod_iso()
    entries = [
        ("/", "1.0", "daily"),
        ("/services/", "0.95", "weekly"),
        ("/telecharger-app-client", "0.85", "weekly"),
        ("/devenir-prestataire", "0.85", "weekly"),
        ("/creer-un-compte", "0.70", "monthly"),
        ("/proposer-metier/", "0.65", "weekly"),
        ("/cgu/", "0.30", "yearly"),
        ("/confidentialite/", "0.30", "yearly"),
        ("/mentions-legales/", "0.30", "yearly"),
        ("/politique-cookies/", "0.30", "yearly"),
    ]
    for trade in SEO_TRADES:
        entries.append((f"/services/{trade['slug']}/", "0.90", "weekly"))
        for zone in SEO_ZONES:
            entries.append(
                (f"/services/{trade['slug']}/{zone['slug']}/", zone["priority"], "weekly")
            )

    items = "".join(
        f"<url><loc>{base}{path}</loc><lastmod>{lastmod}</lastmod>"
        f"<changefreq>{freq}</changefreq><priority>{prio}</priority></url>"
        for path, prio, freq in entries
    )
    xml = (
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'
        + items
        + "</urlset>"
    )
    return HttpResponse(xml, content_type="application/xml")


@require_GET
def vitrine_healthz(request):
    """Healthcheck local Vitrine sans dependance reseau Admin."""
    from django.db import connection

    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1")
        return JsonResponse({"status": "ok", "service": "vitrine"})
    except Exception:
        return JsonResponse({"status": "error", "service": "vitrine"}, status=503)
