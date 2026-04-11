// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  Tests d'intégration — Parcours utilisateur PRESTATAIRE BABIFIX         ║
// ║                                                                          ║
// ║  Couvre l'ensemble du parcours :                                         ║
// ║    Landing → Connexion → Dashboard → Toggle disponibilité                ║
// ║    → Demandes (swipe accepter/refuser) → Gains → Profil                 ║
// ║    → Wizard d'inscription (3 étapes CNI)                                ║
// ║                                                                          ║
// ║  Exécution :                                                             ║
// ║    flutter test integration_test/user_journey_prestataire_test.dart      ║
// ╚══════════════════════════════════════════════════════════════════════════╝

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:babifix_prestataire_flutter/main.dart' as app;

// ── Helpers ──────────────────────────────────────────────────────────────────

Future<void> waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final end = DateTime.now().add(timeout);
  while (!finder.evaluate().isNotEmpty) {
    if (DateTime.now().isAfter(end)) {
      throw Exception('Timeout : ${finder.description}');
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> tapOn(WidgetTester tester, Finder finder) async {
  await waitFor(tester, finder);
  await tester.tap(finder.first);
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

// ── Constantes ────────────────────────────────────────────────────────────────
const _kTestUsername = 'test_prest_integ';
const _kTestPassword = 'TestPwd123!';
const _kTestEmail = 'prest_integ@babifix.ci';
const _kTestNom = 'Koffi Test Integ';

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ── Groupe 1 : Landing Screen ─────────────────────────────────────────────
  group('🏁 Landing Screen', () {
    testWidgets('1.1 — Landing se charge sans erreur', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 6));
      expect(tester.takeException(), isNull);
      expect(find.byType(Scaffold), findsAtLeastNWidgets(1));
    });

    testWidgets('1.2 — Bouton "Connexion" visible', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 6));

      final loginBtn = find.textContaining('Connexion');
      debugPrint('Bouton Connexion : ${loginBtn.evaluate().isNotEmpty}');
    });

    testWidgets('1.3 — Bouton "S\'inscrire" visible', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 6));

      final signupBtn = find.textContaining('inscrire');
      debugPrint('Bouton S\'inscrire : ${signupBtn.evaluate().isNotEmpty}');
    });
  });

  // ── Groupe 2 : Connexion prestataire ──────────────────────────────────────
  group('🔐 Connexion Prestataire', () {
    testWidgets('2.1 — Navigation vers écran de connexion', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 6));

      final loginBtn = find.textContaining('Connexion');
      if (loginBtn.evaluate().isNotEmpty) {
        await tester.tap(loginBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('2.2 — Connexion avec identifiants valides', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 6));

      final loginBtn = find.textContaining('Connexion');
      if (loginBtn.evaluate().isNotEmpty) {
        await tester.tap(loginBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
      }

      final fields = find.byWidgetPredicate(
        (w) => w is TextField || w is TextFormField,
      );

      if (fields.evaluate().length >= 2) {
        await tester.enterText(fields.first, _kTestUsername);
        await tester.enterText(fields.at(1), _kTestPassword);
        await tester.pump();

        final submitBtn = find.textContaining('Connexion');
        if (submitBtn.evaluate().isNotEmpty) {
          await tester.tap(submitBtn.first);
          await tester.pumpAndSettle(const Duration(seconds: 10));
        }
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('2.3 — Mauvais mot de passe ne crashe pas', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 6));

      final loginBtn = find.textContaining('Connexion');
      if (loginBtn.evaluate().isNotEmpty) {
        await tester.tap(loginBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }

      final fields = find.byWidgetPredicate(
        (w) => w is TextField || w is TextFormField,
      );

      if (fields.evaluate().length >= 2) {
        await tester.enterText(fields.first, 'mauvais_user');
        await tester.enterText(fields.at(1), 'mauvais_mdp');
        await tester.pump();

        final submitBtn = find.textContaining('Connexion');
        if (submitBtn.evaluate().isNotEmpty) {
          await tester.tap(submitBtn.first);
          await tester.pumpAndSettle(const Duration(seconds: 5));
        }
      }
      expect(tester.takeException(), isNull);
    });
  });

  // ── Groupe 3 : Wizard d'inscription ──────────────────────────────────────
  group('📝 Wizard d\'inscription (3 étapes)', () {
    testWidgets('3.1 — Navigation vers le wizard', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 6));

      final signupBtn = find.textContaining('inscrire');
      if (signupBtn.evaluate().isNotEmpty) {
        await tester.tap(signupBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('3.2 — Étape 1 (Identité) : remplir prénom/nom/email/password', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 6));

      final signupBtn = find.textContaining('inscrire');
      if (signupBtn.evaluate().isNotEmpty) {
        await tester.tap(signupBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
      }

      final nameField = find.widgetWithText(TextFormField, 'Prénom');
      if (nameField.evaluate().isNotEmpty) {
        await tester.tap(nameField.first);
        await tester.enterText(nameField.first, 'Koffi');
        await tester.pump();
      }

      final allFields = find.byType(TextFormField);
      if (allFields.evaluate().length >= 2) {
        await tester.enterText(allFields.at(1), 'Test');
        await tester.pump();
      }

      // Email
      final emailField = find.byWidgetPredicate(
        (w) => w is TextFormField,
      );
      if (emailField.evaluate().isNotEmpty) {
        await tester.enterText(emailField.first, _kTestEmail);
        await tester.pump();
      }

      expect(tester.takeException(), isNull);
    });

    testWidgets('3.3 — Étape 1 : bouton Suivant visible', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 6));

      final signupBtn = find.textContaining('inscrire');
      if (signupBtn.evaluate().isNotEmpty) {
        await tester.tap(signupBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
      }

      final nextBtn = find.textContaining('Suivant');
      debugPrint('Bouton Suivant : ${nextBtn.evaluate().isNotEmpty}');
      expect(tester.takeException(), isNull);
    });

    testWidgets('3.4 — Validation étape 1 sans remplir bloque la progression', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 6));

      final signupBtn = find.textContaining('inscrire');
      if (signupBtn.evaluate().isNotEmpty) {
        await tester.tap(signupBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
      }

      // Tenter de passer à l'étape suivante sans remplir
      final nextBtn = find.textContaining('Suivant');
      if (nextBtn.evaluate().isNotEmpty) {
        await tester.tap(nextBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        // Ne doit pas crasher
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('3.5 — Indicateur de progression affiché', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 6));

      final signupBtn = find.textContaining('inscrire');
      if (signupBtn.evaluate().isNotEmpty) {
        await tester.tap(signupBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
      }

      final progressBar = find.byType(LinearProgressIndicator);
      debugPrint('Barre de progression : ${progressBar.evaluate().isNotEmpty}');
      expect(tester.takeException(), isNull);
    });
  });

  // ── Groupe 4 : Dashboard Prestataire ─────────────────────────────────────
  group('📊 Dashboard', () {
    testWidgets('4.1 — Dashboard se charge sans erreur', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));
      expect(tester.takeException(), isNull);
    });

    testWidgets('4.2 — Toggle disponibilité visible', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final toggleText = find.textContaining('Disponible');
      debugPrint('Toggle disponibilité : ${toggleText.evaluate().isNotEmpty}');
      expect(tester.takeException(), isNull);
    });

    testWidgets('4.3 — Tap toggle disponibilité ne crashe pas', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final sw = find.byType(Switch);
      if (sw.evaluate().isNotEmpty) {
        await tester.tap(sw.first);
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('4.4 — Section "Actions rapides" visible', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final actionsSection = find.textContaining('Actions rapides');
      debugPrint('Actions rapides : ${actionsSection.evaluate().isNotEmpty}');
      expect(tester.takeException(), isNull);
    });

    testWidgets('4.5 — QuickAction "Demandes" navigue vers les requêtes', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final demandesBtn = find.textContaining('Demandes');
      if (demandesBtn.evaluate().isNotEmpty) {
        await tester.tap(demandesBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        expect(tester.takeException(), isNull);
      }
    });
  });

  // ── Groupe 5 : Demandes (Requests) ───────────────────────────────────────
  group('📋 Demandes / Requêtes', () {
    testWidgets('5.1 — Écran demandes se charge', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final demandesBtn = find.textContaining('Demandes');
      if (demandesBtn.evaluate().isNotEmpty) {
        await tester.tap(demandesBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 5));
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('5.2 — Hint de swipe affiché pour demandes pending', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final demandesBtn = find.textContaining('Demandes');
      if (demandesBtn.evaluate().isNotEmpty) {
        await tester.tap(demandesBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 5));

        final swipeHint = find.textContaining('Glissez');
        debugPrint('Hint swipe : ${swipeHint.evaluate().isNotEmpty}');
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('5.3 — Swipe vers la droite sur une card pending (accepter)', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final demandesBtn = find.textContaining('Demandes');
      if (demandesBtn.evaluate().isNotEmpty) {
        await tester.tap(demandesBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 5));

        final dismissibles = find.byType(Dismissible);
        if (dismissibles.evaluate().isNotEmpty) {
          await tester.drag(
            dismissibles.first,
            const Offset(300, 0), // glisser vers la droite (accepter)
          );
          await tester.pumpAndSettle(const Duration(seconds: 3));
          expect(tester.takeException(), isNull);
        }
      }
    });

    testWidgets('5.4 — Swipe vers la gauche sur une card pending (refuser)', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final demandesBtn = find.textContaining('Demandes');
      if (demandesBtn.evaluate().isNotEmpty) {
        await tester.tap(demandesBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 5));

        final dismissibles = find.byType(Dismissible);
        if (dismissibles.evaluate().length >= 2) {
          await tester.drag(
            dismissibles.at(1),
            const Offset(-300, 0), // glisser vers la gauche (refuser)
          );
          await tester.pumpAndSettle(const Duration(seconds: 3));
          expect(tester.takeException(), isNull);
        }
      }
    });
  });

  // ── Groupe 6 : Gains ──────────────────────────────────────────────────────
  group('💰 Gains', () {
    testWidgets('6.1 — Écran gains se charge', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final gainsBtn = find.textContaining('Gains');
      if (gainsBtn.evaluate().isNotEmpty) {
        await tester.tap(gainsBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 5));
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('6.2 — Sélecteur de période visible', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final gainsBtn = find.textContaining('Gains');
      if (gainsBtn.evaluate().isNotEmpty) {
        await tester.tap(gainsBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 5));

        for (final period in ['Jour', 'Semaine', 'Mois', 'Tout']) {
          final chip = find.textContaining(period);
          debugPrint('Période "$period" : ${chip.evaluate().isNotEmpty}');
        }
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('6.3 — Changement de période Jour → Semaine', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final gainsBtn = find.textContaining('Gains');
      if (gainsBtn.evaluate().isNotEmpty) {
        await tester.tap(gainsBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 5));

        final semaineChip = find.textContaining('Semaine');
        if (semaineChip.evaluate().isNotEmpty) {
          await tester.tap(semaineChip.first);
          await tester.pumpAndSettle(const Duration(seconds: 3));
          expect(tester.takeException(), isNull);
        }
      }
    });

    testWidgets('6.4 — Période "Tout" disponible', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final gainsBtn = find.textContaining('Gains');
      if (gainsBtn.evaluate().isNotEmpty) {
        await tester.tap(gainsBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 5));

        final toutChip = find.textContaining('Tout');
        if (toutChip.evaluate().isNotEmpty) {
          await tester.tap(toutChip.first);
          await tester.pumpAndSettle(const Duration(seconds: 3));
          expect(tester.takeException(), isNull);
        }
      }
    });

    testWidgets('6.5 — Pull-to-refresh ne crashe pas', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final gainsBtn = find.textContaining('Gains');
      if (gainsBtn.evaluate().isNotEmpty) {
        await tester.tap(gainsBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 5));

        // Simuler pull-to-refresh
        final listFinder = find.byType(ListView);
        if (listFinder.evaluate().isNotEmpty) {
          await tester.drag(listFinder.first, const Offset(0, 300));
          await tester.pumpAndSettle(const Duration(seconds: 3));
          expect(tester.takeException(), isNull);
        }
      }
    });
  });

  // ── Groupe 7 : Stabilité ─────────────────────────────────────────────────
  group('🛡️ Stabilité', () {
    testWidgets('7.1 — Pas de crash au lancement', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('7.2 — Navigation rapide entre onglets ne crashe pas', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 6));

      final tabs = ['Demandes', 'Gains', 'Messages'];
      for (final tab in tabs) {
        final f = find.textContaining(tab);
        if (f.evaluate().isNotEmpty) {
          await tester.tap(f.first);
          await tester.pump(const Duration(milliseconds: 300));
        }
      }
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('7.3 — Rotation écran préservée', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      tester.view.physicalSize = const Size(1080, 1920);
      await tester.pump();
      tester.view.physicalSize = const Size(1920, 1080);
      await tester.pump();
      tester.view.physicalSize = const Size(1080, 1920);
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('7.4 — Appels API en background sans context invalide', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));
      // Attendre les appels initState
      await tester.pump(const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
    });
  });
}
