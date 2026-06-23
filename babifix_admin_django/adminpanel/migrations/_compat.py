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
        # Les FK vers un modèle référencé par chaîne (ex. settings.AUTH_USER_MODEL
        # = 'auth.User') ne se résolvent pas toujours sur une base NEUVE
        # (« Related model 'auth.user' cannot be resolved »). On pointe la cible
        # sur le modèle historique de l'état de migration → résolution fiable.
        rf = getattr(f, "remote_field", None)
        if rf is not None and isinstance(getattr(rf, "model", None), str):
            try:
                target = apps.get_model(rf.model)
                rf.model = target
                # Sans field_name, schema_editor cherche un champ « None » sur la
                # cible → on pointe sur sa clé primaire (généralement « id »).
                if not getattr(rf, "field_name", None):
                    rf.field_name = target._meta.pk.name
            except Exception:
                pass
        if f.column in existing:
            continue
        schema_editor.add_field(model, f)
