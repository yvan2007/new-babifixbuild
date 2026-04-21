import 'package:flutter/material.dart';

import '../../babifix_design_system.dart';

class CallButton extends StatelessWidget {
  final String targetId;
  final String targetName;
  final VoidCallback? onCallStarted;

  const CallButton({
    super.key,
    required this.targetId,
    required this.targetName,
    this.onCallStarted,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🔊 Appel vocal via Babifix vers $targetName...'),
            backgroundColor: BabifixDesign.ciBlue,
            duration: Duration(seconds: 2),
          ),
        );
        onCallStarted?.call();
      },
      icon: Icon(Icons.phone, color: Colors.white, size: 20),
      label: Text(
        '📞 Appeler',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: BabifixDesign.ciGreen,
        foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 2,
      ),
    );
  }
}

class VideoCallButton extends StatelessWidget {
  final String targetId;
  final String targetName;
  final VoidCallback? onCallStarted;

  const VideoCallButton({
    super.key,
    required this.targetId,
    required this.targetName,
    this.onCallStarted,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📹 Appel vidéo vers $targetName...'),
            backgroundColor: BabifixDesign.ciBlue,
            duration: Duration(seconds: 2),
          ),
        );
        onCallStarted?.call();
      },
      icon: Icon(Icons.videocam, color: Colors.white, size: 20),
      label: Text(
        '🎥 Vidéo',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: BabifixDesign.ciBlue,
        foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 2,
      ),
    );
  }
}
