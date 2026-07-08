"""Settings de test : sqlite en mémoire + migrations désactivées (évite la
migration MySQL-only 0071 qui casse sur sqlite). Schéma construit depuis les
modèles → couvre tous les champs actuels."""
import os
os.environ["MYSQL_DATABASE"] = ""
os.environ["MYSQL_NAME"] = ""
os.environ["DATABASE_URL"] = ""
# Pas de données de démo (le seed Client a une depense mal formatée qui casse
# bulk_create) — on veut des tests déterministes sur nos propres fixtures.
os.environ["BABIFIX_ENABLE_DEMO_SEED"] = "0"

from config.settings import *  # noqa

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.sqlite3",
        "NAME": ":memory:",
    }
}


class _DisableMigrations:
    def __contains__(self, item):
        return True

    def __getitem__(self, item):
        return None


MIGRATION_MODULES = _DisableMigrations()
