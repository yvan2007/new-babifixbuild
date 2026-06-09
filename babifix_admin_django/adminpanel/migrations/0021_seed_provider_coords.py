"""
Data migration : assigner des coordonnées GPS aux prestataires qui n'en ont pas,
en fonction de leur ville déclarée.
"""
import random

from django.db import migrations

VILLE_COORDS = {
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
    'yamoussoukro': (6.8206, -5.2767),
    'dabou': (5.3256, -4.3769),
    'bouake': (7.6858, -5.0300),
    'soubré': (5.7833, -6.6000),
    'soubre': (5.7833, -6.6000),
    'abengourou': (6.7297, -3.4964),
    'bondoukou': (8.0333, -2.8000),
    'dimbokro': (6.6467, -4.7050),
    'odienné': (9.5000, -7.5667),
    'odienne': (9.5000, -7.5667),
    'séguéla': (7.9667, -6.6667),
    'seguela': (7.9667, -6.6667),
}


def _fuzz(d, spread=0.005):
    return round(d + random.uniform(-spread, spread), 6)


def seed_provider_coords(apps, schema_editor):
    Provider = apps.get_model('adminpanel', 'Provider')
    for p in Provider.objects.filter(latitude__isnull=True, longitude__isnull=True):
        ville = (p.ville or '').strip().lower()
        coords = VILLE_COORDS.get(ville)
        if coords:
            p.latitude = _fuzz(coords[0])
            p.longitude = _fuzz(coords[1])
            p.save(update_fields=['latitude', 'longitude'])


class Migration(migrations.Migration):

    dependencies = [
        ('adminpanel', '0020_prix_propose_cni_recto_verso'),
    ]

    operations = [
        migrations.RunPython(seed_provider_coords, reverse_code=migrations.RunPython.noop),
    ]
