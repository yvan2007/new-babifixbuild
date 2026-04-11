import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class NetworkConnectivity {
  NetworkConnectivity._();

  static final NetworkConnectivity instance = NetworkConnectivity._();

  final Connectivity _connectivity = Connectivity();

  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  Stream<bool> get onConnectivityChanged => _connectionController.stream;

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  Future<void> initialize() async {
    final results = await _connectivity.checkConnectivity();
    _updateStatus(results);

    _connectivity.onConnectivityChanged.listen(_updateStatus);
  }

  void _updateStatus(List<ConnectivityResult> results) {
    final wasOnline = _isOnline;
    _isOnline =
        results.isNotEmpty && !results.contains(ConnectivityResult.none);

    if (wasOnline != _isOnline) {
      _connectionController.add(_isOnline);
      debugPrint(
        '[Network] Connectivity changed: ${_isOnline ? "ONLINE" : "OFFLINE"}',
      );
    }
  }

  Future<bool> checkConnection() async {
    final results = await _connectivity.checkConnectivity();
    _isOnline =
        results.isNotEmpty && !results.contains(ConnectivityResult.none);
    return _isOnline;
  }

  void dispose() {
    _connectionController.close();
  }
}

class OfflineAwareWidget extends StatefulWidget {
  final Widget child;
  final Widget? offlineBanner;

  const OfflineAwareWidget({
    super.key,
    required this.child,
    this.offlineBanner,
  });

  @override
  State<OfflineAwareWidget> createState() => _OfflineAwareWidgetState();
}

class _OfflineAwareWidgetState extends State<OfflineAwareWidget> {
  late StreamSubscription<bool> _subscription;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    _subscription = NetworkConnectivity.instance.onConnectivityChanged.listen((
      isOnline,
    ) {
      if (mounted) {
        setState(() {
          _isOffline = !isOnline;
        });
      }
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_isOffline)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: widget.offlineBanner ?? _DefaultOfflineBanner(),
          ),
      ],
    );
  }
}

class _DefaultOfflineBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: Colors.orange.shade800,
      child: const Text(
        'Vous êtes hors ligne. Certaines fonctionnalités peuvent être limitées.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white, fontSize: 14),
      ),
    );
  }
}
