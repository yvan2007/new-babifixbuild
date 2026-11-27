import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:babifix_prestataire_flutter/babifix_design_system.dart';
import 'package:babifix_prestataire_flutter/features/availability/availability_screen.dart';
import 'package:babifix_prestataire_flutter/features/disputes/presta_disputes_screen.dart';
import 'package:babifix_prestataire_flutter/features/kyc/kyc_screen.dart';
import 'package:babifix_prestataire_flutter/shared/app_palette_mode.dart';

ThemeData _prestataireTheme(AppPaletteMode mode) {
  final isDark = mode == AppPaletteMode.blue;
  final isWhite = mode == AppPaletteMode.white;
  final bg = isDark
      ? BabifixDesign.navy
      : (isWhite ? BabifixDesign.bgWhite : BabifixDesign.bgLight);
  final onBg =
      isDark ? BabifixDesign.textStrongDark : BabifixDesign.textStrongLight;
  return ThemeData(
    useMaterial3: true,
    brightness: isDark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: bg,
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: onBg,
      iconTheme: IconThemeData(color: onBg),
      actionsIconTheme: IconThemeData(color: onBg),
    ),
  );
}

Widget _harness({
  required Widget child,
  required AppPaletteMode mode,
  required Size size,
}) {
  const pad = EdgeInsets.only(top: 59, bottom: 34);
  return MaterialApp(
    theme: _prestataireTheme(mode),
    home: MediaQuery(
      data: MediaQueryData(
        size: size,
        padding: pad,
        viewPadding: pad,
        textScaler: const TextScaler.linear(1.3),
      ),
      child: child,
    ),
  );
}

void main() {
  testWidgets(
      'AvailabilityScreen suit le theme actif avec fleche retour contrastee et zero overflow',
      (tester) async {
    final errors = <FlutterErrorDetails>[];
    final prevOnError = FlutterError.onError;
    FlutterError.onError = (details) => errors.add(details);
    try {
      for (final mode in AppPaletteMode.values) {
        final rootKey = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: rootKey,
            theme: _prestataireTheme(mode),
            home: const Scaffold(body: SizedBox.shrink()),
          ),
        );
        rootKey.currentState!.push(
          MaterialPageRoute(
            builder: (_) => const MediaQuery(
              data: MediaQueryData(
                size: Size(320, 568),
                padding: EdgeInsets.only(top: 59, bottom: 34),
                viewPadding: EdgeInsets.only(top: 59, bottom: 34),
                textScaler: TextScaler.linear(1.3),
              ),
              child: AvailabilityScreen(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        final backBtn = tester.widget<BackButton>(find.byType(BackButton));
        final expected = mode == AppPaletteMode.blue
            ? BabifixDesign.textStrongDark
            : BabifixDesign.textStrongLight;
        expect(backBtn.color, expected);
        expect(find.text('Mes disponibilités'), findsOneWidget);
      }
      expect(errors, isEmpty);
    } finally {
      FlutterError.onError = prevOnError;
    }
  });

  testWidgets(
      'PrestaDisputesScreen et KycScreen rendent sans overflow sur 320px et 402x874',
      (tester) async {
    final errors = <FlutterErrorDetails>[];
    final prevOnError = FlutterError.onError;
    FlutterError.onError = (details) => errors.add(details);
    try {
      for (final size in [const Size(320, 568), const Size(402, 874)]) {
        for (final mode in AppPaletteMode.values) {
          await tester.pumpWidget(_harness(
            mode: mode,
            size: size,
            child: const PrestaDisputesScreen(),
          ));
          await tester.pump();
          expect(find.text('Litiges'), findsOneWidget);

          await tester.pumpWidget(_harness(
            mode: mode,
            size: size,
            child: KYCScreen(
              paletteMode: mode,
              onBack: () {},
            ),
          ));
          await tester.pump();
          expect(find.text('Verifier mon compte'), findsOneWidget);
        }
      }
      expect(errors, isEmpty);
    } finally {
      FlutterError.onError = prevOnError;
    }
  });
}
