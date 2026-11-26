"""Catalogue Service : Suggestions de fournitures, kits 1-clic et profils UI devis par metier BABIFIX.

Permet a tout prestataire (BTP technique, services a la personne comme Nounou/Soutien,
maison/forfait, surface) de rediger un devis clair en moins de 30 secondes sans jargon :
- Suggestions 1-clic de lignes frequentes adaptees au metier.
- Kits complets 1-clic (diagnostic + lignes pre-remplies, seul le prix reste ajustable).
- Profil UI adaptatif (`DEVIS_UI_PROFILES`) qui masque les champs techniques inutiles
  (ex. pas de "Fournitures" ni "Diagnostic technique" pour une Nounou ou un professeur).
"""

from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

# Catalogues de reference par code icone_slug ou alias metier
CATALOGUE_DATA: Dict[str, List[Dict[str, Any]]] = {
    # Plomberie & Sanitaire
    "goutte": [
        {"type_ligne": "FOURNITURE", "nom": "Tuyau PVC O32 mm", "unite": "ml", "prix": 1500, "marque": "Nacoplast"},
        {"type_ligne": "FOURNITURE", "nom": "Tuyau PVC O40 mm", "unite": "ml", "prix": 2000, "marque": "Nacoplast"},
        {"type_ligne": "FOURNITURE", "nom": "Tuyau PVC O100 mm evacuation", "unite": "ml", "prix": 3500, "marque": "Nacoplast"},
        {"type_ligne": "FOURNITURE", "nom": "Coude PVC O32 / O40", "unite": "u", "prix": 800, "marque": ""},
        {"type_ligne": "FOURNITURE", "nom": "Colle PVC grand pot", "unite": "u", "prix": 2500, "marque": "Tangit"},
        {"type_ligne": "FOURNITURE", "nom": "Robinet melangeur lavabo", "unite": "u", "prix": 14000, "marque": "Grohe"},
        {"type_ligne": "FOURNITURE", "nom": "Flexible tresse inox douche", "unite": "u", "prix": 4500, "marque": ""},
        {"type_ligne": "FOURNITURE", "nom": "Siphon evier / lavabo PVC", "unite": "u", "prix": 3000, "marque": ""},
        {"type_ligne": "FOURNITURE", "nom": "Joint silicone sanitaire anti-moisissure", "unite": "u", "prix": 2500, "marque": "Sika"},
        {"type_ligne": "FOURNITURE", "nom": "Mecanisme complet chasse d'eau", "unite": "u", "prix": 18000, "marque": "Siamp"},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Diagnostic recherche de fuite", "unite": "forfait", "prix": 8000, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Pose robinet / mitigeur", "unite": "u", "prix": 7000, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Debouchage canalisation wc ou lavabo", "unite": "forfait", "prix": 12000, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Remplacement tuyauterie et raccordement", "unite": "ml", "prix": 4000, "marque": ""},
        {"type_ligne": "DEPLACEMENT", "nom": "Deplacement urbain zone Abidjan", "unite": "forfait", "prix": 3000, "marque": ""},
    ],
    # Electricite Batiment
    "eclair": [
        {"type_ligne": "FOURNITURE", "nom": "Cable cuivre TH 2.5 mm2", "unite": "ml", "prix": 600, "marque": ""},
        {"type_ligne": "FOURNITURE", "nom": "Cable cuivre TH 1.5 mm2", "unite": "ml", "prix": 400, "marque": ""},
        {"type_ligne": "FOURNITURE", "nom": "Gaine annelee ICTA O20", "unite": "ml", "prix": 350, "marque": ""},
        {"type_ligne": "FOURNITURE", "nom": "Disjoncteur divisionnaire 16A / 20A", "unite": "u", "prix": 4500, "marque": "Schneider"},
        {"type_ligne": "FOURNITURE", "nom": "Disjoncteur differentiel 30mA 40A", "unite": "u", "prix": 22000, "marque": "Legrand"},
        {"type_ligne": "FOURNITURE", "nom": "Prise de courant 2P+T avec terre", "unite": "u", "prix": 1800, "marque": "Legrand"},
        {"type_ligne": "FOURNITURE", "nom": "Interrupteur simple va-et-vient", "unite": "u", "prix": 1500, "marque": "Legrand"},
        {"type_ligne": "FOURNITURE", "nom": "Spot encastre LED 12W", "unite": "u", "prix": 3500, "marque": ""},
        {"type_ligne": "FOURNITURE", "nom": "Tableau modulaire 2 rangees", "unite": "u", "prix": 15000, "marque": "Schneider"},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Diagnostic securite et recherche court-circuit", "unite": "forfait", "prix": 10000, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Pose et raccordement appareillage", "unite": "u", "prix": 3500, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Cablage sous gaine par circuit", "unite": "ml", "prix": 2000, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Mise aux normes tableau electrique", "unite": "forfait", "prix": 35000, "marque": ""},
        {"type_ligne": "DEPLACEMENT", "nom": "Deplacement urgence electrique", "unite": "forfait", "prix": 3500, "marque": ""},
    ],
    # Climatisation & Froid
    "climatisation": [
        {"type_ligne": "FOURNITURE", "nom": "Charge gaz refrigerant R410A", "unite": "kg", "prix": 12000, "marque": "Honeywell"},
        {"type_ligne": "FOURNITURE", "nom": "Charge gaz refrigerant ecologique R32", "unite": "kg", "prix": 15000, "marque": ""},
        {"type_ligne": "FOURNITURE", "nom": "Kit liaisons frigorifiques cuivre isole", "unite": "ml", "prix": 7000, "marque": ""},
        {"type_ligne": "FOURNITURE", "nom": "Support mural groupe exterieur robuste", "unite": "u", "prix": 8500, "marque": ""},
        {"type_ligne": "FOURNITURE", "nom": "Disjoncteur courbe D pour compresseur", "unite": "u", "prix": 6000, "marque": "Schneider"},
        {"type_ligne": "FOURNITURE", "nom": "Tuyau d'evacuation condensat cristal", "unite": "ml", "prix": 1000, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Entretien complet split (nettoyage vapeur + antibacterien)", "unite": "u", "prix": 15000, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Diagnostic pression gaz et fuite circuit froid", "unite": "forfait", "prix": 8000, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Pose et mise en service split", "unite": "u", "prix": 30000, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Depose soignee ancien groupe split", "unite": "u", "prix": 15000, "marque": ""},
        {"type_ligne": "DEPLACEMENT", "nom": "Deplacement technicien frigoriste", "unite": "forfait", "prix": 3000, "marque": ""},
    ],
    # Serrurerie & Securite
    "cle": [
        {"type_ligne": "FOURNITURE", "nom": "Cylindre canon securite haute protection 3 cles", "unite": "u", "prix": 9000, "marque": "Vachette"},
        {"type_ligne": "FOURNITURE", "nom": "Serrure encastree a larder 3 points", "unite": "u", "prix": 22000, "marque": "Bricard"},
        {"type_ligne": "FOURNITURE", "nom": "Verrou applique cylindre double", "unite": "u", "prix": 11000, "marque": ""},
        {"type_ligne": "FOURNITURE", "nom": "Poignee inox blindee de securite", "unite": "u", "prix": 7500, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Ouverture de porte claquee sans casse", "unite": "forfait", "prix": 15000, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Extraction de cle cassee et reglage barillet", "unite": "forfait", "prix": 10000, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Remplacement et ajustement serrure", "unite": "u", "prix": 10000, "marque": ""},
        {"type_ligne": "DEPLACEMENT", "nom": "Deplacement urgence serrurerie 24/7", "unite": "forfait", "prix": 5000, "marque": ""},
    ],
    # Peinture & Revetement mural
    "pinceau": [
        {"type_ligne": "FOURNITURE", "nom": "Peinture acrylique mate blanche seau 15L", "unite": "u", "prix": 26000, "marque": "Seigneurie"},
        {"type_ligne": "FOURNITURE", "nom": "Peinture satin velours teintable 15L", "unite": "u", "prix": 34000, "marque": "Ripolin"},
        {"type_ligne": "FOURNITURE", "nom": "Enduit de rebouchage et lissage sac 25kg", "unite": "u", "prix": 9500, "marque": "Toupret"},
        {"type_ligne": "FOURNITURE", "nom": "Impression primaire sous-couche 15L", "unite": "u", "prix": 22000, "marque": ""},
        {"type_ligne": "FOURNITURE", "nom": "Rouleaux, pinceaux et baches de protection", "unite": "forfait", "prix": 6500, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Preparation des fonds (rebouchage, poncage)", "unite": "m2", "prix": 1200, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Application 2 couches peinture murale interieure", "unite": "m2", "prix": 2200, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Peinture complete d'une chambre (forfait)", "unite": "forfait", "prix": 35000, "marque": ""},
        {"type_ligne": "DEPLACEMENT", "nom": "Acheminement materiel et deplacement", "unite": "forfait", "prix": 3000, "marque": ""},
    ],
    # Carrelage & Faience
    "carrelage": [
        {"type_ligne": "FOURNITURE", "nom": "Carreaux gres cerame poli 60x60", "unite": "m2", "prix": 8500, "marque": ""},
        {"type_ligne": "FOURNITURE", "nom": "Faience murale salle de bain", "unite": "m2", "prix": 7000, "marque": ""},
        {"type_ligne": "FOURNITURE", "nom": "Ciment colle haute adherence sac 25kg", "unite": "u", "prix": 4500, "marque": "Cimaf"},
        {"type_ligne": "FOURNITURE", "nom": "Mortier a joint hydrofuge sac 5kg", "unite": "u", "prix": 3500, "marque": "Weber"},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Chape de nivellement et ragreage sol", "unite": "m2", "prix": 2500, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Pose collee carrelage au sol", "unite": "m2", "prix": 5000, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Pose faience murale et joints etanches", "unite": "m2", "prix": 6000, "marque": ""},
        {"type_ligne": "DEPLACEMENT", "nom": "Transport outillage coupe carrelage", "unite": "forfait", "prix": 3500, "marque": ""},
    ],
    # Menuiserie Bois & Alu
    "menuiserie": [
        {"type_ligne": "FOURNITURE", "nom": "Bloc porte interieure 83cm", "unite": "u", "prix": 38000, "marque": ""},
        {"type_ligne": "FOURNITURE", "nom": "Poignee et paumelles inox renforcees", "unite": "u", "prix": 6500, "marque": ""},
        {"type_ligne": "FOURNITURE", "nom": "Planche bois dur traite Iroko", "unite": "ml", "prix": 6500, "marque": ""},
        {"type_ligne": "FOURNITURE", "nom": "Colle a bois et visserie assortie", "unite": "forfait", "prix": 4000, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Rabotage et ajustement porte bloquante", "unite": "u", "prix": 8000, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Pose et calage bloc porte", "unite": "u", "prix": 15000, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Fabrication ou retouche placard sur-mesure", "unite": "forfait", "prix": 30000, "marque": ""},
        {"type_ligne": "DEPLACEMENT", "nom": "Deplacement atelier mobile", "unite": "forfait", "prix": 3000, "marque": ""},
    ],
    # Nettoyage & Menage
    "nettoyage": [
        {"type_ligne": "FOURNITURE", "nom": "Produits professionnels de desinfection sols & vitres", "unite": "forfait", "prix": 5000, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Menage complet appartement 2 a 3 pieces", "unite": "forfait", "prix": 15000, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Grand nettoyage villa ou fin de chantier", "unite": "forfait", "prix": 35000, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Shampouinage canape ou tapis tissu", "unite": "u", "prix": 15000, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Repassage et pliage linge (panier)", "unite": "forfait", "prix": 6000, "marque": ""},
    ],
    # Nounou & Garde d'enfants (Service a la personne - zero jargon BTP)
    "nounou": [
        {"type_ligne": "MAIN_OEUVRE", "nom": "Garde d'enfants a l'heure (1 a 2 enfants)", "unite": "heure", "prix": 2000, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Garde a la journee complete (8h - 18h)", "unite": "jour", "prix": 10000, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Baby-sitting soiree (4 heures)", "unite": "forfait", "prix": 10000, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Forfait garde reguliere a la semaine (5 jours)", "unite": "semaine", "prix": 35000, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Forfait garde mensuelle (lundi au vendredi)", "unite": "mois", "prix": 90000, "marque": ""},
        {"type_ligne": "AUTRE", "nom": "Supplement enfant additionnel ou aide aux devoirs", "unite": "forfait", "prix": 3000, "marque": ""},
        {"type_ligne": "AUTRE", "nom": "Majoration garde de nuit ou week-end / transport retour", "unite": "forfait", "prix": 4000, "marque": ""},
    ],
    # Soutien scolaire & Cours particuliers
    "soutien": [
        {"type_ligne": "MAIN_OEUVRE", "nom": "Seance de soutien scolaire individuel (2h)", "unite": "seance", "prix": 8000, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Pack suivi hebdomadaire (3 seances de 2h)", "unite": "semaine", "prix": 20000, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Forfait mensuel accompagnement examens (BEPC / BAC)", "unite": "mois", "prix": 65000, "marque": ""},
        {"type_ligne": "AUTRE", "nom": "Supports d'exercices et fiches de revision", "unite": "forfait", "prix": 3000, "marque": ""},
    ],
    # Electromenager
    "electromenager": [
        {"type_ligne": "MAIN_OEUVRE", "nom": "Diagnostic panne appareil electromenager", "unite": "forfait", "prix": 7000, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Reparation refrigerateur / congelateur", "unite": "forfait", "prix": 18000, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Reparation machine a laver / seche-linge", "unite": "forfait", "prix": 18000, "marque": ""},
        {"type_ligne": "FOURNITURE", "nom": "Piece detachee d'origine (thermostat / pompe / relais)", "unite": "u", "prix": 15000, "marque": ""},
        {"type_ligne": "FOURNITURE", "nom": "Recharge gaz frigorifique refrigerateur", "unite": "forfait", "prix": 15000, "marque": ""},
    ],
    # Maconnerie & Gros oeuvre leger
    "maconnerie": [
        {"type_ligne": "FOURNITURE", "nom": "Sac de ciment 50 kg CPJ 42.5", "unite": "sac", "prix": 4500, "marque": "Cimaf"},
        {"type_ligne": "FOURNITURE", "nom": "Sable et gravier (brouette / chargement)", "unite": "forfait", "prix": 12000, "marque": ""},
        {"type_ligne": "FOURNITURE", "nom": "Agglos / parpaings creux 15", "unite": "u", "prix": 400, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Rebouchage fissure et reprise enduit mur", "unite": "m2", "prix": 4500, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Montage mur ou cloison en agglos", "unite": "m2", "prix": 7000, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Chape ciment et finition lisse", "unite": "m2", "prix": 4000, "marque": ""},
    ],
    # Jardinage & Espaces verts
    "jardinage": [
        {"type_ligne": "MAIN_OEUVRE", "nom": "Tonte de pelouse et nettoyage jardin", "unite": "forfait", "prix": 15000, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Taille de haies et arbustes", "unite": "forfait", "prix": 12000, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Elagage arbre et evacuation des branches", "unite": "forfait", "prix": 25000, "marque": ""},
        {"type_ligne": "FOURNITURE", "nom": "Terreau, engrais ou sacs d'evacuation dechets verts", "unite": "forfait", "prix": 6000, "marque": ""},
    ],
    # Cuisine & Traiteur a domicile
    "cuisine": [
        {"type_ligne": "MAIN_OEUVRE", "nom": "Preparation repas familial a domicile (demi-journee)", "unite": "forfait", "prix": 15000, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Service chef a domicile pour reception (jusqu'a 15 pers.)", "unite": "forfait", "prix": 45000, "marque": ""},
        {"type_ligne": "FOURNITURE", "nom": "Budget courses et ingredients (sur justificatif)", "unite": "forfait", "prix": 25000, "marque": ""},
    ],
    # Demenagement & Manutention
    "demenagement": [
        {"type_ligne": "MAIN_OEUVRE", "nom": "Equipe manutention (chargement et dechargement)", "unite": "forfait", "prix": 30000, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Demontage et remontage meubles", "unite": "forfait", "prix": 15000, "marque": ""},
        {"type_ligne": "AUTRE", "nom": "Transport vehicule utilitaire / camionnette", "unite": "forfait", "prix": 35000, "marque": ""},
        {"type_ligne": "FOURNITURE", "nom": "Cartons, film etirable et ruban d'emballage", "unite": "forfait", "prix": 10000, "marque": ""},
    ],
    # Coiffure & Beaute a domicile
    "beaute": [
        {"type_ligne": "MAIN_OEUVRE", "nom": "Coiffure / tresses / brushing a domicile", "unite": "forfait", "prix": 12000, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Manucure / pedicure complete a domicile", "unite": "forfait", "prix": 10000, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Maquillage evenementiel", "unite": "forfait", "prix": 20000, "marque": ""},
        {"type_ligne": "FOURNITURE", "nom": "Meches / produits capillaires ou soin inclus", "unite": "forfait", "prix": 8000, "marque": ""},
    ],
    # Mecanique / Auto a domicile
    "auto": [
        {"type_ligne": "MAIN_OEUVRE", "nom": "Diagnostic valise electronique a domicile", "unite": "forfait", "prix": 12000, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Vidange moteur et remplacement filtres", "unite": "forfait", "prix": 15000, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Depannage batterie / demarrage sur place", "unite": "forfait", "prix": 10000, "marque": ""},
        {"type_ligne": "FOURNITURE", "nom": "Huile moteur synthetique + filtre a huile", "unite": "forfait", "prix": 25000, "marque": ""},
    ],
    # Informatique & Reseau Wi-Fi
    "informatique": [
        {"type_ligne": "MAIN_OEUVRE", "nom": "Diagnostic et depannage ordinateur PC / Mac", "unite": "forfait", "prix": 15000, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Installation routeur Wi-Fi / repetiteur fibre", "unite": "forfait", "prix": 15000, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Nettoyage virus, sauvegarde et reinstallation systeme", "unite": "forfait", "prix": 20000, "marque": ""},
        {"type_ligne": "FOURNITURE", "nom": "Cable reseau RJ45 / composant de remplacement", "unite": "u", "prix": 10000, "marque": ""},
    ],
    # Socle generique par defaut
    "generique": [
        {"type_ligne": "MAIN_OEUVRE", "nom": "Diagnostic preliminaire et evaluation", "unite": "forfait", "prix": 6000, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Prestation qualifiee a l'heure", "unite": "heure", "prix": 4000, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Forfait demi-journee", "unite": "forfait", "prix": 15000, "marque": ""},
        {"type_ligne": "MAIN_OEUVRE", "nom": "Forfait journee complete", "unite": "jour", "prix": 25000, "marque": ""},
    ],
}

UNITS_BY_CATEGORY: Dict[str, List[str]] = {
    "goutte": ["forfait", "u", "ml", "heure", "jour"],
    "eclair": ["forfait", "u", "ml", "point", "heure"],
    "climatisation": ["u", "forfait", "kg", "ml", "heure"],
    "cle": ["forfait", "u", "heure"],
    "pinceau": ["m2", "forfait", "u", "jour"],
    "carrelage": ["m2", "forfait", "sac", "u"],
    "menuiserie": ["forfait", "u", "ml", "m2", "heure"],
    "nettoyage": ["forfait", "heure", "jour", "m2", "u"],
    "nounou": ["heure", "jour", "semaine", "mois", "forfait"],
    "soutien": ["seance", "heure", "semaine", "mois", "forfait"],
    "electromenager": ["forfait", "u", "heure"],
    "maconnerie": ["m2", "forfait", "sac", "u", "jour"],
    "jardinage": ["forfait", "heure", "jour", "m2"],
    "cuisine": ["forfait", "jour", "heure", "pers"],
    "demenagement": ["forfait", "heure", "jour", "u"],
    "beaute": ["forfait", "heure", "u"],
    "auto": ["forfait", "u", "heure"],
    "informatique": ["forfait", "heure", "u"],
    "generique": ["forfait", "heure", "jour", "u", "m2"],
}

# Profils UI adaptatifs pour que la redaction du devis soit naturelle dans chaque metier
DEVIS_UI_PROFILES: Dict[str, Dict[str, Any]] = {
    "nounou": {
        "mode": "SERVICE_PERSONNE",
        "screen_subtitle": "Proposez votre tarif de garde en 2 clics",
        "section_summary_title": "Details de la garde",
        "diagnostic_label": "Organisation de la garde *",
        "diagnostic_hint": "Ex : Garde de 2 enfants de 8h a 18h, repas et aide aux devoirs inclus...",
        "show_fournitures": False,
        "show_diag_photos": False,
        "line_labels": {
            "MAIN_OEUVRE": "Garde / Forfait",
            "FOURNITURE": "Frais annexes",
            "AUTRE": "Option / Prime",
        },
        "empty_hint": "Choisissez un modele ci-dessus (heure, journee, mois) ou ajoutez un tarif.",
    },
    "soutien": {
        "mode": "SERVICE_PERSONNE",
        "screen_subtitle": "Proposez votre forfait de cours",
        "section_summary_title": "Programme et rythme",
        "diagnostic_label": "Objectif et matieres *",
        "diagnostic_hint": "Ex : Remise a niveau Maths & Physique classe de 3e, 2 seances de 2h par semaine...",
        "show_fournitures": False,
        "show_diag_photos": False,
        "line_labels": {
            "MAIN_OEUVRE": "Cours / Seances",
            "FOURNITURE": "Supports / Livres",
            "AUTRE": "Option",
        },
        "empty_hint": "Selectionnez un forfait (seance, semaine, mois) et ajustez votre tarif.",
    },
    "nettoyage": {
        "mode": "FORFAIT_MAISON",
        "screen_subtitle": "Chiffrez votre prestation menage simplement",
        "section_summary_title": "Details du menage",
        "diagnostic_label": "Prestation prevue *",
        "diagnostic_hint": "Ex : Nettoyage complet appartement 3 pieces (sols, vitres, cuisine, salles d'eau)...",
        "show_fournitures": True,
        "show_diag_photos": False,
        "line_labels": {
            "MAIN_OEUVRE": "Prestation menage",
            "FOURNITURE": "Produits / Materiel",
            "AUTRE": "Option",
        },
        "empty_hint": "Touchez un forfait ci-dessus ou ajoutez votre prestation.",
    },
    "cuisine": {
        "mode": "FORFAIT_MAISON",
        "screen_subtitle": "Proposez votre menu et votre forfait",
        "section_summary_title": "Menu et organisation",
        "diagnostic_label": "Plats et prestation *",
        "diagnostic_hint": "Ex : Preparation de 3 plats pour 6 personnes a domicile...",
        "show_fournitures": True,
        "show_diag_photos": False,
        "line_labels": {
            "MAIN_OEUVRE": "Service cuisine",
            "FOURNITURE": "Courses / Ingredients",
            "AUTRE": "Option",
        },
        "empty_hint": "Ajoutez votre forfait cuisine et eventuellement le budget ingredients.",
    },
    "beaute": {
        "mode": "SERVICE_PERSONNE",
        "screen_subtitle": "Proposez votre tarif beaute a domicile",
        "section_summary_title": "Details de la prestation",
        "diagnostic_label": "Prestation souhaitee *",
        "diagnostic_hint": "Ex : Coiffure / tresses a domicile avec soin capillaire...",
        "show_fournitures": True,
        "show_diag_photos": False,
        "line_labels": {
            "MAIN_OEUVRE": "Prestation",
            "FOURNITURE": "Produits / Meches",
            "AUTRE": "Option",
        },
        "empty_hint": "Choisissez un forfait beaute ou ajoutez votre prestation.",
    },
    "pinceau": {
        "mode": "SURFACE",
        "screen_subtitle": "Devis peinture clair (forfait piece ou m2)",
        "section_summary_title": "Constat des murs & surface",
        "diagnostic_label": "Travaux de peinture *",
        "diagnostic_hint": "Ex : Rebouchage fissures, poncage et 2 couches peinture satin sur salon + couloir...",
        "show_fournitures": True,
        "show_diag_photos": True,
        "line_labels": {
            "MAIN_OEUVRE": "Main-d'oeuvre",
            "FOURNITURE": "Peinture & Materiel",
            "AUTRE": "Autre",
        },
        "empty_hint": "Utilisez un kit 1-clic (Chambre, Salon...) ou detaillez Main-d'oeuvre + Peinture.",
    },
    "carrelage": {
        "mode": "SURFACE",
        "screen_subtitle": "Devis carrelage clair (forfait ou m2)",
        "section_summary_title": "Constat du sol / mur",
        "diagnostic_label": "Travaux de carrelage *",
        "diagnostic_hint": "Ex : Depose anciens carreaux, ragreage et pose gres cerame 60x60...",
        "show_fournitures": True,
        "show_diag_photos": True,
        "line_labels": {
            "MAIN_OEUVRE": "Pose / Main-d'oeuvre",
            "FOURNITURE": "Carreaux & Colle",
            "AUTRE": "Autre",
        },
        "empty_hint": "Utilisez un modele rapide ou detaillez Pose + Carreaux/Colle.",
    },
    "_default": {
        "mode": "BTP_TECHNIQUE",
        "screen_subtitle": "Etablissez un devis clair en quelques secondes",
        "section_summary_title": "Constat & details",
        "diagnostic_label": "Ce que vous allez faire *",
        "diagnostic_hint": "Decrivez simplement la panne observee et l'intervention prevue...",
        "show_fournitures": True,
        "show_diag_photos": True,
        "line_labels": {
            "MAIN_OEUVRE": "Main-d'oeuvre",
            "FOURNITURE": "Pieces / Fournitures",
            "AUTRE": "Autre",
        },
        "empty_hint": "Touchez un modele rapide ci-dessus ou ajoutez vos lignes.",
    },
}

# Modeles de devis 1-clic (remplissent diagnostic + lignes d'un seul geste)
QUICK_DEVIS_TEMPLATES: Dict[str, List[Dict[str, Any]]] = {
    "nounou": [
        {
            "title": "Garde journee (8h - 18h)",
            "diagnostic": "Garde d'enfants a domicile sur la journee, repas, jeux calmes et securite.",
            "lignes": [
                {"type_ligne": "MAIN_OEUVRE", "description": "Garde d'enfants a la journee", "quantite": 1, "unite": "jour", "prix_unitaire": 10000},
            ],
        },
        {
            "title": "Baby-sitting soiree (4h)",
            "diagnostic": "Garde d'enfants en soiree avec coucher et surveillance jusqu'au retour des parents.",
            "lignes": [
                {"type_ligne": "MAIN_OEUVRE", "description": "Baby-sitting soiree (4h)", "quantite": 1, "unite": "forfait", "prix_unitaire": 10000},
                {"type_ligne": "AUTRE", "description": "Transport retour securise", "quantite": 1, "unite": "forfait", "prix_unitaire": 2500},
            ],
        },
        {
            "title": "Forfait mensuel (Lun-Ven)",
            "diagnostic": "Garde reguliere a domicile du lundi au vendredi, suivi quotidien et accompagnement.",
            "lignes": [
                {"type_ligne": "MAIN_OEUVRE", "description": "Forfait mensuel garde d'enfants", "quantite": 1, "unite": "mois", "prix_unitaire": 90000},
            ],
        },
    ],
    "soutien": [
        {
            "title": "Seance 2h a domicile",
            "diagnostic": "Cours particulier a domicile avec revision des lecons et exercices corriges.",
            "lignes": [
                {"type_ligne": "MAIN_OEUVRE", "description": "Seance soutien scolaire (2h)", "quantite": 1, "unite": "seance", "prix_unitaire": 8000},
            ],
        },
        {
            "title": "Forfait mensuel (8 seances)",
            "diagnostic": "Accompagnement scolaire regulier : 2 seances de 2h par semaine avec suivi parents.",
            "lignes": [
                {"type_ligne": "MAIN_OEUVRE", "description": "Suivi scolaire mensuel (8 seances de 2h)", "quantite": 1, "unite": "mois", "prix_unitaire": 60000},
            ],
        },
    ],
    "goutte": [
        {
            "title": "Reparation fuite / siphon",
            "diagnostic": "Recherche de fuite, remplacement joint/siphon et verification etancheite.",
            "lignes": [
                {"type_ligne": "MAIN_OEUVRE", "description": "Reparation fuite et test etancheite", "quantite": 1, "unite": "forfait", "prix_unitaire": 10000},
                {"type_ligne": "FOURNITURE", "description": "Joints, teflon et siphon neuf", "quantite": 1, "unite": "forfait", "prix_unitaire": 4500},
            ],
        },
        {
            "title": "Debouchage canalisation",
            "diagnostic": "Debouchage complet evier/lavabo/WC et nettoyage du circuit d'evacuation.",
            "lignes": [
                {"type_ligne": "MAIN_OEUVRE", "description": "Debouchage canalisation complet", "quantite": 1, "unite": "forfait", "prix_unitaire": 12000},
            ],
        },
        {
            "title": "Remplacement robinet",
            "diagnostic": "Depose ancien robinet, pose robinet neuf avec flexibles et test pression.",
            "lignes": [
                {"type_ligne": "MAIN_OEUVRE", "description": "Depose et pose robinet / mitigeur", "quantite": 1, "unite": "u", "prix_unitaire": 8000},
                {"type_ligne": "FOURNITURE", "description": "Robinet melangeur et flexibles inox", "quantite": 1, "unite": "u", "prix_unitaire": 15000},
            ],
        },
    ],
    "climatisation": [
        {
            "title": "Entretien complet 1 split",
            "diagnostic": "Nettoyage filtres, evaporateur, bac condensats, desinfection et controle froid.",
            "lignes": [
                {"type_ligne": "MAIN_OEUVRE", "description": "Entretien complet et nettoyage split", "quantite": 1, "unite": "u", "prix_unitaire": 15000},
            ],
        },
        {
            "title": "Recharge gaz + controle fuite",
            "diagnostic": "Verification pression, recherche de fuite et appoint gaz refrigerant R410A/R32.",
            "lignes": [
                {"type_ligne": "MAIN_OEUVRE", "description": "Diagnostic circuit froid et mise en pression", "quantite": 1, "unite": "forfait", "prix_unitaire": 10000},
                {"type_ligne": "FOURNITURE", "description": "Recharge gaz refrigerant", "quantite": 1, "unite": "kg", "prix_unitaire": 14000},
            ],
        },
        {
            "title": "Installation split neuf",
            "diagnostic": "Pose unite interieure et groupe exterieur, raccordement cuivre, tirage au vide et essai.",
            "lignes": [
                {"type_ligne": "MAIN_OEUVRE", "description": "Pose et mise en service climatiseur split", "quantite": 1, "unite": "u", "prix_unitaire": 30000},
                {"type_ligne": "FOURNITURE", "description": "Support mural et accessoires de fixation", "quantite": 1, "unite": "forfait", "prix_unitaire": 10000},
            ],
        },
    ],
    "eclair": [
        {
            "title": "Recherche panne / disjoncteur",
            "diagnostic": "Diagnostic tableau electrique, isolation du defaut et remise en service securisee.",
            "lignes": [
                {"type_ligne": "MAIN_OEUVRE", "description": "Recherche de panne et depannage electrique", "quantite": 1, "unite": "forfait", "prix_unitaire": 12000},
                {"type_ligne": "FOURNITURE", "description": "Disjoncteur divisionnaire neuf", "quantite": 1, "unite": "u", "prix_unitaire": 5000},
            ],
        },
        {
            "title": "Pose prises / interrupteurs",
            "diagnostic": "Fourniture et installation appareillage electrique avec test securite terre.",
            "lignes": [
                {"type_ligne": "MAIN_OEUVRE", "description": "Pose et raccordement prises / interrupteurs", "quantite": 2, "unite": "u", "prix_unitaire": 3500},
                {"type_ligne": "FOURNITURE", "description": "Prises / interrupteurs Legrand", "quantite": 2, "unite": "u", "prix_unitaire": 2000},
            ],
        },
    ],
    "cle": [
        {
            "title": "Ouverture porte claquee",
            "diagnostic": "Ouverture fine de porte claquee sans degradation du bati.",
            "lignes": [
                {"type_ligne": "MAIN_OEUVRE", "description": "Ouverture de porte claquee sans casse", "quantite": 1, "unite": "forfait", "prix_unitaire": 15000},
            ],
        },
        {
            "title": "Changement cylindre / serrure",
            "diagnostic": "Depose cylindre defectueux, pose cylindre haute securite 3 cles et reglage.",
            "lignes": [
                {"type_ligne": "MAIN_OEUVRE", "description": "Remplacement cylindre et reglage serrure", "quantite": 1, "unite": "u", "prix_unitaire": 10000},
                {"type_ligne": "FOURNITURE", "description": "Cylindre securite 3 cles", "quantite": 1, "unite": "u", "prix_unitaire": 10000},
            ],
        },
    ],
    "nettoyage": [
        {
            "title": "Menage appartement (2-3 p.)",
            "diagnostic": "Nettoyage complet sols, poussiere, cuisine, sanitaires et vitres accessibles.",
            "lignes": [
                {"type_ligne": "MAIN_OEUVRE", "description": "Forfait menage complet appartement", "quantite": 1, "unite": "forfait", "prix_unitaire": 15000},
            ],
        },
        {
            "title": "Grand nettoyage / fin chantier",
            "diagnostic": "Remise a neuf complete, degraissage, vitrerie et desinfection des surfaces.",
            "lignes": [
                {"type_ligne": "MAIN_OEUVRE", "description": "Forfait grand nettoyage / fin de chantier", "quantite": 1, "unite": "forfait", "prix_unitaire": 35000},
                {"type_ligne": "FOURNITURE", "description": "Produits desinfectants professionnels", "quantite": 1, "unite": "forfait", "prix_unitaire": 5000},
            ],
        },
    ],
    "pinceau": [
        {
            "title": "Peinture 1 chambre (forfait)",
            "diagnostic": "Protection sol, rebouchage leger et application de 2 couches peinture interieure.",
            "lignes": [
                {"type_ligne": "MAIN_OEUVRE", "description": "Preparation et peinture 2 couches (1 piece)", "quantite": 1, "unite": "forfait", "prix_unitaire": 30000},
                {"type_ligne": "FOURNITURE", "description": "Peinture acrylique + consommables", "quantite": 1, "unite": "forfait", "prix_unitaire": 28000},
            ],
        },
    ],
    "electromenager": [
        {
            "title": "Depannage frigo / lave-linge",
            "diagnostic": "Diagnostic panne, remplacement piece defectueuse et test complet de fonctionnement.",
            "lignes": [
                {"type_ligne": "MAIN_OEUVRE", "description": "Diagnostic et reparation electromenager", "quantite": 1, "unite": "forfait", "prix_unitaire": 15000},
                {"type_ligne": "FOURNITURE", "description": "Piece detachee de remplacement", "quantite": 1, "unite": "u", "prix_unitaire": 12000},
            ],
        },
    ],
    "generique": [
        {
            "title": "Intervention forfait simple",
            "diagnostic": "Evaluation du besoin sur place et realization complete de la prestation.",
            "lignes": [
                {"type_ligne": "MAIN_OEUVRE", "description": "Forfait prestation complete", "quantite": 1, "unite": "forfait", "prix_unitaire": 15000},
            ],
        },
    ],
}


class CatalogueService:
    """Service metier d'alimentation du catalogue hybride et profils devis."""

    @classmethod
    def get_slug_for_category(cls, category: Optional[Any]) -> str:
        """Trouve la cle de catalogue la plus appropriee pour n'importe quelle categorie."""
        if not category:
            return "generique"
        slug = (getattr(category, "icone_slug", "") or "").strip().lower()
        if slug in CATALOGUE_DATA:
            return slug

        nom = (getattr(category, "nom", "") or "").lower()
        kw = (getattr(category, "search_keywords", "") or "").lower()
        blob = f"{nom} {kw} {slug}"

        if any(k in blob for k in ("nounou", "garde d'enfant", "garde enfant", "baby", "nourrice", "creche")):
            return "nounou"
        if any(k in blob for k in ("soutien", "cours", "repetiteur", "professeur", "scolaire")):
            return "soutien"
        if any(k in blob for k in ("plomb", "sanitaire", "goutte")):
            return "goutte"
        if any(k in blob for k in ("electromenager", "frigo", "lave-linge", "refriger")):
            return "electromenager"
        if any(k in blob for k in ("electr", "eclair")):
            return "eclair"
        if any(k in blob for k in ("clim", "froid", "split", "ventilation")):
            return "climatisation"
        if any(k in blob for k in ("serrur", "cle", "verrou")):
            return "cle"
        if any(k in blob for k in ("peint", "pinceau", "ravalement")):
            return "pinceau"
        if any(k in blob for k in ("carr", "faience")):
            return "carrelage"
        if any(k in blob for k in ("macon", "beton", "parpaing", "gros oeuvre")):
            return "maconnerie"
        if any(k in blob for k in ("menuis", "bois", "ebenist", "placard")):
            return "menuiserie"
        if any(k in blob for k in ("menage", "nett", "propr", "repassage")):
            return "nettoyage"
        if any(k in blob for k in ("jardin", "pelouse", "elagage", "paysag")):
            return "jardinage"
        if any(k in blob for k in ("cuisin", "traiteur", "chef")):
            return "cuisine"
        if any(k in blob for k in ("demenag", "manutent", "transport meuble")):
            return "demenagement"
        if any(k in blob for k in ("coiff", "beaut", "esthet", "manucur", "maquill", "massage")):
            return "beaute"
        if any(k in blob for k in ("mecan", "auto", "voiture", "vidange")):
            return "auto"
        if any(k in blob for k in ("informati", "wi-fi", "wifi", "ordinateur", "reseau")):
            return "informatique"

        return "generique"

    @classmethod
    def _load_category(cls, category_id: Optional[int]):
        if not category_id:
            return None
        try:
            from ..models import Category

            return Category.objects.filter(id=category_id).first()
        except Exception as exc:
            logger.warning("Erreur lecture categorie id=%s: %s", category_id, exc)
            return None

    @classmethod
    def _build_items_for_slug(
        cls, category_id: Optional[int], slug: str
    ) -> List[Dict[str, Any]]:
        raw_items = CATALOGUE_DATA.get(slug) or CATALOGUE_DATA["generique"]
        items = []
        base_id = (category_id or 1) * 1000
        for idx, item in enumerate(raw_items, start=1):
            items.append(
                {
                    "id": base_id + idx,
                    "type_ligne": item["type_ligne"],
                    "nom": item["nom"],
                    "description": f"{item['nom']} · {item['unite']}",
                    "unite": item["unite"],
                    "marque": item.get("marque", ""),
                    "prix_unitaire_indicatif": float(item["prix"]),
                }
            )
        return items

    @classmethod
    def get_catalogue_items_for_category(
        cls, category: Optional[Any]
    ) -> List[Dict[str, Any]]:
        """Construit les articles depuis un objet Category deja charge (0 requete SQL)."""
        slug = cls.get_slug_for_category(category)
        cid = getattr(category, "id", None) if category is not None else None
        return cls._build_items_for_slug(cid, slug)

    @classmethod
    def get_catalogue_items(cls, category_id: Optional[int]) -> List[Dict[str, Any]]:
        category = cls._load_category(category_id)
        slug = cls.get_slug_for_category(category)
        return cls._build_items_for_slug(category_id, slug)

    @classmethod
    def get_recommended_units(cls, category_id: Optional[int]) -> List[str]:
        category = cls._load_category(category_id)
        slug = cls.get_slug_for_category(category)
        return UNITS_BY_CATEGORY.get(slug) or UNITS_BY_CATEGORY["generique"]

    @classmethod
    def get_devis_ui_profile(cls, category_id: Optional[int]) -> Dict[str, Any]:
        """Retourne le profil d'interface devis adapte a la categorie (zero jargon)."""
        category = cls._load_category(category_id)
        slug = cls.get_slug_for_category(category)
        profile = dict(DEVIS_UI_PROFILES.get(slug) or DEVIS_UI_PROFILES["_default"])
        profile["slug"] = slug
        profile["units"] = UNITS_BY_CATEGORY.get(slug) or UNITS_BY_CATEGORY["generique"]
        return profile

    @classmethod
    def get_quick_templates(cls, category_id: Optional[int]) -> List[Dict[str, Any]]:
        """Retourne les modeles de devis prets en 1 clic pour cette categorie."""
        category = cls._load_category(category_id)
        slug = cls.get_slug_for_category(category)
        return list(QUICK_DEVIS_TEMPLATES.get(slug) or QUICK_DEVIS_TEMPLATES["generique"])
