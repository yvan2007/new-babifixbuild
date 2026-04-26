import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class LottieService {
  static Widget _lottie(String asset, {double size = 200, bool repeat = false}) {
    return Lottie.asset(
      asset,
      width: size,
      height: size,
      repeat: repeat,
      errorBuilder: (_, __, ___) => Icon(
        Icons.check_circle_outline,
        size: size * 0.6,
        color: Colors.green,
      ),
    );
  }

  static Future<void> showSuccessAnimation(
    BuildContext context, {
    String? message,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _lottie('assets/lottie/success.json'),
            if (message != null) ...[
              const SizedBox(height: 16),
              Text(
                message,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  static Future<void> showDevisAcceptedAnimation(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _lottie('assets/lottie/success.json'),
            const SizedBox(height: 16),
            const Text(
              'Devis accepté !',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            const Text('Le prestataire sera notifié', style: TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }

  static Future<void> showPaymentSuccessAnimation(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _lottie('assets/lottie/payment.json'),
            const SizedBox(height: 16),
            const Text(
              'Paiement réussi !',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> showTravauxTerminesAnimation(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _lottie('assets/lottie/success.json'),
            const SizedBox(height: 16),
            const Text(
              'Travaux terminés !',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            const Text('Merci de confirmer la fin des travaux', style: TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}
