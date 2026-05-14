# Guide de migration BABIFIX — Phases A → G + B7/C1/B12/B6

## Pré-requis

```bash
# Activer le venv puis :
pip install -r requirements.txt   # Pillow + reportlab + autres
```

Le `requirements.txt` contient déjà `Pillow>=10.0.0` et `reportlab>=4.0.0`.

## 1. Variables d'environnement (Render / .env)

Ajouter / vérifier :

| Variable | Rôle | Obligatoire |
|---|---|---|
| `LIVEKIT_URL` | URL LiveKit (`wss://...livekit.cloud`) | Oui (appels) |
| `LIVEKIT_API_KEY` | Clé API LiveKit | Oui (appels) |
| `LIVEKIT_API_SECRET` | Secret API LiveKit | Oui (appels) |
| `GENIUSPAY_PUBLIC_KEY` | Clé pub GeniusPay | Oui (paiement) |
| `GENIUSPAY_SECRET_KEY` | Clé secrète GeniusPay (HMAC webhook) | **OUI** (sinon webhook non vérifié, faille) |
| `GENIUSPAY_API_URL` | Défaut `https://pay.genius.ci/api/v1/merchant` | Non |
| `GENIUSPAY_WEBHOOK_URL` | URL publique du webhook | Oui (config GeniusPay) |
| `GENIUSPAY_SUCCESS_URL` | Redirection succès | Recommandé |
| `GENIUSPAY_ERROR_URL` | Redirection échec | Recommandé |

⚠️ **Sécurité** : si `GENIUSPAY_SECRET_KEY` est vide, le webhook accepte tout
(mode dev). En prod c'est OBLIGATOIRE.

## 2. Migrations DB

```bash
python manage.py migrate adminpanel
```

Applique séquentiellement :
- `0041_devis_net_prestataire` — Phase A : ajout `net_prestataire`, backfill devis ENVOYE/BROUILLON/EXPIRE.
- `0042_reservation_funds_released_at` — Phase F escrow.
- `0043_message_kind_payload` — Phase C chat enrichi.
- `0044_catalogue_items_lignes_extension` — Phase B catalogue.
- `0045_call_signaling` — Phase D modèle Call.
- `0046_client_journal` — journal client post-intervention.
- `0047_cancellation_refund` — C1 annulation + remboursement.

## 3. Seed catalogue prestataire

```bash
python manage.py seed_catalogue
```

Crée ~34 `CatalogueItem` répartis sur les catégories existantes
(Plomberie, Électricité, Menuiserie, Climatisation). Idempotent.

Pour ajouter Peinture / Ménage / Soudure : créer d'abord les Categories
correspondantes dans l'admin Django puis re-lancer la commande.

## 4. Tests de non-régression

```bash
python manage.py test adminpanel.tests.test_phase_f_to_b12 -v 1 --noinput
```

20 tests doivent passer. Couvre escrow mobile/cash, B12 minimum
commission, C1 annulation (5 stages × 2 acteurs), MediaService,
journal client.

## 5. Configuration Mobile Money (GeniusPay)

Côté dashboard GeniusPay :
- URL webhook = `<API_BASE>/api/paiements/geniuspay/webhook/`
- Événements à activer : `payment.success`, `payment.failed`,
  `payment.cancelled`, `payment.expired`.

## 6. Build apps Flutter

```bash
# Client
cd babifix_client_flutter
flutter clean && flutter pub get && flutter build apk --release

# Prestataire
cd ../babifix_prestataire_flutter
flutter clean && flutter pub get && flutter build apk --release
```

Vérifier que ni `_defaultLiveKitApiSecret` ni `_defaultLiveKitApiKey`
n'apparaissent en clair après dump APK (les apps doivent utiliser
`/api/calls/initiate` qui renvoie un token côté serveur).

## 7. Permissions Android

Manifestes mis à jour avec :
- `POST_NOTIFICATIONS` (Android 13+)
- `USE_FULL_SCREEN_INTENT` (Android 14+) — pour la sonnerie d'appel
  fullscreen
- `READ_MEDIA_IMAGES`, `READ_EXTERNAL_STORAGE` (image_picker)
- `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_PHONE_CALL`

Channel notification `babifix_calls` créé au démarrage avec
`Importance.max`.

## 8. Endpoints nouveaux (référence rapide)

| Méthode | URL | Rôle |
|---|---|---|
| GET | `/api/reservations/<ref>/payment/quote` | Calcul escrow cash/mobile |
| POST | `/api/calls/initiate` | Démarrer un appel (token serveur) |
| POST | `/api/calls/<id>/answer` | Décrocher |
| POST | `/api/calls/<id>/reject` | Rejeter |
| POST | `/api/calls/<id>/end` | Terminer |
| GET | `/api/calls/<id>` | Détail appel |
| GET | `/api/calls/history` | 30 derniers |
| GET | `/api/categories/<id>/catalogue` | Items catalogue catégorie |
| GET/POST | `/api/client/reservations/<ref>/journal` | Journal client |
| POST | `/api/media/upload` | Upload image multipart ou data URI |
| POST | `/api/client/demandes/<ref>/annuler` | Annulation client + refund |
| POST | `/api/prestataire/requests/<ref>/annuler` | Annulation presta |
| POST | `/api/admin/reservations/<ref>/refund/mark-paid` | Admin confirme virement |
| POST | `/api/client/reservations/<ref>/dispute` | Ouverture litige |
| POST | `/api/admin/disputes/<dispute_ref>/resolve` | Résolution litige |

## 9. Règle d'or escrow

**Aucun fonds ne quitte la plateforme avant `client_confirme_prestation_at`.**

- Mobile 100% : tout en escrow, 82% wallet presta + 18% PlatformRevenue
  uniquement à la confirmation finale.
- Cash : la commission 18% est encaissée à l'acompte ; le solde 82%
  est payé en main à main par le client au prestataire.
- B12 : si commission < 500 FCFA, prélèvement minimum 500 FCFA ; le
  surplus est reversé au prestataire à la confirmation.

## 10. Rollback

Aucune migration n'est destructive. En cas de besoin, `manage.py
migrate adminpanel 0040` revient à l'état pré-Phase A (les nouveaux
champs sont conservés mais ignorés).

⚠️ Ne pas dropper les tables — les nouvelles colonnes (`net_prestataire`,
`funds_released_at`, etc.) contiennent les vérités financières.
