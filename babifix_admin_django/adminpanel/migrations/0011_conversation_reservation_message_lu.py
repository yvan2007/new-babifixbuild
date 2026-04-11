# Generated manually for BABIFIX v7 — chat par réservation + messages lus

from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
        ('adminpanel', '0010_actualite_provider_client'),
    ]

    operations = [
        migrations.RemoveConstraint(
            model_name='conversation',
            name='unique_conversation_client_prestataire',
        ),
        migrations.AddField(
            model_name='conversation',
            name='reservation',
            field=models.OneToOneField(
                blank=True,
                null=True,
                on_delete=models.CASCADE,
                related_name='chat_conversation',
                to='adminpanel.reservation',
            ),
        ),
        migrations.AddField(
            model_name='message',
            name='lu',
            field=models.BooleanField(db_index=True, default=False, help_text='Lu par le destinataire (pas l’expéditeur)'),
        ),
    ]
