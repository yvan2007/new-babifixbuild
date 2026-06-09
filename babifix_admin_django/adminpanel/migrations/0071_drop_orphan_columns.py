"""Supprime les colonnes ORPHELINES laissées par 0057.

0057 a retiré certains champs de l'ÉTAT Django (sans supprimer les colonnes en
base). Sur une base PostgreSQL neuve (Render), ces colonnes existent toujours,
parfois NOT NULL sans défaut → tout INSERT échoue (ex. inscription :
« null value in column "phone_verified" »).

Comme ces champs ne font plus partie d'aucun modèle (et ne sont pas re-créés
par une migration ultérieure), on supprime les colonnes pour aligner la base
sur l'état. Idempotent (DROP seulement si la colonne existe) et compatible
MySQL (local) + PostgreSQL (Render).
"""
from django.db import migrations


# table -> noms de champs retirés de l'état en 0057 et JAMAIS re-créés ensuite.
_ORPHANS = {
    "adminpanel_userprofile": ["phone_verified"],
    "adminpanel_reservation": [
        "cancellation_by", "cancellation_motif", "cancellation_stage",
        "cancelled_at", "created_at", "updated_at",
    ],
    "adminpanel_platformrevenue": ["refunded_at"],
    "adminpanel_provider": ["has_used_premium_trial", "is_premium_annual"],
}


def drop_orphans(apps, schema_editor):
    conn = schema_editor.connection
    quote = conn.ops.quote_name
    for table, names in _ORPHANS.items():
        with conn.cursor() as cur:
            existing = {
                c.name for c in conn.introspection.get_table_description(cur, table)
            }
        for n in names:
            # Gère aussi les colonnes de clé étrangère (suffixe _id).
            for col in (n, n + "_id"):
                if col in existing:
                    schema_editor.execute(
                        f"ALTER TABLE {quote(table)} DROP COLUMN {quote(col)}"
                    )


class Migration(migrations.Migration):

    dependencies = [
        ('adminpanel', '0070_devicetoken_app'),
    ]

    operations = [
        migrations.RunPython(drop_orphans, migrations.RunPython.noop),
    ]
