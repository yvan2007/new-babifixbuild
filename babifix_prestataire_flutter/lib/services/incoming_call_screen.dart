/// Écran d'appel entrant fullscreen (Phase D — C7/P9).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../babifix_design_system.dart';
import '../services/babifix_api.dart';
import 'call_service.dart';

class IncomingCallScreen extends StatefulWidget {
  final int callId;
  final bool isVideo;
  final String callerName;
  final String roomName;
  final String reservationReference;

  const IncomingCallScreen({
    super.key,
    required this.callId,
    required this.isVideo,
    required this.callerName,
    required this.roomName,
    this.reservationReference = '',
  });

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();
    // Garde l'écran allumé pendant la sonnerie
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    HapticFeedback.heavyImpact();
  }

  @override
  void dispose() {
    _pulse.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final invite = await CallsApi.answer(widget.callId);
      if (!mounted) return;
      await CallService.openActiveCallFromInvite(
        context: context,
        invite: invite,
        isVideo: widget.isVideo,
      );
      // À la sortie de l'écran d'appel actif → end best-effort
      try {
        await CallsApi.end(widget.callId);
      } catch (_) {}
    } on BabifixApiException catch (e) {
      _snack(e.message);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await CallsApi.reject(widget.callId);
    } catch (_) {}
    if (mounted) Navigator.pop(context);
  }

  void _snack(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BabifixDesign.navy,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            Text(
              widget.isVideo ? 'Appel vidéo entrant' : 'Appel entrant',
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  letterSpacing: 0.5),
            ),
            const SizedBox(height: 20),
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) {
                final t = _pulse.value;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 180 + 60 * t,
                      height: 180 + 60 * t,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: BabifixDesign.ciBlue
                            .withValues(alpha: (1 - t) * 0.3),
                      ),
                    ),
                    Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: BabifixDesign.ciBlue,
                        boxShadow: [
                          BoxShadow(
                              color: BabifixDesign.ciBlue
                                  .withValues(alpha: 0.6),
                              blurRadius: 30),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          (widget.callerName.isEmpty
                                  ? '?'
                                  : widget.callerName[0])
                              .toUpperCase(),
                          style: const TextStyle(
                              fontSize: 64,
                              color: Colors.white,
                              fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 28),
            Text(
              widget.callerName,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800),
            ),
            if (widget.reservationReference.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Réservation ${widget.reservationReference}',
                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 50, vertical: 36),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _circleButton(
                    icon: Icons.call_end,
                    color: BabifixDesign.error,
                    label: 'Refuser',
                    onTap: _reject,
                  ),
                  _circleButton(
                    icon: widget.isVideo ? Icons.videocam : Icons.call,
                    color: BabifixDesign.ciGreen,
                    label: 'Accepter',
                    onTap: _accept,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleButton({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _busy ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Icon(icon, color: Colors.white, size: 38),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white)),
      ],
    );
  }
}
