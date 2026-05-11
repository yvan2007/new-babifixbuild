MÉMOIRE DE FIN DE CYCLE
République de Côte d'Ivoire

Union — Discipline — Travail

Ministère de l'Enseignement Supérieur et de la Recherche Scientifique

INSTITUT IVOIRIEN DE TECHNOLOGIE

DÉPARTEMENT D'INFORMATIQUE

THÈME : CONCEPTION ET RÉALISATION D'UNE PLATEFORME NUMÉRIQUE DE SERVICES À DOMICILE EN CÔTE D'IVOIRE — LE CAS BABIFIX
Réalisé par : [NOM Prénom]

Élève en [Cycle / Filière], Promotion [année]

Période du projet : [date de début] — [date de fin]

Année académique : [année]

Directeur de mémoire : [Nom, Prénom et titre]

Maître de stage : M. TIÉ Narcisse, Ingénieur Informaticien — Société Nationale de Développement Informatique (SNDI)

DÉDICACE
À ma famille.

REMERCIEMENTS
Avant d'ouvrir ce rapport, nous tenons tout d'abord à remercier Dieu, pour la santé accordée et la paix du cœur quotidienne.

Nous adressons ensuite nos remerciements au Directeur Général de la Société Nationale de Développement Informatique (SNDI), Monsieur NONGOLOUGO SORA, ainsi qu'à tous les autres responsables de la structure qui nous ont accueilli et permis d'effectuer notre stage dans de bonnes conditions.

Nous remercions tout particulièrement notre maître de stage, Monsieur TIÉ Narcisse, Ingénieur Informaticien, pour son accueil chaleureux, ses conseils, ses orientations et la grande disponibilité dont il a fait preuve tout au long de la période de stage.

Nous adressons également nos remerciements à la Direction de l'Institut Ivoirien de Technologie (IIT) et à [Nom du directeur de mémoire], notre directeur de mémoire, pour sa disponibilité, ses orientations et la confiance qu'il nous a accordée tout au long du projet.

Nous tenons également à exprimer notre gratitude à l'ensemble du corps enseignant du Département d'Informatique de l'IIT pour la qualité de la formation reçue, et pour la patience dont les enseignants ont su faire preuve malgré leurs charges.

À nos camarades de promotion, pour les échanges et l'émulation intellectuelle qui ont enrichi notre réflexion. Et enfin à notre famille, pour son soutien indéfectible : nous adressons nos remerciements les plus sincères.

SOMMAIRE
DÉDICACE
REMERCIEMENTS
SOMMAIRE
AVANT-PROPOS
LISTE DES SIGLES ET ABRÉVIATIONS
LISTE DES TABLEAUX
LISTE DES FIGURES
LISTE DES ANNEXES
RÉSUMÉ
ABSTRACT
INTRODUCTION
PREMIÈRE PARTIE : PRÉSENTATION DE L'ENTREPRISE ET DU THÈME
CHAPITRE I : PRÉSENTATION DE L'ENTREPRISE
CHAPITRE II : PRÉSENTATION DU THÈME
DEUXIÈME PARTIE : ÉTUDE CONCEPTUELLE ET TECHNIQUE
CHAPITRE III : APPROCHE MÉTHODOLOGIQUE
TROISIÈME PARTIE : MISE EN ŒUVRE
CHAPITRE IV : ÉTUDE TECHNIQUE
CHAPITRE V : RÉALISATION
CONCLUSION
RÉFÉRENCES BIBLIOGRAPHIQUES
WEBOGRAPHIES
ANNEXES
AVANT-PROPOS
L'Institut Ivoirien de Technologie (IIT) est un établissement d'enseignement supérieur privé qui forme des techniciens et des ingénieurs dans plusieurs filières, notamment l'informatique, les réseaux et télécommunications, la comptabilité et le management.

Le département d'informatique, dans lequel nous avons effectué notre formation, prépare ses étudiants aux métiers du développement logiciel, des systèmes d'information et de la cybersécurité. Soucieux d'ancrer la pédagogie dans la réalité professionnelle, l'IIT recommande à ses étudiants de réaliser, en fin de cycle, un mémoire à forte composante pratique, capable de témoigner de leur capacité à concevoir et à mettre en œuvre une véritable solution informatique. C'est dans ce cadre que s'inscrit le présent travail consacré à la plateforme BABIFIX.

LISTE DES SIGLES ET ABRÉVIATIONS
Sigle	Signification
API	Interface de programmation applicative
ARTCI	Autorité de Régulation des Télécommunications et TIC de Côte d'Ivoire
BDD	Base de Données
CNI	Carte Nationale d'Identité
DEI	Direction des Études et de l'Ingénierie (SNDI)
EPN	Établissement Public National
EPIC	Établissement Public à caractère Industriel et Commercial
FCFA	Franc de la Communauté Financière Africaine
IIT	Institut Ivoirien de Technologie
KYC	Know Your Customer — vérification d'identité
SGBD	Système de Gestion de Base de Données
SI	Système d'Information
SNDI	Société Nationale de Développement Informatique
TIC	Technologies de l'Information et de la Communication
UEMOA	Union Économique et Monétaire Ouest-Africaine
UML	Unified Modeling Language — langage de modélisation unifié
LISTE DES TABLEAUX
N°	Titre du tableau	Page
Tableau 1	Indicateurs clés du Mobile Money en Côte d'Ivoire	…
Tableau 2	Diagramme de Gantt du projet BABIFIX	…
Tableau 3	Comparatif des plateformes existantes en Côte d'Ivoire	…
Tableau 4	Comparaison entre l'existant et la solution proposée	…
Tableau 5	Liste des besoins fonctionnels (BF-01 à BF-14)	…
Tableau 6	Exigences non fonctionnelles	…
Tableau 7	Liste des cas d'utilisation par acteur	…
Tableau 8	Description des principales classes du système	…
Tableau 9	Justification des choix techniques	…
Tableau 10	Protocoles de tests et résultats	…
Tableau 11	Bilan de conformité aux objectifs	…
LISTE DES FIGURES
N°	Titre de la figure	Page
Figure 1	Architecture générale de la plateforme BABIFIX	…
Figure 2	Diagramme des cas d'utilisation	…
Figure 3	Diagramme de classes	…
Figure 4	Diagramme de séquence — réservation et paiement	…
Figure 5	Diagramme d'activité — inscription du prestataire	…
Figure 6	Diagramme d'état — cycle de vie d'une réservation	…
Figure 7	Logo PostgreSQL	…
Figure 8	Logo Django	…
Figure 9	Logo Flutter	…
Figure 10	Écran d'accueil de l'application client	…
Figure 11	Écran de réservation	…
Figure 12	Écran de chat	…
Figure 13	Écran d'inscription du prestataire	…
Figure 14	Écran d'attente de validation	…
Figure 15	Tableau de bord de l'administrateur	…
LISTE DES ANNEXES
N°	Titre de l'annexe	Page
Annexe 1	Organigramme administratif de la SNDI	…
Annexe 2	Captures d'écran complémentaires des interfaces	…
RÉSUMÉ
Réalisé dans le cadre de notre projet de fin de cycle à l'Institut Ivoirien de Technologie, ce travail a pour objet la conception et la réalisation d'une plateforme numérique de services à domicile en Côte d'Ivoire, baptisée BABIFIX.

Le projet part d'un constat simple : le secteur des services à domicile — plomberie, électricité, ménage, jardinage, garde d'enfants — est largement informel en Côte d'Ivoire. Les clients peinent à trouver des prestataires fiables, et les artisans n'ont pas de moyen simple de se faire connaître ni de se faire payer en toute sécurité. Le besoin d'une solution numérique mettant en relation clients et prestataires, tout en garantissant la confiance, devient donc une nécessité.

Notre travail a consisté, dans un premier temps, à étudier le marché ivoirien et à analyser les solutions existantes. Dans un second temps, nous avons conçu une plateforme composée de quatre interfaces — une application mobile pour le client, une application mobile pour le prestataire, un site web de présentation et un panneau d'administration — toutes reliées à un même serveur central. La modélisation du système a été menée en UML, avec les diagrammes de cas d'utilisation, de classes, de séquences, d'activités et d'états. La plateforme s'articule autour d'un cycle de devis qui rend la prestation transparente, d'un chat temps réel lié à chaque réservation, d'un portefeuille pour le prestataire, et de mécanismes de fidélité et de parrainage destinés à animer la communauté. Enfin, nous avons réalisé l'application en nous appuyant sur les outils Python, Django, Flutter, PostgreSQL et Firebase, puis nous avons testé l'ensemble du parcours utilisateur.

ABSTRACT
This work, conducted as part of our final-year project at the Ivorian Institute of Technology, presents the design and implementation of a digital home-services platform in Côte d'Ivoire, named BABIFIX.

The project arises from a simple observation: the home-services sector — plumbing, electrical work, cleaning, gardening, childcare — operates largely informally in Côte d'Ivoire. Customers struggle to find reliable service providers, and craftsmen have no easy way to advertise themselves or to receive payments securely. A digital solution connecting customers and providers, while building trust, has therefore become a real necessity.

Our work consisted first of studying the Ivorian market and analysing existing solutions. We then designed a platform made up of four interfaces — a mobile app for the customer, a mobile app for the service provider, a public showcase website and an administration panel — all connected to a single central server. The system was modelled using UML, with use case, class, sequence, activity and state diagrams. It revolves around a quotation cycle which keeps the service relationship transparent, a real-time chat bound to each booking, a digital wallet for the service provider, as well as loyalty and referral mechanisms designed to engage the community. Finally, we implemented the application using the Python, Django, Flutter, PostgreSQL and Firebase technologies, and tested the complete user journey.

INTRODUCTION
Depuis quelques années, les téléphones mobiles et internet ont profondément changé la manière dont les gens accèdent aux services. Dans les grandes villes du monde, des plateformes comme Uber pour le transport, Airbnb pour le logement, ou TaskRabbit pour les services à domicile, ont démontré que les particuliers étaient prêts à passer par une application mobile pour trouver un service, le réserver et le payer.

En Côte d'Ivoire, et plus particulièrement à Abidjan, cette tendance s'observe également. Le pays compte aujourd'hui plus de vingt-quatre millions de comptes Mobile Money et plus de 70 % des adultes utilisent un service de paiement par téléphone. Ces chiffres montrent que la population est prête à effectuer des transactions numériques. Pourtant, le secteur des services à domicile reste massivement informel : plomberie, électricité, ménage, jardinage et autres prestations passent encore par le bouche-à-oreille, par les réseaux sociaux ou par des annonces dans le quartier. Ce mode de fonctionnement crée une asymétrie d'information : le client ne sait pas s'il peut faire confiance à l'intervenant qu'il invite chez lui, et le prestataire honnête peine à se distinguer des autres.

Face à ce constat, l'idée de BABIFIX est née : proposer une plateforme numérique qui permette à un client ivoirien de trouver un prestataire vérifié, de réserver son service, d'échanger avec lui en temps réel et de le payer en toute sécurité, le tout en francs CFA.

Cette partie présente la Société Nationale de Développement Informatique (SNDI), structure qui nous a accueilli pour la réalisation de notre projet de fin de cycle, ainsi que le contexte du thème, ses objectifs et le plan général du travail.

Le présent mémoire est organisé en trois parties. La Première Partie présente la structure d'accueil et le thème du mémoire, avec son contexte, ses objectifs et la planification du projet. La Deuxième Partie expose l'étude conceptuelle et technique : l'analyse de l'existant, la solution proposée et la modélisation UML du système. La Troisième Partie détaille la mise en œuvre : les choix techniques retenus et la présentation de la solution réalisée à travers ses différentes interfaces.

PREMIÈRE PARTIE : PRÉSENTATION DE L'ENTREPRISE ET DU THÈME
Cette partie présente l'Institut Ivoirien de Technologie, structure d'accueil de notre projet de fin de cycle, ainsi que le thème retenu, son contexte, ses objectifs et sa planification.

CHAPITRE I : PRÉSENTATION DE L'ENTREPRISE
1.1. Historique
La Société Nationale de Développement Informatique, en abrégé SNDI, est une société d'État de droit privé dont le rôle est d'effectuer, dans le domaine informatique, des prestations de gestion, de conseil et de formation à l'adresse de l'État, de ses ramifications et du secteur privé. Elle a été créée par le décret n°99-220 du 10 mars 1999 et est placée sous la tutelle du Ministère de l'économie numérique et de la poste.

Son siège social est situé à Abidjan-Plateau, Boulevard Angoulvant, à la cité Financière (Tour B), au quatrième étage de l'immeuble du Trésor (BP V69 Abidjan — Tél. : 20 21 78 81 / 20 21 79 41).

La SNDI propose une offre de services intégrés, composée de neuf grands domaines d'activités stratégiques et d'expertise métier, qui vont de l'élaboration d'une stratégie informatique jusqu'à la maintenance des systèmes d'information. Présente en Côte d'Ivoire et dans la sous-région — notamment au Sénégal, au Bénin, au Togo et en Guinée Bissau —, elle compte plus de deux cent quinze employés, dont plus de 70 % de ressources techniques (techniciens supérieurs, ingénieurs et autres), appuyés par une centaine de collaborateurs extérieurs.

Pour accéder au meilleur savoir-faire et accroître ses compétences, la SNDI a conclu des partenariats avec des éditeurs de logiciels et des fabricants de matériels informatiques de premier plan, ce qui lui permet de proposer à ses clients des solutions adaptées à leurs besoins. Sa clientèle est variée : administration publique, structures parapubliques, organismes et institutions, collectivités et entreprises privées de tout secteur d'activité.

1.2. Domaine d'activité
Depuis sa création, la SNDI exerce dans le domaine informatique des prestations de gestion, de conseil et de formation à l'adresse de l'État et de ses ramifications. Elle dispose d'un large panel de métiers et d'expertises, parmi lesquels :

le développement et l'intégration de solutions logicielles ;
les études et le conseil en systèmes d'information ;
les réseaux et les télécommunications ;
l'administration de bases de données et de datacenters ;
l'archivage numérique ;
la cybersécurité ;
la formation et les services associés.
Grâce à ses partenariats avec des acteurs internationaux comme CISCO, RedHat ou Juniper Networks, la SNDI peut offrir à ses clients, en toute liberté, des solutions à l'exacte mesure de leurs besoins, sur les architectures et les technologies majeures du marché.

1.3. Missions de la SNDI
La SNDI a pour mission d'effectuer, dans le domaine informatique, des prestations de gestion, de conseil et de formation pour le compte de l'administration publique, des structures parapubliques, des sociétés d'État, des institutions et des organismes internationaux. Elle s'intègre aux organisations de ses clients afin de mieux s'imprégner de leurs réalités de fonctionnement et de saisir leurs besoins réels, dans le but de proposer des solutions informatiques plus efficaces leur permettant de se consacrer à leurs métiers et d'être plus productifs.

1.4. Organisation administrative
L'organisation administrative de la SNDI est présentée en Annexe 1.

1.5. Département d'accueil : Génie Logiciel
Notre stage s'est déroulé au sein du Département Génie Logiciel de la SNDI. Ce département a en charge le développement des applications informatiques. Il est rattaché à la Direction des Études et de l'Ingénierie (DEI), qui supervise l'ensemble des prestations offertes par la SNDI et a pour mission de concevoir le plan informatique national, de réaliser les schémas directeurs informatiques à la demande des administrations, et d'apporter son expérience dans la réalisation des marchés informatiques.

C'est dans ce cadre et avec l'accompagnement du Département Génie Logiciel que nous avons conduit l'étude et la réalisation du projet BABIFIX présenté dans ce mémoire.

CHAPITRE II : PRÉSENTATION DU THÈME
2.1. Présentation du thème et son contexte
Le thème retenu pour notre mémoire est intitulé : « Conception et réalisation d'une plateforme numérique de services à domicile en Côte d'Ivoire — le cas BABIFIX ».

Le contexte est le suivant : à Abidjan comme dans les autres grandes villes du pays, les particuliers ont régulièrement besoin de prestations à domicile telles que la plomberie, l'électricité, le ménage, le jardinage, les cours particuliers ou la garde d'enfants. Aujourd'hui, ces services sont rendus par des artisans et des professionnels qui exercent en grande majorité dans le secteur informel, sans contrat, sans cadre juridique formalisé et sans dispositif clair de contrôle qualité. Le client cherche le plus souvent son prestataire par le bouche-à-oreille, par les réseaux sociaux ou par les annonces collées dans le quartier.

Cette manière de fonctionner pose plusieurs problèmes. Le client n'a aucun moyen de vérifier l'identité ou les références d'un intervenant avant de l'inviter chez lui. Il n'a pas non plus de recours simple en cas de prestation mal faite. De son côté, le prestataire honnête a beaucoup de mal à se faire connaître au-delà de son cercle de proximité, et les paiements se font le plus souvent en espèces, sans aucune traçabilité.

C'est pour répondre à ces difficultés que nous avons proposé la plateforme BABIFIX : une solution numérique qui met en relation des clients particuliers et des prestataires vérifiés, qui permet d'échanger des messages en temps réel et qui prend en charge les paiements en francs CFA via le Mobile Money (Orange Money, MTN Moov Money, Moov Africa, Wave) ou en espèces.

Cette orientation s'appuie sur un contexte favorable : la Côte d'Ivoire figure parmi les pays africains les plus avancés dans l'adoption du paiement mobile, comme le résument les indicateurs ci-dessous.

Tableau 1 — Indicateurs clés du Mobile Money en Côte d'Ivoire

Indicateur	Valeur
Taux de pénétration du Mobile Money chez les adultes	Plus de 70 %
Nombre de comptes actifs (tous opérateurs confondus)	24 millions
Volume annuel des transactions	Plus de 40 000 milliards de FCFA
Opérateurs historiques présents sur le marché	Orange Money, MTN Moov Money, Moov Africa
Nouvel entrant en forte progression	Wave
Taux d'inclusion financière (Mobile Money compris)	82 %
Taux de bancarisation classique	26 %
Ces chiffres confirment que la majorité des Ivoiriens dispose déjà d'un moyen de paiement numérique au quotidien, mais sans plateforme adaptée pour l'utiliser dans le cadre des services à domicile. C'est précisément ce vide que BABIFIX vient combler.

2.2. Objectifs du thème
L'objectif principal du projet est de concevoir et réaliser une plateforme numérique capable de répondre aux besoins exprimés par les deux parties — clients et prestataires — tout en assurant un cadre de confiance.

Plus précisément, la solution doit permettre au client de parcourir les prestataires disponibles dans une catégorie donnée avec leur photo, leur description, leur note et leur tarif, de localiser sur une carte ceux qui se trouvent près de chez lui, de réserver un service en choisissant une date et un créneau, de recevoir un devis détaillé du prestataire avant de confirmer, d'échanger des messages directement avec lui, de payer en francs CFA par Mobile Money ou en espèces, et d'évaluer le prestataire à la fin de la prestation. Le client doit également pouvoir bénéficier d'un programme de fidélité ainsi que d'un système de parrainage lui permettant de recommander la plateforme à son entourage.

Du côté du prestataire, la plateforme doit permettre de s'inscrire en soumettant une pièce d'identité, de recevoir une décision claire de l'administrateur — acceptation ou refus motivé —, de fixer ses créneaux de disponibilité, de rédiger des devis en réponse aux demandes des clients, de suivre ses missions, de noter à son tour ses clients à la fin de la prestation, et de consulter ses revenus à travers un portefeuille personnel depuis lequel il peut suivre ses gains et déclencher ses retraits.

Enfin, du côté de l'administrateur, le système doit offrir un panneau dédié pour gérer les prestataires, vérifier leurs pièces d'identité, gérer les catégories de services, publier des actualités, suivre les paiements, traiter les éventuels litiges et consulter les statistiques de la plateforme.

2.3. Modèle économique et viabilité du projet
Pour que la plateforme puisse fonctionner de manière durable, il est nécessaire de penser, dès la conception, à son modèle économique. Nous avons retenu une approche simple, progressive et adaptée au marché ivoirien.

La principale source de revenus est une commission de dix-huit pour cent (18 %) prélevée sur chaque réservation menée à son terme. Ce mécanisme présente un double avantage. D'une part, il aligne les intérêts de la plateforme sur ceux des prestataires : BABIFIX n'encaisse de revenu que lorsque la prestation est réellement réalisée et payée. D'autre part, ce taux nous permet de financer l'infrastructure, la modération des dossiers, le support utilisateur et le développement continu de la plateforme, tout en laissant au prestataire l'essentiel du fruit de son travail.

À cette source principale s'ajouteront, dans les phases ultérieures de développement, deux compléments. Un abonnement premium sera proposé aux prestataires souhaitant bénéficier d'avantages additionnels : statistiques détaillées de leur activité, badge de certification mis en avant sur leur profil, et priorité dans les résultats de recherche. Une offre de mise en avant sponsorisée permettra aux prestataires qui le souhaitent d'apparaître en tête des résultats d'une catégorie ou d'une zone géographique donnée pendant une période choisie.

À titre d'illustration, une projection prudente sur la première année dans le Grand Abidjan permet de mesurer la viabilité du modèle. En retenant l'hypothèse de cinq cents prestataires actifs réalisant en moyenne huit missions par mois pour un montant moyen de douze mille francs CFA par mission, on obtient un volume mensuel d'environ quarante-huit millions de francs CFA de transactions. La commission de dix-huit pour cent représenterait alors un revenu mensuel brut de l'ordre de huit millions six cent mille francs CFA, soit environ cent trois millions de francs CFA par an. Une fois déduits les coûts d'infrastructure, de modération et de support, ce volume permet d'envisager un équilibre économique dès la première année, puis une croissance soutenue à mesure que la communauté de prestataires et de clients s'étoffe.

Ces estimations restent volontairement conservatrices ; elles servent surtout à démontrer que la plateforme n'est pas seulement faisable sur le plan technique, mais qu'elle l'est également sur le plan économique.

2.4. Planification des tâches
Pour mener à bien notre projet, nous avons découpé le travail en plusieurs grandes phases que nous avons planifiées dans le temps. Le diagramme de Gantt présenté ci-dessous représente cette planification sur une période de seize semaines.

Tableau 2 — Diagramme de Gantt du projet BABIFIX

Activité	M1	M2	M3	M4
Cadrage et étude des besoins	✅			
Analyse et conception (UML)	✅	✅		
Choix techniques et préparation de l'environnement		✅		
Développement des modules		✅	✅	✅
Tests et corrections			✅	✅
Documentation et rédaction du mémoire			✅	✅
Préparation de la soutenance				✅
DEUXIÈME PARTIE : ÉTUDE CONCEPTUELLE ET TECHNIQUE
Dans cette partie, nous présentons la démarche que nous avons suivie pour analyser le besoin et concevoir la solution, ainsi que la modélisation UML qui en a découlé.

CHAPITRE III : APPROCHE MÉTHODOLOGIQUE
3.1. Étude de l'existant
Avant de concevoir notre plateforme, nous avons étudié la manière dont les services à domicile sont actuellement organisés en Côte d'Ivoire. Nous avons constaté que la mise en relation entre clients et prestataires se fait principalement par trois canaux : le bouche-à-oreille familial et amical, les groupes de discussion sur les réseaux sociaux (notamment WhatsApp), et les annonces dans les quartiers ou aux entrées des marchés.

Nous avons également recensé quelques solutions numériques déjà disponibles en Côte d'Ivoire, telles que Yako Services, OnDjossi, Gombo ou Mon Artisan. Toutefois, ces solutions restent partielles : la plupart se contentent d'afficher un répertoire de prestataires sans réel système de réservation, sans messagerie intégrée et sans paiement par Mobile Money. Le tableau suivant en présente une comparaison synthétique selon les principaux critères qui caractérisent une plateforme complète de services à domicile.

Tableau 3 — Comparatif des plateformes existantes en Côte d'Ivoire

Plateforme	Domaine couvert	Vérification du prestataire	Messagerie intégrée	Paiement numérique
Yako Services	Ménage, plomberie, électricité	Non	Non	Non
OnDjossi	Cuisine à domicile	Non	Non	Non
Gombo	Multi-services	Non documentée	Non documentée	Non documenté
Mon Artisan	Plomberie, menuiserie, électricité	Formation et test des prestataires	Non documentée	Non documenté
BABIFIX	Multi-services	Pièce d'identité + validation administrateur	Oui, liée à chaque réservation	Mobile Money + espèces (en FCFA)
Cette analyse confirme que BABIFIX se distingue des solutions disponibles sur trois points essentiels : une vérification administrative formalisée des prestataires, une messagerie temps réel adossée à la réservation, et un paiement adapté au marché ivoirien.

3.2. Analyse de l'existant
L'étude que nous avons menée fait ressortir trois insuffisances majeures dans le mode de fonctionnement actuel.

D'abord, la confiance n'est pas garantie. Le client n'a aucun moyen simple de vérifier qu'un prestataire est bien la personne qu'il prétend être. Aucune pièce d'identité n'est demandée, aucune validation n'est faite par un tiers.

Ensuite, la communication est désorganisée. Une fois le contact établi, les échanges se déroulent par appels téléphoniques ou par messages dispersés, sans aucun lien avec une réservation précise. Quand survient un désaccord, il n'existe pas d'historique consultable.

Enfin, les paiements ne sont pas adaptés. Les rares plateformes existantes proposent un paiement par carte bancaire, alors que la majorité des Ivoiriens n'en possèdent pas. Le Mobile Money, qui est pourtant le moyen de paiement le plus utilisé dans le pays, n'est pas pris en charge.

3.3. Proposition de solution
Sur la base de cette analyse, nous proposons la plateforme BABIFIX. Il s'agit d'un système d'information complet qui apporte une réponse aux trois insuffisances identifiées et qui structure la relation entre le client et le prestataire d'un bout à l'autre du parcours.

Pour assurer la confiance, chaque prestataire est obligé de soumettre sa Carte Nationale d'Identité au moment de son inscription, accompagnée d'une photo le tenant en main. L'administrateur examine le dossier et l'accepte ou le refuse en motivant clairement sa décision. Tant qu'un prestataire n'est pas validé, il n'apparaît pas dans les résultats des clients. À la fin de chaque mission, le client note le prestataire et, à son tour, le prestataire note le client : cette notation bidirectionnelle entretient un climat de respect mutuel et permet à la plateforme d'identifier rapidement les comportements problématiques.

Pour faciliter la communication, chaque réservation dispose d'un fil de discussion qui lui est propre. Le client et le prestataire peuvent y échanger en temps réel, et la plateforme conserve l'historique des messages. Un compteur de messages non lus informe immédiatement l'utilisateur lorsqu'un nouveau message arrive.

Pour rendre la prestation transparente, BABIFIX introduit un cycle de devis structuré. Lorsqu'un client envoie sa demande, le prestataire ne s'engage pas immédiatement : il étudie le besoin, consulte éventuellement les photos jointes, échange avec le client par message si nécessaire, puis lui transmet un devis détaillé indiquant le diagnostic, le montant et la date proposée. Le client a alors le choix d'accepter ou de refuser le devis. Ce cycle évite les mauvaises surprises sur le prix le jour de l'intervention et donne au client la maîtrise de sa décision.

Pour les paiements, BABIFIX intègre nativement les opérateurs Mobile Money utilisés en Côte d'Ivoire (Orange Money, MTN Moov Money, Moov Africa, Wave) et propose également le paiement en espèces. Tous les montants sont affichés et enregistrés en francs CFA.

Pour fidéliser et faire grandir la communauté, la plateforme propose enfin un programme de fidélité qui récompense les clients réguliers, ainsi qu'un système de parrainage : chaque utilisateur dispose d'un code personnel qu'il peut partager pour inviter ses proches à rejoindre BABIFIX, et il bénéficie d'avantages lorsque ses filleuls effectuent leurs premières réservations.

Le tableau suivant résume les apports de notre solution par rapport à la situation existante.

Tableau 4 — Comparaison entre l'existant et la solution proposée

Critère	Situation existante	BABIFIX
Mise en relation	Bouche-à-oreille, réseaux sociaux	Application mobile dédiée
Vérification du prestataire	Aucune	Pièce d'identité + validation par l'administrateur
Communication	Appels et messages dispersés	Chat lié à chaque réservation
Paiement	Espèces, parfois carte bancaire	Mobile Money + espèces, en francs CFA
Historique	Pas de trace	Toutes les actions sont enregistrées
Évaluation du service	Aucune	Note et commentaire après chaque prestation
L'architecture générale de la plateforme est représentée à la Figure 1. Elle comprend quatre interfaces utilisateur — une application mobile pour le client, une application mobile pour le prestataire, un site web de présentation et un panneau d'administration — toutes reliées à un même serveur central qui gère les données et les échanges.

[Figure 1 : Architecture générale de la plateforme BABIFIX]

3.4. Méthode d'analyse et de modélisation
3.4.1. Présentation d'UML
Pour modéliser notre système, nous avons retenu le langage UML (Unified Modeling Language). UML est une norme internationale, largement enseignée en informatique, qui propose un ensemble de diagrammes permettant de représenter graphiquement les différents aspects d'un logiciel : ses utilisateurs, ses données, ses interactions et son comportement dans le temps.

Nous avons utilisé l'outil PlantUML pour rédiger ces diagrammes sous forme textuelle, ce qui présente l'avantage de pouvoir les versionner facilement et de générer automatiquement leur rendu graphique. Cinq familles de diagrammes ont été produites au cours du projet : les diagrammes de cas d'utilisation, qui décrivent ce que chaque utilisateur peut faire ; le diagramme de classes, qui représente la structure des données ; les diagrammes de séquence, qui retracent les échanges entre l'utilisateur et le système au fil du temps ; les diagrammes d'activité, qui décrivent les parcours utilisateur ; et les diagrammes d'état, qui modélisent le cycle de vie des objets importants comme la réservation ou le compte prestataire.

3.4.2. Règles de gestion
Une règle de gestion exprime une contrainte que le système doit respecter. Pour BABIFIX, les principales règles de gestion retenues sont les suivantes :

un client doit s'inscrire et créer un compte avant de pouvoir réserver un service ;
un prestataire ne devient visible qu'après validation de son dossier par l'administrateur ;
une réservation est obligatoirement liée à un client, à un prestataire et à un service ;
un prestataire ne peut accepter qu'une réservation à la fois sur un même créneau ;
un client ne peut noter un prestataire qu'après la réalisation effective de la prestation ;
tous les montants sont exprimés en francs CFA ;
toute action sensible de l'administrateur (validation, refus, suspension) est enregistrée dans un journal.
3.4.3. Besoins fonctionnels
Les besoins fonctionnels décrivent ce que le système doit savoir faire, c'est-à-dire les services qu'il doit rendre à chaque acteur. Nous avons recensé quatorze besoins fonctionnels, présentés dans le tableau ci-dessous. Chaque besoin est numéroté de BF-01 à BF-14, accompagné de l'acteur principal concerné et d'un niveau de priorité.

Tableau 5 — Liste des besoins fonctionnels (BF-01 à BF-14)

Code	Besoin fonctionnel	Acteur concerné	Priorité
BF-01	Inscription et connexion sécurisée à la plateforme	Client, Prestataire	Haute
BF-02	Soumission du dossier prestataire avec pièce d'identité	Prestataire	Haute
BF-03	Validation ou refus motivé du dossier par l'administrateur	Administrateur	Haute
BF-04	Correction et resoumission du dossier en cas de refus	Prestataire	Haute
BF-05	Recherche et filtrage des prestataires par catégorie, note et proximité	Client	Haute
BF-06	Envoi d'une demande de réservation accompagnée de photos	Client	Haute
BF-07	Rédaction et transmission d'un devis détaillé au client	Prestataire	Haute
BF-08	Acceptation ou refus du devis par le client	Client	Haute
BF-09	Chat temps réel lié à chaque réservation avec badge de messages non lus	Client, Prestataire	Haute
BF-10	Paiement en francs CFA par Mobile Money ou en espèces	Client	Haute
BF-11	Notation bidirectionnelle à la fin de la prestation	Client, Prestataire	Haute
BF-12	Gestion des disponibilités et indisponibilités	Prestataire	Moyenne
BF-13	Portefeuille de revenus et retrait des gains	Prestataire	Haute
BF-14	Tableau de bord, gestion des catégories, des litiges et des actualités	Administrateur	Haute
3.4.4. Exigences non fonctionnelles
Au-delà de ce que le système doit faire, des exigences non fonctionnelles encadrent la manière dont il doit le faire : performance, sécurité, ergonomie, disponibilité. Le tableau suivant récapitule les principales exigences retenues pour BABIFIX.

Tableau 6 — Exigences non fonctionnelles

Catégorie	Exigence	Cible
Performance	Temps de réponse des écrans courants	Inférieur à une seconde
Performance	Délai de réception d'un message dans le chat	Quelques secondes au maximum
Disponibilité	Taux de disponibilité du service	Au moins 99 %
Sécurité	Authentification par mot de passe + option biométrique	Obligatoire
Sécurité	Vérification de l'identité des prestataires (pièce d'identité + selfie)	Obligatoire
Sécurité	Chiffrement des communications entre les applications et le serveur	Obligatoire
Confidentialité	Conformité à la Loi ivoirienne n°2013-450 sur les données personnelles	Obligatoire
Ergonomie	Interfaces mobiles adaptées aux smartphones courants en Côte d'Ivoire	Obligatoire
Ergonomie	Affichage des montants en francs CFA	Obligatoire
Accessibilité	Navigation simple par onglets, lisibilité des textes	Obligatoire
3.4.5. Diagramme des cas d'utilisation
Le diagramme des cas d'utilisation présente la vue globale des interactions entre les acteurs et le système. Il identifie trois acteurs principaux — le client, le prestataire et l'administrateur — qui correspondent aux trois grands rôles de la plateforme.

Le client peut s'inscrire, se connecter, parcourir les catégories de services, localiser les prestataires sur une carte, consulter leurs profils, envoyer une demande de réservation, recevoir et accepter ou refuser un devis, payer la prestation, échanger des messages, recevoir des notifications, évaluer le prestataire à la fin de la mission, consulter ses réservations passées, profiter du programme de fidélité et parrainer ses proches.

Le prestataire peut s'inscrire et soumettre sa pièce d'identité, attendre la validation de son dossier, recevoir la décision de l'administrateur, corriger et resoumettre son dossier en cas de refus, consulter les demandes reçues, rédiger et envoyer un devis au client, accepter ou décliner une mission, fixer ses créneaux de disponibilité, démarrer puis clôturer la prestation, échanger avec le client, noter à son tour le client à la fin de la mission, consulter son portefeuille de revenus et déclencher des retraits, et profiter lui aussi du parrainage.

L'administrateur, enfin, peut se connecter au panneau d'administration, valider ou refuser un prestataire en motivant sa décision, gérer les catégories de services, consulter le tableau de bord, suivre les paiements, traiter les litiges et publier des actualités.

Le tableau suivant récapitule les principaux cas d'utilisation par acteur.

Tableau 7 — Liste des cas d'utilisation par acteur

Acteur	Cas d'utilisation principaux
Client	S'inscrire, se connecter, rechercher un prestataire, localiser sur la carte, envoyer une demande, recevoir un devis, accepter ou refuser un devis, payer, communiquer, noter, parrainer, profiter de la fidélité
Prestataire	S'inscrire, soumettre la CNI, corriger et resoumettre si refusé, gérer ses disponibilités, consulter une demande, rédiger un devis, démarrer la prestation, la clôturer, communiquer, noter le client, suivre son portefeuille, retirer ses gains
Administrateur	Se connecter, valider ou refuser un prestataire, gérer les catégories, suivre les paiements, traiter les litiges, publier des actualités, consulter les statistiques
Le diagramme complet des cas d'utilisation est représenté à la Figure 2.

[Figure 2 : Diagramme des cas d'utilisation]

3.4.6. Diagramme de classes
Le diagramme de classes présente la structure des données manipulées par le système ainsi que les relations qui les unissent. Pour BABIFIX, ce diagramme s'articule autour d'une classe centrale, Utilisateur, qui se décline en trois types : Client, Prestataire et Administrateur.

Le Client est lié à ses Réservations. Chaque Réservation concerne un Service, lui-même rattaché à une Catégorie. Une réservation déclenche la création d'une Conversation contenant un ensemble de Messages, ainsi qu'un Paiement et, à la fin de la prestation, une Note attribuée par le client au prestataire. Les Notifications sont envoyées aux différents utilisateurs selon les évènements survenus, et les Actualités sont publiées par l'administrateur à destination de la communauté.

Tableau 8 — Description des principales classes du système

Classe	Rôle
Utilisateur	Classe générique représentant tout utilisateur (Client, Prestataire ou Administrateur)
Client	Particulier qui réserve des services
Prestataire	Artisan ou professionnel qui propose ses services ; possède un statut (en attente, validé, refusé) et un éventuel motif de refus
Administrateur	Gestionnaire de la plateforme
Catégorie	Famille de services (plomberie, électricité, ménage, etc.)
Service	Prestation proposée par un prestataire
Réservation	Demande effectuée par un client pour un service ; possède un statut au cours du cycle de vie
Conversation	Fil de discussion lié à une réservation
Message	Message échangé dans une conversation
Paiement	Règlement effectué pour une réservation, en Mobile Money ou en espèces
Note	Évaluation du prestataire par le client après la prestation
Notification	Message système envoyé à un utilisateur
Actualité	Information publiée par l'administrateur
Le diagramme complet des classes est représenté à la Figure 3.

[Figure 3 : Diagramme de classes]

3.4.7. Diagrammes de séquence
Les diagrammes de séquence décrivent les échanges qui se produisent entre les acteurs et le système au fil du temps. Ils permettent de visualiser, étape par étape, le déroulement d'un scénario.

Dans notre projet, plusieurs diagrammes de séquence ont été produits pour illustrer les flux les plus importants : le parcours complet de demande, de devis, de réservation et de paiement côté client, l'inscription et la validation d'un prestataire, le traitement administratif des dossiers, le paiement Mobile Money, le paiement en espèces, le fonctionnement du chat temps réel entre le client et le prestataire, ainsi que la gestion d'un litige. La Figure 4 présente, à titre d'exemple, le diagramme de séquence de la réservation et du paiement, qui retrace toutes les interactions depuis l'envoi de la demande par le client jusqu'à la confirmation du paiement final, en passant par la transmission du devis et son acceptation.

[Figure 4 : Diagramme de séquence — réservation et paiement]

3.4.8. Diagrammes d'activité
Les diagrammes d'activité représentent les parcours utilisateur sous forme de schémas de flux, en décrivant les enchaînements d'actions et les décisions à prendre. Quatre diagrammes d'activité ont été produits au cours du projet : le parcours du client lorsqu'il effectue une réservation, le parcours du prestataire au moment de son inscription et de sa validation, le parcours de l'administrateur dans la gestion quotidienne de la plateforme, et le parcours de notation à la fin d'une prestation. La Figure 5 illustre, à titre d'exemple, l'inscription du prestataire avec ses trois issues possibles : acceptation, refus avec correction, ou abandon.

[Figure 5 : Diagramme d'activité — inscription du prestataire]

3.4.9. Diagrammes d'état
Les diagrammes d'état modélisent le cycle de vie d'un objet en représentant les différents états par lesquels il peut passer ainsi que les transitions qui les relient. Deux diagrammes d'état ont été produits dans le cadre de ce projet.

Le premier concerne le cycle de vie d'une réservation, qui suit le parcours suivant : la demande envoyée par le client est reçue par le prestataire, qui passe alors à la phase de préparation du devis, puis transmet le devis envoyé au client. Ce dernier accepte le devis (devis accepté), ce qui autorise le démarrage de l'intervention en cours. À la fin des travaux, la réservation passe en attente de validation du client ; lorsque le client confirme, la réservation devient terminée. Une annulation peut intervenir à n'importe quelle étape antérieure à l'intervention. Ce cycle est représenté à la Figure 6.

[Figure 6 : Diagramme d'état — cycle de vie d'une réservation]

Le second diagramme modélise le cycle de vie d'un compte prestataire, qui peut être en attente de validation, validé, refusé ou suspendu, l'administrateur ayant la possibilité de basculer un compte d'un état à l'autre selon les évènements.

TROISIÈME PARTIE : MISE EN ŒUVRE
Dans cette partie, nous présentons les choix techniques retenus pour la réalisation de BABIFIX, puis nous décrivons les principales interfaces de la solution réalisée à travers quelques captures d'écran.

CHAPITRE IV : ÉTUDE TECHNIQUE
Dans ce chapitre, nous justifions les choix techniques que nous avons retenus pour la réalisation du système.

4.1. Choix de la base de données
Pour stocker les données de BABIFIX, nous avons retenu PostgreSQL.

PostgreSQL est un Système de Gestion de Base de Données relationnel, libre et gratuit. Il est riche en fonctionnalités, capable de manipuler de gros volumes de données de manière fiable, et il est très largement utilisé dans le monde professionnel. Il dispose d'un planificateur de requêtes performant et permet de définir des contraintes d'intégrité fortes — clés primaires, clés étrangères, valeurs uniques — qui garantissent la cohérence des informations. Pendant la phase de développement, nous avons utilisé SQLite, plus léger et plus simple à mettre en place, avant de basculer sur PostgreSQL pour la mise en production.

[Figure 7 : Logo PostgreSQL]

4.2. Choix du framework côté serveur
Pour le serveur d'application, nous avons retenu le framework Django, associé au serveur Daphne.

Django est un framework écrit en Python qui permet de développer rapidement des applications web complètes. Il offre nativement une couche d'accès à la base de données, un système d'authentification, un panneau d'administration et un mécanisme de migration des données. Pour les fonctionnalités de temps réel — c'est-à-dire la messagerie instantanée entre client et prestataire —, Django est complété par Django Channels, qui permet de gérer des connexions persistantes entre le serveur et les applications mobiles. Daphne est le serveur qui exécute Django et Django Channels en production.

[Figure 8 : Logo Django]

4.3. Choix de la technologie mobile
Pour les applications mobiles, nous avons retenu Flutter, un cadre de développement créé par Google et basé sur le langage Dart. Flutter présente un avantage majeur pour notre projet : il permet, à partir d'une seule base de code, de produire à la fois une application pour Android et une application pour iOS. Cela nous a permis de développer en parallèle deux applications — l'une destinée au client, l'autre au prestataire — sans dupliquer notre travail. Les écrans produits par Flutter offrent par ailleurs un rendu fluide, comparable à celui des applications natives.

[Figure 9 : Logo Flutter]

4.4. Notifications et paiements
Pour envoyer des notifications aux utilisateurs — par exemple lorsqu'une réservation est validée, qu'un message est reçu ou qu'un paiement aboutit —, nous avons retenu Firebase Cloud Messaging. Il s'agit d'un service gratuit fourni par Google qui permet d'expédier des notifications aux téléphones, qu'il s'agisse d'Android ou d'iOS.

Pour les paiements en Mobile Money, nous avons intégré la passerelle GeniusPay, qui couvre les quatre opérateurs ivoiriens — Orange Money, MTN Moov Money, Moov Africa et Wave. GeniusPay se charge de toute la complexité technique de la transaction (redirection de l'utilisateur, dialogue avec l'opérateur, confirmation finale) ; notre application n'a qu'à initier la demande et à attendre la confirmation.

4.5. Architecture en couches
L'architecture retenue pour BABIFIX repose sur une organisation en trois couches. La première, la couche de présentation, regroupe ce que voit l'utilisateur, c'est-à-dire les deux applications mobiles, le site web public et le panneau d'administration. La deuxième, la couche applicative, gère la logique métier : elle reçoit les demandes, vérifie les droits, applique les règles de gestion et prépare les réponses. La troisième, la couche de données, est constituée de la base PostgreSQL qui conserve toutes les informations de manière durable. Cette séparation rend le système plus facile à entretenir et à faire évoluer.

4.6. Récapitulatif des choix techniques
Le tableau suivant récapitule les choix retenus pour chaque composant de la plateforme.

Tableau 9 — Justification des choix techniques

Composant	Outil retenu	Justification
Base de données	PostgreSQL (production), SQLite (développement)	PostgreSQL est libre, robuste et largement utilisé en entreprise ; SQLite est plus léger pour la phase de développement.
Serveur d'application	Django + Django Channels	Django offre nativement la gestion des données, l'authentification et un panneau d'administration ; Django Channels permet la messagerie en temps réel.
Langage côté serveur	Python	Langage clair, lisible, dispose d'une grande communauté et d'une documentation abondante.
Applications mobiles	Flutter (langage Dart)	Une seule base de code produit à la fois l'application Android et l'application iOS, ce qui réduit le temps de développement de moitié.
Notifications	Firebase Cloud Messaging	Service gratuit et fiable de Google, compatible Android et iOS, intégration simple.
Paiement Mobile Money	GeniusPay	Passerelle ivoirienne couvrant les quatre opérateurs du pays (Orange Money, MTN Moov Money, Moov Africa, Wave).
Site web public et panneau d'administration	Django (HTML, CSS, JavaScript)	Cohérence avec la pile serveur ; rendu côté serveur favorable au référencement du site vitrine.
Modélisation	UML	Standard international enseigné en informatique, lisible par tout professionnel du domaine.
CHAPITRE V : RÉALISATION
Dans ce chapitre, nous présentons la solution réalisée à travers ses principales interfaces.

5.1. Connexion à la plateforme
Pour utiliser BABIFIX, il faut disposer d'un compte utilisateur. Un compte est constitué d'une adresse électronique (ou d'un nom d'utilisateur) associée à un mot de passe personnel. Chaque compte est rattaché à un rôle — client, prestataire ou administrateur — qui détermine les fonctionnalités auxquelles l'utilisateur a accès.

Le client peut également se connecter avec son compte Google ou son compte Apple, ce qui lui évite d'avoir à mémoriser un nouveau mot de passe. Une fois inscrit, il reçoit un courriel contenant un lien de vérification ; il doit cliquer sur ce lien avant de pouvoir effectuer ses premières réservations. En cas d'oubli, un mécanisme de réinitialisation de mot de passe par courriel est également disponible.

5.2. Au niveau du client
Une fois connecté, le client accède à l'écran d'accueil de l'application mobile, présenté à la Figure 10. Cet écran propose une barre d'onglets — Accueil, Services, Actualités, Mes rendez-vous, Profil — qui permet de naviguer entre les principales sections de l'application.

[Figure 10 : Écran d'accueil de l'application client]

Pour rechercher un service, le client commence par sélectionner une catégorie (par exemple plomberie, électricité, ménage ou jardinage). L'application lui présente alors la liste des prestataires validés qui exercent dans cette catégorie, classés par proximité géographique lorsque le client autorise la localisation. Pour chaque prestataire, on affiche la photo, le nom, la spécialité, la note moyenne donnée par les autres clients et le tarif indicatif. Le client peut également ouvrir une carte interactive qui affiche tous les prestataires disponibles autour de lui sur un fond cartographique.

Le client choisit ensuite le prestataire qui lui convient et passe à l'écran de réservation (Figure 11). Sur cet écran, il décrit son besoin, ajoute si nécessaire quelques photos, indique la date, l'heure souhaitée et l'adresse de l'intervention — qu'il peut saisir manuellement, choisir parmi ses adresses enregistrées ou indiquer en touchant directement la carte. Il valide enfin la demande.

[Figure 11 : Écran de réservation]

Une fois la réservation envoyée, le prestataire en est informé immédiatement par notification. Plutôt que de confirmer aveuglément, il étudie le besoin et transmet au client un devis détaillé précisant le diagnostic, le montant proposé en francs CFA et la date d'intervention. Le client reçoit le devis dans son application : il peut prendre le temps d'en discuter avec le prestataire par message, puis l'accepter ou le refuser. Tant que le devis n'est pas accepté, aucun engagement financier n'est pris.

Pendant toute la durée de la mission, le client peut échanger directement avec le prestataire via l'écran de chat présenté à la Figure 12. Chaque message envoyé arrive en quelques secondes grâce à la connexion temps réel, et un compteur indique les messages non lus.

[Figure 12 : Écran de chat entre client et prestataire]

Lorsque le prestataire a terminé l'intervention, il déclare la prestation achevée. La réservation passe alors en attente de validation : le client confirme que les travaux ont bien été réalisés, procède au paiement (en Mobile Money via GeniusPay, ou en espèces), puis attribue une note de un à cinq étoiles accompagnée éventuellement d'un commentaire. Cette évaluation alimente la note moyenne affichée sur le profil du prestataire et contribue à orienter les futurs clients.

Au-delà de la simple réservation, le client a accès à deux fonctionnalités complémentaires. Le programme de fidélité lui attribue des points à chaque prestation, qu'il pourra ensuite convertir en avantages. Le parrainage lui fournit un code personnel qu'il peut partager : chaque proche qui s'inscrit avec ce code et effectue sa première réservation lui rapporte un bénéfice. Une section actualités lui permet par ailleurs de suivre les annonces de la plateforme, et l'authentification biométrique (empreinte digitale ou reconnaissance faciale) lui évite, à chaque ouverture de l'application, de ressaisir son mot de passe.

5.3. Au niveau du prestataire
L'inscription du prestataire se fait également depuis une application mobile, mais le parcours est différent. Le prestataire commence par renseigner ses informations professionnelles — nom, spécialités, zone d'intervention, tarif — et téléverse une copie de sa Carte Nationale d'Identité, accompagnée d'une photo de lui tenant cette CNI à la main. L'écran d'inscription correspondant est présenté à la Figure 13.

[Figure 13 : Écran d'inscription du prestataire]

Une fois le dossier soumis, le prestataire est redirigé vers une page d'attente (Figure 14), qui lui rappelle que son dossier est en cours d'examen. Il ne peut pas encore recevoir de mission tant que la validation n'est pas effectuée.

[Figure 14 : Écran d'attente de validation]

Lorsque l'administrateur valide le dossier, le prestataire reçoit une notification et accède à son tableau de bord. Si au contraire le dossier est refusé, une page particulière lui présente clairement le motif du refus, ainsi qu'un bouton « Modifier ma demande » qui lui permet de corriger les éléments signalés et de soumettre à nouveau le dossier sans avoir à recréer un compte. Cette possibilité de resoumission après refus motivé constitue l'une des particularités de notre plateforme : elle réduit considérablement le découragement des prestataires dont le dossier serait insuffisant à la première tentative. Le prestataire est aussi invité, à ce stade, à signer électroniquement le contrat d'utilisation qui formalise les engagements de chacune des parties.

Une fois validé, le prestataire accède à un tableau de bord qui rassemble ses missions, ses messages et ses revenus. Il commence par renseigner ses créneaux de disponibilité — jours et heures auxquels il accepte d'intervenir — afin que les clients ne lui adressent que des demandes compatibles avec son emploi du temps. Il peut également déclarer ponctuellement des périodes d'indisponibilité (vacances, formation, autre engagement).

À chaque nouvelle demande, il reçoit immédiatement une notification. Plutôt que d'accepter à l'aveugle, il consulte le besoin du client, échange éventuellement quelques messages pour préciser les détails, puis rédige un devis indiquant le diagnostic, le montant proposé en francs CFA et la date d'intervention. Le client reçoit ce devis et l'accepte ou le refuse. Lorsque le devis est accepté, le prestataire passe en intervention : il démarre la mission au moment convenu, puis la déclare terminée à la fin des travaux. Le client confirme alors que la prestation a bien été réalisée, ce qui déclenche le paiement et la possibilité, pour chacun des deux, d'évaluer l'autre.

Le prestataire dispose enfin d'un portefeuille personnel qui retrace l'ensemble de ses gains. Il y consulte le détail de chaque mission, suit son solde en francs CFA et peut déclencher, lorsqu'il le souhaite, le retrait de ses gains vers son compte Mobile Money. Comme les clients, il bénéficie également du système de parrainage et reçoit régulièrement les notifications de la plateforme (nouvelles missions, messages, paiements perçus).

5.4. Au niveau de l'administrateur
L'administrateur dispose d'un panneau dédié, accessible depuis un navigateur web. Sa page d'accueil est un tableau de bord (Figure 15) qui présente, en un coup d'œil, les principaux indicateurs de la plateforme : nombre total d'utilisateurs inscrits, nombre de prestataires en attente, nombre de réservations du jour, montant total des revenus générés en francs CFA et répartition des paiements par opérateur Mobile Money.

[Figure 15 : Tableau de bord de l'administrateur]

Depuis ce panneau, l'administrateur peut valider ou refuser les dossiers prestataires en attente : il consulte les informations soumises et la pièce d'identité, puis prend sa décision. En cas de refus, il est tenu de saisir un motif clair, qui sera ensuite transmis automatiquement au prestataire concerné.

L'administrateur peut également gérer les catégories de services disponibles sur la plateforme, publier des actualités à destination des clients et des prestataires, suivre les paiements et traiter les éventuels litiges signalés par les utilisateurs. Toutes ses actions sensibles sont enregistrées dans un journal d'audit qui en garde la trace.

5.5. Site web public
Enfin, BABIFIX dispose d'un site web public, qui sert à présenter la plateforme aux visiteurs et à les inviter à télécharger l'application mobile. On y trouve une présentation des services proposés, les principales catégories, des témoignages de clients et de prestataires, une foire aux questions et un formulaire de contact. Lors de la première visite, un bandeau invite le visiteur à donner son consentement pour les cookies, conformément à la Loi ivoirienne n°2013-450 sur la protection des données à caractère personnel.

5.6. Tests et validation
Avant de considérer notre solution comme prête, nous avons effectué une série de tests permettant de valider chaque parcours utilisateur de bout en bout. Le tableau ci-dessous récapitule les principaux tests réalisés et leur résultat.

Tableau 10 — Protocoles de tests et résultats

Domaine testé	Méthode	Critère de succès	Résultat
Inscription du client	Création d'un compte complet	Compte créé, première connexion réussie	Validé
Inscription du prestataire	Soumission du dossier avec pièce d'identité	Dossier reçu, statut « en attente » affiché	Validé
Validation par l'administrateur	Acceptation depuis le panneau admin	Statut prestataire passe à « validé » et notification reçue	Validé
Refus motivé et resoumission	Refus avec motif, puis correction du dossier	Motif affiché côté prestataire, dossier renvoyé	Validé
Cycle de devis	Demande client → devis prestataire → acceptation client	Toutes les étapes franchies avec notifications	Validé
Chat temps réel	Échange entre un client et un prestataire	Messages reçus en quelques secondes	Validé
Paiement Mobile Money	Règlement d'une réservation via Mobile Money	Transaction confirmée et paiement enregistré	Validé
Paiement en espèces	Déclaration du règlement par le client puis confirmation prestataire	Paiement enregistré après confirmation	Validé
Notation bidirectionnelle	Notation du prestataire par le client et vice-versa	Notes enregistrées et affichées sur les profils	Validé
Portefeuille prestataire	Demande de retrait des gains	Solde mis à jour après retrait	Validé
Connexion à un appareil sans biométrie	Repli sur le mot de passe classique	Connexion réussie	Validé
Tableau de bord administrateur	Affichage des indicateurs en francs CFA	Données correctes et à jour	Validé
CONCLUSION
Au terme de notre projet de fin de cycle, nous avons pu concevoir et réaliser BABIFIX, une plateforme numérique de mise en relation entre des clients particuliers et des prestataires de services à domicile en Côte d'Ivoire. Le système comporte une application mobile pour le client, une application mobile pour le prestataire, un site web public et un panneau d'administration, tous reliés à un même serveur central.

Pour parvenir à ce résultat, nous avons d'abord analysé la situation actuelle des services à domicile dans le pays et identifié les insuffisances du mode de fonctionnement informel. Nous avons ensuite conçu la solution en suivant la démarche de modélisation UML enseignée à l'IIT, en produisant successivement le diagramme des cas d'utilisation, le diagramme de classes, plusieurs diagrammes de séquence, les diagrammes d'activité et les diagrammes d'état nécessaires pour décrire le cycle de vie d'une réservation et celui d'un compte prestataire. Enfin, nous avons réalisé l'application en nous appuyant sur les outils Python, Django, Flutter, PostgreSQL et Firebase, puis nous avons testé l'ensemble du parcours utilisateur.

La principale contribution de notre travail est d'avoir proposé une solution adaptée au contexte ivoirien : les paiements se font en francs CFA via les opérateurs Mobile Money les plus utilisés du pays, les prestataires sont vérifiés par un administrateur avant d'être visibles, les engagements financiers sont encadrés par un cycle de devis transparent qui protège le client comme le prestataire, et les échanges sont conservés dans un fil de discussion lié à chaque réservation. La plateforme intègre par ailleurs plusieurs mécanismes destinés à animer la communauté : un portefeuille personnel qui permet au prestataire de suivre et de retirer ses gains, une notation bidirectionnelle qui responsabilise les deux parties, un programme de fidélité et un système de parrainage qui récompensent les utilisateurs les plus engagés.

Sur le plan personnel, ce projet nous a permis de mettre en pratique de nombreuses notions abordées au cours de notre formation — analyse des besoins, modélisation UML, conception de bases de données, programmation côté serveur et côté mobile — et de découvrir les réalités d'un projet informatique mené de bout en bout.

Le tableau ci-dessous fait le bilan de la conformité de la solution réalisée vis-à-vis des objectifs initiaux du thème.

Tableau 11 — Bilan de conformité aux objectifs

Objectif fixé au démarrage	Statut
Quatre interfaces distinctes : client, prestataire, vitrine, administration	Atteint
Cycle complet de validation des prestataires (en attente, validé, refusé)	Atteint
Refus motivé du dossier prestataire avec resoumission sans recréer un compte	Atteint
Cycle de devis (demande → devis → acceptation → intervention)	Atteint
Chat lié à chaque réservation avec badge de messages non lus	Atteint
Paiement en francs CFA par Mobile Money et en espèces	Atteint
Notation bidirectionnelle après la prestation	Atteint
Portefeuille prestataire avec suivi des gains et retraits	Atteint
Gestion des disponibilités par le prestataire	Atteint
Programme de fidélité et système de parrainage	Atteint
Tableau de bord d'indicateurs pour l'administrateur	Atteint
Section actualités diffusée aux clients et prestataires	Atteint
Conformité à la Loi n°2013-450 (consentement aux cookies, gestion des données)	Atteint
Déploiement en production sur un serveur public	À finaliser
Plusieurs perspectives d'amélioration restent ouvertes pour la suite. Le déploiement sur un serveur de production accessible au public constitue l'étape immédiate. À moyen terme, l'enrichissement du moteur de recommandation, l'extension à d'autres villes ivoiriennes, puis aux pays voisins partageant le franc CFA, viendraient compléter la solution. Plus loin encore, l'intégration de techniques d'intelligence artificielle pourrait permettre de proposer automatiquement les prestataires les mieux adaptés au profil de chaque client.

RÉFÉRENCES BIBLIOGRAPHIQUES
Ouvrages
AUDIBERT L., UML 2 — De l'apprentissage à la pratique, Ellipses, Paris.
ROQUES P., UML 2 par la pratique — Études de cas et exercices corrigés, Eyrolles, Paris.
GABAY J., Merise et UML pour la modélisation des systèmes d'information, Dunod, Paris.
LUTZ M., Programmation Python, O'Reilly.
Cours
Cours de génie logiciel et modélisation UML, dispensé au Département d'Informatique de l'Institut Ivoirien de Technologie.
Cours de bases de données relationnelles, dispensé au Département d'Informatique de l'Institut Ivoirien de Technologie.
Cours de programmation web et applications mobiles, dispensé au Département d'Informatique de l'Institut Ivoirien de Technologie.
WEBOGRAPHIES
[W1] Documentation officielle de Django. https://www.djangoproject.com/ — consulté pendant toute la durée du projet.
[W2] Documentation officielle de Django Channels. https://channels.readthedocs.io/ — consulté pour la mise en place du chat temps réel.
[W3] Documentation officielle de Flutter. https://docs.flutter.dev/ — consulté pendant toute la durée du projet.
[W4] Documentation officielle de PostgreSQL. https://www.postgresql.org/docs/ — consulté pendant toute la durée du projet.
[W5] Documentation officielle de Firebase Cloud Messaging. https://firebase.google.com/docs/cloud-messaging — consulté pour l'intégration des notifications.
[W6] Documentation de PlantUML pour la modélisation UML. https://plantuml.com/ — consulté pour la production des diagrammes.
[W7] Documentation de la passerelle GeniusPay. https://pay.genius.ci/ — consulté pour l'intégration des paiements Mobile Money.
[W8] Loi ivoirienne n°2013-450 du 19 juin 2013 relative à la protection des données à caractère personnel. https://www.artci.ci — consulté pour la rédaction du chapitre sur la confidentialité.
[W9] Statistiques sur le Mobile Money en Côte d'Ivoire. https://www.sikafinance.com — consulté pour le contexte économique.
ANNEXES
Annexe 1 : Organigramme administratif de la SNDI
[Insérer ici l'organigramme officiel de la Société Nationale de Développement Informatique (SNDI)]

Annexe 2 : Captures d'écran complémentaires des interfaces
[Insérer ici les captures d'écran complémentaires de l'application : écran de paiement Mobile Money, écran d'évaluation, écran de profil, écran de gestion des actualités, etc.]
