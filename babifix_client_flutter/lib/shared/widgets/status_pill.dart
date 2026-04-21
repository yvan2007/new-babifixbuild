import 'package:flutter/material.dart';

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.text});

  final String text;

  String _humanLabel() {
    final t = text.trim();
    if (t == 'DEVIS_ENVOYE') return 'Devis re\u00e7u';
    if (t == 'DEVIS_EN_COURS') return 'Devis en cours';
    if (t == 'DEVIS_ACCEPTE') return 'Devis accept\u00e9';
    if (t == 'DEMANDE_ENVOYEE') return 'Demande envoy\u00e9e';
    if (t == 'INTERVENTION_EN_COURS') return 'Intervention en cours';
    if (t == 'En attente client') return 'En attente validation';
    if (t == 'Confirmee') return 'Confirm\u00e9e';
    if (t == 'Terminee') return 'Termin\u00e9e';
    if (t == 'Annulee') return 'Annul\u00e9e';
    if (t == 'En cours') return 'En cours';
    if (t == 'En attente') return 'En attente';
    return t;
  }

  @override
  Widget build(BuildContext context) {
    final t = _humanLabel();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final isCancelled = text == 'Annulee' || text.contains('Annul');
    final isRunning = text == 'En cours' || text == 'INTERVENTION_EN_COURS';
    final isDone = text == 'Terminee' || text.contains('Termin');
    final isDevisEnvoye = text == 'DEVIS_ENVOYE';
    final isDevisEnCours = text == 'DEVIS_EN_COURS' || text == 'DEVIS_ACCEPTE';
    final isPendingClient = text == 'En attente client';

    Color bg;
    Color fg;
    if (isCancelled) {
      bg = isDark ? const Color(0xFF450A0A) : const Color(0xFFFEE2E2);
      fg = isDark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B);
    } else if (isDevisEnvoye || isDevisEnCours) {
      bg = isDark ? const Color(0xFF1E3A5E) : const Color(0xFFDBEAFE);
      fg = isDark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8);
    } else if (isRunning) {
      bg = isDark ? const Color(0xFF451A03) : const Color(0xFFFEF3C7);
      fg = isDark ? const Color(0xFFFCD34D) : const Color(0xFF92400E);
    } else if (isDone) {
      bg = isDark ? const Color(0xFF1E1B4B) : const Color(0xFFE0E7FF);
      fg = isDark ? const Color(0xFFA5B4FC) : const Color(0xFF3730A3);
    } else if (isPendingClient) {
      bg = isDark ? const Color(0xFF451A03) : const Color(0xFFFEF3C7);
      fg = isDark ? const Color(0xFFFCD34D) : const Color(0xFF92400E);
    } else {
      bg = isDark ? const Color(0xFF052E16) : const Color(0xFFDCFCE7);
      fg = isDark ? const Color(0xFF86EFAC) : const Color(0xFF166534);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        t,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}
