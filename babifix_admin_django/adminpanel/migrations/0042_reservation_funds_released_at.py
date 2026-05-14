"""Phase F — Escrow paiement.

Ajoute `funds_released_at` à `Reservation`. Tant que ce champ est null, les
fonds restent bloqués côté plateforme (escrow). Il n'est renseigné qu'après
appel à `EscrowService.release_funds(reservation)`, lui-même déclenché par
`api_client_confirmer_travaux`.
"""

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("adminpanel", "0041_devis_net_prestataire"),
    ]

    operations = [
        migrations.AddField(
            model_name="reservation",
            name="funds_released_at",
            field=models.DateTimeField(
                blank=True,
                null=True,
                help_text=(
                    "Horodatage de libération escrow. Null = fonds encore bloqués. "
                    "Set après client_confirme_prestation_at via EscrowService.release_funds."
                ),
            ),
        ),
    ]
