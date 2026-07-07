import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../babifix_design_system.dart';

/// Formate une durée en mm:ss.
String formatVoiceDuration(int seconds) {
  final m = (seconds ~/ 60).toString().padLeft(2, '0');
  final s = (seconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// ─────────────────────────────────────────────────────────────────────────
/// LECTEUR de note vocale : bulle play/pause + barre de progression + durée.
/// ─────────────────────────────────────────────────────────────────────────
class BabifixVoiceNotePlayer extends StatefulWidget {
  const BabifixVoiceNotePlayer({
    super.key,
    required this.url,
    required this.durationSeconds,
    required this.isMe,
  });

  final String url;
  final int durationSeconds;
  final bool isMe;

  @override
  State<BabifixVoiceNotePlayer> createState() => _BabifixVoiceNotePlayerState();
}

class _BabifixVoiceNotePlayerState extends State<BabifixVoiceNotePlayer> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<void>? _completeSub;
  StreamSubscription<Duration>? _stateSub;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _total = Duration.zero;

  @override
  void initState() {
    super.initState();
    _total = Duration(seconds: widget.durationSeconds);
    _posSub = _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _stateSub = _player.onDurationChanged.listen((d) {
      if (mounted && d > Duration.zero) setState(() => _total = d);
    });
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playing = false;
          _position = Duration.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _stateSub?.cancel();
    _completeSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    try {
      if (_playing) {
        await _player.pause();
        if (mounted) setState(() => _playing = false);
      } else {
        await _player.play(UrlSource(widget.url));
        if (mounted) setState(() => _playing = true);
      }
    } catch (_) {
      if (mounted) setState(() => _playing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.isMe ? Colors.white : BabifixDesign.navy;
    final track = fg.withValues(alpha: 0.25);
    final totalMs = _total.inMilliseconds == 0
        ? (widget.durationSeconds * 1000)
        : _total.inMilliseconds;
    final progress = totalMs == 0
        ? 0.0
        : (_position.inMilliseconds / totalMs).clamp(0.0, 1.0);
    final remaining = _playing || _position > Duration.zero
        ? formatVoiceDuration(
            ((totalMs - _position.inMilliseconds) ~/ 1000).clamp(0, 9999))
        : formatVoiceDuration(widget.durationSeconds);

    return SizedBox(
      width: 210,
      child: Row(
        children: [
          GestureDetector(
            onTap: _toggle,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: fg.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: fg,
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: track,
                    valueColor: AlwaysStoppedAnimation(fg),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.mic_rounded, size: 13, color: fg.withValues(alpha: 0.7)),
                    const SizedBox(width: 4),
                    Text(
                      remaining,
                      style: TextStyle(
                        fontSize: 11,
                        color: fg.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────
/// ENREGISTREUR : bouton micro maintenu pour enregistrer. Au relâchement,
/// renvoie le chemin du fichier + la durée. Annulation si glissement / trop court.
/// ─────────────────────────────────────────────────────────────────────────
class BabifixVoiceRecorderButton extends StatefulWidget {
  const BabifixVoiceRecorderButton({
    super.key,
    required this.onRecorded,
    this.color,
  });

  /// Appelé avec (cheminFichier, dureeSecondes) une fois l'enregistrement prêt.
  final void Function(String path, int durationSeconds) onRecorded;
  final Color? color;

  @override
  State<BabifixVoiceRecorderButton> createState() =>
      _BabifixVoiceRecorderButtonState();
}

class _BabifixVoiceRecorderButtonState
    extends State<BabifixVoiceRecorderButton> {
  final AudioRecorder _rec = AudioRecorder();
  bool _recording = false;
  int _seconds = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _rec.dispose();
    super.dispose();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _toggle() async {
    if (_recording) {
      // Arrêt
      String? path;
      try {
        path = await _rec.stop();
      } catch (_) {}
      _timer?.cancel();
      final dur = _seconds;
      if (mounted) setState(() {
        _recording = false;
        _seconds = 0;
      });
      if (path != null && path.isNotEmpty && dur >= 1) {
        widget.onRecorded(path, dur);
      } else {
        _snack('Note vocale trop courte.');
      }
      return;
    }
    // Démarrage
    try {
      if (!await _rec.hasPermission()) {
        _snack('Autorisez le micro pour enregistrer une note vocale.');
        return;
      }
      final dir = await getTemporaryDirectory();
      final p =
          '${dir.path}/vn_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _rec.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: p,
      );
      if (mounted) setState(() {
        _recording = true;
        _seconds = 0;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _seconds++);
        if (_seconds >= 120) _toggle(); // limite 2 minutes
      });
    } catch (e) {
      _snack('Enregistrement impossible.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.color ?? BabifixDesign.cyan;
    if (_recording) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            formatVoiceDuration(_seconds),
            style: const TextStyle(
                color: Colors.red, fontWeight: FontWeight.w700, fontSize: 12),
          ),
          IconButton(
            onPressed: _toggle,
            icon: const Icon(Icons.stop_circle_rounded, color: Colors.red),
            tooltip: 'Arrêter',
          ),
        ],
      );
    }
    return IconButton(
      onPressed: _toggle,
      icon: Icon(Icons.mic_none_rounded, color: c),
      tooltip: 'Enregistrer une note vocale',
    );
  }
}
