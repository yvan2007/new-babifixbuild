import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter/foundation.dart';

/// Biometric authentication service for BABIFIX Pro (Prestataire) app.
/// Supports Face ID (iOS) and Fingerprint (Android).
class BiometricAuthService {
  BiometricAuthService._();

  static final LocalAuthentication _auth = LocalAuthentication();

  /// Check if biometric authentication is available on the device.
  static Future<bool> isBiometricAvailable() async {
    try {
      final canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      final canAuthenticate = await _auth.isDeviceSupported();
      return canAuthenticateWithBiometrics || canAuthenticate;
    } on PlatformException catch (e) {
      debugPrint('Biometric check failed: ${e.message}');
      return false;
    }
  }

  /// Get available biometric types on the device.
  static Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } on PlatformException {
      return [];
    }
  }

  /// Check if Face ID is available (iOS).
  static Future<bool> isFaceIdAvailable() async {
    final biometrics = await getAvailableBiometrics();
    return biometrics.contains(BiometricType.face);
  }

  /// Check if Fingerprint is available (Android).
  static Future<bool> isFingerprintAvailable() async {
    final biometrics = await getAvailableBiometrics();
    return biometrics.contains(BiometricType.fingerprint) ||
        biometrics.contains(BiometricType.strong);
  }

  /// Authenticate using biometrics.
  static Future<BiometricResult> authenticate({
    String reason = 'Authentifiez-vous pour accéder à BABIFIX Pro',
    bool biometricOnly = false,
  }) async {
    try {
      final isAvailable = await isBiometricAvailable();
      if (!isAvailable) {
        return BiometricResult(
          success: false,
          error: BiometricError.notAvailable,
          message: 'Biométrie non disponible sur cet appareil',
        );
      }

      final didAuthenticate = await _auth.authenticate(
        localizedReason: reason,
        options: AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: biometricOnly,
          useErrorDialogs: true,
          sensitiveTransaction: true,
        ),
      );

      if (didAuthenticate) {
        return BiometricResult(
          success: true,
          error: BiometricError.none,
          message: 'Authentification réussie',
        );
      } else {
        return BiometricResult(
          success: false,
          error: BiometricError.failed,
          message: 'Authentification annulée',
        );
      }
    } on PlatformException catch (e) {
      debugPrint('Biometric auth error: ${e.code} - ${e.message}');

      BiometricError error;
      switch (e.code) {
        case 'NotAvailable':
          error = BiometricError.notAvailable;
          break;
        case 'NotEnrolled':
          error = BiometricError.notEnrolled;
          break;
        case 'LockedOut':
          error = BiometricError.lockedOut;
          break;
        case 'PermanentlyLockedOut':
          error = BiometricError.permanentlyLockedOut;
          break;
        default:
          error = BiometricError.unknown;
      }

      return BiometricResult(
        success: false,
        error: error,
        message: e.message ?? 'Erreur d\'authentification',
      );
    }
  }

  /// Cancel any ongoing authentication.
  static Future<void> cancelAuthentication() async {
    try {
      await _auth.stopAuthentication();
    } catch (_) {}
  }
}

/// Result of a biometric authentication attempt.
class BiometricResult {
  final bool success;
  final BiometricError error;
  final String message;

  BiometricResult({
    required this.success,
    required this.error,
    required this.message,
  });
}

/// Biometric authentication errors.
enum BiometricError {
  none,
  notAvailable,
  notEnrolled,
  failed,
  lockedOut,
  permanentlyLockedOut,
  unknown,
}

/// Extension to get human-readable error messages.
extension BiometricErrorExtension on BiometricError {
  String get userMessage {
    switch (this) {
      case BiometricError.none:
        return '';
      case BiometricError.notAvailable:
        return 'L\'authentification biométrique n\'est pas disponible sur cet appareil.';
      case BiometricError.notEnrolled:
        return 'Aucune biométrie configurée. Veuillez configurer Face ID ou Fingerprint dans les paramètres.';
      case BiometricError.failed:
        return 'Authentification échouée. Veuillez réessayer.';
      case BiometricError.lockedOut:
        return 'Trop de tentatives. Veuillez réessayer dans quelques minutes.';
      case BiometricError.permanentlyLockedOut:
        return 'L\'authentification biométrique est désactivée. Veuillez utiliser votre mot de passe.';
      case BiometricError.unknown:
        return 'Une erreur s\'est produite. Veuillez réessayer.';
    }
  }
}
