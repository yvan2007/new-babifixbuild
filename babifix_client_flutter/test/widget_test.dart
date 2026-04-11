// This is a basic Flutter widget test.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:babifix_client_flutter/main.dart';

void main() {
  testWidgets('Affiche l ecran client', (WidgetTester tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      'client_onboarding_done': true,
      'client_palette': 'light',
    });

    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const BabifixClientApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Services'), findsWidgets);
    expect(find.text('Dernieres Actualites'), findsOneWidget);
  });
}
