"""Catalogue SEO local programmatique & generateurs Schema.org JSON-LD pour BABIFIX Vitrine.

Concu pour positionner babifix.ci sur les requetes locales a forte intention en Cote d'Ivoire :
  - "plombier Abidjan", "plombier Cocody", "depannage climatisation Marcory",
  - "electricien Plateau", "serrurier urgence Yopougon", "nounou verifiee Abidjan", etc.

Zero fausse note (aucun aggregateRating invente), slugs listes blanches (anti soft-404 / XSS),
maillage interne propre (metiers lies + communes voisines) et balisage JSON-LD valide.
"""

from __future__ import annotations

from datetime import date
import json
import os
from typing import Any, Dict, List, Optional


def canonical_base_url(request=None) -> str:
    """Base canonique configurable via CANONICAL_BASE_URL (defaut https://babifix.ci)."""
    env_url = (os.getenv("CANONICAL_BASE_URL") or "").strip().rstrip("/")
    if env_url.startswith(("https://", "http://")):
        return env_url
    if request is not None:
        host = (request.get_host() or "").lower()
        if host and "127.0.0.1" not in host and "localhost" not in host and "testserver" not in host:
            return f"{request.scheme}://{host}".rstrip("/")
    return "https://babifix.ci"


def safe_json_ld(data: Dict[str, Any]) -> str:
    """Serialise un objet JSON-LD en echappant les sequences '</' contre toute injection."""
    return json.dumps(data, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")


SEO_TRADES: List[Dict[str, Any]] = [
    {
        "slug": "plomberie",
        "name": "Plomberie",
        "artisan_label": "Plombier verifie",
        "artisan_plural": "Plombiers verifies",
        "urgent_247": True,
        "eta": "Des 30 min en urgence SOS",
        "hero_subtitle": "Recherche de fuite, debouchage evier ou WC, remplacement de robinet, chauffe-eau et canalisation avec devis clair et paiement sous sequestre.",
        "interventions": [
            "Recherche et reparation de fuite d'eau (tuyau, robinet, raccord)",
            "Debouchage d'evier, lavabo, douche et WC haute efficacite",
            "Remplacement de robinetterie, mitigeur et mecanisme de chasse d'eau",
            "Installation et depannage de chauffe-eau electrique ou sanitaire",
            "Pose de lavabo, colonne de douche et raccordement machine a laver",
            "Diagnostic complet du reseau sanitaire et etancheite silicone",
        ],
        "faq": [
            ("Comment trouver un plombier fiable rapidement ?", "Sur BABIFIX, chaque plombier a passe une verification d'identite (CNI). Decrivez votre fuite par texte, photo ou note vocale et recevez un devis ecrit clair avant toute intervention."),
            ("Comment fonctionne le paiement pour une intervention de plomberie ?", "Vous reglez en Mobile Money (Wave, Orange Money, MTN MoMo, Moov). Les fonds restent proteges sous sequestre et ne sont verses au plombier qu'apres votre confirmation des travaux."),
            ("Un plombier peut-il venir voir la panne avant le devis ?", "Oui. Si un diagnostic sur place est necessaire, le plombier peut proposer une visite avec une caution transparente (0, 1 500 ou 2 500 FCFA), integralement deduite du devis final accepte."),
            ("La plomberie est-elle disponible en urgence la nuit ou le dimanche ?", "Oui, le mode SOS 24/7 alerte immediatement les plombiers disponibles de votre secteur avec une majoration transparente affichee avant validation."),
        ],
        "related_slugs": ["climatisation", "electricite", "serrurerie", "carrelage"],
    },
    {
        "slug": "electricite",
        "name": "Electricite",
        "artisan_label": "Electricien verifie",
        "artisan_plural": "Electriciens verifies",
        "urgent_247": True,
        "eta": "Des 35 min en urgence SOS",
        "hero_subtitle": "Depannage court-circuit, disjoncteur qui saute, tableau electrique, prises, luminaires et mise aux normes securisee en Cote d'Ivoire.",
        "interventions": [
            "Recherche de panne, coupure partielle et court-circuit domestique",
            "Remplacement de disjoncteur divisionnaire ou differentiel 30 mA",
            "Installation et mise en securite de tableau electrique et terre",
            "Pose de prises de courant, interrupteurs, spots LED et lustres",
            "Raccordement d'onduleur, regulateur de tension et groupe electrogene",
            "Verification securite electrique complete pour maison ou bureau",
        ],
        "faq": [
            ("Mon disjoncteur saute sans arret : puis-je faire appel a BABIFIX ?", "Oui. Activez une demande classique ou SOS 24/7 pour faire intervenir un electricien verifie qui isolera le circuit en defaut en toute securite."),
            ("Les fournitures electriques sont-elles detaillees sur le devis ?", "Oui, nos electriciens separent clairement la main-d'oeuvre et les pieces (disjoncteur, cable, prises) sur un devis ecrit que vous validez avant travaux."),
            ("Le paiement Mobile Money est-il securise ?", "Tout paiement Mobile Money passe par le sequestre BABIFIX : l'artisan est paye uniquement lorsque l'installation fonctionne et que vous validez la fin de mission."),
            ("Intervenez-vous aussi pour les bureaux et PME ?", "Oui, BABIFIX Pro accompagne les entreprises, commerces et residences avec facturation conforme DGI."),
        ],
        "related_slugs": ["climatisation", "plomberie", "electromenager", "informatique"],
    },
    {
        "slug": "climatisation",
        "name": "Climatisation & Froid",
        "artisan_label": "Technicien climatisation",
        "artisan_plural": "Techniciens climatisation",
        "urgent_247": True,
        "eta": "Intervention sous 2 heures",
        "hero_subtitle": "Entretien et nettoyage antibacterien de split, recharge gaz R410A / R32, fuite d'eau climatiseur et installation neuve par frigoristes verifies.",
        "interventions": [
            "Entretien complet de climatiseur split (nettoyage filtres, turbine, desinfection)",
            "Diagnostic pression et recharge gaz refrigerant R410A / R32",
            "Reparation climatiseur qui coule de l'eau ou ne refroidit plus",
            "Installation et mise en service complete de split neuf",
            "Depose propre et deplacement de groupe exterieur / unite interieure",
            "Maintenance preventive multi-splits pour villas, residences et bureaux",
        ],
        "faq": [
            ("A quelle frequence entretenir un climatiseur a Abidjan ?", "Avec la chaleur et la poussiere, un entretien complet tous les 4 a 6 mois ameliore le refroidissement, assainit l'air et reduit votre facture CIE."),
            ("Dois-je connaitre la puissance BTU ou le gaz de mon split ?", "Non. Sur BABIFIX, il suffit d'indiquer le nombre d'appareils et le symptome : le technicien verifie la puissance et le type de gaz directement sur place."),
            ("Comment eviter les fausses recharges de gaz ?", "Le technicien envoie un devis detaille apres diagnostic et le paiement reste bloque sous sequestre jusqu'a ce que votre clim refroidisse efficacement."),
            ("Proposez-vous des contrats d'entretien pour entreprises et hotels ?", "Oui, notre offre BABIFIX Pro couvre la maintenance periodique de parcs multi-splits avec suivi et facturation mensuelle."),
        ],
        "related_slugs": ["electricite", "electromenager", "plomberie", "menage"],
    },
    {
        "slug": "serrurerie",
        "name": "Serrurerie",
        "artisan_label": "Serrurier verifie",
        "artisan_plural": "Serruriers verifies",
        "urgent_247": True,
        "eta": "Des 30 min en urgence SOS",
        "hero_subtitle": "Ouverture de porte claquee sans casse, extraction de cle cassee, changement de cylindre haute securite et renforcement de porte.",
        "interventions": [
            "Ouverture fine de porte claquee sans degrader le bati",
            "Extraction de cle cassee dans le barillet",
            "Remplacement de cylindre standard ou haute securite (3 a 5 cles)",
            "Pose de serrure 3 points, verrou applique et poignee blindee",
            "Securisation apres perte de cles ou emmenagement",
            "Reglage de porte d'entree, grille ou portail metallique",
        ],
        "faq": [
            ("Comment etre sur que le serrurier est de confiance ?", "Chaque serrurier BABIFIX est identifie (CNI verifiee, photo portrait et avis clients reels) avant toute mise en relation."),
            ("Le prix est-il fixe avant l'ouverture de la porte ?", "Oui : vous validez le devis ecrit directement dans l'application avant que le serrurier ne demarre les travaux."),
            ("Intervenez-vous tard le soir si ma porte est bloquee ?", "Oui, le mode SOS 24/7 permet de solliciter un serrurier de garde dans votre commune avec frais d'astreinte transparents."),
            ("Puis-je payer par Wave ou Orange Money ?", "Oui, Wave, Orange Money, MTN MoMo et Moov Money sont acceptes avec recu PDF automatique."),
        ],
        "related_slugs": ["menuiserie", "plomberie", "electricite", "maconnerie"],
    },
    {
        "slug": "menage",
        "name": "Menage & Entretien",
        "artisan_label": "Aide menagere verifiee",
        "artisan_plural": "Professionnels du menage",
        "urgent_247": False,
        "eta": "Creneau au choix des aujourd'hui",
        "hero_subtitle": "Menage regulier, grand nettoyage de printemps, remise en etat fin de chantier, nettoyage de canapes, tapis et vitres a domicile.",
        "interventions": [
            "Menage complet d'appartement, studio ou villa",
            "Grand nettoyage en profondeur (cuisine, salles d'eau, placards)",
            "Nettoyage apres travaux / fin de chantier ou avant emmenagement",
            "Shampouinage et detachement de canapes tissu, matelas et tapis",
            "Lavage haute pression de terrasses, cours et facades",
            "Repassage soigne et entretien du linge a domicile",
        ],
        "faq": [
            ("Les professionnels du menage sont-ils verifies ?", "Oui, identite CNI controlee, profil complet et notes laissees uniquement par de vrais clients ayant paye sur BABIFIX."),
            ("Dois-je fournir les produits d'entretien ?", "Vous choisissez simplement lors de la demande si vous fournissez vos produits ou si le prestataire vient equipe."),
            ("Puis-je reserver pour un nettoyage apres travaux ?", "Oui, selectionnez 'Fin de chantier' dans le formulaire guide pour recevoir un devis adapte a la surface."),
            ("Comment reserver pour une residence meublee ?", "Vous pouvez commander ponctuellement ou ouvrir un compte BABIFIX Pro pour gerer vos remises en etat entre deux locataires."),
        ],
        "related_slugs": ["nounou-garde-enfants", "jardinage", "climatisation", "peinture"],
    },
    {
        "slug": "nounou-garde-enfants",
        "name": "Nounou & Garde d'enfants",
        "artisan_label": "Nounou verifiee",
        "artisan_plural": "Nounous verifiees",
        "urgent_247": False,
        "eta": "Profils controles avec dossier renforce",
        "hero_subtitle": "Garde d'enfants ponctuelle, baby-sitting de soiree ou garde reguliere a la maison par des nounous au dossier verifie (CNI, casier judiciaire et references).",
        "interventions": [
            "Garde d'enfants a la journee (bebes, maternelle, primaire)",
            "Baby-sitting ponctuel en soiree ou le week-end",
            "Garde reguliere a la semaine ou au mois (sortie d'ecole, mercredi)",
            "Accompagnement aux devoirs et activites calmes a domicile",
            "Preparation des repas simples et routines du coucher",
            "Entretien prealable avec la famille avant engagement",
        ],
        "faq": [
            ("Quelles verifications sont effectuees pour les nounous sur BABIFIX ?", "Ce metier releve du regime KYC renforce BABIFIX : CNI validee, extrait ou recepisse de casier judiciaire, contact de reference verifie et entretien superviseur."),
            ("Comment sont calcules les tarifs de garde ?", "Les devis s'adaptent au rythme choisi (a l'heure, a la journee, en soiree ou au forfait mensuel) sans jargon technique."),
            ("Puis-je echanger avec la nounou avant de confirmer ?", "Oui, la messagerie integree et les notes vocales vous permettent de discuter des horaires, allergies et habitudes de vos enfants."),
            ("Le paiement est-il encadre ?", "Oui, tout reglement via Mobile Money est trace avec recu officiel et protection BABIFIX."),
        ],
        "related_slugs": ["menage", "soutien-scolaire", "cuisine", "jardinage"],
    },
    {
        "slug": "peinture",
        "name": "Peinture & Decoration",
        "artisan_label": "Peintre batiment",
        "artisan_plural": "Peintres batiment",
        "urgent_247": False,
        "eta": "Devis sous 24 heures",
        "hero_subtitle": "Rafraichissement interieur, rebouchage de fissures, enduit lisse, peinture anti-humidite et ravalement de facade avec devis detaille.",
        "interventions": [
            "Preparation des murs (lessivage, rebouchage fissures, poncage)",
            "Application peinture mate, satinee ou velours en 2 couches",
            "Peinture de plafonds sans traces et boiseries",
            "Traitement murs humides et sous-couche isolante",
            "Ravalement et peinture de facades exterieures et clotures",
            "Remise en etat locative avant etat des lieux de sortie",
        ],
        "faq": [
            ("Dois-je connaitre la surface exacte en m2 ?", "Pas du tout : indiquez simplement '1 chambre', 'Salon' ou 'Tout l'appartement', et le peintre mesure exactement lors de sa visite."),
            ("Le peintre peut-il fournir la peinture ?", "Oui, vous choisissez lors de la demande si le peintre inclut les pots de peinture et baches dans le devis ou si vous achetez les fournitures."),
            ("Comment proteger mon budget sur un gros chantier peinture ?", "Votre paiement reste bloque sous sequestre BABIFIX et est libere apres verification des finitions et photos avant/apres."),
            ("Combien de temps faut-il pour peindre une chambre ?", "En general 1 a 2 jours selon la preparation des murs et le temps de sechage entre deux couches."),
        ],
        "related_slugs": ["carrelage", "menuiserie", "maconnerie", "menage"],
    },
    {
        "slug": "carrelage",
        "name": "Carrelage & Faience",
        "artisan_label": "Carreleur verifie",
        "artisan_plural": "Carreleurs verifies",
        "urgent_247": False,
        "eta": "Devis sous 24 heures",
        "hero_subtitle": "Pose de carreaux gres cerame, faience de salle de bain et cuisine, ragreage de sol et remplacement de carreaux casses.",
        "interventions": [
            "Pose de carrelage sol interieur (gres cerame, grand format)",
            "Pose de faience murale salle de bain, douche et credences cuisine",
            "Remplacement propre de carreaux fissures ou decolles",
            "Chape de nivellement, ragreage et joints etanches hydrofuges",
            "Pose de carrelage antiderapant pour terrasses, balcons et escaliers",
            "Depose d'ancien revetement et evacuation des gravats",
        ],
        "faq": [
            ("Un carreleur peut-il venir mesurer avant de faire le devis ?", "Oui, le parcours Visite de diagnostic permet au carreleur de prendre les mesures exactes et de vous envoyer un devis ferme detaille."),
            ("Les carreaux et le ciment-colle sont-ils separes sur le devis ?", "Oui, main-d'oeuvre au m2 et fournitures (colle, joints, carreaux) apparaissent sur des lignes distinctes."),
            ("Puis-je faire remplacer seulement 3 ou 4 carreaux casses ?", "Oui, nos carreleurs interviennent aussi bien sur de petites reprises que sur des renovations completes."),
            ("Comment suivre l'avancement si je ne suis pas sur place ?", "Le prestataire partage des photos avant/apres dans le suivi de mission avant votre validation finale."),
        ],
        "related_slugs": ["plomberie", "peinture", "maconnerie", "menuiserie"],
    },
    {
        "slug": "electromenager",
        "name": "Depannage Electromenager",
        "artisan_label": "Reparateur electromenager",
        "artisan_plural": "Reparateurs electromenager",
        "urgent_247": False,
        "eta": "Intervention sous 2 heures",
        "hero_subtitle": "Reparation a domicile de refrigerateurs, congelateurs, machines a laver, cuisinieres et fours toutes marques sans transporter votre appareil.",
        "interventions": [
            "Depannage refrigerateur et congelateur (ne refroidit plus, fuite, bruit)",
            "Reparation machine a laver (vidange, essorage, porte bloquee, carte)",
            "Diagnostic et depannage four, plaque de cuisson et micro-ondes",
            "Remplacement thermostat, pompe de vidange, relais ou joint de porte",
            "Installation et mise en service d'appareils electromenagers neufs",
            "Verification alimentation electrique et securite de raccordement",
        ],
        "faq": [
            ("Faut-il deplacer mon refrigerateur ou ma machine a laver ?", "Non, le technicien vient diagnostiquer et reparer directement chez vous, ce qui evite les couts et risques de transport."),
            ("Que se passe-t-il si l'appareil n'est pas reparable ?", "Le technicien etablit un diagnostic clair : vous ne payez jamais une reparation non validee."),
            ("Toutes les marques sont-elles prises en charge ?", "Oui (Nasco, Samsung, LG, Beko, Bosch, Hisense, Sharp, Whirlpool et autres marques courantes en Cote d'Ivoire)."),
            ("Les pieces remplacees sont-elles indiquees sur le devis ?", "Oui, chaque piece et son tarif figurent separement de la main-d'oeuvre."),
        ],
        "related_slugs": ["climatisation", "electricite", "plomberie", "informatique"],
    },
    {
        "slug": "menuiserie",
        "name": "Menuiserie Bois & Alu",
        "artisan_label": "Menuisier verifie",
        "artisan_plural": "Menuisiers verifies",
        "urgent_247": False,
        "eta": "Sur rendez-vous rapide",
        "hero_subtitle": "Ajustement et rabotage de portes, montage de meubles, placards et dressings sur mesure, fenetres bois ou aluminium.",
        "interventions": [
            "Rabotage et reglage de porte qui frotte ou ferme mal",
            "Pose de bloc-porte interieur, paumelles et poignees",
            "Montage, reparation et renforcement de meubles et lits",
            "Conception et pose de placards, etageres et dressings sur mesure",
            "Reparation de baies vitrees, fenetres aluminium et moustiquaires",
            "Pose de plinthes, habillages bois et petites renovations interieures",
        ],
        "faq": [
            ("Pouvez-vous reparer une porte qui gonfle avec l'humidite ?", "Oui, nos menuisiers realisent le rabotage, le reglage des paumelles et la reprise des huisseries rapidement."),
            ("Faites-vous aussi la menuiserie aluminium ?", "Oui, indiquez bois ou aluminium dans votre demande pour etre mis en relation avec le bon specialiste."),
            ("Puis-je envoyer une photo du meuble ou de la porte ?", "Oui, joignez jusqu'a plusieurs photos ou une courte video dans le formulaire pour obtenir un devis precis."),
            ("Le paiement est-il securise pour un meuble sur mesure ?", "Oui, le sequestre BABIFIX encadre l'acompte et le solde jusqu'a la pose finale chez vous."),
        ],
        "related_slugs": ["serrurerie", "peinture", "carrelage", "maconnerie"],
    },
    {
        "slug": "jardinage",
        "name": "Jardinage & Paysage",
        "artisan_label": "Jardinier verifie",
        "artisan_plural": "Jardiniers verifies",
        "urgent_247": False,
        "eta": "Creneau au choix",
        "hero_subtitle": "Tonte de pelouse, taille de haies, elagage securise, desherbage et entretien regulier des jardins de villas et residences.",
        "interventions": [
            "Tonte de pelouse, bordures et debroussaillage complet",
            "Taille soignee de haies, bougainvilliers et arbustes d'ornement",
            "Elagage d'arbres et abattage controle de branches dangereuses",
            "Desherbage, nettoyage d'allees et evacuation des dechets verts",
            "Plantation, engazonnement et creation de massifs tropicaux",
            "Entretien mensuel pour villas, syndics et residences",
        ],
        "faq": [
            ("Le jardinier vient-il avec sa tondeuse et ses outils ?", "Oui, precisiez vos besoins et le prestataire adapte son materiel (tondeuse, taille-haie, tronconneuse) sur le devis."),
            ("L'evacuation des branches coupees est-elle possible ?", "Oui, cochez l'option 'Evacuer les dechets verts' dans votre demande pour l'inclure au devis."),
            ("Proposez-vous des passages reguliers chaque mois ?", "Oui, vous pouvez reserver a la demande ou planifier un entretien periodique."),
            ("Intervenez-vous pour les cours d'immeubles et entreprises ?", "Oui, nos equipes interviennent autant pour les particuliers que pour les syndics et entreprises."),
        ],
        "related_slugs": ["menage", "plomberie", "peinture", "maconnerie"],
    },
    {
        "slug": "informatique",
        "name": "Informatique & Reseau Wi-Fi",
        "artisan_label": "Technicien informatique",
        "artisan_plural": "Techniciens informatiques",
        "urgent_247": False,
        "eta": "Intervention sous 2 heures",
        "hero_subtitle": "Depannage PC et Mac a domicile, optimisation Wi-Fi / box fibre, installation d'imprimantes, cameras et sauvegarde securisee.",
        "interventions": [
            "Depannage ordinateur lent, ecran bleu, virus ou blocage Windows / Mac",
            "Optimisation couverture Wi-Fi, repetiteurs Mesh et configuration fibre",
            "Installation d'imprimantes reseau, scanners et postes de teletravail",
            "Sauvegarde, recuperation de donnees et migration vers nouveau PC",
            "Installation et parametrage de cameras de surveillance Wi-Fi",
            "Support informatique rapide pour particuliers et petites entreprises",
        ],
        "faq": [
            ("Le technicien se deplace-t-il a la maison ou au bureau ?", "Oui, toutes les interventions informatiques BABIFIX ont lieu directement sur site pour tester votre vrai reseau et materiel."),
            ("Mes donnees personnelles sont-elles respectees ?", "Nos techniciens sont identifies (CNI verifiee) et soumis a une charte de confidentialite stricte (Loi CI 2013-450)."),
            ("Pouvez-vous regler un probleme de Wi-Fi qui ne passe pas dans les chambres ?", "Oui, le technicien mesure le signal et installe des points d'acces ou un kit Mesh proprement configure."),
            ("Recevrai-je une facture pour mon entreprise ?", "Oui, un recu PDF officiel est emis automatiquement apres chaque reglement."),
        ],
        "related_slugs": ["electricite", "electromenager", "climatisation", "serrurerie"],
    },
]

SEO_ZONES: List[Dict[str, Any]] = [
    {
        "slug": "abidjan",
        "name": "Abidjan",
        "region": "District Autonome d'Abidjan",
        "priority": "0.85",
        "quartiers": ["Cocody", "Marcory", "Plateau", "Yopougon", "Treichville", "Koumassi", "Bingerville"],
        "intro": "Interventions rapides dans toutes les communes d'Abidjan avec artisans verifies CNI et suivi temps reel.",
        "nearby_slugs": ["cocody", "marcory", "plateau", "yopougon"],
    },
    {
        "slug": "cocody",
        "name": "Cocody",
        "region": "Abidjan · Cocody",
        "priority": "0.85",
        "quartiers": ["Riviera 2 / 3 / 4", "Angre 7e et 8e tranche", "Deux-Plateaux", "Palmeraie", "M'Badon", "Danga"],
        "intro": "Nos artisans bases a Cocody interviennent rapidement dans les villas, appartements et residences de la Riviera, Deux-Plateaux et Angre.",
        "nearby_slugs": ["abidjan", "bingerville", "plateau", "marcory"],
    },
    {
        "slug": "marcory",
        "name": "Marcory",
        "region": "Abidjan · Marcory",
        "priority": "0.85",
        "quartiers": ["Zone 4", "Bietry", "Marcory Residentiel", "Anoumabo", "INJS", "Remblais"],
        "intro": "Depannage rapide et maintenance fiable a Marcory, Zone 4 et Bietry pour particuliers, residences meublees et entreprises.",
        "nearby_slugs": ["abidjan", "treichville", "koumassi", "plateau"],
    },
    {
        "slug": "plateau",
        "name": "Plateau",
        "region": "Abidjan · Le Plateau",
        "priority": "0.85",
        "quartiers": ["Centre d'affaires", "Cite Administrative", "Avenue Chardy", "Indenie", "Boulevard de la Republique"],
        "intro": "Interventions soignees au Plateau pour bureaux, cabinets, immeubles et appartements avec devis ecrit et facturation transparente.",
        "nearby_slugs": ["abidjan", "cocody", "treichville", "marcory"],
    },
    {
        "slug": "yopougon",
        "name": "Yopougon",
        "region": "Abidjan · Yopougon",
        "priority": "0.85",
        "quartiers": ["Niangon", "Maroc", "Selmer", "Siporex", "Toits-Rouges", "Ananeraie", "Sideci"],
        "intro": "Artisans de proximite verifies a Yopougon pour des interventions rapides, tarifs clairs et paiement Mobile Money protege.",
        "nearby_slugs": ["abidjan", "abobo", "plateau", "cocody"],
    },
    {
        "slug": "treichville",
        "name": "Treichville",
        "region": "Abidjan · Treichville",
        "priority": "0.75",
        "quartiers": ["Avenue 16 / 21", "Arras", "Zone 3", "Belleville", "Port"],
        "intro": "Intervention rapide a Treichville et Zone 3 pour logements, commerces et ateliers avec devis detaille.",
        "nearby_slugs": ["marcory", "plateau", "koumassi", "abidjan"],
    },
    {
        "slug": "koumassi",
        "name": "Koumassi",
        "region": "Abidjan · Koumassi",
        "priority": "0.75",
        "quartiers": ["Remblais", "Sicogi", "Prodomo", "Grand Campement", "Zone Industrielle"],
        "intro": "Trouvez rapidement un professionnel verifie a Koumassi pour vos urgences et travaux a domicile.",
        "nearby_slugs": ["marcory", "treichville", "grand-bassam", "abidjan"],
    },
    {
        "slug": "abobo",
        "name": "Abobo",
        "region": "Abidjan · Abobo",
        "priority": "0.75",
        "quartiers": ["Abobo Baoule", "Dokui", "Avocatier", "PK18", "Samake"],
        "intro": "Prestataires identifies CNI a Abobo et Dokui pour des depannages clairs et sans surprise.",
        "nearby_slugs": ["cocody", "yopougon", "abidjan", "bingerville"],
    },
    {
        "slug": "bingerville",
        "name": "Bingerville",
        "region": "Grand Abidjan · Bingerville",
        "priority": "0.75",
        "quartiers": ["Feh Kesse", "Cite Marina", "Jardin Botanique", "Akandje", "Eloka"],
        "intro": "Couverture dediee des nouvelles cites et residences de Bingerville et Akandje avec artisans verifies.",
        "nearby_slugs": ["cocody", "abidjan", "grand-bassam", "abobo"],
    },
    {
        "slug": "grand-bassam",
        "name": "Grand-Bassam",
        "region": "Sud-Comoe · Grand-Bassam",
        "priority": "0.75",
        "quartiers": ["Quartier France", "Mockeyville", "Modeste", "Imperial", "Zone balneaire"],
        "intro": "Artisans verifies pour residences principales, villas de week-end et hotels a Grand-Bassam et Modeste.",
        "nearby_slugs": ["abidjan", "koumassi", "marcory", "bingerville"],
    },
    {
        "slug": "yamoussoukro",
        "name": "Yamoussoukro",
        "region": "District de Yamoussoukro",
        "priority": "0.75",
        "quartiers": ["220 Logements", "Habitat", "Millionnaire", "Morofe", "Assabou"],
        "intro": "BABIFIX deploie son reseau d'artisans verifies et de paiement securise a Yamoussoukro.",
        "nearby_slugs": ["abidjan", "bouake", "cocody", "plateau"],
    },
    {
        "slug": "bouake",
        "name": "Bouake",
        "region": "Gbeke · Bouake",
        "priority": "0.75",
        "quartiers": ["Air France", "Commerce", "Nimbo", "Koko", "Beaufort"],
        "intro": "Depannage et services a domicile verifies a Bouake avec devis transparents et suivi client.",
        "nearby_slugs": ["yamoussoukro", "abidjan", "cocody", "marcory"],
    },
]

TRADES_BY_SLUG: Dict[str, Dict[str, Any]] = {t["slug"]: t for t in SEO_TRADES}
ZONES_BY_SLUG: Dict[str, Dict[str, Any]] = {z["slug"]: z for z in SEO_ZONES}


def build_home_jsonld(base_url: str, faq_items: Optional[List[Dict[str, str]]] = None) -> str:
    """Genere un graphe Schema.org JSON-LD riche et conforme Google (zero faux avis)."""
    logo_url = f"{base_url}/static/vitrine/assets/babifix-logo.png"
    graph: List[Dict[str, Any]] = [
        {
            "@type": "Organization",
            "@id": f"{base_url}/#organization",
            "name": "BABIFIX",
            "url": f"{base_url}/",
            "logo": {"@type": "ImageObject", "url": logo_url},
            "email": "contact@babifix.ci",
            "description": (
                "Plateforme de services a domicile et maintenance B2B en Cote d'Ivoire : "
                "artisans verifies (CNI), devis ecrit transparent et paiement sous sequestre Mobile Money."
            ),
            "areaServed": {"@type": "Country", "name": "Cote d'Ivoire"},
            "address": {
                "@type": "PostalAddress",
                "addressLocality": "Abidjan",
                "addressCountry": "CI",
            },
            "sameAs": [
                "https://www.tiktok.com/@babifix.ci",
                "https://www.facebook.com/babifix.ci",
                "https://www.instagram.com/babifix.ci",
                "https://www.linkedin.com/company/babifix",
            ],
        },
        {
            "@type": "WebSite",
            "@id": f"{base_url}/#website",
            "url": f"{base_url}/",
            "name": "BABIFIX",
            "inLanguage": "fr-CI",
            "publisher": {"@id": f"{base_url}/#organization"},
            "potentialAction": {
                "@type": "SearchAction",
                "target": f"{base_url}/?q={{search_term_string}}#categories",
                "query-input": "required name=search_term_string",
            },
        },
        {
            "@type": "HomeAndConstructionBusiness",
            "@id": f"{base_url}/#localbusiness",
            "name": "BABIFIX · Services a domicile Cote d'Ivoire",
            "url": f"{base_url}/",
            "image": logo_url,
            "email": "contact@babifix.ci",
            "priceRange": "XOF",
            "currenciesAccepted": "XOF",
            "paymentAccepted": "Orange Money, MTN Mobile Money, Wave, Moov Money",
            "address": {
                "@type": "PostalAddress",
                "addressLocality": "Abidjan",
                "addressRegion": "Lagunes",
                "addressCountry": "CI",
            },
            "areaServed": [
                {"@type": "City", "name": z["name"]} for z in SEO_ZONES
            ],
        },
    ]

    if faq_items:
        entities = []
        for item in faq_items[:10]:
            q = (item.get("question") or "").strip()
            a = (item.get("answer") or "").strip()
            if q and a:
                entities.append(
                    {
                        "@type": "Question",
                        "name": q,
                        "acceptedAnswer": {"@type": "Answer", "text": a},
                    }
                )
        if entities:
            graph.append({"@type": "FAQPage", "mainEntity": entities})

    return safe_json_ld({"@context": "https://schema.org", "@graph": graph})


def build_service_jsonld(
    base_url: str,
    trade: Dict[str, Any],
    zone: Optional[Dict[str, Any]] = None,
) -> str:
    """Genere le graphe JSON-LD (Service + BreadcrumbList + FAQPage) d'une page metier / locale."""
    place_name = zone["name"] if zone else "Cote d'Ivoire"
    page_url = (
        f"{base_url}/services/{trade['slug']}/{zone['slug']}/"
        if zone
        else f"{base_url}/services/{trade['slug']}/"
    )
    crumbs = [
        {"@type": "ListItem", "position": 1, "name": "Accueil", "item": f"{base_url}/"},
        {"@type": "ListItem", "position": 2, "name": "Services", "item": f"{base_url}/services/"},
        {
            "@type": "ListItem",
            "position": 3,
            "name": trade["name"],
            "item": f"{base_url}/services/{trade['slug']}/",
        },
    ]
    if zone:
        crumbs.append(
            {
                "@type": "ListItem",
                "position": 4,
                "name": f"{trade['artisan_label']} a {zone['name']}",
                "item": page_url,
            }
        )

    graph: List[Dict[str, Any]] = [
        {
            "@type": "Service",
            "name": f"{trade['name']} a {place_name}",
            "serviceType": trade["name"],
            "url": page_url,
            "description": trade["hero_subtitle"],
            "provider": {
                "@type": "Organization",
                "name": "BABIFIX",
                "url": f"{base_url}/",
            },
            "areaServed": {
                "@type": "City" if zone else "Country",
                "name": place_name,
            },
            "hasOfferCatalog": {
                "@type": "OfferCatalog",
                "name": f"Prestations {trade['name']}",
                "itemListElement": [
                    {
                        "@type": "Offer",
                        "itemOffered": {"@type": "Service", "name": label},
                    }
                    for label in trade["interventions"]
                ],
            },
        },
        {
            "@type": "BreadcrumbList",
            "itemListElement": crumbs,
        },
        {
            "@type": "FAQPage",
            "mainEntity": [
                {
                    "@type": "Question",
                    "name": q,
                    "acceptedAnswer": {"@type": "Answer", "text": a},
                }
                for q, a in trade["faq"]
            ],
        },
    ]
    return safe_json_ld({"@context": "https://schema.org", "@graph": graph})


def build_services_index_jsonld(base_url: str) -> str:
    """Genere le graphe JSON-LD (CollectionPage + ItemList + BreadcrumbList) de /services/."""
    graph: List[Dict[str, Any]] = [
        {
            "@type": "CollectionPage",
            "name": "Services a domicile en Cote d'Ivoire · BABIFIX",
            "url": f"{base_url}/services/",
            "inLanguage": "fr-CI",
        },
        {
            "@type": "ItemList",
            "name": "Metiers BABIFIX",
            "itemListElement": [
                {
                    "@type": "ListItem",
                    "position": idx,
                    "name": t["name"],
                    "url": f"{base_url}/services/{t['slug']}/",
                }
                for idx, t in enumerate(SEO_TRADES, start=1)
            ],
        },
        {
            "@type": "BreadcrumbList",
            "itemListElement": [
                {"@type": "ListItem", "position": 1, "name": "Accueil", "item": f"{base_url}/"},
                {"@type": "ListItem", "position": 2, "name": "Services", "item": f"{base_url}/services/"},
            ],
        },
    ]
    return safe_json_ld({"@context": "https://schema.org", "@graph": graph})


def sitemap_lastmod_iso() -> str:
    return date.today().isoformat()
