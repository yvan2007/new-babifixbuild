"""seed_catalogue — Catalogues indicatifs par catégorie BABIFIX (Phase B).

Remplit `CatalogueItem` avec une base de matériaux et de prestations types
par catégorie. Le prestataire pourra cocher dans cette liste lors de la
rédaction d'un devis, tout en gardant la possibilité d'ajouter du libre.

Idempotent : on utilise `update_or_create` sur (category, type_ligne, nom).
"""

from decimal import Decimal

from django.core.management.base import BaseCommand

from adminpanel.models import Category, CatalogueItem, LigneDevis


# Catalogues par slug de catégorie. Les prix sont indicatifs (XOF) et le
# prestataire peut toujours les surcharger.
CATALOGS = {
    "plomberie": [
        ("FOURNITURE", "Tuyau PVC Ø32 mm", "ml", 1500, ""),
        ("FOURNITURE", "Tuyau PVC Ø40 mm", "ml", 2000, ""),
        ("FOURNITURE", "Coude PVC Ø32", "u", 800, ""),
        ("FOURNITURE", "Robinet mélangeur lavabo", "u", 12000, "Grohe"),
        ("FOURNITURE", "Joint silicone sanitaire", "u", 2500, ""),
        ("FOURNITURE", "Chasse d'eau complète", "u", 18000, ""),
        ("MAIN_OEUVRE", "Diagnostic plomberie", "forfait", 5000, ""),
        ("MAIN_OEUVRE", "Pose robinet / mitigeur", "u", 7000, ""),
        ("MAIN_OEUVRE", "Débouchage canalisation", "forfait", 10000, ""),
        ("MAIN_OEUVRE", "Heure de main d'œuvre", "h", 4000, ""),
        ("DEPLACEMENT", "Déplacement urbain Abidjan", "forfait", 3000, ""),
    ],
    "electricite": [
        ("FOURNITURE", "Câble électrique 2.5 mm²", "ml", 600, ""),
        ("FOURNITURE", "Câble électrique 1.5 mm²", "ml", 400, ""),
        ("FOURNITURE", "Disjoncteur 16A", "u", 4500, "Schneider"),
        ("FOURNITURE", "Prise standard 16A", "u", 1500, ""),
        ("FOURNITURE", "Interrupteur simple", "u", 1200, ""),
        ("FOURNITURE", "Ampoule LED 9W", "u", 1500, ""),
        ("MAIN_OEUVRE", "Diagnostic installation électrique", "forfait", 8000, ""),
        ("MAIN_OEUVRE", "Pose prise / interrupteur", "u", 3000, ""),
        ("MAIN_OEUVRE", "Pose disjoncteur dans tableau", "u", 5000, ""),
        ("MAIN_OEUVRE", "Heure de main d'œuvre", "h", 5000, ""),
        ("DEPLACEMENT", "Déplacement urbain", "forfait", 3000, ""),
    ],
    "menuiserie": [
        ("FOURNITURE", "Planche bois (sapin)", "m", 3500, ""),
        ("FOURNITURE", "Serrure porte standard", "u", 8000, ""),
        ("FOURNITURE", "Vis bois (boîte 100)", "u", 2000, ""),
        ("MAIN_OEUVRE", "Pose porte intérieure", "u", 15000, ""),
        ("MAIN_OEUVRE", "Réparation meuble", "h", 4000, ""),
        ("DEPLACEMENT", "Déplacement urbain", "forfait", 3000, ""),
    ],
    "peinture": [
        ("FOURNITURE", "Peinture acrylique blanche", "kg", 1800, ""),
        ("FOURNITURE", "Peinture couleur (kg)", "kg", 2500, ""),
        ("FOURNITURE", "Rouleau peinture", "u", 1500, ""),
        ("FOURNITURE", "Bâche de protection", "u", 2000, ""),
        ("MAIN_OEUVRE", "Peinture mur (intérieur)", "m²", 2000, ""),
        ("MAIN_OEUVRE", "Peinture plafond", "m²", 2500, ""),
        ("MAIN_OEUVRE", "Préparation surface (poncage)", "m²", 800, ""),
        ("DEPLACEMENT", "Déplacement urbain", "forfait", 3000, ""),
    ],
    "menage": [
        ("MAIN_OEUVRE", "Ménage standard logement", "h", 2500, ""),
        ("MAIN_OEUVRE", "Grand ménage (vitres + sols)", "forfait", 15000, ""),
        ("FOURNITURE", "Produits ménagers (fournis)", "forfait", 3000, ""),
        ("DEPLACEMENT", "Déplacement urbain", "forfait", 2000, ""),
    ],
    "climatisation": [
        ("FOURNITURE", "Recharge gaz R410A", "kg", 12000, ""),
        ("FOURNITURE", "Filtre climatiseur split", "u", 8000, ""),
        ("MAIN_OEUVRE", "Diagnostic climatisation", "forfait", 7000, ""),
        ("MAIN_OEUVRE", "Nettoyage split", "u", 12000, ""),
        ("MAIN_OEUVRE", "Pose split (mur)", "u", 30000, ""),
        ("DEPLACEMENT", "Déplacement urbain", "forfait", 3000, ""),
    ],
    "soudure": [
        ("FOURNITURE", "Électrodes (boîte)", "u", 5000, ""),
        ("FOURNITURE", "Tôle acier 2 mm", "m²", 8000, ""),
        ("MAIN_OEUVRE", "Soudure portail / grille", "ml", 4000, ""),
        ("MAIN_OEUVRE", "Réparation soudure simple", "forfait", 8000, ""),
        ("DEPLACEMENT", "Déplacement urbain", "forfait", 3500, ""),
    ],
}


def _normalize_slug(s: str) -> str:
    return (
        (s or "")
        .lower()
        .strip()
        .replace("é", "e")
        .replace("è", "e")
        .replace("ê", "e")
        .replace("à", "a")
        .replace("ô", "o")
        .replace("'", "")
        .replace("-", "")
        .replace(" ", "")
    )


class Command(BaseCommand):
    help = "Seed le catalogue de matériaux / prestations par catégorie."

    def handle(self, *args, **opts):
        # Indexer les catégories existantes par slug normalisé
        cats_by_key = {}
        for cat in Category.objects.all():
            key_name = _normalize_slug(cat.nom or "")
            key_slug = _normalize_slug(getattr(cat, "slug", "") or "")
            for k in (key_name, key_slug):
                if k:
                    cats_by_key[k] = cat

        total = 0
        created = 0
        for slug, items in CATALOGS.items():
            cat = cats_by_key.get(_normalize_slug(slug))
            if not cat:
                self.stdout.write(
                    self.style.WARNING(
                        f"  – Catégorie '{slug}' introuvable, skip ({len(items)} items)"
                    )
                )
                continue
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
            self.stdout.write(
                self.style.SUCCESS(
                    f"  OK {cat.nom}: {len(items)} items (crees/maj)"
                )
            )

        self.stdout.write(
            self.style.SUCCESS(
                f"Catalogue : {total} items traités, {created} nouveaux."
            )
        )
