"""Helpers de compatibilité migrations (fichier ignoré par le loader Django car
préfixé « _ »).

Contexte : la migration 0057 a retiré certains champs de l'ÉTAT Django via
`SeparateDatabaseAndState(database_operations=[])` — sans supprimer les colonnes
en base. Sur la base MySQL locale (déjà migrée) tout est cohérent, mais sur une
base PostgreSQL **neuve** (Render), ces colonnes existent déjà (créées par des
migrations antérieures à 0057). Les migrations 0058+ qui les « re-créent »
échouent alors avec « column already exists ».

`add_missing` ajoute uniquement les colonnes RÉELLEMENT absentes — idempotent et
compatible MySQL + PostgreSQL.
"""


def add_missing(apps, schema_editor, model_name, fields):
    """Ajoute en base les champs dont la colonne n'existe pas encore.

    fields : liste de tuples (nom_attribut, instance_de_field).
    """
    model = apps.get_model("adminpanel", model_name)
    table = model._meta.db_table
    conn = schema_editor.connection
    with conn.cursor() as cursor:
        existing = {
            col.name for col in conn.introspection.get_table_description(cursor, table)
        }
    for attr_name, field in fields:
        f = field.clone()
        f.set_attributes_from_name(attr_name)
        if f.column in existing:
            continue
        schema_editor.add_field(model, f)
