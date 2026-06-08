import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../babifix_design_system.dart';
import '../shared/widgets/babifix_snackbar.dart';

class LiveKitCallScreen extends StatefulWidget {
  final String liveKitUrl;
  final String token;
  final String roomName;
  final String targetUserID;
  final String targetUserName;
  final bool isVideoCall;

  const LiveKitCallScreen({
    super.key,
    required this.liveKitUrl,
    required this.token,
    required this.roomName,
    required this.targetUserID,
    required this.targetUserName,
    this.isVideoCall = true,
  });

  @override
  State<LiveKitCallScreen> createState() => _LiveKitCallScreenState();
}

class _LiveKitCallScreenState extends State<LiveKitCallScreen> {
  Room? _room;
  bool _isConnected = false;
  bool _isMicEnabled = true;
  bool _isCameraEnabled = true;
  String _connectionStatus = 'Connexion...';
  final List<EventsListener> _listeners = [];
  RemoteParticipant? _remoteParticipant;

  @override
  void initState() {
    super.initState();
    _connectToRoom();
  }

  @override
  void dispose() {
    for (final listener in _listeners) {
      listener.dispose();
    }
    _disconnectFromRoom();
    super.dispose();
  }

  Future<void> _connectToRoom() async {
    try {
      debugPrint('[LiveKit] Creating Room...');
      _room = Room();

      debugPrint('[LiveKit] Creating room listener...');
      final roomListener = _room!.createListener();
      _listeners.add(roomListener);

      roomListener
        ..on<RoomConnectedEvent>((event) {
          debugPrint('[LiveKit] Room connected!');
          setState(() {
            _isConnected = true;
            _connectionStatus = 'Connecté';
          });
          _checkExistingParticipants();
        })
        ..on<RoomDisconnectedEvent>((event) {
          debugPrint('[LiveKit] Room disconnected: ${event.reason}');
          if (mounted) Navigator.of(context).pop();
        })
        ..on<ParticipantConnectedEvent>((event) {
          debugPrint('[LiveKit] Participant connected: ${event.participant.identity}');
          setState(() {
            _remoteParticipant = event.participant;
          });
          _setupRemoteParticipantListener(event.participant);
        })
        ..on<ParticipantDisconnectedEvent>((event) {
          debugPrint('[LiveKit] Participant disconnected: ${event.participant.identity}');
          setState(() {
            if (_remoteParticipant?.identity == event.participant.identity) {
              _remoteParticipant = null;
            }
          });
        })
        ..on<TrackPublishedEvent>((event) {
          debugPrint('[LiveKit] Track published: ${event.publication} by ${event.participant.identity}');
          setState(() {});
        })
        ..on<TrackSubscribedEvent>((event) {
          debugPrint('[LiveKit] Track subscribed: ${event.track}');
          setState(() {});
        });

      debugPrint('[LiveKit] Connecting to: ${widget.liveKitUrl}');
      debugPrint('[LiveKit] Room: ${widget.roomName}');

      await _room!.connect(
        widget.liveKitUrl,
        widget.token,
      );

      debugPrint('[LiveKit] Connect call returned');

      if (_room!.localParticipant != null) {
        if (widget.isVideoCall) {
          try {
            debugPrint('[LiveKit] Enabling camera...');
            await _room!.localParticipant!.setCameraEnabled(true);
            setState(() => _isCameraEnabled = true);
          } catch (e) {
            debugPrint('[LiveKit] Could not enable camera: $e');
          }
        }

        try {
          debugPrint('[LiveKit] Enabling microphone...');
          await _room!.localParticipant!.setMicrophoneEnabled(true);
          setState(() => _isMicEnabled = true);
        } catch (e) {
          debugPrint('[LiveKit] Could not enable microphone: $e');
        }
      }
    } catch (e, stackTrace) {
      debugPrint('[LiveKit] Connection error: $e');
      debugPrint('[LiveKit] Stack trace: $stackTrace');
      if (mounted) {
        showBabifixToast(
        context,
        type: BabifixToastType.error,
        message: 'Erreur de connexion: $e',
        duration: const Duration(seconds: 5),
      );
      }
    }
  }

  void _checkExistingParticipants() {
    if (_room == null) return;
    final remoteParticipants = _room!.remoteParticipants.values.toList();
    debugPrint('[LiveKit] Existing remote participants: ${remoteParticipants.length}');
    if (remoteParticipants.isNotEmpty) {
      setState(() {
        _remoteParticipant = remoteParticipants.first;
      });
      _setupRemoteParticipantListener(remoteParticipants.first);
    }
  }

  void _setupRemoteParticipantListener(RemoteParticipant participant) {
    try {
      final listener = participant.createListener();
      _listeners.add(listener);
      listener
        ..on<TrackPublishedEvent>((event) {
          debugPrint('[LiveKit] Remote track published: ${event.publication}');
          setState(() {});
        })
        ..on<TrackSubscribedEvent>((event) {
          debugPrint('[LiveKit] Remote track subscribed: ${event.track}');
          setState(() {});
        });
    } catch (e) {
      debugPrint('[LiveKit] Could not setup participant listener: $e');
    }
  }

  Future<void> _disconnectFromRoom() async {
    try {
      await _room?.disconnect();
      debugPrint('[LiveKit] Disconnected');
    } catch (e) {
      debugPrint('[LiveKit] Disconnect error: $e');
    }
  }

  void _toggleMic() {
    final newState = !_isMicEnabled;
    _room?.localParticipant?.setMicrophoneEnabled(newState);
    setState(() => _isMicEnabled = newState);
  }

  void _toggleCamera() {
    final newState = !_isCameraEnabled;
    _room?.localParticipant?.setCameraEnabled(newState);
    setState(() => _isCameraEnabled = newState);
  }

  void _endCall() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BabifixDesign.navy,
      body: SafeArea(
        child: Stack(
          children: [
            _buildRemoteVideo(),
            _buildLocalVideo(),
            _buildTopBar(),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 20,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              _isConnected ? Icons.check_circle : Icons.hourglass_empty,
              color: _isConnected ? BabifixDesign.success : Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isConnected ? 'Appel en cours' : _connectionStatus,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    widget.targetUserName,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Piste vidéo caméra du correspondant distant (null si pas de vidéo).
  VideoTrack? get _remoteVideoTrack {
    final p = _remoteParticipant;
    if (p == null) return null;
    final pub = p.getTrackPublicationBySource(TrackSource.camera);
    if (pub?.subscribed != true) return null;
    return pub?.track as VideoTrack?;
  }

  /// Piste vidéo caméra locale (null si caméra coupée).
  VideoTrack? get _localVideoTrack {
    final lp = _room?.localParticipant;
    if (lp == null || !_isCameraEnabled) return null;
    final pub = lp.getTrackPublicationBySource(TrackSource.camera);
    return pub?.track as VideoTrack?;
  }

  Widget _buildRemoteVideo() {
    final track = _remoteVideoTrack;
    if (track != null) {
      // Flux vidéo distant en plein écran.
      return Positioned.fill(
        child: VideoTrackRenderer(
          track,
          fit: VideoViewFit.cover,
        ),
      );
    }
    // Pas de vidéo distante : avatar + statut (appel audio, ou vidéo coupée).
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [BabifixDesign.navy, Color(0xFF0A1020)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 120),
            CircleAvatar(
              radius: 60,
              backgroundColor: BabifixDesign.ciOrange,
              child: Text(
                widget.targetUserName.isNotEmpty
                    ? widget.targetUserName[0].toUpperCase()
                    : '?',
                style: const TextStyle(fontSize: 48, color: Colors.white),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.targetUserName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isConnected
                  ? (_remoteParticipant != null
                      ? (widget.isVideoCall
                          ? 'Caméra désactivée'
                          : 'Appel en cours')
                      : 'En attente de réponse…')
                  : 'Connexion…',
              style: const TextStyle(color: Colors.white60, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalVideo() {
    if (!widget.isVideoCall) return const SizedBox.shrink();

    final track = _localVideoTrack;
    return Positioned(
      top: 90,
      right: 16,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 100,
          height: 150,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24, width: 1),
          ),
          child: track != null
              ? VideoTrackRenderer(track, fit: VideoViewFit.cover)
              : const Center(
                  child: Icon(Icons.videocam_off,
                      color: Colors.white, size: 32),
                ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Positioned(
      bottom: 30,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildControlButton(
            icon: _isMicEnabled ? Icons.mic : Icons.mic_off,
            color: _isMicEnabled ? Colors.white : BabifixDesign.error,
            bgColor: _isMicEnabled
                ? Colors.white.withValues(alpha: 0.2)
                : BabifixDesign.error,
            onPressed: _toggleMic,
          ),
          const SizedBox(width: 20),
          _buildControlButton(
            icon: Icons.call_end,
            color: Colors.white,
            bgColor: BabifixDesign.error,
            size: 60,
            onPressed: _endCall,
          ),
          if (widget.isVideoCall) ...[
            const SizedBox(width: 20),
            _buildControlButton(
              icon: _isCameraEnabled ? Icons.videocam : Icons.videocam_off,
              color: _isCameraEnabled ? Colors.white : BabifixDesign.error,
              bgColor: _isCameraEnabled
                  ? Colors.white.withValues(alpha: 0.2)
                  : BabifixDesign.error,
              onPressed: _toggleCamera,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required Color color,
    required Color bgColor,
    required VoidCallback onPressed,
    double size = 50,
  }) {
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(size / 2),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(size / 2),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            color: color,
            size: size * 0.45,
          ),
        ),
      ),
    );
  }
}
