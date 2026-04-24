"""Seed actualites (news/announcements) for apps."""

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand
from adminpanel.models import Actualite


class Command(BaseCommand):
    help = "Seed demo actualites for client/prestataire apps"

    def handle(self, *args, **options):
        User = get_user_model()
        admin = User.objects.filter(username="admin_demo").first()
        if not admin:
            admin = User.objects.filter(is_superuser=True).first()

        actualites = [
            {
                "titre": "Bienvenue sur BABIFIX !",
                "description": "Votre plateforme de services a domicile en Cote d Ivoire. Trouvez des prestataires verifies pres de chez vous.",
                "categorie_tag": "general",
                "icone_key": "star",
            },
            {
                "titre": "Nouveaux prestataires disponibles",
                "description": "Des plombiers, electriciens et menagers certifies viennent de rejoindre BABIFIX. Consultez les avis et reservez en quelques clics.",
                "categorie_tag": "nouveau_prestataire",
                "icone_key": "person_add",
            },
            {
                "titre": "Paiement Mobile Money facilite",
                "description": "Payez vos prestations directement par Orange Money, MTN ou Wave. Transactions securisees et instantanees.",
                "categorie_tag": "paiement",
                "icone_key": "payment",
            },
            {
                "titre": "-20% sur votre premiere reservation",
                "description": "Profitez d une offre speciale pour votre premiere demande de service. Code promo: BIENVENUE",
                "categorie_tag": "promo",
                "icone_key": "local_offer",
            },
            {
                "titre": "Comment faire une demande de devis",
                "description": "1. Choisissez votre categorie 2. Decrivez votre besoin 3. Recevez des devis en moins de 24h 4. Comparez et choisissez !",
                "categorie_tag": "general",
                "icone_key": "help",
            },
            {
                "titre": "Service client 24h/24",
                "description": "Notre equipe est disponible pour vous aider a tout moment. Contactez-nous par chat ou appel.",
                "categorie_tag": "general",
                "icone_key": "support_agent",
            },
            {
                "titre": "Conseils de securite",
                "description": "Verifiez toujours les avis avant de choisir un prestataire. BABIFIX certifie tous ses partenaires.",
                "categorie_tag": "general",
                "icone_key": "shield",
            },
            {
                "titre": "Zone d intervention Etendue",
                "description": "BABIFIX couvre maintenant Abidjan, Bouake, Yamoussoukro et Daloa ! Plus de services pres de chez vous.",
                "categorie_tag": "general",
                "icone_key": "location_on",
            },
        ]

        count = 0
        for data in actualites:
            obj, created = Actualite.objects.get_or_create(
                titre=data["titre"],
                defaults={
                    "description": data["description"],
                    "categorie_tag": data["categorie_tag"],
                    "icone_key": data["icone_key"],
                    "publie": True,
                    "created_by": admin,
                },
            )
            if created:
                count += 1
                self.stdout.write(f"[OK] Created: {data['titre'][:40]}")
            else:
                self.stdout.write(f"[--] Exists: {data['titre'][:40]}")

        self.stdout.write(
            self.style.SUCCESS(
                f"\n[OK] {count} actualites creees, {Actualite.objects.count()} total"
            )
        )
