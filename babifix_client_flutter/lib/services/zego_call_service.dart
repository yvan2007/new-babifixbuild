import 'package:flutter/material.dart';

import '../babifix_design_system.dart';

class BabifixZegoService {
  static bool _isInitialized = false;

  static Future<void> init({
    required String userID,
    required String userName,
  }) async {
    _isInitialized = true;
    debugPrint('ZEGO init: $userID ($userName)');
  }

  static void startVoiceCall({
    required BuildContext context,
    required String callID,
    required String targetUserID,
    required String targetUserName,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Appel vocal vers $targetUserName (ID: $targetUserID)'),
      ),
    );
  }

  static void startVideoCall({
    required BuildContext context,
    required String callID,
    required String targetUserID,
    required String targetUserName,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Appel vidéo vers $targetUserName (ID: $targetUserID)'),
      ),
    );
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
    return ElevatedButton.icon(
      onPressed: () {
        final callID =
            'call_${reservationRef}_${DateTime.now().millisecondsSinceEpoch}';
        if (isVideoCall) {
          BabifixZegoService.startVideoCall(
            context: context,
            callID: callID,
            targetUserID: targetUserID,
            targetUserName: targetUserName,
          );
        } else {
          BabifixZegoService.startVoiceCall(
            context: context,
            callID: callID,
            targetUserID: targetUserID,
            targetUserName: targetUserName,
          );
        }
      },
      icon: Icon(
        isVideoCall ? Icons.videocam : Icons.phone,
        color: Colors.white,
      ),
      label: Text(
        isVideoCall ? 'Appel Vidéo' : 'Appeler via Babifix',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: isVideoCall
            ? BabifixDesign.ciBlue
            : BabifixDesign.ciGreen,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
