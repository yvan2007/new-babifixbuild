# MySQL utf8mb4 : index UNIQUE limité (~191 car.) — raccourcit le jeton FCM si ancienne migration 0006 en 512.

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('adminpanel', '0008_alter_systemsetting_mode_paiement'),
    ]

    operations = [
        migrations.AlterField(
            model_name='devicetoken',
            name='token',
            field=models.CharField(db_index=True, max_length=191, unique=True),
        ),
    ]
