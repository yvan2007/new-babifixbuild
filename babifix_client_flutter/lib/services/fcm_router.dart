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

    // Plus de SnackBar ici : la notification SYSTÈME (en haut) est déjà
    // affichée par _onForegroundMessage, et l'événement est ajouté au centre de
    // notifications (cloche). Afficher en plus un SnackBar faisait apparaître la
    // notif EN DOUBLE (haut + bas). On ne garde donc que la gestion d'appel.
  }
}
