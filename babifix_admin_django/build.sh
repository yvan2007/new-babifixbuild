#!/usr/bin/env bash
set -o errexit
pip install -r requirements.txt
python manage.py collectstatic --no-input
python manage.py migrate
# Créer le superadmin automatiquement si inexistant (variables depuis env Render)
python manage.py createsuperuser --noinput || true
