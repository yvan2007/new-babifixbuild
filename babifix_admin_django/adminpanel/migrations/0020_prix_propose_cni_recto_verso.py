from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('adminpanel', '0019_clientfavorite'),
    ]

    operations = [
        migrations.AddField(
            model_name='reservation',
            name='prix_propose',
            field=models.DecimalField(
                blank=True, decimal_places=2, max_digits=10, null=True,
                help_text='Prix proposé par le client (optionnel — si différent du tarif catalogue)',
            ),
        ),
        migrations.AddField(
            model_name='provider',
            name='cni_recto_url',
            field=models.CharField(blank=True, default='', max_length=500, help_text='CNI face avant'),
        ),
        migrations.AddField(
            model_name='provider',
            name='cni_verso_url',
            field=models.CharField(blank=True, default='', max_length=500, help_text='CNI face arrière'),
        ),
    ]
