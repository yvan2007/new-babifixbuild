from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("adminpanel", "0028_provider_wallet_wallettransaction"),
    ]

    operations = [
        migrations.AddField(
            model_name="actualite",
            name="cible",
            field=models.CharField(
                choices=[
                    ("client", "Client uniquement"),
                    ("prestataire", "Prestataire uniquement"),
                    ("tous", "Tous les utilisateurs"),
                ],
                db_index=True,
                default="tous",
                help_text="Audience : client uniquement, prestataire uniquement, ou tous",
                max_length=20,
            ),
        ),
    ]
