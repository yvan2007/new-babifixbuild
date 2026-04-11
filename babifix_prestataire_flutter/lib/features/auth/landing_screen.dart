import 'package:flutter/material.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({
    super.key,
    required this.onCreateAccount,
    required this.onLogin,
  });

  final VoidCallback onCreateAccount;
  final VoidCallback onLogin;

  static const _navy = Color(0xFF0B1B34);
  static const _blue = Color(0xFF0084D1);
  static const _cyan = Color(0xFF4CC9F0);
  static const _orange = Color(0xFFFF9500);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F9FF),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Gradient background
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFFEFF6FF),
                  const Color(0xFFF0F9FF),
                  const Color(0xFFFFFBF5),
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
          // Decorative top blob
          Positioned(
            top: -80,
            right: -60,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _cyan.withValues(alpha: 0.12),
              ),
            ),
          ),
          Positioned(
            bottom: -60,
            left: -80,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _orange.withValues(alpha: 0.08),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 40),

                  // Logo + badge
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          image: const DecorationImage(
                            image: AssetImage('assets/images/babifix-logo.png'),
                            fit: BoxFit.cover,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _blue.withValues(alpha: 0.28),
                              blurRadius: 28,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF059669),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Text(
                          'Pro',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Headline
                  const Text(
                    'BABIFIX Prestataire',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: _navy,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Développez votre activité en Côte d\'Ivoire',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.blueGrey.shade700,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Key benefits card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        _BenefitRow(
                          icon: Icons.people_alt_rounded,
                          color: _blue,
                          title: 'Clients vérifiés',
                          subtitle: 'Accédez à des milliers de particuliers qualifiés',
                        ),
                        const _Divider(),
                        _BenefitRow(
                          icon: Icons.lock_rounded,
                          color: const Color(0xFF059669),
                          title: 'Paiement sécurisé FCFA',
                          subtitle: 'Orange Money, MTN, Wave, Moov — libéré après service',
                        ),
                        const _Divider(),
                        _BenefitRow(
                          icon: Icons.verified_rounded,
                          color: _orange,
                          title: 'Badge Vérifié BABIFIX',
                          subtitle: 'La validation admin renforce votre crédibilité',
                        ),
                        const _Divider(),
                        _BenefitRow(
                          icon: Icons.trending_up_rounded,
                          color: const Color(0xFF7C3AED),
                          title: 'Gagnez plus chaque mois',
                          subtitle: 'Jusqu\'à 300 000+ FCFA/mois pour les top prestataires',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Social proof strip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: _blue.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _blue.withValues(alpha: 0.15)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _MiniStat(value: '10 000+', label: 'Prestataires'),
                        _VerticalDivider(),
                        _MiniStat(value: '4,9 / 5', label: 'Note moyenne'),
                        _VerticalDivider(),
                        _MiniStat(value: '5 villes', label: 'Côte d\'Ivoire'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Primary CTA
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: onCreateAccount,
                      icon: const Icon(Icons.person_add_rounded, size: 20),
                      label: const Text(
                        'Créer un compte Prestataire',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: _blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 4,
                        shadowColor: _blue.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Secondary CTA
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: onLogin,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _navy,
                        side: BorderSide(color: _navy.withValues(alpha: 0.25), width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Déjà inscrit ? Se connecter',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Legal note
                  Text(
                    'Inscription gratuite · Aucune commission cachée\nPaiements conformes ARTCI – Loi n°2013-450',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.blueGrey.shade400,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: Color(0xFF0B1B34),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.blueGrey.shade600,
                    height: 1.4,
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

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, color: const Color(0xFFF1F5F9));
  }
}

class _VerticalDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 32, color: const Color(0xFFE2E8F0));
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            color: Color(0xFF0084D1),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            color: Colors.blueGrey.shade500,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
