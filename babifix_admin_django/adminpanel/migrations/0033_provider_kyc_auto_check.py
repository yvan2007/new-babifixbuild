from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("adminpanel", "0032_platform_revenue_rating_voice"),
    ]

    operations = [
        migrations.AddField(
            model_name="provider",
            name="auto_check_score",
            field=models.IntegerField(
                default=0,
                help_text="Score de vérification automatique 0–100 (moteur KYC engine)",
            ),
        ),
        migrations.AddField(
            model_name="provider",
            name="auto_check_result",
            field=models.JSONField(
                blank=True,
                default=dict,
                help_text="Résultat détaillé du moteur KYC (checks, confiance, visages)",
            ),
        ),
        migrations.AddField(
            model_name="provider",
            name="auto_check_at",
            field=models.DateTimeField(
                blank=True,
                null=True,
                help_text="Date/heure du dernier passage du moteur de vérification automatique",
            ),
        ),
    ]
