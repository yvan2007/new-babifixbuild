class BabifixZegoConfig {
  // ZEGOCLOUD Account - BABIFIX
  static const int appId = 1521126264;
  static const String appSign =
      'f12825891f04174427822ee6a4f6c7c4331211b38130b72b7664df803ace456f';
  static const String serverSecret = 'c5ca398c430c6522a418d91dd15465aa';

  static String getCurrentUserId(String userId, String role) {
    return 'babifix_${role}_$userId';
  }

  static String generateCallId(String reservationRef) {
    return 'call_babifix_$reservationRef';
  }
}
