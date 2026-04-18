import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../babifix_api_config.dart';

class WebSocketPushService {
  WebSocketPushService._();

  static final WebSocketPushService instance = WebSocketPushService._();

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  bool _isConnected = false;

  final _categoryController =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  final _providerController =
      StreamController<List<Map<String, dynamic>>>.broadcast();

  Stream<List<Map<String, dynamic>>> get categoriesStream =>
      _categoryController.stream;
  Stream<List<Map<String, dynamic>>> get providersStream =>
      _providerController.stream;

  bool get isConnected => _isConnected;

  void connect() {
    if (_isConnected) return;

    try {
      final base = babifixApiBaseUrl();
      final wsUrl = base.replaceFirst('http', 'ws') + '/ws/realtime/';

      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _channel!.stream.listen(_onMessage, onError: _onError, onDone: _onDone);

      _isConnected = true;
      debugPrint('WebSocketPush: Connecté à $wsUrl');
    } catch (e) {
      debugPrint('WebSocketPush: Erreur de connexion: $e');
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;
      final type = data['type'] as String?;

      switch (type) {
        case 'categories_update':
          final categories =
              (data['categories'] as List<dynamic>?)
                  ?.map((e) => Map<String, dynamic>.from(e))
                  .toList() ??
              [];
          _categoryController.add(categories);
          debugPrint('WebSocketPush: Catégories mises à jour');
          break;

        case 'providers_update':
          final providers =
              (data['providers'] as List<dynamic>?)
                  ?.map((e) => Map<String, dynamic>.from(e))
                  .toList() ??
              [];
          _providerController.add(providers);
          debugPrint('WebSocketPush: Prestataires mis à jour');
          break;

        case 'new_provider':
          _providerController.add(
            data['providers'] as List<Map<String, dynamic>>,
          );
          debugPrint('WebSocketPush: Nouveau prestataire');
          break;

        default:
          debugPrint('WebSocketPush: Message type inconnu: $type');
      }
    } catch (e) {
      debugPrint('WebSocketPush: Erreur parsing: $e');
    }
  }

  void _onError(dynamic error) {
    debugPrint('WebSocketPush: Erreur: $error');
    _isConnected = false;
    _scheduleReconnect();
  }

  void _onDone() {
    debugPrint('WebSocketPush: Connexion fermée');
    _isConnected = false;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      debugPrint('WebSocketPush: Reconnexion...');
      connect();
    });
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _isConnected = false;
    debugPrint('WebSocketPush: Déconnecté');
  }

  void dispose() {
    disconnect();
    _categoryController.close();
    _providerController.close();
  }
}

class WebSocketWrapper extends StatefulWidget {
  final Widget child;

  const WebSocketWrapper({super.key, required this.child});

  @override
  State<WebSocketWrapper> createState() => _WebSocketWrapperState();
}

class _WebSocketWrapperState extends State<WebSocketWrapper> {
  bool _hasNewData = false;

  @override
  void initState() {
    super.initState();
    _initWebSocket();
  }

  void _initWebSocket() {
    WebSocketPushService.instance.connect();

    WebSocketPushService.instance.categoriesStream.listen((_) {
      if (mounted) {
        setState(() => _hasNewData = true);
      }
    });

    WebSocketPushService.instance.providersStream.listen((_) {
      if (mounted) {
        setState(() => _hasNewData = true);
      }
    });
  }

  void _handleRefresh() {
    setState(() => _hasNewData = false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_hasNewData)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: GestureDetector(
              onTap: _handleRefresh,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 16,
                ),
                color: Colors.green.shade600,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.sync, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Mise à jour en temps réel - Appuyez pour rafraichir',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
