import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../auth_utils.dart';
import 'babifix_snackbar.dart';

/// Formate une duree en mm:ss.
String formatVoiceDuration(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  final m = (safe ~/ 60).toString().padLeft(2, '0');
  final s = (safe % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// Lecteur premium Direction 3 pour notes vocales :
/// - bouton lecture/pause contrasté
/// - forme d'onde 22 barres interactive (tap pour avancer/reculer)
/// - selecteur de vitesse (1x / 1.5x / 2x)
/// - bouton "Transcrire" connecte a POST /api/audio/transcribe/
class BabifixVoiceNotePlayer extends StatefulWidget {
  const BabifixVoiceNotePlayer({
    super.key,
    required this.url,
    required this.durationSeconds,
    required this.isMe,
    this.foregroundColor,
    this.initialTranscript,
    this.messageId,
    this.reservationReference,
    this.authToken,
  });

  final String url;
  final int durationSeconds;
  final bool isMe;
  final Color? foregroundColor;
  final String? initialTranscript;
  final int? messageId;
  final String? reservationReference;
  final String? authToken;

  @override
  State<BabifixVoiceNotePlayer> createState() => _BabifixVoiceNotePlayerState();
}

class _BabifixVoiceNotePlayerState extends State<BabifixVoiceNotePlayer> {
  static const List<double> _speeds = <double>[1.0, 1.5, 2.0];
  static const int _barCount = 22;

  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<void>? _completeSub;
  StreamSubscription<Duration>? _stateSub;
  bool _playing = false;
  int _speedIndex = 0;
  Duration _position = Duration.zero;
  Duration _total = Duration.zero;

  String? _transcript;
  bool _transcriptExpanded = false;
  bool _transcribing = false;
  String? _transcribeNotice;

  late final List<double> _bars;

  bool get _canTranscribe =>
      (widget.messageId != null && widget.messageId! > 0) ||
      (widget.reservationReference != null &&
          widget.reservationReference!.trim().isNotEmpty);

  @override
  void initState() {
    super.initState();
    _total = Duration(seconds: widget.durationSeconds);
    final initT = (widget.initialTranscript ?? '').trim();
    if (initT.isNotEmpty) {
      _transcript = initT;
    }
    _bars = _generateDeterministicBars(widget.url);
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

  static List<double> _generateDeterministicBars(String seed) {
    var h = 2166136261;
    for (var i = 0; i < seed.length; i++) {
      h ^= seed.codeUnitAt(i);
      h = (h * 16777619) & 0x7fffffff;
    }
    final out = <double>[];
    for (var i = 0; i < _barCount; i++) {
      final phase = (i + 1) * 0.55 + (h % 13) * 0.2;
      final envelope = math.sin((i / (_barCount - 1)) * math.pi);
      final wave = 0.35 + 0.65 * ((math.sin(phase).abs() * 0.7) + envelope * 0.3);
      out.add(wave.clamp(0.24, 1.0));
    }
    return out;
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
        if (_speeds[_speedIndex] != 1.0) {
          await _player.setPlaybackRate(_speeds[_speedIndex]);
        }
        if (mounted) setState(() => _playing = true);
      }
    } catch (_) {
      if (mounted) setState(() => _playing = false);
    }
  }

  Future<void> _cycleSpeed() async {
    final nextIdx = (_speedIndex + 1) % _speeds.length;
    setState(() => _speedIndex = nextIdx);
    try {
      await _player.setPlaybackRate(_speeds[nextIdx]);
    } catch (_) {}
  }

  Future<void> _seekToRatio(double ratio) async {
    final totalMs = _total.inMilliseconds > 0
        ? _total.inMilliseconds
        : (widget.durationSeconds * 1000);
    if (totalMs <= 0) return;
    final targetMs = (totalMs * ratio.clamp(0.0, 1.0)).round();
    final target = Duration(milliseconds: targetMs);
    setState(() => _position = target);
    try {
      await _player.seek(target);
    } catch (_) {}
  }

  Future<void> _toggleTranscript() async {
    if (_transcript != null && _transcript!.isNotEmpty) {
      setState(() => _transcriptExpanded = !_transcriptExpanded);
      return;
    }
    if (_transcribing || !_canTranscribe) return;
    setState(() {
      _transcribing = true;
      _transcribeNotice = null;
      _transcriptExpanded = true;
    });
    try {
      final token = (widget.authToken != null && widget.authToken!.isNotEmpty)
          ? widget.authToken
          : await readStoredApiToken();
      if (token == null || token.isEmpty) {
        if (mounted) {
          setState(() {
            _transcribing = false;
            _transcribeNotice = 'Connexion requise pour transcrire cet audio.';
          });
        }
        return;
      }
      final payload = <String, dynamic>{};
      if (widget.messageId != null && widget.messageId! > 0) {
        payload['message_id'] = widget.messageId;
      } else if (widget.reservationReference != null &&
          widget.reservationReference!.trim().isNotEmpty) {
        payload['reservation_reference'] = widget.reservationReference!.trim();
      }
      final res = await http
          .post(
            Uri.parse('${babifixApiBaseUrl()}/api/audio/transcribe/'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 25));
      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final txt = '${data['transcript'] ?? ''}'.trim();
      if (res.statusCode == 200 && data['ok'] == true && txt.isNotEmpty) {
        setState(() {
          _transcript = txt;
          _transcribeNotice = null;
          _transcribing = false;
        });
      } else {
        final msg = '${data['detail'] ?? ''}'.trim();
        setState(() {
          _transcribing = false;
          _transcribeNotice = msg.isNotEmpty
              ? msg
              : 'Transcription indisponible pour cette note vocale.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _transcribing = false;
          _transcribeNotice = 'Impossible de joindre le service de transcription.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.foregroundColor ??
        (widget.isMe ? Colors.white : BabifixDesign.textPrimaryOf(context));
    final inactiveBar = fg.withValues(alpha: 0.28);
    final pillBg = fg.withValues(alpha: 0.14);
    final totalMs = _total.inMilliseconds == 0
        ? (widget.durationSeconds * 1000)
        : _total.inMilliseconds;
    final progress = totalMs == 0
        ? 0.0
        : (_position.inMilliseconds / totalMs).clamp(0.0, 1.0);
    final timeLabel = _playing || _position > Duration.zero
        ? formatVoiceDuration(
            ((totalMs - _position.inMilliseconds) ~/ 1000).clamp(0, 9999))
        : formatVoiceDuration(widget.durationSeconds);
    final speedVal = _speeds[_speedIndex];
    final speedText = speedVal == 1.5 ? '1.5x' : '${speedVal.toInt()}x';

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 215, maxWidth: 360),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: _toggle,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: fg.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                    border: Border.all(color: fg.withValues(alpha: 0.25)),
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
                    LayoutBuilder(
                      builder: (ctx, box) => GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (d) {
                          if (box.maxWidth > 0) {
                            _seekToRatio(d.localPosition.dx / box.maxWidth);
                          }
                        },
                        child: SizedBox(
                          height: 26,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: List.generate(_bars.length, (i) {
                              final barRatio = (i + 0.5) / _bars.length;
                              final active = progress >= barRatio;
                              return Container(
                                width: 3,
                                height: 6 + (_bars[i] * 18),
                                decoration: BoxDecoration(
                                  color: active ? fg : inactiveBar,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              );
                            }),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.graphic_eq_rounded,
                          size: 13,
                          color: fg.withValues(alpha: 0.78),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          timeLabel,
                          style: TextStyle(
                            fontSize: 11,
                            color: fg.withValues(alpha: 0.9),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: _cycleSpeed,
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: pillBg,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              speedText,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: fg,
                              ),
                            ),
                          ),
                        ),
                        if (_canTranscribe) ...[
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: _toggleTranscript,
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: pillBg,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_transcribing)
                                    SizedBox(
                                      width: 10,
                                      height: 10,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.6,
                                        color: fg,
                                      ),
                                    )
                                  else
                                    Icon(
                                      Icons.subtitles_outlined,
                                      size: 12,
                                      color: fg,
                                    ),
                                  const SizedBox(width: 3),
                                  Text(
                                    _transcriptExpanded && _transcript != null
                                        ? 'Masquer'
                                        : 'Transcrire',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: fg,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_transcriptExpanded &&
              (_transcript != null || _transcribeNotice != null)) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: fg.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: fg.withValues(alpha: 0.18)),
              ),
              child: Text(
                _transcript ?? _transcribeNotice ?? '',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: fg.withValues(alpha: 0.92),
                  fontStyle: _transcript == null ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Enregistreur : bouton micro (en attente de compatibilite SDK cote Prestataire).
class BabifixVoiceRecorderButton extends StatefulWidget {
  const BabifixVoiceRecorderButton({
    super.key,
    required this.onRecorded,
    this.color,
  });

  final void Function(String path, int durationSeconds) onRecorded;
  final Color? color;

  @override
  State<BabifixVoiceRecorderButton> createState() =>
      _BabifixVoiceRecorderButtonState();
}

class _BabifixVoiceRecorderButtonState
    extends State<BabifixVoiceRecorderButton> {
  @override
  Widget build(BuildContext context) {
    final c = widget.color ?? BabifixDesign.cyan;
    return IconButton(
      onPressed: () {
        showBabifixToast(
          context,
          type: BabifixToastType.info,
          message: 'Note vocale bientot disponible.',
          duration: const Duration(seconds: 2),
        );
      },
      icon: Icon(Icons.mic_none_rounded, color: c.withValues(alpha: 0.6)),
      tooltip: 'Note vocale (bientot)',
    );
  }
}
