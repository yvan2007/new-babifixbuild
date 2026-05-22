/// Splash screen BABIFIX Prestataire — variante orange (couleur prestataire).
///
/// Même séquence d'animation que l'app client, mais accentuée orange CI
/// pour qu'on distingue visuellement les deux apps au démarrage.
import 'package:flutter/material.dart';

import 'shared/widgets/babifix_ring_loader.dart';

class BabifixPrestataireSplashScreen extends StatefulWidget {
  const BabifixPrestataireSplashScreen({super.key});

  @override
  State<BabifixPrestataireSplashScreen> createState() =>
      _BabifixPrestataireSplashScreenState();
}

class _BabifixPrestataireSplashScreenState
    extends State<BabifixPrestataireSplashScreen>
    with TickerProviderStateMixin {
  // Couleur d'accent prestataire (orange CI)
  static const _accent = Color(0xFFE87722);
  static const _accentLight = Color(0xFFFFA94D);

  late final AnimationController _entrance;
  late final AnimationController _idle;

  late final Animation<double> _haloOpacity;
  late final Animation<double> _haloScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoScale;
  late final Animation<double> _titleOpacity;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _taglineOpacity;
  late final Animation<double> _loaderOpacity;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..forward();
    _idle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    // Le splash natif Android n'affiche PLUS de logo (fond navy uni). Le logo
    // + le halo s'animent donc ICI, en une seule entrée fluide, en même temps
    // que le titre « BABIFIX » et la pill « PRESTATAIRE ». Plus aucun doublon
    // de logo : on arrive directement sur l'écran avec les écritures.
    _haloOpacity = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
    );
    _haloScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: _entrance,
        curve: const Interval(0.0, 0.55, curve: Curves.easeOutCubic),
      ),
    );
    _logoOpacity = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.08, 0.55, curve: Curves.easeOut),
    );
    _logoScale = Tween<double>(begin: 0.55, end: 1.0).animate(
      CurvedAnimation(
        parent: _entrance,
        curve: const Interval(0.08, 0.7, curve: Curves.elasticOut),
      ),
    );
    _titleOpacity = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.45, 0.75, curve: Curves.easeOut),
    );
    _titleSlide = Tween(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entrance,
        curve: const Interval(0.45, 0.85, curve: Curves.easeOutCubic),
      ),
    );
    _taglineOpacity = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.7, 0.95, curve: Curves.easeOut),
    );
    _loaderOpacity = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.85, 1.0, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _entrance.dispose();
    _idle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Fond dégradé navy avec teinte chaude
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF0A0B1F),
                    Color(0xFF1A1530),
                    Color(0xFF2E1F1F),
                  ],
                  stops: [0.0, 0.55, 1.0],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            // Halos décoratifs
            Positioned(
              top: -80,
              right: -80,
              child: _glowCircle(220, _accent, 0.10),
            ),
            Positioned(
              bottom: -100,
              left: -100,
              child: _glowCircle(260, _accentLight, 0.08),
            ),
            // Contenu central
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: Listenable.merge([_entrance, _idle]),
                    builder: (_, __) {
                      final idleScale = 1.0 + (_idle.value * 0.04);
                      final idleGlow = 0.55 + (_idle.value * 0.20);
                      return SizedBox(
                        width: 200,
                        height: 200,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Halo orange qui pulse
                            Opacity(
                              opacity: _haloOpacity.value * idleGlow,
                              child: Transform.scale(
                                scale: _haloScale.value * idleScale,
                                child: Container(
                                  width: 200,
                                  height: 200,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color:
                                        _accent.withValues(alpha: 0.10),
                                    boxShadow: [
                                      BoxShadow(
                                        color: _accent
                                            .withValues(alpha: 0.40),
                                        blurRadius: 60,
                                        spreadRadius: 12,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // Anneau orange fin
                            Opacity(
                              opacity: _haloOpacity.value * 0.8,
                              child: Container(
                                width: 168,
                                height: 168,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _accent.withValues(alpha: 0.4),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                            // Logo réel — pas de fond blanc, agrandi.
                            Opacity(
                              opacity: _logoOpacity.value,
                              child: Transform.scale(
                                scale: _logoScale.value,
                                child: SizedBox(
                                  width: 180,
                                  height: 180,
                                  child: Image.asset(
                                    'assets/images/logo_babifix.png',
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 36),
                  // Titre BABIFIX en gradient blanc → orange
                  FadeTransition(
                    opacity: _titleOpacity,
                    child: SlideTransition(
                      position: _titleSlide,
                      child: ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [Color(0xFFFFFFFF), _accentLight],
                        ).createShader(bounds),
                        child: const Text(
                          'BABIFIX',
                          style: TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 8,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  FadeTransition(
                    opacity: _titleOpacity,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _accent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _accent.withValues(alpha: 0.45),
                        ),
                      ),
                      child: const Text(
                        'PRESTATAIRE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: _accentLight,
                          letterSpacing: 4,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FadeTransition(
                    opacity: _taglineOpacity,
                    child: const Text(
                      'Gérez vos interventions',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white60,
                        letterSpacing: 2.5,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  ),
                  const SizedBox(height: 50),
                  // Loader Uiverse 4-rings (palette orange/prestataire)
                  FadeTransition(
                    opacity: _loaderOpacity,
                    child: const BabifixRingLoader.orange(size: 70),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 30,
              child: FadeTransition(
                opacity: _loaderOpacity,
                child: const Text(
                  'made in Côte d\'Ivoire',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white30,
                    letterSpacing: 3,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _glowCircle(double size, Color color, double opacity) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: opacity),
            color.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}

// Le loader de chargement est maintenant `BabifixRingLoader.orange`.
// Voir `shared/widgets/babifix_ring_loader.dart`.
