import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../babifix_api_config.dart';
import '../babifix_design_system.dart';
import '../shared/auth_utils.dart';
import 'livekit_call_screen.dart';
import '../shared/widgets/babifix_snackbar.dart';

/// Service d'appel LiveKit pour l'app PRESTATAIRE.
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
  static String get currentIdentity => 'prestataire_${_currentUserId ?? 0}';

  /// Récupère un token LiveKit du backend.
  static Future<({String token, String url, String room})> _fetchToken({
    int? conversationId,
    String? reservationReference,
  }) async {
    if (conversationId == null && (reservationReference == null || reservationReference.isEmpty)) {
      throw ArgumentError('conversationId ou reservationReference requis');
    }

    final apiBase = babifixApiBaseUrl();
    final apiToken = await readStoredApiToken();
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
    debugPrint('[LiveKit Presta] Initialized userId=$userId userName=$userName');
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
    debugPrint('[LiveKit Presta] Uninitialized');
  }
}
