import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// IDs alignés sur [PAYMENT_METHOD_STATIC] (API Django / client).
const Map<String, String> kBabifixPaymentLogoAssets = {
  'ORANGE_MONEY': 'assets/payment_logos/orange-money.png',
  'MTN_MOMO': 'assets/payment_logos/mtn-momo.png',
  'WAVE': 'assets/payment_logos/wave.png',
  'MOOV': 'assets/payment_logos/moov-money.png',
};

/// Logo d’un opérateur Mobile Money : URL API (PNG/SVG) ou asset embarqué.
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
              child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
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
    final path = kBabifixPaymentLogoAssets[id];
    if (path == null) {
      return Icon(Icons.payments_rounded, size: h * 0.85, color: Colors.grey);
    }
    return Image.asset(path, height: h, fit: fit);
  }
}
