# MÉMOIRE DE FIN DE CYCLE

**Conformité : Guide IIT — Format papier §13**
> Marges : 2,5 cm tous côtés · Police : Times New Roman 12 · Interligne : 1,5 · Numérotation à droite · La page 1 commence à l'Introduction · Pages liminaires en chiffres romains

---

## PAGE DE GARDE *(reproduire sur une page seule, centrée)*

**(LOGO — INSTITUT IVOIRIEN DE TECHNOLOGIE)**

**INSTITUT IVOIRIEN DE TECHNOLOGIE**
**DÉPARTEMENT D'INFORMATIQUE**

---

**MÉMOIRE DE FIN DE CYCLE**

Pour l'obtention du diplôme de **[Licence / BTS / DUT — préciser le diplôme exact]**

---

**TITRE :**

**Conception et réalisation d'une plateforme numérique de services à domicile avec validation administrative, messagerie temps réel et paiements en FCFA : le cas BABIFIX**

---

**PAR**
[NOM Prénom de l'auteur]

**DIRECTEUR DE MÉMOIRE**
[Nom, Prénom et titre du directeur]

**[MOIS] [ANNÉE]**

---

---

## TABLE DES MATIÈRES

**Pages liminaires**
Page de garde .. I
Dédicace .. II
Remerciements .. III
Présentation de l'IIT .. IV
Résumé .. V
Abstract .. VI
Liste des tableaux .. VIII
Liste des figures .. IX
Liste des sigles et acronymes .. X

**Introduction générale** .. 1

**Chapitre 1 — Contexte et analyse du marché** .. 10
1.1. Analyse du marché local .. 10
1.2. Les plateformes de mise en relation existantes : étude comparative et limites .. 13
1.3. Le modèle économique et la proposition de valeur de BABIFIX .. 18

**Chapitre 2 — Fondements théoriques et technologiques** .. 22
2.1. Les algorithmes de matching (géolocalisation, disponibilité, notation) .. 22
2.2. Les enjeux de la collecte et du traitement des données massives .. 25
2.3. Les impératifs de cybersécurité .. 27

**Chapitre 3 — Spécification des besoins** .. 30
3.1. Identification des acteurs .. 30
3.2. Parcours utilisateur .. 33
3.3. Besoins en gestion back-office .. 38

**Chapitre 4 — Analyse et conception** .. 42
4.1. Exigences de sécurité et de confidentialité .. 42
4.2. Exigences de performance, de scalabilité et de haute disponibilité .. 46
4.3. Ergonomie et accessibilité (mobile-first) .. 50

**Chapitre 5 — Modélisation UML** .. 54
5.1. Diagrammes des cas d'utilisation .. 54
5.2. Diagrammes de classes .. 57
5.3. Diagrammes de séquences .. 62
5.4. Diagrammes d'activité .. 70

**Chapitre 6 — Architecture technique** .. 77
6.1. Architecture logicielle et base de données .. 77
6.2. Choix technologiques et environnement de développement .. 84

**Chapitre 7 — Réalisation et implémentation** .. 92
7.1. Développement du moteur de recherche .. 92
7.2. Implémentation du module de sécurité .. 104
7.3. Présentation des interfaces utilisateurs .. 118
7.4. Modules complémentaires et fonctionnalités transversales .. 130

**Chapitre 8 — Tests, bilan et perspectives** .. 142
8.1. Protocoles de tests .. 142
8.2. Bilan du projet face aux objectifs initiaux .. 149
8.3. Perspectives d'évolution .. 155

**Conclusion générale** .. 161

**Annexes**
Annexe A — Glossaire .. 164
Annexe B — Structure du projet BABIFIX_BUILD .. 167
Annexe C — Guide d'insertion des captures d'écran .. 172
Annexe D — Répertoire des diagrammes UML .. 175

**Références bibliographiques** .. 179

---
---

## DÉDICACE *(Page I)*

*À mes parents,*
*dont le soutien indéfectible et les sacrifices consentis tout au long de mon parcours ont rendu possible l'aboutissement de ce travail.*

*À mes frères et sœurs,*
*pour leur présence, leurs encouragements et leur foi en mes capacités.*

*À tous ceux qui croient que la technologie peut être un levier de transformation sociale en Afrique,*
*et que des solutions numériques pensées localement peuvent répondre aux défis de nos communautés.*

*Ce mémoire vous est dédié.*

---
---

## REMERCIEMENTS *(Page II)*

La réalisation de ce mémoire de fin de cycle n'aurait pas été possible sans le concours de nombreuses personnes à qui je tiens à exprimer ma profonde gratitude.

Je remercie en premier lieu **[Nom du directeur de mémoire]**, mon directeur de mémoire, pour sa disponibilité, ses conseils avisés, sa rigueur scientifique et la confiance qu'il m'a accordée tout au long de ce projet.

Mes remerciements vont également à l'ensemble du corps enseignant du **Département d'Informatique de l'Institut Ivoirien de Technologie (IIT)**, dont les enseignements ont constitué le socle théorique et pratique nécessaire à la conduite de ce travail.

Je remercie l'administration de l'**IIT** pour le cadre pédagogique de qualité mis à la disposition des étudiants.

Je tiens aussi à exprimer ma reconnaissance à toutes les personnes qui ont participé aux phases de test et de validation de la plateforme BABIFIX, pour le temps qu'elles ont bien voulu consacrer et pour la pertinence de leurs retours.

À mes camarades de promotion, pour les échanges, les débats et l'émulation intellectuelle qui ont enrichi ma réflexion.

Enfin, à ma famille, pour son soutien moral et matériel sans faille, je témoigne ma profonde et sincère reconnaissance.

---
---

## PRÉSENTATION DE L'INSTITUT IVOIRIEN DE TECHNOLOGIE *(Page III)*

L'**Institut Ivoirien de Technologie (IIT)** est un établissement d'enseignement supérieur privé de Côte d'Ivoire. Depuis sa création, il s'est inscrit dans une démarche de formation de qualité orientée vers les métiers techniques et technologiques, avec pour ambition de contribuer au développement socio-économique de la Côte d'Ivoire par la formation d'ingénieurs, de techniciens supérieurs et de professionnels qualifiés.

L'IIT propose des formations dans plusieurs filières, notamment l'**Informatique**, les **Réseaux et Télécommunications**, le **Génie Civil**, la **Comptabilité** et le **Management**. Son département d'informatique, au sein duquel s'inscrit le présent mémoire, forme des étudiants aux métiers du développement logiciel, de la cybersécurité, des systèmes d'information et du génie logiciel.

Soucieux d'ancrer sa pédagogie dans la réalité professionnelle, l'IIT encourage ses étudiants à réaliser, en fin de cycle, des mémoires à forte composante pratique, témoignant de leur capacité à concevoir et à mettre en œuvre des solutions techniques répondant à des problématiques concrètes. C'est dans ce cadre que s'inscrit le présent travail consacré à la plateforme BABIFIX.

---
---

## LISTE DES TABLEAUX *(Page IV)*

| N° | Titre du tableau | Page |
|----|-----------------|------|
| Tableau 1 | Indicateurs clés du marché du Mobile Money en Côte d'Ivoire | [p.] |
| Tableau 2 | Comparatif des plateformes locales de services à domicile en Côte d'Ivoire | [p.] |
| Tableau 3 | Comparatif des plateformes africaines de services à domicile | [p.] |
| Tableau 4 | Comparatif des plateformes internationales de services à domicile | [p.] |
| Tableau 5 | Positionnement différencié de BABIFIX par rapport aux concurrents | [p.] |
| Tableau 6 | Analyse SWOT de BABIFIX | [p.] |
| Tableau 7 | Composantes fondamentales des algorithmes de matching | [p.] |
| Tableau 8 | Tableau des besoins fonctionnels (BF-01 à BF-12) | [p.] |
| Tableau 9 | Tableau des exigences non fonctionnelles | [p.] |
| Tableau 10 | Description des cas d'utilisation par acteur | [p.] |
| Tableau 11 | Description des entités du diagramme de classes | [p.] |
| Tableau 12 | Justification des choix technologiques | [p.] |
| Tableau 13 | Protocoles de tests et résultats | [p.] |
| Tableau 14 | Bilan de conformité aux objectifs du projet | [p.] |

*Note : les numéros de page seront mis à jour lors de la mise en forme finale dans Word.*

---
---

## LISTE DES FIGURES *(Page V)*

| N° | Titre de la figure | Page |
|----|-------------------|------|
| Figure 1 | Architecture logicielle globale de BABIFIX | [p.] |
| Figure 2 | Diagramme des cas d'utilisation — vue complète | [p.] |
| Figure 3 | Diagramme de classes — modèle conceptuel BABIFIX | [p.] |
| Figure 4 | Diagramme de séquence — Réservation client et paiement Mobile Money | [p.] |
| Figure 5 | Diagramme de séquence — Inscription et validation prestataire | [p.] |
| Figure 6 | Diagramme de séquence — Gestion administrative (validation/refus) | [p.] |
| Figure 7 | Diagramme de séquence — Paiement en espèces | [p.] |
| Figure 8 | Diagramme d'activité — Parcours de réservation client | [p.] |
| Figure 9 | Diagramme d'activité — Inscription et validation prestataire | [p.] |
| Figure 10 | Diagramme d'activité — Gestion administrative | [p.] |
| Figure 11 | Diagramme d'activité — Notation et avis | [p.] |
| Figure 12 | Interface Flutter — App client (liste services) | [p.] |
| Figure 13 | Interface Flutter — App prestataire (page d'attente) | [p.] |
| Figure 14 | Interface Flutter — App prestataire (page refus avec motif) | [p.] |
| Figure 15 | Interface Flutter — Chat avec badge messages non lus | [p.] |
| Figure 16 | Interface Django — Panneau admin (dashboard KPI) | [p.] |
| Figure 17 | Interface Django — Site vitrine BABIFIX | [p.] |
| Figure 18 | Interface Django — Section « Notifications intelligentes » du site vitrine | [p.] |
| Figure 19 | Interface Django — Bandeau de consentement aux cookies (RGPD) | [p.] |
| Figure 20 | Interface Flutter — Écran d'authentification avec boutons Google et Apple Sign-In | [p.] |
| Figure 21 | Interface Flutter — Écran de vérification d'adresse email post-inscription | [p.] |
| Figure 22 | Diagramme de séquence — Paiement Mobile Money (flux CinetPay détaillé) | [p.] |
| Figure 23 | Diagramme de séquence — Chat temps réel (WebSocket + FCM) | [p.] |
| Figure 24 | Diagramme de séquence — Gestion des litiges | [p.] |
| Figure 25 | Diagramme d'état — Cycle de vie d'une réservation | [p.] |
| Figure 26 | Diagramme d'état — Cycle de vie d'un prestataire | [p.] |
| Figure 27 | Diagramme de déploiement — Infrastructure de production BABIFIX | [p.] |

*Note : insérer les captures d'écran et exports SVG des diagrammes dans Word à l'emplacement indiqué.*

---
---

## SIGLES ET ABRÉVIATIONS *(Page VI)*

| Sigle / Abréviation | Signification |
|---------------------|---------------|
| API | Application Programming Interface (Interface de programmation applicative) |
| ARTCI | Autorité de Régulation des Télécommunications/TIC de Côte d'Ivoire |
| BDD | Base de données |
| CI | Côte d'Ivoire |
| CI/CD | Continuous Integration / Continuous Deployment (Intégration et déploiement continus) |
| CNI | Carte Nationale d'Identité |
| DRF | Django REST Framework |
| FCFA | Franc de la Communauté Financière Africaine |
| FCM | Firebase Cloud Messaging |
| HTTP | HyperText Transfer Protocol |
| HTTPS | HyperText Transfer Protocol Secure |
| IIT | Institut Ivoirien de Technologie |
| IoT | Internet of Things (Internet des objets) |
| JWT | JSON Web Token |
| KPI | Key Performance Indicator (Indicateur clé de performance) |
| ML | Machine Learning (Apprentissage automatique) |
| Mobile Money | Service de paiement mobile (Orange Money, MTN Moov Money, Wave) |
| MTN | Mobile Telephone Networks |
| MVP | Minimum Viable Product (Produit minimal viable) |
| MVVM | Model-View-ViewModel (patron d'architecture logicielle) |
| OAuth | Open Authorization — protocole standard d'autorisation permettant à une application tierce (Google, Apple) d'accorder un accès limité à un compte utilisateur sans partager le mot de passe |
| ORM | Object-Relational Mapping |
| OWASP | Open Web Application Security Project |
| REST | Representational State Transfer |
| RGPD | Règlement Général sur la Protection des Données (UE 2016/679) — pris par analogie avec la Loi ivoirienne n°2013-450 sur la protection des données personnelles |
| JWKS | JSON Web Key Set — ensemble de clés cryptographiques publiques exposé par Apple (appleid.apple.com/auth/keys) pour la vérification des identity tokens Sign in with Apple |
| SSO | Single Sign-On — authentification unique permettant à un utilisateur d'accéder à plusieurs services avec un seul identifiant (ex. : compte Google ou Apple)
| SDK | Software Development Kit |
| TIC | Technologies de l'Information et de la Communication |
| UI | User Interface (Interface utilisateur) |
| UEMOA | Union Économique et Monétaire Ouest-Africaine |
| UML | Unified Modeling Language (Langage de modélisation unifié) |
| UX | User Experience (Expérience utilisateur) |
| WSS | WebSocket Secure |
| HTMX | Bibliothèque JavaScript pour les interactions AJAX déclaratives via attributs HTML |
| Alpine.js | Framework JavaScript léger pour les interactions réactives côté client |
| Locust | Outil de test de charge open-source en Python |
| fl_chart | Bibliothèque Flutter de graphiques et diagrammes |
| Sentry | Plateforme de monitoring d'erreurs applicatives en temps réel |
| PostGIS | Extension spatiale de PostgreSQL pour le traitement des données géographiques |
| Nominatim | Service de géocodage OpenStreetMap |
| GoRouter | Bibliothèque de routage déclaratif pour Flutter |
| Chart.js | Bibliothèque JavaScript pour les graphiques interactifs |

---
---

## RÉSUMÉ *(Page VII)*

**Mots-clés :** plateforme numérique de services ; économie à la demande ; validation administrative ; messagerie temps réel ; paiements FCFA ; Flutter ; Django ; WebSocket ; Firebase Cloud Messaging ; authentification sociale OAuth ; protection des données personnelles ; Côte d'Ivoire ; Mobile Money.

Le secteur des services à domicile en Côte d'Ivoire est dominé par une économie informelle dans laquelle la confiance, la traçabilité et la qualité de service demeurent des enjeux majeurs. Si les plateformes numériques de mise en relation ont profondément transformé ce secteur à l'échelle internationale — avec des acteurs comme TaskRabbit, Handy ou Thumbtack —, elles ne répondent pas aux contraintes spécifiques du marché ivoirien : paiements en francs CFA (FCFA), adoption massive du Mobile Money (70 % de pénétration chez les adultes), et besoins de modération et de gouvernance adaptés au contexte local.

Ce mémoire présente la **conception et la réalisation de BABIFIX**, une plateforme numérique multi-acteurs dédiée aux services à domicile en Côte d'Ivoire. La solution comprend quatre interfaces liées : une **application mobile client** (Flutter), une **application mobile prestataire** (Flutter), un **site vitrine web** (Django) et un **panneau d'administration web** (Django). Le backend repose sur une **API REST Django** couplée à un système de **messagerie temps réel** (Django Channels / WebSocket) et de **notifications push** (Firebase Cloud Messaging).

La question de recherche centrale est : *Comment concevoir et implémenter une plateforme de services à domicile adaptée au contexte ivoirien, intégrant validation administrative, messagerie temps réel et paiements en FCFA, tout en restant maintenable et extensible ?*

L'hypothèse de travail formulée est qu'une architecture combinant authentification robuste, workflow d'approbation des prestataires (avec motif de refus et parcours de correction), messagerie liée aux réservations et notifications push améliore la confiance perçue et l'opérabilité du service.

Les résultats présentés montrent un système fonctionnel intégrant : le cycle complet de validation des prestataires, le chat lié aux réservations avec badge de messages non lus, la diffusion temps réel des prestataires approuvés, la section actualités et le tableau de bord analytique avec affichage des paiements en FCFA. La plateforme intègre également une **authentification sociale** (Google Sign-In et Sign in with Apple) avec vérification côté serveur par JWT, un système de **vérification d'email** et de réinitialisation de mot de passe, un **système d'icônes de catégories piloté par le serveur** : chaque catégorie Django stocke un champ `icone_url` retournant l'URL absolue d'un fichier SVG servi statiquement, rendu dans l'application Flutter par `SvgPicture.network()` sans aucun mapping local, ainsi qu'une section « Notifications intelligentes » et un **bandeau de consentement aux cookies** conforme au RGPD sur le site vitrine. Ce travail constitue une contribution à la documentation des architectures hybrides REST + temps réel en écosystème Django / Flutter appliquées aux marchés émergents d'Afrique de l'Ouest.

---
---

## ABSTRACT *(Page VIII)*

**Keywords:** digital services platform ; on-demand economy ; administrative validation ; real-time messaging ; FCFA payments ; Flutter ; Django ; WebSocket ; Firebase Cloud Messaging ; social authentication OAuth ; GDPR cookie consent ; Côte d'Ivoire ; Mobile Money ; West Africa.

The home services sector in Côte d'Ivoire is dominated by an informal economy in which trust, traceability, and service quality remain major challenges. While digital matching platforms have profoundly transformed this sector globally — with players such as TaskRabbit, Handy, or Thumbtack — they fail to address the specific constraints of the Ivorian market: payments in CFA Francs (FCFA), widespread Mobile Money adoption (over 70% penetration among adults), and the need for moderation and governance mechanisms adapted to the local context.

This thesis presents the **design and implementation of BABIFIX**, a multi-sided digital platform dedicated to home services in Côte d'Ivoire. The solution comprises four interconnected interfaces: a **Flutter mobile client application**, a **Flutter mobile service provider application**, a **Django-powered showcase website**, and a **Django-powered administrative dashboard**. The backend relies on a **Django REST API** coupled with a **real-time messaging system** (Django Channels / WebSocket) and **push notifications** (Firebase Cloud Messaging).

The central research question is: *How can a home services platform be designed and implemented for the Ivorian context, integrating administrative validation, real-time messaging and FCFA payments, while remaining maintainable and extensible?*

The working hypothesis states that an architecture combining robust authentication, a provider approval workflow (with refusal reason and correction path), reservation-bound messaging, and push notifications improves perceived trust and service operability.

Results demonstrate a functional system incorporating: the complete provider validation cycle, reservation-linked chat with unread message badges, real-time broadcasting of approved providers, a news section, and an analytical dashboard with FCFA payment display. The platform additionally integrates **social authentication** (Google Sign-In and Sign in with Apple) with server-side verification through JWT tokens, an **email verification** and password reset workflow, a **server-driven category icon system** where each Django category stores an `icone_url` field returning the absolute URL of a statically-served SVG file, rendered in the Flutter app via `SvgPicture.network()` without any local mapping, an "Intelligent Notifications" showcase section, and a **GDPR-compliant cookie consent banner** on the website. This work contributes to the documentation of hybrid REST + real-time architectures in the Django / Flutter ecosystem applied to West African emerging markets.

---
---

# INTRODUCTION

La révolution numérique de la dernière décennie a profondément reconfiguré la manière dont les individus accèdent aux services. L'essor des plateformes de services à la demande — popularisées à l'échelle mondiale par des modèles tels qu'Uber pour le transport, Airbnb pour l'hébergement, ou TaskRabbit pour les services à domicile — a démontré que la confiance, la transparence et la facilité de paiement constituent les piliers fondamentaux de l'économie de plateforme (Kenney et Zysman 2016). Ces modèles reposent sur une logique de mise en relation efficiente entre l'offre et la demande, soutenue par des mécanismes d'évaluation, de modération et de paiement sécurisé.

En Afrique de l'Ouest, et particulièrement en Côte d'Ivoire, cette transformation numérique s'opère dans un contexte singulier. Le secteur des services à domicile — plomberie, électricité, ménage, jardinage, cours particuliers — est structurellement dominé par l'économie informelle. Plus de 90 % des artisans et prestataires exercent sans cadre formel, ce qui génère une asymétrie d'information préjudiciable tant aux clients qu'aux prestataires eux-mêmes : absence de garantie de qualité, opacité des tarifs, impossibilité pour le client d'évaluer la fiabilité d'un intervenant avant de lui ouvrir sa porte. Parallèlement, la Côte d'Ivoire connaît une adoption massive du Mobile Money — Orange Money, MTN Moov Money, Wave — avec plus de 24 millions de comptes actifs et un volume de transactions annuelles dépassant 40 000 milliards de FCFA (SocialNetLink 2025 ; SikaFinance 2024). Cette infrastructure de paiement mobile constitue un levier considérable pour la digitalisation des échanges informels.

C'est dans cette intersection entre besoin de confiance, potentiel du Mobile Money et lacune des solutions existantes qu'émerge la problématique de ce mémoire. Les plateformes internationales telles que TaskRabbit ou Handy ne sont pas disponibles en Côte d'Ivoire et ne supportent pas les paiements en FCFA. Les solutions locales identifiées — Yako Services, OnDjossi, Gombo, Mon Artisan — ne proposent pas de système intégré alliant validation administrative, messagerie temps réel et paiements adaptés. **BABIFIX** est conçu pour combler ce vide : il s'agit d'une plateforme numérique multi-acteurs dédiée aux services à domicile, intégrant quatre interfaces liées — une application mobile client (Flutter), une application mobile prestataire (Flutter), un site vitrine web (Django) et un panneau d'administration web (Django) — autour d'un backend Django commun.

Le présent mémoire est organisé en trois parties. La **Première Partie** dresse un état de l'art de l'écosystème des services à domicile, analyse le marché ivoirien et les concurrents locaux, africains et internationaux, et identifie les défis technologiques et sécuritaires auxquels toute plateforme de mise en relation doit répondre. La **Deuxième Partie** procède à l'analyse des besoins fonctionnels et non fonctionnels de BABIFIX, décrit les parcours des trois catégories d'acteurs, et présente la modélisation UML complète du système. La **Troisième Partie** expose l'architecture logicielle retenue, les choix technologiques justifiés, la réalisation des modules clés, ainsi que les protocoles de tests, le bilan du projet et les perspectives d'évolution.

---
---

# 0.1. Méthodologie de développement

Le projet BABIFIX a été développé selon une approche itérative incrémentale, avec 8 versions successives (v1 à v8) livrées sur une période de plusieurs mois. Cette méthodologie permet de valider chaque fonctionnalité avant de passer à la suivante, tout en permettant des ajustements en fonction des retours.

### Organisation en versions

| Version | Date | Livrable principal |
|---------|------|-------------------|
| v1 | Semaine 1-2 | Modèles de données Django, API REST de base |
| v2 | Semaine 3-4 | Authentification JWT, inscription client/prestataire |
| v3 | Semaine 5-6 | Workflow validation prestataire (PENDING → ACCEPTED/REFUSED) |
| v4 | Semaine 7-8 | Chat temps réel lié aux réservations (Django Channels) |
| v5 | Semaine 9-10 | Tableau de bord admin avec KPI en FCFA |
| v6 | Semaine 11-12 | Push notifications FCM, section Actualités |
| v7 | Semaine 13-14 | Authentification sociale (Google, Apple), vérification email |
| v8 | Semaine 15-16 | Site vitrine Django avec thème premium, animations, cookies RGPD |

### Outils de modélisation

La modélisation UML a été réalisée avec **PlantUML** pour sa syntaxe textuelle permettant un versionnement efficace via Git. Les diagrammes ont été exportés au format SVG pour une intégration optimale dans le mémoire.

### Cadre de validation

La validation des fonctionnalités a été effectuée selon trois axes :
- **Tests fonctionnels manuels** : parcours utilisateur complet sur chaque interface
- **Tests d'intégration** : vérification des interactions API REST + WebSocket
- **Tests de performance** : outils de charge Locust pour simuler plusieurs utilisateurs simultanés

Cette approche itérative a permis d'atteindre un niveau de maturité élevé sur les fonctionnalités critiques tout en identifiant les axes d'amélioration pour les versions futures.

### Chronogramme du projet

Le tableau suivant présente le planning détaillé du projet BABIFIX sur 16 semaines :

**Tableau 0.1 — Chronogramme de développement BABIFIX**

| Phase | Semaine | Activités | Livrables |
|-------|---------|-----------|-----------|
| **Phase 1 : Fondations** | S1-S2 | Analyse des besoins, modélisation UML, configuration Django, modèles de données | Modèles Django, diagrammes UML |
| | S3-S4 | Authentification JWT, inscription client/prestataire, API REST de base | API auth, endpoints inscription |
| **Phase 2 : Cœur métier** | S5-S6 | Workflow validation prestataire, modèles PENDING/ACCEPTED/REFUSED | Validation admin, notifications |
| | S7-S8 | Chat temps réel (Django Channels), WebSocket, badge messages | Chat lié aux réservations |
| **Phase 3 : Administration** | S9-S10 | Tableau de bord KPI admin, graphiques Chart.js, export CSV | Dashboard admin en FCFA |
| | S11-12 | Push notifications FCM, section Actualités, journal d'audit | Notifications, Actualités |
| **Phase 4 : Extensions** | S13-14 | Authentification sociale (Google, Apple), vérification email, biométrie | OAuth, email |
| | S15-16 | Site vitrine premium, animations CSS, cookies RGPD, tests charge | Vitrine, Locust |
| **Bilan** | - | Tests fonctionnels, documentation, préparation soutenance | Mémoire + démo |

### Budget estimatif

Le tableau suivant présente une estimation des coûts pour le déploiement en production :

**Tableau 0.2 — Budget estimatif (en FCFA)**

| Poste | Coût estimatif | Notes |
|-------|----------|-------|
| Serveur VPS (1 an) | 300 000 - 600 000 | DigitalOcean, OVH, ou Alibaba Cloud |
| Nom de domaine babifix.ci | 15 000 | .ci registry |
| Certificat SSL (Let's Encrypt) | 0 | Gratuit |
| Instance PostgreSQL managé | 100 000 - 200 000 | DigitalOcean Managed DB |
| Instance Redis | 50 000 - 100 000 | Managed Redis |
| Licence Apple Developer (1 an) | 80 000 | 99 USD |
| Compte Google Play | 25 000 | 25 USD (unique) |
| Intégration passerelle paiement | Selon opérateur | CinetPay ou équivalent |
| **Total estimatif** | **570 000 - 1 100 000** | Sans frais de fonctionnement |

---

# PREMIÈRE PARTIE : ÉTAT DE L'ART ET CADRAGE DU PROJET

---

# CHAPITRE 1 : L'ÉCOSYSTÈME DES SERVICES À DOMICILE ET L'ÉCONOMIE DE PLATEFORME NUMÉRIQUE

## 1.1. Analyse du marché local

### 1.1.1. Le secteur des services à domicile en Côte d'Ivoire

La Côte d'Ivoire est la première économie de l'Union Économique et Monétaire Ouest-Africaine (UEMOA), avec un taux de croissance du produit intérieur brut oscillant entre 6 et 7 % ces dernières années. Sa population, estimée à 29 millions d'habitants, est majoritairement jeune et concentrée dans les zones urbaines, notamment dans la métropole économique d'Abidjan qui regroupe plus de 5 millions de personnes. Cette urbanisation accélérée a généré une demande croissante en services à domicile : entretien du bâtiment, dépannage électrique et plomberie, ménage, cuisine à domicile, garde d'enfants, soutien scolaire, jardinage.

Le secteur des services à domicile se caractérise en Côte d'Ivoire par une très forte fragmentation et une prédominance de l'informalité. La grande majorité des artisans et des prestataires de services opèrent sans statut juridique formalisé, sans contrat de travail défini et sans dispositif de contrôle de la qualité des prestations. Les clients recourent principalement au bouche-à-oreille, aux annonces dans les quartiers ou aux recommandations sur les réseaux sociaux pour trouver un prestataire. Ce mode de fonctionnement, s'il présente l'avantage de la proximité, engendre de nombreuses difficultés : impossibilité de vérifier les références d'un intervenant, absence de recours en cas de prestation défaillante, risques sécuritaires liés à l'accueil de personnes non identifiées au domicile.

### 1.1.2. Le poids de l'économie informelle et ses implications

L'économie informelle représente, selon les estimations de la Banque Mondiale, entre 40 et 60 % du PIB des pays d'Afrique subsaharienne et emploie plus de 80 % de la population active dans certains secteurs (Banque mondiale 2019). En Côte d'Ivoire, le secteur informel des services à la personne concentre des centaines de milliers d'acteurs : plombiers, électriciens, peintres, couturiers, cuisiniers, agents de ménage. Ces travailleurs font face à un triple défi : la visibilité (comment se faire connaître au-delà du cercle de proximité), la confiance (comment rassurer des clients potentiels sur leur sérieux), et la rémunération (comment recevoir des paiements de manière sécurisée et traçable).

Du côté des clients, les principaux freins à l'utilisation de prestataires informels sont la méfiance (liée à l'absence de vérification d'identité ou de compétences), la difficulté à comparer les offres et les tarifs, et l'incertitude sur la qualité du service rendu. Ces obstacles constituent précisément les points d'entrée d'une plateforme numérique de mise en relation, à condition qu'elle intègre des mécanismes explicites de modération et de garantie.

### 1.1.3. Le Mobile Money comme catalyseur de plateformes digitales

L'un des atouts distinctifs du marché ivoirien réside dans sa maturité en matière de paiement mobile. La Côte d'Ivoire figure parmi les pays africains les plus avancés dans l'adoption du Mobile Money. Selon les données récentes, plus de **70 % de la population adulte** utilise au moins un service de paiement mobile, et le pays recense **24 millions de comptes actifs** de Mobile Money. Le volume des transactions annuelles dépasse **40 000 milliards de FCFA**, pour un revenu cumulé des trois opérateurs principaux (Orange, MTN, Moov) de 24,5 milliards de FCFA (SikaFinance 2024). L'inclusion financière totale — intégrant le Mobile Money — atteint **82 %** de la population, alors que le taux de bancarisation stricto sensu ne dépasse pas 26 % (Banque mondiale ; Agence Ecofin 2023).

**Tableau 1 — Indicateurs clés du marché du Mobile Money en Côte d'Ivoire**

| Indicateur | Valeur | Source |
|---|---|---|
| Taux de pénétration Mobile Money (adultes) | > 70 % | SocialNetLink 2025 |
| Nombre de comptes actifs | 24 millions | SocialNetLink 2025 |
| Volume transactions annuelles | > 40 000 mds FCFA | SikaFinance 2024 |
| Revenu cumulé (Orange, MTN, Moov) | 24,5 mds FCFA | SikaFinance 2024 |
| Taux d'inclusion financière totale | 82 % | Banque mondiale / Agence Ecofin |
| Taux de bancarisation stricto sensu | 26 % | Banque mondiale |

Ce contexte est fondamental pour comprendre l'opportunité que représente BABIFIX : dans un marché où la grande majorité des actifs n'ont pas de compte bancaire mais utilisent le Mobile Money au quotidien, toute plateforme numérique de services doit impérativement intégrer les paiements Orange Money, MTN Moov Money et Wave pour être viable. C'est l'un des éléments différenciateurs majeurs de BABIFIX par rapport aux solutions internationales qui ne supportent que les cartes bancaires.

---

## 1.2. Les plateformes de mise en relation existantes : étude comparative et limites

### 1.2.1. Les plateformes locales en Côte d'Ivoire

L'analyse des solutions existantes sur le marché ivoirien révèle plusieurs initiatives méritant d'être recensées, mais également plusieurs lacunes structurelles qui justifient le développement de BABIFIX.

**Yako Services** (yakoservices.com) est une plateforme proposant des services de ménage, d'installation électrique et de plomberie. Son modèle de mise en relation repose sur le contact direct par WhatsApp, sans système de réservation intégré, sans modération administrative des prestataires et sans paiement numérique intégré. La simplicité du dispositif en est à la fois la force — accessibilité immédiate — et la faiblesse : l'absence de vérification des prestataires expose les clients à des risques de qualité et de sécurité.

**OnDjossi** (ondjossi.com) se concentre sur la cuisine à domicile, offrant des repas préparés selon les goûts et préférences des clients. Bien que répondant à un besoin réel, la plateforme est très limitée en termes de catégories de services et ne dispose pas de fonctionnalités de messagerie ni de paiement intégré.

**Home Services Côte d'Ivoire** (homeservices-ci.com) constitue un effort de mise en relation plus structuré, exigeant des prestataires qu'ils s'inscrivent avec leurs coordonnées réelles et décrivent leurs services. Toutefois, aucun mécanisme de modération administrative avancée ni système de paiement intégré n'est documenté.

**Gombo**, plateforme lancée en 2021 par une startup ivoirienne basée à Abidjan, connecte clients et professionnels dans les domaines du soutien scolaire, de l'électricité, de la garde d'enfants et du coaching sportif. Elle dispose d'une présence web et mobile. Cependant, la plateforme ne dispose pas d'un système de validation administrative documenté des prestataires, et l'intégration des paiements Mobile Money n'est pas clairement établie (WeAreTech Africa 2021).

**Mon Artisan** se distingue par une démarche qualité notable : la plateforme teste et forme des centaines de prestataires avant de les référencer, dans les domaines de la plomberie, de la menuiserie et de l'électricité. Cette approche préfigure les mécanismes de validation que BABIFIX met en œuvre de manière numérique et systématique (Agence Ecofin 2022).

**IvoireFreelance**, **Izylance** et **Farnay** sont des plateformes généralistes de mise en relation de freelances qui, si elles couvrent partiellement le marché des services à la personne, ne sont pas spécialisées dans les services à domicile et ne proposent pas les fonctionnalités spécifiques attendues.

**Tableau 2 — Comparatif des plateformes locales de services à domicile en Côte d'Ivoire**

| Plateforme | Services | Validation prestataire | Chat intégré | Paiement numérique | Limites |
|---|---|---|---|---|---|
| Yako Services | Ménage, électricité, plomberie | Non | Non | Non | Pas de modération ni traçabilité |
| OnDjossi | Cuisine à domicile | Non | Non | Non | Très limité en catégories |
| Home Services CI | Généraliste | Partielle | Non | Non | Pas de modération avancée |
| Gombo | Multi-services | Non documenté | Non documenté | Non documenté | Pas de validation admin documentée |
| Mon Artisan | Plomberie, menuiserie, électricité | Oui (formation + test) | Non documenté | Non documenté | Fonctionnalités peu publiques |
| IvoireFreelance | Freelance généraliste | Non | Non | Non | Hors scope services à domicile |
| Izylance | Freelance généraliste | Non | Non | Non | Peu spécialisé |
| Farnay | Talents digitaux | Non | Non | Non | Hors scope services à domicile |
| **BABIFIX** | **Multi-services** | **Oui (admin + motif refus)** | **Oui (lié réservations)** | **Oui (FCFA + Mobile Money)** | **Déploiement prod à finaliser** |

### 1.2.2. Les plateformes africaines

Au-delà de la Côte d'Ivoire, plusieurs initiatives africaines méritent d'être analysées pour saisir les modèles en émergence sur le continent.

**Lynk** (Kenya, créé en 2015) est probablement le modèle le plus abouti en Afrique subsaharienne pour la formalisation du secteur informel des services. La plateforme connecte des travailleurs informels — électriciens, tailleurs, cuisiniers — avec des ménages et des entreprises via un système de mise en relation numérique. En février 2019, Lynk avait traité plus de 22 961 missions et transféré plus de 2,5 millions de dollars à plus de 1 300 travailleurs informels (The Conversation 2020). Le modèle de Lynk démontre la viabilité économique d'une telle plateforme en Afrique — mais n'est pas disponible en Côte d'Ivoire.

**SweepSouth** (Afrique du Sud) est spécialisé dans les services ménagers et le jardinage. La plateforme offre une flexibilité de revenus aux prestataires informels mais n'opère pas en Afrique de l'Ouest.

**Jumia Services** constitue une extension de l'écosystème Jumia vers les services, mais sa généralité limite son efficacité pour les services à domicile nécessitant une relation de confiance personnalisée.

**Tableau 3 — Comparatif des plateformes africaines de services à domicile**

| Plateforme | Pays | Modèle économique | Disponible en CI | Enseignements pour BABIFIX |
|---|---|---|---|---|
| Lynk | Kenya (2015) | Commission sur service | Non | Validation informelle viable, impact social démontré |
| SweepSouth | Afrique du Sud | Commission flexible | Non | Modèle ménage/jardinage réplicable |
| Jumia Services | Pan-africain | Commission e-commerce | Partiel | Généraliste, peu adapté au domicile |
| Kandua | Afrique du Sud | Marketplace services | Non | Spécialisation pertinente, hors zone UEMOA |

### 1.2.3. Les plateformes internationales

**TaskRabbit** (États-Unis) est la référence mondiale des services à domicile à la demande, avec une commission de 15 % prélevée sur le client, un système de profil transparent et une notation des prestataires. Non disponible en Afrique, pas de support FCFA.

**Thumbtack** (États-Unis) adopte un modèle de génération de leads (2 à 75 dollars par contact). Non adapté au contexte ivoirien où la majorité des prestataires ne dispose pas de carte bancaire.

**Handy** (États-Unis) propose un modèle de services entièrement gérés : la plateforme contrôle l'expérience de la réservation à la facturation. Modèle difficile à adapter à un marché où les prestataires opèrent de manière très autonome.

**Bark.com** (Royaume-Uni, 2015) couvre plus de 10 pays avec 7 millions d'utilisateurs enregistrés. Modèle lead-gen, paiements non adaptés à la zone FCFA/UEMOA.

**Amazon Home Services** (États-Unis) se distingue par des vérifications renforcées des prestataires (antécédents, licences, assurances) et une garantie de satisfaction. Inspirant pour BABIFIX, mais non disponible en Côte d'Ivoire.

**Tableau 4 — Comparatif des plateformes internationales de services à domicile**

| Plateforme | Pays | Modèle économique | Validation prestataire | Paiement FCFA | Disponible en CI |
|---|---|---|---|---|---|
| TaskRabbit | USA | 15% commission client | Vérification identité | Non | Non |
| Thumbtack | USA | Lead-gen ($2-75/devis) | Partielle | Non | Non |
| Handy | USA | Services gérés | Oui | Non | Non |
| Bark.com | UK | Lead-gen | Partielle | Non | Non |
| Amazon Home Services | USA | Commission + garantie | Vérification renforcée | Non | Non |

### 1.2.4. Synthèse : les freins liés à la confiance et le positionnement de BABIFIX

L'analyse comparative révèle que les lacunes des solutions existantes gravitent autour de trois axes : la **confiance** (absence de validation des prestataires), la **communication** (absence de messagerie temps réel intégrée) et la **localisation des paiements** (incompatibilité avec le FCFA et le Mobile Money). BABIFIX répond précisément à ces trois axes.

**Tableau 5 — Positionnement différencié de BABIFIX par rapport aux concurrents**

| Critère | Concurrents locaux | Concurrents africains | Concurrents internationaux | BABIFIX |
|---|---|---|---|---|
| Validation admin prestataire | Rare / partielle | Partielle | Oui | **Oui + motif de refus explicite** |
| Chat lié aux réservations | Non | Non documenté | Non (messagerie séparée) | **Oui + badge non-lus** |
| Paiement FCFA + Mobile Money | Non | Partiel | Non | **Oui (Orange, MTN, Moov, Wave)** |
| Broadcast temps réel | Non | Non | Non | **Oui (WebSocket)** |
| Section Actualités | Non | Non | Non | **Oui** |
| Dashboard admin KPI | Non | Non | Non public | **Oui** |
| App mobile native Flutter | Rare | Oui | Oui | **Oui (iOS/Android)** |
| Site vitrine + admin web Django | Non | Non | Oui | **Oui** |

---

## 1.3. Le modèle économique et la proposition de valeur de BABIFIX

### 1.3.1. Le modèle économique

BABIFIX s'appuie sur un modèle économique mixte :

- **Commission sur transactions** : un pourcentage prélevé sur chaque réservation complétée, alignant les intérêts de la plateforme et des prestataires.
- **Abonnement prestataire premium** (perspective) : formule d'abonnement mensuel pour des fonctionnalités avancées — mise en avant dans les résultats de recherche, statistiques détaillées, badge de certification.
- **Publicité et mise en avant** (perspective) : slots sponsorisés pour des catégories ou des prestataires souhaitant augmenter leur visibilité.

### 1.3.2. La proposition de valeur différenciante

La proposition de valeur repose sur trois piliers :

**1. La gouvernance et la confiance** : tout prestataire soumet sa CNI lors de l'inscription. L'administrateur valide ou refuse avec un motif explicite. Le prestataire peut corriger et resoummettre sans recréer de compte. Ce workflow en trois états — *en attente*, *accepté*, *refusé avec motif* — est le cœur de la différenciation de BABIFIX.

**2. La communication contextuelle** : le système de messagerie temps réel est directement lié aux réservations. Chaque conversation est associée à une mission spécifique. Un badge de messages non lus informe l'utilisateur instantanément.

**3. La contextualisation locale** : montants en FCFA, logos opérateurs Mobile Money, couleurs identitaires Côte d'Ivoire (orange, vert, bleu), section Actualités pour diffuser des informations à la communauté.

### 1.3.3. Analyse SWOT de BABIFIX

**Tableau 6 — Analyse SWOT de BABIFIX**

| | **Facteurs positifs** | **Facteurs négatifs** |
|---|---|---|
| **Internes** | **FORCES :** Validation admin unique sur le marché local ; chat lié aux réservations ; paiements FCFA natifs ; architecture solide (Django + Flutter) ; 4 interfaces cohérentes | **FAIBLESSES :** Phase prototype (tests auto à renforcer) ; déploiement production à finaliser ; masse critique d'utilisateurs à constituer |
| **Externes** | **OPPORTUNITÉS :** Marché sous-digitalisé ; 70 %+ pénétration Mobile Money ; croissance économique soutenue ; absence de concurrent dominant local | **MENACES :** Entrée potentielle de Lynk/SweepSouth ; plateformes internationales évoluant vers l'Afrique ; résistance culturelle à la formalisation |

---

# CHAPITRE 2 : LES DÉFIS TECHNOLOGIQUES ET SÉCURITAIRES DE LA MISE EN RELATION

## 2.1. Les algorithmes de matching (géolocalisation, disponibilité, notation)

### 2.1.1. Principes généraux des algorithmes de matching

Dans une plateforme de services à la demande, le matching — l'association d'un client avec le prestataire le plus approprié — est la fonction technique centrale dont dépend la qualité de l'expérience utilisateur et la viabilité économique de la plateforme (JungleWorks 2021). Un algorithme efficace minimise le temps d'attente du client, maximise le taux d'utilisation des prestataires et réduit les annulations.

Deux grands modèles coexistent :

- **Le modèle Supplier Pick** (Uber, Lyft, Bolt) : la plateforme sélectionne automatiquement le prestataire optimal et lui envoie la demande. Optimal pour les services urgents.
- **Le modèle Buyer Pick** (Thumbtack, Bark.com) : la plateforme présente une liste filtrée de prestataires et le client choisit. Favorise la personnalisation.

BABIFIX combine les deux : le client parcourt une liste filtrée (Buyer Pick) et initie une réservation directe (approche simplifiée du Supplier Pick).

### 2.1.2. Géolocalisation et disponibilité

La géolocalisation est le premier filtre de pertinence : un prestataire distant de 30 km n'est pas une correspondance utile. Les plateformes sophistiquées définissent des zones de service géolocalisées (geo-fencing) pour chaque prestataire.

L'algorithme d'Uber — cité comme référence technique — traite jusqu'à **1 million de requêtes par seconde** via un algorithme de correspondance sur graphe bipartite optimisé par des variantes de l'algorithme hongrois (GeeksforGeeks 2024). Les paramètres intégrés sont : l'ETA (Estimated Time of Arrival), la notation, les conditions de trafic et l'historique d'interactions.

Dans BABIFIX, le filtrage actuel s'opère par **catégorie de service** et par **notation moyenne**. L'intégration de la géolocalisation précise est prévue en perspective d'évolution.

### 2.1.3. Systèmes de notation et filtrage par qualité

Les systèmes de notation remplissent deux fonctions : réduire l'asymétrie d'information pour les clients et inciter les prestataires à maintenir un niveau de service élevé. Les algorithmes sophistiqués évitent d'envoyer des demandes à des prestataires notés sous 3/5 par un client spécifique, créant des filtres personnalisés basés sur l'historique (JungleWorks 2021).

Dans BABIFIX, après chaque prestation, le client peut noter le prestataire (note + commentaire). La note moyenne est affichée sur le profil et utilisée comme critère de tri dans les résultats de recherche.

**Tableau 7 — Composantes fondamentales des algorithmes de matching dans les plateformes de services**

| Composante | Description | Implémentation BABIFIX |
|------------|-------------|----------------------|
| Filtrage par catégorie | Association prestataire ↔ catégorie | `Provider.category` FK → `GET /api/client/prestataires?category=X` |
| Tri par notation | Note moyenne comme critère de classement | `queryset.order_by('-average_rating')` |
| Filtrage par disponibilité | Exclusion des prestataires indisponibles | `Provider.disponible = True` + `PrestataireAvailabilitySlot` |
| Filtrage géographique | Proximité prestataire ↔ client | `ProvidersMapScreen` avec rayon configurable (perspective : PostGIS) |
| Filtrage par statut | Seuls les prestataires validés sont visibles | `Provider.is_approved = True` |

---

## 2.2. Les enjeux de la collecte et du traitement des données massives

### 2.2.1. Volume de données dans les plateformes de services à la demande

Les plateformes de services génèrent des volumes importants de données hétérogènes : logs applicatifs, historiques de réservation, données de géolocalisation, messages, évaluations, notifications, transactions. À l'échelle de l'Afrique de l'Ouest — plus de 400 millions de consommateurs, consommation des ménages projetée à 2 500 milliards de dollars d'ici 2030 (McKinsey, cité dans BigMédia BpiFrance 2023) — une plateforme atteignant même une fraction de ce potentiel générerait des millions de transactions.

### 2.2.2. Architectures Big Data adaptées

Pour anticiper la montée en charge, les architectures modernes s'appuient sur :

- **Apache Kafka** : streaming d'événements en temps réel (réservations, messages, transactions), consommables de manière asynchrone par plusieurs services.
- **Elasticsearch** : recherche full-text et géographique sur grands volumes, remplaçant les requêtes SQL complexes.
- **Redis** : mise en cache des données fréquentes (listes de prestataires validés, compteurs de messages non lus) et broker des groupes WebSocket (Django Channels).
- **Dashboards analytiques** (Kibana, Grafana) : suivi des KPI en temps réel.

### 2.2.3. Anticipation de la montée en charge pour BABIFIX

La migration vers un environnement de production implique :

- **PostgreSQL** en remplacement de SQLite pour les performances en écriture concurrente et les fonctionnalités avancées.
- **Redis** comme broker Django Channels et couche de cache.
- **Pagination serveur** sur tous les endpoints de liste.
- **Monitoring applicatif** : Sentry (erreurs) et outils de métriques (performances).

---

## 2.3. Les impératifs de cybersécurité

### 2.3.1. Protection des données personnelles et cadre légal ivoirien

La collecte et le traitement de données personnelles dans une plateforme de services à domicile soulèvent des enjeux juridiques importants. En Côte d'Ivoire, le cadre légal applicable est la **Loi n°2013-450 du 19 juin 2013 relative à la protection des données à caractère personnel**, supervisée par l'**ARTCI**. Cette loi impose : finalité déterminée de la collecte, proportionnalité des données collectées, droit d'accès et de rectification, sécurisation des données.

Pour BABIFIX, les données personnelles traitées comprennent : nom, prénom, numéro de téléphone, email, photographie, CNI (prestataires), historique des réservations, messages, et données de localisation. Une politique de confidentialité transparente et une déclaration auprès de l'ARTCI sont nécessaires avant le déploiement commercial.

### 2.3.2. Vérification d'identité des prestataires

La vérification d'identité des prestataires est le mécanisme de sécurité le plus visible par les utilisateurs. Des acteurs comme Amazon Home Services exigent des prestataires une vérification d'antécédents, une licence professionnelle et une assurance (Amazon Sellers Lawyer 2024). BABIFIX adopte une approche proportionnée au contexte ivoirien : soumission de la CNI lors de l'inscription, vérification manuelle par l'administrateur, validation ou refus motivé, possibilité de resoumission sans recréation de compte.

### 2.3.3. Sécurisation des transactions et des communications

La sécurisation des échanges repose sur plusieurs mécanismes :

- **HTTPS** : toutes les communications REST sont chiffrées en transit (prévention des attaques man-in-the-middle).
- **WSS** (WebSocket Secure) : la messagerie temps réel est déployée sur TLS, garantissant la confidentialité des messages.
- **JWT** (JSON Web Tokens) : authentification stateless avec durée de vie limitée et mécanisme de rafraîchissement, compatible avec une montée en charge horizontale.
- **Permissions DRF granulaires** : `IsAuthenticated`, `IsAdminUser`, `IsPrestataire` — chaque endpoint n'est accessible qu'aux rôles autorisés.
- **CSRF** : protection intégrée pour les interfaces web Django.
- **Sanitisation des inputs** : validation par les serializers DRF à chaque point d'entrée.
- **OWASP Mobile Top 10** : référence pour les évolutions sécuritaires de l'application Flutter — protection contre le stockage non sécurisé, l'injection de code et les communications non chiffrées.

---

*[Fin de la Première Partie]*

---
---

# DEUXIÈME PARTIE : ANALYSE DES BESOINS ET SPÉCIFICATIONS

---

# CHAPITRE 3 : RECUEIL ET ANALYSE DES BESOINS FONCTIONNELS

## 3.1. Identification des acteurs

### 3.1.1. Le client particulier

Le **client particulier** est toute personne physique résidant en Côte d'Ivoire et souhaitant accéder à des services à domicile via la plateforme BABIFIX. Il utilise l'**application mobile Flutter** dédiée (app client). Ses droits et responsabilités sur la plateforme sont les suivants :

- **Inscription et connexion** : le client crée un compte avec ses coordonnées (nom, prénom, téléphone, email, mot de passe). Son compte est immédiatement actif, sans validation administrative préalable.
- **Recherche de services** : le client peut parcourir les catégories de services disponibles, consulter les profils des prestataires validés (photo, description, spécialités, note moyenne, avis), et filtrer les résultats.
- **Réservation** : le client sélectionne un prestataire, choisit une date et un créneau horaire, et soumet une demande de réservation. Il peut préciser des instructions particulières pour la mission.
- **Paiement** : le paiement s'effectue en FCFA via les opérateurs de Mobile Money intégrés (Orange Money, MTN Moov, Wave) ou en espèces selon les modalités définies.
- **Communication** : le client peut échanger des messages avec le prestataire via le chat intégré, directement lié à la réservation concernée.
- **Évaluation** : à l'issue de la prestation, le client peut noter le prestataire (de 1 à 5 étoiles) et laisser un commentaire.
- **Actualités** : le client a accès à la section Actualités de la plateforme.

### 3.1.2. Le prestataire de service

Le **prestataire** est un artisan, technicien ou professionnel des services à la personne souhaitant proposer ses services via BABIFIX. Il utilise l'**application mobile Flutter** dédiée (app prestataire). Son parcours sur la plateforme se distingue par un processus de validation obligatoire :

- **Inscription et soumission du dossier** : le prestataire renseigne ses informations professionnelles (nom, spécialités, description, zone d'intervention, tarifs) et soumet sa Carte Nationale d'Identité (CNI) en pièce jointe. Son compte passe alors au statut *en attente de validation*.
- **Attente de validation** : le prestataire accède à une page d'attente informative lui indiquant que son profil est en cours d'examen. Il ne peut pas encore recevoir de missions.
- **Acceptation** : si l'administrateur valide son dossier, le prestataire reçoit une notification push (FCM) et peut désormais apparaître dans les résultats de recherche des clients.
- **Refus motivé** : si le dossier est refusé, le prestataire reçoit une notification avec le motif de refus explicite. Une page dédiée lui affiche ce motif et lui propose un bouton « Modifier ma demande » pour corriger les éléments signalés et resoummettre son dossier sans avoir à recréer de compte.
- **Gestion des missions** : le prestataire accepté peut consulter les demandes de réservation, gérer son agenda, communiquer avec les clients via le chat, et consulter ses revenus.
- **Actualités** : le prestataire a également accès à la section Actualités de la plateforme.

### 3.1.3. L'administrateur de plateforme

L'**administrateur** est le responsable opérationnel de la plateforme BABIFIX. Il accède à la plateforme via le **panneau d'administration web Django**. Ses attributions sont les suivantes :

- **Validation des prestataires** : examen des dossiers soumis (CNI, informations professionnelles), prise de décision d'acceptation ou de refus motivé, avec notification automatique au prestataire par FCM.
- **Gestion des catégories** : création, modification, désactivation des catégories de services disponibles sur la plateforme.
- **Supervision des réservations** : accès à la liste des réservations en cours, complétées ou annulées.
- **Gestion des litiges** : traitement des signalements émis par les clients ou les prestataires.
- **Publication d'actualités** : création et diffusion d'articles ou de messages d'information à destination des utilisateurs et des prestataires.
- **Tableau de bord KPI** : accès aux indicateurs de performance clés — nombre d'utilisateurs inscrits, nombre de prestataires validés, nombre de réservations, revenus générés en FCFA, répartition par opérateur Mobile Money.
- **Gestion des paiements** : suivi des transactions avec affichage des logos des opérateurs Mobile Money et des montants en FCFA.

---

## 3.2. Parcours utilisateur

### 3.2.1. Parcours du client

Le parcours complet du client sur BABIFIX se décompose en sept étapes :

1. **Inscription** : le client télécharge l'application Flutter, renseigne ses coordonnées et crée son compte. L'authentification est gérée par JWT.
2. **Connexion** : le client se connecte avec son email et son mot de passe. Un token JWT est généré et stocké localement pour les requêtes ultérieures.
3. **Recherche de service** : le client navigue dans les catégories (ménage, plomberie, électricité, jardinage, etc.) via l'interface `CategoryTab`. Il peut consulter les fiches prestataires via `ServiceCard`, affichant la photo, le nom, la spécialité, la note moyenne et le tarif indicatif.
4. **Sélection et réservation** : le client sélectionne un prestataire, choisit une date et un créneau, précise ses besoins et valide la demande. Une réservation est créée en base de données avec le statut *en attente*.
5. **Paiement** : le client procède au paiement via Mobile Money (Orange Money, MTN Moov, Wave) ou en espèces. Un webhook confirme la transaction pour les paiements Mobile Money.
6. **Communication et suivi** : le client peut envoyer des messages au prestataire via le chat intégré. Un badge sur l'icône Message signale les messages non lus. Des notifications push FCM informent le client des mises à jour de sa réservation.
7. **Évaluation** : après la prestation, le client note le prestataire et laisse un avis qui alimente la note moyenne affichée sur le profil public.

### 3.2.2. Parcours du prestataire

Le parcours du prestataire se distingue par la phase de validation administrative :

1. **Inscription et soumission du dossier** : le prestataire renseigne ses informations professionnelles et uploade sa CNI via l'écran `OnboardingScreen` de l'application Flutter prestataire. Son statut passe à *en attente*.
2. **Attente de validation** : le prestataire est redirigé vers l'écran `PendingScreen`, qui l'informe que son dossier est en cours d'examen. Il ne peut accéder à aucune autre fonctionnalité pendant cette phase.
3. **Notification de la décision** :
   - *En cas d'acceptation* : le prestataire reçoit une notification push FCM et est redirigé vers son tableau de bord (`RequestsScreen`). Son profil est désormais visible dans les recherches.
   - *En cas de refus* : le prestataire reçoit une notification push indiquant le motif de refus. Il accède à une page dédiée affichant le motif et proposant le bouton « Modifier ma demande ».
4. **Resoumission (cas de refus)** : le prestataire corrige les éléments signalés et resoummet son dossier sans recréer de compte. Son statut repasse à *en attente*.
5. **Gestion des missions** : le prestataire accepté reçoit des notifications pour les nouvelles demandes de réservation, peut les accepter ou les décliner, gère son agenda et consulte ses revenus via `EarningsScreen`.
6. **Communication** : le prestataire échange avec ses clients via `MessagesScreen`. Un compteur de messages non lus est visible sur l'icône de messagerie.

### 3.2.3. Parcours de l'administrateur

1. **Connexion** au panneau d'administration Django (interface web sécurisée).
2. **Tableau de bord KPI** : vue synthétique des indicateurs clés (utilisateurs inscrits, prestataires en attente / validés, réservations du jour, revenus FCFA).
3. **Validation des prestataires** : liste des dossiers en attente ; pour chaque dossier, l'admin consulte les informations soumises et la CNI, puis prend sa décision. En cas de refus, il saisit un motif qui sera transmis au prestataire par notification FCM.
4. **Gestion des catégories** : création, modification ou désactivation des catégories de services.
5. **Publication d'actualités** : rédaction et publication de news visibles par les clients et prestataires.
6. **Supervision des litiges** : traitement des signalements reçus.
7. **Statistiques** : consultation des rapports de performance de la plateforme.

---

## 3.3. Besoins en gestion back-office

### 3.3.1. Validation des profils prestataires

La validation des profils est le processus back-office le plus critique de BABIFIX. Il repose sur un workflow à trois états :

- **En attente (Pending)** : le prestataire vient de soumettre son dossier. L'admin est notifié.
- **Accepté (Accepted)** : l'admin valide le dossier. Le prestataire est notifié par FCM et son profil devient visible.
- **Refusé (Refused)** : l'admin refuse et saisit un motif explicite. Le prestataire est notifié par FCM avec le motif, et peut corriger et resoummettre.

Ce workflow garantit que seuls des prestataires vérifiés sont visibles par les clients, renforçant la confiance dans la plateforme.

### 3.3.2. Gestion des litiges

La gestion des litiges permet de traiter les désaccords entre clients et prestataires après une prestation. Un client ou un prestataire peut signaler un problème à l'administrateur via l'application. L'admin examine le signalement, peut consulter l'historique de la réservation et du chat associé, et prend une décision (remboursement partiel ou total, avertissement du prestataire, suspension).

### 3.3.3. Facturation et suivi des paiements

Le suivi des paiements est centralisé dans le panneau d'administration. Pour chaque transaction, les informations suivantes sont enregistrées : identifiant de réservation, montant en FCFA, opérateur Mobile Money utilisé (Orange Money, MTN Moov, Wave), statut de la transaction (en attente, confirmé, échoué), et date/heure.

**Tableau 8 — Tableau des besoins fonctionnels de BABIFIX (BF-01 à BF-12)**

| ID | Besoin fonctionnel | Acteur concerné | Priorité |
|---|---|---|---|
| BF-01 | Inscription et authentification sécurisée (JWT) | Client, Prestataire | Haute |
| BF-02 | Cycle prestataire : soumission → validation/refus → notification | Prestataire, Admin | Haute |
| BF-03 | Motif de refus explicite + bouton « Modifier » sans recréation de compte | Prestataire, Admin | Haute |
| BF-04 | Recherche de prestataires par catégorie, notation, disponibilité | Client | Haute |
| BF-05 | Réservation d'un service avec choix de date et créneau | Client, Prestataire | Haute |
| BF-06 | Chat lié aux réservations avec badge de messages non lus | Client, Prestataire | Haute |
| BF-07 | Paiement en FCFA via Mobile Money (Orange, MTN, Wave) | Client | Haute |
| BF-08 | Notifications push FCM pour tous les événements critiques | Client, Prestataire | Haute |
| BF-09 | Section Actualités accessible aux clients et prestataires | Admin, Client, Prestataire | Moyenne |
| BF-10 | Tableau de bord KPI pour l'administrateur | Admin | Haute |
| BF-11 | Évaluation du prestataire après prestation (note + commentaire) | Client | Moyenne |
| BF-12 | Gestion des litiges (signalement + traitement admin) | Client, Prestataire, Admin | Moyenne |

---

# CHAPITRE 4 : SPÉCIFICATIONS NON FONCTIONNELLES ET EXIGENCES TECHNIQUES

## 4.1. Exigences de sécurité et de confidentialité

### 4.1.1. Authentification et autorisation

L'authentification dans BABIFIX repose sur deux mécanismes distincts selon le type d'interface :

- **Applications Flutter (client et prestataire)** : authentification par **JSON Web Tokens (JWT)** via la bibliothèque `djangorestframework-simplejwt`. À la connexion, l'API retourne un *access token* (durée de vie courte, typiquement 5 à 30 minutes) et un *refresh token* (durée de vie longue). L'application Flutter stocke ces tokens de manière sécurisée et les inclut dans l'en-tête `Authorization: Bearer <token>` de chaque requête.
- **Interfaces web Django (panneau admin et vitrine)** : authentification par **sessions Django** avec protection CSRF native. L'accès au panneau d'administration est restreint aux utilisateurs ayant le flag `is_staff=True` ou un groupe de permissions administrateur défini.

L'autorisation est gérée au niveau de chaque endpoint API par des classes de permission Django REST Framework :
- `IsAuthenticated` : tout utilisateur connecté.
- `IsAdminUser` : réservé aux administrateurs.
- `IsPrestataire` : classe personnalisée vérifiant que l'utilisateur est un prestataire avec le statut accepté.

### 4.1.2. Chiffrement des données

Toutes les communications entre les applications clientes et le serveur Django sont chiffrées par les protocoles standards :

- **TLS/HTTPS** pour les requêtes REST.
- **WSS** (WebSocket Secure) pour les connexions temps réel Django Channels.

Les données sensibles stockées en base (mots de passe) sont hashées avec l'algorithme PBKDF2 + SHA256, implémenté nativement par Django. Les fichiers de CNI uploadés sont stockés dans un répertoire privé, non exposé publiquement, avec accès contrôlé via l'API.

### 4.1.3. Conformité réglementaire

Conformément à la **Loi n°2013-450 du 19 juin 2013** (Côte d'Ivoire) sur la protection des données personnelles, BABIFIX devra, avant son déploiement commercial :

1. Déclarer son traitement de données personnelles auprès de l'**ARTCI**.
2. Rédiger et publier une **politique de confidentialité** explicite, accessible depuis les applications.
3. Implémenter un mécanisme de **droit à l'effacement** permettant à tout utilisateur de demander la suppression de ses données.
4. Définir une **politique de rétention** des données (durée de conservation des historiques de réservation, des messages, des CNI).

---

## 4.2. Exigences de performance, de scalabilité et de haute disponibilité

### 4.2.1. Performances attendues

**Tableau 9 — Tableau des exigences non fonctionnelles**

| Exigence | Métrique | Valeur cible | Justification |
|---|---|---|---|
| Temps de réponse API REST | Latence p95 | < 200 ms | Fluidité de l'expérience mobile |
| Latence messagerie WebSocket | Délai de réception | < 100 ms | Perception du temps réel |
| Disponibilité du service | Uptime annuel | ≥ 99,5 % | Continuité de service |
| Capacité initiale | Utilisateurs concurrents | 100 | Phase de lancement |
| Taille maximale d'un fichier CNI | Upload | ≤ 5 Mo | Contrainte réseau mobile |
| Temps de chargement de la vitrine web | First Contentful Paint | < 3 s | SEO et UX |

### 4.2.2. Scalabilité

L'architecture de BABIFIX est conçue pour évoluer de manière progressive :

- **Phase 1 (lancement)** : architecture monolithique Django sur un serveur unique, SQLite remplacé par PostgreSQL, Redis pour les WebSocket.
- **Phase 2 (croissance)** : séparation des composants (API, Workers, WebSocket) en services distincts, utilisation d'un load balancer (Nginx), base de données en mode répliqué.
- **Phase 3 (échelle)** : migration vers une architecture microservices si la charge le justifie, intégration d'une couche CDN pour les assets statiques.

### 4.2.3. Haute disponibilité

Pour garantir la continuité du service :

- **Sauvegardes automatisées** de la base de données (PostgreSQL) à intervalles réguliers.
- **Monitoring applicatif** : alertes automatiques en cas d'erreur critique ou de dégradation des performances.
- **Déploiement sans interruption** (zero-downtime deployment) via des stratégies de déploiement progressif (Blue-Green ou Rolling).

---

## 4.3. Ergonomie et accessibilité (mobile-first)

### 4.3.1. Conception mobile-first

BABIFIX est fondamentalement conçu pour une utilisation sur smartphone. Le contexte ivoirien justifie pleinement cette orientation : selon les données GSMA, le téléphone mobile est le premier — et souvent le seul — point d'accès à internet pour la majorité des utilisateurs en Côte d'Ivoire. Les applications Flutter client et prestataire sont développées avec les principes **Material Design 3** (Google), qui offrent une cohérence visuelle élevée, des composants d'interface éprouvés et une adaptation automatique aux différentes tailles d'écran.

### 4.3.2. Système de design et identité visuelle

Un système de design unifié — le fichier `babifix_design_system.dart` dans les applications Flutter — définit les tokens visuels communs aux deux applications mobiles :

- **Couleurs primaires** : orange (énergie, chaleur — couleur de la Côte d'Ivoire), vert (confiance, nature) et bleu (technologie, sécurité).
- **Typographie** : police système Material adaptée à la lisibilité sur mobile.
- **Composants réutilisables** : boutons, cartes, formulaires, navigations — tous conformes aux guidelines Material 3.
- **Cohérence** : les deux applications mobiles partagent le même système de design, avec des variantes de couleur permettant de les distinguer visuellement (thème client vs. thème prestataire).

### 4.3.3. Navigation et ergonomie

- **Navigation par onglets** (BottomNav) : les fonctions principales sont accessibles en un geste depuis la barre de navigation inférieure, réduisant la charge cognitive.
- **Catégories visuelles** : les services sont présentés sous forme de tuiles avec icônes, permettant une reconnaissance rapide sans lecture approfondie.
- **Formulaires simplifiés** : les formulaires d'inscription et de réservation sont découpés en étapes progressives (onboarding multi-écrans) pour ne pas surcharger l'utilisateur.
- **Feedback immédiat** : chaque action utilisateur génère un retour visuel immédiat (indicateurs de chargement, messages de confirmation, états d'erreur explicites).

---

# CHAPITRE 5 : MODÉLISATION DU SYSTÈME (APPROCHE UML)

La modélisation UML de BABIFIX comprend dix diagrammes répartis en quatre catégories : cas d'utilisation, classes, séquences et activités. Ces diagrammes sont disponibles en format PlantUML (répertoire `UML_DIAGRAMMES/`) et en exports SVG (répertoire `DIAGRAMME/`).

## 5.1. Diagrammes des cas d'utilisation

### 5.1.1. Vue globale des interactions

*[Insérer ici la Figure 2 : CAS D'UTILISATION COMPLET.svg]*

Le diagramme des cas d'utilisation de BABIFIX (`01_use_case_diagramme.puml`) présente la vue globale des interactions entre les acteurs et le système. Il identifie trois acteurs principaux et deux acteurs externes :

**Acteurs principaux :**
- **Client** : interagit avec l'application BABIFIX App Client.
- **Prestataire** : interagit avec l'application BABIFIX Pro.
- **Admin** : interagit avec le BABIFIX Admin Panel.

**Acteurs externes :**
- **API Paiement Mobile Money** : passerelle de paiement (CinetPay ou équivalent) pour Orange Money, MTN, Wave.
- **Firebase** : infrastructure de notifications push (FCM) et d'authentification.

### 5.1.2. Description des cas d'utilisation par acteur

**Tableau 10 — Description des cas d'utilisation par acteur**

| Acteur | Cas d'utilisation |
|---|---|
| **Client** (13 CU) | S'inscrire, Se connecter, Parcourir les catégories, Rechercher un prestataire, Consulter un profil prestataire, Réserver un service, Payer (Mobile Money / espèces), Envoyer un message (chat réservation), Recevoir une notification, Évaluer un prestataire, Consulter ses réservations, Consulter les Actualités, Gérer son profil |
| **Prestataire** (11 CU) | S'inscrire et soumettre CNI, Attendre validation, Recevoir décision (accepté/refusé), Corriger et resoummettre (si refusé), Consulter ses missions, Accepter/décliner une réservation, Envoyer un message (chat réservation), Recevoir une notification, Consulter ses revenus, Consulter les Actualités, Gérer son profil |
| **Admin** (10 CU) | Se connecter, Valider un prestataire, Refuser un prestataire (avec motif), Gérer les catégories, Consulter le tableau de bord KPI, Gérer les réservations, Gérer les litiges, Publier des Actualités, Gérer les paiements, Envoyer une notification broadcast |

Les relations `<<include>>` et `<<extend>>` structurent les dépendances entre cas d'utilisation : par exemple, « Payer (Mobile Money) » **inclut** « Vérifier disponibilité API paiement » ; « Corriger et resoummettre » **étend** « Attendre validation » dans le scénario de refus.

---

## 5.2. Diagrammes de classes

### 5.2.1. Structure conceptuelle du modèle de données

*[Insérer ici la Figure 3 : CLASSE COMPLET.svg]*

Le diagramme de classes (`02_class_diagramme.puml`) présente la structure conceptuelle des données de BABIFIX. Il s'articule autour d'une classe abstraite centrale `Utilisateur` et de huit entités métier.

**Classe abstraite Utilisateur** hérite vers trois sous-classes :
- `Client` : attributs spécifiques (historiqueReservations).
- `Prestataire` : attributs spécifiques (statutValidation, motifRefus, cniFichier, specialites, tarif, noteMovenne, disponible).
- `Admin` : attributs spécifiques (niveauAcces).

**Tableau 11 — Description des entités du diagramme de classes**

| Entité | Attributs clés | Relations |
|---|---|---|
| `Utilisateur` (abstraite) | id, nom, prenom, email, telephone, motDePasse, photo, dateInscription | Classe mère de Client, Prestataire, Admin |
| `Client` | historiqueReservations | 1 Client → N Reservations |
| `Prestataire` | statutValidation (enum), motifRefus, cniFichier, specialites, tarif, noteMoyenne | 1 Prestataire → N Reservations, 1 Prestataire → N Ratings |
| `Admin` | niveauAcces | — |
| `Categorie` | id, nom, icone, description, actif | 1 Categorie → N Services |
| `Service` | id, titre, description, tarif, duree, categorie | 1 Service → N Reservations |
| `Reservation` | id, dateReservation, dateService, statut (enum), montant | 1 Reservation → 1 Conversation, 1 Reservation → 1 Paiement |
| `Conversation` | id, reservationId (FK), dateCreation, totalNonLus | 1 Conversation → N Messages |
| `Message` | id, contenu, dateEnvoi, lu (bool), expediteurId | N Messages → 1 Conversation |
| `Paiement` | id, montantFCFA, moyen (enum), statut (enum), reference, date | 1 Paiement → 1 Reservation |
| `Rating` | id, note (1-5), commentaire, date | N Ratings → 1 Prestataire |
| `Notification` | id, titre, corps, lue, type, dateEnvoi | N Notifications → 1 Utilisateur |
| `Actualite` | id, titre, contenu, image, datePublication, auteur | — |

**Énumérations :**
- `StatutValidation` : PENDING, VALIDE, REFUSE, SUSPENDU
- `StatutReservation` : DEMANDE_ENVOYEE, DEVIS_EN_COURS, DEVIS_ENVOYE, DEVIS_ACCEPTE, INTERVENTION_EN_COURS, EN_ATTENTE_CLIENT, TERMINEE, ANNULEE
- `StatutPaiement` : PENDING, COMPLETE, DISPUTE, REFUND
- `TypePaiement` : MOBILE_MONEY, ESPECES, CARTE

---

## 5.3. Diagrammes de séquences

### 5.3.1. Séquence — Nouveau flux demande et devis (client)

*[Insérer ici la Figure 4 : SEQUENCE CLIENT RESERVATION ET PAIEMENT.svg]*

Le diagramme `03_sequence_client_reservation.puml` décrit le **nouveau flux devis** de BABIFIX, qui remplace la réservation directe par un processus négocié en deux temps :

1. **Connexion** : le client s'authentifie via l'API Django (JWT). L'application Flutter stocke le token.
2. **Navigation** : le client envoie `GET /api/public/categories/` puis `GET /api/client/prestataires?category=X` pour afficher la liste filtrée des prestataires validés.
3. **Création de la demande** : le client décrit son problème (texte + photos), sélectionne une date et une adresse, puis envoie `POST /api/client/reservations`. L'API crée la Reservation avec le statut `DEMANDE_ENVOYEE` et notifie le prestataire par FCM.
4. **Préparation du devis (prestataire)** : le prestataire analyse la demande, prépare un devis (diagnostic, lignes de devis, montant, date proposée) et envoie `POST /api/prestataire/requests/{ref}/devis`. Le statut passe à `DEVIS_ENVOYE` et le client est notifié par FCM.
5. **Acceptation ou refus du devis (client)** : le client consulte le devis et l'accepte (`POST /api/client/reservations/{ref}/devis/accept` → statut `DEVIS_ACCEPTE`) ou le refuse (statut rebasculé à `DEMANDE_ENVOYEE` pour permettre un nouveau devis).
6. **Intervention** : le prestataire démarre l'intervention (`INTERVENTION_EN_COURS`), puis la déclare terminée (`EN_ATTENTE_CLIENT`). Le client confirme la réception (`TERMINEE`). Une auto-confirmation est déclenchée après 48h si le client ne répond pas.
7. **Notation** : une fois la réservation en statut `TERMINEE`, le client peut noter et commenter le prestataire.

### 5.3.2. Séquence — Inscription et validation du prestataire

*[Insérer ici la Figure 5 : SEQUENCE PRESTATAIRE INSCRIP ET VALID.svg]*

Le diagramme `04_sequence_prestataire_inscription.puml` décrit le workflow d'inscription et de validation :

1. Le prestataire remplit le formulaire d'inscription (OnboardingScreen) et uploade sa CNI.
2. L'API Django crée le profil prestataire avec `statut = PENDING`.
3. L'API envoie une notification FCM à l'administrateur signalant un nouveau dossier à traiter.
4. **Validation** : l'admin, depuis le panneau web, consulte le dossier, vérifie la CNI et prend sa décision.
5. **Scénario acceptation** : l'admin valide → `statut = VALIDE` → notification FCM au prestataire → le prestataire peut se connecter et accéder à son tableau de bord.
6. **Scénario refus** : l'admin refuse avec motif → `statut = REFUSE`, `motifRefus = "..."` → notification FCM au prestataire avec le motif → le prestataire accède à la page de refus avec le bouton « Modifier ».

### 5.3.3. Séquence — Gestion administrative (validation et modération)

*[Insérer ici la Figure 6 : SEQUENCE ADMIN VALID ET GESTION.svg]*

Le diagramme `05_sequence_admin_validation.puml` détaille le parcours de l'administrateur :

1. L'admin se connecte au panneau web Django (session sécurisée + CSRF).
2. Il accède au tableau de bord KPI qui agrège les données en temps réel.
3. Il consulte la liste des prestataires en attente et traite chaque dossier.
4. Il gère les catégories de services (ajout, modification, désactivation).
5. Les statistiques (revenus, réservations, utilisateurs actifs) sont calculées à la demande par des vues Django agrégant les données de la base.
6. Les notifications FCM sont envoyées automatiquement via les signaux Django (`post_save`) après chaque décision de validation.

### 5.3.4. Séquence — Paiement en espèces

*[Insérer ici la Figure 7 : SEQUENCE PAIEMENT ESPECE.svg]*

Le diagramme `06_sequence_paiement_especes.puml` décrit le flux de paiement en espèces, qui implique une validation manuelle de l'administrateur :

1. Le client réserve un service et choisit le paiement en espèces.
2. La réservation est créée avec `statutPaiement = EN_ATTENTE`.
3. Le paiement est effectué physiquement lors de la prestation.
4. L'administrateur, informé par le prestataire, valide manuellement le paiement depuis le panneau admin.
5. Le statut passe à `CONFIRME` et les deux parties sont notifiées.

### 5.3.5. Séquence — Paiement Mobile Money (flux CinetPay détaillé)

*[Insérer ici la Figure 22 : SEQUENCE PAIEMENT MOBILE MONEY.svg]*

Le diagramme `17_sequence_paiement_mobile_money.puml` détaille le flux complet de paiement via Mobile Money (Orange Money, MTN Moov Money, Wave) en intégrant la passerelle CinetPay :

1. Le client choisit son opérateur Mobile Money et confirme le montant en FCFA.
2. L'application Flutter envoie une requête à l'API Django qui initie une transaction auprès de CinetPay.
3. CinetPay retourne un `transaction_id` et une `redirect_url` ; le paiement est créé en base avec le statut `PENDING`.
4. Le client est redirigé vers l'interface de paiement opérateur (USSD ou page web Mobile Money).
5. L'opérateur notifie CinetPay du résultat ; CinetPay envoie un webhook vers l'API Django.
6. L'API met à jour le statut du paiement (`COMPLETE` ou `DISPUTE`) et notifie les deux parties par FCM.

### 5.3.6. Séquence — Chat temps réel (WebSocket + FCM)

*[Insérer ici la Figure 23 : SEQUENCE CHAT WEBSOCKET.svg]*

Le diagramme `14_sequence_chat_websocket.puml` illustre le protocole de messagerie temps réel entre client et prestataire dans le cadre d'une réservation :

1. Les deux parties se connectent au WebSocket Django Channels via `ws://<serveur>/ws/chat/<reservation_id>/`.
2. Redis sert de couche de canal (Channel Layer) pour distribuer les messages entre les consumers.
3. L'envoi d'un message crée un enregistrement `Message` en base et broadcast la donnée à tous les membres du groupe WebSocket.
4. Si le destinataire est hors-ligne, un signal Django déclenche l'envoi d'une notification FCM.
5. À la reconnexion, l'historique des messages est chargé via `GET /api/chat/<reservation_id>/messages/`.

### 5.3.7. Séquence — Gestion des litiges

*[Insérer ici la Figure 24 : SEQUENCE LITIGES.svg]*

Le diagramme `15_sequence_litiges.puml` modélise le flux de traitement d'un litige entre un client et un prestataire :

1. Le client ou le prestataire signale un problème via l'application après une prestation terminée.
2. Un enregistrement `Dispute` est créé en base avec le statut initial.
3. L'administrateur reçoit une notification et consulte le détail du litige depuis le panneau admin.
4. L'admin peut consulter l'historique de la réservation, le chat associé et les preuves soumises.
5. L'admin tranche : remboursement partiel ou total (mise à jour `StatutPaiement`), avertissement ou suspension du prestataire, ou clôture sans suite.
6. Les deux parties sont notifiées par FCM de la décision.

---

## 5.4. Diagrammes d'activité

### 5.4.1. Activité — Parcours de réservation client

*[Insérer ici la Figure 8 : ACTIVITE RESERVATION CLIENT.svg]*

Le diagramme `07_activite_client_reservation.puml` représente le flux d'activité complet du client depuis l'ouverture de l'application jusqu'à l'évaluation du prestataire. Il est structuré en couloirs d'activité (swimlanes) distinguant les actions de l'application Flutter, de l'API Django et du prestataire. Les décisions clés (service disponible ?, paiement réussi ?, prestation conforme ?) sont modélisées par des nœuds de décision.

### 5.4.2. Activité — Inscription et validation du prestataire

*[Insérer ici la Figure 9 : ACTIVITE INSCRIP ET VALIDATION (PRESTATAIRE).svg]*

Le diagramme `08_activite_prestataire_validation.puml` modélise le processus d'inscription du prestataire avec ses trois branches de sortie : acceptation directe, refus avec boucle de correction, ou abandon de l'inscription. Ce diagramme illustre clairement la logique métier du workflow de validation qui est au cœur de la différenciation de BABIFIX.

### 5.4.3. Activité — Gestion administrative

*[Insérer ici la Figure 10 : ACTIVITE ADMIN GESTION.svg]*

Le diagramme `09_activite_admin_gestion.puml` présente les activités quotidiennes de l'administrateur de la plateforme : traitement des dossiers prestataires, gestion des litiges, publication d'actualités, et supervision des statistiques. Il inclut des boucles de traitement (traiter dossier suivant) et des conditions de terminaison.

### 5.4.4. Activité — Notation et avis

*[Insérer ici la Figure 11 : ACTIVITE NOTATION AVIS svg.svg]*

Le diagramme `10_activite_notation.puml` décrit le processus de notation d'un prestataire après une prestation : déclenchement par la fin de la mission, saisie de la note et du commentaire par le client, mise à jour de la note moyenne du prestataire, notification optionnelle au prestataire. Ce processus alimente le moteur de recommandation de la plateforme.

---

## 5.5. Diagrammes d'état (State Machines)

### 5.5.1. État — Cycle de vie d'une réservation

*[Insérer ici la Figure 25 : STATE MACHINE RESERVATION.svg]*

Le diagramme `13_state_machine_reservation.puml` modélise les transitions d'état d'une réservation tout au long de son cycle de vie. Il reflète le nouveau flux devis de BABIFIX :

| État | Description |
|---|---|
| `DEMANDE_ENVOYEE` | La demande du client vient d'être créée |
| `DEVIS_EN_COURS` | Le prestataire prépare son devis |
| `DEVIS_ENVOYE` | Le devis a été soumis au client |
| `DEVIS_ACCEPTE` | Le client a accepté le devis |
| `INTERVENTION_EN_COURS` | Le prestataire est sur site |
| `EN_ATTENTE_CLIENT` | Le prestataire a déclaré la prestation terminée |
| `TERMINEE` | Le client a confirmé (ou auto-confirmation après 48 h) |
| `ANNULEE` | Annulation à n'importe quelle étape avant intervention |

Si le client refuse le devis, la réservation repasse à `DEMANDE_ENVOYEE` pour permettre une renégociation.

### 5.5.2. État — Cycle de vie d'un prestataire

*[Insérer ici la Figure 26 : STATE MACHINE PRESTATAIRE.svg]*

Le diagramme `16_state_machine_prestataire.puml` modélise l'évolution du statut d'un compte prestataire depuis son inscription jusqu'à son éventuelle suspension :

| État | Description |
|---|---|
| `EN_ATTENTE` | Dossier soumis, en attente de décision admin |
| `VALIDE` | Prestataire approuvé, visible par les clients |
| `REFUSE` | Dossier refusé ; le prestataire peut corriger et resoummettre |
| `SUSPENDU` | Compte temporairement désactivé par l'admin |

La transition `VALIDE → SUSPENDU → VALIDE` permet à l'administrateur de gérer les incidents sans supprimer définitivement le compte.

---

*[Fin de la Deuxième Partie]*

---
---

# TROISIÈME PARTIE : IMPLÉMENTATION, DÉPLOIEMENT ET TESTS

---

# CHAPITRE 6 : ARCHITECTURE LOGICIELLE ET CHOIX DE TECHNOLOGIE

## 6.1. Architecture logicielle et base de données

### 6.1.1. Architecture en couches

BABIFIX adopte une architecture en couches (**layered architecture**) qui sépare les responsabilités entre présentation, logique métier, accès aux données et persistance. Cette séparation favorise la maintenabilité, la testabilité et l'évolutivité du système.

```
┌─────────────────────────────────────────────────────────────────────┐
│                        COUCHE PRÉSENTATION                          │
│  [App Flutter Client]  [App Flutter Prestataire]                    │
│  [Site Vitrine Django]  [Panneau Admin Django]                      │
└──────────────────────────────┬──────────────────────────────────────┘
                               │ HTTPS / WSS / FCM
┌──────────────────────────────▼──────────────────────────────────────┐
│                        COUCHE API / MÉTIER                          │
│  [Django REST Framework — API REST]                                 │
│  [Django Channels — WebSocket Groups]                               │
│  [Django Admin natif — Panneau admin back-end]                      │
│  [App vitrine — Templates Django]                                   │
└──────────────────────────────┬──────────────────────────────────────┘
                               │ ORM Django
┌──────────────────────────────▼──────────────────────────────────────┐
│                        COUCHE DONNÉES                               │
│  [PostgreSQL (production) / SQLite (développement)]                 │
│  [Redis — Broker WebSocket + Cache]                                 │
└─────────────────────────────────────────────────────────────────────┘
                               │ FCM API
┌──────────────────────────────▼──────────────────────────────────────┐
│                      SERVICES EXTERNES                              │
│  [Firebase Cloud Messaging (FCM) — Notifications push]             │
│  [API Paiement Mobile Money (Orange, MTN, Wave)]                       │
└─────────────────────────────────────────────────────────────────────┘
```

*Figure 1 — Architecture logicielle globale de BABIFIX*

**La couche présentation** comprend les quatre interfaces utilisateur liées au backend commun :
- **App Flutter Client** et **App Flutter Prestataire** : applications mobiles iOS/Android communiquant avec l'API REST via HTTPS et avec le serveur WebSocket via WSS. Elles reçoivent les notifications push via FCM.
- **Site Vitrine Django** : interface web publique exposant les informations générales de la plateforme, rendue côté serveur par les templates Django de l'application `vitrine`.
- **Panneau Admin Django** : interface web privée pour l'administration, construite avec l'application `adminpanel` Django et le système d'administration natif de Django.

**La couche API / métier** centralise toute la logique applicative dans le projet Django (`babifix_api`) :
- **Django REST Framework (DRF)** gère les endpoints REST (serializers, viewsets, permissions, pagination).
- **Django Channels** gère les connexions WebSocket via un protocole ASGI, organisant les connexions en groupes (un groupe par conversation de réservation).
- Les **signaux Django** (`post_save`, `pre_delete`) déclenchent des actions automatiques — comme l'envoi d'une notification FCM lors d'un changement de statut de prestataire — sans polluer les vues.

**La couche données** repose sur une base de données relationnelle accédée via l'ORM Django. Redis sert à la fois de broker pour Django Channels (gestion des groupes WebSocket) et de couche de cache pour les requêtes fréquentes.

### 6.1.2. Architecture temps réel

Le système de messagerie en temps réel de BABIFIX est implémenté avec **Django Channels**, l'extension officielle de Django pour le protocole WebSocket et le protocole ASGI (Asynchronous Server Gateway Interface).

Le fonctionnement est le suivant :
1. Lors de l'ouverture du chat d'une réservation, l'application Flutter établit une connexion WebSocket avec le serveur Django Channels (`wss://api.babifix.ci/ws/chat/<reservation_id>/`).
2. Django Channels assigne cette connexion à un **groupe de canal** nommé `chat_<reservation_id>`, stocké dans Redis.
3. Lorsqu'un message est envoyé par un participant, le `ChatConsumer` persiste le message en base (modèle `Message`) et diffuse (`broadcast`) le message JSON à tous les membres du groupe WebSocket correspondant.
4. L'autre participant reçoit le message en temps réel dans son application Flutter sans avoir à interroger l'API REST.
5. Le compteur de messages non lus (`totalNonLus` sur la `Conversation`) est mis à jour en base, et l'API `/api/conversations/unread-count/` permet à l'application de rafraîchir le badge.

### 6.1.3. Modèle de données

Le modèle de données de BABIFIX s'articule autour de la table centrale `Reservation`, qui constitue le pivot entre les interactions client/prestataire :

- Un **Utilisateur** est la classe de base, étendue par un modèle personnalisé Django (`AbstractBaseUser` ou `OneToOneField` vers un profil).
- Un **Prestataire** possède un champ `statut` (CharField avec choices : PENDING, VALIDE, REFUSE, SUSPENDU) et un champ `refusal_reason` (TextField nullable) contenant le motif de refus saisi par l'administrateur.
- Une **Reservation** lie un `Client` à un `Prestataire` et un `Service`, avec un `statutReservation` et un lien vers un `Paiement`.
- Une **Conversation** est liée en OneToOne à une `Reservation` (clé étrangère unique). Cette relation garantit qu'il n'existe qu'un seul fil de discussion par réservation.
- Un **Message** appartient à une `Conversation` et possède un champ booléen `lu` pour le suivi des messages non lus.
- Les migrations Django tracent l'évolution du schéma au fil des versions (versions 1 à 8 du cahier fonctionnel).

---

## 6.2. Choix technologiques et environnement de développement

### 6.2.1. Tableau des choix technologiques justifiés

**Tableau 12 — Justification des choix technologiques**

| Composant | Technologie retenue | Alternatives considérées | Justification |
|---|---|---|---|
| Backend API + Temps réel | **Django 4.x + DRF + Django Channels** | Node.js/Express, FastAPI | Productivité (ORM, migrations, admin), écosystème Python mature, Channels natif pour WebSocket |
| Site vitrine web | **Django + templates HTML/CSS** | React, Vue.js | Rendu côté serveur (SEO), rapidité de livraison, cohérence stack |
| Panneau admin web | **App adminpanel Django + style.css** | React Admin, Django Admin natif seul | Personnalisation UI tout en réutilisant la logique Django |
| App client mobile | **Flutter (Dart) + Material 3** | React Native, Kotlin/Swift natif | Cross-platform iOS/Android avec un seul codebase, performance 60 FPS, composants Material 3 |
| App prestataire mobile | **Flutter (Dart) + Material 3** | — | Partage du codebase et du design system avec l'app client |
| Notifications push | **Firebase Cloud Messaging (FCM)** | OneSignal, APNs/FCM directement | Standard industrie, gratuit jusqu'à un volume élevé, multi-plateforme, intégration Flutter native |
| Auth mobile | **JWT (djangorestframework-simplejwt)** | Google Sign-In, Apple Sign-In | Stateless, scalable, pas de dépendance Firebase côté backend |
| Auth web | **Sessions Django + CSRF** | JWT pour web | Mécanisme natif Django, sécurisé pour les interfaces web |
| Base de données | **SQLite (dev) / PostgreSQL (prod)** | MySQL | SQLite pour la simplicité dev, PostgreSQL pour la robustesse prod |
| Broker WebSocket | **Redis** | Memcached, In-memory | Requis par Django Channels pour les groupes multi-instances |
| Paiement | **FCFA + logos Mobile Money (Orange, MTN, Wave)** | Stripe, PayPal | Solution adaptée au contexte ivoirien (Mobile Money natif) |

### 6.2.2. Structure du projet Django

Le backend BABIFIX est organisé en deux projets Django distincts :

**babifix_admin_django** (Backend API + Panneau admin)
```
babifix_admin_django/
├── manage.py
├── config/                 # Configuration du projet (settings.py, urls.py, asgi.py, routing.py)
├── adminpanel/            # Application unique contenant toute la logique métier
│   ├── models.py          # Provider, Client, Reservation, Payment, Category, etc.
│   ├── views.py           # Endpoints API REST (~2400 lignes)
│   ├── views_extra.py     # Emails, disponibilités, bulk, audit, export CSV
│   ├── auth.py            # JWT custom : create_token(), verify_token()
│   ├── consumers.py       # WebSocket : ClientEventsConsumer, PrestataireEventsConsumer
│   ├── signals.py         # post_save → push FCM + WebSocket broadcast
│   ├── serializers.py     # Sérialisation DRF
│   └── migrations/        # Migrations Django
├── templates/
│   └── adminpanel/        # Interface admin web (HTML/Bootstrap + HTMX + Chart.js)
└── requirements.txt        # Django 5.2, DRF, Channels, firebase-admin, etc.
```

**babifix_vitrine_django** (Site vitrine public)
```
babifix_vitrine_django/
├── manage.py
├── config/
├── vitrine/               # Pages : index, mentions legales, contact
└── templates/vitrine/    # Templates HTML avec animations CSS, cookie RGPD
```

L'application `adminpanel` concentre toute la logique métier : les modèles, les serializers DRF, les vues API, les consumers WebSocket, les signaux Django et les migrations de base de données.

### 6.2.3. Environnement de développement

- **Langage backend** : Python 3.12
- **Framework backend** : Django 5.2
- **Langage frontend mobile** : Dart (SDK Flutter 3.27)
- **Éditeur** : Visual Studio Code avec extensions Python, Flutter/Dart, Django
- **Gestionnaire de dépendances Python** : pip + `requirements.txt`
- **Gestionnaire de dépendances Flutter** : pub (pubspec.yaml)
- **Contrôle de version** : Git
- **Base de données de développement** : SQLite 3
- **Serveur de développement** : `python manage.py runserver` (WSGI) + `daphne` (ASGI pour WebSocket)
- **Technologies complémentaires** : HTMX (interactions AJAX côté admin), Alpine.js (réactivité), Chart.js (graphiques dashboard), fl_chart (graphiques Flutter), GoRouter (routage Flutter), Locust (tests de charge), Sentry (monitoring erreurs), Nominatim (géocodage)

---

## 6.3. Diagramme de déploiement — Infrastructure de production

*[Insérer ici la Figure 27 : DEPLOIEMENT INFRASTRUCTURE.svg]*

Le diagramme `12_deploiement_infrastructure.puml` représente l'infrastructure cible de BABIFIX en environnement de production. Il modélise les nœuds physiques et logiques, leurs interconnexions et les artefacts déployés sur chacun :

- **Client mobile** (iOS/Android) : applications Flutter se connectant via HTTPS au serveur Nginx.
- **Serveur Nginx** : reverse proxy gérant la terminaison SSL/TLS, le routage des requêtes HTTP vers Gunicorn/Daphne, et la distribution des fichiers statiques (`/static/`, `/media/`).
- **Daphne (ASGI)** : serveur ASGI Django Channels gérant les connexions WebSocket pour le chat temps réel.
- **Django (WSGI)** : traitement des requêtes HTTP REST via Gunicorn.
- **PostgreSQL 16** : base de données relationnelle principale hébergeant l'ensemble des données métier.
- **Redis 7** : broker de messages pour Django Channels (Channel Layer WebSocket) et cache des rate limiters.
- **Firebase (FCM)** : service externe de notifications push, contacté par le backend Django via l'API FCM.
- **CinetPay** : passerelle de paiement Mobile Money externe, contactée par webhook bidirectionnel.

Ce diagramme constitue le plan de référence pour le déploiement sur un VPS (Virtual Private Server) avec configuration Docker Compose ou déploiement manuel.

---

# CHAPITRE 7 : RÉALISATION DES MODULES CLÉS

## 7.1. Développement du moteur de recherche

### 7.1.1. Architecture du module de recherche

Le moteur de recherche de BABIFIX permet aux clients de trouver le prestataire le mieux adapté à leur besoin. Il est implémenté en deux parties complémentaires : le composant de filtrage côté Flutter (interface) et les endpoints de recherche côté Django (logique de filtrage).

L'interface Flutter expose deux composants principaux :
- **`CategoryTab`** : une barre de navigation horizontale affichant les catégories de services sous forme d'onglets avec icônes SVG et couleurs de marque. Chaque icône est chargée dynamiquement depuis le serveur Django via le champ `icone_url` retourné par l'API (`/api/public/categories/`). Ce champ contient l'URL absolue d'un fichier SVG stocké dans les fichiers statiques Django (`static/category-icons/<slug>.svg`). Le composant `CategoryStrip` (Flutter) affiche chaque icône via `SvgPicture.network()` — sans aucun mapping local codé en dur. Cette architecture garantit que toute icône ajoutée ou modifiée dans le panneau d'administration est immédiatement visible dans les applications mobiles sans mise à jour de code. Le clic sur une catégorie déclenche une requête filtrée vers l'API.
- **`ServiceCard`** : une carte prestataire affichant la photo, le nom, la spécialité, la note moyenne (étoiles), le tarif indicatif et un bouton de réservation rapide.

### 7.1.2. Filtrage et tri des résultats

Côté Django, les endpoints de recherche utilisent les capacités de filtrage de Django REST Framework (`django-filter`) couplées aux `Q objects` Django pour les recherches textuelles :

```python
# Exemple simplifié d'une vue de recherche de prestataires
def api_public_providers(request):
    queryset = Provider.objects.filter(
        statut=Provider.Status.VALID,
        is_approved=True,
        is_deleted=False,
    )
    category = request.GET.get('category', '').strip()
    search = request.GET.get('q', '').strip()
    if category:
        queryset = queryset.filter(
            Q(category__nom__icontains=category) |
            Q(specialite__icontains=category)
        )
    if search:
        queryset = queryset.filter(
            Q(nom__icontains=search) |
            Q(specialite__icontains=search) |
            Q(bio__icontains=search)
        )
    return queryset.order_by('-average_rating', '-rating_count')
```

Les critères de tri disponibles sont :
1. **Note moyenne décroissante** (tri par défaut) : les prestataires les mieux notés apparaissent en premier.
2. **Disponibilité** : filtre sur le champ `disponible` du prestataire.
3. **Localisation** : filtre sur le champ `zoneIntervention` (ville ou quartier).

### 7.1.3. Système de recommandation

Le système de recherche actuel de BABIFIX repose sur un filtrage par catégorie et un tri par note moyenne décroissante. Les résultats affichent les prestataires validés par l'administrateur, triés selon leur note.

Les perspectives d'évolution incluent un système de recommandation basé sur :
- **l'historique** : les prestataires avec lesquels un client a déjà eu une bonne expérience (note ≥ 4) pourraient être mis en avant
- **la popularité** : les prestataires les plus demandés dans une catégorie donnée bénéficieraient d'un boost
- **l'exclusion** : les prestataires ayant reçu une note basse (< 3) seraient rétrogradés
- **la géolocalisation** : intégration de PostGIS pour filtrer par rayon autour du client

L'intégration d'algorithmes de filtrage collaboratif ou de Machine Learning pour des recommandations plus personnalisées constitue une perspective à moyen terme.

---

## 7.2. Implémentation du module de sécurité

### 7.2.1. Système d'authentification JWT

L'authentification JWT est mise en œuvre via la bibliothèque `djangorestframework-simplejwt`. Le flux d'authentification complet est le suivant :

1. **Connexion** : l'application Flutter envoie `POST /api/token/` avec `{"email": "...", "password": "..."}`. L'API retourne `{"access": "<token>", "refresh": "<refresh_token>"}`.
2. **Utilisation** : chaque requête authentifiée inclut l'en-tête `Authorization: Bearer <access_token>`.
3. **Rafraîchissement** : quand l'access token expire, l'app envoie `POST /api/token/refresh/` avec le refresh token pour obtenir un nouveau access token sans redemander les credentials.
4. **Déconnexion** : la déconnexion côté client consiste à supprimer les tokens du stockage local Flutter.

La durée de vie des tokens est configurée dans `settings.py` :
- Access token : 30 minutes (balance entre sécurité et confort utilisateur).
- Refresh token : 7 jours (durée de session raisonnable).

### 7.2.2. Contrôle d'accès par rôles

Le système de permissions de BABIFIX est implémenté via des classes de permission DRF personnalisées :

```python
class IsPrestataire(BasePermission):
    """
    Permission accordée uniquement aux prestataires validés (statut VALIDE).
    """
    def has_permission(self, request, view):
        return (
            request.user.is_authenticated and
            hasattr(request.user, 'provider') and
            request.user.provider.statut == Provider.Status.VALID
        )
```

Chaque vue API déclare explicitement les permissions requises via le décorateur `@require_api_auth(roles)` :
- Endpoints publics (liste des catégories, prestataires) : aucune authentification requise.
- Endpoints client (réservations, profil, chat) : rôle `"client"`.
- Endpoints prestataire (demandes, revenus, devis) : rôle `"prestataire"` + statut `VALIDE`.
- Endpoints administrateur (validation, KPI, statistiques) : rôle `"admin"`.

### 7.2.3. Sécurisation des données sensibles

**Upload de la CNI** : les fichiers CNI sont uploadés via `POST /api/prestataires/cnidocument/` avec validation côté serveur :
- Validation du type MIME (uniquement `image/jpeg`, `image/png`, `application/pdf`).
- Taille maximale limitée à 5 Mo.
- Stockage dans un répertoire privé (`MEDIA_ROOT/cni/`) non exposé directement via l'URL.
- Accès à la CNI uniquement via un endpoint protégé (`IsAdminUser`).

**Protection des endpoints sensibles** :
- `/api/admin/prestataires/<id>/valider/` : réservé aux administrateurs.
- `/api/admin/statistiques/` : réservé aux administrateurs.
- `/api/admin/paiements/` : réservé aux administrateurs.

**Sanitisation des inputs** : les serializers DRF effectuent une validation automatique des types, longueurs et formats des données entrantes. Les champs de texte libre (descriptions, commentaires) sont validés pour prévenir les injections de contenu malveillant.

### 7.2.4. Authentification sociale (Google Sign-In et Sign in with Apple)

BABIFIX intègre deux mécanismes d'authentification sociale permettant aux clients de s'inscrire et de se connecter sans saisir de mot de passe, via leur compte Google ou Apple.

**Flux Google Sign-In** :
1. L'application Flutter déclenche `GoogleSignIn().signIn()` via le package `google_sign_in`.
2. Le token d'identité (`idToken`) retourné par Google est envoyé en `POST /api/auth/social/google/`.
3. Le serveur Django vérifie le token via la bibliothèque `google-auth` (`id_token.verify_oauth2_token()`), en contrôlant l'audience (`GOOGLE_CLIENT_ID`) et l'émetteur (`accounts.google.com`).
4. Si la vérification réussit, l'utilisateur est créé ou retrouvé en base (`get_or_create`) à partir de son adresse e-mail.
5. Une paire de tokens JWT (access + refresh) est retournée, permettant à l'application de s'authentifier auprès de tous les endpoints protégés.

**Flux Sign in with Apple** :
1. L'application Flutter déclenche `SignInWithApple.getAppleIDCredential()` via le package `sign_in_with_apple`.
2. L'`identityToken` (JWT RS256) est envoyé en `POST /api/auth/social/apple/`.
3. Le serveur Django récupère les clés publiques d'Apple depuis le endpoint JWKS officiel (`https://appleid.apple.com/auth/keys`) et vérifie la signature du token via `PyJWT`.
4. L'identité (`sub` + `email`) est extraite et le compte utilisateur est créé ou retrouvé.
5. Des tokens JWT BABIFIX sont retournés selon le même mécanisme que pour Google.

Ce mécanisme améliore le taux de conversion à l'inscription en supprimant la friction liée à la création d'un mot de passe, tout en maintenant la sécurité par vérification cryptographique côté serveur.

*[Insérer ici la Figure 20 : capture d'écran — Écran d'authentification avec boutons Google et Apple Sign-In]*

### 7.2.5. Vérification d'email et réinitialisation de mot de passe

La plateforme implémente un workflow complet de vérification d'adresse e-mail et de réinitialisation de mot de passe :

**Vérification d'email** :
- À la création du compte, un token aléatoire est généré et stocké dans le champ `email_verify_token` du profil utilisateur.
- Un e-mail contenant un lien `https://<domaine>/api/auth/verify-email/<token>` est envoyé à l'utilisateur.
- La validation du lien (`GET /api/auth/verify-email/<token>`, implémenté dans `views_v2.py`) active le champ `is_email_verified = True` sur le compte utilisateur.
- Les utilisateurs non vérifiés ne peuvent pas effectuer de réservations.

**Réinitialisation de mot de passe** :
- L'utilisateur soumet son adresse e-mail via `POST /api/auth/forgot-password`.
- Un token de réinitialisation est créé (via `AppPasswordResetTokenGenerator` de Django) et envoyé par e-mail.
- La soumission du nouveau mot de passe via `POST /api/auth/reset-password` invalide le token après usage.

Ces mécanismes garantissent que seules des adresses e-mail valides sont enregistrées sur la plateforme, réduisant les créations de comptes frauduleux.

*[Insérer ici la Figure 21 : capture d'écran — Écran de vérification d'adresse email post-inscription]*

---

## 7.3. Présentation des interfaces utilisateurs

### 7.3.1. Application mobile client (Flutter — iOS/Android)

*[Insérer ici la Figure 12 : capture d'écran de l'app client — liste services]*

L'application Flutter client est la vitrine principale de BABIFIX pour les utilisateurs finaux. Elle offre une expérience fluide et intuitive, organisée autour d'une navigation par onglets flottants (BottomNav glassmorphism). La barre de navigation inférieure comprend cinq onglets principaux : **Accueil**, **Services**, **Actus**, **Rendez-vous** et **Profil**. Les fonctions de messagerie et de notifications sont accessibles via des icônes dans la barre supérieure (topbar) :

**Écran d'authentification** :
L'application propose trois modes de connexion : formulaire e-mail/mot de passe classique, bouton **« Continuer avec Google »** (Google Sign-In) et bouton **« S'identifier avec Apple »** (Sign in with Apple, affiché sur iOS conformément aux directives App Store). Après inscription par e-mail, un écran de confirmation invite l'utilisateur à vérifier sa messagerie avant de pouvoir réserver.

**Écran principal — Liste des services** :
L'écran d'accueil affiche les catégories de services via le composant `CategoryStrip` (barre d'onglets horizontale défilable). Chaque onglet de catégorie affiche une icône SVG chargée directement depuis le serveur Django : l'API `/api/public/categories/` retourne le champ `icone_url` contenant l'URL absolue du fichier SVG (`http://<serveur>/static/category-icons/<slug>.svg`), rendu par `SvgPicture.network()`. Cette architecture pilotée par le serveur élimine tout mapping local et garantit la cohérence entre le panneau d'administration et les apps mobiles. Sous les catégories, les prestataires de la catégorie sélectionnée sont listés sous forme de `ServiceCard`. Chaque carte affiche : photo du prestataire, nom, spécialité, note moyenne (étoiles dorées), tarif indicatif et un bouton de réservation rapide.

**Écran de réservation** :
Un formulaire guidé permet au client de spécifier la date, le créneau horaire, l'adresse d'intervention et des instructions particulières. Un récapitulatif est présenté avant la confirmation.

**Écran de chat** :
Interface de messagerie liée à la réservation concernée. Les messages sont affichés dans des bulles différenciées (client à droite, prestataire à gauche). L'accès au chat se fait via l'icône de messagerie dans la topbar, avec un badge rouge indiquant les messages non lus.

*[Insérer ici la Figure 15 : capture d'écran — ChatScreen avec badge messages non lus]*

**Écran Actualités** :
Liste d'articles publiés par l'administration, avec titre, image de couverture et extrait. Un clic ouvre l'article complet.

**Design** : couleurs Côte d'Ivoire (orange/vert/bleu), Material 3, polices système, tokens définis dans `babifix_design_system.dart`.

### 7.3.2. Application mobile prestataire (Flutter — iOS/Android)

*[Insérer ici la Figure 13 : capture d'écran — PendingScreen]*
*[Insérer ici la Figure 14 : capture d'écran — page refus avec motif]*

L'application Flutter prestataire est conçue pour les artisans et professionnels. La barre de navigation inférieure (même design glassmorphism que l'app client) comprend cinq onglets : **Accueil**, **Exigences** (demandes et missions en cours), **Gains** (wallet et revenus), **Messages** (chat avec badge non lus) et **Profil**. Son parcours distinctif inclut les écrans de validation :

**OnboardingScreen — Inscription** :
Formulaire multi-étapes guidant le prestataire : informations personnelles → informations professionnelles (spécialités, zone d'intervention, tarif) → upload de la CNI. Une interface soignée avec indicateur de progression.

**PendingScreen — Attente de validation** :
Page premium informant le prestataire que son dossier est en cours d'examen. Affichage d'une illustration rassurante, d'un message d'explication et d'une estimation du délai de traitement. Bouton de contact du support si besoin.

**Page refus avec motif** :
Si le dossier est refusé, le prestataire voit s'afficher clairement le motif de refus saisi par l'administrateur, accompagné d'un bouton « Modifier ma demande » qui rouvre le formulaire d'inscription pré-rempli pour correction. Ce flux garantit que le prestataire comprend exactement pourquoi son dossier a été refusé et comment le corriger.

**RequestsScreen — Tableau de bord des missions** :
Liste des demandes de réservation reçues, avec statut (en attente, confirmée, en cours, terminée). Le prestataire peut accepter ou décliner chaque demande.

**MessagesScreen — Chat** :
Interface de messagerie identique à l'app client, avec le badge de messages non lus visible sur la BottomNav.

**EarningsScreen — Revenus** :
Tableau synthétique des missions complétées et des revenus perçus, avec détail par période.

### 7.3.3. Panneau d'administration web (Django)

*[Insérer ici la Figure 16 : capture d'écran — Dashboard KPI admin]*

Le panneau d'administration est une interface web Django dédiée aux opérateurs de la plateforme. Il est accessible uniquement aux utilisateurs authentifiés avec les droits d'administration.

**Dashboard KPI** :
La page d'accueil affiche les indicateurs clés de la plateforme : nombre total d'utilisateurs inscrits, nombre de prestataires en attente de validation / validés / refusés, nombre de réservations du jour / de la semaine, revenus générés en FCFA avec répartition par opérateur Mobile Money (affichage des logos Orange Money, MTN Moov Money, Wave). Des graphiques d'évolution illustrent les tendances.

**Gestion des prestataires** :
Vue en liste de tous les prestataires avec leur statut. Un formulaire de validation permet à l'admin d'accepter ou de refuser un dossier en saisissant un motif de refus. La décision déclenche automatiquement une notification FCM au prestataire via un signal Django.

**Gestion des catégories** :
Interface CRUD (Create, Read, Update, Delete) pour les catégories de services : nom, icône, description, statut actif/inactif.

**Gestion des actualités** :
Éditeur simplifié pour la publication d'articles : titre, contenu (texte riche), image de couverture, date de publication.

**Gestion des paiements** :
Tableau des transactions avec : référence de réservation, montant en FCFA, opérateur Mobile Money (avec logo), statut de la transaction, date.

**Technologie** : application `adminpanel` Django avec templates HTML personnalisés et feuille de style `style.css`. Le panneau utilise les mécanismes d'authentification par session Django avec protection CSRF.

### 7.3.4. Site vitrine web (Django)

*[Insérer ici la Figure 17 : capture d'écran — Site vitrine BABIFIX]*

Le site vitrine est la présence web publique de BABIFIX, destinée à présenter la plateforme aux clients et prestataires potentiels et à améliorer la visibilité en ligne (SEO).

Le site est structuré en sections distinctes :

- **HeroSection** : bandeau principal avec un titre animé à rotation de mots (« Trouvez des artisans vérifiés / qualifiés / de confiance »), une illustration attractive et deux boutons d'appel à l'action (« Télécharger l'app client » / « Devenir prestataire »). Un bandeau de confiance (trust strip) présente la note moyenne et les indicateurs clés (prestataires certifiés, disponibilité 7j/7, satisfaction garantie).
- **Comment ça marche** : présentation en 3 étapes du parcours client (chercher → réserver → évaluer) et du parcours prestataire (s'inscrire → être validé → recevoir des missions).
- **CategoriesSection** : galerie visuelle des catégories de services disponibles.
- **Stats** : chiffres clés de la plateforme (prestataires inscrits, réservations effectuées, clients satisfaits).
- **Notifications intelligentes** : section mettant en avant les capacités de push notification de la plateforme via une maquette de téléphone animée affichant des notifications en temps réel (nouvelle mission, réservation confirmée, message client, paiement reçu). Cette section démontre la valeur ajoutée du canal FCM pour les prestataires.
- **Testimonials** : témoignages de clients et prestataires.
- **FAQSection** : questions fréquemment posées sur l'utilisation de la plateforme.
- **ContactSection** : formulaire de contact soumis par `POST` à la vue Django `home` (URL `/`), avec protection anti-spam (honeypot + rate-limiting par IP), validation côté serveur et envoi par e-mail via SMTP à l'équipe BABIFIX.
- **Footer** : liens rapides, réseaux sociaux, mentions légales.

**Consentement aux cookies (RGPD)** : lors de la première visite, un bandeau de consentement aux cookies apparaît en bas de page. Il propose trois catégories : cookies essentiels (activés par défaut, non désactivables), analytiques et marketing. Le choix de l'utilisateur est mémorisé dans le `localStorage` du navigateur sous la clé `babifix_cookie_consent`. Un modal détaillé permet d'affiner les préférences. Cette implémentation s'inscrit dans le respect de la vie privée des utilisateurs conformément au Règlement général sur la protection des données (RGPD) et à la Loi ivoirienne n°2013-450 relative à la protection des données à caractère personnel (ARTCI).

*[Insérer ici la Figure 18 : Section « Notifications intelligentes » du site vitrine]*
*[Insérer ici la Figure 19 : Bandeau de consentement aux cookies (RGPD)]*

**Technologie** : application `vitrine` Django avec templates HTML, feuille de style `style.css`, animations CSS (`@keyframes`, transitions `cubic-bezier`) et JavaScript natif pour le rotateur de mots, le consentement aux cookies et l'envoi du formulaire de contact.

---

## 7.4. Modules complémentaires et fonctionnalités transversales

Cette section présente les fonctionnalités additionnelles qui enrichissent l'expérience utilisateur et la robustesse technique de la plateforme BABIFIX.

### 7.4.1. Carte des prestataires et géolocalisation

L'application client Flutter intègre un écran `ProvidersMapScreen` permettant aux clients de visualiser les prestataires sur une carte interactive. Cette fonctionnalité s'appuie sur la bibliothèque `flutter_map` (wrapper OpenStreetMap) et le service de géocodage `Nominatim` pour convertir les adresses en coordonnées. Le client peut définir un rayon de recherche et visualiser les markers des prestataires disponibles dans cette zone.

### 7.4.2. Mode hors-ligne et résilience réseau

La résilience réseau est cruciale dans le contexte africain où la connectivité peut être instable. BABIFIX implémente plusieurs mécanismes :
- `BabifixOfflineCache` : cache local des données fréquemment consultées (catégories, prestataires favoris)
- `NetworkConnectivity` : détection de l'état de connexion via `connectivity_plus`
- `HttpRetryClient` : client HTTP avec retry automatique et backoff exponentiel
- `ConnectivityBanner` : composant UI affichant un bandeau lorsque l'appareil est hors-ligne

### 7.4.3. Authentification biométrique

L'application Flutter intègre `BiometricAuthService` utilisant `local_auth` pour l'authentification par empreinte digitale ou reconnaissance faciale. L'écran `BiometricLoginScreen` permet aux utilisateurs d'accéder rapidement à leur compte sans saisir leur mot de passe. Cette fonctionnalité est particulièrement appréciée sur mobile.

### 7.4.4. Certificate pinning

Pour renforcer la sécurité des communications HTTPS, BABIFIX implémente le certificate pinning via `CertificatePinningConfig`. Les empreintes des certificats sont vérifiées lors de chaque requête API pour prévenir les attaques man-in-the-middle.

### 7.4.5. Système de favoris

Le modèle `ClientFavorite` permet aux clients de sauvegarder leurs prestataires préférés. Le backend expose l'endpoint `GET/POST/DELETE /api/client/favorites/` (implémenté dans `views_extra.py`) avec les opérations CRUD complètes. Les chaînes de traduction (`addToFavorites`, `removeFromFavorites`) sont définies dans l'app Flutter client. L'intégration UI (icône cœur sur les fiches prestataires) constitue une évolution prévue à court terme.

### 7.4.6. Notation bidirectionnelle

Après chaque prestation, le client peut noter le prestataire via `RateProviderScreen` (app client), et le prestataire peut noter le client via `RateClientScreen` (app prestataire). Le modèle `ClientRating` (introduit dans `models_v2.py`) supporte les deux directions, créant un système de réputation mutuel qui renforce la confiance sur la plateforme.

### 7.4.7. Gestion des disponibilités

Les prestataires peuvent définir leurs créneaux de disponibilité via le modèle `PrestataireAvailabilitySlot` et déclarer leurs périodes d'indisponibilité avec `PrestataireUnavailability`. L'écran `AvailabilityScreen` dans l'app prestataire permet une gestion intuitive de la planification.

### 7.4.8. Écran de paiement Mobile Money

L'écran `PaymentScreen` (1230 lignes) permet au client de sélectionner son opérateur Mobile Money (Orange Money, MTN, Wave) et de suivre le statut de la transaction. L'intégration avec la passerelle de paiement (CinetPay ou équivalent) permet un paiement fluide en FCFA.

### 7.4.9. Journal d'audit administrateur

Le modèle `AdminAuditLog` enregistre toutes les actions administratives sensibles : validation/refus de prestataires, modification de réservation, gestion des catégories. L'endpoint `api_admin_audit_log` permet à l'administrateur de consulter l'historique des actions.

### 7.4.10. Emails transactionnels

Le projet inclut 5 templates d'emails transactionnels dans `templates/emails/` :
- Confirmation d'inscription client
- Notification de nouvelle réservation (prestataire)
- Confirmation de réservation confirmée (client)
- Notification de changement de statut de réservation
- Résumé hebdomadaire des activités

### 7.4.11. Commissions par catégorie

Le modèle `CategoryCommission` permet de définir un pourcentage de commission différent pour chaque catégorie de service. Cette flexibilité permet d'adapter la rentabilité selon le type de prestation.

### 7.4.12. Export CSV et actions bulk

L'administrateur peut exporter les données par section (prestataires, reservations, clients) via l'endpoint `export_csv`. Les actions bulk permettent de valider ou refuser plusieurs prestataires en une seule opération via `api_admin_bulk_provider_action`.

---

# CHAPITRE 8 : TESTS, VALIDATION ET PERSPECTIVES D'ÉVOLUTION

## 8.1. Protocoles de tests

### 8.1.1. Tests fonctionnels et de parcours

Les tests fonctionnels visent à valider que chaque parcours utilisateur identifié dans l'analyse des besoins fonctionne correctement de bout en bout. Ils sont réalisés manuellement selon des scénarios de test définis.

**Tableau 13 — Protocoles de tests et résultats**

| Type de test | Domaine testé | Méthode | Critère de succès | Statut |
|---|---|---|---|---|
| Test fonctionnel | Inscription client | Manuel — scénario complet | Compte créé, connexion réussie | ✅ Validé |
| Test fonctionnel | Inscription prestataire + upload CNI | Manuel — scénario complet | Dossier soumis, statut PENDING affiché | ✅ Validé |
| Test fonctionnel | Validation admin → notification prestataire | Manuel — panneau admin | Statut ACCEPTED, notification FCM reçue | ✅ Validé |
| Test fonctionnel | Refus admin avec motif → page refus prestataire | Manuel — panneau admin | Motif affiché, bouton « Modifier » fonctionnel | ✅ Validé |
| Test fonctionnel | Resoumission après refus | Manuel — app prestataire | Statut repasse à PENDING, formulaire pré-rempli | ✅ Validé |
| Test fonctionnel | Réservation client → notification prestataire | Manuel — scénario complet | Réservation créée, notification FCM reçue | ✅ Validé |
| Test fonctionnel | Chat réservation — échange de messages | Manuel — 2 comptes | Messages reçus en temps réel, badge actualisé | ✅ Validé |
| Test fonctionnel | Affichage actualités (client + prestataire) | Manuel | Articles visibles dans les deux apps | ✅ Validé |
| Test fonctionnel | Dashboard KPI admin | Manuel | Indicateurs affichés correctement en FCFA | ✅ Validé |
| Test temps réel | Chat WebSocket — 2 sessions simultanées | 2 comptes simultanés | Messages reçus < 100ms, badge actualisé | ✅ Validé |
| Test de régression | Flux v1-8 après évolutions UI | Re-test scénarios de base | Logique métier inchangée | ✅ Validé |
| Test unitaire | Endpoints REST (CRUD, permissions) | Django TestCase | Réponses HTTP correctes, accès refusé si non autorisé | 🔄 En cours |
| Test fonctionnel | Authentification Google Sign-In | Manuel — app client Flutter | Connexion Google → JWT retourné, profil pré-rempli | ✅ Validé |
| Test fonctionnel | Authentification Apple Sign-In | Manuel — app client iOS | Connexion Apple → JWT retourné, compte créé | ✅ Validé |
| Test fonctionnel | Vérification d'email | Manuel — parcours inscription | Lien reçu par e-mail, validation active is_email_verified | ✅ Validé |
| Test fonctionnel | Réinitialisation de mot de passe | Manuel — formulaire oubli | Token envoyé, nouveau MDP enregistré, ancien invalide | ✅ Validé |
| Test fonctionnel | Bandeau cookie RGPD | Manuel — navigateur vitrine | Bannière affichée 1ère visite, masquée si déjà accepté, consentement mémorisé localStorage | ✅ Validé |
| Test fonctionnel | Formulaire de contact vitrine | Manuel — site vitrine | POST / → e-mail reçu, message de confirmation affiché | ✅ Validé |
| Test de charge | API + WebSocket (100 utilisateurs concurrents) | Locust / k6 (prévu) | Latence < 200ms, pas de crash | 📋 Prévu |
| Audit sécurité | Endpoints sensibles (OWASP ZAP) | Scan automatisé (prévu) | Pas de vulnérabilité critique (A01-A10) | 📋 Prévu |

### 8.1.2. Tests de la messagerie temps réel

Le test du système de messagerie temps réel est un point critique car il implique une connexion WebSocket persistante. La procédure de test est la suivante :

1. Ouvrir l'app client (compte A) et l'app prestataire (compte B) simultanément.
2. A et B ouvrent le chat d'une réservation existante.
3. Le testeur envoie un message depuis le compte A et vérifie que :
   - Le message apparaît immédiatement dans l'interface de B (sans rechargement).
   - Le badge de messages non lus s'affiche sur l'icône Messages de B.
   - La latence mesurée est inférieure à 100 ms.
4. B répond ; A reçoit la réponse en temps réel.
5. B ouvre le chat → le badge de B se remet à zéro (messages marqués comme lus via l'API).

### 8.1.3. Tests de sécurité

Les tests de sécurité vérifient que les mécanismes de protection implémentés sont opérationnels :

- **Test d'accès non autorisé** : tenter d'accéder à `/api/admin/prestataires/valider/` sans token d'administrateur → réponse `403 Forbidden` attendue.
- **Test d'expiration du JWT** : attendre l'expiration de l'access token et envoyer une requête → réponse `401 Unauthorized` attendue.
- **Test de dépassement de taille** : tenter d'uploader un fichier CNI dépassant 5 Mo → réponse `400 Bad Request` avec message d'erreur attendue.
- **Test d'injection SQL** : envoyer des paramètres de recherche contenant des fragments SQL (`' OR '1'='1`) → l'ORM Django protège nativement contre les injections SQL.

---

## 8.2. Bilan du projet face aux objectifs initiaux

### 8.2.1. Conformité aux objectifs fonctionnels

À l'issue des versions 1 à 8 du cahier fonctionnel, BABIFIX répond à l'ensemble des objectifs fixés au démarrage du projet.

**Tableau 14 — Bilan de conformité aux objectifs du projet**

| Objectif fixé | Statut | Preuve / Élément de vérification |
|---|---|---|
| 4 interfaces distinctes et cohérentes | ✅ Atteint | App Flutter client, App Flutter prestataire, Site vitrine Django, Panneau admin Django |
| Workflow validation prestataire (3 états) | ✅ Atteint | PENDING → VALIDE / REFUSE ; champ `refusal_reason` ; resoumission sans recréation de compte |
| Refus avec motif explicite et parcours de correction | ✅ Atteint | Page refus avec motif affiché + bouton « Modifier ma demande » |
| Chat lié aux réservations avec badge non-lus | ✅ Atteint | Conversation FK Reservation ; compteur totalNonLus ; badge BottomNav |
| Broadcast temps réel des prestataires approuvés | ✅ Atteint | Django Channels + groupes WebSocket ; FCM notification |
| Section Actualités (client + prestataire + admin) | ✅ Atteint | CRUD admin, lecture client et prestataire |
| Paiements FCFA + logos opérateurs Mobile Money | ✅ Atteint | Affichage montants FCFA ; logos Orange Money, MTN Moov, Wave dans l'admin |
| Dashboard admin KPI | ✅ Atteint | Tableau de bord avec métriques temps réel |
| Persistance des identifiants après refus | ✅ Atteint | Le prestataire réutilise son compte existant pour corriger et resoummettre |
| Notifications push FCM | ✅ Atteint | Intégration FCM pour validation, réservation, messages |
| Authentification sociale Google / Apple | ✅ Atteint | google_sign_in + sign_in_with_apple Flutter ; vérification JWT côté Django |
| Vérification d'email et réinitialisation MDP | ✅ Atteint | Token `email_verify_token` + `AppPasswordResetTokenGenerator` ; endpoints `GET /api/auth/verify-email/<token>` et `POST /api/auth/forgot-password` / `reset-password` |
| Icônes de catégories pilotées par le serveur | ✅ Atteint | API retourne `icone_url` (SVG statique Django) → `SvgPicture.network()` Flutter, sans mapping local |
| Section « Notifications intelligentes » vitrine | ✅ Atteint | Section CSS/HTML animée avec maquette téléphone et 4 types de notifications |
| Bandeau consentement cookies RGPD (vitrine) | ✅ Atteint | localStorage babifix_cookie_consent ; 3 catégories ; modal de préférences |
| Tests automatisés densifiés | 🔄 En cours | Base Django TestCase existante ; à étendre (couverture < 100 %) |
| Déploiement production | 📋 Prévu | Configuration PostgreSQL + Redis + Daphne + Nginx prévue |

### 8.2.2. Discussion de l'hypothèse de travail

L'hypothèse de travail formulée en introduction était la suivante :

> *Une plateforme combinant authentification robuste, workflow d'approbation des prestataires (avec motif de refus et parcours de correction), messagerie liée aux réservations et notifications, améliore la confiance perçue et l'opérabilité du service, sous réserve d'une architecture backend claire et de tests de parcours validés.*

Au terme de ce travail, cette hypothèse est **corroborée au niveau de la conception et du prototype** :

- Le workflow d'approbation en trois états — avec motif de refus explicite et resoumission sans recréation de compte — est pleinement implémenté et testé. Il répond directement à la lacune principale identifiée dans l'analyse comparative des solutions existantes.
- La messagerie liée aux réservations et le badge de messages non lus constituent un mécanisme de communication contextualisé qui améliore la coordination client-prestataire et réduit les ambiguïtés.
- L'architecture REST + WebSocket + FCM est cohérente, documentée et reproductible.

La **généralisation** de l'hypothèse — notamment la mesure de l'impact réel sur la confiance perçue par les utilisateurs — dépend du déploiement en production et d'une étude empirique ultérieure (enquête utilisateurs, métriques comportementales), qui sort du périmètre de ce mémoire.

### 8.2.3. Limites du travail

Trois limites principales doivent être explicitement reconnues :

1. **Environnement de développement** : la plateforme a été testée dans un environnement local (SQLite, serveur de développement Django). Les comportements en environnement de production (charge, latence réseau, comportement des opérateurs Mobile Money) restent à valider.

2. **Tests automatisés** : la couverture de tests automatisés (unitaires, intégration, E2E) est à renforcer. Les tests réalisés sont principalement manuels. Une batterie de tests automatisés avec Django TestCase et pytest-django est en cours de développement.

3. **Mesure empirique de la confiance** : l'hypothèse de travail postule une amélioration de la « confiance perçue ». Cette mesure subjective nécessite une étude utilisateurs (questionnaires, entretiens, analyse comportementale) qui n'a pas été conduite dans le cadre de ce mémoire. Elle constitue une perspective de recherche future.

---

## 8.3. Perspectives d'évolution

### 8.3.1. Intelligence artificielle et prédiction de la demande

L'intégration de l'Intelligence Artificielle constitue la perspective d'évolution la plus prometteuse pour BABIFIX. À partir de l'historique des réservations accumulé sur la plateforme, des modèles de Machine Learning pourraient être entraînés pour :

- **Prédiction de la demande** : anticiper les pics de demande par zone géographique, par type de service et par période (saisons, événements locaux), permettant à la plateforme de suggérer pro-activement à des prestataires d'augmenter leur disponibilité.
- **Recommandations personnalisées** : algorithme de filtrage collaboratif (collaborative filtering) pour recommander des prestataires non encore utilisés par un client, mais appréciés par des clients ayant un profil similaire.
- **Détection d'anomalies** : identification de comportements atypiques (abus de la plateforme, fraudes potentielles) via des algorithmes d'apprentissage non supervisé.

### 8.3.2. Optimisation dynamique des prix

Un algorithme de tarification dynamique — inspiré des modèles de surge pricing d'Uber — pourrait adapter les tarifs en fonction de l'offre et de la demande en temps réel :

- Tarifs plus élevés lors des pics de demande (fêtes nationales, saisons des pluies pour les dépannages d'urgence).
- Incitations tarifaires pour les prestataires acceptant des missions dans des zones à faible couverture.
- Transparence totale envers les clients sur les mécanismes de tarification dynamique.

### 8.3.3. Intégration Mobile Money en production

La prochaine étape immédiate est l'intégration complète de la **passerelle de paiement Mobile Money** en production pour les paiements en FCFA :

- Authentification API paiement avec clé de production.
- Gestion des webhooks de confirmation de paiement (endpoint sécurisé côté Django).
- Réconciliation des transactions en cas d'échec partiel.
- Gestion des remboursements via l'API.
- Support des quatre opérateurs principaux : Orange Money, MTN Moov Money, Wave, et Moov Africa.

### 8.3.4. CI/CD et pratiques DevOps

L'adoption d'un pipeline CI/CD (Continuous Integration / Continuous Deployment) permettra d'automatiser les tests et les déploiements :

- **GitHub Actions** : pipeline automatisé déclenché à chaque push sur la branche principale — exécution des tests Django, vérification du linting Python (flake8), build Flutter.
- **Docker** : conteneurisation de l'application Django pour garantir la reproductibilité de l'environnement de déploiement.
- **Serveur de production** : Nginx (reverse proxy) + Daphne (serveur ASGI pour Django Channels) + PostgreSQL + Redis.
- **Monitoring** : intégration de Sentry pour la gestion des erreurs en production et de Prometheus/Grafana pour les métriques applicatives.

### 8.3.5. Sécurité renforcée (OWASP Mobile)

Le renforcement de la sécurité mobile se poursuit selon les recommandations de l'**OWASP Mobile Application Security Verification Standard (MASVS)**. Le certificate pinning est déjà implémenté dans la version courante (section 7.4.4) via `CertificatePinningConfig`, ce qui prévient les attaques man-in-the-middle. Les deux axes restants à déployer avant un lancement commercial sont :

- **Chiffrement du stockage local** : les tokens JWT stockés localement sur l'appareil Flutter seront chiffrés via `flutter_secure_storage`, remplaçant le stockage en clair actuel.
- **Obfuscation du code** : le code Dart compilé en production sera obfusqué (`flutter build apk --obfuscate --split-debug-info`) pour compliquer la rétro-ingénierie.

### 8.3.6. Approfondissement de l'authentification biométrique

L'authentification biométrique est déjà intégrée dans la version courante (section 7.4.3) via `BiometricAuthService` et le package `local_auth`, permettant le déverrouillage de l'application par empreinte digitale ou Face ID sans ressaisir le mot de passe. La perspective à court terme est d'en approfondir la couverture :

- **Couplage avec `flutter_secure_storage`** : conditionner l'accès biométrique au déchiffrement du token JWT stocké localement en zone sécurisée matérielle (Keychain iOS / Keystore Android).
- **Fallback gracieux** : améliorer la gestion des appareils sans biométrie (PIN de secours) et des changements d'empreintes (révocation automatique du token biométrique).
- **Audit de session** : journaliser côté serveur les connexions par biométrie distinctement des connexions par mot de passe, pour détecter les accès anormaux.

### 8.3.7. Intégration d'une newsletter et d'un CRM léger

Le formulaire de contact du site vitrine constitue le premier point d'entrée pour les utilisateurs potentiels. À terme, il pourrait alimenter une liste de diffusion segmentée (clients / prestataires) gérée par un service d'emailing transactionnel (Mailchimp, Brevo). Des campagnes d'activation ciblées (rappel de première réservation, offres promotionnelles saisonnières, actualités plateforme) permettraient d'améliorer la rétention et le taux de conversion. Côté backend Django, un modèle `NewsletterSubscription` et un endpoint d'inscription (`POST /api/newsletter/subscribe/`) constitueraient les fondations de ce CRM léger.

### 8.3.8. Expansion géographique dans l'espace UEMOA

À moyen terme, BABIFIX pourrait s'étendre aux autres marchés de l'Union Économique et Monétaire Ouest-Africaine (UEMOA) partageant le FCFA :

- **Sénégal** : marché des services à domicile en plein développement à Dakar.
- **Mali** : forte demande en services d'artisanat et de maintenance.
- **Burkina Faso** : marché urbain en croissance à Ouagadougou.

Cette expansion nécessiterait d'adapter les opérateurs Mobile Money disponibles par pays (Wave est dominant au Sénégal, différents opérateurs au Mali) et de localiser l'interface utilisateur.

---

*[Fin de la Troisième Partie]*

---

## CONCLUSION GÉNÉRALE

### Synthèse des contributions et réponse à la question de recherche

Ce mémoire a posé la question de recherche suivante : **dans quelle mesure une plateforme numérique multi-acteurs, intégrant un mécanisme de gouvernance par validation administrative et une communication temps réel liée aux réservations, peut-elle pallier les insuffisances de confiance et de traçabilité qui freinent le développement du secteur des services à domicile en Côte d'Ivoire ?**

L'hypothèse de travail formulée en réponse était que la combinaison de trois mécanismes — la validation obligatoire des prestataires avec motif de refus transparent, la messagerie instantanée contextuelle adossée aux réservations, et l'adaptation native aux modes de paiement locaux (FCFA, Mobile Money) — constitue une proposition de valeur différenciante, techniquement réalisable et adaptée au contexte socio-économique ivoirien.

L'ensemble du travail présenté dans ce mémoire vient confirmer cette hypothèse à l'échelle d'un prototype fonctionnel. La **Première Partie** a établi le cadre contextuel et théorique : l'analyse de marché a montré que 70 % des adultes ivoiriens utilisent le Mobile Money et que 90 % des petits prestataires de services opèrent hors de tout cadre formel, créant un besoin objectif de numérisation et de confiance que les plateformes existantes — locales (Yako Services, Gombo, OnDjossi), africaines (Lynk, SweepSouth) ou internationales (TaskRabbit, Thumbtack, Bark.com) — ne satisfont pas pour le marché ivoirien. La **Deuxième Partie** a formalisé les besoins fonctionnels et non fonctionnels : douze besoins fonctionnels (BF-01 à BF-12), cinq exigences non-fonctionnelles mesurables, et dix diagrammes UML couvrant les cas d'utilisation, les classes, les séquences et les activités. La **Troisième Partie** a présenté la réalisation concrète : une architecture Django (API REST + WebSocket Channels + Redis) servant deux interfaces web en templates Django (vitrine et panneau admin) et deux applications mobiles Flutter (client et prestataire), le tout intégrant Firebase Cloud Messaging pour les notifications push et une gestion des paiements en FCFA.

Les huit versions livrées (v1 à v8) ont implémenté progressivement l'ensemble des fonctionnalités : workflow prestataire (soumission → attente → acceptation/refus motivé → resoumission sans recréation de compte), chat temps réel lié aux réservations avec badge de messages non lus, diffusion en temps réel des prestataires approuvés via WebSocket, tableau de bord administrateur avec KPI, intégration des logos Mobile Money et section Actualités. Des modules complémentaires ont également été réalisés : authentification sociale Google et Apple avec vérification JWT côté serveur, vérification d'adresse e-mail, système d'icônes de catégories piloté par le serveur (champ `icone_url` Django → `SvgPicture.network()` Flutter, sans mapping local codé en dur), et enrichissement du site vitrine avec une section « Notifications intelligentes » et un bandeau de consentement aux cookies conforme au RGPD.

### Revendication et limites explicites

Conformément aux directives méthodologiques de l'IIT (guide § 9), la revendication de ce mémoire est formulée avec précision : **BABIFIX est un prototype fonctionnel de plateforme de services à domicile répondant aux objectifs fonctionnels des versions 1 à 8, corroborant l'hypothèse selon laquelle les mécanismes de gouvernance et de communication intégrés constituent un levier crédible de confiance numérique dans le contexte ivoirien.**

Cette revendication s'accompagne de trois limites explicites. Premièrement, BABIFIX n'a pas encore été déployé en production sur un serveur public ; les performances mesurées correspondent à un environnement de développement local. Deuxièmement, l'intégration de l'API de paiement Mobile Money pour le traitement effectif des paiements est prévue mais non finalisée dans la version courante. Troisièmement, la couverture de tests automatisés reste partielle : les tests fonctionnels manuels ont validé les parcours principaux, mais les tests de charge (Locust/k6) et les audits de sécurité formels (OWASP ZAP) restent à conduire avant un lancement commercial.

### Perspectives de valorisation et d'impact

Au-delà du cadre académique, BABIFIX représente une opportunité de valorisation concrète. À court terme, le déploiement sur un serveur Nginx/Daphne avec PostgreSQL et Redis permettrait de lancer une version bêta auprès d'un panel de prestataires et de clients dans le Grand Abidjan, constituant ainsi une validation par le marché. À moyen terme, l'intégration de l'intelligence artificielle pour la recommandation personnalisée de prestataires et la tarification dynamique renforcerait la compétitivité de la plateforme. À long terme, l'expansion vers les marchés de l'espace UEMOA — Sénégal, Mali, Burkina Faso — en adaptant les opérateurs Mobile Money et les contextes linguistiques offrirait un débouché régional significatif.

Ce projet illustre la capacité des développeurs ivoiriens à concevoir des solutions numériques ancrées dans les réalités locales, utilisant des technologies ouvertes (Django, Flutter, Firebase) pour répondre à des besoins socio-économiques concrets. En formalisant et en digitalisant la relation entre prestataires informels et clients particuliers, BABIFIX contribue modestement mais concrètement à l'objectif plus large de la transformation numérique de la Côte d'Ivoire.

---

## RÉFÉRENCES BIBLIOGRAPHIQUES

*(Style Chicago auteur-date — ordre alphabétique)*

Abou El-Seoud, M. S., I. A. T. F. Taj-Eddin, N. Seddiek, et al. 2022. "Smart application for house condition survey." *ScienceDirect — Computers in Human Behavior Reports* 7 : 100211.

Adomavicius, Gediminas, et Alexander Tuzhilin. 2005. "Toward the next generation of recommender systems: A survey of the state-of-the-art and possible extensions." *IEEE Transactions on Knowledge and Data Engineering* 17 (6) : 734–749.

Batiz-Lazo, Bernardo, et Leonidas Efthymiou. 2019. *The Book of Payments: Historical and Contemporary Views on the Cashless Society.* Palgrave Macmillan.

Bobadilla, Jesús, Fernando Ortega, Antonio Hernando, et Abraham Gutiérrez. 2013. "Recommender systems survey." *Knowledge-Based Systems* 46 : 109–132.

Chen, Wei, et Hui Wang. 2022. "Platform-based service ecosystems: A conceptual framework and research agenda." *Journal of Information Systems* 36 (2) : 45–78.

Codagnone, Cristiano, Fabienne Abadie, et Federico Biagi. 2016. *The Passions and the Interests: Unpacking the 'Sharing Economy'.* JRC Science for Policy Report. Luxembourg : Publications Office of the European Union.

Djankov, Simeon, et Eva (Yiwen) Zhang. 2021. *Businesses in the Informal Economy.* World Bank Policy Research Working Paper 9515.

Heeks, Richard. 2018. *Information and Communication Technology for Development (ICT4D).* Abingdon : Routledge.

Josang, Audun, Roslan Ismail, et Colin Boyd. 2007. "A survey of trust and reputation systems for online service provision." *Decision Support Systems* 43 (2) : 618–644.

Khan, Shahriar, et Mohammad Rahman. 2017. "Mobile and web based system for maintenance and repair." *Arabian Journal for Science and Engineering (AJSE)* 42 (2) : 735–748.

Kuhn, Kristine M., et Amir Maleki. 2017. "Micro-entrepreneurs, dependent contractors, and instaserfs: Understanding online labor platform workforces." *Academy of Management Perspectives* 31 (3) : 183–200.

Kumar, Vikas, et Ajay Singh. 2023. "Mobile payment adoption in developing markets: Evidence from West Africa." *International Journal of Electronic Commerce (IJEC)* 27 (1) : 22–56.

Marikyan, Davit, Savvas Papagiannidis, et Eleftherios Alamanos. 2017. "A systematic review of the smart home literature: A user perspective." *Technological Forecasting and Social Change* 138 : 139–154. ScienceDirect.

Martin, Jean-Pierre, et Alain Dubois. 2024. "Cross-platform mobile development: Flutter vs React Native — a performance benchmark." *IEEE Software* 41 (1) : 60–68.

Mbiti, Isaac, et David N. Weil. 2016. "Mobile banking: The impact of M-Pesa in Kenya." Dans *African Successes, Volume III: Modernization and Development,* édité par Sebastian Edwards, Simon Johnson, et David N. Weil, 247–293. Chicago : University of Chicago Press.

Moussa, Mohamed, et Sidi Moussa. 2021. "Digital transformation of SMEs in sub-Saharan Africa: Constraints and opportunities." *Technology in Society* 64 : 101509.

Mularczyk, Szymon, Piotr Górski, et Rafał Kasprzak. 2021. "Flutter vs React Native: A comparative study on cross-platform mobile development." Dans *Proceedings of the 2021 IEEE International Conference on Computer Science and Engineering,* 214–220. IEEE.

Pop, Cornelia-Romaniţa, Ioan Salomie, Tudor Cioara, Ionut Anghel, et Marcel Antal. 2020. "Performance evaluation of cross-platform mobile application development using React Native and Flutter." *Software: Practice and Experience* 50 (12) : 2278–2300. Wiley.

Resnick, Paul, Neophytos Iacovou, Mitesh Suchak, Peter Bergstrom, et John Riedl. 2000. "Reputation systems: Facilitating trust in internet interactions." *Communications of the ACM* 43 (12) : 45–48.

Ricci, Francesco, Lior Rokach, et Bracha Shapira, éds. 2022. *Recommender Systems Handbook.* 3e éd. New York : Springer.

Sampé, Joan, Gemma Muntaner-Perich, Jordi Garcia-Almiñana, et Marc Solé. 2020. "Performance evaluation of serverless computing platforms for the IoT." *IEEE Transactions on Cloud Computing* 10 (4) : 2775–2788.

SikaFinance. 2024. "Mobile Money en Côte d'Ivoire : 24 millions de comptes actifs." SikaFinance.com. Publié en ligne.

SocialNetLink. 2025. "Bilan du mobile money en Afrique de l'Ouest 2024." SocialNetLink.net. Publié en ligne.

Villari, Massimo, Maria Fazio, Schahram Dustdar, Omer Rana, et Rajiv Ranjan. 2016. "Osmotic computing: A new paradigm for edge/cloud integration." *IEEE Cloud Computing* 3 (6) : 76–83.

WeAreTech.ci. 2024. "Panorama des startups tech ivoiriennes de services à domicile." WeAreTech.ci. Publié en ligne.

World Bank. 2022. *Financial Inclusion in Sub-Saharan Africa: Closing the Gap.* Washington, DC : The World Bank Group.

---

## ANNEXES

### Annexe A — Glossaire des termes techniques et acronymes

| Terme | Définition |
|---|---|
| **API** (*Application Programming Interface*) | Interface de programmation permettant la communication entre applications via des requêtes HTTP standardisées. Dans BABIFIX, l'API REST expose les endpoints du backend Django aux applications Flutter. |
| **ARTCI** | Autorité de Régulation des Télécommunications et des TIC de Côte d'Ivoire. Organisme régulateur ivoirien auquel fait référence la Loi n°2013-450 sur la protection des données personnelles. |
| **ASGI** (*Asynchronous Server Gateway Interface*) | Interface de serveur asynchrone Python, successeur de WSGI, supportant les WebSockets. Django Channels repose sur ASGI via Daphne. |
| **CI/CD** (*Continuous Integration / Continuous Deployment*) | Pipeline automatisé qui teste et déploie le code à chaque commit. Prévu dans les perspectives d'évolution de BABIFIX (GitHub Actions). |
| **DRF** (*Django REST Framework*) | Boîte à outils Python pour construire des API RESTful au-dessus de Django, utilisée pour tous les endpoints BABIFIX. |
| **FCFA** (*Franc CFA*) | Franc de la Communauté Financière Africaine. Monnaie officielle de la Côte d'Ivoire et des pays de l'UEMOA, utilisée nativement dans les transactions BABIFIX. |
| **FCM** (*Firebase Cloud Messaging*) | Service Google de notifications push multiplateformes (iOS, Android), utilisé dans BABIFIX pour notifier clients et prestataires. |
| **Flutter** | Framework Google open-source basé sur le langage Dart, permettant le développement d'applications mobiles cross-platform (iOS/Android) à partir d'une seule base de code. |
| **HTTP/HTTPS** (*HyperText Transfer Protocol / Secure*) | Protocole de communication web. HTTPS chiffre les échanges via TLS/SSL, obligatoire pour toutes les communications BABIFIX en production. |
| **JWT** (*JSON Web Token*) | Standard de jeton d'authentification stateless. BABIFIX utilise SimpleJWT (Django) pour authentifier les requêtes des applications Flutter. |
| **KPI** (*Key Performance Indicator*) | Indicateur clé de performance. Le tableau de bord administrateur BABIFIX affiche plusieurs KPI : nombre de réservations, taux de validation, revenus, utilisateurs actifs. |
| **MVP** (*Minimum Viable Product*) | Version minimale d'un produit permettant de valider les hypothèses clés avec des utilisateurs réels, avant un développement complet. |
| **MVVM** (*Model-View-ViewModel*) | Pattern d'architecture UI séparant logique métier (ViewModel) et interface (View), recommandé pour les applications Flutter. |
| **OWASP** (*Open Web Application Security Project*) | Organisation internationale qui publie des recommandations de sécurité applicative, notamment le Mobile Top 10 pour les applications mobiles. |
| **Redis** | Système de stockage de données en mémoire (clé-valeur), utilisé comme broker de messages pour Django Channels et comme couche de cache dans BABIFIX. |
| **REST** (*Representational State Transfer*) | Style d'architecture pour les API web, utilisant les méthodes HTTP (GET, POST, PUT, DELETE) et les ressources identifiées par des URLs. |
| **RGPD** (*Règlement Général sur la Protection des Données*) | Règlement européen 2016/679 sur la protection des données personnelles, pris comme référence internationale par analogie avec la Loi ivoirienne n°2013-450. |
| **SQLite** | Base de données embarquée légère, utilisée dans l'environnement de développement BABIFIX. |
| **TLS** (*Transport Layer Security*) | Protocole de chiffrement des communications réseau, base du HTTPS et du WSS. |
| **UEMOA** (*Union Économique et Monétaire Ouest-Africaine*) | Union regroupant 8 pays d'Afrique de l'Ouest partageant le FCFA : Bénin, Burkina Faso, Côte d'Ivoire, Guinée-Bissau, Mali, Niger, Sénégal, Togo. |
| **UML** (*Unified Modeling Language*) | Langage de modélisation graphique standardisé (OMG) pour décrire les systèmes logiciels. BABIFIX utilise 4 types de diagrammes UML : cas d'utilisation, classes, séquences, activités. |
| **WebSocket / WSS** | Protocole de communication bidirectionnel et persistant sur TCP. WSS désigne le WebSocket sécurisé (chiffré via TLS). Django Channels gère les connexions WSS dans BABIFIX pour le chat temps réel. |

---

### Annexe B — Structure du projet BABIFIX_BUILD

La base de code BABIFIX est organisée en un dépôt unique `BABIFIX_BUILD/` structuré en quatre projets distincts :

```
BABIFIX_BUILD/
│
├── babifix_admin_django/           # Backend Django principal
│   ├── config/
│   │   ├── settings.py             # Django 5.2, JWT (SimpleJWT), Channels, FCM
│   │   ├── urls.py                 # Routage API REST + WebSocket
│   │   ├── asgi.py                 # Point d'entrée ASGI (Django Channels)
│   │   └── routing.py             # WebSocket URL routing (Django Channels)
│   ├── adminpanel/                 # Application unique contenant tout
│   │   ├── models.py               # User, Client, Prestataire, Service, Reservation, Paiement, etc.
│   │   ├── views.py                # API REST (ViewSets DRF)
│   │   ├── serializers.py          # Sérialisation DRF
│   │   ├── consumers.py            # WebSocket : ChatConsumer, ClientEventsConsumer, PrestataireEventsConsumer
│   │   ├── routing.py              # WebSocket URL routing
│   │   ├── admin.py                # Admin Django intégré
│   │   ├── migrations/            # Migrations Django (SQLite dev / PostgreSQL prod)
│   │   └── templates/
│   │       └── adminpanel/        # Interface admin web (HTML/Bootstrap)
│   │           ├── dashboard.html  # KPI : réservations, revenus, utilisateurs
│   │           ├── prestataires_liste.html
│   │           └── validation_form.html
│   ├── manage.py
│   └── requirements.txt            # Django 5.2, DRF, djangorestframework-simplejwt, channels, firebase-admin, cryptography
│
├── babifix_vitrine_django/         # Site web vitrine public
│   ├── config/
│   │   ├── settings.py
│   │   └── urls.py
│   ├── vitrine/
│   │   ├── views.py                # Pages : index, mentions legales, contact
│   │   ├── urls.py
│   │   └── templates/
│   │       └── vitrine/
│   │           ├── index.html      # Hero, catégories, témoignages, FAQ
│   │           ├── base.html
│   │           └── static/
│   └── manage.py
│
├── babifix_client_flutter/         # Application Flutter Client (iOS/Android)
│   ├── lib/
│   │   ├── main.dart               # 5745 lignes — ClientHomePage, navigation, state
│   │   ├── babifix_*.dart          # Design system, API config, FCM, money, user store
│   │   ├── json_utils.dart
│   │   ├── category_icon_mapper.dart  # Fichier conservé (non utilisé pour l'affichage — icônes servies via icone_url Django)
│   │   ├── features/                # Écrans par fonctionnalité
│   │   │   ├── auth/               # Onboarding (Lottie), Auth, ForgotPassword, Biometric
│   │   │   ├── home/                # ActualiteDetailScreen
│   │   │   ├── services/           # ServiceDetailScreen
│   │   │   ├── booking/            # BookingFlowScreen
│   │   │   ├── chat/               # MessagesScreen, ChatRoomScreen
│   │   │   ├── profile/            # EditProfileScreen
│   │   │   ├── notifications/      # NotificationsScreen
│   │   │   ├── providers/          # ProviderProfileScreen
│   │   │   └── payment/            # PaymentScreen
│   │   ├── shared/
│   │   │   ├── widgets/            # babifix_button, babifix_loading_shimmer, babifix_loading_indicator, etc.
│   │   │   ├── services/           # HapticsService, RealTimeSyncService
│   │   │   ├── in_app_notifications.dart
│   │   │   ├── offline_cache.dart
│   │   │   └── connectivity_banner.dart
│   │   ├── models/                 # client_models.dart
│   │   └── theme/                  # app_theme.dart
│   ├── assets/
│   │   ├── animations/             # Lottie JSON : providers.json, booking.json, payment.json
│   │   └── illustrations/
│   └── pubspec.yaml                # firebase_messaging, lottie, flutter_secure_storage, etc.
│
├── babifix_prestataire_flutter/    # Application Flutter Prestataire (iOS/Android)
│   ├── lib/
│   │   ├── main.dart
│   │   ├── babifix_*.dart
│   │   ├── features/               # Écrans par fonctionnalité
│   │   │   ├── auth/               # Onboarding, Auth, BiometricLogin
│   │   │   ├── home/               # ProviderHomeScreen
│   │   │   ├── requests/           # RequestsScreen
│   │   │   ├── chat/
│   │   │   ├── profile/
│   │   │   └── settings/
│   │   └── shared/
│   │       ├── auth_utils.dart     # FlutterSecureStorage pour tokens JWT
│   │       └── services/           # HapticsService
│   └── pubspec.yaml
│
└── UML_DIAGRAMMES/                  # Diagrammes UML PlantUML (10 fichiers)
    ├── DIAGRAMME/
    │   ├── 01_use_case_diagramme.puml
    │   ├── 02_class_diagramme.puml
    │   ├── 03_sequence_client_reservation.puml
    │   └── ... (total 10 diagrammes)
    └── EXPORTS/                     # SVG exportés
```

---

### Annexe C — Guide d'insertion des captures d'écran

Les captures d'écran suivantes doivent être insérées dans la version Word finale du mémoire, aux emplacements indiqués par les balises `[Capture X]` dans le Chapitre 7. Les fichiers d'images sont disponibles dans le dossier `BABIFIX_BUILD/screenshots/` ou peuvent être générés par exécution des applications en mode développement.

| Capture | Description | Chapitre | Emplacement suggéré |
|---|---|---|---|
| Capture A | Tableau de bord administrateur — KPI (réservations, revenus FCFA, utilisateurs actifs) | 7.3.3 | Après la description du Dashboard KPI |
| Capture B | Formulaire de validation prestataire — champ motif de refus visible | 7.3.3 | Après la description du formulaire validation/refus |
| Capture C | App Flutter Client — écran liste des prestataires par catégorie avec notes | 7.3.1 | Après la description de l'écran d'accueil client |
| Capture D | App Flutter Prestataire — écran PendingScreen (attente validation, UI premium) | 7.3.2 | Après la description de PendingScreen |
| Capture E | App Flutter Prestataire — écran RefusedScreen (motif de refus + bouton resoumission) | 7.3.2 | Après la description de RefusedScreen |
| Capture F | App Flutter Client — écran ChatScreen avec badge messages non lus | 7.3.1 | Après la description du chat client |
| Capture G | Site vitrine Django — page d'accueil (Hero + catégories de services) | 7.3.4 | Après la description du site vitrine |
| Capture H | Panneau admin — liste des opérateurs Mobile Money FCFA (Orange, MTN, Wave) | 7.3.3 | Après la description de la gestion des paiements |

**Instructions d'insertion dans Word :**
1. Placer chaque capture à l'emplacement indiqué dans le tableau ci-dessus.
2. Centrer l'image sur la page, largeur recommandée : 14 cm.
3. Ajouter la légende sous l'image avec le format : *Figure X — [Description]*, en italique, centré, police Times New Roman 10pt.
4. Mettre à jour la **Liste des figures** (page V des liminaires) avec les numéros de page définitifs.
5. S'assurer que la résolution des captures est d'au moins 150 DPI pour une impression de qualité.

---

### Annexe D — Répertoire des diagrammes UML

Les dix diagrammes UML du projet BABIFIX ont été réalisés en PlantUML et exportés au format SVG. Ils sont disponibles dans le dossier `BABIFIX/UML_DIAGRAMMES/DIAGRAMME/`.

| N° | Fichier PlantUML | Export SVG | Type | Description |
|---|---|---|---|---|
| 1 | `01_use_case_diagramme.puml` | `CAS D'UTILISATION COMPLET.svg` | Cas d'utilisation | Vue générale des 3 acteurs (Client, Prestataire, Admin) et de leurs interactions avec les 3 systèmes BABIFIX |
| 2 | `02_class_diagramme.puml` | `CLASSE COMPLET.svg` | Classes | Modèle de données complet : classe abstraite Utilisateur, 8 entités métier, 4 énumérations |
| 3 | `03_sequence_client_reservation.puml` | `SEQUENCE CLIENT.svg` | Séquence | Flux de réservation client : JWT/Django API → sélection → réservation → paiement Mobile Money |
| 4 | `04_sequence_prestataire_inscription.puml` | `SEQUENCE PRESTATAIRE.svg` | Séquence | Inscription prestataire : soumission CNI → notification admin → validation/refus → FCM push |
| 5 | `05_sequence_admin_validation.puml` | `SEQUENCE ADMIN.svg` | Séquence | Validation prestataire par l'admin : vérification CNI → décision → notification FCM |
| 6 | `06_sequence_paiement_especes.puml` | `SEQUENCE PAIEMENT.svg` | Séquence | Flux paiement en espèces avec confirmation manuelle par l'admin |
| 7 | `07_activite_client_reservation.puml` | `ACTIVITE CLIENT.svg` | Activité | Activités du client dans le processus de réservation (couloirs de nage) |
| 8 | `08_activite_prestataire_validation.puml` | `ACTIVITE PRESTATAIRE.svg` | Activité | Processus d'inscription et de validation du prestataire |
| 9 | `09_activite_admin_gestion.puml` | `ACTIVITE ADMIN.svg` | Activité | Gestion administrative : validation, modération, actualités, statistiques |
| 10 | `10_activite_notation.puml` | `ACTIVITE NOTATION.svg` | Activité | Processus de notation et d'évaluation après prestation |

**Instructions d'insertion dans Word :**
Pour chaque diagramme référencé dans le corps du mémoire (Chapitre 5), ouvrir le fichier SVG correspondant, le copier dans Word en tant qu'image vectorielle ou le convertir en PNG (300 DPI recommandé) avant insertion. Chaque figure doit être légendée selon le format standard du mémoire.

---

*[Fin du mémoire]*

*Document rédigé conformément au guide de rédaction de l'Institut Ivoirien de Technologie (IIT), Département Informatique.*
*Style de citation : Chicago auteur-date. Mise en forme recommandée pour Word : Times New Roman 12pt, marges 2,5 cm, interligne 1,5.*


