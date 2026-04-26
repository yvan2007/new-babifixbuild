import 'package:flutter/material.dart';

class PrestataireOnboardingScreen extends StatefulWidget {
  const PrestataireOnboardingScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<PrestataireOnboardingScreen> createState() =>
      _PrestataireOnboardingScreenState();
}

class _PrestataireOnboardingScreenState
    extends State<PrestataireOnboardingScreen>
    with TickerProviderStateMixin {
  final _pageCtrl = PageController();
  int _page = 0;
  late final AnimationController _bgCtrl;

  static const _slides = [
    _Slide(
      icon: Icons.assignment_turned_in_rounded,
      color: Color(0xFF4CC9F0),
      title: 'Gérez vos missions',
      subtitle:
          'Recevez des demandes de clients, acceptez ou refusez en un glissement, et suivez l\'avancement en temps réel.',
    ),
    _Slide(
      icon: Icons.request_quote_rounded,
      color: Color(0xFF818CF8),
      title: 'Répondez aux devis',
      subtitle:
          'Envoyez vos devis directement depuis l\'app. Le client les reçoit instantanément et peut les accepter ou négocier.',
    ),
    _Slide(
      icon: Icons.account_balance_wallet_rounded,
      color: Color(0xFF22C55E),
      title: 'Suivez vos revenus',
      subtitle:
          'Visualisez vos gains, gérez votre wallet et demandez des retraits en toute simplicité.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _bgCtrl = AnimationController(
      duration: const Duration(seconds: 8),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _bgCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < _slides.length - 1) {
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    } else {
      widget.onDone();
    }
  }

  @override
  Widget build(BuildContext context) {
    final slide = _slides[_page];
    return Scaffold(
      backgroundColor: const Color(0xFF0B1B34),
      body: Stack(
        children: [
          // Fond animé
          AnimatedBuilder(
            animation: _bgCtrl,
            builder: (_, __) {
              return Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(
                        -0.6 + _bgCtrl.value * 1.2,
                        -0.4 + _bgCtrl.value * 0.8,
                      ),
                      radius: 1.4,
                      colors: [
                        slide.color.withValues(alpha: 0.15),
                        const Color(0xFF0B1B34),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          SafeArea(
            child: Column(
              children: [
                // Skip
                Align(
                  alignment: Alignment.topRight,
                  child: TextButton(
                    onPressed: widget.onDone,
                    child: Text(
                      'Passer',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                // Pages
                Expanded(
                  child: PageView.builder(
                    controller: _pageCtrl,
                    itemCount: _slides.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (_, i) => _SlidePage(slide: _slides[i]),
                  ),
                ),
                // Indicateurs + bouton
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                  child: Column(
                    children: [
                      // Dots
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(_slides.length, (i) {
                          final active = i == _page;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: active ? 24 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: active
                                  ? slide.color
                                  : Colors.white.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 28),
                      // Bouton
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                slide.color,
                                slide.color.withValues(alpha: 0.7),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: slide.color.withValues(alpha: 0.35),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: _next,
                              child: Center(
                                child: Text(
                                  _page == _slides.length - 1
                                      ? 'Commencer'
                                      : 'Suivant',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
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
        ],
      ),
    );
  }
}

class _Slide {
  const _Slide({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
}

class _SlidePage extends StatefulWidget {
  const _SlidePage({required this.slide});
  final _Slide slide;

  @override
  State<_SlidePage> createState() => _SlidePageState();
}

class _SlidePageState extends State<_SlidePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    )..forward();
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: widget.slide.color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.slide.color.withValues(alpha: 0.3),
                    width: 2,
                  ),
                ),
                child: Icon(
                  widget.slide.icon,
                  size: 56,
                  color: widget.slide.color,
                ),
              ),
              const SizedBox(height: 40),
              Text(
                widget.slide.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.slide.subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.white.withValues(alpha: 0.65),
                  height: 1.55,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
