/// Francs CFA (XOF) — affichage « 12 500 FCFA ».

String _spacedThousands(int n) {
  final s = n.abs().toString();
  final buf = StringBuffer();
  if (n < 0) buf.write('-');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) {
      buf.write('\u202f');
    }
    buf.write(s[i]);
  }
  return buf.toString();
}

String formatFcfa(num? value) {
  if (value == null) return '—';
  return '${_spacedThousands(value.round())} FCFA';
}
