// Tests unitaires — babifix_api_config.dart
// Run : flutter test test/unit/api_config_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:babifix_client_flutter/babifix_api_config.dart';

void main() {
  group('babifixApiBaseUrl()', () {
    test('retourne une URL non-vide', () {
      final url = babifixApiBaseUrl();
      expect(url, isNotEmpty);
    });

    test('ne se termine pas par un slash', () {
      final url = babifixApiBaseUrl();
      expect(url.endsWith('/'), isFalse);
    });

    test('commence par http:// ou https://', () {
      final url = babifixApiBaseUrl();
      expect(url.startsWith('http://') || url.startsWith('https://'), isTrue);
    });

    test('contient un numéro de port valide ou un hostname', () {
      final url = babifixApiBaseUrl();
      // Doit contenir un hostname ou IP
      expect(url.contains('.') || url.contains('localhost'), isTrue);
    });
  });

  group('babifixWsBaseUrl()', () {
    test('commence par ws:// ou wss://', () {
      final ws = babifixWsBaseUrl();
      expect(ws.startsWith('ws://') || ws.startsWith('wss://'), isTrue);
    });

    test('wss:// si API en https://', () {
      // La logique interne fait https → wss
      final api = babifixApiBaseUrl();
      final ws = babifixWsBaseUrl();
      if (api.startsWith('https://')) {
        expect(ws.startsWith('wss://'), isTrue);
      } else {
        expect(ws.startsWith('ws://'), isTrue);
      }
    });

    test('ne se termine pas par un slash', () {
      final ws = babifixWsBaseUrl();
      expect(ws.endsWith('/'), isFalse);
    });

    test('même host que babifixApiBaseUrl', () {
      final api = babifixApiBaseUrl()
          .replaceFirst('https://', '')
          .replaceFirst('http://', '');
      final ws = babifixWsBaseUrl()
          .replaceFirst('wss://', '')
          .replaceFirst('ws://', '');
      expect(ws, equals(api));
    });
  });
}
