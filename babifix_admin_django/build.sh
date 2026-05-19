#!/usr/bin/env bash
set -o errexit
pip install -r requirements.txt
python manage.py collectstatic --no-input
python manage.py migrate

# Superadmin auto (variables depuis env Render : DJANGO_SUPERUSER_USERNAME, _EMAIL, _PASSWORD)
python manage.py createsuperuser --noinput || true

# Seed initial des catégories + commissions si la base est vide.
# Idempotent : ne re-seed PAS si des catégories existent déjà.
python manage.py shell -c "
from adminpanel.models import Category
if Category.objects.count() == 0:
    print('[seed] Base vide → chargement des fixtures…')
    from django.core.management import call_command
    call_command('loaddata', 'adminpanel/fixtures/categories.json')
    call_command('loaddata', 'adminpanel/fixtures/commissions.json')
    print('[seed] Catégories + commissions chargées.')
else:
    print(f'[seed] Skip — déjà {Category.objects.count()} catégories en base.')
" || echo "[seed] Échec non bloquant — vérifier manuellement"
