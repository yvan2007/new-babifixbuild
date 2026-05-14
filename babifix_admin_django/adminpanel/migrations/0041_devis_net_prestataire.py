"""Phase A — Fix calcul devis.

Ajoute le champ `net_prestataire` au modèle `Devis` et recalcule les devis
existants selon la nouvelle règle métier BABIFIX :

- total_ttc          = sous_total   (ce que paye le client)
- commission_montant = sous_total * commission_rate / 100  (notre part)
- net_prestataire    = sous_total - commission_montant      (sa part)

Avant ce fix, `total_ttc = sous_total + commission_montant`, ce qui faisait
payer au client la commission EN PLUS du devis. Bug confirmé par le métier
et corrigé ici.

On ne recalcule QUE les devis non encore acceptés/payés (BROUILLON, ENVOYE,
EXPIRE) pour ne pas réécrire l'historique financier réel.
"""
from decimal import Decimal

from django.db import migrations, models


def recompute_pending_devis(apps, schema_editor):
    Devis = apps.get_model("adminpanel", "Devis")
    qs = Devis.objects.filter(statut__in=["BROUILLON", "ENVOYE", "EXPIRE"])
    for devis in qs.iterator():
        sous_total = sum(
            (l.quantite * l.prix_unitaire for l in devis.lignes.all()),
            Decimal("0"),
        )
        rate = Decimal(str(devis.commission_rate or 0))
        commission = (sous_total * rate / Decimal("100")).quantize(Decimal("0.01"))
        devis.sous_total = sous_total
        devis.commission_montant = commission
        devis.total_ttc = sous_total
        devis.net_prestataire = sous_total - commission
        devis.save(
            update_fields=[
                "sous_total",
                "commission_montant",
                "total_ttc",
                "net_prestataire",
            ]
        )


def noop_reverse(apps, schema_editor):
    # Pas de rollback financier — on garde simplement le champ.
    pass


class Migration(migrations.Migration):

    dependencies = [
        ("adminpanel", "0040_payment_commission_nullable"),
    ]

    operations = [
        migrations.AddField(
            model_name="devis",
            name="net_prestataire",
            field=models.DecimalField(
                decimal_places=2,
                default=0,
                help_text="Montant reversé au prestataire = sous_total - commission_montant",
                max_digits=12,
            ),
        ),
        migrations.AlterField(
            model_name="devis",
            name="sous_total",
            field=models.DecimalField(
                decimal_places=2,
                default=0,
                help_text="Total HT des lignes du devis = ce que le client paye",
                max_digits=12,
            ),
        ),
        migrations.AlterField(
            model_name="devis",
            name="commission_montant",
            field=models.DecimalField(
                decimal_places=2,
                default=0,
                help_text="Part BABIFIX, DÉDUITE du sous_total (jamais ajoutée au client)",
                max_digits=12,
            ),
        ),
        migrations.AlterField(
            model_name="devis",
            name="total_ttc",
            field=models.DecimalField(
                decimal_places=2,
                default=0,
                help_text="Montant final payé par le client (= sous_total)",
                max_digits=12,
            ),
        ),
        migrations.RunPython(recompute_pending_devis, noop_reverse),
    ]
