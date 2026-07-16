// Tests de l'app prestataire BABIFIX.
//
// NB : ce fichier contenait encore le test « compteur » généré par défaut par
// `flutter create` (il pompait `MyApp` et cherchait un bouton « + »). Ni cette
// classe ni ce compteur n'ont jamais existé dans BABIFIX : le fichier ne
// compilait donc plus du tout et la suite de tests était rouge en permanence.
//
// On teste ici la logique PURE et critique : le formatage des montants (XOF).
// Pomper l'app entière (BabifixPrestataireApp) demanderait de simuler Firebase,
// le stockage local et le réseau : ce sera l'objet de tests d'intégration.

import 'package:flutter_test/flutter_test.dart';

import 'package:babifix_prestataire_flutter/babifix_money.dart';

void main() {
  group('formatFcfa', () {
    test('sépare les milliers avec une espace fine insécable', () {
      //   = espace fine insécable (NARROW NO-BREAK SPACE)
      expect(formatFcfa(12500), '12 500 FCFA');
      expect(formatFcfa(1000), '1 000 FCFA');
      expect(formatFcfa(1000000), '1 000 000 FCFA');
    });

    test('n\'ajoute pas de séparateur sous 1 000', () {
      expect(formatFcfa(0), '0 FCFA');
      expect(formatFcfa(500), '500 FCFA');
      expect(formatFcfa(999), '999 FCFA');
    });

    test('arrondit les décimales', () {
      expect(formatFcfa(12499.6), '12 500 FCFA');
      expect(formatFcfa(999.4), '999 FCFA');
    });

    test('gère null et les négatifs', () {
      expect(formatFcfa(null), 'N/A');
      expect(formatFcfa(-1500), '-1 500 FCFA');
    });
  });

  group('formatFcfaFromString', () {
    test('formate une chaîne numérique', () {
      expect(formatFcfaFromString('12500'), '12 500 FCFA');
      expect(formatFcfaFromString('12500.0'), '12 500 FCFA');
    });

    test('renvoie la chaîne telle quelle si ce n\'est pas un nombre', () {
      expect(formatFcfaFromString('Sur devis'), 'Sur devis');
      expect(formatFcfaFromString(''), '');
    });

    test('renvoie la chaîne telle quelle pour 0 (montant non défini)', () {
      // Choix produit : « 0 » n'est pas un vrai montant, on n'affiche pas
      // « 0 FCFA » sur une demande dont le prix n'est pas encore fixé.
      expect(formatFcfaFromString('0'), '0');
    });
  });
}
