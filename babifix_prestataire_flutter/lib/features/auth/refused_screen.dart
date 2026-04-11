import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../babifix_design_system.dart';

class ProviderRefusedScreen extends StatefulWidget {
  const ProviderRefusedScreen({
    super.key,
    required this.reason,
    required this.onEdit,
  });

  final String reason;
  final VoidCallback onEdit;

  @override
  State<ProviderRefusedScreen> createState() => _ProviderRefusedScreenState();
}

class _ProviderRefusedScreenState extends State<ProviderRefusedScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  late Animation<double> _slideAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<double>(begin: 28, end: 0).animate(
      CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic),
    );
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const brandNavy = Color(0xFF0B1B34);
    const refusedBg = Color(0xFFFFF8F6);
    final theme = Theme.of(context);
    final reasonText = widget.reason.isEmpty
        ? 'L\'administration a refusé votre dossier. Veuillez corriger vos informations et soumettre à nouveau.'
        : widget.reason;

    return Scaffold(
      backgroundColor: refusedBg,
      body: AnimatedBuilder(
        animation: _fadeCtrl,
        builder: (context, child) => Opacity(
          opacity: _fadeAnim.value,
          child: Transform.translate(
            offset: Offset(0, _slideAnim.value),
            child: child,
          ),
        ),
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Icône principale animée
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.7, end: 1),
                        duration: const Duration(milliseconds: 800),
                        curve: Curves.easeOutBack,
                        builder: (context, scale, child) =>
                            Transform.scale(scale: scale, child: child),
                        child: Container(
                          width: 110,
                          height: 110,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                Colors.red.shade50,
                                const Color(0xFFFFEDD5),
                              ],
                            ),
                            border: Border.all(
                              color: Colors.red.shade200,
                              width: 2.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.red.withValues(alpha: 0.18),
                                blurRadius: 32,
                                spreadRadius: 4,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Icon(
                              Icons.folder_off_rounded,
                              size: 56,
                              color: Colors.red.shade600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Titre
                      Text(
                        'Votre dossier nécessite\ndes corrections',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: brandNavy,
                          letterSpacing: -0.5,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Lisez attentivement le motif ci-dessous,\ncorrigez et soumettez à nouveau.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: Colors.blueGrey.shade600,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Carte motif de refus (mise en évidence)
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.red.shade300,
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withValues(alpha: 0.1),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header de la carte motif
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 18, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.red.shade100,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(18),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.error_outline_rounded,
                                      color: Colors.red.shade700, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Motif de refus',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                      color: Colors.red.shade800,
                                    ),
                                  ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade700,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Text(
                                      'À corriger',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Corps du motif
                            Padding(
                              padding: const EdgeInsets.all(18),
                              child: Text(
                                reasonText,
                                style: TextStyle(
                                  fontSize: 14.5,
                                  height: 1.6,
                                  color: Colors.red.shade900,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Ce que vous pouvez corriger
                      _WhatToFixCard(),
                      const SizedBox(height: 20),

                      // Message rassurant
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE0F2FE),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFF0EA5E9).withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0EA5E9).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.lightbulb_rounded,
                                color: Color(0xFF0284C7),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Bonne nouvelle',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: Color(0xFF0369A1),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Vous pouvez soumettre à nouveau sans recréer de compte. '
                                    'Votre email et mot de passe sont conservés.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      height: 1.45,
                                      color: Colors.blueGrey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),

                      // CTA principal: corriger et soumettre
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: widget.onEdit,
                          icon: const Icon(Icons.edit_document, size: 20),
                          label: const Text(
                            'Corriger et soumettre à nouveau',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: BabifixDesign.ciOrange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 4,
                            shadowColor: BabifixDesign.ciOrange.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Contacter l'admin
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _showAdminContact(context),
                          icon: const Icon(Icons.support_agent_rounded, size: 18),
                          label: const Text(
                            'Contacter l\'administration',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: brandNavy,
                            side: BorderSide(
                              color: brandNavy.withValues(alpha: 0.35),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 36),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAdminContact(BuildContext context) {
    const navy = Color(0xFF0B1B34);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Contacter l\'administration',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: navy,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Si vous pensez que ce refus est une erreur ou souhaitez des précisions, '
              'contactez-nous directement.',
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: Colors.blueGrey.shade600,
              ),
            ),
            const SizedBox(height: 20),
            _ContactTile(
              icon: Icons.email_outlined,
              title: 'Email',
              value: 'validation@babifix.ci',
              color: const Color(0xFF0084D1),
            ),
            const SizedBox(height: 10),
            _ContactTile(
              icon: Icons.phone_outlined,
              title: 'Téléphone support',
              value: '+225 07 00 00 00 00',
              color: const Color(0xFF059669),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: BabifixDesign.ciOrange.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.schedule_rounded,
                      color: BabifixDesign.ciOrange, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Heures d\'ouverture : Lun–Ven, 8h–18h',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.orange.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
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

class _WhatToFixCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF0B1B34);
    final items = [
      _FixItem(
        icon: Icons.badge_rounded,
        text: 'Vérifiez que votre CNI est lisible (recto et verso)',
        color: const Color(0xFF7C3AED),
      ),
      _FixItem(
        icon: Icons.person_rounded,
        text: 'Assurez-vous que votre photo de profil est claire et récente',
        color: const Color(0xFF0EA5E9),
      ),
      _FixItem(
        icon: Icons.info_rounded,
        text: 'Complétez toutes les informations professionnelles requises',
        color: const Color(0xFF059669),
      ),
    ];

    return Container(
      width: double.infinity,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              children: [
                Icon(Icons.checklist_rounded,
                    color: BabifixDesign.ciOrange, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Points à vérifier',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: navy,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: const Color(0xFFE2E8F0)),
          for (int i = 0; i < items.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: items[i].color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(items[i].icon, color: items[i].color, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      items[i].text,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.45,
                        color: Colors.blueGrey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (i < items.length - 1)
              Divider(
                height: 1,
                indent: 62,
                color: const Color(0xFFF1F5F9),
              ),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _FixItem {
  const _FixItem({
    required this.icon,
    required this.text,
    required this.color,
  });
  final IconData icon;
  final String text;
  final Color color;
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
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
