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
  static const _kAddressLat = 'babifix_profile_address_lat';
  static const _kAddressLng = 'babifix_profile_address_lng';
  static const _kAvatarB64 = 'babifix_profile_avatar_b64';
  static const _kUserId = 'babifix_user_id';

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

  static Future<http.Response> authGet(
    String url, {
    Map<String, String> extraHeaders = const {},
  }) async {
    var token = await getApiToken();
    final fullUrl = url.startsWith('http') ? url : '${babifixApiBaseUrl()}$url';
    // Timeout généreux pour survivre au réveil du serveur (cold start Render),
    // mais borné pour ne jamais figer l'app indéfiniment.
    var res = await http.get(
      Uri.parse(fullUrl),
      headers: {
        if (token != null) 'Authorization': 'Bearer $token',
        ...extraHeaders,
      },
    ).timeout(const Duration(seconds: 40));
    if (res.statusCode == 401) {
      final fresh = await refreshAccessToken();
      if (fresh != null) {
        res = await http.get(
          Uri.parse(fullUrl),
          headers: {'Authorization': 'Bearer $fresh', ...extraHeaders},
        ).timeout(const Duration(seconds: 40));
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
    final fullUrl = url.startsWith('http') ? url : '${babifixApiBaseUrl()}$url';
    final headers = {
      if (token != null) 'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      ...extraHeaders,
    };
    var res = await http.post(Uri.parse(fullUrl), headers: headers, body: body);
    if (res.statusCode == 401) {
      final fresh = await refreshAccessToken();
      if (fresh != null) {
        final h2 = {
          'Authorization': 'Bearer $fresh',
          'Content-Type': 'application/json',
          ...extraHeaders,
        };
        res = await http.post(Uri.parse(fullUrl), headers: h2, body: body);
      }
    }
    return res;
  }

  static Future<http.Response> authPatch(
    String url, {
    Object? body,
  }) async {
    final token = await getApiToken();
    final fullUrl = url.startsWith('http') ? url : '${babifixApiBaseUrl()}$url';
    final headers = {
      if (token != null) 'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    return http.patch(Uri.parse(fullUrl), headers: headers, body: body);
  }

  static Future<http.Response> authDelete(String url) async {
    final token = await getApiToken();
    final fullUrl = url.startsWith('http') ? url : '${babifixApiBaseUrl()}$url';
    final headers = {
      if (token != null) 'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    return http.delete(Uri.parse(fullUrl), headers: headers);
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
      'address_lat': p.getString(_kAddressLat) ?? '',
      'address_lng': p.getString(_kAddressLng) ?? '',
    };
  }

  /// Récupère le profil réel depuis le serveur (`/api/auth/me`) et le fusionne
  /// dans le stockage local : nom complet, email, téléphone saisis à
  /// l'inscription. Évite que le nom affiché soit l'email après reconnexion.
  /// Silencieux en cas d'échec réseau (on garde les valeurs locales).
  static Future<void> hydrateProfileFromServer() async {
    try {
      final token = await getApiToken();
      if (token == null || token.isEmpty) return;
      final res = await http
          .get(
            Uri.parse('${babifixApiBaseUrl()}/api/auth/me'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return;
      final d = jsonDecode(res.body) as Map<String, dynamic>;
      final serverName = (d['name'] ?? '').toString().trim();
      final serverEmail = (d['email'] ?? '').toString().trim();
      final serverPhone = (d['phone_e164'] ?? '').toString().trim();
      final local = await loadProfile();
      // On n'écrase un champ local que si le serveur a une valeur utile.
      await saveProfile(
        name: serverName.isNotEmpty ? serverName : null,
        email: serverEmail.isNotEmpty ? serverEmail : null,
        phone: serverPhone.isNotEmpty ? serverPhone : null,
      );
      // Si le serveur ne renvoie pas de nom mais que le local vaut l'email,
      // on évite d'afficher l'email comme nom.
      if (serverName.isEmpty) {
        final n = (local['name'] ?? '').trim();
        final em = (local['email'] ?? serverEmail).trim();
        if (n.isNotEmpty && n == em && n.contains('@')) {
          await saveProfile(name: n.split('@').first);
        }
      }
    } catch (_) {
      // Réseau indisponible : on conserve les valeurs locales.
    }
  }

  /// Pousse les modifications du profil vers le serveur (`/api/auth/me`) pour
  /// qu'elles persistent (visibles après reconnexion / sur un autre appareil).
  static Future<void> pushProfileToServer({
    String? name,
    String? email,
    String? phone,
  }) async {
    try {
      final token = await getApiToken();
      if (token == null || token.isEmpty) return;
      final body = <String, dynamic>{};
      if (name != null && name.trim().isNotEmpty) body['name'] = name.trim();
      if (email != null && email.trim().isNotEmpty) body['email'] = email.trim();
      if (phone != null && phone.trim().isNotEmpty) {
        body['phone_e164'] = phone.trim();
      }
      if (body.isEmpty) return;
      await http
          .post(
            Uri.parse('${babifixApiBaseUrl()}/api/auth/me'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 12));
    } catch (_) {
      // Silencieux : la valeur locale reste enregistrée.
    }
  }

  /// Coordonnées de l'adresse profil (repli proximité quand le GPS est coupé).
  static Future<({double lat, double lng})?> loadAddressCoords() async {
    final p = await SharedPreferences.getInstance();
    final la = double.tryParse(p.getString(_kAddressLat) ?? '');
    final lo = double.tryParse(p.getString(_kAddressLng) ?? '');
    if (la == null || lo == null) return null;
    return (lat: la, lng: lo);
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
    double? addressLat,
    double? addressLng,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (name != null) await prefs.setString(_kName, name);
    if (email != null) await prefs.setString(_kEmail, email);
    if (phone != null) await prefs.setString(_kPhone, phone);
    if (address != null) await prefs.setString(_kAddress, address);
    if (addressLat != null) {
      await prefs.setString(_kAddressLat, addressLat.toString());
    }
    if (addressLng != null) {
      await prefs.setString(_kAddressLng, addressLng.toString());
    }
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
      // Timeout borné (cold start serveur). Sans ça, l'inscription pouvait
      // « traîner » puis tomber en fallback local silencieux → compte jamais
      // créé en base (donc invisible dans l'admin) et reconnexion impossible.
      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'username': key,
              'email': key, // Ajouter le champ email
              'name': name.trim(), // Nom complet → persiste côté serveur
              'password': password,
              'role': 'client',
              'phone_e164': phone.trim(),
              'country_code': countryCode,
            }),
          )
          .timeout(const Duration(seconds: 45));
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
          BabifixFcm.registerTokenWithBackend(token).catchError((_) {});
          return null;
        }
      }
      // Messages serveur lisibles (compte déjà existant, etc.).
      try {
        final err = jsonDecode(res.body) as Map<String, dynamic>;
        final code = '${err['error'] ?? ''}';
        if (code == 'username_exists') {
          return 'Un compte existe déjà avec cet email. Connectez-vous.';
        }
        if (code == 'password_too_short') {
          return 'Mot de passe trop court (6 caractères minimum).';
        }
        return code.isNotEmpty ? code : 'Inscription impossible (HTTP ${res.statusCode}).';
      } catch (_) {
        return 'Inscription impossible (HTTP ${res.statusCode}).';
      }
    } catch (e) {
      // Réseau / serveur indisponible : on NE crée PAS un compte local trompeur
      // (il ne serait pas en base). On demande de réessayer — le 2e essai marche
      // une fois le serveur réveillé.
      return 'Connexion au serveur impossible. Vérifiez votre réseau et réessayez.';
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
      // Timeout borné : sans ça, un cold start Render (serveur endormi) faisait
      // « tourner » le login à l'infini. 45 s = marge pour le réveil serveur.
      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'username': key, 'password': password}),
          )
          .timeout(const Duration(seconds: 45));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        // Support both {"token": "..."} and {"access": "...", "refresh": "..."} formats
        final token = (data['token'] ?? data['access']) as String?;
        final refreshToken = data['refresh'] as String?;
        if (token != null) {
          await _saveApiToken(token);
          if (refreshToken != null) await _saveRefreshToken(refreshToken);
          // Email d'abord, puis on récupère nom/téléphone réels du serveur
          // (ne PAS mettre name=username : ce serait l'email).
          await saveProfile(email: email.trim());
          await hydrateProfileFromServer();
          await _setSession(true);
          // FCM en arrière-plan : ne JAMAIS bloquer le retour du login
          // (si l'enregistrement du token traîne, l'utilisateur entre quand même).
          BabifixFcm.registerTokenWithBackend(token).catchError((_) {});
          return null;
        }
      }
      // NB : on ne court-circuite PAS ici sur un 401/400 — on laisse la main au
      // repli local ci-dessous (comptes créés hors-ligne avant une connexion).
      // Si le compte n'existe pas non plus en local → « incorrect ».
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
      await _saveRefreshToken(result.refreshToken);
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
      await _saveRefreshToken(result.refreshToken);
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
