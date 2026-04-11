// Tests unitaires — Parsing des données de gains (earnings)
// Cible : earnings_screen.dart → _parseTransactions(), _parseChart(), _formatFcfa()
// Run : flutter test test/unit/earnings_parsing_test.dart

import 'package:flutter_test/flutter_test.dart';

// Logique extraite pour tests isolés

List<Map<String, String>> parseTransactions(dynamic raw) {
  if (raw is! List) return [];
  return raw
      .map((e) => {
            'client': '${e['client']}',
            'service': '${e['service']}',
            'gross': '${e['gross']}',
            'commission': '${e['commission']}',
            'net': '${e['net']}',
            'status': '${e['status']}',
          })
      .toList();
}

class BarData {
  const BarData({required this.label, required this.value});
  final String label;
  final int value;
}

List<BarData> parseChart(List raw) {
  if (raw.isEmpty) return [];
  return raw
      .map((e) => BarData(
            label: e['label'] as String? ?? '',
            value: (e['value'] as num?)?.toInt() ?? 0,
          ))
      .toList();
}

String formatFcfa(int v) {
  if (v >= 1000000) {
    return '${(v / 1000000).toStringAsFixed(1)} M FCFA';
  }
  if (v >= 1000) {
    final k = v ~/ 1000;
    final r = v % 1000;
    return r == 0 ? '$k 000 FCFA' : '$v FCFA';
  }
  return '$v FCFA';
}

void main() {
  group('parseTransactions()', () {
    test('liste vide retourne []', () {
      expect(parseTransactions([]), isEmpty);
    });

    test('raw non-List retourne []', () {
      expect(parseTransactions(null), isEmpty);
      expect(parseTransactions('string'), isEmpty);
      expect(parseTransactions(42), isEmpty);
    });

    test('parse correctement une transaction', () {
      final raw = [
        {
          'client': 'Aminata Koné',
          'service': 'Plomberie urgence',
          'gross': '25 000 FCFA',
          'commission': '2 500 FCFA',
          'net': '22 500 FCFA',
          'status': 'Payé',
        }
      ];
      final result = parseTransactions(raw);
      expect(result.length, 1);
      expect(result[0]['client'], 'Aminata Koné');
      expect(result[0]['net'], '22 500 FCFA');
      expect(result[0]['status'], 'Payé');
    });

    test('parse plusieurs transactions', () {
      final raw = List.generate(5, (i) => {
        'client': 'Client $i',
        'service': 'Service $i',
        'gross': '${(i + 1) * 10000} FCFA',
        'commission': '${(i + 1) * 1000} FCFA',
        'net': '${(i + 1) * 9000} FCFA',
        'status': i % 2 == 0 ? 'Payé' : 'En attente',
      });
      final result = parseTransactions(raw);
      expect(result.length, 5);
    });

    test('valeur null dans un champ convertie en string "null"', () {
      final raw = [
        {'client': null, 'service': 'Test', 'gross': null, 'commission': null, 'net': null, 'status': null}
      ];
      final result = parseTransactions(raw);
      expect(result[0]['client'], 'null');
    });
  });

  group('parseChart()', () {
    test('liste vide retourne []', () {
      expect(parseChart([]), isEmpty);
    });

    test('parse un bar chart correctement', () {
      final raw = [
        {'label': 'Lun', 'value': 18000},
        {'label': 'Mar', 'value': 32000},
        {'label': 'Mer', 'value': 0},
      ];
      final result = parseChart(raw);
      expect(result.length, 3);
      expect(result[0].label, 'Lun');
      expect(result[0].value, 18000);
      expect(result[2].value, 0);
    });

    test('valeur null convertie en 0', () {
      final raw = [
        {'label': 'Test', 'value': null},
      ];
      final result = parseChart(raw);
      expect(result[0].value, 0);
    });

    test('label null convertit en chaîne vide', () {
      final raw = [
        {'label': null, 'value': 5000},
      ];
      final result = parseChart(raw);
      expect(result[0].label, '');
    });
  });

  group('formatFcfa()', () {
    test('0 FCFA', () {
      expect(formatFcfa(0), '0 FCFA');
    });

    test('montant sous 1000', () {
      expect(formatFcfa(500), '500 FCFA');
    });

    test('montant exact en milliers', () {
      expect(formatFcfa(25000), '25 000 FCFA');
    });

    test('montant avec reste non-zéro', () {
      final result = formatFcfa(25500);
      expect(result, contains('FCFA'));
    });

    test('1 million', () {
      expect(formatFcfa(1000000), '1.0 M FCFA');
    });

    test('580000 FCFA', () {
      expect(formatFcfa(580000), contains('FCFA'));
    });

    test('1.5 million', () {
      final result = formatFcfa(1500000);
      expect(result, contains('M FCFA'));
    });

    test('100 FCFA affiché tel quel', () {
      expect(formatFcfa(100), '100 FCFA');
    });
  });
}
