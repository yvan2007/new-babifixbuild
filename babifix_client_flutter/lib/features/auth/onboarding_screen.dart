import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../babifix_design_system.dart';
import 'biometric_login_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final _pageController = PageController(viewportFraction: 0.88);
  int page = 0;
  late AnimationController _bgController;
  late AnimationController _pulseController;

  static const _slides = <(String, String, String)>[
    (
      'assets/illustrations/onboarding_prestataires.svg',
      'Artisans de confiance à domicile',
      'Plomberie, électricité, rénovation, peinture — des prestataires vérifiés et notés, près de chez vous.',
    ),
    (
      'assets/illustrations/onboarding_intervention.svg',
      'Réservez et parlez au pro',
      'Choisissez un créneau, échangez en direct via le chat de votre réservation avant l\'intervention.',
    ),
    (
      'assets/illustrations/onboarding_suivi.svg',
      'Paiement sécurisé en FCFA',
      'Fonds en séquestre jusqu\'à validation du service. Payez avec Orange Money, MTN ou Wave.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat(reverse: true);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _pageController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _bgController.dispose();
    _pulseController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  double get _pageProgress {
    if (!_pageController.hasClients) return page.toDouble();
    return _pageController.page ?? page.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isLight = theme.brightness == Brightness.light;
    final accentBlue = cs.primary;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          CustomAnimatedBuilder(
            animation: _bgController,
            builder: (context, _) {
              final t = _bgController.value;
              final begin =
                  Alignment.lerp(Alignment.topLeft, Alignment.bottomRight, t) ??
                  Alignment.topLeft;
              final end =
                  Alignment.lerp(Alignment.bottomRight, Alignment.topLeft, t) ??
                  Alignment.bottomRight;
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: begin,
                    end: end,
                    colors: isLight
                        ? [
                            Color.lerp(
                                  const Color(0xFFEFF6FF),
                                  const Color(0xFFF5F3FF),
                                  t,
                                ) ??
                                const Color(0xFFEFF6FF),
                            Color.lerp(
                                  const Color(0xFFDBEAFE),
                                  const Color(0xFFE0E7FF),
                                  1 - t,
                                ) ??
                                const Color(0xFFDBEAFE),
                            Color.lerp(
                                  const Color(0xFFCFFAFE),
                                  const Color(0xFFDCEEFC),
                                  t,
                                ) ??
                                const Color(0xFFCFFAFE),
                          ]
                        : [
                            Color.lerp(
                                  BabifixDesign.navy,
                                  const Color(0xFF0E2844),
                                  t,
                                ) ??
                                BabifixDesign.navy,
                            Color.lerp(
                                  const Color(0xFF0E2844),
                                  const Color(0xFF123A52),
                                  1 - t,
                                ) ??
                                const Color(0xFF0E2844),
                            Color.lerp(
                                  const Color(0xFF123A52),
                                  BabifixDesign.navy,
                                  t,
                                ) ??
                                const Color(0xFF123A52),
                          ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              );
            },
          ),
          Positioned(
            top: -80,
            right: -60,
            child: CustomAnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) {
                final p = _pulseController.value;
                return Container(
                  width: 220 + 40 * p,
                  height: 220 + 40 * p,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (isLight ? accentBlue : BabifixDesign.cyan)
                        .withValues(alpha: isLight ? 0.12 : 0.08),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: widget.onDone,
                      child: Text(
                        'Passer',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: _slides.length,
                      onPageChanged: (v) => setState(() => page = v),
                      itemBuilder: (context, index) {
                        final data = _slides[index];
                        final dist = (_pageProgress - index).abs().clamp(
                          0.0,
                          1.0,
                        );
                        final opacity = (1.0 - dist * 0.65).clamp(0.35, 1.0);
                        final scale = 1.0 - dist * 0.06;
                        final translateY = dist * 28.0;

                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 8,
                          ),
                          child: Transform.translate(
                            offset: Offset(0, translateY),
                            child: Transform.scale(
                              scale: scale,
                              child: Opacity(
                                opacity: opacity,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(32),
                                  child: BackdropFilter(
                                    filter: ImageFilter.blur(
                                      sigmaX: 12,
                                      sigmaY: 12,
                                    ),
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(32),
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: isLight
                                              ? [
                                                  const Color(0xD9FFFFFF),
                                                  const Color(0xB3F8FAFC),
                                                ]
                                              : [
                                                  const Color(0x4D1E293B),
                                                  const Color(0x33111827),
                                                ],
                                        ),
                                        border: Border.all(
                                          color: isLight
                                              ? const Color(0x66FFFFFF)
                                              : const Color(0x33FFFFFF),
                                        ),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          20,
                                          28,
                                          20,
                                          28,
                                        ),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            CustomAnimatedBuilder(
                                              animation: _pulseController,
                                              builder: (context, _) {
                                                final glow =
                                                    0.85 +
                                                    0.15 *
                                                        _pulseController.value;
                                                return Transform.scale(
                                                  scale: index == page
                                                      ? glow
                                                      : 1.0,
                                                  child: Container(
                                                    width: 200,
                                                    height: 200,
                                                    decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      gradient: RadialGradient(
                                                        colors: [
                                                          (isLight
                                                                  ? accentBlue
                                                                  : BabifixDesign
                                                                        .cyan)
                                                              .withValues(
                                                                alpha: 0.25,
                                                              ),
                                                          Colors.transparent,
                                                        ],
                                                      ),
                                                    ),
                                                    alignment: Alignment.center,
                                                    child: Container(
                                                      width: 168,
                                                      height: 168,
                                                      decoration: BoxDecoration(
                                                        shape: BoxShape.circle,
                                                        color: isLight
                                                            ? cs.surfaceContainerHighest
                                                            : const Color(
                                                                0x1FFFFFFF,
                                                              ),
                                                        border: Border.all(
                                                          color: theme
                                                              .dividerColor,
                                                        ),
                                                      ),
                                                      padding:
                                                          const EdgeInsets.all(
                                                            18,
                                                          ),
                                                      child: SvgPicture.asset(
                                                        data.$1,
                                                        fit: BoxFit.contain,
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                            const SizedBox(height: 28),
                                            Text(
                                              data.$2,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 26,
                                                fontWeight: FontWeight.w800,
                                                height: 1.15,
                                                letterSpacing: -0.5,
                                                color: cs.onSurface,
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            Text(
                                              data.$3,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 15,
                                                height: 1.45,
                                                color: cs.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_slides.length, (i) {
                      final active = i == page;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOutCubic,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: active ? 28 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(99),
                          gradient: active
                              ? LinearGradient(
                                  colors: [cs.primary, BabifixDesign.cyan],
                                )
                              : null,
                          color: active
                              ? null
                              : (isLight
                                    ? const Color(0xFFCBD5E1)
                                    : const Color(0xFF475569)),
                          boxShadow: active
                              ? [
                                  BoxShadow(
                                    color: cs.primary.withValues(alpha: 0.45),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : null,
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      if (page > 0)
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => _pageController.previousPage(
                                duration: const Duration(milliseconds: 380),
                                curve: Curves.easeOutCubic,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 16,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: theme.dividerColor),
                                ),
                                child: Icon(
                                  Icons.arrow_back_rounded,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                      Expanded(
                        child: _PremiumOnboardingCta(
                          label: page == _slides.length - 1
                              ? 'Commencer'
                              : 'Suivant',
                          isLast: page == _slides.length - 1,
                          onPressed: page == _slides.length - 1
                              ? widget.onDone
                              : () => _pageController.nextPage(
                                  duration: const Duration(milliseconds: 420),
                                  curve: Curves.easeOutCubic,
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumOnboardingCta extends StatelessWidget {
  const _PremiumOnboardingCta({
    required this.label,
    required this.isLast,
    required this.onPressed,
  });

  final String label;
  final bool isLast;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                BabifixDesign.cyan,
                const Color(0xFF2563EB),
                BabifixDesign.navy,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
            boxShadow: [
              BoxShadow(
                color: BabifixDesign.cyan.withValues(alpha: 0.38),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  isLast
                      ? Icons.rocket_launch_rounded
                      : Icons.arrow_forward_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
