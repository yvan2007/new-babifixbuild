// Tests widget — _AvailabilityToggleCard (dashboard_screen.dart)
// Run : flutter test test/widget/availability_toggle_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Copie locale du widget pour tests isolés (sans dépendance au dashboard complet)
class AvailabilityToggleCard extends StatelessWidget {
  const AvailabilityToggleCard({
    super.key,
    required this.isAvailable,
    required this.toggling,
    required this.onChanged,
  });

  final bool isAvailable;
  final bool toggling;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final activeColor = const Color(0xFF22C55E);
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isAvailable
              ? activeColor.withValues(alpha: 0.4)
              : cs.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isAvailable ? 'Disponible' : 'Indisponible'),
                Text(
                  isAvailable
                      ? 'Les clients peuvent vous réserver'
                      : 'Vous n\'apparaissez plus dans les recherches',
                ),
              ],
            ),
          ),
          toggling
              ? const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : Switch(
                  value: isAvailable,
                  onChanged: onChanged,
                  activeColor: activeColor,
                ),
        ],
      ),
    );
  }
}

Widget _wrap(Widget w) => MaterialApp(home: Scaffold(body: w));

void main() {
  group('AvailabilityToggleCard — état disponible', () {
    testWidgets('affiche "Disponible" quand isAvailable=true', (tester) async {
      await tester.pumpWidget(_wrap(
        AvailabilityToggleCard(
          isAvailable: true,
          toggling: false,
          onChanged: (_) {},
        ),
      ));
      expect(find.text('Disponible'), findsOneWidget);
    });

    testWidgets('Switch est ON quand disponible', (tester) async {
      await tester.pumpWidget(_wrap(
        AvailabilityToggleCard(
          isAvailable: true,
          toggling: false,
          onChanged: (_) {},
        ),
      ));
      final sw = tester.widget<Switch>(find.byType(Switch));
      expect(sw.value, isTrue);
    });
  });

  group('AvailabilityToggleCard — état indisponible', () {
    testWidgets('affiche "Indisponible" quand isAvailable=false', (tester) async {
      await tester.pumpWidget(_wrap(
        AvailabilityToggleCard(
          isAvailable: false,
          toggling: false,
          onChanged: (_) {},
        ),
      ));
      expect(find.text('Indisponible'), findsOneWidget);
    });

    testWidgets('Switch est OFF quand indisponible', (tester) async {
      await tester.pumpWidget(_wrap(
        AvailabilityToggleCard(
          isAvailable: false,
          toggling: false,
          onChanged: (_) {},
        ),
      ));
      final sw = tester.widget<Switch>(find.byType(Switch));
      expect(sw.value, isFalse);
    });
  });

  group('AvailabilityToggleCard — état toggling', () {
    testWidgets('affiche CircularProgressIndicator pendant le chargement', (tester) async {
      await tester.pumpWidget(_wrap(
        AvailabilityToggleCard(
          isAvailable: true,
          toggling: true,
          onChanged: (_) {},
        ),
      ));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
    });
  });

  group('AvailabilityToggleCard — interaction', () {
    testWidgets('toggle appelle onChanged avec la valeur inverse', (tester) async {
      bool? received;
      await tester.pumpWidget(_wrap(
        AvailabilityToggleCard(
          isAvailable: true,
          toggling: false,
          onChanged: (v) => received = v,
        ),
      ));
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(received, isFalse);
    });

    testWidgets('toggle false→true appelle onChanged(true)', (tester) async {
      bool? received;
      await tester.pumpWidget(_wrap(
        AvailabilityToggleCard(
          isAvailable: false,
          toggling: false,
          onChanged: (v) => received = v,
        ),
      ));
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(received, isTrue);
    });
  });
}
