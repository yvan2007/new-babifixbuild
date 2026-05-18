/// Splash screen BABIFIX — logo réel + animations multi-couches.
///
/// Séquence (1.6 s total) :
///  0.0 → 0.3 s : halo cyan qui s'épanouit derrière le logo
///  0.1 → 0.7 s : logo apparaît (scale elasticOut 0.5 → 1.0) + fade
///  0.5 → 0.9 s : "BABIFIX" slide-up + fade depuis le bas
///  0.7 → 1.0 s : tagline fade
///  ∞ : pulse continu sur le halo + BabifixRingLoader (4 anneaux choregraphiés)
import 'package:flutter/material.dart';

import 'shared/widgets/babifix_ring_loader.dart';

class BabifixSplashScreen extends StatefulWidget {
  const BabifixSplashScreen({super.key});

  @override
  State<BabifixSplashScreen> createState() => _BabifixSplashScreenState();
}

class _BabifixSplashScreenState extends State<BabifixSplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entrance;
  late final AnimationController _idle;

  // Animations de l'entrée (jouent une seule fois)
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

    // Halo immédiatement visible (pas de fade-in) → transition depuis le
    // splash natif Android invisible : seul le pulse idle reste.
    _haloOpacity = const AlwaysStoppedAnimation<double>(1.0);
    _haloScale = const AlwaysStoppedAnimation<double>(1.0);
    // Le logo est déjà visible sur le splash natif Android (même taille,
    // même position). On le maintient à scale 1.0 + opacity 1.0 dès le
    // début pour garantir une transition continue, sans flash ni rebond.
    _logoOpacity = const AlwaysStoppedAnimation<double>(1.0);
    _logoScale = const AlwaysStoppedAnimation<double>(1.0);
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
            // Fond dégradé navy → bleu profond
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF050B1F),
                    Color(0xFF0B1B34),
                    Color(0xFF0E2A56),
                  ],
                  stops: [0.0, 0.55, 1.0],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            // Cercles décoratifs subtils en arrière-plan
            Positioned(
              top: -80,
              right: -80,
              child: _glowCircle(220, 0xFF4CC9F0, 0.08),
            ),
            Positioned(
              bottom: -100,
              left: -100,
              child: _glowCircle(260, 0xFF22C55E, 0.06),
            ),
            // Contenu central
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo + halo qui pulse
                  AnimatedBuilder(
                    animation: Listenable.merge([_entrance, _idle]),
                    builder: (_, __) {
                      // Pulse continu après l'entrée
                      final idleScale = 1.0 + (_idle.value * 0.04);
                      final idleGlow = 0.55 + (_idle.value * 0.20);
                      return SizedBox(
                        width: 200,
                        height: 200,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Halo externe qui pulse
                            Opacity(
                              opacity: _haloOpacity.value * idleGlow,
                              child: Transform.scale(
                                scale: _haloScale.value * idleScale,
                                child: Container(
                                  width: 200,
                                  height: 200,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: const Color(0xFF4CC9F0)
                                        .withValues(alpha: 0.10),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF4CC9F0)
                                            .withValues(alpha: 0.4),
                                        blurRadius: 60,
                                        spreadRadius: 12,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // Anneau lumineux fin
                            Opacity(
                              opacity: _haloOpacity.value * 0.8,
                              child: Container(
                                width: 168,
                                height: 168,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFF4CC9F0)
                                        .withValues(alpha: 0.35),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                            // Logo lui-même
                            Opacity(
                              opacity: _logoOpacity.value,
                              child: Transform.scale(
                                scale: _logoScale.value,
                                child: Container(
                                  width: 140,
                                  height: 140,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.25),
                                        blurRadius: 20,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  padding: const EdgeInsets.all(14),
                                  child: ClipOval(
                                    child: Image.asset(
                                      'assets/images/logo_babifix.png',
                                      fit: BoxFit.contain,
                                    ),
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
                  // Titre BABIFIX qui slide + fade
                  FadeTransition(
                    opacity: _titleOpacity,
                    child: SlideTransition(
                      position: _titleSlide,
                      child: ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [
                            Color(0xFFFFFFFF),
                            Color(0xFF4CC9F0),
                          ],
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
                  const SizedBox(height: 10),
                  // Tagline
                  FadeTransition(
                    opacity: _taglineOpacity,
                    child: const Text(
                      'Vos services à domicile',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white60,
                        letterSpacing: 2.5,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  ),
                  const SizedBox(height: 50),
                  // Loader Uiverse 4-rings (palette cyan/client)
                  FadeTransition(
                    opacity: _loaderOpacity,
                    child: const BabifixRingLoader.cyan(size: 70),
                  ),
                ],
              ),
            ),
            // Pied de page : copyright très discret
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

  Widget _glowCircle(double size, int color, double opacity) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            Color(color).withValues(alpha: opacity),
            Color(color).withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}

// Le loader de chargement est maintenant `BabifixRingLoader` (4 anneaux
// animés Uiverse). Voir `shared/widgets/babifix_ring_loader.dart`.
