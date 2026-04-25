/// Silent Refresh Token Service — Refresh automatique sans interruption utilisateur
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;

class SilentRefreshService {
  /// Duree avant expiration pour trigger refresh (5 minutes)
  static const _refreshBufferSeconds = 300;
  
  /// Timer pour le refresh automatique
  Timer? _refreshTimer;
  
  /// Callback quand le token est refresh
  final Function(String newToken)? onTokenRefreshed;
  final Function()? onRefreshFailed;
  
  SilentRefreshService({
    this.onTokenRefreshed,
    this.onRefreshFailed,
  });
  
  /// Demarre le monitoring du token
  void startMonitoring({
    required String accessToken,
    required String refreshToken,
    required DateTime expiresAt,
    required String apiBase,
  }) {
    // Calculer le temps restant avant expiration
    final now = DateTime.now();
    final remaining = expiresAt.difference(now).inSeconds;
    
    // Si deja expiré, refresh immediatement
    if (remaining <= 0) {
      _doRefresh(accessToken, refreshToken, apiBase);
      return;
    }
    
    // Programmer le refresh avant expiration
    final triggerAt = remaining - _refreshBufferSeconds;
    if (triggerAt > 0) {
      _refreshTimer = Timer(
        Duration(seconds: triggerAt),
        () => _doRefresh(accessToken, refreshToken, apiBase),
      );
    }
  }
  
  /// Arrete le monitoring
  void stopMonitoring() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }
  
  Future<void> _doRefresh(
    String accessToken,
    String refreshToken,
    String apiBase,
  ) async {
    try {
      final resp = await http.post(
        Uri.parse('$apiBase/api/auth/refresh'),
        headers: {
          'Authorization': 'Bearer $refreshToken',
          'Content-Type': 'application/json',
        },
      );
      
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final newToken = data['access'] ?? data['token'];
        if (newToken != null) {
          onTokenRefreshed?.call(newToken);
          
          // Replanifier pour le nouveau token
          final newExpires = DateTime.now().add(const Duration(minutes: 15));
          startMonitoring(
            accessToken: newToken,
            refreshToken: refreshToken,
            expiresAt: newExpires,
            apiBase: apiBase,
          );
        }
      } else {
        // Refresh echoue - deconnecter
        onRefreshFailed?.call();
      }
    } catch (e) {
      onRefreshFailed?.call();
    }
  }
  
  /// Force un refresh immediat
  Future<bool> forceRefresh({
    required String refreshToken,
    required String apiBase,
  }) async {
    try {
      final resp = await http.post(
        Uri.parse('$apiBase/api/auth/refresh'),
        headers: {
          'Authorization': 'Bearer $refreshToken',
          'Content-Type': 'application/json',
        },
      );
      
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final newToken = data['access'] ?? data['token'];
        if (newToken != null) {
          onTokenRefreshed?.call(newToken);
          return true;
        }
      }
    } catch (_) {}
    return false;
  }
}