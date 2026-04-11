# Generated manually for Cote d'Ivoire Mobile Money operators

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('adminpanel', '0006_device_token_fcm'),
    ]

    operations = [
        migrations.AddField(
            model_name='reservation',
            name='mobile_money_operator',
            field=models.CharField(
                blank=True,
                choices=[
                    ('', 'Non precise'),
                    ('ORANGE_MONEY', 'Orange Money'),
                    ('MTN_MOMO', 'MTN Mobile Money'),
                    ('WAVE', 'Wave'),
                    ('MOOV', 'Moov Money'),
                ],
                default='',
                help_text="Si paiement Mobile Money : Orange, MTN, Wave, Moov (Cote d'Ivoire).",
                max_length=24,
            ),
        ),
    ]
