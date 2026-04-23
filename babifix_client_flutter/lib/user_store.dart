import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'babifix_api_config.dart';
import 'babifix_fcm.dart';
import 'social_auth_service.dart';

/// Profil local + session API Django BABIFIX.
/// Tokens JWT stockés de manière sécurisée via flutter_secure_storage.
class BabifixUserStore {
  BabifixUserStore._();

  static const _kAccounts = 'babifix_accounts_v1';
  static const _kSession = 'babifix_session_logged_in';
  static const _kApiToken = 'babifix_api_token';
  static const _kRefreshToken = 'babifix_refresh_token';
  static const _kName = 'babifix_profile_name';
  static const _kEmail = 'babifix_profile_email';
  static const _kPhone = 'babifix_profile_phone';
  static const _kAddress = 'babifix_profile_address';
  static const _kAvatarB64 = 'babifix_profile_avatar_b64';

  static final FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static Future<String?> getApiToken() async {
    return _secureStorage.read(key: _kApiToken);
  }

  static Future<void> _saveApiToken(String? token) async {
    if (token == null || token.isEmpty) {
      await _secureStorage.delete(key: _kApiToken);
    } else {
      await _secureStorage.write(key: _kApiToken, value: token);
    }
  }

  static Future<void> _saveRefreshToken(String? token) async {
    if (token == null || token.isEmpty) {
      await _secureStorage.delete(key: _kRefreshToken);
    } else {
      await _secureStorage.write(key: _kRefreshToken, value: token);
    }
  }

  static Future<String?> _getRefreshToken() async {
    return _secureStorage.read(key: _kRefreshToken);
  }

  /// Tries to obtain a fresh access token using the stored refresh token.
  /// Returns the new access token on success, or null on failure.
  static Future<String?> refreshAccessToken() async {
    final refresh = await _getRefreshToken();
    if (refresh == null || refresh.isEmpty) return null;
    try {
      final res = await http.post(
        Uri.parse('${babifixApiBaseUrl()}/api/auth/refresh/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh': refresh}),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final newAccess = (data['access'] ?? data['token']) as String?;
        if (newAccess != null && newAccess.isNotEmpty) {
          await _saveApiToken(newAccess);
          return newAccess;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Makes an authenticated HTTP GET, auto-refreshing the token on 401.
  /// Returns the response, with the updated token used if a refresh occurred.
  static Future<http.Response> authGet(
    String url, {
    Map<String, String> extraHeaders = const {},
  }) async {
    var token = await getApiToken();
    var res = await http.get(
      Uri.parse(url),
      headers: {
        if (token != null) 'Authorization': 'Bearer $token',
        ...extraHeaders,
      },
    );
    if (res.statusCode == 401) {
      final fresh = await refreshAccessToken();
      if (fresh != null) {
        res = await http.get(
          Uri.parse(url),
          headers: {'Authorization': 'Bearer $fresh', ...extraHeaders},
        );
      }
    }
    return res;
  }

  /// Makes an authenticated HTTP POST, auto-refreshing the token on 401.
  static Future<http.Response> authPost(
    String url, {
    Map<String, String> extraHeaders = const {},
    Object? body,
  }) async {
    var token = await getApiToken();
    final headers = {
      if (token != null) 'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      ...extraHeaders,
    };
    var res = await http.post(Uri.parse(url), headers: headers, body: body);
    if (res.statusCode == 401) {
      final fresh = await refreshAccessToken();
      if (fresh != null) {
        final h2 = {
          'Authorization': 'Bearer $fresh',
          'Content-Type': 'application/json',
          ...extraHeaders,
        };
        res = await http.post(Uri.parse(url), headers: h2, body: body);
      }
    }
    return res;
  }

  static Future<bool> isLoggedIn() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kSession) ?? false;
  }

  static Future<void> _setSession(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kSession, v);
  }

  static Future<Map<String, String>> loadProfile() async {
    final p = await SharedPreferences.getInstance();
    return {
      'name': p.getString(_kName) ?? '',
      'email': p.getString(_kEmail) ?? '',
      'phone': p.getString(_kPhone) ?? '',
      'address': p.getString(_kAddress) ?? '',
    };
  }

  static Future<Uint8List?> loadAvatarBytes() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_kAvatarB64);
    if (s == null || s.isEmpty) return null;
    try {
      return base64Decode(s);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveProfile({
    String? name,
    String? email,
    String? phone,
    String? address,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (name != null) await prefs.setString(_kName, name);
    if (email != null) await prefs.setString(_kEmail, email);
    if (phone != null) await prefs.setString(_kPhone, phone);
    if (address != null) await prefs.setString(_kAddress, address);
  }

  static Future<void> saveAvatarBytes(Uint8List bytes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAvatarB64, base64Encode(bytes));
  }

  static Future<void> clearAvatar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAvatarB64);
  }

  static Future<Map<String, Map<String, String>>> _readAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kAccounts);
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((k, v) {
      final m = (v as Map).map((a, b) => MapEntry('$a', '$b'));
      return MapEntry(k, Map<String, String>.from(m));
    });
  }

  static Future<void> _writeAccounts(Map<String, Map<String, String>> m) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccounts, jsonEncode(m));
  }

  static Future<String?> register({
    required String email,
    required String password,
    required String name,
    required String phone,
    String countryCode = 'CI',
  }) async {
    final key = email.trim().toLowerCase();
    if (key.isEmpty || password.isEmpty) return 'Email et mot de passe requis.';
    final uri = Uri.parse('${babifixApiBaseUrl()}/api/auth/register');
    try {
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': key,
          'email': key, // Ajouter le champ email
          'password': password,
          'role': 'client',
          'phone_e164': phone.trim(),
          'country_code': countryCode,
        }),
      );
      if (res.statusCode == 201) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final token = data['token'] as String?;
        if (token != null) {
          await _saveApiToken(token);
          await saveProfile(
            name: name.trim(),
            email: email.trim(),
            phone: phone.trim(),
          );
          await _setSession(true);
          await BabifixFcm.registerTokenWithBackend(token);
          return null;
        }
      }
      try {
        final err = jsonDecode(res.body) as Map<String, dynamic>;
        return '${err['error'] ?? 'Erreur inscription'}';
      } catch (_) {
        return 'Inscription impossible (HTTP ${res.statusCode}).';
      }
    } catch (e) {
      return _registerLocalFallback(email, password, name, phone);
    }
  }

  static Future<String?> _registerLocalFallback(
    String email,
    String password,
    String name,
    String phone,
  ) async {
    final key = email.trim().toLowerCase();
    final accounts = await _readAccounts();
    if (accounts.containsKey(key))
      return 'Un compte existe deja avec cet email.';
    accounts[key] = {
      'password': password,
      'name': name.trim(),
      'phone': phone.trim(),
    };
    await _writeAccounts(accounts);
    final ex = await loadProfile();
    await saveProfile(
      name: name.trim(),
      email: email.trim(),
      phone: phone.trim(),
      address: ex['address'],
    );
    await _setSession(true);
    return null;
  }

  static Future<String?> login(String email, String password) async {
    final key = email.trim().toLowerCase();
    final uri = Uri.parse('${babifixApiBaseUrl()}/api/auth/login');
    try {
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': key, 'password': password}),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        // Support both {"token": "..."} and {"access": "...", "refresh": "..."} formats
        final token = (data['token'] ?? data['access']) as String?;
        final refreshToken = data['refresh'] as String?;
        final username = data['username'] as String? ?? key;
        if (token != null) {
          await _saveApiToken(token);
          if (refreshToken != null) await _saveRefreshToken(refreshToken);
          await saveProfile(name: username, email: email.trim());
          await _setSession(true);
          await BabifixFcm.registerTokenWithBackend(token);
          return null;
        }
      }
    } catch (_) {
      // fallback local
    }
    final accounts = await _readAccounts();
    final u = accounts[key];
    if (u == null || u['password'] != password) {
      return 'Email ou mot de passe incorrect.';
    }
    await saveProfile(
      name: u['name'] ?? '',
      email: email.trim(),
      phone: u['phone'] ?? '',
    );
    await _setSession(true);
    await _saveApiToken(null);
    return null;
  }

  /// Sign in with Google via google_sign_in + backend BABIFIX.
  /// Returns null on success, error string on failure.
  static Future<String?> tryGoogleAuth() async {
    final result = await SocialAuthService.signInWithGoogle();
    if (!result.isSuccess) return result.error;
    await saveProfile(name: result.name ?? '', email: result.email ?? '');
    await _setSession(true);
    await _saveApiToken(result.accessToken);
    if (result.refreshToken != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kRefreshToken, result.refreshToken!);
    }
    return null; // success
  }

  /// Sign in with Apple via sign_in_with_apple + backend BABIFIX.
  /// Returns null on success, error string on failure.
  static Future<String?> tryAppleAuth() async {
    final result = await SocialAuthService.signInWithApple();
    if (!result.isSuccess) return result.error;
    await saveProfile(name: result.name ?? '', email: result.email ?? '');
    await _setSession(true);
    await _saveApiToken(result.accessToken);
    if (result.refreshToken != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kRefreshToken, result.refreshToken!);
    }
    return null; // success
  }

  static Future<void> socialDemoLogin() async {
    await saveProfile(name: '', email: '');
    await _setSession(false);
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSession, false);
    await prefs.remove(_kApiToken);
    await prefs.remove(_kRefreshToken);
    await prefs.remove(_kName);
    await prefs.remove(_kEmail);
    await prefs.remove(_kPhone);
    await prefs.remove(_kAddress);
    await prefs.remove(_kAvatarB64);
    await _secureStorage.delete(key: _kApiToken);
    await _secureStorage.delete(key: _kRefreshToken);
    await _secureStorage.delete(key: _kName);
    await _secureStorage.delete(key: _kEmail);
    await _secureStorage.delete(key: _kPhone);
    await _secureStorage.delete(key: _kAvatarB64);
  }
}
