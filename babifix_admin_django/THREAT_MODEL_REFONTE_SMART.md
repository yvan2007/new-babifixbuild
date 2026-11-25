# THREAT_MODEL_REFONTE_SMART : BABIFIX (Refonte SOS 24/7, Finance, Reçus/Emails & Cartographie)

Date : 2026-11-21
Conformite : Loi ivoirienne n° 2013-450 sur la protection des donnees a caractere personnel, OWASP API Security Top 10.

---

## 1. Perimetre de la refonte

1. **Module « BABIFIX SOS 24/7 » & Visite de diagnostic** :
   - Creation de demande SOS restreinte aux categories critiques (`Category.supports_sos`), horodatage serveur (jour vs nuit/dimanche GMT+0 Abidjan), forfait fixe serveur (`1 500` / `2 500` FCFA deductible du devis final).
   - Diffusion sectorielle aux prestataires approuves et disponibles du secteur/rayon, attribution atomique (`POST /api/prestataire/requests/<ref>/sos-claim/`).
   - Verrouillage strict de `address_is_approximate=True` jusqu au paiement de la caution ou acceptation du devis.
2. **Integrite Financiere, Escrow, Abonnements & Paiements** :
   - Expiration d abonnement `Pro Silver` / `Pro Gold` avec suppression de toute reduction de commission apres `premium_until`.
   - Synchronisation sans course entre `geniuspay_status` (polling) et `geniuspay_webhook`.
   - Prise en compte reelle de `Devis.remise`, liberation automatique dans `auto_confirm_interventions`, assiette de commission coherente, filtrage strict `Payment.State.COMPLETE` dans les revenus prestataires.
3. **Recus PDF, In-App & E-mails Transactionnels** :
   - Generation exacte et reconciliee des montants (devis, remise, caution deduite, montant paye, reste a payer), zero fuite de commission interne sur les recus client, dates en francais sans locale OS.
   - E-mails HTML compatibles Gmail/Outlook sans injection ni lien mort, logo inline CID, template dedie mot de passe oublie (expiration 15 min strictement appliquee).
4. **Cartographie & Geolocalisation** :
   - Validation des bornes GPS (`[-90..90]`, `[-180..180]`), stockage securise cote mobile (`loadAddressCoords`), preservation des coordonnees prestataires a l inscription sans ecrasement silencieux vers Abidjan.

---

## 2. Matrice des Menaces et Mitigations Retenues

| ID | Menace / Faille identifiee | Surface / Endpoint | Mitigation appliquee |
|---|---|---|---|
| **T1** | **Attribution multiple (Race Condition SOS)** : 2 prestataires cliquent simultanement sur « Prendre la mission » | `POST /api/prestataire/requests/<ref>/sos-claim/` | Verrou DB `transaction.atomic()` + `Reservation.objects.select_for_update()`. Verifie `assigned_provider is None`, `sos_mode=True`, `sos_expires_at > now`, prestataire `statut='Valide'`, categorie compatible. Reponse `409 sos_already_claimed` pour les suivants. |
| **T2** | **Falsification du forfait / creneau SOS cote client** : un attaquant force `sos_fee_fcfa=0` ou `sos_is_night=False` | `POST /api/client/reservations/create/` | Recalcul 100% serveur via l heure officielle Abidjan (UTC+0, 20h00 a 05h59 ou dimanche) et `PlatformConfig`. Verification `Category.supports_sos=True`. |
| **T3** | **Fuite d adresse exacte & contourne­ment avant paiement/visite** : `api_prestataire_decide_request` exposait l adresse des le clic « Accepter » | `POST /api/prestataire/requests/<ref>/decide/`, `GET /api/prestataire/requests/` | Maintien de `address_is_approximate=True` lors de `accept`. Deblocage exclusif lors de `caution_payee=True` ou `devis_accepte`/`acompte_valide`. |
| **T4** | **Abus d abonnement expire a vie** : un prestataire dont l abonnement Silver/Gold a expire conservait `-5/-10 pts` de commission | `ProviderSubscriptionService`, `wallet_service.py` | Suppression du fallback sur `provider.premium_tier` lorsque `get_subscription(provider)` retourne `None`. Reinitialisation effective en palier `standard`. |
| **T5** | **Course Webhook vs Polling GeniusPay** : `geniuspay_status` passait le paiement a `COMPLETE` sans crediter la reservation/abonnement, bloquant ensuite le webhook | `geniuspay_status`, `geniuspay_webhook` | Helper atomique unique `_finalize_completed_payment(payment)` verrouille par `select_for_update()`, appele par les deux points d entree. |
| **T6** | **Fonds bloques apres auto-confirmation 48h** | `adminpanel.tasks.auto_confirm_interventions` | Mise a jour de `client_confirme_prestation_at` + appel explicite et idempotent a `EscrowService.release_funds(resa)`. |
| **T7** | **Faux montants / remise negative sur devis ou recu** | `Devis.save()`, `api_prestataire_create_devis`, `InvoiceService` | Validation `0 <= remise <= sous_total`. Reconciliaton stricte des totaux PDF/JSON. |
| **T8** | **Confusion OTP inscription vs mot de passe oublie** : `_send_reset_email` utilisait le mauvais template et des durees contradictoires (30 min vs 15 min) | `views_v2._send_reset_email`, `password_reset_otp.html` | Template dedie `password_reset_otp.html`, expiration harmonisee a 15 minutes cote email et serveur, masquage anti-enumeration preserve. |
| **T9** | **Spoofing GPS / Ecrasement ville prestataire** | `api_prestataire_register`, `api_prestataire_location_update`, `LocationReporter` | Controle bornes `[-90..90]`/`[-180..180]`, sauvegarde de `service_latitude`/`service_longitude`, non-ecrasement de `prov.ville` par un simple nom de metropole generique. |

---

## 3. Verifications obligatoires post-implementation

1. Suite Django : `python manage.py check` + tests existants + nouveaux tests unitaires/integration couvrant T1 a T9 (`317+` tests + nouveaux cas SOS, expiration abonnement, course GeniusPay, remise devis, PDF exact).
2. Apps Flutter : `flutter analyze` + `flutter test` sur `babifix_client_flutter` et `babifix_prestataire_flutter`.
3. Zero secret en clair, zero tiret cadratin (`\u2014`) ou semi-cadratin (`\u2013`), zero regression sur les routes existantes.
