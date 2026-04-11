# BABIFIX — Un seul projet Flutter (client + prestataire)

Objectif : remplacer les deux dossiers `babifix_client_flutter` et `babifix_prestataire_flutter` par **un** dépôt avec **deux flavors** (`client` / `prestataire`), `applicationId` distincts et point d’entrée différent (`lib/main_client.dart` / `lib/main_prestataire.dart`).

## Étapes recommandées

1. Créer un dossier `babifix_flutter/` et y copier la base la plus complète (souvent prestataire + écrans client à fusionner).
2. Dans `pubspec.yaml`, garder une seule liste de dépendances (union des deux apps).
3. Ajouter [`flutter_flavor`](https://pub.dev/packages/flutter_flavor) ou configuration **Gradle/iOS** manuelle :
   - `--dart-define=APP_ROLE=client|prestataire` lu au démarrage pour router vers le bon `MaterialApp`.
4. Fichiers à dupliquer par flavor :
   - `android/app/src/client/` et `.../prestataire/` : `AndroidManifest.xml`, `build.gradle` (`applicationId` : `com.babifix.client` / `com.babifix.prestataire`).
   - iOS : deux schémas ou deux `bundle identifier`.
5. Code partagé : `lib/core/`, `lib/babifix_money.dart`, API (`baseUrl`), thème. Code spécifique : `lib/features/client/` vs `lib/features/prestataire/`.
6. Vérifier `babifix_api_token` et les routes API (`/api/client/...` vs `/api/prestataire/...`) selon le rôle.

## Pourquoi ce n’est pas fusionné dans BABIFIX_BUILD

La fusion complète impose des tests manuels longs (build Android/iOS, stores). Les deux apps restent séparées tant que le MVP backend n’est pas figé ; ce document sert de feuille de route.
