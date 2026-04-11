from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ('adminpanel', '0014_rating_photo_attachments'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='AdminAuditLog',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('action', models.CharField(
                    choices=[
                        ('provider_accepted', 'Prestataire accepté'),
                        ('provider_refused', 'Prestataire refusé'),
                        ('provider_suspended', 'Prestataire suspendu'),
                        ('litige_resolved', 'Litige résolu'),
                        ('bulk_accept', 'Validation en masse'),
                        ('bulk_refuse', 'Refus en masse'),
                        ('payment_validated', 'Paiement validé'),
                        ('other', 'Autre'),
                    ],
                    default='other',
                    max_length=40,
                )),
                ('target_type', models.CharField(blank=True, default='', max_length=40)),
                ('target_id', models.IntegerField(blank=True, null=True)),
                ('target_label', models.CharField(blank=True, default='', max_length=200)),
                ('details', models.JSONField(blank=True, default=dict)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('admin_user', models.ForeignKey(
                    blank=True,
                    null=True,
                    on_delete=django.db.models.deletion.SET_NULL,
                    related_name='audit_logs',
                    to=settings.AUTH_USER_MODEL,
                )),
            ],
            options={
                'verbose_name': 'Journal admin',
                'ordering': ['-created_at'],
            },
        ),
    ]
