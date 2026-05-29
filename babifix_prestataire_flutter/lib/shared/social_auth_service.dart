import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
// sign_in_with_apple retiré côté prestataire : iOS-only et bloque le build
// Android. À ré-activer si on déploie l'app pro sur l'App Store.

import '../babifix_api_config.dart';

class SocialAuthResult {
  final bool isSuccess;
  final String? accessToken;
  final String? refreshToken;
  final String? email;
  final String? name;
  final String? error;

  SocialAuthResult({
    required this.isSuccess,
    this.accessToken,
    this.refreshToken,
    this.email,
    this.name,
    this.error,
  });
}

class SocialAuthService {
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );

  static Future<SocialAuthResult> signInWithGoogle() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return SocialAuthResult(
          isSuccess: false,
          error: 'Google sign in cancelled',
        );
      }

      final auth = await googleUser.authentication;
      final idToken = auth.idToken;

      if (idToken == null) {
        return SocialAuthResult(isSuccess: false, error: 'No Google ID token');
      }

      final response = await http.post(
        Uri.parse('${babifixApiBaseUrl()}/api/auth/google/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id_token': idToken}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return SocialAuthResult(
          isSuccess: true,
          accessToken: data['token'] as String? ?? data['access'] as String?,
          refreshToken: data['refresh'] as String?,
          email: googleUser.email,
          name: googleUser.displayName,
        );
      } else {
        return SocialAuthResult(
          isSuccess: false,
          error: 'Backend auth failed: ${response.statusCode}',
        );
      }
    } catch (e) {
      return SocialAuthResult(
        isSuccess: false,
        error: 'Google sign in error: $e',
      );
    }
  }

  static Future<SocialAuthResult> signInWithApple() async {
    // Stub : Apple Sign In est iOS-only. Sur Android côté prestataire on
    // renvoie un échec propre pour ne pas casser le build.
    return SocialAuthResult(
      isSuccess: false,
      error: "Apple Sign In n'est pas disponible sur cette plateforme.",
    );
  }

  static Future<void> signOut() async {
    await _googleSignIn.signOut();
  }
}
