import 'package:flutter/material.dart';

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = text.trim();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isRunning = t == 'En cours';
    final isCancelled = t == 'Annulee' || t.contains('Annul');
    final isDone = t == 'Terminee' || t.contains('Termin');

    Color bg;
    Color fg;
    if (isCancelled) {
      bg = isDark ? const Color(0xFF450A0A) : const Color(0xFFFEE2E2);
      fg = isDark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B);
    } else if (isRunning) {
      bg = isDark ? const Color(0xFF451A03) : const Color(0xFFFEF3C7);
      fg = isDark ? const Color(0xFFFCD34D) : const Color(0xFF92400E);
    } else if (isDone) {
      bg = isDark ? const Color(0xFF1E1B4B) : const Color(0xFFE0E7FF);
      fg = isDark ? const Color(0xFFA5B4FC) : const Color(0xFF3730A3);
    } else {
      bg = isDark ? const Color(0xFF052E16) : const Color(0xFFDCFCE7);
      fg = isDark ? const Color(0xFF86EFAC) : const Color(0xFF166534);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        t,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}
