# BABIFIX BUILD

**Dernière MAJ:** 2026-04-21

## Résumé du projet

**BABIFIX** - Plateforme de services à domicile (Côte d'Ivoire)
- Client Flutter + Prestataire Flutter + Admin Django

## Flow Devis (complet)

```
Client                    Backend                    Prestataire
   |                          |                           |
   |--POST demande--------->|                           |
   |                  |                           |
   |<---DEMANDE_ENVOYEE-----|                           |
   |                  |                           |
   |                  |<------POST accept-------|
   |                  | (DEVIS_EN_COURS)      |
   |                  |                           |
   |                  |----push + WS--------->|
   |                  |                           |
   |<--DEVIS_ENVOYE-----|       poll (5s)          |
   |                  |                           |
   |--POST accept----->|                           |
   |  (Confirmee)    |                           |
   |                  |----push + WS--------->|
   |                  |                           |
   |                  |<----POST demarrer----|
   |                  | (INTERVENTION_EN_COURS)|
   |                  |                           |
   |                  |--push + WS--------->|
   |                  |                           |
   |<--En attente--- |   |--POST terminer-->|
   |  client        |   |(En attente client)|
   |               |   |                      |
   |--confirm----->|   |                         |
   |  (Terminee)  |   |                         |
   |               |   |                         |
   |--POST pay--->|   |<--payment webhook--|
   |  (COMPLETE) |   | (CinetPay)    |
   |               |   |--push--------->| (payment.received)
```

## Commandes

### Backend
```powershell
cd babifix_admin_django
python manage.py runserver 0.0.0.0:8002
```

### Client Flutter
```powershell
cd babifix_client_flutter
flutter run
```

### Prestataire Flutter
```powershell
cd babifix_prestataire_flutter
flutter run
```

## Fichiers clés

| Feature | Backend | Client | Prestataire |
|---------|---------|--------|-----------|
| Devis flow | views.py (api_prestataire_decide_request) | main.dart | requests_screen.dart |
| WebSocket | realtime.py, push_dispatch.py | main.dart (_clientWsChannel) | main.dart |
| StatusPill | - | status_pill.dart | - |
| Waiting payment | - | - | waiting_payment_screen.dart |
| Réservation accepted | - | reservation_accepted_screen.dart | - |

## Statuts supportés

| Statut | Label StatusPill | Action suivante |
|--------|---------------|-------------|
| DEMANDE_ENVOYEE | Demande envoyée | Prestataire accepte |
| DEVIS_EN_COURS | Devis en cours | Prestataire crée devis |
| DEVIS_ENVOYE | Devis reçu | Client accepte |
| DEVIS_ACCEPTE | Devis accepté | Client paie |
| CONFIRMEE | Confirmée | Prestataire démarrant |
| INTERVENTION_EN_COURS | Intervention en cours | Prestataire termine |
| EN_ATTENTE_CLIENT | En attente validation | Client confirme |
| TERMINEE | Terminée | Client note |

## Palette couleurs (premium)

| Usage | Hex | Nom |
|-------|-----|-----|
| Primaire | #0F172A | Navy |
| Accent | #10B981 | Emerald |
| Secondaire | #F8FAFC | Slate-50 |
| Warning | #F59E0B | Amber |
| Error | #EF4444 | Red |