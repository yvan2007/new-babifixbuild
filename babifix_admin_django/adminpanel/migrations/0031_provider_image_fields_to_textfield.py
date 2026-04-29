from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("adminpanel", "0030_provider_contrat_signature"),
    ]

    operations = [
        migrations.AlterField(
            model_name="provider",
            name="cni_url",
            field=models.TextField(blank=True, default=""),
        ),
        migrations.AlterField(
            model_name="provider",
            name="cni_recto_url",
            field=models.TextField(blank=True, default="", help_text="CNI face avant"),
        ),
        migrations.AlterField(
            model_name="provider",
            name="cni_verso_url",
            field=models.TextField(blank=True, default="", help_text="CNI face arrière"),
        ),
        migrations.AlterField(
            model_name="provider",
            name="selfie_url",
            field=models.TextField(
                blank=True,
                default="",
                help_text="Selfie avec CNI - validation identité",
            ),
        ),
        migrations.AlterField(
            model_name="provider",
            name="video_intro_url",
            field=models.TextField(
                blank=True,
                default="",
                help_text="Vidéo intro 30-60s - filtre qualité",
            ),
        ),
        migrations.AlterField(
            model_name="provider",
            name="photo_portrait_url",
            field=models.TextField(
                blank=True,
                default="",
                help_text="Photo de profil (URL) — visible après validation admin",
            ),
        ),
    ]
