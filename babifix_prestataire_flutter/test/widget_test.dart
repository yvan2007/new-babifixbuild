// This is a basic Flutter widget test.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:babifix_prestataire_flutter/main.dart';

void main() {
  testWidgets('Affiche le landing prestataire', (WidgetTester tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const BabifixPrestataireApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('BABIFIX Prestataire'), findsOneWidget);
    expect(find.text('Créer un compte Prestataire'), findsOneWidget);
  });
}
