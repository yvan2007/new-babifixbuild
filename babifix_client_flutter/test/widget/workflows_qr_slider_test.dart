import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:babifix_client_flutter/firebase_options.dart';
import 'package:babifix_client_flutter/json_utils.dart';
import 'package:babifix_client_flutter/shared/widgets/babifix_client_shield_card.dart';
import 'package:babifix_client_flutter/shared/widgets/babifix_slide_to_confirm.dart';
import 'package:babifix_client_flutter/theme/app_theme.dart';
import 'package:babifix_client_flutter/user_store.dart';

String _fakeJwt(Map<String, dynamic> payload) {
  final h = base64Url.encode(utf8.encode('{"alg":"HS256","typ":"JWT"}')).replaceAll('=', '');
  final p = base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '');
  return '$h.$p.sig';
}

void main() {
  test('extractJwtRole et traduction erreurs Auth/Role', () {
    expect(BabifixUserStore.extractJwtRole(_fakeJwt({'sub': 1, 'role': 'client'})), 'client');
    expect(BabifixUserStore.extractJwtRole(_fakeJwt({'sub': 2, 'role': 'prestataire'})), 'prestataire');
    expect(BabifixUserStore.extractJwtRole('invalid-token'), '');

    expect(
      babifixTranslateErrorCode('forbidden_role'),
      contains('Client'),
    );
    expect(
      babifixFormatApiErrorBody('{"error":"wrong_app_role"}'),
      contains('Client'),
    );
    expect(DefaultFirebaseOptions.ios.appId.contains('CONFIGUREZ_'), isFalse);
    expect(DefaultFirebaseOptions.ios.iosBundleId, 'com.babifix.client');
    expect(DefaultFirebaseOptions.ios.iosClientId, isNotEmpty);
    expect(DefaultFirebaseOptions.web.appId.contains('CONFIGUREZ_'), isFalse);
  });

  testWidgets('BabifixSlideToConfirm annule l etat si onConfirmed retourne false et confirme si true',
      (tester) async {
    var shouldSucceed = false;
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: BabifixTheme.forMode(AppPaletteMode.white),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: BabifixSlideToConfirm(
                label: 'Glisser pour confirmer',
                onConfirmed: () async {
                  calls++;
                  return shouldSucceed;
                },
              ),
            ),
          ),
        ),
      ),
    );

    // Glisser jusqu a droite -> echec (returns false) : le slider se reinitialise
    final thumbFinder = find.byIcon(Icons.payments_rounded);
    await tester.drag(thumbFinder, const Offset(300, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(calls, 1);
    expect(find.text('Glisser pour confirmer'), findsOneWidget);
    expect(find.text('Confirme'), findsNothing);

    // Second glisser -> succes (returns true)
    shouldSucceed = true;
    await tester.drag(thumbFinder, const Offset(300, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(calls, 2);
    expect(find.text('Confirme'), findsOneWidget);
  });

  testWidgets('BabifixClientShieldCard affiche le QR Code reel au verso', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BabifixTheme.forMode(AppPaletteMode.white),
        home: const Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: BabifixClientShieldCard(
                holderName: 'Aminata Kone',
                tierLabel: 'Or',
                creditFcfa: 15000,
                points: 250,
                missionsCount: 10,
                verifyQrUrl: 'https://new-babifixbuild.onrender.com/verify/client/42-abcdef1234/',
              ),
            ),
          ),
        ),
      ),
    );

    // Basculer sur le verso via tap
    await tester.tap(find.byType(BabifixClientShieldCard));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.textContaining('QR verifie'), findsOneWidget);
  });
}
