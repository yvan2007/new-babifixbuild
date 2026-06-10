import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Code PIN à 4 chiffres protégeant les transactions du portefeuille
/// (demandes de retrait). Le PIN n'est jamais stocké en clair : on conserve
/// uniquement son empreinte SHA-256 (avec un sel), dans le stockage sécurisé
/// du téléphone (Keystore Android / Keychain iOS).
class WalletPinService {
  WalletPinService._();

  static const _kHashKey = 'wallet_pin_hash';
  static const _salt = 'babifix_wallet_pin_v1';

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static String _hash(String pin) {
    return sha256.convert(utf8.encode('$_salt:$pin')).toString();
  }

  /// Un PIN a-t-il déjà été défini ?
  static Future<bool> hasPin() async {
    final v = await _storage.read(key: _kHashKey);
    return v != null && v.isNotEmpty;
  }

  /// Définit (ou remplace) le PIN. `pin` doit être 4 chiffres.
  static Future<void> setPin(String pin) async {
    await _storage.write(key: _kHashKey, value: _hash(pin));
  }

  /// Vérifie un PIN saisi.
  static Future<bool> verifyPin(String pin) async {
    final stored = await _storage.read(key: _kHashKey);
    if (stored == null || stored.isEmpty) return false;
    return stored == _hash(pin);
  }

  /// Supprime le PIN (réinitialisation).
  static Future<void> clearPin() async {
    await _storage.delete(key: _kHashKey);
  }
}
