"""Migration Smart v2 :
- Champs KYC MRZ / anti-fraude hashes sur Provider
- Champs transcription audio sur Message & Reservation
- Passage du quota Standard par defaut de 3 a 5 devis actifs (PlatformConfig)
- Enrichissement complet et simplifie (debutant) des formulaires adaptatifs
  `template_exigences` et `profil_devis` sur toutes les categories (incluant
  Nounou / Garde d'enfants, Soutien scolaire, Serrurerie, Carrelage,
  Electromenager, Maconnerie, Beaute, Auto, Informatique, Plomberie sans doublon
  Urgent, Climatisation sans jargon BTU, Peinture avec reperes simples).
"""

from django.db import migrations, models


BEGINNER_CATEGORY_TEMPLATES = [
    (
        ("nounou", "garde d'enfant", "garde enfant", "baby", "nourrice"),
        "FORFAIT",
        [
            {"key": "nb_enfants", "label": "Nombre d'enfants", "type": "select", "choices": ["1 enfant", "2 enfants", "3 enfants ou plus"], "required": True},
            {"key": "tranche_age", "label": "Age des enfants", "type": "select", "choices": ["Bebe (0 - 2 ans)", "Maternelle (3 - 5 ans)", "Primaire (6 - 11 ans)", "Plusieurs ages"], "required": True},
            {"key": "rythme", "label": "Type de garde souhaite", "type": "select", "choices": ["Ponctuelle (soiree / quelques heures)", "Journee complete", "Reguliere (semaine / mois)", "A definir avec la nounou"], "required": True},
            {"key": "devoirs_repas", "label": "Besoins inclus", "type": "select", "choices": ["Garde simple", "Garde + repas", "Garde + aide aux devoirs", "Garde + repas + devoirs"], "required": False},
        ],
    ),
    (
        ("soutien", "cours", "scolaire", "repetiteur", "professeur"),
        "FORFAIT",
        [
            {"key": "niveau", "label": "Niveau de l'eleve", "type": "select", "choices": ["Primaire (CP - CM2)", "College (6e - 3e / BEPC)", "Lycee (2nde - Tle / BAC)", "Superieur / Adulte"], "required": True},
            {"key": "matiere", "label": "Matiere(s) principale(s)", "type": "text", "hint": "Ex : Maths, Francais, Anglais, Physique...", "required": True},
            {"key": "frequence", "label": "Rythme souhaite", "type": "select", "choices": ["1 seance ponctuelle", "2 seances / semaine", "3 seances / semaine", "Stage intensif examen"], "required": False},
        ],
    ),
    (
        ("plomb", "sanitaire", "eau"),
        "STANDARD",
        [
            {"key": "probleme", "label": "Que se passe-t-il ?", "type": "select", "choices": ["Fuite d'eau visible", "Evier / WC / douche bouche", "Robinet ou chasse d'eau casse", "Chauffe-eau en panne", "Installation neuve / autre"], "required": True},
            {"key": "lieu", "label": "Dans quelle piece ?", "type": "select", "choices": ["Cuisine", "Salle de bain / Douche", "WC / Toilettes", "Cour / Exterieur", "Je ne sais pas"], "required": False},
            {"key": "eau_coupee", "label": "L'eau est-elle deja coupee ?", "type": "bool", "required": False},
        ],
    ),
    (
        ("clim", "froid", "split", "ventilation"),
        "DIAGNOSTIC",
        [
            {"key": "besoin", "label": "De quoi avez-vous besoin ?", "type": "select", "choices": ["Nettoyage / Entretien complet", "Clim ne refroidit plus", "Clim qui coule de l'eau", "Installation clim neuve", "Je ne sais pas (l'artisan verifiera)"], "required": True},
            {"key": "nb_appareils", "label": "Combien de climatiseurs ?", "type": "select", "choices": ["1 climatiseur", "2 climatiseurs", "3 climatiseurs", "4 ou plus"], "required": True},
            {"key": "type_clim", "label": "Type d'appareil", "type": "select", "choices": ["Split mural (classique)", "Armoire / Cassette", "Je ne sais pas (l'artisan verifiera sur place)"], "required": False},
        ],
    ),
    (
        ("electr", "eclair", "courant"),
        "DIAGNOSTIC",
        [
            {"key": "besoin", "label": "Quel est votre besoin ?", "type": "select", "choices": ["Panne / coupure de courant", "Disjoncteur qui saute", "Prise / interrupteur / lampe", "Installation / renovation", "Je ne sais pas (l'artisan verifiera)"], "required": True},
            {"key": "zone", "label": "Zone concernee", "type": "select", "choices": ["Une seule piece", "Tout le logement", "Tableau electrique / compteur", "Exterieur / portail"], "required": False},
            {"key": "acces_tableau", "label": "Le tableau electrique est-il accessible ?", "type": "bool", "required": False},
        ],
    ),
    (
        ("serrur", "cle", "verrou"),
        "STANDARD",
        [
            {"key": "situation", "label": "Quelle est la situation ?", "type": "select", "choices": ["Porte claquee (cle a l'interieur)", "Cle perdue ou cassee", "Serrure bloquee / difficile", "Changer ou renforcer la serrure"], "required": True},
            {"key": "type_porte", "label": "Type de porte", "type": "select", "choices": ["Porte simple (bois / alu)", "Porte blindee", "Portail / Grille metallique", "Je ne sais pas"], "required": False},
        ],
    ),
    (
        ("peint", "ravalement", "decor"),
        "SURFACE",
        [
            {"key": "taille_zone", "label": "Quelle taille a peindre ?", "type": "select", "choices": ["1 petite piece / chambre", "Salon ou 2 pieces", "Tout l'appartement", "Villa / Facade exterieure", "L'artisan mesurera sur place"], "required": True},
            {"key": "surface_m2", "label": "Surface approx. (facultatif)", "type": "number", "unit": "m2", "hint": "Laissez vide si vous ne savez pas", "required": False},
            {"key": "etat_murs", "label": "Etat des murs", "type": "select", "choices": ["Bon etat (rafraichissement)", "Quelques fissures / trous", "Humidite ou peinture qui s'ecaille", "L'artisan verifiera sur place"], "required": False},
            {"key": "fournir_peinture", "label": "Le prestataire fournit la peinture ?", "type": "bool", "required": False},
        ],
    ),
    (
        ("carrel", "faience"),
        "SURFACE",
        [
            {"key": "zone_carrelage", "label": "Ou poser les carreaux ?", "type": "select", "choices": ["Salle de bain / WC", "Cuisine", "Salon / Chambre", "Terrasse / Cour", "Reparation de quelques carreaux"], "required": True},
            {"key": "surface_m2", "label": "Surface approx. (facultatif)", "type": "number", "unit": "m2", "hint": "Laissez vide si l'artisan doit mesurer", "required": False},
            {"key": "carreaux_deja_achetes", "label": "Avez-vous deja achete les carreaux ?", "type": "bool", "required": False},
        ],
    ),
    (
        ("electromenager", "frigo", "lave"),
        "DIAGNOSTIC",
        [
            {"key": "appareil", "label": "Quel appareil est concerne ?", "type": "select", "choices": ["Refrigerateur / Congelateur", "Machine a laver", "Cuisiniere / Four / Micro-ondes", "Television / Autre appareil"], "required": True},
            {"key": "symptome", "label": "Que constatez-vous ?", "type": "select", "choices": ["Ne s'allume plus", "Ne refroidit / ne chauffe plus", "Bruit ou fuite anormale", "Installation / branchement"], "required": True},
            {"key": "marque", "label": "Marque (facultatif)", "type": "text", "hint": "Ex : Nasco, Samsung, LG, Beko (ou Je ne sais pas)", "required": False},
        ],
    ),
    (
        ("macon", "beton", "gros oeuvre"),
        "SURFACE",
        [
            {"key": "type_travaux", "label": "Nature des travaux", "type": "select", "choices": ["Rebouchage fissure / enduit", "Monter un mur / cloison", "Chape / dalle sol", "Petite renovation / muret", "A voir sur place avec le macon"], "required": True},
            {"key": "surface_m2", "label": "Surface estimee (facultatif)", "type": "number", "unit": "m2", "hint": "Optionnel, le macon verifiera sur place", "required": False},
        ],
    ),
    (
        ("menage", "nettoyage", "repassage"),
        "FORFAIT",
        [
            {"key": "type_logement", "label": "Taille du logement", "type": "select", "choices": ["Studio / 1 piece", "Appartement 2-3 pieces", "Grand appartement (4+ pieces)", "Villa / Maison", "Bureau / Local"], "required": True},
            {"key": "formule", "label": "Type de menage", "type": "select", "choices": ["Menage courant", "Grand nettoyage en profondeur", "Fin de chantier / apres travaux", "Canape / Tapis / Vitres"], "required": True},
            {"key": "produits_inclus", "label": "Le prestataire apporte ses produits ?", "type": "bool", "required": False},
        ],
    ),
    (
        ("menuis", "bois", "ebenist", "meuble"),
        "STANDARD",
        [
            {"key": "objet", "label": "De quoi s'agit-il ?", "type": "select", "choices": ["Porte qui frotte ou ne ferme plus", "Montage / reparation de meuble", "Placard / dressing sur mesure", "Fenetre / volet bois ou alu"], "required": True},
            {"key": "fournir_materiaux", "label": "Le menuisier fournit le bois / pieces ?", "type": "bool", "required": False},
        ],
    ),
    (
        ("jardin", "pelouse", "elagage", "paysag"),
        "FORFAIT",
        [
            {"key": "taille_jardin", "label": "Taille de l'espace vert", "type": "select", "choices": ["Petit jardin / cour", "Jardin moyen (villa)", "Grand terrain / residence", "A voir sur place"], "required": True},
            {"key": "travaux", "label": "Travaux souhaites", "type": "select", "choices": ["Tonte de pelouse", "Taille de haies", "Elagage d'arbres", "Entretien complet"], "required": True},
            {"key": "evacuation", "label": "Evacuer les dechets verts ?", "type": "bool", "required": False},
        ],
    ),
    (
        ("cuisin", "traiteur", "chef"),
        "FORFAIT",
        [
            {"key": "nb_personnes", "label": "Pour combien de personnes ?", "type": "select", "choices": ["1 a 4 personnes", "5 a 10 personnes", "11 a 25 personnes", "Plus de 25 personnes (evenement)"], "required": True},
            {"key": "courses_incluses", "label": "Le cuisinier fait les courses ?", "type": "bool", "required": False},
        ],
    ),
    (
        ("demenag", "manutent"),
        "FORFAIT",
        [
            {"key": "volume", "label": "Taille du logement a demenager", "type": "select", "choices": ["Studio / Quelques meubles", "Appartement 2-3 pieces", "Grand appartement 4+ pieces", "Villa / Bureau"], "required": True},
            {"key": "etage_ascenseur", "label": "Acces / Etage", "type": "select", "choices": ["Rez-de-chaussee", "Etage avec ascenseur", "Etage sans ascenseur"], "required": False},
            {"key": "besoin_camion", "label": "Besoin d'un vehicule de transport ?", "type": "bool", "required": False},
        ],
    ),
    (
        ("coiff", "beaut", "esthet", "manucur", "maquill"),
        "FORFAIT",
        [
            {"key": "prestation", "label": "Prestation souhaitee", "type": "select", "choices": ["Coiffure / Tresses / Brushing", "Coupe homme / Barbe", "Manucure / Pedicure", "Maquillage / Soin visage"], "required": True},
            {"key": "nb_personnes", "label": "Nombre de personnes", "type": "select", "choices": ["1 personne", "2 personnes", "Groupe / Evenement"], "required": False},
        ],
    ),
    (
        ("mecan", "auto", "voiture"),
        "DIAGNOSTIC",
        [
            {"key": "besoin", "label": "Besoin automobile", "type": "select", "choices": ["Panne sur place / batterie", "Vidange & entretien", "Diagnostic voyant moteur", "Freins / Pneus / Clim auto"], "required": True},
            {"key": "vehicule", "label": "Marque et modele (facultatif)", "type": "text", "hint": "Ex : Toyota Corolla, Hyundai Tucson...", "required": False},
        ],
    ),
    (
        ("informati", "wi-fi", "wifi", "ordinateur", "reseau"),
        "DIAGNOSTIC",
        [
            {"key": "besoin", "label": "Quel est le souci ?", "type": "select", "choices": ["Probleme Wi-Fi / Box fibre", "Ordinateur lent / bloque / virus", "Installation imprimante / cameras", "Recuperation de donnees / autre"], "required": True},
        ],
    ),
]


def seed_smart_v2(apps, schema_editor):
    PlatformConfig = apps.get_model("adminpanel", "PlatformConfig")
    Category = apps.get_model("adminpanel", "Category")

    # 1. Monter le quota Standard de lancement de 3 a 5 devis actifs
    PlatformConfig.objects.filter(standard_max_devis=3).update(standard_max_devis=5)

    # 2. Enrichir et simplifier toutes les categories existantes
    for cat in Category.objects.all():
        blob = f"{cat.nom or ''} {getattr(cat, 'icone_slug', '') or ''} {getattr(cat, 'search_keywords', '') or ''}".lower()
        for keywords, profil, template in BEGINNER_CATEGORY_TEMPLATES:
            if any(k in blob for k in keywords):
                cat.profil_devis = profil
                cat.template_exigences = template
                cat.save(update_fields=["profil_devis", "template_exigences"])
                break


def reverse_noop(apps, schema_editor):
    pass


class Migration(migrations.Migration):

    dependencies = [
        ("adminpanel", "0102_seed_sos_categories"),
    ]

    operations = [
        migrations.AddField(
            model_name="provider",
            name="kyc_cni_mrz",
            field=models.CharField(
                blank=True,
                default="",
                help_text="Zone MRZ TD1 (3 lignes ICAO 9303) au verso de la CNI ONECI si fournie",
                max_length=120,
            ),
        ),
        migrations.AddField(
            model_name="provider",
            name="kyc_image_hashes",
            field=models.JSONField(
                blank=True,
                default=dict,
                help_text="Empreintes SHA-256 et dHash perceptuelles des pieces KYC (anti-fraude inter-comptes)",
            ),
        ),
        migrations.AddField(
            model_name="reservation",
            name="audio_probleme_transcript",
            field=models.TextField(
                blank=True,
                default="",
                help_text="Transcription texte automatique de la note vocale du besoin",
            ),
        ),
        migrations.AddField(
            model_name="message",
            name="audio_transcript",
            field=models.TextField(
                blank=True,
                default="",
                help_text="Transcription texte de la note vocale (fr).",
            ),
        ),
        migrations.AlterField(
            model_name="platformconfig",
            name="standard_max_devis",
            field=models.PositiveSmallIntegerField(default=5),
        ),
        migrations.RunPython(seed_smart_v2, reverse_noop),
    ]
