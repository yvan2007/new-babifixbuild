/// Contrôle de version minimale (force update).
/// Compare la version installée à la version minimale renvoyée par le backend
/// (`/api/app/version`). Si l'app est trop ancienne → écran de mise à jour
/// bloquant. Tolérant : silencieux en cas d'erreur réseau (ne bloque jamais à tort).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../babifix_api_config.dart';

/// Version installée de l'app — à incrémenter à chaque release.
const String kAppVersion = '1.0.0';

int _cmpVersion(String a, String b) {
  List<int> parse(String s) =>
      s.split('.').map((x) => int.tryParse(x.trim()) ?? 0).toList();
  final pa = parse(a);
  final pb = parse(b);
  for (var i = 0; i < 3; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x < y ? -1 : 1;
  }
  return 0;
}

Future<void> checkAppVersionGate(
  BuildContext context, {
  String app = 'client',
}) async {
  try {
    final resp = await http
        .get(Uri.parse('${babifixApiBaseUrl()}/api/app/version?app=$app'))
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) return;
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    final android = (j['android'] as Map<String, dynamic>?) ?? {};
    final minV = (android['min_version'] ?? '1.0.0').toString();
    final storeUrl = (android['store_url'] ?? '').toString();
    final msg = (j['message'] ??
            'Mettez à jour BABIFIX pour continuer.')
        .toString();
    if (_cmpVersion(kAppVersion, minV) < 0 && context.mounted) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PopScope(
          canPop: false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            icon: const Icon(Icons.system_update_rounded,
                size: 48, color: Color(0xFF4CC9F0)),
            title: const Text('Mise à jour requise',
                style: TextStyle(fontWeight: FontWeight.w800)),
            content: Text(msg,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13.5, height: 1.4)),
            actions: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CC9F0),
                    foregroundColor: const Color(0xFF0B1B34),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Mettre à jour',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  onPressed: () {
                    if (storeUrl.isNotEmpty) {
                      launchUrl(Uri.parse(storeUrl),
                          mode: LaunchMode.externalApplication);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      );
    }
  } catch (_) {
    // silencieux : ne jamais bloquer l'app sur une erreur réseau
  }
}
