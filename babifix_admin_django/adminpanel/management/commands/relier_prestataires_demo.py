"""Relie un compte utilisateur a chaque prestataire orphelin de la demo BABIFIX.

Pourquoi ce script existe : `seed_demo_data` cree 5 fiches prestataires SANS
compte utilisateur, alors que `seed_full_demo` (devis, chat, appels, paiements)
exige des prestataires AVEC un compte lie (Provider.user n'est jamais renseigne
par seed_demo_data). On ne cree ici AUCUNE donnee metier : on rattache
uniquement un compte aux fiches existantes.

Idempotent : ne fait rien pour un prestataire qui a deja un compte.
Mot de passe volontairement simple et LOCAL (base SQLite de capture) : il n'est
jamais ecrit dans un fichier versionne ni pousse nulle part.
"""
from django.contrib.auth.models import User
from django.db import transaction

from adminpanel.models import Provider

MOT_DE_PASSE_LOCAL = "Presta2026!"
DOMAINE = "presta.babifix.local"


@transaction.atomic
def relier():
    orphelins = list(Provider.objects.filter(user__isnull=True).order_by("pk"))
    print(f"PRESTATAIRES_SANS_COMPTE {len(orphelins)}")

    crees = 0
    for i, p in enumerate(orphelins, start=1):
        # Nom d'utilisateur derive du nom du prestataire, unique et lisible.
        base = (p.nom or f"presta{i}").lower()
        for ch in " '’àâäéèêëîïôöùûüç-":
            base = base.replace(ch, "_" if ch == " " else "")
        username = base[:24] or f"presta{i}"
        n = 0
        candidat = username
        while User.objects.filter(username=candidat).exists():
            n += 1
            candidat = f"{username}{n}"
        user = User.objects.create_user(
            username=candidat,
            email=f"{candidat}@{DOMAINE}",
            password=MOT_DE_PASSE_LOCAL,
            first_name=(p.nom or "").split(" ")[0][:30],
            last_name=" ".join((p.nom or "").split(" ")[1:])[:30],
        )
        p.user = user
        p.save(update_fields=["user"])
        crees += 1
        print(f"RELIÉ {p.pk} {p.nom!r} -> {candidat}")

    print(f"COMPTES_CREES {crees}")
    print(f"RESTANT_SANS_COMPTE {Provider.objects.filter(user__isnull=True).count()}")


relier()
