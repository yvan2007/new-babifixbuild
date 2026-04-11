import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../babifix_api_config.dart';
import '../babifix_fcm.dart';

const kBabifixApiToken = 'babifix_api_token';
const _kRefreshToken = 'babifix_refresh_token';

Future<String?> readStoredApiToken() async {
  final p = await SharedPreferences.getInstance();
  return p.getString(kBabifixApiToken);
}

Future<void> writeStoredApiToken(String? t) async {
  final p = await SharedPreferences.getInstance();
  if (t == null || t.isEmpty) {
    await p.remove(kBabifixApiToken);
  } else {
    await p.setString(kBabifixApiToken, t);
  }
}

Future<void> writeStoredRefreshToken(String? t) async {
  final p = await SharedPreferences.getInstance();
  if (t == null || t.isEmpty) {
    await p.remove(_kRefreshToken);
  } else {
    await p.setString(_kRefreshToken, t);
  }
}

/// Tries to obtain a fresh access token using the stored refresh token.
/// Saves and returns the new token, or returns null on failure.
Future<String?> babifixRefreshAccessToken() async {
  final p = await SharedPreferences.getInstance();
  final refresh = p.getString(_kRefreshToken);
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
  return res;
}

void babifixRegisterFcm(String? token) {
  if (token != null && token.isNotEmpty) {
    BabifixFcm.registerTokenWithBackend(token);
  }
}
