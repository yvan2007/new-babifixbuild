from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("adminpanel", "0029_actualite_cible"),
    ]

    operations = [
        migrations.AddField(
            model_name="provider",
            name="contrat_accepte_at",
            field=models.DateTimeField(
                blank=True,
                null=True,
                help_text="Horodatage de l'acceptation du contrat BABIFIX",
            ),
        ),
        migrations.AddField(
            model_name="provider",
            name="contrat_version",
            field=models.CharField(
                blank=True,
                default="",
                max_length=10,
                help_text="Version du contrat signé (ex: '1.0', '1.1')",
            ),
        ),
    ]
