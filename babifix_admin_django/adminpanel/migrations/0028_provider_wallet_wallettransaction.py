"""
Migration 0028 — Wallet prestataire :
  • Ajoute solde_fcfa, wallet_phone, wallet_operator au modèle Provider
  • Crée le modèle WalletTransaction (historique mouvements)
"""

import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("adminpanel", "0027_remove_provider_deleted_at_provider_is_premium_and_more"),
    ]

    operations = [
        # Champs wallet sur Provider
        migrations.AddField(
            model_name="provider",
            name="solde_fcfa",
            field=models.DecimalField(
                decimal_places=2,
                default=0,
                help_text="Solde disponible pour retrait (FCFA)",
                max_digits=12,
            ),
        ),
        migrations.AddField(
            model_name="provider",
            name="wallet_phone",
            field=models.CharField(
                blank=True,
                default="",
                help_text="Numéro Mobile Money pour les retraits",
                max_length=20,
            ),
        ),
        migrations.AddField(
            model_name="provider",
            name="wallet_operator",
            field=models.CharField(
                blank=True,
                choices=[
                    ("mtn", "MTN Mobile Money"),
                    ("orange", "Orange Money"),
                    ("wave", "Wave"),
                    ("moov", "Moov Money"),
                ],
                default="",
                help_text="Opérateur Mobile Money préféré",
                max_length=20,
            ),
        ),
        # Modèle WalletTransaction
        migrations.CreateModel(
            name="WalletTransaction",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False)),
                (
                    "provider",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="wallet_transactions",
                        to="adminpanel.provider",
                    ),
                ),
                (
                    "tx_type",
                    models.CharField(
                        choices=[
                            ("credit", "Crédit (paiement reçu)"),
                            ("debit", "Débit (retrait)"),
                            ("commission", "Commission BABIFIX"),
                            ("refund", "Remboursement"),
                        ],
                        max_length=12,
                    ),
                ),
                ("amount_fcfa", models.DecimalField(decimal_places=2, max_digits=12)),
                (
                    "status",
                    models.CharField(
                        choices=[
                            ("pending", "En attente"),
                            ("success", "Réussi"),
                            ("failed", "Échoué"),
                        ],
                        default="success",
                        max_length=10,
                    ),
                ),
                ("reference", models.CharField(blank=True, default="", max_length=100)),
                ("description", models.TextField(blank=True, default="")),
                ("operator", models.CharField(blank=True, default="", max_length=20)),
                ("phone", models.CharField(blank=True, default="", max_length=20)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
            ],
            options={
                "ordering": ["-created_at"],
                "indexes": [
                    models.Index(fields=["provider", "-created_at"], name="wallet_tx_provider_idx"),
                ],
            },
        ),
    ]
