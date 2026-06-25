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
  if (value == null) return 'N/A';
  return '${_spacedThousands(value.round())} FCFA';
}

/// Formate un montant fourni sous forme de chaîne (ex. « 12500.0 »).
/// Renvoie la chaîne d'origine si elle n'est pas un nombre ou vaut 0.
String formatFcfaFromString(String raw) {
  final n = double.tryParse(raw);
  if (n == null || n == 0) return raw;
  return formatFcfa(n.round());
}
