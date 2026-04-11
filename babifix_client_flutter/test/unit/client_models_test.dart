// Tests unitaires — Modèles client BABIFIX
// Run : flutter test test/unit/client_models_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:babifix_client_flutter/models/client_models.dart';

void main() {
  group('CategoryTab', () {
    test('crée avec icon Material', () {
      const tab = CategoryTab(
        icon: Icons.plumbing,
        label: 'Plomberie',
        filterKey: 'plomberie',
      );
      expect(tab.label, 'Plomberie');
      expect(tab.filterKey, 'plomberie');
      expect(tab.icon, isNotNull);
      expect(tab.iconNetworkUrl, isNull);
    });

    test('crée avec URL réseau', () {
      const tab = CategoryTab(
        iconNetworkUrl: 'https://babifix.ci/icons/plumber.svg',
        label: 'Plomberie',
        filterKey: 'plomberie',
      );
      expect(tab.iconNetworkUrl, isNotNull);
      expect(tab.icon, isNull);
    });
  });

  group('ClientService', () {
    const service = ClientService(
      title: 'Réparation fuite robinet',
      category: 'Plomberie',
      duration: '2h',
      price: 25000,
      rating: 4.8,
      verified: true,
      color: Colors.blue,
      imageUrl: 'https://babifix.ci/img/plumber.jpg',
      providerId: 42,
    );

    test('price est positif', () {
      expect(service.price, greaterThan(0));
    });

    test('rating entre 0 et 5', () {
      expect(service.rating, inInclusiveRange(0.0, 5.0));
    });

    test('providerId accessible', () {
      expect(service.providerId, 42);
    });

    test('verified flag', () {
      expect(service.verified, isTrue);
    });

    test('service sans providerId vaut 0 par défaut', () {
      const s = ClientService(
        title: 'Test',
        category: 'Test',
        duration: '1h',
        price: 1000,
        rating: 3.0,
        verified: false,
        color: Colors.red,
        imageUrl: '',
      );
      expect(s.providerId, 0);
    });
  });

  group('PaymentMethodOption', () {
    const opt = PaymentMethodOption(
      id: 'ORANGE_MONEY',
      label: 'Orange Money',
      logoUrl: 'https://babifix.ci/logos/orange.png',
    );

    test('id non vide', () {
      expect(opt.id, isNotEmpty);
    });

    test('label non vide', () {
      expect(opt.label, isNotEmpty);
    });

    test('logoUrl est une URL valide', () {
      expect(opt.logoUrl, startsWith('http'));
    });
  });

  group('RecentProviderCard', () {
    const card = RecentProviderCard(
      id: 7,
      nom: 'Koffi Yao',
      specialite: 'Électricité',
      ville: 'Abidjan',
      imageUrl: 'https://babifix.ci/photos/koffi.jpg',
      tarif: 15000.0,
    );

    test('id est positif', () {
      expect(card.id, greaterThan(0));
    });

    test('tarif optionnel non null ici', () {
      expect(card.tarif, isNotNull);
      expect(card.tarif, greaterThan(0));
    });

    test('tarif null par défaut', () {
      const c = RecentProviderCard(
        id: 1,
        nom: 'Test',
        specialite: 'Test',
        ville: 'Test',
        imageUrl: '',
      );
      expect(c.tarif, isNull);
    });
  });
}
