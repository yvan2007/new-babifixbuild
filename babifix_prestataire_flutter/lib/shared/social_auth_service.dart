import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

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
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.fullName,
          AppleIDAuthorizationScopes.email,
        ],
      );

      final response = await http.post(
        Uri.parse('${babifixApiBaseUrl()}/api/auth/apple/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id_token': credential.identityToken,
          'user_identifier': credential.userIdentifier,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final fullName = [
          credential.givenName,
          credential.familyName,
        ].where((s) => s != null && s.isNotEmpty).join(' ');

        return SocialAuthResult(
          isSuccess: true,
          accessToken: data['token'] as String? ?? data['access'] as String?,
          refreshToken: data['refresh'] as String?,
          email: credential.email,
          name: fullName.isNotEmpty ? fullName : null,
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
        error: 'Apple sign in error: $e',
      );
    }
  }

  static Future<void> signOut() async {
    await _googleSignIn.signOut();
  }
}
