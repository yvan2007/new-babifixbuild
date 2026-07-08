"""Pré-remplit profil_devis + template_exigences pour chaque catégorie.

Migration de DONNÉES, 100% additive et idempotente :
- On ne modifie une catégorie QUE si son `template_exigences` est encore vide
  (donc jamais on n'écrase une config faite à la main dans l'admin).
- Le matching se fait par mot-clé normalisé (sans accents/casse) → robuste aux
  variantes de nom ("Peinture & Ravalement" ↔ "peinture").
- Reversible : le retour vide simplement les catégories qu'on avait remplies
  (best-effort ; on ne casse rien).
"""
from __future__ import annotations

import unicodedata

from django.db import migrations


def _norm(s: str) -> str:
    s = unicodedata.normalize("NFKD", s or "")
    s = "".join(c for c in s if not unicodedata.combining(c))
    return s.lower()


# Chaque entrée : mot-clé → (profil_devis, [questions]).
# Types supportés par l'app : text | number | select | bool.
SEEDS: list[tuple[str, str, list[dict]]] = [
    (
        # ⚠️ AVANT "menage" : "menage" est un sous-mot de "demenagement".
        "demenagement",
        "FORFAIT",
        [
            {"key": "type_logement", "label": "Logement de départ", "type": "select",
             "choices": ["Studio", "2 pièces", "3 pièces", "4 pièces et +", "Bureau"], "required": True},
            {"key": "etage_depart", "label": "Étage de départ", "type": "number"},
            {"key": "ascenseur", "label": "Ascenseur disponible ?", "type": "bool"},
            {"key": "distance", "label": "Distance approximative", "type": "text", "hint": "Ex. même quartier, 15 km"},
            {"key": "emballage", "label": "Emballage à prévoir par le prestataire ?", "type": "bool"},
        ],
    ),
    (
        "menage",
        "FORFAIT",
        [
            {"key": "type_logement", "label": "Type de logement", "type": "select",
             "choices": ["Studio", "Appartement", "Villa", "Bureau", "Autre"], "required": True},
            {"key": "nb_pieces", "label": "Nombre de pièces", "type": "number", "required": True},
            {"key": "surface_m2", "label": "Surface approximative", "type": "number", "unit": "m²"},
            {"key": "frequence", "label": "Fréquence", "type": "select",
             "choices": ["Ponctuel", "Hebdomadaire", "Bimensuel", "Mensuel"]},
            {"key": "vitres", "label": "Nettoyage des vitres inclus ?", "type": "bool"},
            {"key": "produits_fournis", "label": "Le prestataire fournit les produits ?", "type": "bool"},
        ],
    ),
    (
        "plomberie",
        "DIAGNOSTIC",
        [
            {"key": "type_probleme", "label": "Nature du problème", "type": "select",
             "choices": ["Fuite", "Bouchage", "Installation", "Remplacement", "Autre"], "required": True},
            {"key": "localisation", "label": "Où ?", "type": "select",
             "choices": ["Cuisine", "Salle de bain", "WC", "Extérieur", "Autre"]},
            {"key": "depuis_quand", "label": "Depuis quand ?", "type": "text", "hint": "Ex. 2 jours"},
            {"key": "eau_coupee", "label": "L'eau est-elle coupée ?", "type": "bool"},
            {"key": "urgent", "label": "Urgent ?", "type": "bool"},
        ],
    ),
    (
        "electricite",
        "DIAGNOSTIC",
        [
            {"key": "symptome", "label": "Symptôme", "type": "select",
             "choices": ["Panne totale", "Prise/interrupteur", "Disjoncteur saute", "Court-circuit", "Installation", "Autre"], "required": True},
            {"key": "piece", "label": "Pièce concernée", "type": "text", "hint": "Ex. cuisine, salon"},
            {"key": "depuis_quand", "label": "Depuis quand ?", "type": "text"},
            {"key": "danger", "label": "Danger visible (étincelle, odeur) ?", "type": "bool"},
        ],
    ),
    (
        "peinture",
        "SURFACE",
        [
            {"key": "surface_m2", "label": "Surface à peindre", "type": "number", "unit": "m²", "required": True},
            {"key": "nb_pieces", "label": "Nombre de pièces", "type": "number"},
            {"key": "emplacement", "label": "Intérieur ou extérieur ?", "type": "select",
             "choices": ["Intérieur", "Extérieur", "Les deux"], "required": True},
            {"key": "type_peinture", "label": "Type de finition", "type": "select",
             "choices": ["Mate", "Satinée", "Brillante", "Laquée"]},
            {"key": "etat_mur", "label": "État des murs", "type": "select",
             "choices": ["Neufs", "Bon état", "À préparer (fissures, humidité)"]},
            {"key": "fournir_peinture", "label": "Le prestataire fournit la peinture ?", "type": "bool"},
        ],
    ),
    (
        "jardin",
        "FORFAIT",
        [
            {"key": "type_travail", "label": "Type de travail", "type": "select",
             "choices": ["Tonte", "Taille de haie", "Débroussaillage", "Entretien complet", "Autre"], "required": True},
            {"key": "surface_m2", "label": "Surface du jardin", "type": "number", "unit": "m²"},
            {"key": "frequence", "label": "Fréquence", "type": "select",
             "choices": ["Ponctuel", "Hebdomadaire", "Mensuel"]},
            {"key": "evacuation", "label": "Évacuation des déchets verts ?", "type": "bool"},
        ],
    ),
    (
        "cuisine",
        "FORFAIT",
        [
            {"key": "type_evenement", "label": "Type d'événement", "type": "select",
             "choices": ["Repas familial", "Anniversaire", "Mariage", "Réception pro", "Autre"], "required": True},
            {"key": "nb_personnes", "label": "Nombre de personnes", "type": "number", "required": True},
            {"key": "type_menu", "label": "Type de menu", "type": "text", "hint": "Ex. ivoirien, grillades, buffet"},
            {"key": "service", "label": "Sur place ou livraison ?", "type": "select",
             "choices": ["Sur place", "Livraison", "À emporter"]},
        ],
    ),
    (
        "menuiserie",
        "STANDARD",
        [
            {"key": "type_travail", "label": "Type de travail", "type": "select",
             "choices": ["Pose", "Réparation", "Fabrication sur mesure", "Autre"], "required": True},
            {"key": "materiau", "label": "Matériau", "type": "select",
             "choices": ["Bois", "Alu", "PVC", "Autre"]},
            {"key": "dimensions", "label": "Dimensions (si connues)", "type": "text", "hint": "Ex. 200 x 90 cm"},
        ],
    ),
    (
        "climatisation",
        "DIAGNOSTIC",
        [
            {"key": "type_intervention", "label": "Intervention", "type": "select",
             "choices": ["Installation", "Entretien / recharge", "Panne", "Désinstallation"], "required": True},
            {"key": "nb_splits", "label": "Nombre de climatiseurs", "type": "number"},
            {"key": "puissance", "label": "Puissance (si connue)", "type": "text", "hint": "Ex. 1.5 CV, 12000 BTU"},
            {"key": "symptome", "label": "Symptôme (si panne)", "type": "text"},
        ],
    ),
    (
        "multiservice",
        "STANDARD",
        [
            {"key": "nature", "label": "Nature du besoin", "type": "text", "required": True,
             "hint": "Décrivez brièvement le travail attendu"},
        ],
    ),
]


def seed(apps, schema_editor):
    Category = apps.get_model("adminpanel", "Category")
    for cat in Category.objects.all():
        # Ne jamais écraser une config existante.
        if cat.template_exigences:
            continue
        n = _norm(cat.nom)
        for keyword, profil, template in SEEDS:
            if keyword in n:
                cat.profil_devis = profil
                cat.template_exigences = template
                cat.save(update_fields=["profil_devis", "template_exigences"])
                break


def unseed(apps, schema_editor):
    # Best-effort : on revide uniquement les catégories dont le template
    # correspond exactement à un de nos seeds (on ne touche pas au manuel).
    Category = apps.get_model("adminpanel", "Category")
    seed_templates = [t for _, _, t in SEEDS]
    for cat in Category.objects.all():
        if cat.template_exigences in seed_templates:
            cat.template_exigences = []
            cat.profil_devis = "STANDARD"
            cat.save(update_fields=["profil_devis", "template_exigences"])


class Migration(migrations.Migration):

    dependencies = [
        ("adminpanel", "0083_reservation_reponses_exigences"),
    ]

    operations = [
        migrations.RunPython(seed, unseed),
    ]
