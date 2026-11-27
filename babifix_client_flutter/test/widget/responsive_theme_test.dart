import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:babifix_client_flutter/babifix_design_system.dart';
import 'package:babifix_client_flutter/features/booking/client_journal_screen.dart';
import 'package:babifix_client_flutter/features/booking/confirm_travaux_screen.dart';
import 'package:babifix_client_flutter/features/booking/devis_kanban_screen.dart';
import 'package:babifix_client_flutter/features/disputes/my_disputes_screen.dart';
import 'package:babifix_client_flutter/theme/app_theme.dart';

Widget _themedHarness({
  required Widget child,
  required AppPaletteMode mode,
  required Size size,
  EdgeInsets viewPadding = const EdgeInsets.only(top: 59, bottom: 34),
}) {
  return MaterialApp(
    theme: BabifixTheme.forMode(mode),
    home: MediaQuery(
      data: MediaQueryData(
        size: size,
        padding: viewPadding,
        viewPadding: viewPadding,
        textScaler: const TextScaler.linear(1.3),
      ),
      child: child,
    ),
  );
}

void main() {
  testWidgets('AppBarTheme configure iconTheme contraste sur les 3 palettes',
      (tester) async {
    for (final mode in AppPaletteMode.values) {
      final theme = BabifixTheme.forMode(mode);
      final expectedIconColor = mode == AppPaletteMode.blue
          ? BabifixDesign.textStrongDark
          : BabifixDesign.textStrongLight;
      expect(theme.appBarTheme.iconTheme?.color, expectedIconColor);
      expect(theme.appBarTheme.foregroundColor, expectedIconColor);
    }
  });

  testWidgets(
      'Ecrans client sans erreur layout/overflow sur iPhone SE (320px) et iPhone 17 Pro',
      (tester) async {
    final errors = <FlutterErrorDetails>[];
    final prevOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      errors.add(details);
    };
    try {
      for (final size in [const Size(320, 568), const Size(402, 874)]) {
        for (final mode in AppPaletteMode.values) {
          await tester.pumpWidget(_themedHarness(
            mode: mode,
            size: size,
            child: const MyDisputesScreen(),
          ));
          await tester.pump();
          expect(find.text('Mes litiges'), findsOneWidget);

          await tester.pumpWidget(_themedHarness(
            mode: mode,
            size: size,
            child: const DevisKanbanScreen(reservationReference: 'RES-TEST-1'),
          ));
          await tester.pump();
          expect(find.text('Détail du devis'), findsOneWidget);

          await tester.pumpWidget(_themedHarness(
            mode: mode,
            size: size,
            child: const ClientJournalScreen(reservationReference: 'RES-TEST-1'),
          ));
          await tester.pump();
          expect(find.text('Mon journal'), findsOneWidget);

          await tester.pumpWidget(_themedHarness(
            mode: mode,
            size: size,
            child: ConfirmTravauxScreen(
              reservationReference: 'RES-TEST-1',
              onBack: () {},
              onConfirmed: () {},
            ),
          ));
          await tester.pump();
          expect(find.text('Confirmer les travaux'), findsOneWidget);
        }
      }
      expect(errors, isEmpty);
    } finally {
      FlutterError.onError = prevOnError;
    }
  });
}
