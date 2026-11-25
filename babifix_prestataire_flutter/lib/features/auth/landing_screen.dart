import 'package:flutter/material.dart';
import '../../babifix_design_system.dart';
import '../../shared/widgets/babifix_button.dart';
import '../../shared/widgets/payment_method_logo.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({
    super.key,
    required this.onCreateAccount,
    required this.onLogin,
  });

  final VoidCallback onCreateAccount;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    final lightTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: BabifixDesign.navy,
        brightness: Brightness.light,
      ).copyWith(
        primary: BabifixDesign.navy,
        onPrimary: Colors.white,
        surface: Colors.white,
        onSurface: BabifixDesign.textStrongLight,
      ),
    );
    return Theme(
      data: lightTheme,
      child: Scaffold(
        backgroundColor: BabifixDesign.bgSoft,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 30),

              // En-tete marque + badge Pro
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: BabifixDesign.navy,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: BabifixDesign.borderLight,
                        width: 1.2,
                      ),
                      image: const DecorationImage(
                        image: AssetImage('assets/images/babifix-logo.png'),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  Positioned(
                    right: -6,
                    bottom: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3.5,
                      ),
                      decoration: BoxDecoration(
                        color: BabifixDesign.ciOrange,
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Text(
                        'PRO',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),

              const Text(
                'BABIFIX Prestataire',
                style: TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                  color: BabifixDesign.navy,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Developpez votre activite de terrain en Cote d Ivoire',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: BabifixDesign.textMutedLight,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),

              // Carte avantages structuree 1px
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: BabifixDesign.bgWhite,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: BabifixDesign.borderLight),
                ),
                child: const Column(
                  children: [
                    _BenefitRow(
                      icon: Icons.people_alt_rounded,
                      color: BabifixDesign.cyanDeep,
                      title: 'Clients qualifies pres de vous',
                      subtitle:
                          'Demandes geolocalisees et contacts verifies a Abidjan et en region.',
                    ),
                    _Divider(),
                    _BenefitRow(
                      icon: Icons.lock_rounded,
                      color: BabifixDesign.success,
                      title: 'Paiement protege et garanti',
                      subtitle:
                          'Fonds garantis avant demarrage et retrait rapide sur Mobile Money.',
                    ),
                    _Divider(),
                    _BenefitRow(
                      icon: Icons.verified_rounded,
                      color: BabifixDesign.ciOrange,
                      title: 'Badge Artisan Verifie',
                      subtitle:
                          'Le controle KYC renforce la confiance des clients et vos commandes.',
                    ),
                    _Divider(),
                    _BenefitRow(
                      icon: Icons.trending_up_rounded,
                      color: BabifixDesign.navy,
                      title: 'Suivi clair de vos revenus',
                      subtitle:
                          'Wallet dedie, devis rapides et historique complet en FCFA.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Bandeau chiffres & operateurs
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: BabifixDesign.bgWhite,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: BabifixDesign.borderLight),
                ),
                child: const Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _MiniStat(value: '10 000+', label: 'Artisans'),
                        _VerticalDivider(),
                        _MiniStat(value: '4,9 / 5', label: 'Satisfaction'),
                        _VerticalDivider(),
                        _MiniStat(value: '24/7', label: 'Retraits'),
                      ],
                    ),
                    SizedBox(height: 12),
                    BabifixMobileMoneyLogoStrip(height: 22),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              BabifixButton(
                label: 'Creer un compte Prestataire',
                icon: Icons.person_add_rounded,
                variant: BabifixButtonVariant.primary,
                width: double.infinity,
                onPressed: onCreateAccount,
              ),
              const SizedBox(height: 10),
              BabifixButton(
                label: 'Deja inscrit ? Se connecter',
                icon: Icons.login_rounded,
                variant: BabifixButtonVariant.outlined,
                backgroundColor: Colors.white,
                foregroundColor: BabifixDesign.navy,
                width: double.infinity,
                onPressed: onLogin,
              ),
              const SizedBox(height: 20),

              const Text(
                'Inscription gratuite · Aucun frais cache\nPaiements conformes ARTCI · Loi n°2013-450',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  color: BabifixDesign.textMutedLight,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 26),
            ],
          ),
        ),
      ),
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
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: BabifixDesign.navy,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: BabifixDesign.textMutedLight,
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
    return const Divider(height: 1, color: BabifixDesign.borderLight);
  }
}

class _VerticalDivider extends StatelessWidget {
  const _VerticalDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 30, color: BabifixDesign.borderLight);
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
            color: BabifixDesign.navy,
            fontFeatures: BabifixDesign.tabularFigures,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: BabifixDesign.textMutedLight,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
