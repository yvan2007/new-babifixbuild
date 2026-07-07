# 🎓 BABIFIX — Mémoire de soutenance
## Discours d'introduction, questions du jury & réponses préparées

> Document de préparation. Tout est ici : l'accroche, le plan, les questions-pièges
> (même les plus complexes) avec leurs réponses, le script de démonstration, et les
> points de sécurité à maîtriser. **À connaître ; surtout l'accroche par cœur.**

---

# 🎤 PARTIE 1 — DISCOURS D'INTRODUCTION

## 1. L'accroche (l'histoire qui capte tout de suite)

> « Monsieur le Président du jury, Mesdames et Messieurs les membres du jury, bonjour.
>
> Avant de vous parler de mon travail, permettez-moi de vous poser une situation toute simple.
>
> **Imaginez : vous venez de construire votre maison.** Tout est neuf, tout est beau. Et puis un matin, un robinet se met à fuir. L'eau coule, le carrelage commence à se gâter. Vous avez besoin d'un plombier — *maintenant*, pas dans trois jours.
>
> Que faites-vous ? Vous appelez un cousin, qui appelle un ami, qui connaît "quelqu'un qui fait ça bien". On vous donne un numéro. Vous appelez. L'homme arrive, mais vous ne savez pas s'il est sérieux. Vous ne connaissez pas son prix avant qu'il ait fini. Et s'il fait du mauvais travail, vous n'avez aucun recours.
>
> **Cette scène, des millions d'Ivoiriens la vivent chaque semaine.** »

## 2. Le problème (nommer la douleur)

> « Aujourd'hui, en Côte d'Ivoire, trouver un bon prestataire à domicile — un plombier, un électricien, une aide-ménagère, un climaticien — repose presque entièrement sur le bouche-à-oreille.
>
> D'un côté, **le client** n'a aucune garantie : ni sur la compétence, ni sur le prix, ni sur la sécurité de son paiement.
>
> De l'autre côté, **le prestataire compétent** reste invisible. Il a le savoir-faire, mais pas les moyens de se faire connaître, de prouver son sérieux, ni d'être payé en confiance.
>
> Entre les deux, il manque un pont. Ce pont, c'est **BABIFIX**. »

## 3. La présentation de la solution

> « BABIFIX est une **place de marché numérique de services à domicile**, pensée pour le contexte ivoirien.
>
> Concrètement, c'est un **écosystème de trois applications connectées** :
> - une **application mobile pour le client**, qui géolocalise les prestataires autour de lui, demande un devis, et paie en toute sécurité ;
> - une **application mobile pour le prestataire**, qui reçoit les demandes, propose ses devis et suit ses revenus ;
> - et un **panneau d'administration web**, qui supervise l'ensemble : validation des prestataires, gestion des litiges, suivi des paiements.
>
> Le tout repose sur un **paiement sécurisé par Mobile Money** — Orange, MTN, Wave, Moov — avec un mécanisme de *séquestre* : **l'argent du client est bloqué et n'est versé au prestataire qu'une fois la prestation confirmée.** Personne ne peut tricher. »

## 4. Le pont vers le stage (SNDI)

> « Cette vision, je ne l'ai pas construite seul ni dans le vide. Durant mon stage de trois mois à la **SNDI**, à Cocody Danga, j'ai pu observer de près comment se conçoivent les systèmes d'information à grande échelle, comment on pense la fiabilité, la sécurité et le service rendu à l'utilisateur. Cette expérience a nourri et renforcé chaque choix technique de BABIFIX. »

## 5. L'annonce du plan

> « Au cours de cette présentation, je vous propose de :
> - d'abord, revenir sur **le problème et le contexte du marché** ivoirien ;
> - ensuite, vous présenter **les choix techniques et l'architecture** de la solution ;
> - puis vous faire une **démonstration concrète** du fonctionnement ;
> - et enfin, partager **les difficultés rencontrées, les résultats obtenus et les perspectives** d'évolution.
>
> Je vous remercie de votre attention, et je commence. »

## ✂️ Version courte de l'intro (moins de 2 min)

> « Mesdames et Messieurs du jury, bonjour. Imaginez : vous venez de construire votre maison, et un matin, un robinet fuit. Vous avez besoin d'un plombier maintenant. Qui appelez-vous ? Un cousin, un ami, "quelqu'un qui fait ça bien"… sans connaître ni son sérieux, ni son prix, ni aucune garantie.
>
> Cette difficulté, des millions d'Ivoiriens la vivent. D'un côté, des clients sans repère ; de l'autre, de bons prestataires restés invisibles. Entre les deux, il manque un pont. Ce pont, c'est **BABIFIX** : une place de marché de services à domicile, avec trois applications connectées et un paiement Mobile Money sécurisé, où l'argent n'est versé qu'une fois le travail confirmé.
>
> C'est cette solution que j'ai l'honneur de vous présenter aujourd'hui. »

## 💡 Conseils pour le jour J

| Élément | Conseil |
|---|---|
| **L'accroche** | Marque un **petit silence** après « *l'eau coule, le carrelage se gâte* ». Laisse le jury vivre la scène. |
| **Le regard** | Regarde **un membre du jury dans les yeux** sur l'accroche, comme si tu lui racontais à lui. |
| **Le rythme** | Parle **lentement**. Une bonne intro = ~2 minutes, pas 45 secondes pressées. |
| **Le mot "pont"** | C'est ton image forte. Reviens-y à la fin : *« BABIFIX, c'est le pont que j'ai voulu bâtir. »* |
| **La posture** | Tiens-toi droit, mains visibles. Ne lis pas — connais l'accroche **par cœur**. |

---

# 🛡️ PARTIE 2 — QUESTIONS DU JURY & RÉPONSES

> **Règle d'or** : si tu ne sais pas, ne mens jamais. Dis *« C'est une excellente remarque, c'est une piste d'amélioration que j'ai identifiée »*. Un jury respecte l'honnêteté, pas le bluff.

## 🔴 A. Responsabilité & juridique (les plus redoutées)

### Q1 — « Si un prestataire casse quelque chose chez le client pendant l'intervention, qui est responsable ? Sont-ils assurés ? »
> « Excellente question, c'est un point central de la confiance. Dans la version actuelle, BABIFIX joue le rôle d'**intermédiaire de mise en relation**, comme Uber ou Jumia : la responsabilité contractuelle reste entre le client et le prestataire. **Mais** j'ai conçu trois garde-fous : d'abord, **chaque prestataire est vérifié** (pièce d'identité, KYC) avant d'être validé — on sait exactement qui il est. Ensuite, le **système de litige intégré** permet au client de signaler un dommage, joindre des photos, et bloquer le paiement. Enfin, dans ma feuille de route, je prévois un **partenariat d'assurance** : une **micro-assurance** prélevée sur la commission de chaque prestation, alimentant un fonds de garantie "dégâts". C'est le modèle des plateformes matures. »

**Compagnies à citer (réelles, Côte d'Ivoire) :** NSIA Assurances, SUNU Assurances, Atlantique Assurances, Allianz CI, SAHAM (Sanlam).
**Mot fort à placer :** « micro-assurance ».

### Q2 — « Que se passe-t-il en cas de litige sur la qualité du travail ? »
> « Le mécanisme de **séquestre** est ma réponse. L'argent du client est bloqué sur la plateforme, il n'est **pas** versé automatiquement. Tant que le client n'a pas confirmé que la prestation est satisfaisante, les fonds restent gelés. En cas de désaccord, le client ouvre un litige depuis l'application, l'administrateur le voit dans son tableau de bord, examine les preuves des deux côtés (le prestataire a aussi un **droit de réponse**), et tranche : remboursement, versement partiel, ou versement total. »

### Q3 — « Un prestataire pourrait-il contourner la plateforme et se faire payer directement en cash pour éviter la commission ? »
> « C'est le risque numéro un de toutes les marketplaces, et je ne prétends pas l'éliminer à 100 %. Ma stratégie est de **rendre la plateforme plus intéressante que la fraude** : le prestataire qui passe par BABIFIX gagne une **visibilité**, un **historique d'avis** qui lui ramène de nouveaux clients, des **reçus professionnels**, et un **statut premium** qui réduit sa commission. Celui qui contourne perd tout ça. La confiance et la réputation deviennent sa vraie monnaie. »

### Q3-bis (TOURNURE PIÈGE) — « Mais après acceptation, le prestataire a l'adresse du client… il peut y aller directement sans faire de devis ! »
> « Vous avez raison de soulever ce risque — c'est le défi de **toute** plateforme de mise en relation : aucune technologie n'empêche physiquement deux personnes de se rencontrer. **Ma réponse n'est donc pas technique, elle est stratégique :** je fais en sorte que le prestataire ait **plus à perdre qu'à gagner** en court-circuitant.
>
> **Premièrement**, l'adresse complète n'est révélée qu'**après** acceptation **dans l'application** — j'ai donc déjà une trace qu'il a pris cette demande.
>
> **Deuxièmement**, s'il court-circuite, il perd **tous ses avantages** : pas d'**avis client** (or les avis ramènent ses futurs clients), pas d'**historique de missions**, pas de **badge de confiance**, pas d'éligibilité **premium**.
>
> **Troisièmement**, côté client : payer hors plateforme, c'est **perdre la garantie du séquestre** — plus de paiement sécurisé, plus de recours en cas de dégât. Le client a donc lui aussi **intérêt à rester**.
>
> Autrement dit, la fraude est possible une fois, mais **perdante sur le long terme pour les deux parties**. La plateforme ne retient pas les gens par la contrainte, mais par la **valeur**. »
>
> *(Bonus :)* « À terme, je pourrais suspendre automatiquement un prestataire dont les missions sont systématiquement annulées juste après acceptation — un signal de court-circuitage détectable. »

## 🟠 B. Questions techniques pointues

### Q4 — « Pourquoi trois applications séparées plutôt qu'une seule ? »
> « Parce que les besoins du client et du prestataire sont **fondamentalement différents**. Le client cherche, compare, paie. Le prestataire reçoit, devise, exécute. Fusionner aurait alourdi chaque app de fonctions inutiles à l'un ou l'autre. Trois applications dédiées = **expérience plus claire** et **code plus maintenable**. Le panneau admin est web car la supervision se fait sur grand écran. »

### Q5 — « Comment garantissez-vous la sécurité des paiements Mobile Money ? »
> « Sur trois niveaux. **Un** : je ne stocke **jamais** les identifiants Mobile Money du client — le paiement est délégué à un agrégateur sécurisé (GeniusPay) qui redirige vers l'app Orange/MTN/Wave/Moov ; le client seul tape son code. **Deux** : chaque notification de paiement entrante est **vérifiée par signature cryptographique HMAC-SHA256** — impossible de simuler un faux paiement sans la clé secrète partagée. **Trois** : une **clé d'idempotence** unique par transaction empêche tout double débit. »

**Pour expliquer HMAC simplement :** « L'agrégateur et moi partageons une clé secrète. Avec elle, il calcule une empreinte unique (signature) collée au message. Je recalcule la même de mon côté : si elles correspondent, le message est authentique ; sinon, je le rejette. »

### Q6 — « Comment trouvez-vous les prestataires "autour" du client ? »
> « Avec les **coordonnées GPS** du client et de chaque prestataire. La recherche se fait par **rayon adaptatif** : d'abord 5 km ; s'il n'y a pas assez de prestataires disponibles, on élargit à 15, puis 30, puis 50 km. Le client les voit comme des **points sur une carte**, colorés selon la distance. Il y a toujours une réponse, même en zone peu dense. »

### Q7 — « Comment protégez-vous la vie privée du client ? Le prestataire voit-il l'adresse exacte tout de suite ? »
> « Non, et c'est volontaire. Tant qu'aucun prestataire n'a accepté la demande, **l'adresse précise est masquée** : il ne voit que le quartier, la ville, et une position GPS volontairement approximative (arrondie à ~1 km). **L'adresse exacte — la rue, le repère — n'est révélée qu'au prestataire qui accepte la mission.** »

### Q7-bis — « Et avant l'accord, peuvent-ils communiquer ? »
> « Non. **Tant qu'il n'y a pas d'accord** — c'est-à-dire tant que le prestataire n'a pas accepté la demande — **ni le client ni le prestataire ne peuvent s'appeler ou s'envoyer un message**. Cette règle est appliquée **côté serveur** (impossible à contourner) sur les trois portes : lancer un appel, rejoindre une room, envoyer un message. Cela protège le prestataire du démarchage avant qu'il se soit engagé. »

### Q8 — « Que se passe-t-il si le serveur tombe pendant un paiement ? »
> « Le paiement n'est jamais validé tant que je n'ai pas reçu la confirmation signée de l'agrégateur. Au redémarrage, un **processus de surveillance** (watcher) reprend les paiements en attente et réinterroge l'agrégateur pour synchroniser leur statut. Côté application, si le client ferme l'app pendant un paiement Mobile Money, **la reprise est automatique** : à la réouverture, le suivi du paiement reprend là où il en était. Aucun paiement perdu, aucun compté deux fois. »

### Q9 — « Comment fonctionne le système d'appel ? Est-ce un vrai appel ? »
> « C'est un **vrai appel audio temps réel**, via LiveKit. Le serveur génère un **jeton signé** (la clé secrète n'est jamais dans l'app), crée une "room", puis **fait sonner le destinataire par notification push** — même application fermée, grâce à un canal Android haute priorité. Le destinataire **décroche**, reçoit son propre jeton, rejoint la même room, et les deux **communiquent en direct**. Le micro est réellement publié dans la session. »

## 🟡 C. Modèle économique

### Q10 — « Comment l'entreprise gagne-t-elle de l'argent ? »
> « Par une **commission** sur chaque prestation réalisée — entre 15 et 20 % selon la catégorie. Elle est **déduite de la part du prestataire**, jamais ajoutée au prix du client : le client paie le prix annoncé, sans surprise. Seconde source : l'**abonnement premium** des prestataires, qui réduit leur commission en échange d'une plus grande visibilité. »

### Q10-bis — « Pourquoi 18 % précisément ? Quelle est la logique derrière ce taux, et comment évolue-t-il ? »
> « Le 18 % n'est pas un chiffre arbitraire, il résulte de trois raisonnements : un **benchmark**, une **structure de coûts**, et une **stratégie d'adhésion**.
>
> **1. Le benchmark.** Les plateformes de mise en relation prélèvent généralement entre **15 et 30 %** : Uber/Bolt tournent autour de 20-25 %, les marketplaces de services internationales (TaskRabbit, Thumbtack) entre 15 et 30 %. Me placer à **18 %** me positionne dans le **bas de la fourchette** : assez pour être viable, assez bas pour rester **attractif** face à un marché ivoirien encore informel, où l'intermédiaire ("le cousin qui connaît quelqu'un") prend parfois plus, de façon opaque.
>
> **2. La structure de coûts — à quoi servent ces 18 %.** Ce n'est pas de la marge pure. Sur 100 F de commission, on couvre approximativement :
> - **~2 %** de frais d'agrégateur Mobile Money (GeniusPay) ;
> - **l'infrastructure** (serveurs, base de données, notifications, stockage des photos/CNI) ;
> - la **vérification KYC** de chaque prestataire (contrôle d'identité) ;
> - la **gestion des litiges** et le suivi de l'escrow (séquestre du paiement) ;
> - un **fonds de garantie** "dégâts" (micro-assurance prélevée sur la commission, prévu en feuille de route) ;
> - le **marketing et la visibilité** qui ramènent des clients au prestataire ;
> - une **marge** pour la pérennité de l'entreprise.
> Autrement dit, le prestataire ne paie pas une "taxe", il **achète un service** : des clients, une réputation, un paiement garanti.
>
> **3. La stratégie d'adhésion — le plan de réduction.** Le 18 % est le **taux Standard (gratuit)**. Il est conçu pour **baisser** à mesure que le prestataire s'engage :
>
> | Palier | Commission | Logique |
> |---|---|---|
> | **Standard** (gratuit) | **18 %** | taux de base, sans engagement |
> | **Silver** (7 500 F/mois) | **13 %** (−5 pts) | rentable dès ~40 000 F de missions/mois |
> | **Gold** (15 000 F/mois) | **8 %** (−10 pts) | pour les prestataires à fort volume |
>
> Le message au prestataire est clair : **plus tu travailles avec BABIFIX, moins tu paies.** Le calculateur de rentabilité intégré lui montre, chiffres réels en main, à partir de quel volume chaque palier devient gagnant. On aligne ainsi notre intérêt et le sien : on gagne quand **lui** gagne.
>
> **Et c'est paramétrable** : la commission est stockée en base et ajustable par catégorie (15-20 %) — un métier très concurrentiel peut avoir un taux plus bas pour attirer l'offre, un métier de niche un peu plus haut. Le 18 % est donc un **point d'équilibre de départ**, pas une fin en soi. »

### Q11 — « Pourquoi un prestataire paierait pour le premium si ça lui coûte de l'argent ? »
> « Parce que c'est un **investissement rentable**, et l'application le **prouve chiffres en main** : un calculateur de rentabilité montre, selon son activité réelle des 30 derniers jours, combien il **économiserait** avec chaque palier. Le premium réduit sa commission sur *toutes* ses missions futures, le met en avant dans les résultats, lui donne un badge de confiance et un quota de devis plus élevé. Un prestataire actif rentabilise vite. »

**Détail des paliers :**
| | Standard (gratuit) | Silver (7 500 F/mois) | Gold (15 000 F/mois) |
|---|---|---|---|
| Commission | base | −5 points | −10 points |
| Devis actifs | 3 max | 15 | illimités |
| Visibilité | normale | mise en avant | priorité maximale |
| Badge | — | « Pro vérifié » | « Top » |

### Q12 — « Combien d'utilisateurs faut-il pour que ce soit viable ? »
> « C'est le défi de toute marketplace : l'effet de réseau. J'ai prévu un **système de parrainage** pour amorcer la croissance, et une stratégie de lancement **ville par ville** — concentrer offre et demande sur Abidjan d'abord, atteindre une masse critique locale, puis répliquer. Mieux vaut être dense dans un quartier que dispersé dans tout le pays. »

### Q12-bis — « Comment financez-vous concrètement le fonds de garantie / l'assurance dégâts ? »
> « Par une **micro-assurance** : une **petite fraction de la commission** de chaque prestation est mise de côté et alimente un **fonds de garantie "dégâts"**. Point crucial : BABIFIX **ne devient pas assureur** — je serais **preneur d'une police d'assurance groupe** auprès d'une **compagnie agréée CIMA** (NSIA, SUNU, Atlantique, Allianz CI, SAHAM/Sanlam). En phase pilote, un **fonds interne plafonné** ; au passage à l'échelle, le **partenariat assureur**. Je n'ai donc pas besoin d'agrément d'assurance : la compagnie porte le risque, BABIFIX fournit le volume et les preuves horodatées (photos avant/après, géolocalisation) qui fluidifient l'indemnisation. »

> ⚠️ **Piège à éviter** : ne jamais dire « BABIFIX assure les clients ». Toujours : *« partenariat avec une compagnie agréée CIMA, nous ne sommes pas assureur »*.

### Q12-ter — « Et si un gros concurrent débarque (Jumia, un Uber-like) avec plus de moyens ? »
> « D'abord, un gros acteur qui entre **valide le marché** — c'est plutôt bon signe. Ensuite, mon avantage est **local et défensif** : des catégories pensées pour la Côte d'Ivoire, l'intégration Mobile Money (Orange/MTN/Wave/Moov), et surtout la **confiance construite sur le terrain** (KYC, avis, réputation). Or l'**effet de réseau** — les avis, les historiques, les réputations accumulées — **ne se copie pas** : celui qui installe la confiance en premier prend une longueur d'avance. Et rien n'interdit, à terme, un **partenariat ou un rachat** : un grand acteur préfère souvent acheter un acteur local établi que repartir de zéro. »

### Q12-quater — « Quand l'entreprise sera-t-elle rentable ? »
> « L'**économie unitaire est saine** : la commission de chaque transaction couvre ses coûts variables (frais Mobile Money, support). Les **coûts fixes sont faibles** — cloud, pas d'agence physique, pas de stock. La rentabilité vient donc du **volume** : plus de transactions sur la même infrastructure, sans coût proportionnel. L'enjeu n'est pas le coût par transaction, c'est **d'atteindre la masse critique** d'utilisateurs sur une ville d'abord. »

### Q12-quinto — « Le Mobile Money prend déjà des frais. Le prestataire n'est-il pas doublement ponctionné ? »
> « Non. Les frais de l'agrégateur Mobile Money (~2-3 %) sont **inclus dans la commission**, pas ajoutés par-dessus. Le prestataire voit **un seul taux clair**, sans empilement de frais cachés. C'est justement une des choses que la commission couvre — je l'assume à sa place. »

### Q12-sexto — « Qui fixe le prix d'une prestation ? »
> « **Le prestataire**, via son **devis** — il reste maître de ses tarifs et de sa main-d'œuvre. BABIFIX ne fixe **pas** les prix ; il **encadre la transaction** (devis, séquestre, commission). La **concurrence** entre prestataires et les **avis clients** régulent naturellement les prix vers le juste. »

### Q12-septimo — « Et un prestataire qui refuse de payer sa commission ? »
> « Il ne le **peut pas** : la commission est **prélevée automatiquement dans le flux de paiement** (séquestre), **avant** que le prestataire ne touche son net. Il ne reçoit jamais l'argent "brut" du client. La commission n'est donc pas une facture qu'il pourrait ignorer — elle est intégrée au mécanisme de paiement lui-même. »

### Q12-octavo — « Pour les travaux qui exigent une visite (peinture, carrelage), le prestataire se déplace-t-il gratuitement ? Comment le protégez-vous ? »
> « C'est un vrai enjeu : on ne peut pas toujours chiffrer sur photos — la peinture ou le carrelage exigent un **métré** (mesures sur place). Ma réponse est la **visite de diagnostic encadrée** : au lieu d'un devis direct, le prestataire propose une **visite** avec un **créneau** et une **caution de diagnostic** (petite somme fixe). Le client la **paie dans l'app**, ce qui **débloque l'adresse exacte** — pour ce prestataire, pour ce créneau seulement. Après la visite, le prestataire saisit son **devis ferme dans l'app**. Si le client accepte, la caution est **déduite** du devis ; s'il refuse, elle **reste au prestataire** comme dédommagement du déplacement.
>
> Résultat : **le prestataire ne se déplace jamais gratuitement**, le **client fantôme** est dissuadé, l'**adresse reste protégée**, et le devis est **fiable** (basé sur de vraies mesures). Je prends une **petite commission sur la caution** et ma **commission normale sur la prestation** — jamais en double. »

> 💡 **Si on te demande "et vous, quand prenez-vous votre commission là-dedans ?"** : *« Une petite commission sur la caution au moment où elle est payée, et ma commission habituelle sur la prestation à la libération du séquestre. Comme ça, même une visite sans suite me rapporte un peu, et le prestataire est toujours dédommagé. »*

## 🟢 D. Questions ouvertes classiques

### Q13 — « Quelle a été votre plus grande difficulté ? »
> « La gestion du **flux de paiement avec séquestre**. Synchroniser l'état d'un paiement entre l'application, mon serveur, et l'agrégateur Mobile Money — en garantissant qu'aucun double paiement ne survienne et que les fonds se libèrent au bon moment — m'a demandé beaucoup de rigueur. C'est aussi ce dont je suis le plus fier. »

### Q14 — « Si vous deviez recommencer, que feriez-vous différemment ? »
> « Je **factoriserais plus tôt le code commun aux deux applications mobiles** dans une bibliothèque partagée. »
>
> **Ce que ça veut dire :** certaines parties (gestion des erreurs, notifications, design) sont identiques dans les deux apps et étaient copiées-collées. En les regroupant en **un seul module partagé**, une correction profite **automatiquement aux deux applications** au lieu de devoir être faite deux fois. *Image : au lieu que deux cuisiniers aient chacun leur copie de la recette, on met la recette sur une seule affiche au mur que les deux consultent.*

### Q15 — « En quoi est-ce différent d'un simple groupe WhatsApp ou Facebook ? »
> « Un groupe WhatsApp n'offre **aucune garantie** : pas de vérification d'identité, pas de paiement sécurisé, pas de séquestre, pas d'avis, pas de recours en cas de litige. BABIFIX apporte exactement ce qui manque : **la confiance structurée**. »

### Q16 — « Votre projet est-il réellement fonctionnel ou est-ce une maquette ? »
> « Il est **fonctionnel de bout en bout** : un client s'inscrit, géolocalise un prestataire, reçoit un devis (affiché comme une carte professionnelle dans le chat), paie en Mobile Money, suit l'intervention, confirme, note — et le prestataire reçoit son paiement. Le tout avec notifications temps réel, appels audio, notes vocales dans le chat, et supervision admin. Je peux vous le démontrer maintenant. »

## 🔵 E. Marché & impact social

### Q18 — « Quelle est la taille de votre marché ? À qui vous adressez-vous ? »
> « Le marché est **large et concret**. La Côte d'Ivoire compte plus de **24 millions de comptes Mobile Money**, et **plus de 70 % des adultes** paient déjà par téléphone — la population est donc **prête à transiger en numérique**. En face, les services à domicile (plomberie, électricité, ménage, jardinage, climatisation…) sont un **besoin quotidien et récurrent**, aujourd'hui **massivement informel**. Ma cible de départ : **Abidjan**, la plus dense, avant de répliquer ville par ville. Je ne crée pas un besoin, je **structure un marché qui existe déjà**. »

### Q19 — « Quel est l'impact social / sur l'emploi de votre plateforme ? »
> « Il est direct : BABIFIX **formalise un secteur informel** et **valorise le travail des prestataires**. Un artisan compétent mais invisible obtient une **vitrine numérique**, une **réputation vérifiable** (avis, historique), des **reçus professionnels**, et surtout un **revenu plus régulier** grâce aux clients apportés. C'est un outil d'**inclusion économique** : je donne des moyens de se faire connaître et d'être payé en confiance à des travailleurs qui n'avaient que le bouche-à-oreille. »

### Q20 — « Comment touchez-vous les non-bancarisés ? »
> « C'est justement la **force du Mobile Money**. En Côte d'Ivoire, la majorité des gens n'ont **pas de compte bancaire**, mais **ont un compte Mobile Money**. En construisant tout le paiement sur **Orange, MTN, Wave et Moov** — et **pas** sur la carte bancaire — je rends la plateforme accessible à la **grande majorité de la population**, y compris les prestataires et clients **non bancarisés**. »

### Q21 — « Beaucoup de prestataires sont peu à l'aise avec le numérique. Comment gérez-vous cette barrière ? »
> « J'en ai fait un **principe de conception** : l'application prestataire est **simple, en français, guidée pas à pas**, avec des **messages d'erreur clairs** (jamais de code technique). Le parcours suit sa logique métier : *recevoir une demande → faire un devis → exécuter → être payé*. À terme, un **onboarding accompagné** (tutoriels, voire agents de terrain pour l'inscription des premiers) lève la barrière — c'est un enjeu d'**accompagnement**, pas seulement de technologie. »

### Q22 — « Votre modèle est-il réplicable à d'autres pays ? »
> « Oui, et c'est voulu. Les briques — Mobile Money, géolocalisation, séquestre, KYC — sont **communes à toute l'Afrique de l'Ouest** (zone **UEMOA/CIMA**). Le socle technique est le même ; il suffit d'**adapter les opérateurs de paiement et les catégories locales**. La Côte d'Ivoire est un **marché-pilote** représentatif : ce qui marche à Abidjan est transposable à Dakar, Lomé, Cotonou… »

### Q23 — « En quoi contribuez-vous concrètement à l'économie ivoirienne ? »
> « Sur trois plans. **Formalisation** : je fais entrer une activité informelle dans un cadre tracé (identité vérifiée, transactions enregistrées, reçus). **Confiance** : je réduis l'asymétrie d'information qui freine la consommation de ces services. **Numérisation des paiements** : je pousse l'usage du Mobile Money vers de nouveaux cas d'usage. C'est aligné avec la stratégie nationale de **transformation numérique** de la Côte d'Ivoire. »

---

# 🔐 PARTIE 3 — LA QUESTION KYC (vérification d'identité)

### Q17 — « Est-ce que se contenter d'uploader la pièce d'identité et un selfie de la personne avec sa pièce est pertinent et suffisant pour sécuriser ? Ne faut-il pas plus que ça ? »

**Réponse honnête et nuancée :**

> « Très bonne question. Uploader la pièce d'identité + un selfie est le **socle de base** de tout KYC ("Know Your Customer"), et c'est déjà pertinent — mais vous avez raison : **seul, ce n'est pas suffisant**, car on peut tricher (photo d'une photo, pièce volée, deepfake). C'est pourquoi BABIFIX **ne se contente pas de stocker les images** : il les fait passer par une **vérification en cascade à trois niveaux**.
>
> **Niveau 1 — Contrôle automatique de l'image** (toujours actif) : format valide, résolution suffisante, **détection de flou**, luminosité correcte, et surtout les trois images ne doivent **pas être identiques** (empreinte SHA-256) — ce qui bloque celui qui enverrait trois fois la même photo. On valide aussi le **format du numéro de CNI ivoirienne**.
>
> **Niveau 2 — Vision par ordinateur (OpenCV)** : on **détecte le visage** dans le selfie ET dans la pièce, on vérifie qu'il y a **exactement un visage** dans chaque, et un contrôle anti-spoofing basique.
>
> **Niveau 3 — Smile Identity** (service spécialisé africain) : vérification du **numéro de CNI contre la base gouvernementale ivoirienne** et **correspondance biométrique** entre le selfie et la photo officielle.
>
> Le système produit un **score de confiance de 0 à 100**, mais — point essentiel — **la décision finale revient toujours à un administrateur humain**. L'IA suggère, l'humain tranche. »

**Sécurisation du stockage :**
> « Les pièces ne sont pas exposées publiquement, et — c'est désormais **implémenté** — elles sont **purgées automatiquement** une fois le dossier traité : on ne garde que le résultat, le numéro masqué et la date d'expiration. »

**État des renforts identité :**
- ✅ **Purge des pièces** après traitement (fait — minimisation des données).
- ✅ **Re-vérification automatique** quand la CNI expire (fait).
- ✅ **Vérification du numéro de téléphone** par OTP (déjà en place).
- 🔜 **Liveness / preuve de vie** : via Smile Identity (option à activer, pipeline prêt).
- 🔜 **Justificatif de domicile** / attestation de compétence pour certains métiers.
- ⚠️ **Casier judiciaire** : pertinent pour métiers sensibles mais nécessite un cadre légal et un partenariat institutionnel (piste long terme — voir formulation prudente Q17-bis).

**Phrase de synthèse à dire :**
> « Donc : la pièce + le selfie sont le **point de départ nécessaire**, mais la vraie sécurité vient de ce qu'on en **fait** — analyse automatique, biométrie, vérification gouvernementale, validation humaine — et de la **feuille de route** : preuve de vie, chiffrement, re-vérification. La confiance se construit en couches, pas en un seul upload. »

### Q17-bis — « Comment vérifier qu'une CNI ivoirienne est authentique, numériquement ? »

> « En Côte d'Ivoire, l'autorité officielle est l'**ONECI** (Office National de l'État Civil et de l'Identification), qui gère le **RNPP** (Registre National des Personnes Physiques) et délivre la **CNI biométrique** ainsi que le **NNI** (Numéro National d'Identification, 11 chiffres). L'ONECI propose même une identité numérique via l'application **MyONECI+**.
>
> **Point important et honnête** : l'ONECI **n'expose pas d'API publique** ouverte à toute entreprise privée pour interroger directement la base par numéro. La vérification se fait donc via un **agrégateur agréé** — dans mon cas **Smile Identity**, un acteur spécialisé africain. Mon système envoie le **numéro + les images** ; Smile Identity **authentifie le document**, **lit (OCR) le numéro**, et **compare biométriquement le selfie à la photo de la pièce** (modèles "dé-biaisés", ~99,8 % de précision sur les carnations africaines).
>
> Concrètement, côté code : pays `CI`, type `NATIONAL_ID`, produit *Document Verification* — c'est exactement la méthode adaptée au contexte ivoirien. »

**Ce que mon moteur fait précisément (à pouvoir détailler) :**
- **Validation de format intelligente** : reconnaît en priorité le **NNI (11 chiffres)** et la **CNI ONECI** (préfixe CI), tolère les anciens formats, et **rejette les saisies bidon** (chiffre unique répété type `00000000000`, séquences triviales `123456789`).
- **Niveau de confiance du numéro** : `strong` (NNI / CNI ONECI), `ok` (ancien format), `weak` (repli).
- Puis **biométrie** (visage selfie ↔ visage pièce) + **vérification via Smile Identity**.

### ✅ Ce qui vient d'être ajouté au projet (à citer comme fait, pas en roadmap)

1. **Minimisation des données (purge des pièces)** : une fois le dossier **traité** (approuvé ou rejeté), les **images d'identité brutes** (selfie + CNI recto/verso) sont **automatiquement supprimées** au bout d'un délai (30 j par défaut), via une commande de maintenance planifiable. On ne conserve que le **résultat**, le **numéro masqué** (`CI•••••789`) et la **date d'expiration**. → respect de la vie privée par conception.
2. **Re-vérification automatique à l'expiration** : si la **CNI d'un prestataire approuvé expire**, son dossier repasse automatiquement en attente avec un message lui demandant une pièce à jour.

> Phrase à dire : *« Je ne garde pas les pièces d'identité indéfiniment : une fois le dossier traité, les images sont purgées et il ne reste que le résultat et le numéro masqué. Et si la CNI expire, le prestataire est automatiquement re-vérifié. »*

### Sur la **preuve de vie (liveness)** — formulation maligne
> « Le liveness — demander à la personne de cligner ou tourner la tête pour bloquer la photo d'une photo et les deepfakes — **se branche directement via Smile Identity** : mon pipeline est déjà prêt à le recevoir, c'est une **option à activer**, pas un développement maison. »

### Sur le **casier judiciaire** — formulation prudente (NE PAS prétendre l'avoir fait)
> « Pour les métiers les plus sensibles (garde d'enfants, aide aux personnes âgées), une vérification d'antécédents serait pertinente — **mais elle exige un cadre légal et un partenariat institutionnel** : le casier judiciaire (bulletin n°3) est délivré par le ministère de la Justice, une plateforme privée ne peut pas y accéder librement. C'est une **piste à long terme**, pas une fonctionnalité que je peux décider seul, d'autant qu'elle touche des **données ultra-sensibles**. »

> ⚠️ **Piège à éviter** : ne JAMAIS dire « je vérifie le casier judiciaire » sans cette nuance — le jury demanderait *« avec quelle autorisation légale ? »* et tu serais coincé.

---

# 🎬 PARTIE 4 — SCRIPT DE DÉMONSTRATION

> **Durée cible : 4 à 6 minutes.** Appareils/émulateurs **allumés et connectés AVANT** de commencer. Comptes client + prestataire **déjà créés et connectés**.

## ⚙️ Checklist avant de commencer
- [ ] Backend lancé et accessible
- [ ] App client ouverte sur un écran/émulateur
- [ ] App prestataire ouverte sur un second écran/émulateur
- [ ] Panneau admin ouvert dans un navigateur
- [ ] Connexion internet stable
- [ ] Comptes de test déjà connectés
- [ ] **Vidéo de secours** + captures d'écran prêtes (plan B)

## 🎯 Scénario : « Le parcours complet d'une demande »

**ÉTAPE 1 — Côté client : la demande (1 min)**
> *« Reprenons notre exemple : mon robinet fuit. J'ouvre l'application client. »*
- Montre l'**écran d'accueil** avec la carte et les prestataires géolocalisés autour.
- *« Voici les plombiers disponibles autour de moi, chacun sur la carte. »*
- Sélectionne une catégorie / un prestataire.
- Crée une demande : décris le problème, ajoute une photo, valide l'adresse.
- *« Ma demande part. Remarquez : mon adresse exacte reste masquée pour l'instant. »*

**ÉTAPE 2 — Côté prestataire : réception, accord & devis (1 min 30)**
> *« Basculons sur le téléphone du prestataire. »*
- Montre la **notification reçue en temps réel**. *(Point fort.)*
- Ouvre la demande : *« Il voit le quartier, mais pas la rue exacte. »*
- Le prestataire **accepte** : *« À cet instant, l'adresse complète lui est révélée, et c'est seulement maintenant que le client et lui peuvent communiquer. »*
- Il **crée un devis** et l'envoie.
- *« Le devis part chez le client, instantanément, et apparaît comme une carte professionnelle dans le chat. »*

**ÉTAPE 3 — Côté client : acceptation & paiement sécurisé (1 min 30)**
> *« Retour chez le client. »*
- Montre la **carte devis dans le chat** + le détail.
- Le client **accepte** puis passe au **paiement Mobile Money**.
- Montre les **logos Orange / MTN / Wave / Moov**.
- *« Le client paie. Mais — point essentiel — l'argent n'arrive PAS encore chez le prestataire. Il est bloqué en séquestre. »* **← Phrase clé, dite lentement.**

**ÉTAPE 4 — Côté admin : la supervision (45 s)**
> *« Pendant ce temps, côté administrateur… »*
- Montre le **tableau de bord** : la réservation apparaît, le paiement est en attente.
- Montre le **Kanban**, la section paiements, les litiges.
- *« L'administrateur a une vue totale : prestataires, paiements, litiges. Rien ne lui échappe. »*

**ÉTAPE 5 — Confirmation & libération des fonds (45 s)**
> *« L'intervention est terminée. »*
- Côté client : **confirme la prestation** + laisse une **note/avis**.
- *« À cet instant précis, et seulement maintenant, les fonds sont libérés vers le prestataire. »*
- Montre le **reçu PDF** généré.
- *« Le prestataire est payé, le client a son reçu, tout le monde est protégé. La boucle est bouclée. »*

## 🧯 Plan B (si la démo plante)
- **Vidéo de secours** du parcours complet sur ton téléphone.
- **3-4 captures clés** dans tes diapositives.
- Si ça plante : *« Je rencontre un souci réseau, permettez-moi de vous montrer la séquence enregistrée. »* Calme, pro, pas de panique. **Le jury juge ta réaction autant que ta démo.**

## 🎤 Transition vers la conclusion
> *« Vous venez de voir, en quelques minutes, ce qu'un Ivoirien vivra demain en quelques clics : trouver, faire confiance, payer sereinement, être protégé. C'est tout le sens de BABIFIX. »*

---

# 📌 PARTIE 5 — FONCTIONNALITÉS À METTRE EN AVANT

Ce que tu peux citer comme **réellement implémenté et fonctionnel** :

- ✅ **3 applications connectées** (client, prestataire, admin web) + site vitrine
- ✅ **Géolocalisation** des prestataires (carte + pins + rayon adaptatif 5→50 km)
- ✅ **Confidentialité de l'adresse** (masquée avant accord, révélée après acceptation)
- ✅ **Devis** affiché comme **carte professionnelle figée** dans le chat
- ✅ **Paiement Mobile Money** sécurisé (Orange/MTN/Wave/Moov) + **séquestre**
- ✅ **Reçu PDF** professionnel généré automatiquement
- ✅ **Chat temps réel** (WebSocket) + **images** + **notes vocales** + **événements système**
- ✅ **Appels audio** réels (LiveKit) avec sonnerie push même app fermée
- ✅ **Règle d'accord** : pas de contact (appel/message) avant acceptation
- ✅ **Notifications push** (FCM) opérationnelles + notifications persistantes
- ✅ **Actualités** consultables et cliquables (client & prestataire)
- ✅ **KYC en cascade** (Pillow → OpenCV → Smile Identity) + validation humaine
- ✅ **Premium 3 paliers** (commission réduite, visibilité, quota devis, badge) + **calculateur de rentabilité**
- ✅ **Système de litiges** avec droit de réponse du prestataire + arbitrage admin
- ✅ **Commission honnête** (dégressive par volume + réduction premium, identique à l'affichage)
- ✅ **Animations** de confirmation (paiement, retrait avec confettis)
- ✅ **Messages d'erreur clairs en français** (jamais de code HTTP brut affiché)

---

# 🎯 PARTIE 6 — PHRASES À CONNAÎTRE PAR CŒUR

1. *(Accroche)* « Imaginez : vous venez de construire votre maison, et un matin, un robinet fuit. »
2. *(Le pont)* « Entre les deux, il manque un pont. Ce pont, c'est BABIFIX. »
3. *(Séquestre)* « L'argent du client est bloqué et n'est versé au prestataire qu'une fois la prestation confirmée. Personne ne peut tricher. »
4. *(Différenciation)* « BABIFIX apporte ce qui manque au bouche-à-oreille : la confiance structurée. »
5. *(Clôture)* « BABIFIX, c'est le pont que j'ai voulu bâtir. »

---

*Document de préparation soutenance — BABIFIX. Bon courage. 🚀*


🔴 Casier judiciaire — à manier avec beaucoup de prudence
Honnêtement, je suis plus réservé sur celui-là :

Les problèmes :

Accès légal compliqué : en Côte d'Ivoire, le casier judiciaire (bulletin n°3) est un document personnel, délivré par le ministère de la Justice. Une plateforme privée ne peut pas y accéder librement — il faudrait un cadre légal/institutionnel lourd.
Question éthique/RGPD : stocker des données judiciaires = données ultra-sensibles, fortes obligations légales.
Le jury peut te piéger : si tu dis « je vérifie le casier judiciaire », un membre peut demander « comment ? avec quelle autorisation légale ? » → tu te retrouves coincé.
Comment le formuler intelligemment si tu y tiens :

« Pour les métiers les plus sensibles (garde d'enfants, aide aux personnes âgées), une vérification d'antécédents serait pertinente — mais elle nécessite un cadre légal et un partenariat institutionnel. C'est une piste à long terme, pas une fonctionnalité technique que je peux décider seul. »

👉 Cette formulation te protège : tu montres que tu y as pensé, et que tu connais les limites. C'est plus fort que de prétendre l'avoir fait.