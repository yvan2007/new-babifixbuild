import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

class PendingScreen extends StatefulWidget {
  const PendingScreen({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  State<PendingScreen> createState() => _PendingScreenState();
}

class _PendingScreenState extends State<PendingScreen>
    with TickerProviderStateMixin {
  static const _primaryBlue = Color(0xFF0084D1);
  static const _cyan = Color(0xFF4CC9F0);
  static const _navy = Color(0xFF0B1B34);
  static const _bg = Color(0xFFF4F9FF);
  static const _logoAsset = 'assets/images/babifix-logo.png';

  late AnimationController _pulseCtrl;
  late AnimationController _fadeCtrl;
  late AnimationController _rotCtrl;
  late Animation<double> _fadeAnim;
  late Animation<double> _slideAnim;

  int _refreshSeconds = 60;
  Timer? _refreshTimer;
  Timer? _countdownTimer;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _rotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<double>(begin: 24, end: 0).animate(
      CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic),
    );
    _fadeCtrl.forward();

    // Auto-refresh toutes les 60 secondes
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) _triggerRefresh();
    });
    // Countdown
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_refreshSeconds > 0) _refreshSeconds--;
        else _refreshSeconds = 60;
      });
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _fadeCtrl.dispose();
    _rotCtrl.dispose();
    _refreshTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _triggerRefresh() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _refreshSeconds = 60;
    });
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() => _refreshing = false);
    widget.onContinue();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: Listenable.merge([_fadeAnim, _slideAnim]),
          builder: (context, child) => Opacity(
            opacity: _fadeAnim.value,
            child: Transform.translate(
              offset: Offset(0, _slideAnim.value),
              child: child,
            ),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Logo
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: _navy,
                    image: const DecorationImage(
                      image: AssetImage(_logoAsset),
                      fit: BoxFit.cover,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _primaryBlue.withValues(alpha: 0.28),
                        blurRadius: 22,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Icône animée (horloge pulsante)
                AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (_, child) {
                    final scale = 1.0 + 0.06 * _pulseCtrl.value;
                    return Transform.scale(scale: scale, child: child);
                  },
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          _cyan.withValues(alpha: 0.25),
                          _primaryBlue.withValues(alpha: 0.08),
                        ],
                      ),
                      border: Border.all(
                        color: _cyan.withValues(alpha: 0.55),
                        width: 2.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _cyan.withValues(alpha: 0.22),
                          blurRadius: 28,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Aiguille tournante
                        AnimatedBuilder(
                          animation: _rotCtrl,
                          builder: (_, __) => Transform.rotate(
                            angle: _rotCtrl.value * 2 * math.pi,
                            child: const Icon(
                              Icons.refresh_rounded,
                              color: _cyan,
                              size: 20,
                            ),
                          ),
                        ),
                        const SizedBox.shrink(),
                        const Icon(Icons.hourglass_top_rounded, color: _primaryBlue, size: 42),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // Titre principal
                const Text(
                  'Votre dossier est en cours\nd\'examen',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: _navy,
                    height: 1.25,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Notre équipe vérifie vos informations et documents.\nVous serez notifié sous 1 à 48 heures.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.55,
                    color: Colors.blueGrey.shade700,
                  ),
                ),
                const SizedBox(height: 28),

                // Indicateur d'étapes
                _StepsIndicator(),
                const SizedBox(height: 28),

                // Conseils en attendant
                _TipsCard(),
                const SizedBox(height: 20),

                // Auto-refresh indicator
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: _primaryBlue.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: _primaryBlue.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_refreshing)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _primaryBlue,
                          ),
                        )
                      else
                        const Icon(Icons.sync_rounded, color: _primaryBlue, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        _refreshing
                            ? 'Vérification en cours…'
                            : 'Vérification auto dans ${_refreshSeconds}s',
                        style: const TextStyle(
                          color: _primaryBlue,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Bouton de vérification manuelle
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _refreshing ? null : _triggerRefresh,
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    label: const Text(
                      'Vérifier maintenant',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: _primaryBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Contacter le support
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _showSupportSheet(context),
                    icon: const Icon(Icons.headset_mic_rounded, size: 18),
                    label: const Text(
                      'Contacter le support',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _primaryBlue,
                      side: BorderSide(color: _primaryBlue.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSupportSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Contacter le support BABIFIX',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: _navy,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Notre équipe est disponible pour répondre à vos questions concernant la validation de votre dossier.',
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: Colors.blueGrey.shade700,
              ),
            ),
            const SizedBox(height: 20),
            _SupportTile(
              icon: Icons.email_rounded,
              label: 'Email support',
              value: 'support@babifix.ci',
              color: _primaryBlue,
            ),
            const SizedBox(height: 10),
            _SupportTile(
              icon: Icons.phone_rounded,
              label: 'Téléphone',
              value: '+225 07 00 00 00 00',
              color: const Color(0xFF059669),
            ),
            const SizedBox(height: 10),
            _SupportTile(
              icon: Icons.chat_bubble_rounded,
              label: 'WhatsApp',
              value: 'Disponible 8h–20h',
              color: const Color(0xFF25D366),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Fermer'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepsIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const primaryBlue = Color(0xFF0084D1);
    const cyan = Color(0xFF4CC9F0);
    const navy = Color(0xFF0B1B34);

    final steps = [
      _Step(label: 'Dossier\nsoumis', done: true, active: false),
      _Step(label: 'En cours\nd\'examen', done: false, active: true),
      _Step(label: 'Compte\nvalidé', done: false, active: false),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          for (int i = 0; i < steps.length; i++) ...[
            Expanded(
              child: Column(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: steps[i].done
                          ? const Color(0xFF059669)
                          : steps[i].active
                              ? primaryBlue
                              : const Color(0xFFE2E8F0),
                      border: steps[i].active
                          ? Border.all(color: cyan, width: 2.5)
                          : null,
                      boxShadow: steps[i].active
                          ? [
                              BoxShadow(
                                color: primaryBlue.withValues(alpha: 0.3),
                                blurRadius: 10,
                                spreadRadius: 2,
                              )
                            ]
                          : null,
                    ),
                    child: Center(
                      child: steps[i].done
                          ? const Icon(Icons.check_rounded, color: Colors.white, size: 22)
                          : steps[i].active
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(Icons.circle_outlined,
                                  color: Colors.blueGrey.shade300, size: 18),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    steps[i].label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: steps[i].active || steps[i].done
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: steps[i].done
                          ? const Color(0xFF059669)
                          : steps[i].active
                              ? navy
                              : Colors.blueGrey.shade400,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            if (i < steps.length - 1)
              Expanded(
                child: Container(
                  height: 2.5,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: i == 0
                        ? const Color(0xFF059669)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Step {
  const _Step({required this.label, required this.done, required this.active});
  final String label;
  final bool done;
  final bool active;
}

class _TipsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const primaryBlue = Color(0xFF0084D1);
    const navy = Color(0xFF0B1B34);

    final tips = [
      _Tip(
        icon: Icons.build_circle_rounded,
        title: 'Préparez vos outils',
        body: 'Assurez-vous d\'avoir tout le matériel nécessaire pour démarrer rapidement après validation.',
        color: const Color(0xFF0EA5E9),
      ),
      _Tip(
        icon: Icons.calendar_today_rounded,
        title: 'Vérifiez vos disponibilités',
        body: 'Réfléchissez aux créneaux où vous êtes disponible pour recevoir vos premières demandes.',
        color: const Color(0xFF7C3AED),
      ),
      _Tip(
        icon: Icons.star_rounded,
        title: 'Soignez votre réputation',
        body: 'Les premiers avis clients sont déterminants. Préparez-vous à offrir un service de qualité.',
        color: const Color(0xFFF59E0B),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'En attendant la validation',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: navy,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              for (int i = 0; i < tips.length; i++) ...[
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: tips[i].color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(tips[i].icon, color: tips[i].color, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tips[i].title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: navy,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              tips[i].body,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.45,
                                color: Colors.blueGrey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (i < tips.length - 1)
                  Divider(
                    height: 1,
                    indent: 68,
                    color: const Color(0xFFE2E8F0),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Tip {
  const _Tip({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
  });
  final IconData icon;
  final String title;
  final String body;
  final Color color;
}

class _SupportTile extends StatelessWidget {
  const _SupportTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0B1B34),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
