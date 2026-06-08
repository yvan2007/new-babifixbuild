"""Seed de démonstration BABIFIX (noms réalistes).

Peuple la base pour le binôme de test :
  - Client      : compte user id 55 (affiché « Awa Traoré »)
  - Prestataire : Provider id 59 / user id 57 (affiché « Koffi Yao »)

Crée des réservations dans TOUS les statuts (demande, devis envoyé, devis
accepté, confirmée/acompte versé, intervention en cours, terminées, annulée),
des lignes de devis détaillées (pour des reçus crédibles), les paiements
correspondants (acompte / solde / commission), les revenus plateforme, le
solde wallet du prestataire et des retraits (réussi + en attente).

Idempotent : supprime d'abord tout ce qui est préfixé BBX- (et l'ancien DEMO-)
avant de recréer.  Lancer :  python seed_demo.py
"""
import os
import django
from decimal import Decimal

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")
django.setup()

from django.contrib.auth.models import User  # noqa: E402
from django.utils import timezone  # noqa: E402
from django.db import transaction  # noqa: E402
from adminpanel.models import (  # noqa: E402
    Reservation, Devis, LigneDevis, Payment, PlatformRevenue, Provider,
    WalletTransaction,
)

CLIENT_USER_ID = 55
PRESTA_USER_ID = 57

# Noms réalistes affichés dans l'app et sur les reçus
CLIENT_FIRST, CLIENT_LAST = "Awa", "Traoré"
CLIENT_LABEL = "Awa Traoré"
PRESTA_NOM = "Koffi Yao"
PRESTA_SPEC = "Plomberie & Électricité"
PRESTA_VILLE = "Abidjan"

prov = Provider.objects.filter(user_id=PRESTA_USER_ID).first()
if not prov:
    raise SystemExit("Provider (user 57) introuvable")

# ─── Noms réalistes sur les comptes (affichage uniquement, login inchangé) ───
prov.nom = PRESTA_NOM
prov.specialite = PRESTA_SPEC
prov.ville = PRESTA_VILLE
prov.save(update_fields=["nom", "specialite", "ville"])

client_user = User.objects.filter(id=CLIENT_USER_ID).first()
if client_user:
    client_user.first_name = CLIENT_FIRST
    client_user.last_name = CLIENT_LAST
    client_user.save(update_fields=["first_name", "last_name"])

PREFIX = "BBX-"            # nouveau préfixe « pro » (références : BBX-2606-01…)
OLD_PREFIX = "DEMO-"       # ancien préfixe à nettoyer


def cleanup():
    for pfx in (PREFIX, OLD_PREFIX):
        Payment.objects.filter(reference__startswith=pfx).delete()
        PlatformRevenue.objects.filter(reference__startswith=pfx).delete()
        WalletTransaction.objects.filter(reference__startswith=pfx).delete()
        # Les LigneDevis et Devis tombent en cascade avec la Reservation
        Reservation.objects.filter(reference__startswith=pfx).delete()
    # Devis orphelins éventuels
    Devis.objects.filter(reference__startswith="DV-").delete()


def mkres(ref, statut, ptype, total, *, acompte_valide=False, montant_verse=0,
          solde_valide=False, terminee=False, confirme=False, released=False,
          operator="", make_devis=True, devis_statut="ACCEPTE",
          title="", msg="Intervention", addr="Cocody, Abidjan", lignes=None):
    total = Decimal(str(total))
    commission = (total * Decimal("0.18")).quantize(Decimal("1"))
    net = total - commission
    res = Reservation.objects.create(
        reference=ref, statut=statut, payment_type=ptype, montant=Decimal("0"),
        title=title or msg,
        client=CLIENT_LABEL, client_user_id=CLIENT_USER_ID,
        prestataire=PRESTA_NOM, prestataire_user_id=PRESTA_USER_ID,
        assigned_provider=prov,
        address_label=addr, address_ville="Abidjan",
        client_message=msg, mobile_money_operator=operator,
        acompte_valide=acompte_valide,
        montant_verse=Decimal(str(montant_verse)),
        montant_restant=(total - Decimal(str(montant_verse))) if make_devis else Decimal("0"),
        solde_valide=solde_valide,
    )
    if terminee:
        res.prestation_terminee_at = timezone.now()
    if confirme:
        res.client_confirme_prestation_at = timezone.now()
    if released:
        res.funds_released_at = timezone.now()
        res.cash_flow_status = "validated"
    if make_devis:
        dv = Devis.objects.create(
            reference="DV-" + ref, reservation=res, prestataire=prov,
            sous_total=total,
            commission_rate=18, commission_montant=commission,
            net_prestataire=net, total_ttc=total,
            statut=devis_statut, diagnostic=msg,
        )
        # Lignes détaillées → reçu crédible. Doivent sommer à `total`.
        for (typ, desc, qte, pu) in (lignes or [("MAIN_OEUVRE", msg, 1, int(total))]):
            LigneDevis.objects.create(
                devis=dv, type_ligne=typ, description=desc,
                quantite=qte, prix_unitaire=Decimal(str(pu)),
            )
        dv.save()  # recalcule sous_total/commission depuis les lignes
        res.montant = total
    res.save()
    return res, commission, net


def pay(ref, total_amount, etat=Payment.State.COMPLETE, type_p=None):
    return Payment.objects.create(
        reference=ref, client=CLIENT_LABEL, prestataire=PRESTA_NOM,
        montant=Decimal(str(total_amount)), commission=Decimal("0"),
        etat=etat, type_paiement=type_p or Payment.TypePaiement.MOBILE_MONEY,
    )


def revenue(ref, amount, desc):
    PlatformRevenue.objects.create(
        amount_fcfa=Decimal(str(amount)), source="commission",
        reference=ref, description=desc,
    )


def wtx(tx_type, amount, status, ref, desc, operator=""):
    WalletTransaction.objects.create(
        provider=prov, tx_type=tx_type, amount_fcfa=Decimal(str(amount)),
        status=status, reference=ref, description=desc, operator=operator,
    )


with transaction.atomic():
    cleanup()

    # 1) Nouvelle demande (pas encore de devis) — espèces
    mkres(PREFIX + "2606-01", "DEMANDE_ENVOYEE", "ESPECES", 0,
          make_devis=False, title="Fuite robinet cuisine",
          msg="Le robinet de la cuisine goutte en continu.")

    # 2) Devis envoyé, en attente d'acceptation — mobile
    mkres(PREFIX + "2606-02", "DEVIS_ENVOYE", "MOBILE_MONEY", 40000,
          devis_statut="ENVOYE", title="Installation chauffe-eau",
          msg="Pose et raccordement d'un chauffe-eau 100 L.",
          lignes=[
              ("FOURNITURE", "Chauffe-eau 100 L", 1, 28000),
              ("MAIN_OEUVRE", "Pose et raccordement", 1, 12000),
          ])

    # 3) Devis accepté, acompte pas encore payé — espèces
    mkres(PREFIX + "2606-03", "DEVIS_ACCEPTE", "ESPECES", 25000,
          title="Réparation prise électrique",
          msg="Remplacement de 3 prises défectueuses au salon.",
          lignes=[
              ("FOURNITURE", "Prises encastrées", 3, 4000),
              ("MAIN_OEUVRE", "Dépose / pose et mise aux normes", 1, 13000),
          ])

    # 4) Confirmée : acompte 30% versé (escrow), en attente intervention — mobile
    mkres(PREFIX + "2606-04", "Confirmee", "MOBILE_MONEY", 30000,
          acompte_valide=True, montant_verse=9000, operator="ORANGE_MONEY",
          title="Peinture salon",
          msg="Peinture complète du salon (2 couches).",
          lignes=[
              ("FOURNITURE", "Peinture acrylique (pots)", 4, 4500),
              ("MAIN_OEUVRE", "Préparation murs + application", 1, 12000),
          ])
    pay(PREFIX + "2606-04-AC", 9000)

    # 5) Intervention en cours — espèces (commission payée en ligne)
    mkres(PREFIX + "2606-05", "INTERVENTION_EN_COURS", "ESPECES", 20000,
          acompte_valide=True, montant_verse=3600, operator="WAVE",
          title="Débouchage canalisation",
          msg="Canalisation de la salle de bain bouchée.",
          lignes=[
              ("MAIN_OEUVRE", "Débouchage haute pression", 1, 15000),
              ("DEPLACEMENT", "Déplacement", 1, 5000),
          ])
    pay(PREFIX + "2606-05-CM", 3600)

    # 6) Terminée payée intégralement (mobile) → libérée au wallet
    _, c6, n6 = mkres(PREFIX + "2606-06", "Terminee", "MOBILE_MONEY", 50000,
                      acompte_valide=True, montant_verse=50000, solde_valide=True,
                      terminee=True, confirme=True, released=True,
                      operator="MTN_MOMO", title="Climatisation — pose complète",
                      msg="Installation d'un split 1.5 CV avec mise en service.",
                      lignes=[
                          ("FOURNITURE", "Climatiseur split 1.5 CV", 1, 38000),
                          ("MAIN_OEUVRE", "Pose, raccordement, mise en service", 1, 12000),
                      ])
    pay(PREFIX + "2606-06-AC", 15000)
    pay(PREFIX + "2606-06-SO", 35000)
    revenue(PREFIX + "2606-06", c6, "Commission 18% — Climatisation")
    wtx("credit", n6, "success", PREFIX + "2606-06", "Libération escrow — Climatisation")
    wtx("commission", c6, "success", PREFIX + "2606-06", "Commission BABIFIX 18% — Climatisation")

    # 7) Terminée espèces : commission encaissée, reste payé cash (pas de wallet)
    _, c7, n7 = mkres(PREFIX + "2606-07", "Terminee", "ESPECES", 35000,
                      acompte_valide=True, montant_verse=6300, solde_valide=True,
                      terminee=True, confirme=True, released=True,
                      operator="", title="Montage meubles",
                      msg="Montage d'une armoire et d'un lit.",
                      lignes=[
                          ("MAIN_OEUVRE", "Montage armoire 3 portes", 1, 20000),
                          ("MAIN_OEUVRE", "Montage lit + sommier", 1, 15000),
                      ])
    pay(PREFIX + "2606-07-CM", 6300)
    revenue(PREFIX + "2606-07", c7, "Commission 18% (cash) — Montage meubles")

    # 8) Terminée payée intégralement (mobile) → libérée au wallet
    _, c8, n8 = mkres(PREFIX + "2606-08", "Terminee", "MOBILE_MONEY", 45000,
                      acompte_valide=True, montant_verse=45000, solde_valide=True,
                      terminee=True, confirme=True, released=True,
                      operator="ORANGE_MONEY", title="Carrelage salle de bain",
                      msg="Pose de carrelage mural et sol salle de bain.",
                      lignes=[
                          ("FOURNITURE", "Carreaux (m²)", 12, 2500),
                          ("MAIN_OEUVRE", "Pose et jointoiement", 1, 15000),
                      ])
    pay(PREFIX + "2606-08-AC", 13500)
    pay(PREFIX + "2606-08-SO", 31500)
    revenue(PREFIX + "2606-08", c8, "Commission 18% — Carrelage")
    wtx("credit", n8, "success", PREFIX + "2606-08", "Libération escrow — Carrelage")
    wtx("commission", c8, "success", PREFIX + "2606-08", "Commission BABIFIX 18% — Carrelage")

    # 9) Annulée — mobile
    mkres(PREFIX + "2606-09", "Annulee", "MOBILE_MONEY", 28000,
          devis_statut="ENVOYE", title="Vitre cassée (annulée)",
          msg="Remplacement d'une vitre — réservation annulée.",
          lignes=[("FOURNITURE", "Vitre sur mesure", 1, 28000)])

    # 10) Confirmée : acompte 30% versé, en attente — mobile
    mkres(PREFIX + "2606-10", "Confirmee", "MOBILE_MONEY", 18000,
          acompte_valide=True, montant_verse=5400, operator="WAVE",
          title="Serrurerie — changement serrure",
          msg="Changement de la serrure de la porte d'entrée.",
          lignes=[
              ("FOURNITURE", "Serrure 3 points", 1, 13000),
              ("MAIN_OEUVRE", "Dépose / pose", 1, 5000),
          ])
    pay(PREFIX + "2606-10-AC", 5400)

    # ---- Retraits (WalletTransaction debit) ----
    wtx("debit", 30000, "success", PREFIX + "WD-260605",
        "Retrait Mobile Money — versé", operator="ORANGE_MONEY")
    wtx("debit", 20000, "pending", PREFIX + "WD-260607",
        "Retrait Mobile Money — en attente admin", operator="MTN_MOMO")

    # ---- Solde wallet du prestataire ----
    total_credit = n6 + n8
    total_withdraw = Decimal("30000") + Decimal("20000")
    prov.solde_fcfa = total_credit - total_withdraw
    prov.save(update_fields=["solde_fcfa"])

    print("Crédité wallet:", total_credit, "| retraits:", total_withdraw,
          "| solde final:", prov.solde_fcfa)

print("=== SEED OK ===")
print("Prestataire:", prov.nom, "—", prov.specialite)
print("Réservations:",
      Reservation.objects.filter(reference__startswith=PREFIX).count())
print("Paiements:", Payment.objects.filter(reference__startswith=PREFIX).count())
print("Revenus plateforme:",
      PlatformRevenue.objects.filter(reference__startswith=PREFIX).count())
print("Wallet tx:",
      WalletTransaction.objects.filter(reference__startswith=PREFIX).count())
print("Solde wallet:", prov.solde_fcfa, "FCFA")
