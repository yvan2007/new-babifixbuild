import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
// sign_in_with_apple retire cote prestataire : iOS-only et bloque le build
// Android. A re-activer si on deploie l'app pro sur l'App Store.

import '../babifix_api_config.dart';
import '../firebase_options.dart';
import 'error_utils.dart';

class SocialAuthResult {
  final bool isSuccess;
  final String? accessToken;
  final String? refreshToken;
  final String? email;
  final String? name;
  final String role;
  final String? error;

  SocialAuthResult({
    required this.isSuccess,
    this.accessToken,
    this.refreshToken,
    this.email,
    this.name,
    this.role = '',
    this.error,
  });
}

class SocialAuthService {
  static const String _googleServerClientId =
      '583956327591-oj9n36bdfj4o0ras9ecr265g81c4jkll.apps.googleusercontent.com';

  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    clientId: (!kIsWeb && Platform.isIOS)
        ? DefaultFirebaseOptions.ios.iosClientId
        : null,
    serverClientId: _googleServerClientId,
  );

  static Future<SocialAuthResult> signInWithGoogle() async {
    if (!kIsWeb &&
        Platform.isIOS &&
        DefaultFirebaseOptions.ios.appId.contains('CONFIGUREZ_IOS')) {
      return SocialAuthResult(
        isSuccess: false,
        error:
            'Connexion Google en cours d\'activation sur iOS. Utilisez votre telephone ou email.',
      );
    }
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return SocialAuthResult(
          isSuccess: false,
          error: 'Connexion Google annulee.',
        );
      }

      final auth = await googleUser.authentication;
      final idToken = auth.idToken;

      if (idToken == null || idToken.isEmpty) {
        return SocialAuthResult(
          isSuccess: false,
          error: 'Impossible d\'obtenir le jeton Google.',
        );
      }

      final response = await http
          .post(
            Uri.parse('${babifixApiBaseUrl()}/api/auth/google/'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'id_token': idToken,
              'role': 'prestataire',
            }),
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final userMap = data['user'] is Map
            ? Map<String, dynamic>.from(data['user'] as Map)
            : const <String, dynamic>{};
        final token = (data['token'] ??
                data['access_token'] ??
                data['access'] ??
                '')
            .toString();
        final refresh =
            (data['refresh_token'] ?? data['refresh'] ?? '').toString();
        final role = (data['role'] ?? userMap['role'] ?? '').toString();
        return SocialAuthResult(
          isSuccess: token.isNotEmpty,
          accessToken: token,
          refreshToken: refresh,
          email: (userMap['email'] ?? data['email'] ?? googleUser.email)
              .toString(),
          name: (userMap['name'] ??
                  data['name'] ??
                  googleUser.displayName ??
                  '')
              .toString(),
          role: role,
          error: token.isNotEmpty ? null : 'Session serveur non recue.',
        );
      } else {
        final parsedErr =
            apiErrorMessage(response.body) ?? 'Connexion Google refusee (${response.statusCode}).';
        return SocialAuthResult(
          isSuccess: false,
          error: parsedErr,
        );
      }
    } catch (e) {
      return SocialAuthResult(
        isSuccess: false,
        error: 'Erreur Google Sign-In : $e',
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
