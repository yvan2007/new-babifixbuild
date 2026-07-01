import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../babifix_api_config.dart';
import '../babifix_design_system.dart';
import '../user_store.dart';
import 'livekit_call_screen.dart';
import '../shared/widgets/babifix_snackbar.dart';

/// Service d'appel LiveKit pour l'app CLIENT.
///
/// IMPORTANT (sécurité) : aucun secret LiveKit n'est stocké dans cette
/// app. Tous les tokens sont générés côté backend (`/api/livekit/token`
/// ou `/api/calls/initiate`) qui détient seul la clé API LiveKit.
class BabifixLiveKitService {
  static bool _isInitialized = false;
  static bool get isInitialized => _isInitialized;
  static int? _currentUserId;
  static String? _currentUserName;

  static int? get currentUserId => _currentUserId;
  static String? get currentUserName => _currentUserName;
  static String get currentIdentity => 'client_${_currentUserId ?? 0}';

  /// Récupère un token LiveKit du backend pour rejoindre une room donnée.
  /// Le backend vérifie que l'user a bien le droit d'accéder à cette
  /// conversation/réservation avant de signer.
  static Future<({String token, String url, String room})> _fetchToken({
    int? conversationId,
    String? reservationReference,
  }) async {
    if (conversationId == null && (reservationReference == null || reservationReference.isEmpty)) {
      throw ArgumentError('conversationId ou reservationReference requis');
    }

    final apiBase = babifixApiBaseUrl();
    final apiToken = await BabifixUserStore.getApiToken();
    if (apiToken == null || apiToken.isEmpty) {
      throw Exception('Non authentifié');
    }

    final body = <String, dynamic>{};
    if (conversationId != null) body['conversation_id'] = conversationId;
    if (reservationReference != null && reservationReference.isNotEmpty) {
      body['reservation_reference'] = reservationReference;
    }

    final res = await http.post(
      Uri.parse('$apiBase/api/livekit/token'),
      headers: {
        'Authorization': 'Bearer $apiToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (res.statusCode != 200) {
      String msg = 'Erreur ${res.statusCode}';
      try {
        msg = (jsonDecode(res.body)['error'] ?? msg).toString();
      } catch (_) {}
      throw Exception(msg);
    }

    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return (
      token: (j['token'] ?? '').toString(),
      url: (j['url'] ?? '').toString(),
      room: (j['room'] ?? '').toString(),
    );
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
    required int conversationId,
    required String targetUserID,
    required String targetUserName,
  }) async {
    await _startCall(
      context: context,
      conversationId: conversationId,
      targetUserID: targetUserID,
      targetUserName: targetUserName,
      isVideoCall: false,
    );
  }

  static Future<void> startVideoCall({
    required BuildContext context,
    required int conversationId,
    required String targetUserID,
    required String targetUserName,
  }) async {
    await _startCall(
      context: context,
      conversationId: conversationId,
      targetUserID: targetUserID,
      targetUserName: targetUserName,
      isVideoCall: true,
    );
  }

  static Future<void> _startCall({
    required BuildContext context,
    required int conversationId,
    required String targetUserID,
    required String targetUserName,
    required bool isVideoCall,
  }) async {
    if (!_isInitialized || _currentUserId == null) {
      showBabifixToast(
        context,
        type: BabifixToastType.info,
        message: 'Service d\'appel non initialisé (userId=$_currentUserId)',
      );
      return;
    }

    try {
      final creds = await _fetchToken(conversationId: conversationId);
      if (!context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => LiveKitCallScreen(
            liveKitUrl: creds.url,
            token: creds.token,
            roomName: creds.room,
            targetUserID: targetUserID,
            targetUserName: targetUserName,
            isVideoCall: isVideoCall,
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      showBabifixToast(
        context,
        type: BabifixToastType.error,
        message: 'Impossible de démarrer l\'appel : $e',
      );
    }
  }

  static String getIdentityForClient(int clientId) => 'client_$clientId';
  static String getIdentityForPrestataire(int prestataireId) =>
      'prestataire_$prestataireId';

  static Future<void> uninit() async {
    _isInitialized = false;
    _currentUserId = null;
    _currentUserName = null;
    debugPrint('[LiveKit] Uninitialized');
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
    showBabifixToast(
        context,
        type: BabifixToastType.info,
        message: 'Conversation non initialisée',
      );
    return;
  }

  if (!BabifixLiveKitService.isInitialized) {
    showBabifixToast(
        context,
        type: BabifixToastType.info,
        message: 'Service d\'appel non initialisé : reconnectez-vous',
      );
    return;
  }

  if (isVideoCall) {
    BabifixLiveKitService.startVideoCall(
      context: context,
      conversationId: conversationId,
      targetUserID: targetUserID,
      targetUserName: targetUserName,
    );
  } else {
    BabifixLiveKitService.startVoiceCall(
      context: context,
      conversationId: conversationId,
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
      icon: Icon(isVideoCall ? Icons.videocam : Icons.phone),
      label: Text(isVideoCall ? 'Vidéo' : 'Appel'),
      onPressed: () async {
        try {
          final creds = await BabifixLiveKitService._fetchToken(
            reservationReference: reservationRef,
          );
          if (!context.mounted) return;
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => LiveKitCallScreen(
                liveKitUrl: creds.url,
                token: creds.token,
                roomName: creds.room,
                targetUserID: targetUserID,
                targetUserName: targetUserName,
                isVideoCall: isVideoCall,
              ),
            ),
          );
        } catch (e) {
          if (!context.mounted) return;
          showBabifixToast(
        context,
        type: BabifixToastType.error,
        message: 'Erreur : $e',
      );
        }
      },
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
