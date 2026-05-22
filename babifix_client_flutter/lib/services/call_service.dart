/// CallService — appel BABIFIX via LiveKit, signalisation backend authoritative
/// (Phase D — C7/P9 + S2 suppression secret côté Flutter).
///
/// Plus aucune génération de token côté app : on délègue tout à
/// `/api/calls/*`. La sonnerie entrante est déclenchée par un FCM
/// data-message `type=call.incoming` reçu via [BabifixFcm].
import 'package:flutter/material.dart';

import '../babifix_design_system.dart';
import '../models/babifix_models.dart';
import '../services/babifix_api.dart';
import 'incoming_call_screen.dart';
import 'livekit_call_screen.dart';
import '../shared/widgets/babifix_snackbar.dart';

class CallService {
  CallService._();

  /// Démarre un appel sortant : crée la room côté backend, envoie un FCM
  /// ring à l'autre partie, et ouvre l'écran d'appel actif.
  static Future<void> startOutgoing({
    required BuildContext context,
    required String reservationReference,
    required String targetName,
    bool isVideo = false,
  }) async {
    try {
      final invite = await CallsApi.initiate(
        reservationReference: reservationReference,
        isVideo: isVideo,
      );
      if (!context.mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => LiveKitCallScreen(
          liveKitUrl: invite.call.liveKitUrl,
          token: invite.token,
          roomName: invite.call.roomName,
          targetUserID: invite.call.calleeId.toString(),
          targetUserName: targetName.isEmpty ? invite.call.calleeName : targetName,
          isVideoCall: isVideo,
        ),
      ));
      // Best-effort : à la sortie de l'écran, on tente un /end
      try {
        await CallsApi.end(invite.call.id);
      } catch (_) {}
    } on BabifixApiException catch (e) {
      if (!context.mounted) return;
      showBabifixToast(
        context,
        type: BabifixToastType.error,
        message: 'Impossible de démarrer l\'appel : ${e.message}',
      );
    } catch (e) {
      if (!context.mounted) return;
      showBabifixToast(
        context,
        type: BabifixToastType.error,
        message: 'Erreur appel : $e',
      );
    }
  }

  /// À appeler quand un FCM data `type=call.incoming` arrive. Affiche
  /// l'écran d'appel entrant fullscreen.
  static Future<void> handleIncomingFcm({
    required BuildContext context,
    required Map<String, dynamic> data,
  }) async {
    final callIdStr = (data['call_id'] ?? '').toString();
    if (callIdStr.isEmpty) return;
    final callId = int.tryParse(callIdStr);
    if (callId == null) return;
    final isVideo = (data['kind'] ?? '').toString().toUpperCase() == 'VIDEO';
    final callerName = (data['caller_name'] ?? 'Quelqu\'un').toString();
    final room = (data['room_name'] ?? '').toString();
    final reservationRef = (data['reservation_reference'] ?? '').toString();

    if (!context.mounted) return;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => IncomingCallScreen(
          callId: callId,
          isVideo: isVideo,
          callerName: callerName,
          roomName: room,
          reservationReference: reservationRef,
        ),
      ),
    );
  }

  /// Helper utilisé après un answer côté callee.
  static Future<void> openActiveCallFromInvite({
    required BuildContext context,
    required CallInvite invite,
    required bool isVideo,
  }) async {
    if (!context.mounted) return;
    await Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => LiveKitCallScreen(
        liveKitUrl: invite.call.liveKitUrl,
        token: invite.token,
        roomName: invite.call.roomName,
        targetUserID: invite.call.callerId.toString(),
        targetUserName: invite.call.callerName,
        isVideoCall: isVideo,
      ),
    ));
  }
}
