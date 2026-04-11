# Roadmap — Connexion web & OTP téléphone (Côte d’Ivoire)

Ce document décrit une intégration possible **sans l’implémenter entièrement** dans le dépôt actuel (auth mobile = **JWT** déjà en place).

## Objectifs

- Connexion **panel admin** ou **vitrine** avec **django-allauth** (email / social optionnel).
- **OTP SMS** pour numéros **+225** (validation compte ou login secondaire) via un fournisseur (Twilio, Africa’s Talking, Orange SMS API, etc.).

## Étapes techniques (résumé)

1. Ajouter `django-allauth`, `django.contrib.sites`, configurer `SITE_ID`, URLs `accounts/`.
2. Modèle `PhoneNumber` ou champ `UserProfile.phone` (E.164) + `phonenumbers` / `django-phonenumber-field`.
3. Flux OTP : `POST /api/auth/phone/request` → envoi SMS avec code à durée de vie courte ; `POST /api/auth/phone/verify` → session ou jeton.
4. **Ne jamais** logger le code OTP en production ; en dev, option `BABIFIX_OTP_LOG_TO_CONSOLE=1`.
5. Harmoniser avec l’existant : les apps Flutter continuent d’utiliser **JWT** ; l’OTP peut servir au **premier lien** téléphone ↔ compte ou au **support**.

## Fichiers à toucher

- `config/settings.py`, `config/urls.py`
- Nouvelle app `accounts/` ou extension `adminpanel`
- Variables `.env` : clés API SMS, `OTP_EXPIRY_SECONDS`

Une fois le prestataire SMS choisi et les CGU vérifiées, implémenter les vues et les tests (`pytest` / `django.test`).
