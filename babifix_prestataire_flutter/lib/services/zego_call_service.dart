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

    final zegoUserID = 'prestataire_$userId';

    debugPrint('[Zego] Initializing for prestataire: $zegoUserID ($userName)');

    try {
      await ZegoUIKitPrebuiltCallInvitationService().init(
        appID: kZegoAppID,
        appSign: kZegoAppSign,
        userID: zegoUserID,
        userName: userName,
        plugins: [ZegoUIKitSignalingPlugin()],
        config: ZegoCallInvitationConfig(
          useSystemCallingUI: false,
        ),
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
            ZegoCallType callType,
            Map<String, String> customData,
          ) {
            debugPrint('[Zego] Incoming call from: ${caller.name} (type: $callType)');
          },
          onIncomingCallAccepted: (
            String callID,
            ZegoCallUser caller,
            ZegoCallType callType,
            Map<String, String> customData,
          ) {
            debugPrint('[Zego] Incoming call accepted');
          },
          onIncomingCallRejected: (
            String callID,
            ZegoCallUser caller,
            ZegoCallType callType,
            Map<String, String> customData,
          ) {
            debugPrint('[Zego] Incoming call rejected');
          },
          onOutgoingCallAccepted: (
            String callID,
            ZegoCallUser callee,
            ZegoCallType callType,
          ) {
            debugPrint('[Zego] Outgoing call accepted by: ${callee.name}');
          },
          onOutgoingCallRejected: (
            String callID,
            ZegoCallUser callee,
            ZegoCallType callType,
            String code,
            String message,
          ) {
            debugPrint('[Zego] Outgoing call rejected: $message');
          },
          onOutgoingCallTimeout: (
            String callID,
            List<ZegoCallUser> callees,
            ZegoCallType callType,
          ) {
            debugPrint('[Zego] Outgoing call timeout');
            if (callees.isNotEmpty) {
              ScaffoldMessenger.of(
                ZegoUIKitPrebuiltCallInvitationService().navigatorKey.currentContext!,
              ).showSnackBar(
                SnackBar(
                  content: Text('${callees.first.name} ne répond pas...'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
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

  static Future<bool> sendCallInvitation({
    required String targetUserID,
    required String targetUserName,
    required bool isVideoCall,
  }) async {
    if (!isZegoConfigured || !_isInitialized) {
      debugPrint('[Zego] Cannot send call: not configured or not initialized');
      return false;
    }

    try {
      final result = await ZegoUIKitPrebuiltCallInvitationService().send(
        invitees: [
          ZegoCallUser(
            id: targetUserID,
            name: targetUserName,
          ),
        ],
        isVideoCall: isVideoCall,
        notificationTitle: isVideoCall ? 'Appel vidéo' : 'Appel vocal',
        notificationMessage: '${targetUserName} vous appelle...',
        timeoutSeconds: 60,
      );
      debugPrint('[Zego] Call invitation sent to $targetUserID');
      return result;
    } catch (e) {
      debugPrint('[Zego] Send call error: $e');
      return false;
    }
  }
}

class CallButton extends StatelessWidget {
  final String targetUserID;
  final String targetUserName;
  final String callID;
  final bool isVideo;

  const CallButton({
    super.key,
    required this.targetUserID,
    required this.targetUserName,
    required this.callID,
    this.isVideo = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!isZegoConfigured) {
      return ElevatedButton.icon(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Service d\'appel non configuré'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        icon: Icon(isVideo ? Icons.videocam : Icons.phone, color: Colors.white),
        label: Text(
          isVideo ? 'Appel Vidéo' : 'Appeler',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.grey.shade400,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }

    return ZegoSendCallInvitationButton(
      isVideoCall: isVideo,
      iconSize: const Size(32, 32),
      buttonSize: const Size(80, 54),
      icon: ButtonIcon(
        icon: isVideo ? Icons.videocam : Icons.phone,
      ),
      text: isVideo ? 'Vidéo' : 'Appel',
      textStyle: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      invitees: [
        ZegoUIKitUser(
          id: targetUserID,
          name: targetUserName,
        ),
      ],
      onPressed: (String code, String message, List<String> errorInvitees) {
        if (errorInvitees.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Impossible d\'appeler $targetUserName'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
    );
  }
}
