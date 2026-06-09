"""
Management command : assigner des coordonnées GPS aux prestataires qui n'en ont pas.
Les coordonnées sont déduites de la ville déclarée.

Usage : python manage.py seed_provider_coords [--dry-run]
"""
import logging
import random

from django.core.management.base import BaseCommand

from adminpanel.models import Provider

logger = logging.getLogger(__name__)

# Coordonnées approximatives des villes ivoiriennes (lat, lon)
CITY_COORDS = {
    'abidjan': (5.3363, -4.0273),
    'cocody': (5.3575, -3.9866),
    'plateau': (5.3363, -4.0273),
    'treichville': (5.3000, -4.0067),
    'adjamé': (5.3273, -4.0300),
    'yopougon': (5.3322, -4.0786),
    'koumassi': (5.2950, -3.9600),
    'port-bouët': (5.2590, -3.8830),
    'marcory': (5.3100, -3.9900),
    'abobo': (5.4117, -4.0269),
    'attécoubé': (5.3200, -4.0400),
    'grand-bassam': (5.1958, -3.7358),
    'bassam': (5.1958, -3.7358),
    'bingerville': (5.3556, -3.8852),
    'anyama': (5.4500, -4.0500),
    'songon': (5.3200, -4.2200),
    'aboisso': (5.4678, -3.2072),
    'adiaké': (5.2863, -3.3089),
    'agboville': (5.9281, -4.2136),
    'alepe': (5.5065, -3.6586),
    'bouaké': (7.6858, -5.0300),
    'bouake': (7.6858, -5.0300),
    'daloa': (6.8774, -6.4502),
    'duekoué': (6.7420, -7.3492),
    'duekoue': (6.7420, -7.3492),
    'gagnoa': (6.1319, -5.9506),
    'korhogo': (9.4585, -5.6303),
    'man': (7.4120, -7.5530),
    'san-pédro': (4.7480, -6.6363),
    'san pedro': (4.7480, -6.6363),
    'sassandra': (4.9500, -6.0833),
    'yamoussoukro': (6.8206, -5.2767),
    'dabou': (5.3256, -4.3769),
    'grand-lahou': (5.1401, -5.0187),
    'grand lahou': (5.1401, -5.0187),
    'jacqueville': (5.2000, -4.4167),
    'tiassalé': (5.8983, -4.8289),
    'tiassale': (5.8983, -4.8289),
    'soubré': (5.7833, -6.6000),
    'soubre': (5.7833, -6.6000),
    'abengourou': (6.7297, -3.4964),
    'bondoukou': (8.0333, -2.8000),
    'ferkessédougou': (9.5939, -5.1950),
    'ferkessedougou': (9.5939, -5.1950),
    'dimbokro': (6.6467, -4.7050),
    'katiola': (8.1378, -5.1006),
    'béoumi': (7.6739, -5.5800),
    'beoumi': (7.6739, -5.5800),
    'sakassou': (7.4333, -5.2833),
    'touba': (8.2833, -7.6833),
    'odienné': (9.5000, -7.5667),
    'odienne': (9.5000, -7.5667),
    'séguéla': (7.9667, -6.6667),
    'seguela': (7.9667, -6.6667),
    'mankono': (8.0667, -6.1833),
    'vavoua': (7.3833, -6.4833),
    'zuénoula': (7.5667, -6.0500),
    'zuenoula': (7.5667, -6.0500),
    'bouna': (9.2667, -3.0000),
    'tanda': (7.8000, -3.1667),
    'daoukro': (7.0500, -3.9667),
    'mbahiakro': (7.4500, -4.3333),
}


def _fuzz(d: float, spread: float = 0.005) -> float:
    """Ajoute un petit décalage aléatoire (±spread) pour éviter que tous les
    prestataires d'une même ville soient pile au même point GPS."""
    return round(d + random.uniform(-spread, spread), 6)


class Command(BaseCommand):
    help = 'Assigne des coordonnées GPS aux prestataires sans lat/lon (basé sur la ville).'

    def add_arguments(self, parser):
        parser.add_argument('--dry-run', action='store_true', help='Affiche ce qui serait modifié sans sauvegarder.')

    def handle(self, *args, **options):
        dry_run = options['dry_run']
        qs = Provider.objects.filter(latitude__isnull=True, longitude__isnull=True)
        total = qs.count()
        if total == 0:
            self.stdout.write(self.style.SUCCESS('Aucun prestataire sans coordonnées. Rien à faire.'))
            return

        self.stdout.write(f'{total} prestataire(s) sans GPS trouvé(s).')
        updated = 0
        not_found = []

        for p in qs:
            ville_key = p.ville.strip().lower()
            coords = CITY_COORDS.get(ville_key)

            if not coords:
                not_found.append(f'  ID={p.id} ville="{p.ville}" — aucune coordonnée connue')
                continue

            lat, lon = coords
            lat = _fuzz(lat)
            lon = _fuzz(lon)

            if dry_run:
                self.stdout.write(f'  ID={p.id} "{p.nom}" ({p.ville}) → {lat}, {lon}')
            else:
                p.latitude = lat
                p.longitude = lon
                p.save(update_fields=['latitude', 'longitude'])
            updated += 1

        if not_found:
            self.stdout.write(self.style.WARNING(f'\nVilles non reconnues ({len(not_found)}) :'))
            for line in not_found:
                self.stdout.write(line)

        if dry_run:
            self.stdout.write(self.style.SUCCESS(f'\nDry-run : {updated}/{total} auraient des coordonnées.'))
        else:
            self.stdout.write(self.style.SUCCESS(f'\n{updated}/{total} prestataires mis à jour avec des coordonnées GPS.'))
