export 'livekit_call_service.dart';

import 'package:flutter/material.dart';
import 'livekit_call_service.dart';

@Deprecated('Use BabifixLiveKitService instead')
class BabifixZegoService {
  static bool get isInitialized => BabifixLiveKitService.isInitialized;

  static Future<void> init({
    required int userId,
    required String userName,
    BuildContext? context,
  }) async {
    return BabifixLiveKitService.init(
      userId: userId,
      userName: userName,
      context: context,
    );
  }

  static void startVoiceCall({
    required BuildContext context,
    required String callID,
    required String targetUserID,
    required String targetUserName,
  }) {
    BabifixLiveKitService.startVoiceCall(
      context: context,
      callID: callID,
      targetUserID: targetUserID,
      targetUserName: targetUserName,
    );
  }

  static void startVideoCall({
    required BuildContext context,
    required String callID,
    required String targetUserID,
    required String targetUserName,
  }) {
    BabifixLiveKitService.startVideoCall(
      context: context,
      callID: callID,
      targetUserID: targetUserID,
      targetUserName: targetUserName,
    );
  }

  static Future<void> uninit() async {
    return BabifixLiveKitService.uninit();
  }
}
