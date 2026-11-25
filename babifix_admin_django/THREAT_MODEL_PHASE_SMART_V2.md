# Modele de Menaces : Phase Smart v2 (KYC ONECI, Pre-inscription, Sequestre Plafond, Appels & Audio)

Date : 2026-11-23
Conformite : Loi ivoirienne n° 2013-450 (ARTCI) sur la protection des donnees a caractere personnel.

## 1. Perimetre couvert
1. Moteur KYC algorithmique et validation CNI / MRZ ICAO 9303 (`kyc_engine.py`, `api_prestataire_kyc_submit`, `api_prestataire_register`).
2. Mode Pre-inscription Express Prestataire (60 secondes) et cloisonnement des droits operationnels.
3. Separation Statut Verifie (paliers documents / merite) vs Abonnement (18 / 13 / 8 %) et sequestre obligatoire au-dessus du plafond.
4. Paiement GeniusPay de la caution de visite (`kind="caution"`) et anti-manipulation des montants.
5. Signalisation d'appel bidirectionnelle (`views_calls.py`) et transcription audio a la demande (`audio_transcription_service.py`).
6. Pages SEO locales dynamiques (`babifix_vitrine_django`).

## 2. Matrice des menaces et contre-mesures obligatoires

| Surface | Menace identifiee | Severite | Contre-mesure implementee |
|---|---|---|---|
| **KYC CNI / Fraude multi-comptes** | Reutilisation d'un meme numero CNI ou d'une photo legerement recadree sur plusieurs comptes prestataires. | Critique | Verification d'unicite en base sur `kyc_cni_number` normalise + empreinte SHA-256 + empreinte perceptuelle `dHash` 64 bits (distance de Hamming `<= 5`) entre recto/verso/selfie et entre comptes distincts. |
| **KYC Falsification / Photocopie / Ecran** | Soumission d'une photocopie noir et blanc, photo d'ecran avec reflet, image floue ou MRZ inventee. | Elevee | Convolution Laplacienne 2D (nettete reelle), detection reflets speculaires (`>= 248`), saturation couleur HSV (rejet photocopie N&B), ratio carte ID-1 (`1.586`), coherence teinte peau YCbCr sur selfie, parsing et verification des 4 cles modulo-10 (`7-3-1`) ICAO 9303 TD1 (`CIV`) + coherence expiration (`<= 15 ans`, non expiree). Validation finale humaine admin toujours obligatoire (zero auto-approbation). |
| **KYC PII (Loi 2013-450)** | Fuite de numeros CNI, MRZ ou images base64 dans les logs serveur ou reponses publiques. | Critique | Aucun log des donnees base64 ni des numeros CNI complets. Detail `auto_check_result` accessible uniquement au prestataire proprietaire authentifie et au staff admin. |
| **Pre-inscription Express** | Prestataire pre-inscrit (non valide KYC) tentant d'accepter une demande, repondre a un SOS, creer un devis ou demander un retrait. | Critique | Garde serveur `statut == Provider.Status.VALID` obligatoire sur `accept_demande`, `request_visit`, `create_devis`, `sos_claim` et retraits (`403 kyc_required_to_operate`). Filtrage public strict `statut=VALID` sur le catalogue et la recherche client. |
| **Depassement plafond KYC** | Prestataire Palier 1 (`100 000 FCFA`) creant un devis `> 100 000 FCFA` en mode especes pour contourner la securite. | Elevee | Pas de blocage commercial, mais bascule serveur automatique en `MOBILE_MONEY` (sequestre integral obligatoire, especes desactivees sur la mission) + journalisation alerte Admin (`SystemEventLog`). |
| **Prix exorbitant sans justification** | Devis opaque nettement superieur aux references Abidjan (`> 2x` mediane sur une seule ligne). | Moyenne | Exigence serveur d'au moins 2 lignes detaillees (ex. Main-d'oeuvre + Fournitures) ou note explicative substantielle au-dela de `2x` la mediane (`>= 30 000 FCFA`), plus indicateur neutre `price_vigilance` cote client. |
| **Caution visite GeniusPay** | Falsification du montant caution ou double traitement webhook + polling. | Critique | Montant calcule exclusivement cote serveur (`res.caution_montant + cfg.frais_mise_en_relation_fcfa`). Finalisation idempotente sous `transaction.atomic()` + `select_for_update()` dans `_finalize_completed_payment`. |
| **Appels & Transcription audio** | Arret d'appel par un tiers (IDOR) ou transcription d'un vocal d'une autre conversation / abus quota STT. | Elevee | Controle strict d'appartenance (appelant/appele ou participant a la conversation), rate-limiting sur `/api/audio/transcribe/`, cles STT (`GROQ_API_KEY` / `OPENAI_API_KEY` / `GEMINI_API_KEY`) lues uniquement cote serveur. |
| **SEO Vitrine** | Injection XSS via parametres URL `/services/<metier>/<ville>/` ou contenu JSON-LD non echappe. | Moyenne | Slugs valides contre une liste blanche (404 sinon) et serialisation JSON-LD via `json.dumps` + echappement `</` -> `<\/` via `json_script` / filtre sur. |

## 3. Regle d'honnetete reglementaire (ONECI)
Aucune interrogation directe en temps reel de la base nationale ONECI n'est possible sans convention institutionnelle officielle avec l'ONECI Cote d'Ivoire ou via un prestataire agree (ex. Smile Identity). Le moteur local implemente tous les controles cryptographiques et optiques standardises (ICAO 9303 TD1 MRZ, format NNI/CNI ONECI, qualite/anti-fraude image, unicite inter-comptes) et laisse un adaptateur pret pour `SMILE_IDENTITY_*` ou une future cle conventionnee `ONECI_API_*`.
