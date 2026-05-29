import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../babifix_api_config.dart';
import 'babifix_user_store.dart';

/// Service temps réel pour l'app prestataire BABIFIX.
///
/// Connecté à `/ws/prestataire/events/` (Django Channels). Le backend pousse
/// des évènements ciblés sur le groupe `babifix_prestataire_<user_id>` :
///   • `reservation.created`  : nouvelle demande client (à accepter/refuser)
///   • `reservation.updated`  : devis accepté, intervention validée…
///   • `reservation.deleted`  : demande annulée
///
/// Les écrans Flutter s'abonnent via [reservationsStream] et rechargent
/// leur liste à chaque évènement — fini le pull-to-refresh manuel.
///
/// L'app peut soit :
///   • appeler [start] pour ouvrir sa propre connexion WS (utile en standalone) ;
///   • soit pousser manuellement les events reçus par une autre connexion WS
///     déjà ouverte via [pushRawWsMessage] (utilisé dans `main.dart`).
class PrestataireRealTimeSyncService {
  PrestataireRealTimeSyncService._();
  static final PrestataireRealTimeSyncService instance =
      PrestataireRealTimeSyncService._();

  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSubscription;
  Timer? _reconnectTimer;
  bool _started = false;
  bool _stopped = false;

  final _reservationController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Émis pour chaque `reservation.*` event reçu.
  /// Payload contient au minimum `reference`, `statut`, `_event`.
  Stream<Map<String, dynamic>> get reservationsStream =>
      _reservationController.stream;

  /// Pour partager une connexion WS existante : décodage + filtrage des
  /// évènements `reservation.*` et émission sur [reservationsStream].
  /// `raw` peut être un String JSON ou un Map déjà décodé.
  void pushRawWsMessage(dynamic raw) {
    try {
      final msg = raw is Map
          ? Map<String, dynamic>.from(raw)
          : (raw is String
              ? jsonDecode(raw) as Map<String, dynamic>
              : null);
      if (msg == null) return;
      final eventType = msg['type'] as String?;
      if (eventType == null) return;
      if (eventType == 'reservation.created' ||
          eventType == 'reservation.updated' ||
          eventType == 'reservation.deleted') {
        final payload = (msg['payload'] is Map)
            ? Map<String, dynamic>.from(msg['payload'] as Map)
            : <String, dynamic>{};
        payload['_event'] = eventType;
        _reservationController.add(payload);
      }
    } catch (_) {}
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _stopped = false;
    await _connect();
  }

  Future<void> _connect() async {
    if (_stopped) return;
    try {
      final token = await BabifixUserStore.getApiToken();
      if (token == null || token.isEmpty) {
        debugPrint('PrestataireRT: pas de token, skip WS');
        _scheduleReconnect();
        return;
      }
      final wsBase = babifixWsBaseUrl();
      final uri = Uri.parse('$wsBase/ws/prestataire/events/');
      final channel = WebSocketChannel.connect(
        uri,
        protocols: ['BABIFIX $token'],
      );
      _wsChannel = channel;
      _wsSubscription = channel.stream.listen(
        _onMessage,
        onError: (e) {
          debugPrint('PrestataireRT: WS error: $e');
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('PrestataireRT: WS closed');
          _scheduleReconnect();
        },
        cancelOnError: true,
      );
      debugPrint('PrestataireRT: WebSocket connecté');
    } catch (e) {
      debugPrint('PrestataireRT: WS connect fail: $e');
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    if (_stopped) return;
    _reconnectTimer = Timer(const Duration(seconds: 5), _connect);
  }

  void _onMessage(dynamic data) {
    try {
      if (data is! String) return;
      final msg = jsonDecode(data) as Map<String, dynamic>;
      final eventType = msg['type'] as String?;
      if (eventType == null) return;
      if (eventType == 'reservation.created' ||
          eventType == 'reservation.updated' ||
          eventType == 'reservation.deleted') {
        final payload = (msg['payload'] is Map)
            ? Map<String, dynamic>.from(msg['payload'] as Map)
            : <String, dynamic>{};
        payload['_event'] = eventType;
        _reservationController.add(payload);
      }
    } catch (e) {
      debugPrint('PrestataireRT: parse error: $e');
    }
  }

  Future<void> stop() async {
    _stopped = true;
    _started = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _wsSubscription?.cancel();
    _wsSubscription = null;
    await _wsChannel?.sink.close();
    _wsChannel = null;
    debugPrint('PrestataireRT: arrêté');
  }

  void dispose() {
    stop();
    _reservationController.close();
  }
}
