# Generated manually — BABIFIX validation prestataire

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('adminpanel', '0004_uml_alignment'),
    ]

    operations = [
        migrations.AddField(
            model_name='provider',
            name='photo_portrait_url',
            field=models.CharField(
                blank=True,
                default='',
                help_text='Photo de profil (URL) — visible apres validation admin',
                max_length=500,
            ),
        ),
        migrations.AddField(
            model_name='provider',
            name='refusal_reason',
            field=models.TextField(
                blank=True,
                default='',
                help_text='Motif affiche au prestataire si dossier refuse',
            ),
        ),
        migrations.AlterField(
            model_name='provider',
            name='statut',
            field=models.CharField(
                choices=[
                    ('En attente', 'En attente'),
                    ('Valide', 'Valide'),
                    ('Suspendu', 'Suspendu'),
                    ('Refuse', 'Refuse'),
                ],
                default='En attente',
                max_length=20,
            ),
        ),
    ]
