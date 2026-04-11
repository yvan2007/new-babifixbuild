import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../babifix_design_system.dart';

/// Bandeau rouge affiché en haut de page quand la connexion est perdue.
class ConnectivityBanner extends StatefulWidget {
  const ConnectivityBanner({super.key, required this.child});
  final Widget child;

  @override
  State<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends State<ConnectivityBanner> {
  bool _offline = false;
  late final StreamSubscription<List<ConnectivityResult>> _sub;

  @override
  void initState() {
    super.initState();
    _sub = Connectivity().onConnectivityChanged.listen((results) {
      final offline = results.every((r) => r == ConnectivityResult.none);
      if (mounted && offline != _offline) setState(() => _offline = offline);
    });
    // État initial
    Connectivity().checkConnectivity().then((results) {
      if (mounted) {
        setState(() => _offline = results.every((r) => r == ConnectivityResult.none));
      }
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Container(
            width: double.infinity,
            color: const Color(0xFFEF4444),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: const Row(
              children: [
                Icon(Icons.wifi_off_rounded, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Pas de connexion — affichage des données en cache',
                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          crossFadeState: _offline ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 300),
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}
