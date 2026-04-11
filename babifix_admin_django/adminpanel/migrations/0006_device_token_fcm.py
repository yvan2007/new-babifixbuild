# Generated manually for FCM device tokens

import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
        ('adminpanel', '0005_provider_portrait_refusal'),
    ]

    operations = [
        migrations.CreateModel(
            name='DeviceToken',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('token', models.CharField(db_index=True, max_length=191, unique=True)),
                ('platform', models.CharField(choices=[('android', 'Android'), ('ios', 'iOS'), ('web', 'Web')], default='android', max_length=16)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('user', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='fcm_device_tokens', to=settings.AUTH_USER_MODEL)),
            ],
            options={
                'ordering': ['-updated_at'],
            },
        ),
    ]
