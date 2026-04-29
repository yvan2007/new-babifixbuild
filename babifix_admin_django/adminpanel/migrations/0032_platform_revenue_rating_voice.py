from django.db import migrations, models
import django.db.models.deletion
import django.utils.timezone


class Migration(migrations.Migration):

    dependencies = [
        ("adminpanel", "0031_provider_image_fields_to_textfield"),
    ]

    operations = [
        # ── Rating.voice_note_url ───────────────────────────────────────────
        migrations.AddField(
            model_name="rating",
            name="voice_note_url",
            field=models.CharField(
                blank=True,
                default="",
                max_length=500,
                help_text="URL de la note vocale (fichier audio uploadé)",
            ),
        ),
        # ── PlatformRevenue ─────────────────────────────────────────────────
        migrations.CreateModel(
            name="PlatformRevenue",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False)),
                ("amount_fcfa", models.DecimalField(decimal_places=2, max_digits=14)),
                (
                    "source",
                    models.CharField(
                        choices=[
                            ("commission", "Commission prestation"),
                            ("premium", "Abonnement premium"),
                            ("penalite", "Pénalité"),
                            ("autre", "Autre"),
                        ],
                        default="commission",
                        max_length=20,
                    ),
                ),
                ("reference", models.CharField(blank=True, default="", max_length=100)),
                ("description", models.TextField(blank=True, default="")),
                (
                    "payment",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="platform_revenues",
                        to="adminpanel.payment",
                    ),
                ),
                ("created_at", models.DateTimeField(default=django.utils.timezone.now)),
            ],
            options={"ordering": ["-created_at"]},
        ),
        # ── Reservation.urgence_surcharge_pct ──────────────────────────────
        migrations.AddField(
            model_name="reservation",
            name="urgence_surcharge_pct",
            field=models.PositiveSmallIntegerField(
                default=0,
                help_text="Surcharge urgence appliquée en % (ex: 20 = +20%)",
            ),
        ),
        # ── UserProfile.whatsapp_opt_in ─────────────────────────────────────
        migrations.AddField(
            model_name="userprofile",
            name="whatsapp_opt_in",
            field=models.BooleanField(
                default=True,
                help_text="Accepte de recevoir des notifications WhatsApp",
            ),
        ),
    ]
