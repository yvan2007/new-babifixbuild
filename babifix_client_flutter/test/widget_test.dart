// Tests du formatage monétaire (XOF) de l'app client.
//
// Historique de ce fichier :
//  1. il épinglait des textes d'écran ('Services', 'Dernieres Actualites') →
//     rouge à chaque refonte, et « Dernieres Actualites » n'existe même plus ;
//  2. tenté de le remplacer par un smoke test de boot de l'app entière : non
//     viable en test unitaire, car l'app démarre des services permanents
//     (WebSocket / auto-refresh) dont les timers ne sont jamais annulés →
//     « A Timer is still pending ». C'est légitime en production (l'app tourne
//     en continu), mais intestable sans tout simuler. Le boot se vérifie en
//     test d'intégration, pas ici.
//
// On teste donc la logique PURE et critique, jusqu'ici non couverte : le
// formatage des montants, présent sur les devis, les reçus et les paiements.

import 'package:flutter_test/flutter_test.dart';

import 'package:babifix_client_flutter/babifix_money.dart';

/// Séparateur de milliers réellement produit par le formateur : espace FINE
/// INSÉCABLE (U+202F), et PAS une espace ordinaire. On le construit par code
/// point : à l'œil les deux caractères sont identiques, ce qui rend un test
/// écrit avec une espace normale quasi impossible à déboguer.
final nb = String.fromCharCode(0x202f);

void main() {
  group('formatFcfa', () {
    test('sépare les milliers avec une espace fine insécable', () {
      expect(formatFcfa(12500), '12${nb}500 FCFA');
      expect(formatFcfa(1000), '1${nb}000 FCFA');
      expect(formatFcfa(1000000), '1${nb}000${nb}000 FCFA');
    });

    test('n\'ajoute pas de séparateur sous 1 000', () {
      expect(formatFcfa(0), '0 FCFA');
      expect(formatFcfa(500), '500 FCFA');
      expect(formatFcfa(999), '999 FCFA');
    });

    test('arrondit les décimales (le XOF n\'a pas de centimes)', () {
      expect(formatFcfa(12499.6), '12${nb}500 FCFA');
      expect(formatFcfa(999.4), '999 FCFA');
    });

    test('gère null et les négatifs', () {
      expect(formatFcfa(null), 'N/A');
      // Utilisé pour les lignes de déduction (transport, remise fidélité).
      expect(formatFcfa(-1500), '-1${nb}500 FCFA');
    });

    test('formate les montants réels du modèle BABIFIX', () {
      expect(formatFcfa(5000), '5${nb}000 FCFA'); // plafond transport
      expect(formatFcfa(500), '500 FCFA'); // frais de mise en relation
      expect(formatFcfa(50500), '50${nb}500 FCFA'); // total client de l'exemple
    });
  });

  group('formatFcfaFromString', () {
    test('formate une chaîne numérique', () {
      expect(formatFcfaFromString('12500'), '12${nb}500 FCFA');
      expect(formatFcfaFromString('12500.0'), '12${nb}500 FCFA');
    });

    test('renvoie la chaîne telle quelle si ce n\'est pas un nombre', () {
      expect(formatFcfaFromString('Sur devis'), 'Sur devis');
      expect(formatFcfaFromString(''), '');
    });

    test('renvoie la chaîne telle quelle pour 0 (montant non défini)', () {
      // Choix produit : « 0 » n'est pas un vrai montant — on n'affiche pas
      // « 0 FCFA » sur une demande dont le prix n'est pas encore fixé.
      expect(formatFcfaFromString('0'), '0');
    });
  });
}
