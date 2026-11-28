import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:babifix_prestataire_flutter/features/wallet/babifix_wallet_card.dart';
import 'package:babifix_prestataire_flutter/firebase_options.dart';
import 'package:babifix_prestataire_flutter/shared/error_utils.dart';
import 'package:babifix_prestataire_flutter/shared/widgets/babifix_slide_to_confirm.dart';

void main() {
  test('translateErrorCode traduit les erreurs de role et KYC en francais', () {
    expect(translateErrorCode('forbidden_role'), contains('Prestataire'));
    expect(translateErrorCode('kyc_required_to_operate'), contains('KYC'));
    expect(apiErrorMessage('{"error":"wrong_app_role"}'), contains('Prestataire'));
    expect(DefaultFirebaseOptions.ios.appId.contains('CONFIGUREZ_'), isFalse);
    expect(
      DefaultFirebaseOptions.ios.iosBundleId,
      'com.babifix.babifixPrestataireFlutter',
    );
    expect(DefaultFirebaseOptions.ios.iosClientId, isNotEmpty);
    expect(DefaultFirebaseOptions.web.appId.contains('CONFIGUREZ_'), isFalse);
  });

  testWidgets('Pro BabifixSlideToConfirm rollback si echec et verrouille si succes',
      (tester) async {
    var ok = false;
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: BabifixSlideToConfirm(
                label: 'Glisser especes recues',
                onConfirmed: () async {
                  calls++;
                  return ok;
                },
              ),
            ),
          ),
        ),
      ),
    );

    final thumbFinder = find.byIcon(Icons.payments_rounded);
    await tester.drag(thumbFinder, const Offset(300, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(calls, 1);
    expect(find.text('Glisser especes recues'), findsOneWidget);
    expect(find.text('Confirme'), findsNothing);

    ok = true;
    await tester.drag(thumbFinder, const Offset(300, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(calls, 2);
    expect(find.text('Confirme'), findsOneWidget);
  });

  testWidgets('BabifixWalletCard affiche le QR reel et distingue le statut KYC',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BabifixWalletCard(
              soldeFcfa: 45000,
              prestataireName: 'Moussa Diallo',
              maskedCardNumber: '4592 •••• •••• 1234',
              verifyQrUrl: 'https://new-babifixbuild.onrender.com/verify/pro/7-abcdef1234/',
              kycVerified: false,
            ),
          ),
        ),
      ),
    );

    // Retourner la carte via le bouton Verso
    await tester.tap(find.text('Verso'));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.textContaining('KYC EN ATTENTE'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BabifixWalletCard(
              soldeFcfa: 45000,
              prestataireName: 'Moussa Diallo',
              maskedCardNumber: '4592 •••• •••• 1234',
              verifyQrUrl: 'https://new-babifixbuild.onrender.com/verify/pro/7-abcdef1234/',
              kycVerified: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('KYC VERIFIE · CANTONNE'), findsOneWidget);
  });
}
