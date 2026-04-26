import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../babifix_api_config.dart';

// Token store forward declaration
Future<String?> readStoredApiToken() async => null;

class RealTimeSyncService {
  RealTimeSyncService._();

  static final RealTimeSyncService instance = RealTimeSyncService._();

  Timer? _syncTimer;
  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSubscription;
  List<Map<String, dynamic>> _lastCategories = [];
  List<Map<String, dynamic>> _lastProviders = [];

  final _categoryController =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  final _providerController =
      StreamController<List<Map<String, dynamic>>>.broadcast();

  Stream<List<Map<String, dynamic>>> get categoriesStream =>
      _categoryController.stream;
  Stream<List<Map<String, dynamic>>> get providersStream =>
      _providerController.stream;

  bool _isInitialized = false;
  bool _wsConnected = false;

  void startSync({int intervalSeconds = 3, bool preferWebSocket = true}) {
    if (_isInitialized) return;
    _isInitialized = true;

    debugPrint('RealTimeSync: Demarrage synchronisation');
    
    if (preferWebSocket) {
      _tryWebSocket();
    }
    _startPollingFallback(intervalSeconds);

    _checkForUpdates();
  }

  void _tryWebSocket() async {
    try {
      final token = await readStoredApiToken();
      if (token == null || token.isEmpty) {
        debugPrint('RealTimeSync: No token, WebSocket skipped');
        return;
      }
      final wsBase = babifixWsBaseUrl();
      final uri = Uri.parse('$wsBase/ws/client/events/');
      _wsChannel = WebSocketChannel.connect(uri, protocols: ['BABIFIX $token']);
      _wsSubscription = _wsChannel!.stream.listen(
        _onWsMessage,
        onError: (e) {
          debugPrint('RealTimeSync: WS error: $e');
          _wsConnected = false;
        },
        onDone: () {
          debugPrint('RealTimeSync: WS closed');
          _wsConnected = false;
        },
      );
      _wsConnected = true;
      debugPrint('RealTimeSync: WebSocket connected');
    } catch (e) {
      debugPrint('RealTimeSync: WebSocket failed: $e');
    }
  }

  void _onWsMessage(dynamic data) {
    try {
      if (data is! String) return;
      final msg = jsonDecode(data) as Map<String, dynamic>;
      final eventType = msg['type'] as String?;
      if (eventType == 'categories.updated') {
        _checkCategoriesUpdate();
      } else if (eventType == 'prestataire.new' || eventType == 'prestataire.updated') {
        _checkProvidersUpdate();
      }
    } catch (e) {
      debugPrint('RealTimeSync: Parse error: $e');
    }
  }

  void _startPollingFallback(int intervalSeconds) {
    debugPrint('RealTimeSync: Polling fallback (${intervalSeconds}s)');
    _syncTimer = Timer.periodic(Duration(seconds: intervalSeconds), (_) {
      _checkForUpdates();
    });
  }

  void stopSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
    _wsSubscription?.cancel();
    _wsSubscription = null;
    _wsChannel?.sink.close();
    _wsChannel = null;
    _wsConnected = false;
    _isInitialized = false;
    debugPrint('RealTimeSync: Arrete');
  }

  Future<void> _checkForUpdates() async {
    try {
      await Future.wait([_checkCategoriesUpdate(), _checkProvidersUpdate()]);
    } catch (e) {
      debugPrint('RealTimeSync: Erreur: $e');
    }
  }

  Future<void> _checkCategoriesUpdate() async {
    try {
      final base = babifixApiBaseUrl();
      final res = await http.get(Uri.parse('$base/api/public/categories/'));
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final categories = (data['categories'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (_categoriesChanged(categories)) {
        debugPrint('RealTimeSync: Categories mises a jour');
        _lastCategories = categories;
        _categoryController.add(categories);
      }
    } catch (e) {
      debugPrint('BABIFIX: Categories error: $e');
    }
  }

  Future<void> _checkProvidersUpdate() async {
    try {
      final base = babifixApiBaseUrl();
      final res = await http.get(Uri.parse('$base/api/client/prestataires'));
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final providers = (data['items'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (_providersChanged(providers)) {
        debugPrint('RealTimeSync: Prestataires mis a jour');
        _lastProviders = providers;
        _providerController.add(providers);
      }
    } catch (e) {}
  }

  bool _categoriesChanged(List<Map<String, dynamic>> newCategories) {
    if (_lastCategories.isEmpty) {
      _lastCategories = newCategories;
      return false;
    }
    if (newCategories.length != _lastCategories.length) return true;
    for (int i = 0; i < newCategories.length; i++) {
      final newCat = newCategories[i];
      final oldCat = i < _lastCategories.length ? _lastCategories[i] : {};
      if (newCat['id'] != oldCat['id'] ||
          newCat['nom'] != oldCat['nom'] ||
          newCat['actif'] != oldCat['actif']) {
        return true;
      }
    }
    return false;
  }

  bool _providersChanged(List<Map<String, dynamic>> newProviders) {
    if (_lastProviders.isEmpty) {
      _lastProviders = newProviders;
      return false;
    }
    if (newProviders.length != _lastProviders.length) return true;
    final newIds = newProviders.map((p) => p['id']).toSet();
    final oldIds = _lastProviders.map((p) => p['id']).toSet();
    return !newIds.containsAll(oldIds) || !oldIds.containsAll(newIds);
  }

  void dispose() {
    stopSync();
    _categoryController.close();
    _providerController.close();
  }
}

class AutoRefreshWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback onRefresh;

  const AutoRefreshWrapper({
    super.key,
    required this.child,
    required this.onRefresh,
  });

  @override
  State<AutoRefreshWrapper> createState() => _AutoRefreshWrapperState();
}

class _AutoRefreshWrapperState extends State<AutoRefreshWrapper> {
  bool _hasNewData = false;

  @override
  void initState() {
    super.initState();
    RealTimeSyncService.instance.startSync(intervalSeconds: 3);

    RealTimeSyncService.instance.categoriesStream.listen((_) {
      if (mounted) {
        setState(() => _hasNewData = true);
      }
    });
  }

  void _handleRefresh() {
    widget.onRefresh();
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
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                color: Colors.green.shade600,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.refresh, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Nouvelles donnees - Appuyez pour actualiser',
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

  @override
  void dispose() {
    super.dispose();
  }
}