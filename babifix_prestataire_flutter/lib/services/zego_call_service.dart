import 'package:flutter/material.dart';

import '../babifix_design_system.dart';

class VoiceCallService {
  static bool _isInitialized = false;

  static Future<void> initialize(String userId, String userName) async {
    _isInitialized = true;
    debugPrint('VoiceCall init: $userId ($userName)');
  }

  static Future<void> startVoiceCall({
    required BuildContext context,
    required String callID,
    required String targetUserID,
    required String targetUserName,
  }) async {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Appel vers $targetUserName')));
  }

  static void dispose() {
    _isInitialized = false;
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
    return ElevatedButton.icon(
      onPressed: () {
        VoiceCallService.startVoiceCall(
          context: context,
          callID: callID,
          targetUserID: targetUserID,
          targetUserName: targetUserName,
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
        backgroundColor: isVideo ? BabifixDesign.ciBlue : BabifixDesign.ciGreen,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
