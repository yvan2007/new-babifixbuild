import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'babifix_ring_loader.dart';

/// IDs alignes sur [PAYMENT_METHOD_STATIC] (API Django / client).
const Map<String, String> kBabifixPaymentLogoAssets = {
  'ORANGE_MONEY': 'assets/payment_logos/orange-money.png',
  'MTN_MOMO': 'assets/payment_logos/mtn-momo.png',
  'WAVE': 'assets/payment_logos/wave.png',
  'MOOV': 'assets/payment_logos/moov-money.png',
};

class _OperatorStyle {
  const _OperatorStyle({
    required this.label,
    required this.bg,
    required this.border,
  });
  final String label;
  final Color bg;
  final Color border;
}

const Map<String, _OperatorStyle> _operatorStyles = {
  'WAVE': _OperatorStyle(
    label: 'Wave',
    bg: Color(0xFFEAF7FF),
    border: Color(0xFF38BDF8),
  ),
  'ORANGE_MONEY': _OperatorStyle(
    label: 'Orange Money',
    bg: Color(0xFFFFF4EC),
    border: Color(0xFFFB923C),
  ),
  'MTN_MOMO': _OperatorStyle(
    label: 'MTN MoMo',
    bg: Color(0xFFFFFBEB),
    border: Color(0xFFFACC15),
  ),
  'MOOV': _OperatorStyle(
    label: 'Moov Money',
    bg: Color(0xFFEEF4FF),
    border: Color(0xFF60A5FA),
  ),
};

String normalizeBabifixPaymentMethodId(String raw) {
  final u = raw.trim().toUpperCase();
  if (u.contains('WAVE')) return 'WAVE';
  if (u.contains('ORANGE')) return 'ORANGE_MONEY';
  if (u.contains('MTN') || u.contains('MOMO')) return 'MTN_MOMO';
  if (u.contains('MOOV')) return 'MOOV';
  return u;
}

/// Logo d'un operateur Mobile Money : URL API (PNG/SVG) ou asset embarque.
class BabifixPaymentMethodLogo extends StatelessWidget {
  const BabifixPaymentMethodLogo({
    super.key,
    required this.methodId,
    this.logoUrl,
    this.height = 40,
    this.fit = BoxFit.contain,
  });

  final String methodId;
  final String? logoUrl;
  final double height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final u = logoUrl?.trim() ?? '';
    if (u.isNotEmpty) {
      final lower = u.toLowerCase();
      if (lower.endsWith('.svg')) {
        return SizedBox(
          height: height,
          child: SvgPicture.network(
            u,
            fit: fit,
            placeholderBuilder: (_) => SizedBox(
              height: height,
              child: const Center(child: BabifixRingLoader.cyan(size: 22)),
            ),
            errorBuilder: (_, __, ___) => _assetFallback(methodId, height),
          ),
        );
      }
      return Image.network(
        u,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => _assetFallback(methodId, height),
      );
    }
    return _assetFallback(methodId, height);
  }

  Widget _assetFallback(String id, double h) {
    final norm = normalizeBabifixPaymentMethodId(id);
    final path = kBabifixPaymentLogoAssets[norm] ?? kBabifixPaymentLogoAssets[id];
    if (path == null) {
      return Icon(Icons.payments_rounded, size: h * 0.85, color: Colors.grey);
    }
    final img = Image.asset(path, height: h, fit: fit);
    if (norm == 'MTN_MOMO') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(h * 0.22),
        child: Transform.scale(scale: 1.48, child: img),
      );
    }
    return img;
  }
}

/// Badge squircle calibre encadrant proprement n'importe quel logo Mobile Money
/// (Wave, Orange Money, MTN MoMo, Moov) avec taille et padding uniformes.
class BabifixPaymentMethodBadge extends StatelessWidget {
  const BabifixPaymentMethodBadge({
    super.key,
    required this.methodId,
    this.logoUrl,
    this.size = 40,
    this.selected = false,
    this.onDarkSurface = false,
  });

  final String methodId;
  final String? logoUrl;
  final double size;
  final bool selected;
  final bool onDarkSurface;

  @override
  Widget build(BuildContext context) {
    final norm = normalizeBabifixPaymentMethodId(methodId);
    final st = _operatorStyles[norm];
    final radius = (size * 0.28).clamp(6.0, 14.0);
    final borderColor = selected
        ? (st?.border ?? const Color(0xFF4CC9F0))
        : (onDarkSurface
            ? Colors.white.withValues(alpha: 0.22)
            : (st?.border.withValues(alpha: 0.45) ?? const Color(0xFFE2E8F0)));

    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.14),
      decoration: BoxDecoration(
        color: st?.bg ?? Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: borderColor,
          width: selected ? 1.8 : 1.0,
        ),
      ),
      child: Center(
        child: BabifixPaymentMethodLogo(
          methodId: norm,
          logoUrl: logoUrl,
          height: size * 0.68,
        ),
      ),
    );
  }
}

/// Bandeau des 4 operateurs calibres dans des badges squircles uniformes.
class BabifixMobileMoneyLogoStrip extends StatelessWidget {
  const BabifixMobileMoneyLogoStrip({super.key, this.height = 24});

  final double height;

  static const _ids = ['ORANGE_MONEY', 'MTN_MOMO', 'WAVE', 'MOOV'];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < _ids.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          BabifixPaymentMethodBadge(
            methodId: _ids[i],
            size: height + 6,
          ),
        ],
      ],
    );
  }
}
