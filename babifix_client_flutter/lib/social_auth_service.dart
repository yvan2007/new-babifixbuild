import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'babifix_api_config.dart';
import 'firebase_options.dart';

/// Result of a social sign-in attempt.
class SocialAuthResult {
  final String? accessToken;
  final String? refreshToken;
  final String? name;
  final String? email;
  final String role;
  final String? error;

  const SocialAuthResult._({
    this.accessToken,
    this.refreshToken,
    this.name,
    this.email,
    this.role = '',
    this.error,
  });

  factory SocialAuthResult.success({
    required String accessToken,
    required String refreshToken,
    required String name,
    required String email,
    String role = '',
  }) =>
      SocialAuthResult._(
        accessToken: accessToken,
        refreshToken: refreshToken,
        name: name,
        email: email,
        role: role,
      );

  factory SocialAuthResult.failure(String error) =>
      SocialAuthResult._(error: error);

  bool get isSuccess => error == null;
}

class SocialAuthService {
  SocialAuthService._();

  // Client ID Web OAuth configure sur Firebase Console (babifix-b6454)
  static const String _googleServerClientId =
      '583956327591-oj9n36bdfj4o0ras9ecr265g81c4jkll.apps.googleusercontent.com';

  static final _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    clientId: (!kIsWeb && Platform.isIOS)
        ? DefaultFirebaseOptions.ios.iosClientId
        : null,
    serverClientId: _googleServerClientId,
  );

  /// Sign in with Google and exchange the ID token with the BABIFIX backend.
  static Future<SocialAuthResult> signInWithGoogle() async {
    if (!kIsWeb &&
        Platform.isIOS &&
        DefaultFirebaseOptions.ios.appId.contains('CONFIGUREZ_IOS')) {
      return SocialAuthResult.failure(
        'Connexion Google en cours d\'activation sur iOS. Utilisez votre telephone ou email.',
      );
    }
    try {
      // Trigger the authentication flow
      final account = await _googleSignIn.signIn();
      if (account == null) {
        return SocialAuthResult.failure('Connexion Google annulée.');
      }

      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null || idToken.isEmpty) {
        return SocialAuthResult.failure(
            'Impossible d\'obtenir le token Google.');
      }

      // Exchange with BABIFIX backend
      final res = await http
          .post(
            Uri.parse('${babifixApiBaseUrl()}/api/auth/google/'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'id_token': idToken,
              'role': 'client',
            }),
          )
          .timeout(const Duration(seconds: 25));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final userMap = body['user'] is Map
            ? Map<String, dynamic>.from(body['user'] as Map)
            : const <String, dynamic>{};
        final access = (body['access'] ??
                body['access_token'] ??
                body['token'] ??
                '')
            .toString();
        final refresh =
            (body['refresh'] ?? body['refresh_token'] ?? '').toString();
        final role = (body['role'] ?? userMap['role'] ?? '').toString();
        return SocialAuthResult.success(
          accessToken: access,
          refreshToken: refresh,
          name: (userMap['name'] ?? body['name'] ?? account.displayName ?? '')
              .toString(),
          email: (userMap['email'] ?? body['email'] ?? account.email).toString(),
          role: role,
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
    final isAppleAvailable = !kIsWeb && (Platform.isIOS || Platform.isMacOS);
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
      if (identityToken == null || identityToken.isEmpty) {
        return SocialAuthResult.failure(
            'Impossible d\'obtenir le token Apple.');
      }

      final name = [
        credential.givenName ?? '',
        credential.familyName ?? '',
      ].where((s) => s.isNotEmpty).join(' ');

      final res = await http
          .post(
            Uri.parse('${babifixApiBaseUrl()}/api/auth/apple/'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'identity_token': identityToken,
              'authorization_code': credential.authorizationCode,
              'role': 'client',
              if (name.isNotEmpty) 'full_name': name,
              if (name.isNotEmpty) 'name': name,
              if (credential.email != null) 'email': credential.email,
            }),
          )
          .timeout(const Duration(seconds: 25));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final userMap = body['user'] is Map
            ? Map<String, dynamic>.from(body['user'] as Map)
            : const <String, dynamic>{};
        final access = (body['access'] ??
                body['access_token'] ??
                body['token'] ??
                '')
            .toString();
        final refresh =
            (body['refresh'] ?? body['refresh_token'] ?? '').toString();
        final role = (body['role'] ?? userMap['role'] ?? '').toString();
        return SocialAuthResult.success(
          accessToken: access,
          refreshToken: refresh,
          name: (userMap['name'] ?? body['name'] ?? name).toString(),
          email: (userMap['email'] ?? body['email'] ?? credential.email ?? '')
              .toString(),
          role: role,
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
      final message = (j['message'] ?? '').toString().trim();
      if (message.isNotEmpty) return message;
      final detail = (j['detail'] ?? '').toString().trim();
      if (detail.isNotEmpty) return detail;
      final code = (j['error'] ?? '').toString().trim();
      switch (code) {
        case 'wrong_app_role':
        case 'forbidden_role':
        case 'role_forbidden':
          return 'Ce compte est associe a une autre application BABIFIX.';
        case 'invalid_audience':
        case 'google_auth_not_configured':
          return 'Configuration Google OAuth incomplete sur le serveur.';
        case 'apple_auth_not_configured':
          return 'Connexion Apple en cours d\'activation.';
        case 'account_disabled':
          return 'Ce compte a ete desactive. Contactez le support.';
        case 'email_not_verified':
          return 'Veuillez verifier votre adresse email Google.';
        default:
          return code.isNotEmpty ? code : 'Erreur serveur.';
      }
    } catch (_) {
      return 'Erreur serveur.';
    }
  }
}
