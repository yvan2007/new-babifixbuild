import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'babifix_api_config.dart';

/// Result of a social sign-in attempt.
class SocialAuthResult {
  final String? accessToken;
  final String? refreshToken;
  final String? name;
  final String? email;
  final String? error;

  const SocialAuthResult._({
    this.accessToken,
    this.refreshToken,
    this.name,
    this.email,
    this.error,
  });

  factory SocialAuthResult.success({
    required String accessToken,
    required String refreshToken,
    required String name,
    required String email,
  }) =>
      SocialAuthResult._(
        accessToken: accessToken,
        refreshToken: refreshToken,
        name: name,
        email: email,
      );

  factory SocialAuthResult.failure(String error) =>
      SocialAuthResult._(error: error);

  bool get isSuccess => error == null;
}

class SocialAuthService {
  SocialAuthService._();

  static final _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );

  /// Sign in with Google and exchange the ID token with the BABIFIX backend.
  static Future<SocialAuthResult> signInWithGoogle() async {
    try {
      // Trigger the authentication flow
      final account = await _googleSignIn.signIn();
      if (account == null) {
        return SocialAuthResult.failure('Connexion Google annulée.');
      }

      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) {
        return SocialAuthResult.failure(
            'Impossible d\'obtenir le token Google.');
      }

      // Exchange with BABIFIX backend
      final res = await http
          .post(
            Uri.parse('${babifixApiBaseUrl()}/api/auth/social/google/'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'id_token': idToken}),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        return SocialAuthResult.success(
          accessToken: body['access'] as String? ?? '',
          refreshToken: body['refresh'] as String? ?? '',
          name: body['name'] as String? ?? account.displayName ?? '',
          email: body['email'] as String? ?? account.email,
        );
      }

      final msg = _parseError(res.body);
      return SocialAuthResult.failure(msg);
    } on http.ClientException catch (e) {
      return SocialAuthResult.failure('Réseau indisponible : ${e.message}');
    } catch (e) {
      return SocialAuthResult.failure('Erreur Google Sign-In : $e');
    }
  }

  /// Sign in with Apple and exchange the identity token with the BABIFIX backend.
  /// Apple Sign-In is only available on iOS 13+ and macOS.
  static Future<SocialAuthResult> signInWithApple() async {
    final isAppleAvailable = !kIsWeb && Platform.isIOS || Platform.isMacOS;
    if (!isAppleAvailable) {
      return SocialAuthResult.failure(
          'Sign in with Apple n\'est disponible que sur iOS/macOS.');
    }

    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final identityToken = credential.identityToken;
      if (identityToken == null) {
        return SocialAuthResult.failure(
            'Impossible d\'obtenir le token Apple.');
      }

      final name = [
        credential.givenName ?? '',
        credential.familyName ?? '',
      ].where((s) => s.isNotEmpty).join(' ');

      final res = await http
          .post(
            Uri.parse('${babifixApiBaseUrl()}/api/auth/social/apple/'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'identity_token': identityToken,
              'authorization_code': credential.authorizationCode,
              if (name.isNotEmpty) 'name': name,
              if (credential.email != null) 'email': credential.email,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        return SocialAuthResult.success(
          accessToken: body['access'] as String? ?? '',
          refreshToken: body['refresh'] as String? ?? '',
          name: body['name'] as String? ?? name,
          email: body['email'] as String? ?? credential.email ?? '',
        );
      }

      final msg = _parseError(res.body);
      return SocialAuthResult.failure(msg);
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        return SocialAuthResult.failure('Connexion Apple annulée.');
      }
      return SocialAuthResult.failure('Erreur Apple : ${e.message}');
    } on http.ClientException catch (e) {
      return SocialAuthResult.failure('Réseau indisponible : ${e.message}');
    } catch (e) {
      return SocialAuthResult.failure('Erreur Sign in with Apple : $e');
    }
  }

  static String _parseError(String body) {
    try {
      final j = jsonDecode(body) as Map<String, dynamic>;
      return j['detail'] as String? ??
          j['error'] as String? ??
          'Erreur serveur.';
    } catch (_) {
      return 'Erreur serveur.';
    }
  }
}
