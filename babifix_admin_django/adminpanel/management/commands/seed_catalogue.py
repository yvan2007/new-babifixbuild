"""seed_catalogue — Catalogues indicatifs par catégorie BABIFIX (Phase B).

Remplit `CatalogueItem` avec une base RICHE de matériaux et de prestations
types, **spécifiques à chaque catégorie** (identifiée par son `icone_slug`,
stable et sans accents). Le prestataire coche dans cette liste lors de la
rédaction d'un devis, tout en gardant la saisie libre.

- Catalogue spécifique pour les métiers courants (plomberie, électricité…).
- Sinon : un socle générique (diagnostic + main d'œuvre + déplacement) afin
  qu'AUCUNE catégorie ne soit vide.

Idempotent : `update_or_create` sur (category, type_ligne, nom).

Tuple item = (type_ligne, nom, unité, prix_indicatif_XOF, marque)
"""

from decimal import Decimal

from django.core.management.base import BaseCommand

from adminpanel.models import Category, CatalogueItem


# ─────────────────────────────────────────────────────────────────────────────
# Catalogues spécifiques, indexés par icone_slug de la catégorie.
# ─────────────────────────────────────────────────────────────────────────────
CATALOGS = {
    # ── Plomberie ────────────────────────────────────────────────────────────
    "goutte": [
        ("FOURNITURE", "Tuyau PVC Ø32 mm", "ml", 1500, ""),
        ("FOURNITURE", "Tuyau PVC Ø40 mm", "ml", 2000, ""),
        ("FOURNITURE", "Tuyau PVC Ø100 mm (évacuation)", "ml", 3500, ""),
        ("FOURNITURE", "Coude PVC Ø32", "u", 800, ""),
        ("FOURNITURE", "Té PVC Ø40", "u", 1000, ""),
        ("FOURNITURE", "Colle PVC (pot)", "u", 2500, ""),
        ("FOURNITURE", "Robinet mélangeur lavabo", "u", 12000, "Grohe"),
        ("FOURNITURE", "Flexible de douche", "u", 4500, ""),
        ("FOURNITURE", "Siphon lavabo", "u", 3000, ""),
        ("FOURNITURE", "Joint silicone sanitaire", "u", 2500, ""),
        ("FOURNITURE", "Chasse d'eau complète", "u", 18000, ""),
        ("MAIN_OEUVRE", "Diagnostic plomberie", "forfait", 5000, ""),
        ("MAIN_OEUVRE", "Pose robinet / mitigeur", "u", 7000, ""),
        ("MAIN_OEUVRE", "Recherche & réparation fuite", "forfait", 12000, ""),
        ("MAIN_OEUVRE", "Débouchage canalisation", "forfait", 10000, ""),
        ("MAIN_OEUVRE", "Heure de main d'œuvre", "h", 4000, ""),
        ("DEPLACEMENT", "Déplacement urbain Abidjan", "forfait", 3000, ""),
    ],
    # ── Électricité ──────────────────────────────────────────────────────────
    "eclair": [
        ("FOURNITURE", "Câble électrique 2.5 mm²", "ml", 600, ""),
        ("FOURNITURE", "Câble électrique 1.5 mm²", "ml", 400, ""),
        ("FOURNITURE", "Gaine ICTA Ø20", "ml", 350, ""),
        ("FOURNITURE", "Disjoncteur 16A", "u", 4500, "Schneider"),
        ("FOURNITURE", "Disjoncteur différentiel 30mA", "u", 18000, "Schneider"),
        ("FOURNITURE", "Prise standard 16A", "u", 1500, ""),
        ("FOURNITURE", "Interrupteur simple", "u", 1200, ""),
        ("FOURNITURE", "Ampoule LED 9W", "u", 1500, ""),
        ("FOURNITURE", "Tableau électrique 1 rangée", "u", 12000, ""),
        ("MAIN_OEUVRE", "Diagnostic installation électrique", "forfait", 8000, ""),
        ("MAIN_OEUVRE", "Pose prise / interrupteur", "u", 3000, ""),
        ("MAIN_OEUVRE", "Pose disjoncteur dans tableau", "u", 5000, ""),
        ("MAIN_OEUVRE", "Mise aux normes tableau", "forfait", 35000, ""),
        ("MAIN_OEUVRE", "Heure de main d'œuvre", "h", 5000, ""),
        ("DEPLACEMENT", "Déplacement urbain", "forfait", 3000, ""),
    ],
    # ── Climatisation & ventilation ──────────────────────────────────────────
    "climatisation": [
        ("FOURNITURE", "Recharge gaz R410A", "kg", 12000, ""),
        ("FOURNITURE", "Recharge gaz R32", "kg", 14000, ""),
        ("FOURNITURE", "Filtre climatiseur split", "u", 8000, ""),
        ("FOURNITURE", "Tuyau cuivre frigorifique", "ml", 6000, ""),
        ("FOURNITURE", "Support mural split", "u", 7000, ""),
        ("MAIN_OEUVRE", "Diagnostic climatisation", "forfait", 7000, ""),
        ("MAIN_OEUVRE", "Nettoyage split", "u", 12000, ""),
        ("MAIN_OEUVRE", "Pose split (mur)", "u", 30000, ""),
        ("MAIN_OEUVRE", "Dépose / repose climatiseur", "u", 20000, ""),
        ("DEPLACEMENT", "Déplacement urbain", "forfait", 3000, ""),
    ],
    # ── Chauffe-eau / eau chaude ─────────────────────────────────────────────
    "chauffage": [
        ("FOURNITURE", "Chauffe-eau électrique 50L", "u", 65000, ""),
        ("FOURNITURE", "Résistance chauffe-eau", "u", 12000, ""),
        ("FOURNITURE", "Thermostat chauffe-eau", "u", 8000, ""),
        ("FOURNITURE", "Groupe de sécurité", "u", 9000, ""),
        ("MAIN_OEUVRE", "Diagnostic chauffe-eau", "forfait", 6000, ""),
        ("MAIN_OEUVRE", "Pose chauffe-eau", "u", 25000, ""),
        ("MAIN_OEUVRE", "Détartrage cuve", "forfait", 15000, ""),
        ("DEPLACEMENT", "Déplacement urbain", "forfait", 3000, ""),
    ],
    # ── Serrurerie ───────────────────────────────────────────────────────────
    "cle": [
        ("FOURNITURE", "Serrure de porte standard", "u", 8000, ""),
        ("FOURNITURE", "Cylindre / barillet", "u", 6000, ""),
        ("FOURNITURE", "Verrou de sûreté", "u", 9000, ""),
        ("FOURNITURE", "Poignée de porte", "u", 4500, ""),
        ("MAIN_OEUVRE", "Ouverture de porte (sans dégât)", "forfait", 15000, ""),
        ("MAIN_OEUVRE", "Remplacement serrure", "u", 10000, ""),
        ("DEPLACEMENT", "Déplacement urbain", "forfait", 4000, ""),
    ],
    # ── Vitrerie & miroiterie ────────────────────────────────────────────────
    "fenetre": [
        ("FOURNITURE", "Vitre simple 4 mm", "m²", 12000, ""),
        ("FOURNITURE", "Double vitrage", "m²", 28000, ""),
        ("FOURNITURE", "Mastic / joint vitrage", "u", 2500, ""),
        ("MAIN_OEUVRE", "Pose / remplacement vitre", "m²", 8000, ""),
        ("MAIN_OEUVRE", "Pose miroir mural", "u", 10000, ""),
        ("DEPLACEMENT", "Déplacement urbain", "forfait", 3500, ""),
    ],
    "vitrage": [
        ("FOURNITURE", "Panneau bois de sécurisation", "m²", 9000, ""),
        ("FOURNITURE", "Film de sécurité vitrage", "m²", 7000, ""),
        ("FOURNITURE", "Vitrage de remplacement", "m²", 15000, ""),
        ("MAIN_OEUVRE", "Sécurisation d'urgence", "forfait", 20000, ""),
        ("MAIN_OEUVRE", "Remplacement vitrage", "m²", 9000, ""),
        ("DEPLACEMENT", "Intervention urgence", "forfait", 6000, ""),
    ],
    # ── Peinture & décoration ────────────────────────────────────────────────
    "pinceau": [
        ("FOURNITURE", "Peinture acrylique blanche", "kg", 1800, ""),
        ("FOURNITURE", "Peinture couleur", "kg", 2500, ""),
        ("FOURNITURE", "Sous-couche / primaire", "kg", 1600, ""),
        ("FOURNITURE", "Enduit de lissage", "kg", 1200, ""),
        ("FOURNITURE", "Rouleau peinture", "u", 1500, ""),
        ("FOURNITURE", "Pinceau", "u", 1000, ""),
        ("FOURNITURE", "Ruban de masquage", "u", 1500, ""),
        ("FOURNITURE", "Bâche de protection", "u", 2000, ""),
        ("MAIN_OEUVRE", "Peinture mur (intérieur)", "m²", 2000, ""),
        ("MAIN_OEUVRE", "Peinture plafond", "m²", 2500, ""),
        ("MAIN_OEUVRE", "Préparation surface (ponçage)", "m²", 800, ""),
        ("DEPLACEMENT", "Déplacement urbain", "forfait", 3000, ""),
    ],
    # ── Carrelage & faïence ──────────────────────────────────────────────────
    "carrelage": [
        ("FOURNITURE", "Carreau grès 60x60", "m²", 7500, ""),
        ("FOURNITURE", "Faïence murale", "m²", 6000, ""),
        ("FOURNITURE", "Colle à carrelage (sac)", "u", 4500, ""),
        ("FOURNITURE", "Joint de carrelage (sac)", "u", 3500, ""),
        ("FOURNITURE", "Croisillons (sachet)", "u", 1500, ""),
        ("FOURNITURE", "Plinthe carrelage", "ml", 2500, ""),
        ("MAIN_OEUVRE", "Pose carrelage sol", "m²", 5000, ""),
        ("MAIN_OEUVRE", "Pose faïence murale", "m²", 6000, ""),
        ("DEPLACEMENT", "Déplacement urbain", "forfait", 3000, ""),
    ],
    # ── Menuiserie ───────────────────────────────────────────────────────────
    "menuiserie": [
        ("FOURNITURE", "Planche bois (sapin)", "m", 3500, ""),
        ("FOURNITURE", "Porte intérieure", "u", 35000, ""),
        ("FOURNITURE", "Serrure porte standard", "u", 8000, ""),
        ("FOURNITURE", "Charnières (paire)", "u", 2000, ""),
        ("FOURNITURE", "Vis bois (boîte 100)", "u", 2000, ""),
        ("FOURNITURE", "Vernis / lasure (L)", "u", 4000, ""),
        ("MAIN_OEUVRE", "Pose porte intérieure", "u", 15000, ""),
        ("MAIN_OEUVRE", "Réparation meuble", "h", 4000, ""),
        ("DEPLACEMENT", "Déplacement urbain", "forfait", 3000, ""),
    ],
    # ── Jardinage ────────────────────────────────────────────────────────────
    "tondeuse": [
        ("FOURNITURE", "Terreau (sac 50L)", "u", 4000, ""),
        ("FOURNITURE", "Sacs déchets verts (lot)", "u", 2000, ""),
        ("MAIN_OEUVRE", "Tonte de pelouse", "m²", 300, ""),
        ("MAIN_OEUVRE", "Débroussaillage", "m²", 500, ""),
        ("MAIN_OEUVRE", "Taille de haie / arbustes", "ml", 1500, ""),
        ("MAIN_OEUVRE", "Évacuation déchets verts", "forfait", 8000, ""),
        ("MAIN_OEUVRE", "Heure de jardinage", "h", 3000, ""),
        ("DEPLACEMENT", "Déplacement urbain", "forfait", 3000, ""),
    ],
    # ── Élagage ──────────────────────────────────────────────────────────────
    "elagage": [
        ("MAIN_OEUVRE", "Élagage arbre (selon hauteur)", "u", 25000, ""),
        ("MAIN_OEUVRE", "Abattage arbre", "u", 40000, ""),
        ("MAIN_OEUVRE", "Débitage / évacuation", "forfait", 15000, ""),
        ("DEPLACEMENT", "Déplacement + matériel", "forfait", 8000, ""),
    ],
    # ── Ménage courant ───────────────────────────────────────────────────────
    "balai": [
        ("FOURNITURE", "Produits ménagers (fournis)", "forfait", 3000, ""),
        ("MAIN_OEUVRE", "Ménage standard logement", "h", 2500, ""),
        ("MAIN_OEUVRE", "Grand ménage (vitres + sols)", "forfait", 15000, ""),
        ("DEPLACEMENT", "Déplacement urbain", "forfait", 2000, ""),
    ],
    # ── Nettoyage en profondeur ──────────────────────────────────────────────
    "nettoyage": [
        ("FOURNITURE", "Produits spécialisés", "forfait", 5000, ""),
        ("MAIN_OEUVRE", "Shampoing moquette / tapis", "m²", 1500, ""),
        ("MAIN_OEUVRE", "Nettoyage vitres", "m²", 800, ""),
        ("MAIN_OEUVRE", "Nettoyage fin de chantier", "forfait", 25000, ""),
        ("DEPLACEMENT", "Déplacement urbain", "forfait", 3000, ""),
    ],
    # ── Déménagement & manutention ───────────────────────────────────────────
    "demenagement": [
        ("FOURNITURE", "Cartons (lot de 10)", "u", 5000, ""),
        ("FOURNITURE", "Film & adhésif emballage", "forfait", 4000, ""),
        ("MAIN_OEUVRE", "Manutention (par déménageur)", "h", 3500, ""),
        ("MAIN_OEUVRE", "Forfait déménagement studio", "forfait", 50000, ""),
        ("DEPLACEMENT", "Location camion + carburant", "forfait", 25000, ""),
    ],
    # ── Montage de meubles ───────────────────────────────────────────────────
    "escalier": [
        ("FOURNITURE", "Visserie / fixations", "forfait", 2000, ""),
        ("MAIN_OEUVRE", "Montage meuble standard", "u", 8000, ""),
        ("MAIN_OEUVRE", "Fixation murale (étagère, TV)", "u", 6000, ""),
        ("MAIN_OEUVRE", "Heure de main d'œuvre", "h", 3500, ""),
        ("DEPLACEMENT", "Déplacement urbain", "forfait", 3000, ""),
    ],
    # ── Bricolage & petits travaux ───────────────────────────────────────────
    "marteau": [
        ("FOURNITURE", "Fixations / chevilles (lot)", "forfait", 2000, ""),
        ("MAIN_OEUVRE", "Pose étagère / tringle", "u", 5000, ""),
        ("MAIN_OEUVRE", "Petits travaux (heure)", "h", 3500, ""),
        ("DEPLACEMENT", "Déplacement urbain", "forfait", 3000, ""),
    ],
    # ── Réparation électroménager ────────────────────────────────────────────
    "frigo": [
        ("FOURNITURE", "Thermostat", "u", 8000, ""),
        ("FOURNITURE", "Résistance", "u", 7000, ""),
        ("FOURNITURE", "Courroie / pièce détachée", "u", 5000, ""),
        ("MAIN_OEUVRE", "Diagnostic appareil", "forfait", 6000, ""),
        ("MAIN_OEUVRE", "Réparation électroménager", "forfait", 15000, ""),
        ("DEPLACEMENT", "Déplacement urbain", "forfait", 3000, ""),
    ],
    # ── Informatique & assistance ────────────────────────────────────────────
    "ordinateur": [
        ("FOURNITURE", "Barrette RAM 8 Go", "u", 25000, ""),
        ("FOURNITURE", "Disque SSD 480 Go", "u", 35000, ""),
        ("MAIN_OEUVRE", "Nettoyage virus / optimisation", "forfait", 10000, ""),
        ("MAIN_OEUVRE", "Installation système / logiciels", "forfait", 12000, ""),
        ("MAIN_OEUVRE", "Assistance (heure)", "h", 6000, ""),
        ("DEPLACEMENT", "Déplacement urbain", "forfait", 3000, ""),
    ],
    # ── Réparation smartphone & tablette ─────────────────────────────────────
    "telephone": [
        ("FOURNITURE", "Écran de remplacement", "u", 25000, ""),
        ("FOURNITURE", "Batterie", "u", 12000, ""),
        ("FOURNITURE", "Connecteur de charge", "u", 8000, ""),
        ("MAIN_OEUVRE", "Remplacement écran", "forfait", 8000, ""),
        ("MAIN_OEUVRE", "Remplacement batterie", "forfait", 5000, ""),
        ("DEPLACEMENT", "Déplacement urbain", "forfait", 2500, ""),
    ],
    # ── Maçonnerie & béton ───────────────────────────────────────────────────
    "maconnerie": [
        ("FOURNITURE", "Ciment (sac 50 kg)", "u", 5500, ""),
        ("FOURNITURE", "Sable (m³)", "m³", 18000, ""),
        ("FOURNITURE", "Parpaing 15", "u", 450, ""),
        ("FOURNITURE", "Gravier (m³)", "m³", 22000, ""),
        ("MAIN_OEUVRE", "Maçonnerie (m²)", "m²", 6000, ""),
        ("MAIN_OEUVRE", "Heure de main d'œuvre", "h", 3500, ""),
        ("DEPLACEMENT", "Déplacement urbain", "forfait", 4000, ""),
    ],
    # ── Toiture & zinguerie ──────────────────────────────────────────────────
    "toiture": [
        ("FOURNITURE", "Tôle bac acier", "m²", 6500, ""),
        ("FOURNITURE", "Tuiles", "u", 600, ""),
        ("FOURNITURE", "Gouttière PVC", "ml", 3500, ""),
        ("MAIN_OEUVRE", "Réfection toiture", "m²", 5000, ""),
        ("MAIN_OEUVRE", "Réparation fuite toiture", "forfait", 20000, ""),
        ("DEPLACEMENT", "Déplacement urbain", "forfait", 5000, ""),
    ],
    # ── Cloisons & placo ─────────────────────────────────────────────────────
    "placo": [
        ("FOURNITURE", "Plaque BA13", "u", 4500, ""),
        ("FOURNITURE", "Rail / montant métallique", "ml", 1200, ""),
        ("FOURNITURE", "Bande à joint + enduit", "forfait", 4000, ""),
        ("MAIN_OEUVRE", "Pose cloison placo", "m²", 5500, ""),
        ("MAIN_OEUVRE", "Pose faux plafond", "m²", 6000, ""),
        ("DEPLACEMENT", "Déplacement urbain", "forfait", 3000, ""),
    ],
    # ── Isolation ────────────────────────────────────────────────────────────
    "isolation": [
        ("FOURNITURE", "Laine de verre (rouleau)", "m²", 2500, ""),
        ("FOURNITURE", "Polystyrène extrudé", "m²", 3500, ""),
        ("MAIN_OEUVRE", "Pose isolation murs/combles", "m²", 4000, ""),
        ("DEPLACEMENT", "Déplacement urbain", "forfait", 4000, ""),
    ],
    # ── Ravalement de façade ─────────────────────────────────────────────────
    "ravalement": [
        ("FOURNITURE", "Enduit de façade (sac)", "u", 6000, ""),
        ("FOURNITURE", "Peinture façade (kg)", "kg", 2800, ""),
        ("MAIN_OEUVRE", "Ravalement façade", "m²", 4500, ""),
        ("DEPLACEMENT", "Location échafaudage", "forfait", 30000, ""),
    ],
    # ── Cuisine à domicile / traiteur ────────────────────────────────────────
    "casserole": [
        ("FOURNITURE", "Courses / ingrédients", "forfait", 15000, ""),
        ("MAIN_OEUVRE", "Menu par personne", "u", 6000, ""),
        ("MAIN_OEUVRE", "Service en cuisine (heure)", "h", 4000, ""),
        ("DEPLACEMENT", "Déplacement urbain", "forfait", 3000, ""),
    ],
    "traiteur": [
        ("FOURNITURE", "Courses / ingrédients", "forfait", 30000, ""),
        ("MAIN_OEUVRE", "Buffet par personne", "u", 7000, ""),
        ("MAIN_OEUVRE", "Personnel de service (heure)", "h", 4000, ""),
        ("DEPLACEMENT", "Livraison & installation", "forfait", 10000, ""),
    ],
    # ── Coiffure & esthétique ────────────────────────────────────────────────
    "ciseaux": [
        ("FOURNITURE", "Produits coiffure / soins", "forfait", 5000, ""),
        ("MAIN_OEUVRE", "Coupe femme / homme", "u", 5000, ""),
        ("MAIN_OEUVRE", "Coloration", "u", 15000, ""),
        ("MAIN_OEUVRE", "Coiffure / tresses", "u", 12000, ""),
        ("DEPLACEMENT", "Déplacement urbain", "forfait", 3000, ""),
    ],
    # ── Couture & retouches ──────────────────────────────────────────────────
    "couture": [
        ("FOURNITURE", "Fournitures (fil, fermeture…)", "forfait", 2000, ""),
        ("MAIN_OEUVRE", "Ourlet pantalon", "u", 2500, ""),
        ("MAIN_OEUVRE", "Remplacement fermeture éclair", "u", 4000, ""),
        ("MAIN_OEUVRE", "Retouche / ajustement", "u", 3000, ""),
        ("DEPLACEMENT", "Déplacement urbain", "forfait", 2500, ""),
    ],
    # ── Désinfection & antiparasitaire ───────────────────────────────────────
    "desinfection": [
        ("FOURNITURE", "Produits de traitement", "forfait", 8000, ""),
        ("MAIN_OEUVRE", "Désinsectisation logement", "m²", 1000, ""),
        ("MAIN_OEUVRE", "Dératisation", "forfait", 25000, ""),
        ("DEPLACEMENT", "Déplacement urbain", "forfait", 4000, ""),
    ],
    # ── Piscine & spa ────────────────────────────────────────────────────────
    "piscine": [
        ("FOURNITURE", "Chlore (galets, seau)", "u", 18000, ""),
        ("FOURNITURE", "Correcteur pH", "u", 6000, ""),
        ("MAIN_OEUVRE", "Nettoyage piscine", "forfait", 20000, ""),
        ("MAIN_OEUVRE", "Entretien mensuel", "forfait", 30000, ""),
        ("DEPLACEMENT", "Déplacement urbain", "forfait", 4000, ""),
    ],
    # ── Sécurité, alarmes & vidéosurveillance ────────────────────────────────
    "securite": [
        ("FOURNITURE", "Caméra de surveillance", "u", 35000, ""),
        ("FOURNITURE", "Enregistreur (NVR/DVR)", "u", 60000, ""),
        ("FOURNITURE", "Détecteur de mouvement", "u", 12000, ""),
        ("MAIN_OEUVRE", "Pose & configuration caméra", "u", 15000, ""),
        ("MAIN_OEUVRE", "Installation alarme", "forfait", 40000, ""),
        ("DEPLACEMENT", "Déplacement urbain", "forfait", 4000, ""),
    ],
    # ── Lavage & esthétique automobile ───────────────────────────────────────
    "lavage-auto": [
        ("FOURNITURE", "Produits lavage / cire", "forfait", 4000, ""),
        ("MAIN_OEUVRE", "Lavage extérieur", "u", 5000, ""),
        ("MAIN_OEUVRE", "Nettoyage intérieur complet", "u", 12000, ""),
        ("MAIN_OEUVRE", "Polish / lustrage", "u", 20000, ""),
        ("DEPLACEMENT", "Déplacement urbain", "forfait", 3000, ""),
    ],
    # ── Mécanique automobile à domicile ──────────────────────────────────────
    "voiture": [
        ("FOURNITURE", "Huile moteur (L)", "u", 4500, ""),
        ("FOURNITURE", "Filtre à huile", "u", 5000, ""),
        ("FOURNITURE", "Plaquettes de frein (jeu)", "u", 25000, ""),
        ("MAIN_OEUVRE", "Vidange", "forfait", 8000, ""),
        ("MAIN_OEUVRE", "Heure de mécanique", "h", 6000, ""),
        ("DEPLACEMENT", "Déplacement urbain", "forfait", 4000, ""),
    ],
    # ── Forage & pompes ──────────────────────────────────────────────────────
    "forage": [
        ("FOURNITURE", "Pompe immergée", "u", 120000, ""),
        ("FOURNITURE", "Tube PVC forage", "ml", 4000, ""),
        ("MAIN_OEUVRE", "Forage", "ml", 25000, ""),
        ("MAIN_OEUVRE", "Pose pompe", "forfait", 35000, ""),
        ("DEPLACEMENT", "Déplacement + matériel", "forfait", 15000, ""),
    ],
    # ── Soudure légère ───────────────────────────────────────────────────────
    "soudure": [
        ("FOURNITURE", "Électrodes (boîte)", "u", 5000, ""),
        ("FOURNITURE", "Tôle acier 2 mm", "m²", 8000, ""),
        ("MAIN_OEUVRE", "Soudure portail / grille", "ml", 4000, ""),
        ("MAIN_OEUVRE", "Réparation soudure simple", "forfait", 8000, ""),
        ("DEPLACEMENT", "Déplacement urbain", "forfait", 3500, ""),
    ],
    # ── Repassage à domicile ─────────────────────────────────────────────────
    "repassage": [
        ("MAIN_OEUVRE", "Repassage (heure)", "h", 2500, ""),
        ("MAIN_OEUVRE", "Panier de linge (forfait)", "forfait", 8000, ""),
        ("DEPLACEMENT", "Déplacement urbain", "forfait", 2000, ""),
    ],
    # ── Courses & livraison ──────────────────────────────────────────────────
    "courses": [
        ("MAIN_OEUVRE", "Courses (forfait)", "forfait", 5000, ""),
        ("DEPLACEMENT", "Livraison à domicile", "forfait", 3000, ""),
    ],
    # ── Domotique & réseaux ──────────────────────────────────────────────────
    "domotique": [
        ("FOURNITURE", "Box domotique", "u", 45000, ""),
        ("FOURNITURE", "Capteur connecté", "u", 12000, ""),
        ("MAIN_OEUVRE", "Configuration domotique", "forfait", 20000, ""),
        ("DEPLACEMENT", "Déplacement urbain", "forfait", 3500, ""),
    ],
    # ── Antenne TNT & satellite ──────────────────────────────────────────────
    "antenne": [
        ("FOURNITURE", "Antenne / parabole", "u", 18000, ""),
        ("FOURNITURE", "Câble coaxial", "ml", 600, ""),
        ("FOURNITURE", "Démodulateur", "u", 15000, ""),
        ("MAIN_OEUVRE", "Pose & réglage antenne", "forfait", 12000, ""),
        ("DEPLACEMENT", "Déplacement urbain", "forfait", 3500, ""),
    ],
    # ── Gaz & appareils de cuisson ───────────────────────────────────────────
    "gaz-cuisson": [
        ("FOURNITURE", "Flexible gaz normalisé", "u", 4500, ""),
        ("FOURNITURE", "Détendeur gaz", "u", 6000, ""),
        ("MAIN_OEUVRE", "Pose / raccordement cuisinière", "forfait", 10000, ""),
        ("MAIN_OEUVRE", "Contrôle étanchéité gaz", "forfait", 8000, ""),
        ("DEPLACEMENT", "Déplacement urbain", "forfait", 3000, ""),
    ],
}


# Socle générique : appliqué à toute catégorie sans catalogue spécifique afin
# qu'aucune ne soit vide.
GENERIC_BASELINE = [
    ("MAIN_OEUVRE", "Diagnostic / évaluation sur place", "forfait", 5000, ""),
    ("MAIN_OEUVRE", "Heure de main d'œuvre", "h", 4000, ""),
    ("MAIN_OEUVRE", "Forfait prestation standard", "forfait", 15000, ""),
    ("FOURNITURE", "Petites fournitures / consommables", "forfait", 3000, ""),
    ("DEPLACEMENT", "Déplacement urbain Abidjan", "forfait", 3000, ""),
]


def _norm(s: str) -> str:
    return (s or "").strip().lower()


class Command(BaseCommand):
    help = "Seed le catalogue de matériaux / prestations par catégorie (icone_slug)."

    def add_arguments(self, parser):
        parser.add_argument(
            "--no-baseline",
            action="store_true",
            help="Ne pas appliquer le socle générique aux catégories sans catalogue.",
        )

    def handle(self, *args, **opts):
        apply_baseline = not opts.get("no_baseline")
        total = created = specific_cats = baseline_cats = 0

        for cat in Category.objects.all():
            slug = _norm(getattr(cat, "icone_slug", "") or "")
            items = CATALOGS.get(slug)
            is_specific = items is not None
            if items is None:
                if not apply_baseline:
                    continue
                items = GENERIC_BASELINE

            for type_ligne, nom, unite, prix, marque in items:
                _, was_created = CatalogueItem.objects.update_or_create(
                    category=cat,
                    type_ligne=type_ligne,
                    nom=nom,
                    defaults={
                        "unite": unite,
                        "prix_unitaire_indicatif": Decimal(str(prix)),
                        "marque": marque,
                        "actif": True,
                    },
                )
                total += 1
                if was_created:
                    created += 1
            if is_specific:
                specific_cats += 1
            else:
                baseline_cats += 1

        self.stdout.write(
            self.style.SUCCESS(
                f"Catalogue : {total} items ({created} nouveaux) — "
                f"{specific_cats} catégorie(s) avec catalogue spécifique, "
                f"{baseline_cats} avec socle générique."
            )
        )
