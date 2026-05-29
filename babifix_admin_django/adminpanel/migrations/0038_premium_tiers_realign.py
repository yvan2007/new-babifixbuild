from django.db import migrations, models


def bronze_to_silver(apps, schema_editor):
    """Réaligne les paliers : 'bronze' (supprimé) → 'silver' (palier payant d'entrée)."""
    Provider = apps.get_model("adminpanel", "Provider")
    Provider.objects.filter(premium_tier="bronze").update(premium_tier="silver")


def noop_reverse(apps, schema_editor):
    pass


class Migration(migrations.Migration):

    dependencies = [
        ("adminpanel", "0037_category_is_deleted_alter_category_actif"),
    ]

    operations = [
        migrations.AlterField(
            model_name="provider",
            name="is_premium",
            field=models.BooleanField(
                db_index=True,
                default=False,
                help_text="Abonnement premium payant actif (silver/gold)",
            ),
        ),
        migrations.AlterField(
            model_name="provider",
            name="premium_tier",
            field=models.CharField(
                blank=True,
                choices=[
                    ("standard", "Standard"),
                    ("silver", "Silver"),
                    ("gold", "Gold"),
                ],
                default="",
                max_length=20,
            ),
        ),
        migrations.RunPython(bronze_to_silver, noop_reverse),
    ]
