/// Reporter d'erreurs léger (sans dépendance externe).
/// Capture les exceptions Flutter non gérées et les transmet au backend
/// (`/api/app/log-error`), qui les journalise → Sentry côté serveur les capte.
/// Alternative volontaire au SDK sentry_flutter (qui cassait le build).
/// Best-effort, anti-spam, jamais bloquant.
import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../babifix_api_config.dart';

DateTime? _lastSent;

void initErrorReporter({required String app, required String version}) {
  final previous = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    previous?.call(details);
    if (kReleaseMode) {
      _report(app, version, details.exceptionAsString(),
          details.stack?.toString());
    }
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    if (kReleaseMode) {
      _report(app, version, error.toString(), stack.toString());
    }
    return true; // erreur considérée comme gérée (n'arrête pas l'app)
  };
}

Future<void> _report(
    String app, String version, String message, String? stack) async {
  // Anti-spam : au plus 1 envoi / 5 s.
  final now = DateTime.now();
  if (_lastSent != null && now.difference(_lastSent!).inSeconds < 5) return;
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
            'platform': 'flutter',
          }),
        )
        .timeout(const Duration(seconds: 6));
  } catch (_) {
    // best-effort : ne jamais propager une erreur du reporter
  }
}
