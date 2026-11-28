/// Reporter d erreurs et latences leger (sans dependance externe) : app prestataire.
/// Capture les exceptions Flutter non gerees + erreurs/latences HTTP et les
/// transmet au Cockpit Admin (`/api/app/log-error`) avec anti-spam.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../babifix_api_config.dart';

DateTime? _lastSent;
final Map<String, DateTime> _lastSentByEndpoint = <String, DateTime>{};
String _configuredApp = 'prestataire';
String _configuredVersion = '1.0.0';
bool _telemetryEnabled = kReleaseMode || kProfileMode;

void initErrorReporter({
  required String app,
  required String version,
  bool allowInDebug = false,
}) {
  _configuredApp = app;
  _configuredVersion = version;
  _telemetryEnabled = kReleaseMode || kProfileMode || allowInDebug;

  final previous = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    previous?.call(details);
    if (_telemetryEnabled) {
      _report(
        app: app,
        version: version,
        message: details.exceptionAsString(),
        stack: details.stack?.toString(),
        level: 'error',
        screen: details.context?.toDescription() ?? '',
      );
    }
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    if (_telemetryEnabled) {
      _report(
        app: app,
        version: version,
        message: error.toString(),
        stack: stack.toString(),
        level: 'critical',
      );
    }
    return true;
  };
}

class BabifixErrorReporter {
  const BabifixErrorReporter._();

  /// Signale une erreur HTTP critique (>= 500), timeout ou latence elevee (>= 3000ms).
  static Future<void> reportHttpIssue({
    required String endpoint,
    String method = 'GET',
    int? statusCode,
    int? durationMs,
    String? message,
    String? screen,
    bool force = false,
  }) async {
    if (!force && !_telemetryEnabled) return;
    final cleanEndpoint = endpoint.split('?').first;
    if (cleanEndpoint.contains('/api/app/log-error') ||
        cleanEndpoint.contains('/api/telemetry/')) {
      return;
    }
    final bool isSlow = durationMs != null && durationMs >= 3000;
    final bool isServerErr = statusCode != null && statusCode >= 500;
    if (!isServerErr && !isSlow && (message == null || message.isEmpty)) {
      return;
    }
    final level = isServerErr ? 'error' : (isSlow ? 'slow' : 'warning');
    final text = message ??
        (isServerErr
            ? 'Erreur HTTP $statusCode sur $method $cleanEndpoint'
            : 'Latence mobile elevee (${durationMs ?? 0} ms) sur $cleanEndpoint');
    await _report(
      app: _configuredApp,
      version: _configuredVersion,
      message: text,
      level: level,
      endpoint: cleanEndpoint,
      method: method,
      statusCode: statusCode,
      durationMs: durationMs,
      screen: screen,
      exceptionType: isServerErr ? 'MobileHttpError' : (isSlow ? 'SlowMobileAPI' : 'MobileWarning'),
    );
  }
}

Future<void> _report({
  required String app,
  required String version,
  required String message,
  String? stack,
  String level = 'error',
  String? endpoint,
  String? method,
  int? statusCode,
  int? durationMs,
  String? screen,
  String? exceptionType,
}) async {
  final now = DateTime.now();
  if (level == 'slow' && endpoint != null && endpoint.isNotEmpty) {
    final prevEp = _lastSentByEndpoint[endpoint];
    if (prevEp != null && now.difference(prevEp).inSeconds < 60) return;
    _lastSentByEndpoint[endpoint] = now;
  } else {
    if (_lastSent != null && now.difference(_lastSent!).inSeconds < 5) return;
  }
  _lastSent = now;
  try {
    await http
        .post(
          Uri.parse('${babifixApiBaseUrl()}/api/app/log-error'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'message': message,
            'stack': stack ?? '',
            'app': app,
            'version': version,
            'platform': defaultTargetPlatform.name,
            'level': level,
            if (endpoint != null && endpoint.isNotEmpty) 'endpoint': endpoint,
            if (method != null && method.isNotEmpty) 'method': method,
            if (statusCode != null) 'status_code': statusCode,
            if (durationMs != null) 'duration_ms': durationMs,
            if (screen != null && screen.isNotEmpty) 'screen': screen,
            if (exceptionType != null && exceptionType.isNotEmpty)
              'exception_type': exceptionType,
          }),
        )
        .timeout(const Duration(seconds: 6));
  } catch (_) {}
}
