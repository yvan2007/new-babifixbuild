# Ajoute les 5 champs d'adresse structurés à Reservation (rue, quartier,
# ville, pays, repère) pour un affichage pro côté prestataire — au-delà
# du simple `address_label` qui reste comme résumé.
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('adminpanel', '0055_merge_20260528_2135'),
    ]

    operations = [
        migrations.AddField(
            model_name='reservation',
            name='address_street',
            field=models.CharField(blank=True, default='', max_length=200),
        ),
        migrations.AddField(
            model_name='reservation',
            name='address_quartier',
            field=models.CharField(blank=True, default='', max_length=120),
        ),
        migrations.AddField(
            model_name='reservation',
            name='address_ville',
            field=models.CharField(blank=True, default='', max_length=120),
        ),
        migrations.AddField(
            model_name='reservation',
            name='address_pays',
            field=models.CharField(blank=True, default="Côte d'Ivoire", max_length=80),
        ),
        migrations.AddField(
            model_name='reservation',
            name='address_repere',
            field=models.CharField(blank=True, default='', max_length=300),
        ),
    ]
