import 'package:flutter/material.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'package:zego_uikit_signaling_plugin/zego_uikit_signaling_plugin.dart';

import '../babifix_api_config.dart';
import '../babifix_design_system.dart';

class BabifixZegoService {
  static bool _isInitialized = false;

  static bool get isInitialized => _isInitialized;

  static Future<void> init({
    required int userId,
    required String userName,
    required BuildContext? context,
  }) async {
    if (!isZegoConfigured) {
      debugPrint('[Zego] Zego not configured (missing AppID/AppSign)');
      return;
    }

    final zegoUserID = 'client_$userId';

    debugPrint('[Zego] Initializing for client: $zegoUserID ($userName)');

    try {
      await ZegoUIKitPrebuiltCallInvitationService().init(
        appID: kZegoAppID,
        appSign: kZegoAppSign,
        userID: zegoUserID,
        userName: userName,
        plugins: [ZegoUIKitSignalingPlugin()],
        events: ZegoUIKitPrebuiltCallEvents(
          onCallEnd: (ZegoCallEndEvent event, VoidCallback defaultAction) {
            debugPrint('[Zego] Call ended: ${event.reason}');
            defaultAction.call();
          },
        ),
        invitationEvents: ZegoUIKitPrebuiltCallInvitationEvents(
          onIncomingCallReceived: (
            String callID,
            ZegoCallUser caller,
            ZegoCallInvitationType callType,
            List<ZegoCallUser> callees,
            String customData,
          ) {
            debugPrint('[Zego] Incoming call from: ${caller.name}');
          },
          onOutgoingCallTimeout: (
            String callID,
            List<ZegoCallUser> callees,
            bool isVideoCall,
          ) {
            debugPrint('[Zego] Outgoing call timeout');
          },
        ),
      );
      _isInitialized = true;
      debugPrint('[Zego] Initialized successfully');
    } catch (e) {
      debugPrint('[Zego] Init error: $e');
    }
  }

  static Future<void> uninit() async {
    if (!_isInitialized) return;
    try {
      await ZegoUIKitPrebuiltCallInvitationService().uninit();
      _isInitialized = false;
      debugPrint('[Zego] Uninitialized');
    } catch (e) {
      debugPrint('[Zego] Uninit error: $e');
    }
  }
}

class ZegoCallBtn extends StatelessWidget {
  final String targetUserID;
  final String targetUserName;
  final String reservationRef;
  final bool isVideoCall;

  const ZegoCallBtn({
    super.key,
    required this.targetUserID,
    required this.targetUserName,
    required this.reservationRef,
    this.isVideoCall = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!isZegoConfigured) {
      return OutlinedButton.icon(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Service d\'appel non configuré'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        icon: Icon(
          isVideoCall ? Icons.videocam : Icons.phone,
          size: 20,
        ),
        label: Text(isVideoCall ? 'Vidéo' : 'Appel'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.grey,
          side: BorderSide(color: Colors.grey.shade300),
          minimumSize: const Size(0, 54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      );
    }

    return ZegoSendCallInvitationButton(
      isVideoCall: isVideoCall,
      iconSize: const Size(24, 24),
      buttonSize: const Size(80, 54),
      text: isVideoCall ? 'Vidéo' : 'Appel',
      textStyle: TextStyle(
        color: isVideoCall ? BabifixDesign.navy : Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      invitees: [
        ZegoCallUser(
          id: targetUserID,
          name: targetUserName,
        ),
      ],
      onPressed: (String code, String message, List<String> errorInvitees) {
        if (errorInvitees.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$targetUserName ne répond pas...'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
    );
  }
}
