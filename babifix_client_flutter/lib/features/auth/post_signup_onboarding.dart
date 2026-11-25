import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../babifix_design_system.dart';
import '../../shared/widgets/babifix_button.dart';
import '../../shared/widgets/babifix_page_route.dart';

const _kOnboardingDone = 'babifix_post_signup_onboarding_done';
const _kClientHousingPref = 'babifix_client_housing_type';
const _kClientInterestsPref = 'babifix_client_interests';

Future<bool> hasSeenPostSignupOnboarding() async {
  final p = await SharedPreferences.getInstance();
  return p.getBool(_kOnboardingDone) ?? false;
}

Future<void> markPostSignupOnboardingDone() async {
  final p = await SharedPreferences.getInstance();
  await p.setBool(_kOnboardingDone, true);
}

Future<void> saveClientPreferences({
  required String housingType,
  required List<String> interests,
}) async {
  final p = await SharedPreferences.getInstance();
  if (housingType.isNotEmpty) {
    await p.setString(_kClientHousingPref, housingType);
  }
  if (interests.isNotEmpty) {
    await p.setStringList(_kClientInterestsPref, interests);
  }
}

/// Affiche l'onboarding si jamais vu. [onDone] est appele a la fin ou au skip.
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
    babifixRoute<void>(
      (_) => PostSignupOnboardingScreen(
        onDone: () {
          Navigator.of(context).pop();
          onDone();
        },
      ),
    ),
  );
}

// ── Donnees des etapes ───────────────────────────────────────────────────────

const _steps = [
  _Step(
    icon: Icons.search_rounded,
    color: Color(0xFF0084D1),
    title: 'Trouvez un prestataire',
    body:
        'Parcourez notre catalogue de prestataires verifies par categorie ou commune.\n'
        'Utilisez la carte interactive pour trouver les artisans pres de chez vous.',
  ),
  _Step(
    icon: Icons.calendar_today_rounded,
    color: Color(0xFFF97316),
    title: 'Reservez en un clic',
    body:
        'Choisissez une date et un mode de reglement (especes ou Mobile Money securise).\n'
        'Votre prestataire confirme l\'intervention et etablit un devis detaille.',
  ),
  _Step(
    icon: Icons.verified_user_rounded,
    color: Color(0xFF22C55E),
    title: 'Paiement 100 % protege',
    body:
        'Votre argent reste garde en securite par BABIFIX.\n'
        'L\'artisan est paye seulement quand le travail est termine et valide par vous.',
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

// ── Ecran Principal ─────────────────────────────────────────────────────────

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

  // Centres d'interet du client
  String _selectedHousing = 'Villa / Maison';
  final Set<String> _selectedInterests = {
    'Climatisation & Froid',
    'Plomberie & Fuites',
    'Electricite',
  };

  static const _housingOptions = [
    'Villa / Maison',
    'Appartement',
    'Bureau / Entreprise',
    'Boutique / Commerce',
  ];

  static const _interestOptions = [
    'Climatisation & Froid',
    'Plomberie & Fuites',
    'Electricite',
    'Peinture & Deco',
    'Nettoyage & Entretien',
    'Serrurerie Securite',
    'Carrelage & Sols',
    'Jardinage & Piscine',
    'Menuiserie Bois/Alu',
  ];

  // 3 etapes d'explication + 1 etape de personnalisation = 4 pages au total
  int get _totalPages => _steps.length + 1;

  void _next() {
    if (_page < _totalPages - 1) {
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
    await saveClientPreferences(
      housingType: _selectedHousing,
      interests: _selectedInterests.toList(),
    );
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final isLastPage = _page == _totalPages - 1;

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
                itemCount: _totalPages,
                itemBuilder: (_, i) {
                  if (i < _steps.length) {
                    return _StepPage(step: _steps[i]);
                  }
                  return _buildInterestsPage();
                },
              ),
            ),

            // Dots + bouton
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                children: [
                  // Dots indicateurs
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _totalPages,
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
                  const SizedBox(height: 20),
                  BabifixButton(
                    label: isLastPage ? 'Valider et Commencer' : 'Suivant',
                    width: double.infinity,
                    height: 52,
                    onPressed: _next,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Volet Interactif des Centres d'Interet ────────────────────────────────

  Widget _buildInterestsPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: BabifixDesign.cyan.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.tune_rounded, size: 36, color: BabifixDesign.cyan),
            ),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'Vos besoins prioritaires',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 6),
          const Center(
            child: Text(
              'Personnalisez votre accueil en selectionnant vos besoins frequents.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),

          // 1. Type de logement
          const Row(
            children: [
              Icon(Icons.home_work_outlined, size: 16, color: BabifixDesign.cyan),
              SizedBox(width: 6),
              Text(
                'Votre type d\'espace :',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _housingOptions.map((h) {
              final isSel = _selectedHousing == h;
              return ChoiceChip(
                label: Text(h),
                selected: isSel,
                onSelected: (_) => setState(() => _selectedHousing = h),
                selectedColor: BabifixDesign.cyan,
                backgroundColor: const Color(0xFF132238),
                labelStyle: TextStyle(
                  color: isSel ? const Color(0xFF0A1628) : Colors.white70,
                  fontSize: 12,
                  fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: isSel ? BabifixDesign.cyan : const Color(0xFF1E3250),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 22),

          // 2. Services et centres d'interet
          const Row(
            children: [
              Icon(Icons.build_outlined, size: 16, color: BabifixDesign.ciOrange),
              SizedBox(width: 6),
              Text(
                'Services recherches (plusieurs choix) :',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _interestOptions.map((opt) {
              final isSel = _selectedInterests.contains(opt);
              return FilterChip(
                label: Text(opt),
                selected: isSel,
                onSelected: (val) {
                  setState(() {
                    if (val) {
                      _selectedInterests.add(opt);
                    } else {
                      _selectedInterests.remove(opt);
                    }
                  });
                },
                selectedColor: BabifixDesign.ciOrange.withValues(alpha: 0.25),
                backgroundColor: const Color(0xFF132238),
                checkmarkColor: BabifixDesign.ciOrange,
                labelStyle: TextStyle(
                  color: isSel ? Colors.white : Colors.white70,
                  fontSize: 12,
                  fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: isSel ? BabifixDesign.ciOrange : const Color(0xFF1E3250),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
        ],
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
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              color: step.color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(step.icon, size: 54, color: step.color),
          ),
          const SizedBox(height: 36),
          Text(
            step.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          Text(
            step.body,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14.5,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
