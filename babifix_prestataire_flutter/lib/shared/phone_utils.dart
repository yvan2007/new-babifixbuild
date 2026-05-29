/// Utilitaires téléphone partagés (indicatif / E.164).
///
/// Extrait le numéro national (sans indicatif) d'un numéro E.164 enregistré,
/// pour pré-remplir un IntlPhoneField. Ex: "+2250700000000" -> "0700000000".
String babifixPhoneNational(String saved) {
  var s = (saved).trim().replaceAll(' ', '');
  if (s.isEmpty) return '';
  if (s.startsWith('+225')) return s.substring(4);
  if (s.startsWith('225') && s.length > 10) return s.substring(3);
  if (s.startsWith('+')) {
    final digits = s.substring(1);
    return digits.length > 10 ? digits.substring(digits.length - 10) : digits;
  }
  return s;
}
