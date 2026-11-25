#!/usr/bin/env bash
set -o errexit
pip install -r requirements.txt
python manage.py collectstatic --no-input
python manage.py migrate

# ── RESET COMPLET DE LA BASE (optionnel, sur demande) ───────────────────────
# Met la variable RESET_DATABASE=true dans Render → Environment pour vider
# TOUTES les données (comptes, réservations, paiements, messages, devis…) au
# prochain déploiement. Le schéma reste, les catégories se re-sèment ensuite.
# ⚠️ IRRÉVERSIBLE. Après le wipe, REMETS RESET_DATABASE=false (ou supprime la
#    variable) sinon CHAQUE déploiement effacera de nouveau les données.
if [ "${RESET_DATABASE}" = "true" ]; then
  echo "⚠️⚠️  RESET_DATABASE=true → suppression de TOUTES les données (flush)…"
  python manage.py flush --no-input
  echo "✅  Base vidée. Pense à remettre RESET_DATABASE=false."
fi

# ── CATALOGUE MÉTIER (idempotent) ───────────────────────────────────────────
# Sème / met à jour les 77 catégories (depuis data/categories-services-domicile.json).
# Indispensable : sans ça la table Category est vide sur une base fraîche →
# l'app prestataire n'affiche AUCUNE spécialité à l'inscription.
# update_or_create => rejouable sans risque.
python manage.py import_babifix_categories || true
# NB : `seed_catalogue` retiré — il importait le modèle CatalogueItem supprimé
# (migration 0057) → ImportError à chaque build (non bloquant mais pollue les logs).

# Créer le superadmin automatiquement si inexistant (variables depuis env Render)
python manage.py createsuperuser --noinput || true
