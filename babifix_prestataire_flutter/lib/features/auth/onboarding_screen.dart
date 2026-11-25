import 'package:flutter/material.dart';
import '../../babifix_design_system.dart';
import '../../shared/widgets/babifix_button.dart';

class PrestataireOnboardingScreen extends StatefulWidget {
  const PrestataireOnboardingScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<PrestataireOnboardingScreen> createState() =>
      _PrestataireOnboardingScreenState();
}

class _PrestataireOnboardingScreenState
    extends State<PrestataireOnboardingScreen> {
  final _pageCtrl = PageController();
  int _page = 0;

  static const _slides = [
    _Slide(
      icon: Icons.assignment_turned_in_rounded,
      color: BabifixDesign.cyan,
      tag: 'MISSIONS EN TEMPS REEL',
      title: 'Gerez vos missions\nsans effort',
      subtitle:
          'Recevez les demandes qualifiees pres de votre commune, acceptez en un geste et suivez l intervention etape par etape.',
    ),
    _Slide(
      icon: Icons.request_quote_rounded,
      color: BabifixDesign.ciOrange,
      tag: 'DEVIS & NEGOCIATION',
      title: 'Chiffrez et envoyez\nvos devis PRO',
      subtitle:
          'Detaillez main d oeuvre et materiel directement dans l application. Le client valide et bloque l acompte immediatement.',
    ),
    _Slide(
      icon: Icons.account_balance_wallet_rounded,
      color: BabifixDesign.success,
      tag: 'WALLET & MOBILE MONEY',
      title: 'Encaissez en toute\nserenite',
      subtitle:
          'Suivez votre solde et retirez votre argent facilement vers Wave, Orange, MTN ou Moov.',
    ),
  ];

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < _slides.length - 1) {
      _pageCtrl.nextPage(
        duration: BabifixDesign.durationStandard,
        curve: BabifixDesign.curveOut,
      );
    } else {
      widget.onDone();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _slides.length - 1;

    return Scaffold(
      backgroundColor: BabifixDesign.navy,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 16, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.14),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.handyman_rounded,
                          size: 14,
                          color: BabifixDesign.ciOrange,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'BABIFIX PRO',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: widget.onDone,
                    child: Text(
                      'Passer',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.68),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageCtrl,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _SlidePage(slide: _slides[i]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_slides.length, (i) {
                      final active = i == _page;
                      return AnimatedContainer(
                        duration: BabifixDesign.durationFast,
                        curve: BabifixDesign.curveOut,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: active ? 26 : 8,
                        height: 7,
                        decoration: BoxDecoration(
                          color: active
                              ? BabifixDesign.ciOrange
                              : Colors.white.withValues(alpha: 0.24),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 24),
                  BabifixButton(
                    label: isLast ? 'Demarrer mon activite' : 'Suivant',
                    icon: isLast
                        ? Icons.arrow_forward_rounded
                        : Icons.chevron_right_rounded,
                    variant: BabifixButtonVariant.primary,
                    width: double.infinity,
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
}

class _Slide {
  const _Slide({
    required this.icon,
    required this.color,
    required this.tag,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final Color color;
  final String tag;
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
      duration: BabifixDesign.durationStandard,
      vsync: this,
    )..forward();
    _fade = CurvedAnimation(parent: _ctrl, curve: BabifixDesign.curveOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: BabifixDesign.curveOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              color: widget.slide.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: widget.slide.color.withValues(alpha: 0.36),
                width: 1.5,
              ),
            ),
            child: Icon(
              widget.slide.icon,
              size: 52,
              color: widget.slide.color,
            ),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Text(
              widget.slide.tag,
              style: TextStyle(
                color: widget.slide.color,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.slide.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -0.5,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            widget.slide.subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: Colors.white.withValues(alpha: 0.72),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
    if (reduce) return body;
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: body),
    );
  }
}
