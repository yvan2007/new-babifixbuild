import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../babifix_api_config.dart';

class RealTimeSyncService {
  RealTimeSyncService._();

  static final RealTimeSyncService instance = RealTimeSyncService._();

  Timer? _syncTimer;
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

  void startSync({int intervalSeconds = 3}) {
    if (_isInitialized) return;
    _isInitialized = true;

    debugPrint('RealTimeSync: Démarrage synchronisation $intervalSeconds sec');

    _syncTimer = Timer.periodic(Duration(seconds: intervalSeconds), (_) {
      _checkForUpdates();
    });

    _checkForUpdates();
  }

  void stopSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
    _isInitialized = false;
    debugPrint('RealTimeSync: Synchronisation arrêtée');
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
      final url = '$base/api/public/categories/';
      final res = await http.get(Uri.parse(url));

      if (res.statusCode != 200) return;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final categories = (data['categories'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      if (_categoriesChanged(categories)) {
        debugPrint('RealTimeSync: Nouvelles catégories!');
        _lastCategories = categories;
        _categoryController.add(categories);
      }
    } catch (e) {}
  }

  Future<void> _checkProvidersUpdate() async {
    try {
      final base = babifixApiBaseUrl();
      final url = '$base/api/public/providers/';
      final res = await http.get(Uri.parse(url));

      if (res.statusCode != 200) return;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final providers = (data['providers'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      if (_providersChanged(providers)) {
        debugPrint('RealTimeSync: Nouveaux prestataires!');
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
    _startAutoRefresh();
  }

  void _startAutoRefresh() {
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
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 16,
                ),
                color: Colors.green.shade600,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.refresh, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Nouvelles données - Appuyez pour actualiser',
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
