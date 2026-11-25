import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'babifix_api_config.dart';
import 'babifix_fcm.dart';
import 'shared/widgets/error_reporter.dart';
import 'social_auth_service.dart';

/// Profil local + session API Django BABIFIX.
/// Tokens JWT stockés de manière sécurisée via flutter_secure_storage.
class BabifixUserStore {
  BabifixUserStore._();

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

  static final FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static Future<String?> getApiToken() async {
    return _secureStorage.read(key: _kApiToken);
  }

  static Future<void> saveApiToken(String? token) async {
    await _saveApiToken(token);
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
    final sw = Stopwatch()..start();
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
    sw.stop();
    if (res.statusCode >= 500 || sw.elapsedMilliseconds >= 1500) {
      unawaited(BabifixErrorReporter.reportHttpIssue(
        endpoint: url,
        method: 'GET',
        statusCode: res.statusCode,
        durationMs: sw.elapsedMilliseconds,
      ));
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
    final sw = Stopwatch()..start();
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
    sw.stop();
    if (res.statusCode >= 500 || sw.elapsedMilliseconds >= 1500) {
      unawaited(BabifixErrorReporter.reportHttpIssue(
        endpoint: url,
        method: 'POST',
        statusCode: res.statusCode,
        durationMs: sw.elapsedMilliseconds,
      ));
    }
    return res;
  }

  static Future<http.Response> authPatch(
    String url, {
    Object? body,
  }) async {
    var token = await getApiToken();
    final fullUrl = url.startsWith('http') ? url : '${babifixApiBaseUrl()}$url';
    final headers = {
      if (token != null) 'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    var res = await http.patch(Uri.parse(fullUrl), headers: headers, body: body);
    if (res.statusCode == 401) {
      final fresh = await refreshAccessToken();
      if (fresh != null) {
        final h2 = {
          'Authorization': 'Bearer $fresh',
          'Content-Type': 'application/json',
        };
        res = await http.patch(Uri.parse(fullUrl), headers: h2, body: body);
      }
    }
    return res;
  }

  static Future<http.Response> authDelete(String url) async {
    var token = await getApiToken();
    final fullUrl = url.startsWith('http') ? url : '${babifixApiBaseUrl()}$url';
    final headers = {
      if (token != null) 'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    var res = await http.delete(Uri.parse(fullUrl), headers: headers);
    if (res.statusCode == 401) {
      final fresh = await refreshAccessToken();
      if (fresh != null) {
        final h2 = {
          'Authorization': 'Bearer $fresh',
          'Content-Type': 'application/json',
        };
        res = await http.delete(Uri.parse(fullUrl), headers: h2);
      }
    }
    return res;
  }

  static Future<bool> isLoggedIn() async {
    final p = await SharedPreferences.getInstance();
    final flagged = p.getBool(_kSession) ?? false;
    if (!flagged) return false;
    // Une session SANS jeton serveur n'est pas une vraie session : l'app
    // s'ouvrirait puis tous les appels API seraient rejetés (401). C'est le cas
    // des anciens comptes crees hors-ligne, avant que l'inscription n'exige le
    // serveur. On les traite comme deconnectes, sans supprimer leurs donnees.
    final access = await getApiToken();
    final refresh = await _getRefreshToken();
    final noAccess = access == null || access.isEmpty;
    final noRefresh = refresh == null || refresh.isEmpty;
    if (noAccess && noRefresh) {
      await p.setBool(_kSession, false);
      return false;
    }
    return true;
  }

  static Future<void> _setSession(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kSession, v);
  }

  static Future<Map<String, String>> loadProfile() async {
    final p = await SharedPreferences.getInstance();
    // Migration : lire depuis secure storage, repli sur SharedPreferences
    // pour les anciennes installations (migration transparente).
    final name = p.getString(_kName) ?? '';
    final email = await _secureStorage.read(key: _kEmail) ?? p.getString(_kEmail) ?? '';
    final phone = await _secureStorage.read(key: _kPhone) ?? p.getString(_kPhone) ?? '';
    final address = await _secureStorage.read(key: _kAddress) ?? p.getString(_kAddress) ?? '';
    final lat = await _secureStorage.read(key: _kAddressLat) ?? p.getString(_kAddressLat) ?? '';
    final lng = await _secureStorage.read(key: _kAddressLng) ?? p.getString(_kAddressLng) ?? '';
    return {
      'name': name,
      'email': email,
      'phone': phone,
      'address': address,
      'address_lat': lat,
      'address_lng': lng,
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

  /// Coordonnées de l'adresse profil (lit le stockage chiffré puis repli prefs).
  static Future<({double lat, double lng})?> loadAddressCoords() async {
    var laStr = await _secureStorage.read(key: _kAddressLat);
    var loStr = await _secureStorage.read(key: _kAddressLng);
    if (laStr == null || loStr == null || laStr.isEmpty || loStr.isEmpty) {
      final p = await SharedPreferences.getInstance();
      laStr ??= p.getString(_kAddressLat);
      loStr ??= p.getString(_kAddressLng);
    }
    final la = double.tryParse(laStr ?? '');
    final lo = double.tryParse(loStr ?? '');
    if (la == null || lo == null) return null;
    return (lat: la, lng: lo);
  }

  static Future<Uint8List?> loadAvatarBytes() async {
    // Migration : lire depuis secure storage, repli sur SharedPreferences
    var s = await _secureStorage.read(key: _kAvatarB64);
    if (s == null || s.isEmpty) {
      final p = await SharedPreferences.getInstance();
      s = p.getString(_kAvatarB64);
    }
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
    // PII sensibles : stockage chiffre via flutter_secure_storage
    if (email != null) await _secureStorage.write(key: _kEmail, value: email);
    if (phone != null) await _secureStorage.write(key: _kPhone, value: phone);
    if (address != null) await _secureStorage.write(key: _kAddress, value: address);
    if (addressLat != null) {
      await _secureStorage.write(key: _kAddressLat, value: addressLat.toString());
    }
    if (addressLng != null) {
      await _secureStorage.write(key: _kAddressLng, value: addressLng.toString());
    }
    // Nettoyage des anciennes valeurs en clair dans SharedPreferences
    await prefs.remove(_kEmail);
    await prefs.remove(_kPhone);
    await prefs.remove(_kAddress);
    await prefs.remove(_kAddressLat);
    await prefs.remove(_kAddressLng);
  }

  static Future<void> saveAvatarBytes(Uint8List bytes) async {
    await _secureStorage.write(key: _kAvatarB64, value: base64Encode(bytes));
    // Nettoyage de l'ancienne valeur en clair
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAvatarB64);
  }

  static Future<void> clearAvatar() async {
    await _secureStorage.delete(key: _kAvatarB64);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAvatarB64);
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
        final token = (data['token'] ?? data['access']) as String?;
        final refreshToken = data['refresh'] as String?;
        if (token != null) {
          await _saveApiToken(token);
          if (refreshToken != null && refreshToken.isNotEmpty) {
            await _saveRefreshToken(refreshToken);
          }
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

  static Future<String?> login(String email, String password) async {
    final identifier = email.trim();
    final key = identifier.toLowerCase();
    final uri = Uri.parse('${babifixApiBaseUrl()}/api/auth/login');
    try {
      // Timeout borné : sans ça, un cold start Render (serveur endormi) faisait
      // « tourner » le login à l'infini. 45 s = marge pour le réveil serveur.
      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            // Le backend accepte email, nom d'utilisateur ou nom complet
            // (adminpanel/views.py -> api_auth_login) : un seul champ suffit.
            body: jsonEncode({'username': key, 'password': password}),
          )
          .timeout(const Duration(seconds: 45));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        // Support both {"token": "..."} and {"access": "...", "refresh": "..."} formats
        final token = (data['token'] ?? data['access']) as String?;
        final refreshToken = data['refresh'] as String?;
        if (token != null && token.isNotEmpty) {
          await _saveApiToken(token);
          if (refreshToken != null) await _saveRefreshToken(refreshToken);
          // Email d'abord, puis on récupère nom/téléphone réels du serveur
          // (ne PAS mettre name=username : ce serait l'email).
          await saveProfile(email: identifier);
          await _setSession(true);
          // Hydratation du profil EN ARRIÈRE-PLAN : ne pas bloquer l'entrée dans
          // l'app (sinon ~12 s d'attente supplémentaires après l'auth réussie).
          hydrateProfileFromServer().catchError((_) {});
          // FCM en arrière-plan : ne JAMAIS bloquer le retour du login
          // (si l'enregistrement du token traîne, l'utilisateur entre quand même).
          BabifixFcm.registerTokenWithBackend(token).catchError((_) {});
          return null;
        }
        // 200 sans jeton : le serveur n'a pas réellement authentifié. Ne pas
        // ouvrir une session sans jeton, sinon tous les appels API échouent.
        return 'Réponse du serveur invalide. Réessayez.';
      }
      // Le serveur a RÉPONDU : une session locale sans jeton serait une fausse
      // connexion (l'app s'ouvre puis tous les appels API sont rejetés). On
      // renvoie donc un message explicite au lieu de basculer en local.
      if (res.statusCode == 400 || res.statusCode == 401) {
        return 'Identifiant ou mot de passe incorrect.';
      }
      if (res.statusCode == 403) {
        return 'Compte suspendu ou non autorisé. Contactez le support.';
      }
      if (res.statusCode == 429) {
        return 'Trop de tentatives. Patientez une minute puis réessayez.';
      }
      if (res.statusCode >= 500) {
        return 'Le serveur est indisponible (erreur ${res.statusCode}). '
            'Réessayez dans un instant.';
      }
      return 'Connexion impossible (erreur ${res.statusCode}).';
    } catch (_) {
      // Exception réseau (serveur injoignable, DNS, timeout) : c'est le SEUL cas
      // où l'on n'a aucune réponse. On ne crée plus de session sans jeton.
      return 'Serveur injoignable. Vérifiez votre connexion Internet, puis réessayez.';
    }
  }

  /// Sign in with Google via google_sign_in + backend BABIFIX.
  /// Returns null on success, error string on failure.
  static Future<String?> tryGoogleAuth() async {
    final result = await SocialAuthService.signInWithGoogle();
    if (!result.isSuccess) return result.error;
    final token = result.accessToken;
    // Sans jeton serveur, inutile d'ouvrir une session : tous les appels
    // API seraient rejetés (même logique que login()).
    if (token == null || token.isEmpty) {
      return 'Connexion Google acceptée mais le serveur n\'a pas renvoyé de session. Réessayez.';
    }
    await saveProfile(name: result.name ?? '', email: result.email ?? '');
    await _saveApiToken(token);
    if (result.refreshToken != null && result.refreshToken!.isNotEmpty) {
      await _saveRefreshToken(result.refreshToken);
    }
    await _setSession(true);
    return null; // success
  }

  /// Sign in with Apple via sign_in_with_apple + backend BABIFIX.
  /// Returns null on success, error string on failure.
  static Future<String?> tryAppleAuth() async {
    final result = await SocialAuthService.signInWithApple();
    if (!result.isSuccess) return result.error;
    final token = result.accessToken;
    if (token == null || token.isEmpty) {
      return 'Connexion Apple acceptée mais le serveur n\'a pas renvoyé de session. Réessayez.';
    }
    await saveProfile(name: result.name ?? '', email: result.email ?? '');
    await _saveApiToken(token);
    if (result.refreshToken != null && result.refreshToken!.isNotEmpty) {
      await _saveRefreshToken(result.refreshToken);
    }
    await _setSession(true);
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
    await _secureStorage.delete(key: _kEmail);
    await _secureStorage.delete(key: _kPhone);
    await _secureStorage.delete(key: _kAddress);
    await _secureStorage.delete(key: _kAddressLat);
    await _secureStorage.delete(key: _kAddressLng);
    await _secureStorage.delete(key: _kAvatarB64);
    await _secureStorage.delete(key: _kName);
    await _secureStorage.delete(key: _kEmail);
    await _secureStorage.delete(key: _kPhone);
    await _secureStorage.delete(key: _kAvatarB64);
  }
}
