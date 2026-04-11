// Tests unitaires — Logique de bucket des statuts de réservation
// Cible : requests_screen.dart → _bucketFromApi() + _labelStatut()
// Run : flutter test test/unit/requests_bucket_test.dart

import 'package:flutter_test/flutter_test.dart';

// Extrait de requests_screen.dart pour tests isolés
String bucketFromApi(String raw) {
  final t = raw.trim();
  if (t == 'Annulee' || t.toLowerCase().contains('annul')) return 'refused';
  if (t == 'En attente' || t.toLowerCase().contains('attente')) return 'pending';
  if (t == 'Terminee' || t.toLowerCase().contains('termin')) return 'completed';
  return 'active';
}

String labelStatut(String apiStatus) {
  switch (apiStatus) {
    case 'Confirmee':
      return 'Confirmée';
    case 'Terminee':
      return 'Terminée';
    case 'Annulee':
      return 'Annulée';
    case 'En cours':
      return 'En cours';
    default:
      return apiStatus;
  }
}

void main() {
  group('bucketFromApi() — mapping statut API → bucket UI', () {
    // Statuts → pending
    test('"En attente" → pending', () {
      expect(bucketFromApi('En attente'), 'pending');
    });

    test('texte contenant "attente" → pending', () {
      expect(bucketFromApi('En attente validation'), 'pending');
    });

    // Statuts → active
    test('"Confirmee" → active', () {
      expect(bucketFromApi('Confirmee'), 'active');
    });

    test('"En cours" → active', () {
      expect(bucketFromApi('En cours'), 'active');
    });

    // Statuts → completed
    test('"Terminee" → completed', () {
      expect(bucketFromApi('Terminee'), 'completed');
    });

    test('texte contenant "termin" → completed', () {
      expect(bucketFromApi('Terminée'), 'completed');
    });

    // Statuts → refused
    test('"Annulee" → refused', () {
      expect(bucketFromApi('Annulee'), 'refused');
    });

    test('texte contenant "annul" → refused', () {
      expect(bucketFromApi('Annulée par client'), 'refused');
    });

    // Espaces parasites
    test('trim des espaces avant/après', () {
      expect(bucketFromApi('  En attente  '), 'pending');
    });

    // Statut inconnu → active (fallback)
    test('statut inconnu → active (fallback)', () {
      expect(bucketFromApi('StatusInconnu'), 'active');
    });

    test('chaîne vide → active (fallback)', () {
      expect(bucketFromApi(''), 'active');
    });
  });

  group('labelStatut() — libellé affiché à l\'utilisateur', () {
    test('"Confirmee" → "Confirmée"', () {
      expect(labelStatut('Confirmee'), 'Confirmée');
    });

    test('"Terminee" → "Terminée"', () {
      expect(labelStatut('Terminee'), 'Terminée');
    });

    test('"Annulee" → "Annulée"', () {
      expect(labelStatut('Annulee'), 'Annulée');
    });

    test('"En cours" → "En cours"', () {
      expect(labelStatut('En cours'), 'En cours');
    });

    test('statut inconnu retourné tel quel', () {
      expect(labelStatut('CustomStatus'), 'CustomStatus');
    });
  });

  group('Couverture complète des transitions', () {
    const allStatuts = [
      'En attente',
      'Confirmee',
      'En cours',
      'Terminee',
      'Annulee',
    ];

    test('tous les statuts API connus produisent un bucket valide', () {
      const validBuckets = {'pending', 'active', 'completed', 'refused'};
      for (final s in allStatuts) {
        final bucket = bucketFromApi(s);
        expect(
          validBuckets.contains(bucket),
          isTrue,
          reason: '"$s" a produit bucket invalide "$bucket"',
        );
      }
    });
  });
}
