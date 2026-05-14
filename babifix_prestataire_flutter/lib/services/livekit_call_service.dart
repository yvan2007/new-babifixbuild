import 'package:flutter/material.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

import '../babifix_design_system.dart';
import 'livekit_call_screen.dart';

const _hardcodedLiveKitUrl = 'wss://babifix-h1giwqew.livekit.cloud';
const _hardcodedApiKey = 'APIHmepmCSoou3K';
const _hardcodedApiSecret = 'Cets7RORRaNS61Ie4dyCY0rE33lyzxTBrG7NYQifs6IA';

class BabifixLiveKitService {
  static bool _isInitialized = false;
  static bool get isInitialized => _isInitialized;
  static int? _currentUserId;
  static String? _currentUserName;

  static String get url => _hardcodedLiveKitUrl;
  static String get apiKey => _hardcodedApiKey;
  static String get apiSecret => _hardcodedApiSecret;
  static int? get currentUserId => _currentUserId;
  static String? get currentUserName => _currentUserName;
  static String get currentIdentity => 'prestataire_${_currentUserId ?? 0}';

  static String generateLiveKitToken({
    required String identity,
    required String name,
    required String roomName,
    Duration expiresIn = const Duration(hours: 24),
  }) {
    final apiKeyVal = apiKey;
    final apiSecretVal = apiSecret;

    debugPrint('[LiveKit] Generating token with:');
    debugPrint('[LiveKit]   apiKey=$apiKeyVal');
    debugPrint('[LiveKit]   url=$url');

    if (apiKeyVal.isEmpty || apiSecretVal.isEmpty) {
      throw Exception('LiveKit credentials not configured');
    }

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final expiresAt = now + expiresIn.inSeconds;

    final payload = {
      'iss': apiKey,
      'sub': identity,
      'exp': expiresAt,
      'nbf': now - 60,
      'name': name,
      'video': {
        'room': roomName,
        'roomJoin': true,
        'roomCreate': true,
        'canPublish': true,
        'canSubscribe': true,
        'canPublishData': true,
      },
    };

    final jwt = JWT(payload);
    final token = jwt.sign(
      SecretKey(apiSecret),
      algorithm: JWTAlgorithm.HS256,
    );

    return token;
  }

  static Future<void> init({
    required int userId,
    required String userName,
    BuildContext? context,
  }) async {
    _currentUserId = userId;
    _currentUserName = userName;
    _isInitialized = true;
    debugPrint('[LiveKit] Initialized for userId=$userId, userName=$userName');
  }

  static Future<void> startVoiceCall({
    required BuildContext context,
    required String callID,
    required String targetUserID,
    required String targetUserName,
  }) async {
    await _startCall(
      context: context,
      callID: callID,
      targetUserID: targetUserID,
      targetUserName: targetUserName,
      isVideoCall: false,
    );
  }

  static Future<void> startVideoCall({
    required BuildContext context,
    required String callID,
    required String targetUserID,
    required String targetUserName,
  }) async {
    await _startCall(
      context: context,
      callID: callID,
      targetUserID: targetUserID,
      targetUserName: targetUserName,
      isVideoCall: true,
    );
  }

  static Future<void> _startCall({
    required BuildContext context,
    required String callID,
    required String targetUserID,
    required String targetUserName,
    required bool isVideoCall,
  }) async {
    debugPrint('[LiveKit] _startCall called:');
    debugPrint('[LiveKit]   _isInitialized=$_isInitialized');
    debugPrint('[LiveKit]   _currentUserId=$_currentUserId');
    debugPrint('[LiveKit]   url=$url');
    debugPrint('[LiveKit]   apiKey len=${apiKey.length}');

    if (!_isInitialized || _currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Service d\'appel non initialisé (userId=$_currentUserId)'),
          backgroundColor: BabifixDesign.error,
        ),
      );
      return;
    }

    final liveKitUrl = url;
    if (liveKitUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('LiveKit URL non configuré'),
          backgroundColor: BabifixDesign.error,
        ),
      );
      return;
    }

    final roomName = 'room_$callID';
    final identity = _getCurrentIdentity();
    final token = generateLiveKitToken(
      identity: identity,
      name: _currentUserName ?? 'User',
      roomName: roomName,
    );

    debugPrint('[LiveKit] Starting ${isVideoCall ? 'video' : 'voice'} call');
    debugPrint('[LiveKit] Room: $roomName');
    debugPrint('[LiveKit] Identity: $identity');
    debugPrint('[LiveKit] Target: $targetUserID ($targetUserName)');
    debugPrint('[LiveKit] URL: $liveKitUrl');

    if (context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => LiveKitCallScreen(
            liveKitUrl: liveKitUrl,
            token: token,
            roomName: roomName,
            targetUserID: targetUserID,
            targetUserName: targetUserName,
            isVideoCall: isVideoCall,
          ),
        ),
      );
    }
  }

  static String _getCurrentIdentity() {
    return 'prestataire_${_currentUserId ?? 0}';
  }

  static String getIdentityForClient(int clientId) => 'client_$clientId';
  static String getIdentityForPrestataire(int prestataireId) => 'prestataire_$prestataireId';

  static Future<void> uninit() async {
    _isInitialized = false;
    _currentUserId = null;
    _currentUserName = null;
    debugPrint('[LiveKit] Uninitialized');
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
            '${reservationRef}_${DateTime.now().millisecondsSinceEpoch}';
        if (isVideoCall) {
          BabifixLiveKitService.startVideoCall(
            context: context,
            callID: callID,
            targetUserID: targetUserID,
            targetUserName: targetUserName,
          );
        } else {
          BabifixLiveKitService.startVoiceCall(
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

void _startCallFromChat({
  required BuildContext context,
  required int? conversationId,
  required String targetUserID,
  required String targetUserName,
  required bool isVideoCall,
}) {
  if (conversationId == null || conversationId <= 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Conversation non initialisée'),
        backgroundColor: BabifixDesign.error,
      ),
    );
    return;
  }

  if (!BabifixLiveKitService.isInitialized) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Service d\'appel non initialisé — reconnectez-vous'),
        backgroundColor: BabifixDesign.error,
      ),
    );
    return;
  }

  final roomId = 'chat_conv_$conversationId';

  debugPrint('[LiveKit Chat] Starting call, room=$roomId');

  if (isVideoCall) {
    BabifixLiveKitService.startVideoCall(
      context: context,
      callID: roomId,
      targetUserID: targetUserID,
      targetUserName: targetUserName,
    );
  } else {
    BabifixLiveKitService.startVoiceCall(
      context: context,
      callID: roomId,
      targetUserID: targetUserID,
      targetUserName: targetUserName,
    );
  }
}

class ChatCallButton extends StatelessWidget {
  final int? conversationId;
  final String targetUserID;
  final String targetUserName;
  final bool isVideoCall;

  const ChatCallButton({
    super.key,
    required this.conversationId,
    required this.targetUserID,
    required this.targetUserName,
    this.isVideoCall = false,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        isVideoCall ? Icons.videocam : Icons.phone,
        color: Theme.of(context).primaryColor,
      ),
      tooltip: isVideoCall ? 'Appel vidéo' : 'Appel audio',
      onPressed: () => _startCallFromChat(
        context: context,
        conversationId: conversationId,
        targetUserID: targetUserID,
        targetUserName: targetUserName,
        isVideoCall: isVideoCall,
      ),
    );
  }
}
