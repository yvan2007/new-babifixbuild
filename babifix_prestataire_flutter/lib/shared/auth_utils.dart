import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../babifix_api_config.dart';
import '../babifix_fcm.dart';
import 'widgets/error_reporter.dart';

const kBabifixApiToken = 'babifix_api_token';
const _kRefreshToken = 'babifix_refresh_token';
const _kProfileName = 'babifix_profile_name';
const _kProfileEmail = 'babifix_profile_email';
const _kProfileId = 'babifix_profile_id';

Future<void> babifixSaveProfile({
  required String name,
  required String email,
  int? id,
}) async {
  final p = await SharedPreferences.getInstance();
  await p.setString(_kProfileName, name);
  // PII sensibles : stockage chiffre via flutter_secure_storage
  await _secureStorage.write(key: _kProfileEmail, value: email);
  if (id != null) await _secureStorage.write(key: _kProfileId, value: id.toString());
  // Nettoyage des anciennes valeurs en clair
  await p.remove(_kProfileEmail);
  await p.remove(_kProfileId);
}

Future<Map<String, dynamic>> babifixLoadProfileFull() async {
  final p = await SharedPreferences.getInstance();
  // Migration : lire depuis secure storage, repli sur SharedPreferences
  final email = await _secureStorage.read(key: _kProfileEmail) ?? p.getString(_kProfileEmail) ?? '';
  final idStr = await _secureStorage.read(key: _kProfileId);
  final id = idStr != null ? int.tryParse(idStr) : p.getInt(_kProfileId);
  return {
    'name': p.getString(_kProfileName) ?? '',
    'email': email,
    'id': id,
  };
}

const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
);

Future<String?> readStoredApiToken() async {
  return _secureStorage.read(key: kBabifixApiToken);
}

Future<void> writeStoredApiToken(String? t) async {
  if (t == null || t.isEmpty) {
    await _secureStorage.delete(key: kBabifixApiToken);
  } else {
    await _secureStorage.write(key: kBabifixApiToken, value: t);
  }
}

Future<void> writeStoredRefreshToken(String? t) async {
  if (t == null || t.isEmpty) {
    await _secureStorage.delete(key: _kRefreshToken);
  } else {
    await _secureStorage.write(key: _kRefreshToken, value: t);
  }
}

/// Tries to obtain a fresh access token using the stored refresh token.
/// Saves and returns the new token, or returns null on failure.
Future<String?> babifixRefreshAccessToken() async {
  final refresh = await _secureStorage.read(key: _kRefreshToken);
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
        await writeStoredApiToken(newAccess);
        return newAccess;
      }
    }
  } catch (_) {}
  return null;
}

/// Makes an authenticated HTTP GET with auto-refresh on 401.
Future<http.Response> babifixAuthGet(
  String url, {
  Map<String, String> extraHeaders = const {},
}) async {
  var token = await readStoredApiToken();
  final sw = Stopwatch()..start();
  var res = await http.get(
    Uri.parse(url),
    headers: {
      if (token != null) 'Authorization': 'Bearer $token',
      ...extraHeaders,
    },
  );
  if (res.statusCode == 401) {
    final fresh = await babifixRefreshAccessToken();
    if (fresh != null) {
      res = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $fresh', ...extraHeaders},
      );
    }
  }
  sw.stop();
  if (res.statusCode >= 500 || sw.elapsedMilliseconds >= 1500) {
    unawaited(BabifixErrorReporter.reportHttpIssue(
      endpoint: Uri.tryParse(url)?.path ?? url,
      method: 'GET',
      statusCode: res.statusCode,
      durationMs: sw.elapsedMilliseconds,
    ));
  }
  return res;
}

/// Makes an authenticated HTTP POST with auto-refresh on 401.
Future<http.Response> babifixAuthPost(
  String url, {
  Map<String, String> extraHeaders = const {},
  Object? body,
}) async {
  var token = await readStoredApiToken();
  final headers = {
    if (token != null) 'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
    ...extraHeaders,
  };
  final sw = Stopwatch()..start();
  var res = await http.post(Uri.parse(url), headers: headers, body: body);
  if (res.statusCode == 401) {
    final fresh = await babifixRefreshAccessToken();
    if (fresh != null) {
      final h2 = {
        'Authorization': 'Bearer $fresh',
        'Content-Type': 'application/json',
        ...extraHeaders,
      };
      res = await http.post(Uri.parse(url), headers: h2, body: body);
    }
  }
  sw.stop();
  if (res.statusCode >= 500 || sw.elapsedMilliseconds >= 1500) {
    unawaited(BabifixErrorReporter.reportHttpIssue(
      endpoint: Uri.tryParse(url)?.path ?? url,
      method: 'POST',
      statusCode: res.statusCode,
      durationMs: sw.elapsedMilliseconds,
    ));
  }
  return res;
}

void babifixRegisterFcm(String? token) {
  if (token != null && token.isNotEmpty) {
    BabifixFcm.registerTokenWithBackend(token);
  }
}

Future<Map<String, String>> babifixLoadProfile() async {
  final p = await SharedPreferences.getInstance();
  return {
    'name': p.getString(_kProfileName) ?? '',
    'email': p.getString(_kProfileEmail) ?? '',
  };
}
