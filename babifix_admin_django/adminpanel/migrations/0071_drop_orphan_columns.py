"""Supprime les colonnes ORPHELINES laissées par 0057.

0057 a retiré certains champs de l'ÉTAT Django (sans supprimer les colonnes en
base). Sur une base PostgreSQL neuve (Render), ces colonnes existent toujours,
parfois NOT NULL sans défaut → tout INSERT échoue (ex. inscription :
« null value in column "phone_verified" »).

Comme ces champs ne font plus partie d'aucun modèle (et ne sont pas re-créés
par une migration ultérieure), on supprime les colonnes pour aligner la base
sur l'état. Idempotent (DROP seulement si la colonne existe) et compatible
MySQL (local) + PostgreSQL (Render).

CORRECTIF PORTABILITE SQLite (2026-10-21) : PostgreSQL et MySQL suppriment
automatiquement les index qui dépendent d'une colonne supprimée. SQLite NON :
l'index survit et pointe vers une colonne disparue, ce qui fait échouer la
migration avec « error in index ... after drop column ». On supprime donc
explicitement les index de chaque colonne AVANT de la supprimer. Sur
PostgreSQL/MySQL, s'il n'y a aucun index à supprimer, la boucle ne fait rien :
le comportement d'origine est préservé à l'identique.
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


def _indexes_sur_colonne(conn, table, colonne):
    """Renvoie les noms d'index SQLite qui portent sur `colonne`.

    Utilise uniquement sur SQLite : PRAGMA index_info donne, pour chaque index,
    la liste de ses colonnes. Ailleurs, on ne touche pas aux index (les moteurs
    les nettoient seuls), donc la fonction n'est pas appelée.
    """
    if conn.vendor != "sqlite":
        return []
    noms = []
    with conn.cursor() as cur:
        for (nom_index,) in cur.execute(
            f"SELECT name FROM sqlite_master WHERE type='index' AND tbl_name=%s",
            [table],
        ).fetchall():
            # Les index auto (sqlite_autoindex_*) ne peuvent pas être supprimés
            # directement : ils disparaissent avec la table/colonne.
            if nom_index.startswith("sqlite_autoindex_"):
                continue
            colonnes = [
                ligne[2] for ligne in cur.execute(f"PRAGMA index_info({nom_index})")
            ]
            if colonne in colonnes:
                noms.append(nom_index)
    return noms


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
                    # SQLite garde les index après un DROP COLUMN : on les
                    # supprime d'abord, sinon la migration échoue.
                    for nom_index in _indexes_sur_colonne(conn, table, col):
                        schema_editor.execute(
                            f"DROP INDEX IF EXISTS {quote(nom_index)}"
                        )
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
