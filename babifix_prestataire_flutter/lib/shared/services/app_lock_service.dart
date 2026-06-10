import 'package:shared_preferences/shared_preferences.dart';

import 'biometric_auth.dart';

/// Verrou d'accès à l'application BABIFIX Pro.
///
/// Quand il est activé (depuis Profil → Sécurité → Connexion biométrique),
/// l'app demande une authentification (empreinte / Face ID, OU le code de
/// l'écran de verrouillage du téléphone) au démarrage et au retour
/// d'arrière-plan. On s'appuie sur `local_auth` avec `biometricOnly: false`
/// afin que le code/schéma du téléphone serve de repli si la biométrie
/// n'est pas disponible.
class AppLockService {
  AppLockService._();

  static const _kEnabledKey = 'presta_app_lock_enabled';

  /// Le verrou est-il activé par l'utilisateur ?
  static Future<bool> isEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kEnabledKey) ?? false;
  }

  /// Active / désactive le verrou.
  static Future<void> setEnabled(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kEnabledKey, value);
  }

  /// Lance l'authentification (biométrie OU code de l'appareil).
  /// Retourne true si l'utilisateur est authentifié.
  static Future<bool> authenticate({
    String reason = 'Déverrouillez BABIFIX Pro',
  }) async {
    final res = await BiometricAuthService.authenticate(
      reason: reason,
      biometricOnly: false, // autorise le code/schéma du téléphone en repli
    );
    return res.success;
  }

  /// Y a-t-il un moyen d'authentification utilisable sur l'appareil
  /// (biométrie configurée OU verrouillage d'écran) ?
  static Future<bool> canAuthenticate() async {
    return BiometricAuthService.isBiometricAvailable();
  }
}
