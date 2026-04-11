import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../babifix_design_system.dart';

const _kOnboardingDone = 'babifix_post_signup_onboarding_done';

Future<bool> hasSeenPostSignupOnboarding() async {
  final p = await SharedPreferences.getInstance();
  return p.getBool(_kOnboardingDone) ?? false;
}

Future<void> markPostSignupOnboardingDone() async {
  final p = await SharedPreferences.getInstance();
  await p.setBool(_kOnboardingDone, true);
}

/// Affiche l'onboarding si jamais vu. [onDone] est appelé à la fin ou au skip.
Future<void> showPostSignupOnboardingIfNeeded(
  BuildContext context, {
  required VoidCallback onDone,
}) async {
  if (await hasSeenPostSignupOnboarding()) {
    onDone();
    return;
  }
  if (!context.mounted) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => PostSignupOnboardingScreen(
        onDone: () {
          Navigator.of(context).pop();
          onDone();
        },
      ),
    ),
  );
}

// ── Données des étapes ────────────────────────────���───────────────────────────

const _steps = [
  _Step(
    icon: Icons.search_rounded,
    color: Color(0xFF0084D1),
    title: 'Trouvez un prestataire',
    body:
        'Parcourez notre catalogue de prestataires vérifiés par catégorie ou ville.\n'
        'Utilisez la carte pour voir les artisans près de chez vous.',
  ),
  _Step(
    icon: Icons.calendar_today_rounded,
    color: Color(0xFFF97316),
    title: 'Réservez en un clic',
    body:
        'Choisissez une date et un mode de paiement (espèces ou Mobile Money).\n'
        'Votre prestataire confirme la réservation rapidement.',
  ),
  _Step(
    icon: Icons.star_rounded,
    color: Color(0xFF22C55E),
    title: 'Notez après la prestation',
    body:
        'Une fois la prestation terminée, notez le prestataire pour aider la communauté.\n'
        'Vous pouvez aussi suivre toutes vos réservations dans l\'historique.',
  ),
];

class _Step {
  const _Step({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String body;
}

// ── Écran ─────────────────────────────────────────────────────��──────────────

class PostSignupOnboardingScreen extends StatefulWidget {
  const PostSignupOnboardingScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<PostSignupOnboardingScreen> createState() =>
      _PostSignupOnboardingScreenState();
}

class _PostSignupOnboardingScreenState
    extends State<PostSignupOnboardingScreen> {
  final _ctrl = PageController();
  int _page = 0;

  void _next() {
    if (_page < _steps.length - 1) {
      _ctrl.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    await markPostSignupOnboardingDone();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1628),
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: _finish,
                child: const Text(
                  'Passer',
                  style: TextStyle(color: Colors.white60, fontSize: 14),
                ),
              ),
            ),

            // Pages
            Expanded(
              child: PageView.builder(
                controller: _ctrl,
                onPageChanged: (i) => setState(() => _page = i),
                itemCount: _steps.length,
                itemBuilder: (_, i) => _StepPage(step: _steps[i]),
              ),
            ),

            // Dots + bouton
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: Column(
                children: [
                  // Dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _steps.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _page == i ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _page == i
                              ? BabifixDesign.cyan
                              : Colors.white24,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: BabifixDesign.ciOrange,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: _next,
                      child: Text(
                        _page < _steps.length - 1 ? 'Suivant →' : 'Commencer',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepPage extends StatelessWidget {
  const _StepPage({required this.step});
  final _Step step;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: step.color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(step.icon, size: 60, color: step.color),
          ),
          const SizedBox(height: 40),
          Text(
            step.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            step.body,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 15,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
