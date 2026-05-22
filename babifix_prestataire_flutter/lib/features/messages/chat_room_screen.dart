import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../json_utils.dart';
import '../../services/livekit_call_service.dart';
import '../../services/livekit_call_screen.dart';
import '../../shared/services/haptics_service.dart';
import '../../shared/widgets/babifix_phase_widgets.dart';
import '../../shared/widgets/babifix_snackbar.dart';

class PrestChatRoomPage extends StatefulWidget {
  const PrestChatRoomPage({
    super.key,
    required this.name,
    required this.clientUserId,
    this.conversationId,
    this.authToken,
    required this.apiBase,
    this.seed = const [],
  });

  final String name;
  final int clientUserId;
  final int? conversationId;
  final String? authToken;
  final String apiBase;
  final List<(String, bool)> seed;

  bool get apiMode =>
      (clientUserId > 0 || conversationId != null) && authToken != null && authToken!.isNotEmpty;

  @override
  State<PrestChatRoomPage> createState() => _PrestChatRoomPageState();
}

class PrestApiChatMsg {
  PrestApiChatMsg({
    required this.id,
    this.text,
    this.imageBytes,
    this.imageUrl,
    required this.me,
    this.replyToText,
    this.replyToWasMe,
    this.serverMessageId,
    this.replyToServerId,
    this.kind = 'USER',
    this.payloadJson,
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
  final String kind;
  final Map<String, dynamic>? payloadJson;

  String get snippet {
    if (text != null && text!.trim().isNotEmpty) {
      final t = text!.trim();
      return t.length > 80 ? '${t.substring(0, 80)}\u2026' : t;
    }
    return '[Photo]';
  }
}

class _PrestChatRoomPageState extends State<PrestChatRoomPage> {
  final _input = TextEditingController();
  final _picker = ImagePicker();
  late List<PrestApiChatMsg> _chat;
  PrestApiChatMsg? _replyingTo;
  int _nextMsgId = 0;
  int? _conversationId;
  int? _myUserId;
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
  Timer? _ringingVibrationTimer;

  @override
  void initState() {
    super.initState();
    if (widget.apiMode) {
      _chat = [];
      _bootstrapApi();
    } else {
      _chat = [
        for (final s in widget.seed)
          PrestApiChatMsg(
            id: _nextMsgId++,
            text: s.$1,
            me: s.$2,
          ),
      ];
    }
  }

  Future<void> _bootstrapApi() async {
    final base = widget.apiBase;
    final token = widget.authToken!;
    try {
      final me = await http.get(Uri.parse('$base/api/auth/me'), headers: {'Authorization': 'Bearer $token'});
      if (me.statusCode == 200) {
        final d = jsonDecode(me.body) as Map<String, dynamic>;
        _myUserId = jsonInt(d['id']);
      }
      await _reloadMessages();
    } catch (_) {
      if (mounted) {
        showBabifixToast(
        context,
        type: BabifixToastType.error,
        message: 'Erreur chargement messages',
      );
      }
    }
    if (mounted) setState(() {});
  }

   Future<void> _reloadMessages() async {
    final base = widget.apiBase;
    final token = widget.authToken!;
    String url;
    if (widget.conversationId != null && widget.conversationId! > 0) {
      url = '$base/api/messages?conversation_id=${widget.conversationId}';
      debugPrint('[Chat Load PRESTA] GET $url');
    } else {
      final cid = widget.clientUserId;
      url = '$base/api/messages?client_id=$cid';
      debugPrint('[Chat Load PRESTA] GET $url');
    }

    final res = await http.get(
      Uri.parse(url),
      headers: {'Authorization': 'Bearer $token'},
    );

    debugPrint('[Chat Load PRESTA] Response status=${res.statusCode}');
    if (res.statusCode != 200) {
      debugPrint('[Chat Load PRESTA] Error body=${res.body}');
      return;
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final convId = jsonInt(data['conversation_id']);
    debugPrint('[Chat Load PRESTA] conversation_id=$convId');
    debugPrint('[Chat Load PRESTA] Full response: $data');

    final newConvId = convId > 0 ? convId : null;
    debugPrint('[Chat Load PRESTA] newConvId=$newConvId, _conversationId was=$_conversationId');

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
      snippets[mid] = b.isNotEmpty ? (b.length > 80 ? '${b.substring(0, 80)}\u2026' : b) : (iu.isNotEmpty ? '[Photo]' : '\u2026');
    }
    final list = <PrestApiChatMsg>[];
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
        PrestApiChatMsg(
          id: localId++,
          serverMessageId: sid,
          text: '${m['body'] ?? ''}',
          imageUrl: (m['image_url'] as String?)?.isNotEmpty == true ? m['image_url'] as String : null,
          me: _myUserId != null && sender == _myUserId,
          replyToServerId: rtid,
          replyToText: rtid != null ? snippets[rtid] : null,
          replyToWasMe: rtid != null && _myUserId != null ? senderById[rtid] == _myUserId : null,
          kind: kind,
          payloadJson: payload,
        ),
      );
    }
    if (mounted) setState(() => _chat = list);
  }

  @override
  void dispose() {
    _input.dispose();
    _typingTimer?.cancel();
    _peerTypingTimer?.cancel();
    _chatWsSub?.cancel();
    _chatWs?.sink.close();
    super.dispose();
  }

  Future<void> _connectChatWs() async {
    final convId = _conversationId;
    if (convId == null || !widget.apiMode) return;
    final token = widget.authToken;
    if (token == null || token.isEmpty) return;

    await _chatWsSub?.cancel();
    await _chatWs?.sink.close();

    final wsBase = babifixWsBaseUrl();
    final uri = Uri.parse(
      '$wsBase/ws/chat/$convId/?token=${Uri.encodeQueryComponent(token)}',
    );
    final ch = WebSocketChannel.connect(uri);
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
               if (mounted) {
                 setState(() => _peerTyping = true);
                 _peerTypingTimer?.cancel();
                 _peerTypingTimer = Timer(const Duration(seconds: 4), () {
                   if (mounted) setState(() => _peerTyping = false);
                 });
               }
             } else {
               _peerTypingTimer?.cancel();
               if (mounted) setState(() => _peerTyping = false);
             }
           }

            if (msgType == 'call_offer') {
              final roomName = '${m['room_name'] ?? ''}';
              final callerName = '${m['caller_name'] ?? 'Client'}';
              final isVideo = m['is_video'] as bool? ?? false;

              debugPrint('[ChatCall] INCOMING CALL: room=$roomName, caller=$callerName, isVideo=$isVideo');
              debugPrint('[ChatCall] _hasIncomingCall=$_hasIncomingCall, mounted=$mounted');

              if (roomName.isNotEmpty && !_hasIncomingCall && mounted) {
                debugPrint('[ChatCall] Showing incoming call dialog...');

                setState(() {
                  _hasIncomingCall = true;
                  _incomingCallRoom = roomName;
                  _incomingCallerName = callerName;
                  _incomingIsVideo = isVideo;
                });

                HapticsService.heavy();
                HapticFeedback.vibrate();

                _ringingVibrationTimer?.cancel();
                _ringingVibrationTimer = Timer.periodic(const Duration(seconds: 2), (_) {
                  HapticFeedback.vibrate();
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
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted && _conversationId != null) _connectChatWs();
        });
      },
    );
  }

  void _onInputChanged(String text) {
    if (!widget.apiMode || _chatWs == null) return;
    _chatWs!.sink.add(jsonEncode({'type': 'typing', 'is_typing': true}));
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 3), () {
      _chatWs?.sink.add(jsonEncode({'type': 'typing', 'is_typing': false}));
    });
  }

  void _beginReplyTo(PrestApiChatMsg msg) {
    setState(() => _replyingTo = msg);
  }

  void _clearReply() {
    setState(() => _replyingTo = null);
  }

  void _removeMessage(PrestApiChatMsg msg) {
    setState(() {
      _chat.removeWhere((m) => m.id == msg.id);
      if (_replyingTo?.id == msg.id) _replyingTo = null;
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final file = await _picker.pickImage(source: source, maxWidth: 1600, imageQuality: 85);
      if (file == null) return;
      if (widget.apiMode && _conversationId != null) {
        await _sendImageApi(file.path);
        return;
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _chat.add(
          PrestApiChatMsg(
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
        message: 'Acc\u00e8s refus\u00e9 ou erreur : $e',
      );
    }
  }

  Future<void> _sendImageApi(String path) async {
    final base = widget.apiBase;
    final token = widget.authToken!;
    final cid = _conversationId;
    if (cid == null) return;
    try {
      final req = http.MultipartRequest('POST', Uri.parse('$base/api/messages'));
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
    } catch (e) {
      if (mounted) {
        showBabifixToast(
        context,
        type: BabifixToastType.info,
        message: 'Envoi photo: $e',
      );
      }
    }
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
              leading: const Icon(Icons.photo_library_outlined, color: Color(0xFF0B1B34)),
              title: const Text('Choisir une photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: Color(0xFF0B1B34)),
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
    if (widget.apiMode) {
      _sendTextApi(text);
      return;
    }
    setState(() {
      _chat.add(
        PrestApiChatMsg(
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
    final base = widget.apiBase;
    final token = widget.authToken!;
    final cid = _conversationId;
    final clientId = widget.clientUserId;

    debugPrint('[Chat Send PRESTA] _conversationId=$cid');
    debugPrint('[Chat Send PRESTA] clientUserId=$clientId');

    if (cid == null) {
      debugPrint('[Chat Send PRESTA] No conversation_id!');
      if (mounted) {
        showBabifixToast(
        context,
        type: BabifixToastType.info,
        message: 'Conversation pas prête (cid=null, clientId=$clientId)',
      );
      }
      return;
    }

    try {
      debugPrint('[Chat Send PRESTA] POST $base/api/messages, conversation_id=$cid');
      final res = await http.post(
        Uri.parse('$base/api/messages'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'conversation_id': cid,
          'body': text,
          if (_replyingTo?.serverMessageId != null) 'reply_to_id': _replyingTo!.serverMessageId,
        }),
      );

      debugPrint('[Chat Send PRESTA] Response status=${res.statusCode}');
      debugPrint('[Chat Send PRESTA] Response body=${res.body}');

      if (res.statusCode == 201 && mounted) {
        _input.clear();
        setState(() => _replyingTo = null);
        await _reloadMessages();
      } else if (mounted) {
        showBabifixToast(
        context,
        type: BabifixToastType.error,
        message: 'Erreur envoi: HTTP ${res.statusCode}',
      );
      }
    } catch (e) {
      debugPrint('[Chat Send PRESTA] EXCEPTION: $e');
      if (mounted) {
        showBabifixToast(
        context,
        type: BabifixToastType.error,
        message: 'Erreur: $e',
      );
      }
    }
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

    final roomName = 'chat_conv_$convId';
    final myName = BabifixLiveKitService.currentUserName ?? 'Prestataire';

    _sendCallSignal('call_offer',
        roomName: roomName, isVideo: isVideo, callerName: myName);

    final targetUserID = 'client_${widget.clientUserId}';

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

    final targetUserID = 'client_${widget.clientUserId}';
    final isVideo = _incomingIsVideo;

    if (isVideo) {
      BabifixLiveKitService.startVideoCall(
        context: context,
        conversationId: convId,
        targetUserID: targetUserID,
        targetUserName: _incomingCallerName ?? 'Client',
      );
    } else {
      BabifixLiveKitService.startVoiceCall(
        context: context,
        conversationId: convId,
        targetUserID: targetUserID,
        targetUserName: _incomingCallerName ?? 'Client',
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
    _ringingVibrationTimer?.cancel();
    _ringingVibrationTimer = null;
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
                _incomingCallerName ?? 'Client',
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
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back),
        ),
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
                itemCount: _chat.length + (_peerTyping ? 1 : 0),
                itemBuilder: (context, i) {
                  if (i == _chat.length && _peerTyping) {
                    return const Align(
                      alignment: Alignment.centerLeft,
                      child: _TypingIndicator(),
                    );
                  }
                  final msg = _chat[i];
                  // Phase C — DEVIS_CARD / SYSTEM
                  if (msg.kind == 'DEVIS_CARD' && msg.payloadJson != null) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: DevisCardWidget.fromPayload(
                        msg.payloadJson!,
                        compact: true,
                      ),
                    );
                  }
                  if (msg.kind == 'SYSTEM') {
                    return SystemEventWidget(
                      body: msg.text ?? '',
                      eventType:
                          (msg.payloadJson?['event_type'] ?? '').toString(),
                    );
                  }
                  return Align(
                    alignment: msg.me ? Alignment.centerRight : Alignment.centerLeft,
                    child: _PrestApiChatBubble(
                      message: msg,
                      peerName: widget.name,
                      onReply: () => _beginReplyTo(msg),
                      onDelete: msg.me ? () => _removeMessage(msg) : null,
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
                        color: const Color(0xFF4CC9F0),
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
                            'R\u00e9ponse \u00e0 ${_replyingTo!.me ? 'vous' : widget.name}',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                          ),
                          Text(
                            _replyingTo!.snippet,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: Colors.blueGrey.shade800),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _clearReply,
                      icon: const Icon(Icons.close),
                      tooltip: 'Annuler',
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: _showAttachmentMenu,
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: 'Photo ou cam\u00e9ra',
                  color: const Color(0xFF0B1B34),
                ),
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      hintText: 'Votre message...',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: _onInputChanged,
                    onSubmitted: (_) => _sendText(),
                  ),
                ),
                IconButton(
                  onPressed: _sendText,
                  icon: const Icon(Icons.send),
                  color: const Color(0xFF0B1B34),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PrestApiChatBubble extends StatelessWidget {
  const _PrestApiChatBubble({
    required this.message,
    required this.peerName,
    required this.onReply,
    this.onDelete,
  });

  final PrestApiChatMsg message;
  final String peerName;
  final VoidCallback onReply;
  final VoidCallback? onDelete;

  void _showMessageMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply_rounded, color: Color(0xFF0B1B34)),
              title: const Text('R\u00e9pondre'),
              onTap: () {
                Navigator.pop(ctx);
                onReply();
              },
            ),
            if (onDelete != null)
              ListTile(
                leading: Icon(Icons.delete_outline_rounded, color: Colors.red.shade700),
                title: Text('Supprimer', style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w600)),
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
    final w = MediaQuery.sizeOf(context).width * 0.82;
    final bubble = Container(
      constraints: BoxConstraints(maxWidth: w),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: me ? const Color(0xFF4CC9F0) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: me ? null : Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: me
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.replyToText != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: me ? const Color(0x330B1B34) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
                border: const Border(
                  left: BorderSide(color: Color(0xFF4CC9F0), width: 3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.replyToWasMe == true ? 'Vous' : peerName,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      color: me ? const Color(0xFF0B1B34) : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message.replyToText!,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: me ? const Color(0xFF0B1B34) : const Color(0xFF334155),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (message.imageUrl != null && message.imageUrl!.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                message.imageUrl!,
                width: math.min(220, w - 20),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image_outlined),
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
          if (((message.imageUrl != null && message.imageUrl!.isNotEmpty) || (message.imageBytes != null)) &&
              message.text != null &&
              message.text!.trim().isNotEmpty)
            const SizedBox(height: 8),
          if (message.text != null && message.text!.trim().isNotEmpty)
            Text(
              message.text!,
              style: TextStyle(
                color: me ? const Color(0xFF0B1B34) : const Color(0xFF111827),
              ),
            ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: ValueKey<int>(message.id),
        direction: DismissDirection.startToEnd,
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            onReply();
          }
          return false;
        },
        background: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 12, right: 8),
          decoration: BoxDecoration(
            color: Colors.blueGrey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.reply_rounded, color: Colors.blueGrey.shade800, size: 26),
              const SizedBox(width: 6),
              Text(
                'R\u00e9pondre',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.blueGrey.shade800,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        child: GestureDetector(
          onLongPress: () => _showMessageMenu(context),
          behavior: HitTestBehavior.opaque,
          child: Column(
            crossAxisAlignment: me ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [bubble],
          ),
        ),
      ),
    );
  }
}

// ── Typing indicator ──────────────────────────────────────────────────────────

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
        ),
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final delay = i / 3;
              final t = (_ctrl.value + delay) % 1.0;
              final opacity = (math.sin(t * math.pi)).clamp(0.3, 1.0);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Opacity(
                  opacity: opacity,
                  child: const CircleAvatar(
                    radius: 4,
                    backgroundColor: Colors.grey,
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
