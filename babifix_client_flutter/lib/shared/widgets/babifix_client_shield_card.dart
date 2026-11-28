import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../babifix_design_system.dart';
import '../../babifix_money.dart';

/// Carte 3D interactive Bouclier Sequestre & Fidelite Client (Recto / Verso).
/// Respecte Direction 3 : Emeraude Foret (#0E3B2E), Titane (#22303D) et Or (#121512/#E7C463).
class BabifixClientShieldCard extends StatefulWidget {
  const BabifixClientShieldCard({
    super.key,
    required this.holderName,
    required this.tierLabel,
    required this.creditFcfa,
    required this.points,
    this.reductionPct = 0,
    this.missionsCount = 0,
    this.verifyQrUrl = '',
    this.compact = false,
    this.onTapAction,
    this.actionLabel,
  });

  final String holderName;
  final String tierLabel;
  final double creditFcfa;
  final int points;
  final int reductionPct;
  final int missionsCount;
  final String verifyQrUrl;
  final bool compact;
  final VoidCallback? onTapAction;
  final String? actionLabel;

  @override
  State<BabifixClientShieldCard> createState() =>
      _BabifixClientShieldCardState();
}

class _BabifixClientShieldCardState extends State<BabifixClientShieldCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flipCtrl;
  bool _isFlipped = false;
  bool _hideAmount = false;
  double _tiltX = 0.0;
  double _tiltY = 0.0;

  @override
  void initState() {
    super.initState();
    _flipCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
  }

  @override
  void dispose() {
    _flipCtrl.dispose();
    super.dispose();
  }

  void _toggleFlip() {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    setState(() => _isFlipped = !_isFlipped);
    if (reduce) {
      _flipCtrl.value = _isFlipped ? 1.0 : 0.0;
    } else if (_isFlipped) {
      _flipCtrl.forward();
    } else {
      _flipCtrl.reverse();
    }
  }

  _ShieldTierStyle _resolveStyle() {
    final t = widget.tierLabel.toLowerCase();
    if (t.contains('or') || t.contains('gold') || t.contains('diamant')) {
      return const _ShieldTierStyle(
        bg: BabifixDesign.obsidianGold,
        border: BabifixDesign.goldBrass,
        accent: BabifixDesign.goldBrass,
        muted: Color(0xFFD6D3D1),
        tag: 'BOUCLIER OR',
      );
    }
    if (t.contains('argent') || t.contains('silver') || t.contains('platine')) {
      return const _ShieldTierStyle(
        bg: BabifixDesign.titaniumCard,
        border: BabifixDesign.silverMetal,
        accent: Color(0xFFE2E8F0),
        muted: Color(0xFFCBD5E1),
        tag: 'BOUCLIER ARGENT',
      );
    }
    return const _ShieldTierStyle(
      bg: BabifixDesign.emeraldForest,
      border: Color(0xFF34D399),
      accent: Color(0xFF6EE7B7),
      muted: Color(0xFFA7F3D0),
      tag: 'PAIEMENT PROTEGE',
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = _resolveStyle();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final h = widget.compact ? 176.0 : 212.0;

    return GestureDetector(
      onTap: _toggleFlip,
      onPanUpdate: reduce
          ? null
          : (d) {
              setState(() {
                _tiltY = (_tiltY + d.delta.dx * 0.004).clamp(-0.14, 0.14);
                _tiltX = (_tiltX - d.delta.dy * 0.004).clamp(-0.10, 0.10);
              });
            },
      onPanEnd: reduce
          ? null
          : (_) => setState(() {
                _tiltX = 0.0;
                _tiltY = 0.0;
              }),
      onPanCancel: () => setState(() {
        _tiltX = 0.0;
        _tiltY = 0.0;
      }),
      child: AnimatedBuilder(
        animation: _flipCtrl,
        builder: (context, _) {
          final curveVal = Curves.easeInOutCubic.transform(_flipCtrl.value);
          final angle = curveVal * math.pi;
          final showBack = angle > (math.pi / 2);

          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0014)
              ..rotateX(_tiltX)
              ..rotateY(_tiltY + angle),
            child: Container(
              height: h,
              decoration: BoxDecoration(
                color: style.bg,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: style.border.withValues(alpha: 0.55),
                  width: 1.4,
                ),
                boxShadow: [
                  BoxShadow(
                    color: style.bg.withValues(alpha: 0.42),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(21),
                child: Stack(
                  children: [
                    Positioned(
                      right: -46,
                      top: -46,
                      child: Container(
                        width: 170,
                        height: 170,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              style.accent.withValues(alpha: 0.18),
                              style.accent.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(widget.compact ? 16 : 20),
                      child: showBack
                          ? Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()..rotateY(math.pi),
                              child: _buildVerso(style),
                            )
                          : _buildRecto(style),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRecto(_ShieldTierStyle style) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: style.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: style.border.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_user_rounded, size: 13, color: style.accent),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        style.tag,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: style.accent,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.7,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () => setState(() => _hideAmount = !_hideAmount),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      _hideAmount
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                      color: style.muted,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.flip_camera_android_rounded, size: 17, color: style.muted),
              ],
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Credit & paiement protege',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: style.muted,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                _hideAmount ? '•••••• FCFA' : formatFcfa(widget.creditFcfa),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: widget.compact ? 22 : 27,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.6,
                  fontFeatures: BabifixDesign.tabularFigures,
                ),
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.holderName.isEmpty ? 'Client BABIFIX' : widget.holderName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${widget.points} pts · ${widget.tierLabel}${widget.reductionPct > 0 ? " (-${widget.reductionPct}%)" : ""}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: style.muted,
                      fontSize: 11.5,
                      fontFeatures: BabifixDesign.tabularFigures,
                    ),
                  ),
                ],
              ),
            ),
            if (widget.onTapAction != null && widget.actionLabel != null)
              GestureDetector(
                onTap: widget.onTapAction,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: BabifixDesign.ciOrangeBright,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    widget.actionLabel!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  void _openQrModal(_ShieldTierStyle style) {
    final qrData = widget.verifyQrUrl.trim();
    if (qrData.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Passeport Bouclier BABIFIX',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: QrImageView(
                data: qrData,
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Scannez pour verifier la protection du compte sans exposer vos donnees personnelles.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  Widget _buildVerso(_ShieldTierStyle style) {
    final hasQr = widget.verifyQrUrl.trim().isNotEmpty;
    final qrSize = widget.compact ? 66.0 : 80.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'VOS GARANTIES BABIFIX',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: style.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.flip_camera_android_rounded, size: 17, color: style.muted),
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _guaranteeLine(style, Icons.lock_outline_rounded, 'Fonds bloques jusqu\'au code OTP final'),
                  const SizedBox(height: 5),
                  _guaranteeLine(style, Icons.badge_outlined, 'Artisans verifies KYC & identite'),
                  const SizedBox(height: 5),
                  _guaranteeLine(style, Icons.account_balance_wallet_outlined, 'Wave, Orange, MTN, Moov Money'),
                ],
              ),
            ),
            if (hasQr) ...[
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () => _openQrModal(style),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: QrImageView(
                    data: widget.verifyQrUrl.trim(),
                    version: QrVersions.auto,
                    size: qrSize,
                    padding: EdgeInsets.zero,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                '${widget.missionsCount} mission${widget.missionsCount > 1 ? 's' : ''} protegee${widget.missionsCount > 1 ? 's' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: style.muted,
                  fontSize: 11,
                  fontFeatures: BabifixDesign.tabularFigures,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                hasQr ? 'QR verifie · babifix.ci' : 'babifix.ci',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: style.accent,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _guaranteeLine(_ShieldTierStyle s, IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: s.accent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _ShieldTierStyle {
  const _ShieldTierStyle({
    required this.bg,
    required this.border,
    required this.accent,
    required this.muted,
    required this.tag,
  });

  final Color bg;
  final Color border;
  final Color accent;
  final Color muted;
  final String tag;
}
