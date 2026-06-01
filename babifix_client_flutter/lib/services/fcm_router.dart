/// Routeur des FCM data-messages BABIFIX (Phase D + S3 + S8).
///
/// Reçoit la map `data` brute du payload FCM et déclenche l'action UI
/// appropriée :
///
/// | type                  | action                                |
/// |-----------------------|---------------------------------------|
/// | call.incoming         | Ouvre IncomingCallScreen fullscreen   |
/// | call.answered / ended | Snack + ferme l'écran d'appel actif   |
/// | call.rejected         | Snack                                  |
/// | intervention.started  | Snack info                            |
/// | intervention.finished | Snack + redirige vers confirmation    |
/// | payment.received      | Snack                                  |
/// | client.confirmed      | Snack                                  |
/// | chat.message          | Snack (notif déjà gérée par OS)       |
///
/// On expose un seul point d'entrée [route] que [BabifixFcm] appelle.
import 'package:flutter/material.dart';

import '../babifix_design_system.dart';
import 'call_service.dart';

class BabifixFcmRouter {
  BabifixFcmRouter._();

  /// Navigator key global utilisé pour pousser des écrans sans
  /// BuildContext direct (typiquement pour les calls en arrière-plan).
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static Future<void> route(Map<String, dynamic> data) async {
    final type = (data['type'] ?? '').toString();
    if (type.isEmpty) return;

    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;

    if (type == 'call.incoming') {
      await CallService.handleIncomingFcm(context: ctx, data: data);
      return;
    }

    // Autres événements : on remonte un SnackBar contextuel.
    String? msg;
    Color color = BabifixDesign.ciBlue;
    switch (type) {
      case 'call.answered':
        msg = 'Appel accepté.';
        color = BabifixDesign.ciGreen;
        break;
      case 'call.rejected':
        msg = "L'appel n'a pas été pris.";
        color = BabifixDesign.error;
        break;
      case 'call.ended':
        final dur = data['duration_seconds']?.toString() ?? '0';
        msg = "Appel terminé (${dur}s).";
        break;
      case 'intervention.started':
        msg = 'Intervention démarrée.';
        color = BabifixDesign.ciGreen;
        break;
      case 'intervention.finished':
        msg = "Le prestataire a terminé. Veuillez confirmer.";
        break;
      case 'payment.received':
        msg = 'Paiement reçu.';
        color = BabifixDesign.ciGreen;
        break;
      case 'client.confirmed':
      case 'funds.released':
        msg = 'Travaux confirmés, fonds libérés.';
        color = BabifixDesign.ciGreen;
        break;
      case 'devis.received':
        msg = 'Nouveau devis reçu.';
        break;
      case 'devis.accepted':
        msg = 'Devis accepté par le client.';
        color = BabifixDesign.ciGreen;
        break;
      case 'devis.refused':
        msg = 'Devis refusé.';
        color = BabifixDesign.error;
        break;
    }
    if (type == 'notification' || type == 'broadcast') {
      final nTitle = (data['title'] ?? '').toString();
      final nBody = (data['body'] ?? '').toString();
      try {
        ScaffoldMessenger.of(ctx).clearSnackBars();
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          backgroundColor: const Color(0xFF2C3E50),
          padding: EdgeInsets.only(top: MediaQuery.of(ctx).padding.top + 8, left: 16, right: 16, bottom: 12),
          margin: EdgeInsets.zero,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(bottom: Radius.circular(24))),
          elevation: 8,
          duration: const Duration(seconds: 4),
          content: Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
                child: const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (nTitle.isNotEmpty)
                      Text(nTitle, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (nBody.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(nBody, style: const TextStyle(color: Colors.white70, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ));
      } catch (_) {}
      return;
    }

    if (msg != null) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        backgroundColor: color,
        content: Text(msg, style: const TextStyle(color: Colors.white)),
      ));
    }
  }
}
