// Tests widget — BabifixEmptyState
// Run : flutter test test/widget/babifix_empty_state_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:babifix_client_flutter/shared/widgets/babifix_empty_state.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: child),
    );

void main() {
  group('BabifixEmptyState — rendu', () {
    testWidgets('affiche le titre', (tester) async {
      await tester.pumpWidget(_wrap(
        const BabifixEmptyState(
          icon: Icons.search_off,
          title: 'Aucun résultat',
          subtitle: 'Modifiez vos critères de recherche.',
        ),
      ));
      expect(find.text('Aucun résultat'), findsOneWidget);
    });

    testWidgets('affiche le sous-titre', (tester) async {
      await tester.pumpWidget(_wrap(
        const BabifixEmptyState(
          icon: Icons.search_off,
          title: 'Titre',
          subtitle: 'Sous-titre explicatif',
        ),
      ));
      expect(find.text('Sous-titre explicatif'), findsOneWidget);
    });

    testWidgets('affiche l\'icône', (tester) async {
      await tester.pumpWidget(_wrap(
        const BabifixEmptyState(
          icon: Icons.inbox_rounded,
          title: 'Vide',
          subtitle: 'Rien ici.',
        ),
      ));
      expect(find.byIcon(Icons.inbox_rounded), findsOneWidget);
    });

    testWidgets('sans CTA : pas de bouton', (tester) async {
      await tester.pumpWidget(_wrap(
        const BabifixEmptyState(
          icon: Icons.search_off,
          title: 'Titre',
          subtitle: 'Sous-titre',
        ),
      ));
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('avec CTA : bouton affiché', (tester) async {
      await tester.pumpWidget(_wrap(
        BabifixEmptyState(
          icon: Icons.search_off,
          title: 'Titre',
          subtitle: 'Sous-titre',
          ctaLabel: 'Voir tout',
          onCta: () {},
        ),
      ));
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.text('Voir tout'), findsOneWidget);
    });

    testWidgets('CTA null : pas de bouton même si ctaLabel fourni', (tester) async {
      await tester.pumpWidget(_wrap(
        const BabifixEmptyState(
          icon: Icons.search_off,
          title: 'Titre',
          subtitle: 'Sous-titre',
          ctaLabel: 'Voir tout',
          // onCta: null (par défaut)
        ),
      ));
      expect(find.byType(FilledButton), findsNothing);
    });
  });

  group('BabifixEmptyState — interaction', () {
    testWidgets('tap sur CTA appelle le callback', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(_wrap(
        BabifixEmptyState(
          icon: Icons.search_off,
          title: 'Titre',
          subtitle: 'Sous-titre',
          ctaLabel: 'Action',
          onCta: () => tapped = true,
        ),
      ));
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(tapped, isTrue);
    });
  });

  group('BabifixEmptyState — couleur personnalisée', () {
    testWidgets('accepte iconColor personnalisée sans erreur', (tester) async {
      await tester.pumpWidget(_wrap(
        const BabifixEmptyState(
          icon: Icons.warning_rounded,
          title: 'Attention',
          subtitle: 'Problème détecté.',
          iconColor: Colors.orange,
        ),
      ));
      expect(tester.takeException(), isNull);
    });
  });
}
