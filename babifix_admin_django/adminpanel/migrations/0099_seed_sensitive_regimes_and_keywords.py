"""Pre-remplit regime_kyc, groupe, search_keywords, registration_questions et
template_exigences pour les metiers sensibles et les principaux univers.

Migration de donnees additive et idempotente : n'ecrase jamais une configuration
deja personnalisee par l'administrateur.
"""
from __future__ import annotations

import unicodedata

from django.db import migrations


def _norm(s: str) -> str:
    s = unicodedata.normalize("NFKD", s or "")
    s = "".join(c for c in s if not unicodedata.combining(c))
    return s.lower()


SENSITIVE_KEYWORDS = (
    "nounou",
    "garde",
    "babysit",
    "enfant",
    "creche",
    "personne agee",
    "senior",
    "auxiliaire",
    "aide a domicile",
    "aide domicile",
    "garde-malade",
    "garde malade",
    "chauffeur",
    "coursier",
    "livreur",
    "soutien scolaire",
    "repetit",
    "professeur",
    "gouvernante",
)

GROUP_RULES: list[tuple[str, tuple[str, ...]]] = [
    ("Aide & Domicile", ("nounou", "garde", "babysit", "enfant", "senior", "personne agee", "auxiliaire", "menage", "repassage", "nettoyage", "lessive", "cuisin", "jardin", "piscine", "gouvernante", "soutien scolaire", "repetit")),
    ("Depannage & Fluides", ("plomb", "electr", "clim", "froid", "frigo", "electromenag", "serrur", "vitrer", "depannage", "sanitaire", "chauffe-eau", "groupe electrogene", "onduleur", "solaire")),
    ("BTP & Renovation", ("peintr", "carrel", "macon", "menuis", "charpent", "toitur", "etanche", "ferron", "soudur", "placo", "faux plafond", "ferraill", "architecture", "bricol", "alu", "baie vitree", "staff")),
    ("Auto & Mobilite", ("mecani", "auto", "moto", "climatisation auto", "lavage auto", "toli", "carross", "pneu", "depanneuse", "chauffeur", "coursier", "livreur")),
    ("Tech & Bureautique", ("informati", "pc", "ordinateur", "telephon", "reseau", "wifi", "camera", "videosurveillance", "alarme", "domotique", "antenne", "imprimante")),
    ("Beaute & Bien-etre", ("coiff", "tresse", "barbi", "maquill", "esthet", "manucur", "pedicur", "massag", "bien-etre", "sport", "coach")),
    ("Evenements & Artisanat", ("traiteur", "decor", "photo", "video", "sono", "dj", "tapisser", "coutur", "tailleur", "cordon", "evenement")),
]

SEARCH_KEYWORD_SEEDS: list[tuple[str, str]] = [
    ("plomb", "fuite, robinet, evier, lavabo, wc, toilette, canalisation, debouchage, tuyau, eau"),
    ("electr", "panne courant, disjoncteur, prise, interrupteur, tableau electrique, luminaire, court-circuit"),
    ("clim", "climatiseur, split, froid, gaz clim, recharge clim, entretien split, eau qui coule"),
    ("peintr", "mur, facade, enduit, rouleau, peinture interieure, ravalement, plafond"),
    ("carrel", "carreau, sol, faience, dalle, plinthe, joint carreau, salle de bain"),
    ("menage", "nettoyage, grand menage, bureau, appartement, repassage, lavage vitre"),
    ("nounou", "garde enfant, babysitter, creche domicile, sortie ecole, nourrice, bebe"),
    ("garde", "enfant, babysitter, personne agee, aide domicile, surveillance"),
    ("chauffeur", "conduite, voiture privee, trajet, abidjan, deplacement, vtc"),
    ("mecani", "voiture, panne moteur, vidange, frein, batterie, diagnostic auto"),
    ("serrur", "porte bloquee, cle cassee, serrure, blindage, cadenas, ouverture porte"),
    ("macon", "mur, beton, construction, fissure, chape, brique, fondation"),
    ("menuis", "porte bois, placard, armoire, cuisine bois, fenetre, reparation meuble"),
    ("informat", "ordinateur, pc lent, virus, wifi, imprimante, installation logiciel"),
    ("coiff", "tresse, coupe, brushing, barbe, domicile, coloration"),
]

SENSITIVE_BOOKING_TEMPLATES: list[tuple[str, str, list[dict]]] = [
    (
        "nounou",
        "FORFAIT",
        [
            {"key": "nb_enfants", "label": "Nombre d'enfants", "type": "number", "required": True},
            {"key": "ages_enfants", "label": "Ages des enfants", "type": "text", "hint": "Ex. 18 mois et 6 ans", "required": True},
            {"key": "horaires_garde", "label": "Horaires souhaites", "type": "text", "hint": "Ex. Lun-Ven 07h30 a 18h30"},
            {"key": "besoins_specifiques", "label": "Allergies, repas ou soins particuliers ?", "type": "text"},
            {"key": "deplacement_nuit", "label": "Garde en soiree ou weekend ?", "type": "bool"},
        ],
    ),
    (
        "personne agee",
        "FORFAIT",
        [
            {"key": "niveau_autonomie", "label": "Niveau d'autonomie", "type": "select", "choices": ["Autonome", "Aide partielle", "Aide complete"], "required": True},
            {"key": "frequence", "label": "Frequence", "type": "select", "choices": ["Ponctuel", "Quotidien jour", "Nuit", "24h/24"]},
            {"key": "consignes_medicales", "label": "Consignes ou traitements a surveiller", "type": "text"},
        ],
    ),
    (
        "chauffeur",
        "FORFAIT",
        [
            {"key": "duree_mission", "label": "Duree souhaite", "type": "select", "choices": ["Demi-journee", "Journee", "Semaine", "Mensuel"], "required": True},
            {"key": "vehicule_client", "label": "Conduite du vehicule du client ?", "type": "bool"},
            {"key": "type_boite", "label": "Type de boite maitrise", "type": "select", "choices": ["Automatique", "Manuelle", "Les deux"]},
            {"key": "zone_trajets", "label": "Zones / communes de deplacement", "type": "text", "hint": "Ex. Cocody, Plateau, Aeroport"},
        ],
    ),
]

REGISTRATION_QUESTIONS_BY_GROUP: dict[str, list[dict]] = {
    "Aide & Domicile": [
        {"key": "experience_familles", "label": "Anciennete aupres de familles / particuliers", "type": "select", "choices": ["Moins d'1 an", "1 a 3 ans", "3 a 5 ans", "Plus de 5 ans"]},
        {"key": "langues_parlees", "label": "Langues parlees couramment", "type": "text", "hint": "Ex. Francais, Dioula, Baoule, Anglais"},
        {"key": "secourisme_hygiene", "label": "Formation premiers secours ou puericulture / hygiene ?", "type": "bool"},
    ],
    "Depannage & Fluides": [
        {"key": "outillage_pro", "label": "Disposez-vous d'un outillage complet d'intervention ?", "type": "bool"},
        {"key": "interventions_urgence", "label": "Disponible pour depannages urgents (soir / weekend) ?", "type": "bool"},
        {"key": "type_chantiers", "label": "Specialite dominante", "type": "select", "choices": ["Depannage rapide", "Installation neuve", "Maintenance immeubles & bureaux"]},
    ],
    "BTP & Renovation": [
        {"key": "equipe_chantier", "label": "Intervenez-vous seul ou avec une equipe ?", "type": "select", "choices": ["Artisan independant", "Chef d'equipe (2-5 ouvriers)", "Entreprise structuree"]},
        {"key": "devis_metric", "label": "Realisez-vous des releves metriques sur place ?", "type": "bool"},
    ],
    "Auto & Mobilite": [
        {"key": "permis_valide", "label": "Categorie de permis ou qualification mecanique", "type": "text", "hint": "Ex. Permis BCDE, Diagnostic OBD2"},
        {"key": "intervention_domicile", "label": "Deplacement sur le lieu de panne ?", "type": "bool"},
    ],
}


def seed_forward(apps, schema_editor):
    Category = apps.get_model("adminpanel", "Category")
    for cat in Category.objects.all():
        n = _norm(cat.nom)
        updated_fields = []

        # 1. Regime KYC sensible
        if any(kw in n for kw in SENSITIVE_KEYWORDS):
            if cat.regime_kyc != "SENSIBLE_CASIER":
                cat.regime_kyc = "SENSIBLE_CASIER"
                updated_fields.append("regime_kyc")

        # 2. Groupe / Univers
        assigned_group = "Maison & Services"
        for grp_name, grp_kws in GROUP_RULES:
            if any(k in n for k in grp_kws):
                assigned_group = grp_name
                break
        if (not cat.groupe or cat.groupe == "Maison & BTP") and assigned_group:
            cat.groupe = assigned_group
            updated_fields.append("groupe")

        # 3. Mots-cles de recherche intelligents
        if not (cat.search_keywords or "").strip():
            matched_kws = [kws for needle, kws in SEARCH_KEYWORD_SEEDS if needle in n]
            if matched_kws:
                cat.search_keywords = ", ".join(matched_kws)
                updated_fields.append("search_keywords")

        # 4. Template de demande client pour metiers sensibles si encore vide
        if not (cat.template_exigences or []):
            for needle, profil, tpl in SENSITIVE_BOOKING_TEMPLATES:
                if needle in n or (needle == "nounou" and ("garde" in n and "enfant" in n)):
                    cat.profil_devis = profil
                    cat.template_exigences = tpl
                    updated_fields.extend(["profil_devis", "template_exigences"])
                    break

        # 5. Questions d'inscription specifiques au metier si encore vides
        if not (cat.registration_questions or []):
            grp_qs = REGISTRATION_QUESTIONS_BY_GROUP.get(assigned_group)
            if grp_qs:
                cat.registration_questions = grp_qs
                updated_fields.append("registration_questions")

        if updated_fields:
            cat.save(update_fields=list(dict.fromkeys(updated_fields)))


def seed_reverse(apps, schema_editor):
    Category = apps.get_model("adminpanel", "Category")
    Category.objects.all().update(regime_kyc="STANDARD_TERRAIN")


class Migration(migrations.Migration):
    dependencies = [
        ("adminpanel", "0098_category_groupe_category_regime_kyc_and_more"),
    ]

    operations = [
        migrations.RunPython(seed_forward, seed_reverse),
    ]
