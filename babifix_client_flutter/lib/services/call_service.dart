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
      // Cas métier (prestation terminée / contact pas encore autorisé) : rendu
      // soigné via un dialog d'info, pas un toast rouge d'erreur technique.
      final low = '${e.code} ${e.message}'.toLowerCase();
      final isBusinessRule = low.contains('prestation_terminee') ||
          low.contains('contact_not_allowed') ||
          low.contains('reservation_not_found');
      if (isBusinessRule) {
        _showCallBlockedDialog(
          context,
          terminee: low.contains('prestation_terminee'),
          message: e.message,
        );
      } else {
        showBabifixToast(
          context,
          type: BabifixToastType.error,
          message: 'Impossible de démarrer l\'appel : ${e.message}',
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      showBabifixToast(
        context,
        type: BabifixToastType.error,
        message: 'Erreur appel : $e',
      );
    }
  }

  /// Dialog soigné quand un appel est bloqué par une règle métier
  /// (prestation terminée, ou contact pas encore autorisé).
  static void _showCallBlockedDialog(
    BuildContext context, {
    required bool terminee,
    required String message,
  }) {
    final accent =
        terminee ? const Color(0xFF0EA5E9) : const Color(0xFFF59E0B);
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  terminee ? Icons.verified_rounded : Icons.lock_clock_rounded,
                  size: 42,
                  color: accent,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                terminee ? 'Prestation terminée' : 'Appel pas encore disponible',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0B1B34)),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13.5, height: 1.45, color: Color(0xFF475569)),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13)),
                  ),
                  child: const Text('Compris',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
