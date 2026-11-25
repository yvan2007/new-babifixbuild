import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../babifix_design_system.dart';
import '../../shared/widgets/animated_money.dart';
import '../../shared/widgets/babifix_snackbar.dart';
import '../../shared/widgets/payment_method_logo.dart';

enum BabifixWalletTier {
  standard,
  silver,
  gold;

  static BabifixWalletTier fromString(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'gold':
        return BabifixWalletTier.gold;
      case 'silver':
        return BabifixWalletTier.silver;
      default:
        return BabifixWalletTier.standard;
    }
  }

  String get badgeLabel => switch (this) {
        BabifixWalletTier.gold => 'MEMBRE GOLD',
        BabifixWalletTier.silver => 'MEMBRE SILVER',
        BabifixWalletTier.standard => 'PORTEFEUILLE PRO',
      };
}

class _TierPalette {
  const _TierPalette({
    required this.bgStart,
    required this.bgEnd,
    required this.border,
    required this.accent,
    required this.chipBase,
    required this.chipHighlight,
    required this.badgeBg,
    required this.badgeFg,
    required this.subtleInk,
  });

  final Color bgStart;
  final Color bgEnd;
  final Color border;
  final Color accent;
  final Color chipBase;
  final Color chipHighlight;
  final Color badgeBg;
  final Color badgeFg;
  final Color subtleInk;
}

_TierPalette _paletteFor(BabifixWalletTier tier) {
  switch (tier) {
    case BabifixWalletTier.gold:
      return const _TierPalette(
        bgStart: Color(0xFF121512),
        bgEnd: Color(0xFF1E2019),
        border: Color(0xFFE7C463),
        accent: Color(0xFFF3C669),
        chipBase: Color(0xFFC59337),
        chipHighlight: Color(0xFFF5D487),
        badgeBg: Color(0x33E7C463),
        badgeFg: Color(0xFFF6D37A),
        subtleInk: Color(0xFFE7C463),
      );
    case BabifixWalletTier.silver:
      return const _TierPalette(
        bgStart: Color(0xFF22303D),
        bgEnd: Color(0xFF334155),
        border: Color(0xFFCBD5E1),
        accent: Color(0xFFE2E8F0),
        chipBase: Color(0xFF94A3B8),
        chipHighlight: Color(0xFFE2E8F0),
        badgeBg: Color(0x2EE2E8F0),
        badgeFg: Color(0xFFF8FAFC),
        subtleInk: Color(0xFFCBD5E1),
      );
    case BabifixWalletTier.standard:
      return const _TierPalette(
        bgStart: Color(0xFF0E3B2E),
        bgEnd: Color(0xFF08261D),
        border: Color(0xFF34D399),
        accent: Color(0xFF6EE7B7),
        chipBase: Color(0xFF9FB8D0),
        chipHighlight: Color(0xFFE2F1FF),
        badgeBg: Color(0x2634D399),
        badgeFg: Color(0xFFA7F3D0),
        subtleInk: Color(0xFF6EE7B7),
      );
  }
}

/// Carte bancaire / Wallet 3D recto-verso sur mesure pour BABIFIX PRO.
/// Evolue visuellement selon le palier d'abonnement (standard, silver, gold).
class BabifixWalletCard extends StatefulWidget {
  const BabifixWalletCard({
    super.key,
    required this.soldeFcfa,
    required this.prestataireName,
    required this.maskedCardNumber,
    this.tier = BabifixWalletTier.standard,
    this.hidden = false,
    this.phonePrimary = '',
    this.operatorPrimary = '',
    this.phoneSecondary = '',
    this.operatorSecondary = '',
    this.pinActive = false,
    this.onToggleHidden,
    this.compactPreview = false,
  });

  final double soldeFcfa;
  final String prestataireName;
  final String maskedCardNumber;
  final BabifixWalletTier tier;
  final bool hidden;
  final String phonePrimary;
  final String operatorPrimary;
  final String phoneSecondary;
  final String operatorSecondary;
  final bool pinActive;
  final VoidCallback? onToggleHidden;
  final bool compactPreview;

  @override
  State<BabifixWalletCard> createState() => _BabifixWalletCardState();
}

class _BabifixWalletCardState extends State<BabifixWalletCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flipCtrl;
  bool _isBack = false;
  double _tiltX = 0;
  double _tiltY = 0;

  @override
  void initState() {
    super.initState();
    _flipCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 440),
    );
  }

  @override
  void dispose() {
    _flipCtrl.dispose();
    super.dispose();
  }

  void _toggleFlip() {
    HapticFeedback.selectionClick();
    setState(() => _isBack = !_isBack);
    if (_isBack) {
      _flipCtrl.forward();
    } else {
      _flipCtrl.reverse();
    }
  }

  String get _suffix {
    final clean = widget.maskedCardNumber.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.length >= 4) return clean.substring(clean.length - 4);
    final pClean = widget.phonePrimary.replaceAll(RegExp(r'[^0-9]'), '');
    if (pClean.length >= 4) return pClean.substring(pClean.length - 4);
    return '0412';
  }

  String get _holderDisplay {
    final trimmed = widget.prestataireName.trim();
    return (trimmed.isEmpty ? 'PRESTATAIRE BABIFIX' : trimmed).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final palette = _paletteFor(widget.tier);
    final aspect = widget.compactPreview ? 1.66 : 1.586;

    return GestureDetector(
      onPanUpdate: (reduce || widget.compactPreview)
          ? null
          : (d) {
              setState(() {
                _tiltY = (_tiltY - d.delta.dx * 0.0045).clamp(-0.14, 0.14);
                _tiltX = (_tiltX + d.delta.dy * 0.0045).clamp(-0.12, 0.12);
              });
            },
      onPanEnd: (reduce || widget.compactPreview)
          ? null
          : (_) => setState(() {
                _tiltX = 0;
                _tiltY = 0;
              }),
      onPanCancel: (reduce || widget.compactPreview)
          ? null
          : () => setState(() {
                _tiltX = 0;
                _tiltY = 0;
              }),
      onDoubleTap: widget.compactPreview ? null : _toggleFlip,
      child: TweenAnimationBuilder<Offset>(
        tween: Tween<Offset>(
          begin: Offset.zero,
          end: Offset(_tiltX, _tiltY),
        ),
        duration: reduce ? Duration.zero : const Duration(milliseconds: 180),
        curve: BabifixDesign.curveOut,
        builder: (_, tilt, __) {
          return AnimatedBuilder(
            animation: _flipCtrl,
            builder: (ctx, _) {
              final curved = Curves.easeInOutCubic.transform(_flipCtrl.value);
              final flipAngle = curved * math.pi;
              final showBack = flipAngle > (math.pi / 2);
              final matrix = Matrix4.identity()
                ..setEntry(3, 2, 0.0012)
                ..rotateX(tilt.dx)
                ..rotateY(tilt.dy + flipAngle);

              Widget face = showBack
                  ? Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()..rotateY(math.pi),
                      child: _buildVerso(palette),
                    )
                  : _buildRecto(palette, tilt);

              return Transform(
                alignment: Alignment.center,
                transform: matrix,
                child: AspectRatio(
                  aspectRatio: aspect,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.28),
                          blurRadius: 24,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: face,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showQrCertModal(_TierPalette p) {
    final id = 'BFX-PRO-$_suffix';
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: p.bgStart,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: p.border.withValues(alpha: 0.65), width: 1.4),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'CERTIFICAT PRO BABIFIX',
                    style: TextStyle(
                      color: p.accent,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: 170,
                height: 170,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: CustomPaint(
                  painter: _GeometricQrPainter(
                    seedText: '$_suffix|$_holderDisplay',
                    ink: p.bgStart,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _holderDisplay,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'ID $id · ${widget.tier.badgeLabel}',
                style: TextStyle(
                  color: p.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFeatures: BabifixDesign.tabularFigures,
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: id));
                  Navigator.of(ctx).pop();
                  showBabifixToast(
                    context,
                    type: BabifixToastType.success,
                    message: 'Identifiant $id copié',
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: p.border.withValues(alpha: 0.6)),
                ),
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copier l\'identifiant'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecto(_TierPalette p, Offset tilt) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [p.bgStart, p.bgEnd],
        ),
        border: Border.all(
          color: p.border.withValues(alpha: widget.tier == BabifixWalletTier.standard ? 0.36 : 0.62),
          width: widget.tier == BabifixWalletTier.gold ? 1.4 : 1.1,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              painter: _CardArtworkPainter(
                tier: widget.tier,
                accent: p.subtleInk,
                glintOffset: tilt.dy * 2.2,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(widget.compactPreview ? 16 : 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top row: marque + badge abonnement + bouton verso
                Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: BabifixDesign.ciOrange,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: const Icon(
                        Icons.handyman_rounded,
                        color: Colors.white,
                        size: 15,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'BABIFIX PRO',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: p.badgeBg,
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color: p.border.withValues(alpha: 0.55),
                        ),
                      ),
                      child: Text(
                        widget.tier.badgeLabel,
                        style: TextStyle(
                          color: p.badgeFg,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.7,
                        ),
                      ),
                    ),
                    if (!widget.compactPreview) ...[
                      const SizedBox(width: 6),
                      _FlipActionChip(
                        label: 'Verso',
                        color: Colors.white,
                        onTap: _toggleFlip,
                      ),
                    ],
                  ],
                ),

                // Middle row: puce EMV gravee + sans contact + suffixe carte
                Row(
                  children: [
                    RepaintBoundary(
                      child: SizedBox(
                        width: 40,
                        height: 28,
                        child: CustomPaint(
                          painter: _EmvChipPainter(
                            base: p.chipBase,
                            highlight: p.chipHighlight,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(
                      Icons.wifi_rounded,
                      color: Colors.white.withValues(alpha: 0.65),
                      size: 18,
                    ),
                    const Spacer(),
                    Text(
                      '•••• $_suffix',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.6,
                        fontFeatures: BabifixDesign.tabularFigures,
                      ),
                    ),
                  ],
                ),

                // Hero solde disponible
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'SOLDE DISPONIBLE',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.60),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.3,
                          ),
                        ),
                        if (widget.onToggleHidden != null &&
                            !widget.compactPreview) ...[
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: widget.onToggleHidden,
                            behavior: HitTestBehavior.opaque,
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Icon(
                                widget.hidden
                                    ? Icons.visibility_off_rounded
                                    : Icons.visibility_rounded,
                                size: 15,
                                color: Colors.white.withValues(alpha: 0.70),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    AnimatedSwitcher(
                      duration: reduce
                          ? Duration.zero
                          : const Duration(milliseconds: 200),
                      child: FittedBox(
                        key: ValueKey<bool>(widget.hidden),
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: widget.hidden
                            ? Text(
                                '• • • • • FCFA',
                                style: BabifixDesign.amountStyle(
                                  color: Colors.white,
                                  fontSize: widget.compactPreview ? 22 : 28,
                                  fontWeight: FontWeight.w900,
                                ),
                              )
                            : AnimatedMoney(
                                value: widget.soldeFcfa,
                                suffix: ' FCFA',
                                style: BabifixDesign.amountStyle(
                                  color: Colors.white,
                                  fontSize: widget.compactPreview ? 22 : 28,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),

                // Footer: titulaire + certification
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _holderDisplay,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                              letterSpacing: 0.9,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            'Sequestre verifie BABIFIX CI',
                            style: TextStyle(
                              color: p.accent.withValues(alpha: 0.85),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.14),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.verified_user_rounded,
                            size: 12,
                            color: Color(0xFF4ADE80),
                          ),
                          SizedBox(width: 4),
                          Text(
                            'XOF',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
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

  Widget _buildVerso(_TierPalette p) {
    final op1 = normalizeBabifixPaymentMethodId(widget.operatorPrimary);
    final op2 = normalizeBabifixPaymentMethodId(widget.operatorSecondary);
    final hasOp1 = widget.phonePrimary.trim().isNotEmpty;
    final hasOp2 = widget.phoneSecondary.trim().isNotEmpty;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.bgStart,
        border: Border.all(
          color: p.border.withValues(alpha: 0.62),
          width: 1.3,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: CustomPaint(
              painter: _CardArtworkPainter(
                tier: widget.tier,
                accent: p.accent,
                glintOffset: -_tiltY * 2.5,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              // Bande magnetique authentique
              Container(
                height: 28,
                color: const Color(0xFF04060B),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () {
                        final id = 'BFX-PRO-$_suffix';
                        Clipboard.setData(ClipboardData(text: id));
                        HapticFeedback.lightImpact();
                        showBabifixToast(
                          context,
                          type: BabifixToastType.success,
                          message: 'Référence $id copiée',
                          duration: const Duration(seconds: 2),
                        );
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'REF BFX-PRO-$_suffix',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                              fontFeatures: BabifixDesign.tabularFigures,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.copy_rounded,
                            size: 11,
                            color: Colors.white.withValues(alpha: 0.65),
                          ),
                        ],
                      ),
                    ),
                    _FlipActionChip(
                      label: 'Recto',
                      color: Colors.white,
                      onTap: _toggleFlip,
                    ),
                  ],
                ),
              ),
              // Bande de signature satinee + sceau certifie festonne
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 7, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 21,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'KYC VERIFIE · CANTONNE',
                              style: TextStyle(
                                color: p.bgStart,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.7,
                              ),
                            ),
                            Text(
                              widget.pinActive ? 'PIN ACTIF' : 'PIN REQUIS',
                              style: TextStyle(
                                color: widget.pinActive
                                    ? const Color(0xFF15803D)
                                    : const Color(0xFFB45309),
                                fontSize: 8.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CustomPaint(
                        painter: _CertifiedSealPainter(color: p.accent),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'CANAUX DE VERSEMENT',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.60),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                if (!hasOp1 && !hasOp2)
                                  Text(
                                    'Aucun numero configure',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.75),
                                      fontSize: 11,
                                    ),
                                  )
                                else
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (hasOp1)
                                        _LinkedChannelRow(
                                          operatorId: op1,
                                          phone: widget.phonePrimary,
                                        ),
                                      if (hasOp2) ...[
                                        const SizedBox(height: 4),
                                        _LinkedChannelRow(
                                          operatorId: op2,
                                          phone: widget.phoneSecondary,
                                        ),
                                      ],
                                    ],
                                  ),
                              ],
                            ),
                            Row(
                              children: [
                                Icon(
                                  widget.pinActive
                                      ? Icons.lock_rounded
                                      : Icons.lock_open_rounded,
                                  size: 12,
                                  color: widget.pinActive
                                      ? const Color(0xFF4ADE80)
                                      : const Color(0xFFFBBF24),
                                ),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    'Conforme Loi 2013-450',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.72),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: () => _showQrCertModal(p),
                            child: Container(
                              width: 60,
                              height: 60,
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: RepaintBoundary(
                                child: CustomPaint(
                                  painter: _GeometricQrPainter(
                                    seedText: '$_suffix|$_holderDisplay',
                                    ink: p.bgStart,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'QR CONTROLE',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.9,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FlipActionChip extends StatelessWidget {
  const _FlipActionChip({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.flip_rounded, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkedChannelRow extends StatelessWidget {
  const _LinkedChannelRow({
    required this.operatorId,
    required this.phone,
  });

  final String operatorId;
  final String phone;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        BabifixPaymentMethodBadge(
          methodId: operatorId,
          size: 24,
          onDarkSurface: true,
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            phone,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFeatures: BabifixDesign.tabularFigures,
            ),
          ),
        ),
      ],
    );
  }
}

/// Gravure architecturale / topographique / guilloche adaptee au palier.
class _CardArtworkPainter extends CustomPainter {
  const _CardArtworkPainter({
    required this.tier,
    required this.accent,
    required this.glintOffset,
  });

  final BabifixWalletTier tier;
  final Color accent;
  final double glintOffset;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = accent.withValues(alpha: tier == BabifixWalletTier.gold ? 0.14 : 0.10);

    if (tier == BabifixWalletTier.gold) {
      // Guilloche concentrique & triple filets dores en arc
      final origin = Offset(w * 0.88, h * 0.18);
      for (var i = 1; i <= 7; i++) {
        canvas.drawCircle(origin, i * 26.0, linePaint);
      }
      final ringOrigin = Offset(w * 0.14, h * 0.88);
      for (var i = 1; i <= 4; i++) {
        canvas.drawCircle(ringOrigin, i * 22.0, linePaint);
      }
    } else if (tier == BabifixWalletTier.silver) {
      // Courbes topographiques + trame diagonale acier brosse
      for (var i = -3; i < 12; i++) {
        final y = i * (h / 8);
        final path = Path()
          ..moveTo(0, y)
          ..quadraticBezierTo(w * 0.45, y + 18, w, y - 14);
        canvas.drawPath(path, linePaint);
      }
    } else {
      // Grille architecturale isometrique et circuits cyan
      const step = 28.0;
      for (double x = 0; x < w; x += step) {
        canvas.drawLine(Offset(x, 0), Offset(x, h), linePaint);
      }
      for (double y = 0; y < h; y += step) {
        canvas.drawLine(Offset(0, y), Offset(w, y), linePaint);
      }
      canvas.drawCircle(
        Offset(w * 0.85, h * 0.25),
        58,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = accent.withValues(alpha: 0.16),
      );
    }

    // Reflet speculaire dynamique lie a l'inclinaison 3D
    final centerX = w * (0.5 + glintOffset.clamp(-0.4, 0.4));
    final sheen = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.08),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.25, 0.5, 0.75],
      ).createShader(Rect.fromLTWH(centerX - w * 0.35, 0, w * 0.7, h));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), sheen);
  }

  @override
  bool shouldRepaint(covariant _CardArtworkPainter old) =>
      old.tier != tier ||
      old.accent != accent ||
      old.glintOffset != glintOffset;
}

/// Puce EMV gravee en vecteur avec contacts biseautes.
class _EmvChipPainter extends CustomPainter {
  const _EmvChipPainter({required this.base, required this.highlight});

  final Color base;
  final Color highlight;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [highlight, base],
        ).createShader(rect),
    );
    final groove = Paint()
      ..color = Colors.black.withValues(alpha: 0.32)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;
    canvas.drawRRect(rrect, groove);
    canvas.drawLine(
      Offset(0, size.height * 0.36),
      Offset(size.width, size.height * 0.36),
      groove,
    );
    canvas.drawLine(
      Offset(0, size.height * 0.64),
      Offset(size.width, size.height * 0.64),
      groove,
    );
    canvas.drawLine(
      Offset(size.width * 0.34, 0),
      Offset(size.width * 0.34, size.height),
      groove,
    );
    canvas.drawLine(
      Offset(size.width * 0.66, 0),
      Offset(size.width * 0.66, size.height),
      groove,
    );
  }

  @override
  bool shouldRepaint(covariant _EmvChipPainter old) =>
      old.base != base || old.highlight != highlight;
}

/// Matrice geometrique deterministe de verification visuelle (verso de carte).
class _GeometricQrPainter extends CustomPainter {
  const _GeometricQrPainter({required this.seedText, required this.ink});

  final String seedText;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    const grid = 9;
    final cell = size.width / grid;
    final paint = Paint()..color = ink;

    int hash = 2166136261;
    for (final c in seedText.codeUnits) {
      hash ^= c;
      hash = (hash * 16777619) & 0x7FFFFFFF;
    }

    bool isFinder(int r, int c) {
      return (r < 3 && c < 3) || (r < 3 && c >= grid - 3) || (r >= grid - 3 && c < 3);
    }

    for (var r = 0; r < grid; r++) {
      for (var c = 0; c < grid; c++) {
        final finder = isFinder(r, c);
        final bit = finder
            ? ((r == 1 && c == 1) ||
                (r == 1 && c == grid - 2) ||
                (r == grid - 2 && c == 1) ||
                r == 0 ||
                r == 2 ||
                r == grid - 1 ||
                r == grid - 3 ||
                c == 0 ||
                c == 2 ||
                c == grid - 1 ||
                c == grid - 3)
            : (((hash >> ((r * grid + c) % 24)) ^ (r * 7 + c * 13)) & 1) == 1;
        if (bit) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(c * cell + 0.5, r * cell + 0.5, cell - 1, cell - 1),
              const Radius.circular(1.2),
            ),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GeometricQrPainter old) =>
      old.seedText != seedText || old.ink != ink;
}

/// Sceau circulaire de certification BABIFIX (verso de carte physique).
class _CertifiedSealPainter extends CustomPainter {
  const _CertifiedSealPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 1.5;

    final ringPaint = Paint()
      ..color = color.withValues(alpha: 0.90)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(center, radius, ringPaint);

    final innerFill = Paint()
      ..color = color.withValues(alpha: 0.16)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius - 2.6, innerFill);

    final checkPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(size.width * 0.31, size.height * 0.52)
      ..lineTo(size.width * 0.45, size.height * 0.65)
      ..lineTo(size.width * 0.70, size.height * 0.37);
    canvas.drawPath(path, checkPaint);
  }

  @override
  bool shouldRepaint(covariant _CertifiedSealPainter old) =>
      old.color != color;
}
