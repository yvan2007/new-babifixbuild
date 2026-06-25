import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:photo_view/photo_view.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../json_utils.dart';
import '../../user_store.dart';
import '../../services/call_service.dart';
import '../../services/livekit_call_service.dart';
import '../../services/livekit_call_screen.dart';
import '../../shared/error_utils.dart';
import '../../shared/widgets/babifix_phase_widgets.dart';
import '../auth/biometric_login_screen.dart';
import '../booking/devis_kanban_screen.dart';
import '../../shared/widgets/babifix_snackbar.dart';
import '../../shared/widgets/babifix_voice_note.dart';

// ── Model ────────────────────────────────────────────────────────────────────

class ClientChatMsg {
  ClientChatMsg({
    required this.id,
    this.text,
    this.imageBytes,
    this.imageUrl,
    required this.me,
    this.replyToText,
    this.replyToWasMe,
    this.serverMessageId,
    this.replyToServerId,
    this.isRead = false,
    this.kind = 'USER',
    this.payloadJson,
    this.audioUrl,
    this.audioDuration = 0,
  });

  final int id;
  final String? text;
  final Uint8List? imageBytes;
  final String? imageUrl;
  final bool me;
  final String? replyToText;
  final bool? replyToWasMe;
  final int? serverMessageId;
  final int? replyToServerId;
  final bool isRead;
  // Phase C : kind = USER | DEVIS_CARD | SYSTEM
  final String kind;
  final Map<String, dynamic>? payloadJson;
  // Note vocale (URL du fichier audio + durée en secondes).
  final String? audioUrl;
  final int audioDuration;

  bool get hasAudio => audioUrl != null && audioUrl!.isNotEmpty;

  bool get hasContent =>
      (text != null && text!.trim().isNotEmpty) ||
      (imageBytes != null && imageBytes!.isNotEmpty) ||
      (imageUrl != null && imageUrl!.isNotEmpty) ||
      hasAudio;

  String get snippet {
    if (text != null && text!.trim().isNotEmpty) {
      final t = text!.trim();
      return t.length > 80 ? '${t.substring(0, 80)}…' : t;
    }
    return '[Photo]';
  }
}

// ── Screen ───────────────────────────────────────────────────────────────────

class ChatRoomScreen extends StatefulWidget {
  const ChatRoomScreen({
    super.key,
    required this.name,
    this.seed = const [],
    this.peerUserId,
    this.conversationId,
    this.authToken,
    this.apiBase,
    this.reservationReference,
  });

  final String name;
  final List<(String, bool)> seed;
  final int? peerUserId;
  final int? conversationId;
  final String? authToken;
  final String? apiBase;
  /// Phase D — Si fourni, le bouton "Appel" passe par /api/calls/initiate
  /// (FCM ring + token serveur) au lieu du legacy LiveKit direct.
  final String? reservationReference;

  bool get _apiMode => ((peerUserId != null && peerUserId! > 0) || conversationId != null) && apiBase != null;

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> with TickerProviderStateMixin {
  final _input = TextEditingController();
  final _picker = ImagePicker();
  final _scrollCtrl = ScrollController();
  late List<ClientChatMsg> _chat;
  ClientChatMsg? _replyingTo;
  int _nextMsgId = 0;
  int? _conversationId;
  int? _myUserId;
  final _msgAnimations = <int, AnimationController>{};

  // Typing indicator
  bool _peerTyping = false;
  Timer? _typingTimer;
  Timer? _peerTypingTimer;

  // Chat-room WebSocket for typing relay
  WebSocketChannel? _chatWs;
  StreamSubscription<dynamic>? _chatWsSub;

  // Incoming call state
  bool _hasIncomingCall = false;
  String? _incomingCallRoom;
  String? _incomingCallerName;
  bool _incomingIsVideo = false;
  Timer? _incomingCallTimeout;

  @override
  void initState() {
    super.initState();
    if (widget._apiMode) {
      _chat = [];
      _bootstrapApi();
    } else {
      _chat = [
        for (final s in widget.seed)
          ClientChatMsg(id: _nextMsgId++, text: s.$1, me: s.$2),
      ];
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scrollCtrl.dispose();
    _typingTimer?.cancel();
    _peerTypingTimer?.cancel();
    _chatWsSub?.cancel();
    _chatWs?.sink.close();
    for (final c in _msgAnimations.values) {
      c.dispose();
    }
    _msgAnimations.clear();
    super.dispose();
  }

  /// Connects (or reconnects) the chat-room WebSocket once [_conversationId] is known.
  Future<void> _connectChatWs() async {
    final convId = _conversationId;
    if (convId == null || !widget._apiMode) return;
    final token = await _resolveToken();
    if (token == null || token.isEmpty) return;

    // Close any previous connection before reconnecting.
    await _chatWsSub?.cancel();
    await _chatWs?.sink.close();

    final wsBase = babifixWsBaseUrl();
    final uri = Uri.parse('$wsBase/ws/chat/$convId/');
    final ch = WebSocketChannel.connect(uri, protocols: ['BABIFIX $token']);
    _chatWs = ch;
     _chatWsSub = ch.stream.listen(
       (raw) {
         try {
           final m = jsonDecode(raw as String) as Map<String, dynamic>;
           final msgType = '${m['type'] ?? ''}';
           
           debugPrint('[ChatCall] Received WS message type=$msgType');

           if (msgType == 'typing') {
             final isTyping = m['is_typing'] as bool? ?? false;
             if (isTyping) {
               _showPeerTyping();
             } else {
               _peerTypingTimer?.cancel();
               if (mounted) setState(() => _peerTyping = false);
             }
           }

           if (msgType == 'call_offer') {
             final roomName = '${m['room_name'] ?? ''}';
             final callerName = '${m['caller_name'] ?? 'Prestataire'}';
             final isVideo = m['is_video'] as bool? ?? false;

             debugPrint('[ChatCall] INCOMING CALL: room=$roomName, caller=$callerName, isVideo=$isVideo');

             if (roomName.isNotEmpty && !_hasIncomingCall && mounted) {
               setState(() {
                 _hasIncomingCall = true;
                 _incomingCallRoom = roomName;
                 _incomingCallerName = callerName;
                 _incomingIsVideo = isVideo;
               });
               _showIncomingCallDialog();
             }
           }

           if (msgType == 'call_accept') {
             debugPrint('[ChatCall] Call accepted by peer');
           }

           if (msgType == 'call_reject') {
             debugPrint('[ChatCall] Call rejected by peer');
             if (mounted) {
               showBabifixToast(
        context,
        type: BabifixToastType.error,
        message: '${widget.name} a refusé l\'appel',
      );
             }
           }
         } catch (e) {
           debugPrint('[ChatCall] WS message error: $e');
         }
       },
      onError: (_) {},
      onDone: () {
        // Reconnect after a brief pause if the screen is still mounted.
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted && _conversationId != null) _connectChatWs();
        });
      },
    );
  }

  /// Appelé à chaque frappe — envoie un événement WebSocket "typing".
  void _onInputChanged(String text) {
    if (!widget._apiMode || _chatWs == null) return;
    _chatWs!.sink.add(jsonEncode({'type': 'typing', 'is_typing': true}));
    // Send is_typing: false after 3 s of inactivity.
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 3), () {
      _chatWs?.sink.add(jsonEncode({'type': 'typing', 'is_typing': false}));
    });
  }

  /// Called when a typing event is received from the WebSocket.
  void _showPeerTyping() {
    if (!mounted) return;
    setState(() => _peerTyping = true);
    _peerTypingTimer?.cancel();
    _peerTypingTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _peerTyping = false);
    });
  }

  Future<String?> _resolveToken() async {
    final w = widget.authToken;
    if (w != null && w.isNotEmpty) return w;
    return BabifixUserStore.getApiToken();
  }

  Future<void> _bootstrapApi() async {
    final base = widget.apiBase!;
    final token = await _resolveToken();
    if (token == null || token.isEmpty) return;
    try {
      final me = await http.get(
        Uri.parse('$base/api/auth/me'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (me.statusCode == 200) {
        final d = jsonDecode(me.body) as Map<String, dynamic>;
        _myUserId = jsonInt(d['id']);
      }
      await _reloadMessages();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _reloadMessages() async {
    final base = widget.apiBase!;
    final token = await _resolveToken();
    if (token == null || token.isEmpty) {
      debugPrint('[Chat Load] No token!');
      return;
    }
    String url;
    if (widget.conversationId != null && widget.conversationId! > 0) {
      url = '$base/api/messages?conversation_id=${widget.conversationId}';
      debugPrint('[Chat Load] GET $url');
    } else {
      final pid = widget.peerUserId!;
      url = '$base/api/messages?prestataire_id=$pid';
      debugPrint('[Chat Load] GET $url');
    }

    final res = await http.get(
      Uri.parse(url),
      headers: {'Authorization': 'Bearer $token'},
    );

    debugPrint('[Chat Load] Response status=${res.statusCode}');
    if (res.statusCode != 200) {
      debugPrint('[Chat Load] Error body=${res.body}');
      return;
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final cid = jsonInt(data['conversation_id']);
    debugPrint('[Chat Load] conversation_id=$cid');
    debugPrint('[Chat Load] Full response: $data');

    final newConvId = cid > 0 ? cid : null;
    debugPrint('[Chat Load] newConvId=$newConvId, _conversationId was=$_conversationId');

    final needsWsConnect = newConvId != null && newConvId != _conversationId;
    _conversationId = newConvId;
    if (needsWsConnect) _connectChatWs();
    final raw = (data['messages'] as List<dynamic>? ?? []);
    final snippets = <int, String>{};
    final senderById = <int, int>{};
    for (final x in raw) {
      final m = x as Map<String, dynamic>;
      final mid = jsonInt(m['id']);
      final sender = jsonInt(m['sender_id']);
      senderById[mid] = sender;
      final b = '${m['body'] ?? ''}'.trim();
      final iu = '${m['image_url'] ?? ''}';
      snippets[mid] = b.isNotEmpty
          ? (b.length > 80 ? '${b.substring(0, 80)}…' : b)
          : (iu.isNotEmpty ? '[Photo]' : '…');
    }
    final list = <ClientChatMsg>[];
    var localId = 0;
    for (final x in raw) {
      final m = x as Map<String, dynamic>;
      final sid = jsonInt(m['id']);
      final sender = jsonInt(m['sender_id']);
      final rti = m['reply_to_id'];
      final rtid = rti == null ? null : jsonInt(rti);
      final kind = (m['kind'] ?? 'USER').toString();
      final payload = m['payload_json'] is Map
          ? Map<String, dynamic>.from(m['payload_json'] as Map)
          : null;
      list.add(
        ClientChatMsg(
          id: localId++,
          serverMessageId: sid,
          text: '${m['body'] ?? ''}',
          imageUrl: (m['image_url'] as String?)?.isNotEmpty == true
              ? m['image_url'] as String
              : null,
          me: _myUserId != null && sender == _myUserId,
          replyToServerId: rtid,
          replyToText: rtid != null ? snippets[rtid] : null,
          replyToWasMe: rtid != null && _myUserId != null
              ? senderById[rtid] == _myUserId
              : null,
          kind: kind,
          payloadJson: payload,
          audioUrl: (m['audio_url'] as String?)?.isNotEmpty == true
              ? m['audio_url'] as String
              : null,
          audioDuration: jsonInt(m['audio_duration']),
        ),
      );
    }
    if (mounted) setState(() => _chat = list);
  }

  void _beginReplyTo(ClientChatMsg msg) => setState(() => _replyingTo = msg);
  void _clearReply() => setState(() => _replyingTo = null);

  void _removeMessage(ClientChatMsg msg) {
    setState(() {
      _chat.removeWhere((m) => m.id == msg.id);
      if (_replyingTo?.id == msg.id) _replyingTo = null;
    });
  }

  Future<void> _deleteMessageSmart(ClientChatMsg msg) async {
    final sid = msg.serverMessageId;
    if (sid == null || !widget._apiMode) {
      _removeMessage(msg);
      return;
    }
    final base = widget.apiBase!;
    final token = await _resolveToken();
    if (token == null || token.isEmpty) return;
    try {
      final res = await http.post(
        Uri.parse('$base/api/messages/$sid/delete'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200 && mounted) {
        await _reloadMessages();
      }
    } catch (e) {
      if (mounted) {
        showBabifixToast(
        context,
        type: BabifixToastType.info,
        message: '$e',
      );
      }
    }
  }

  void _openImageZoom(String url) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (ctx) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
          body: PhotoView(
            imageProvider: NetworkImage(url),
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 2,
          ),
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (file == null) return;
      if (widget._apiMode && _conversationId != null) {
        await _sendImageApi(file.path);
        return;
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _chat.add(
          ClientChatMsg(
            id: _nextMsgId++,
            imageBytes: bytes,
            me: true,
            replyToText: _replyingTo?.snippet,
            replyToWasMe: _replyingTo?.me,
          ),
        );
        _replyingTo = null;
      });
    } catch (e) {
      if (!mounted) return;
      showBabifixToast(
        context,
        type: BabifixToastType.error,
        message: 'Erreur : $e',
      );
    }
  }

  Future<void> _sendImageApi(String path) async {
    final base = widget.apiBase!;
    final token = await _resolveToken();
    if (token == null || token.isEmpty) return;
    final cid = _conversationId;
    if (cid == null) return;
    try {
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('$base/api/messages'),
      );
      req.headers['Authorization'] = 'Bearer $token';
      req.fields['conversation_id'] = '$cid';
      final rt = _replyingTo?.serverMessageId;
      if (rt != null) req.fields['reply_to_id'] = '$rt';
      req.files.add(await http.MultipartFile.fromPath('image', path));
      final streamed = await req.send();
      if (streamed.statusCode == 201 && mounted) {
        setState(() => _replyingTo = null);
        await _reloadMessages();
      }
    } catch (_) {}
  }

  Future<void> _sendAudioApi(String path, int durationSeconds) async {
    final base = widget.apiBase!;
    final token = await _resolveToken();
    if (token == null || token.isEmpty) return;
    final cid = _conversationId;
    if (cid == null) return;
    try {
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('$base/api/messages'),
      );
      req.headers['Authorization'] = 'Bearer $token';
      req.fields['conversation_id'] = '$cid';
      req.fields['audio_duration'] = '$durationSeconds';
      final rt = _replyingTo?.serverMessageId;
      if (rt != null) req.fields['reply_to_id'] = '$rt';
      req.files.add(await http.MultipartFile.fromPath('audio', path));
      final streamed = await req.send();
      if (streamed.statusCode == 201 && mounted) {
        setState(() => _replyingTo = null);
        await _reloadMessages();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Échec de l\'envoi de la note vocale.')),
        );
      }
    } catch (_) {}
  }

  void _showAttachmentMenu() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choisir une photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Prendre une photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _sendText() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    if (widget._apiMode) {
      _sendTextApi(text);
      return;
    }
    setState(() {
      _chat.add(
        ClientChatMsg(
          id: _nextMsgId++,
          text: text,
          me: true,
          replyToText: _replyingTo?.snippet,
          replyToWasMe: _replyingTo?.me,
        ),
      );
      _input.clear();
      _replyingTo = null;
    });
  }

   Future<void> _sendTextApi(String text) async {
    final base = widget.apiBase!;
    final token = await _resolveToken();
    final cid = _conversationId;
    final pid = widget.peerUserId;

    debugPrint('[Chat Send] _apiMode=${widget._apiMode}');
    debugPrint('[Chat Send] token exists=${token != null && token!.isNotEmpty}');
    debugPrint('[Chat Send] _conversationId=$cid');
    debugPrint('[Chat Send] peerUserId=$pid');

    if (token == null || token.isEmpty) {
      debugPrint('[Chat Send] No token!');
      if (mounted) {
        showBabifixToast(
        context,
        type: BabifixToastType.info,
        message: 'Non connecté',
      );
      }
      return;
    }

    if (cid == null) {
      debugPrint('[Chat Send] No conversation_id - trying to create one or get existing');
      debugPrint('[Chat Send] Base: $base, pid: $pid');

      if (mounted) {
        showBabifixToast(
        context,
        type: BabifixToastType.info,
        message: 'Conversation pas prête (cid=null, pid=$pid)',
      );
      }
      return;
    }

    try {
      debugPrint('[Chat Send] POST $base/api/messages, conversation_id=$cid, body=$text');
      final res = await http.post(
        Uri.parse('$base/api/messages'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'conversation_id': cid,
          'body': text,
          if (_replyingTo?.serverMessageId != null)
            'reply_to_id': _replyingTo!.serverMessageId,
        }),
      );

      debugPrint('[Chat Send] Response status=${res.statusCode}');
      debugPrint('[Chat Send] Response body=${res.body}');

      if (res.statusCode == 201 && mounted) {
        _input.clear();
        setState(() => _replyingTo = null);
        await _reloadMessages();
      } else if (res.statusCode == 403 &&
          res.body.contains('prestation_terminee') &&
          mounted) {
        // Messagerie clôturée après la prestation : rendu soigné, pas une erreur.
        _showChatClosedDialog(apiErrorMessage(res.body));
      } else if (mounted) {
        showBabifixToast(
        context,
        type: BabifixToastType.error,
        message: apiErrorMessage(res.body) ??
            userFriendlyError(null, res.statusCode),
      );
      }
    } catch (e) {
      debugPrint('[Chat Send] EXCEPTION: $e');
      if (mounted) {
        showBabifixToast(
        context,
        type: BabifixToastType.error,
        message: userFriendlyError(e),
      );
      }
    }
  }

  /// Dialog soigné affiché quand la messagerie est clôturée (prestation
  /// terminée) — bien plus agréable qu'un bandeau d'erreur rouge.
  void _showChatClosedDialog(String? detail) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: const BoxDecoration(
                  color: Color(0x1A4CC9F0),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.verified_rounded,
                    size: 42, color: Color(0xFF0EA5E9)),
              ),
              const SizedBox(height: 16),
              const Text(
                'Prestation terminée',
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0B1B34)),
              ),
              const SizedBox(height: 10),
              Text(
                detail ??
                    'La prestation est terminée : la messagerie est clôturée. '
                        'En cas de souci, utilisez « Signaler un problème ».',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13.5, height: 1.45, color: Color(0xFF475569)),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0EA5E9),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13)),
                  ),
                  child: const Text('Compris',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _sendCallSignal(String type, {String? roomName, bool? isVideo, String? callerName}) {
    if (_chatWs == null) {
      debugPrint('[ChatCall] _chatWs is null, cannot send signal');
      return;
    }
    final msg = <String, dynamic>{
      'type': type,
      if (roomName != null) 'room_name': roomName,
      if (isVideo != null) 'is_video': isVideo,
      if (callerName != null) 'caller_name': callerName,
    };
    debugPrint('[ChatCall] Sending: $msg');
    _chatWs!.sink.add(jsonEncode(msg));
  }

  Future<void> _startOutgoingCall({required bool isVideo}) async {
    final convId = _conversationId;
    if (convId == null || convId <= 0) {
      showBabifixToast(
        context,
        type: BabifixToastType.info,
        message: 'Conversation non initialisée',
      );
      return;
    }

    // Phase D — Si on connaît la réservation, on passe par le backend
    // pour avoir un FCM ring + token serveur. Sinon, fallback legacy.
    if (widget.reservationReference != null &&
        widget.reservationReference!.isNotEmpty) {
      await CallService.startOutgoing(
        context: context,
        reservationReference: widget.reservationReference!,
        targetName: widget.name,
        isVideo: isVideo,
      );
      return;
    }

    final roomName = 'chat_conv_$convId';
    final myName = BabifixLiveKitService.currentUserName ?? 'Client';

    _sendCallSignal('call_offer',
        roomName: roomName, isVideo: isVideo, callerName: myName);

    final peerId = widget.peerUserId;
    final targetUserID = peerId != null ? 'prestataire_$peerId' : 'unknown';

    if (!BabifixLiveKitService.isInitialized) {
      showBabifixToast(
        context,
        type: BabifixToastType.info,
        message: 'Service d\'appel non initialisé (userId=${BabifixLiveKitService.currentUserId})',
      );
      return;
    }

    // Token généré côté backend (jamais en local).
    if (isVideo) {
      await BabifixLiveKitService.startVideoCall(
        context: context,
        conversationId: convId,
        targetUserID: targetUserID,
        targetUserName: widget.name,
      );
    } else {
      await BabifixLiveKitService.startVoiceCall(
        context: context,
        conversationId: convId,
        targetUserID: targetUserID,
        targetUserName: widget.name,
      );
    }
  }

  void _acceptIncomingCall() {
    final roomName = _incomingCallRoom;
    if (roomName == null) return;

    _sendCallSignal('call_accept');
    _clearIncomingCall();

    final convId = widget.conversationId;
    if (convId == null) return;

    final peerId = widget.peerUserId;
    final targetUserID = peerId != null ? 'prestataire_$peerId' : 'unknown';
    final isVideo = _incomingIsVideo;

    // Token généré côté backend (jamais en local).
    if (isVideo) {
      BabifixLiveKitService.startVideoCall(
        context: context,
        conversationId: convId,
        targetUserID: targetUserID,
        targetUserName: _incomingCallerName ?? 'Prestataire',
      );
    } else {
      BabifixLiveKitService.startVoiceCall(
        context: context,
        conversationId: convId,
        targetUserID: targetUserID,
        targetUserName: _incomingCallerName ?? 'Prestataire',
      );
    }
  }

  void _rejectIncomingCall() {
    _sendCallSignal('call_reject');
    _clearIncomingCall();
  }

  void _clearIncomingCall() {
    _incomingCallTimeout?.cancel();
    _incomingCallTimeout = null;
    setState(() {
      _hasIncomingCall = false;
      _incomingCallRoom = null;
      _incomingCallerName = null;
      _incomingIsVideo = false;
    });
    Navigator.of(context).pop();
  }

  void _showIncomingCallDialog() {
    if (!mounted) return;

    _incomingCallTimeout?.cancel();
    _incomingCallTimeout = Timer(const Duration(seconds: 30), () {
      if (_hasIncomingCall) _rejectIncomingCall();
    });

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Center(
          child: Column(
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: BabifixDesign.ciOrange,
                child: Text(
                  _incomingCallerName?.isNotEmpty == true
                      ? _incomingCallerName![0].toUpperCase()
                      : '?',
                  style: const TextStyle(fontSize: 32, color: Colors.white),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _incomingIsVideo ? 'Appel vidéo entrant' : 'Appel audio entrant',
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 4),
              Text(
                _incomingCallerName ?? 'Prestataire',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _rejectIncomingCall,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: BabifixDesign.error,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.call_end, size: 24),
                        SizedBox(height: 2),
                        Text('Refuser', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _acceptIncomingCall,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: BabifixDesign.success,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(_incomingIsVideo ? Icons.videocam : Icons.call, size: 24),
                        SizedBox(height: 2),
                        const Text('Accepter', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone),
            tooltip: 'Appel audio',
            color: Theme.of(context).primaryColor,
            onPressed: () => _startOutgoingCall(isVideo: false),
          ),
          IconButton(
            icon: const Icon(Icons.videocam),
            tooltip: 'Appel vidéo',
            color: Theme.of(context).primaryColor,
            onPressed: () => _startOutgoingCall(isVideo: true),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: ListView.builder(
                controller: _scrollCtrl,
                itemCount: _chat.length + (_peerTyping ? 1 : 0),
                itemBuilder: (context, i) {
                  // Indicateur "en train d'écrire" en dernière position
                  if (_peerTyping && i == _chat.length) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 8,
                        ),
                        child: _TypingIndicator(peerName: widget.name),
                      ),
                    );
                  }
                  final msg = _chat[i];
                  // Phase C — Messages spéciaux (DEVIS_CARD / SYSTEM)
                  if (msg.kind == 'DEVIS_CARD' && msg.payloadJson != null) {
                    final reservationRef =
                        (msg.payloadJson!['reservation_reference'] ?? '')
                            .toString();
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: InkWell(
                        onTap: reservationRef.isEmpty
                            ? null
                            : () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => DevisKanbanScreen(
                                      reservationReference: reservationRef,
                                    ),
                                  ),
                                ),
                        child: DevisCardWidget.fromPayload(
                          msg.payloadJson!,
                          compact: true,
                        ),
                      ),
                    );
                  }
                  if (msg.kind == 'SYSTEM') {
                    final body = msg.text ?? '';
                    final eventType =
                        (msg.payloadJson?['event_type'] ?? '').toString();
                    return SystemEventWidget(
                      body: body,
                      eventType: eventType,
                    );
                  }
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.5),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                      parent: _msgAnimations.putIfAbsent(msg.id, () {
                        return AnimationController(
                          duration: const Duration(milliseconds: 300),
                          vsync: this,
                        );
                      }),
                      curve: Curves.easeOutCubic,
                    )),
                    child: Align(
                      alignment: msg.me
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: ChatBubble(
                        message: msg,
                        peerName: widget.name,
                        onReply: () => _beginReplyTo(msg),
                        onDelete: msg.me ? () => _deleteMessageSmart(msg) : null,
                        onImageTap:
                            msg.imageUrl != null && msg.imageUrl!.isNotEmpty
                            ? () => _openImageZoom(msg.imageUrl!)
                            : null,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          if (_replyingTo != null)
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 40,
                      decoration: BoxDecoration(
                        color: BabifixDesign.cyan,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Réponse à ${_replyingTo!.me ? 'vous' : widget.name}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            _replyingTo!.snippet,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _clearReply,
                      tooltip: 'Annuler la réponse',
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            ),
          // Réponses rapides : tap = remplit le message (visible si champ vide).
          if (_input.text.trim().isEmpty)
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (final q in const [
                    'Bonjour 👋',
                    'Vous êtes disponible ?',
                    'À quelle heure pouvez-vous venir ?',
                    'C\'est noté',
                    'Merci !',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        label: Text(q, style: const TextStyle(fontSize: 12.5)),
                        backgroundColor:
                            BabifixDesign.cyan.withValues(alpha: 0.10),
                        side: BorderSide(
                            color: BabifixDesign.cyan.withValues(alpha: 0.3)),
                        onPressed: () {
                          _input.text = q;
                          _input.selection = TextSelection.fromPosition(
                              TextPosition(offset: q.length));
                          _onInputChanged(q);
                          setState(() {});
                        },
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: _showAttachmentMenu,
                  tooltip: 'Joindre un fichier',
                  icon: const Icon(Icons.add_circle_outline),
                  color: BabifixDesign.iconOnDark,
                ),
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 5,
                    onChanged: _onInputChanged,
                    decoration: const InputDecoration(
                      hintText: 'Votre message...',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    onSubmitted: (_) => _sendText(),
                  ),
                ),
                BabifixVoiceRecorderButton(
                  color: BabifixDesign.cyan,
                  onRecorded: (path, dur) => _sendAudioApi(path, dur),
                ),
                IconButton(
                  onPressed: _sendText,
                  tooltip: 'Envoyer',
                  icon: const Icon(Icons.send),
                  color: BabifixDesign.iconOnDark,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bubble Widget ─────────────────────────────────────────────────────────────

class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.message,
    required this.peerName,
    required this.onReply,
    this.onDelete,
    this.onImageTap,
  });

  final ClientChatMsg message;
  final String peerName;
  final VoidCallback onReply;
  final VoidCallback? onDelete;
  final VoidCallback? onImageTap;

  void _showMessageMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: const Text('Répondre'),
              onTap: () {
                Navigator.pop(ctx);
                onReply();
              },
            ),
            if (onDelete != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text(
                  'Supprimer',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  onDelete!();
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = message.me;
    final w = MediaQuery.sizeOf(context).width;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isLight = theme.brightness == Brightness.light;

    Widget bubble = Container(
      constraints: BoxConstraints(maxWidth: w * 0.72),
      padding: EdgeInsets.fromLTRB(
        14,
        message.replyToText != null ? 8 : 12,
        14,
        12,
      ),
      decoration: BoxDecoration(
        gradient: me
            ? LinearGradient(
                colors: [BabifixDesign.cyan, const Color(0xFF4CC9F0)],
              )
            : null,
        color: me ? null : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(me ? 20 : 4),
          bottomRight: Radius.circular(me ? 4 : 20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.replyToText != null)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border(
                  left: BorderSide(color: BabifixDesign.cyan, width: 3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.replyToWasMe == true ? 'Vous' : peerName,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      color: me ? Colors.white : BabifixDesign.cyan,
                    ),
                  ),
                  Text(
                    message.replyToText!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: me
                          ? Colors.white.withValues(alpha: 0.85)
                          : cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          if (message.imageUrl != null && message.imageUrl!.isNotEmpty)
            Semantics(
              label: 'Photo – appuyez pour agrandir',
              button: true,
              child: InkWell(
                onTap: onImageTap,
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: 48,
                    minWidth: 48,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      message.imageUrl!,
                      width: math.min(220, w - 20),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
              ),
            ),
          if (message.imageBytes != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                message.imageBytes!,
                width: math.min(220, w - 20),
                fit: BoxFit.cover,
              ),
            ),
          if (message.hasAudio)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: BabifixVoiceNotePlayer(
                url: message.audioUrl!,
                durationSeconds: message.audioDuration,
                isMe: message.me,
              ),
            ),
          if (message.text != null && message.text!.trim().isNotEmpty) ...[
            if (message.imageUrl != null || message.imageBytes != null)
              const SizedBox(height: 8),
            Text(
              message.text!,
              style: TextStyle(color: me ? BabifixDesign.navy : cs.onSurface),
            ),
          ],
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: ValueKey<int>(message.id),
        direction: DismissDirection.startToEnd,
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) onReply();
          return false;
        },
        background: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(
            color: Colors.blueGrey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.reply_rounded, color: Colors.blueGrey.shade800),
        ),
        child: GestureDetector(
          onLongPress: () => _showMessageMenu(context),
          behavior: HitTestBehavior.opaque,
          child: Column(
            crossAxisAlignment: me
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [bubble],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget "en train d'écrire" — 3 points animés
// ─────────────────────────────────────────────────────────────────────────────
class _TypingIndicator extends StatefulWidget {
  final String peerName;
  const _TypingIndicator({required this.peerName});

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${widget.peerName} écrit',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(width: 6),
          ...List.generate(3, (i) {
            return CustomAnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) {
                final phase = (_ctrl.value * 3 - i).clamp(0.0, 1.0);
                final opacity = (phase < 0.5) ? phase * 2 : (1.0 - phase) * 2;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Opacity(
                    opacity: opacity.clamp(0.2, 1.0),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: BabifixDesign.cyan,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                );
              },
            );
          }),
        ],
      ),
    );
  }
}
