# 🎨 Charte design BABIFIX — sobre & pro

> Objectif : passer d'un rendu « coloré / IA » à un produit **sobre et crédible**
> (type Wave, Yango, Airbnb). Règle d'or : **la couleur porte du sens, pas de la déco.**

## 1. Palette (≈ 12 tokens — rien en dur en dehors)
- **Marque** : navy `#0B1B34`, cyan `#4CC9F0`, orange (action) `#E87722`.
- **Neutres** (l'essentiel de l'UI) : blanc `#FFFFFF`, gris fond `#F1F5F9`, gris carte `#F8FAFC`,
  bordure `#E2E8F0`, texte fort `#0F172A`, texte doux `#64748B`, texte discret `#94A3B8`.
- **Sémantique (statut uniquement)** : succès `#22C55E`, alerte `#F59E0B`, erreur `#EF4444`, premium `#7C3AED`.

➡️ **Interdit** : inventer des hex au cas par cas. On réutilise ces tokens.

## 2. Règles
1. **Fonds plats.** Zéro dégradé décoratif. (Au maximum 1 dégradé signature sur un en-tête de marque, si vraiment utile.)
2. **1 seul accent par écran** = l'orange, réservé au **bouton d'action principal**. Le reste est neutre.
3. **Pas de glow / ombres colorées.** Ombres neutres et subtiles seulement (`rgba(0,0,0,0.06)`).
4. **Pas d'emoji dans l'UI.** Un seul jeu d'icônes cohérent (outline).
5. **Hiérarchie par la taille et l'espace**, pas par la couleur. Le chiffre est gros, pas cyan.
6. **Casse normale** (« Réserver », jamais « RÉSERVER MAINTENANT »).
7. **Statuts en texte/pastille discrète**, pas en dégradés qui se battent.
8. **60 / 30 / 10** : 60 % neutre, 30 % secondaire, 10 % accent max.
9. **Divulgation progressive** : montrer l'essentiel, cacher l'avancé derrière « + d'options ».

## 3. Admin — cas concrets à corriger
- Cartes KPI : fond plat, chiffre gros neutre, **1 seul** indicateur « live » global (pas 1 par carte).
- Graphiques : en-têtes plats, pas de dégradés dans les cartes.
- Réduire le nombre de teintes simultanées.

## 4. Ordre d'exécution
1. [x] Charte (ce doc).
2. [ ] **Admin** (CSS centralisé — priorité soutenance).
3. [ ] App client (booking, carte, listes, devis).
4. [ ] App prestataire (inscription, demandes, devis, dashboard).

*Chaque passe : aplatir dégradés → tokens couleur → retirer glow/emoji → 1 accent/écran.*
