"""Phase C — Conversation unique + bloc devis ancré.

- Ajoute `kind` et `payload_json` au modèle Message pour permettre
  l'injection de cartes devis figées et d'événements système dans le fil
  de chat unique de chaque réservation.
"""

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("adminpanel", "0042_reservation_funds_released_at"),
    ]

    operations = [
        migrations.AddField(
            model_name="message",
            name="kind",
            field=models.CharField(
                choices=[
                    ("USER", "Message utilisateur"),
                    ("DEVIS_CARD", "Carte devis ancrée"),
                    ("SYSTEM", "Événement système"),
                ],
                db_index=True,
                default="USER",
                help_text=(
                    "USER = message libre. DEVIS_CARD = devis figé ancré au fil. "
                    "SYSTEM = événement (démarrage/fin/paiement)."
                ),
                max_length=16,
            ),
        ),
        migrations.AddField(
            model_name="message",
            name="payload_json",
            field=models.JSONField(
                blank=True,
                help_text=(
                    "Données structurées pour les messages DEVIS_CARD/SYSTEM "
                    "(montants, références, statuts…)."
                ),
                null=True,
            ),
        ),
    ]
