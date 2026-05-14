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
    if (msg != null) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        backgroundColor: color,
        content: Text(msg, style: const TextStyle(color: Colors.white)),
      ));
    }
  }
}
