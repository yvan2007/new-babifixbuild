import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:babifix_client_flutter/babifix_api_config.dart';
import 'package:babifix_client_flutter/user_store.dart';

class GeniusPayService {
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 2);

  /// Initie un paiement GeniusPay.
  /// Retourne [GeniusPayInitResult] en cas de succès, null sinon.
  static Future<GeniusPayInitResult?> initiatePayment({
    required int reservationId,
    required int montant,
    required String paymentMethod, // ORANGE_MONEY | MTN_MOMO | WAVE | PAWAPAY
    required String phone,
    String customerName = 'Client BABIFIX',
    String customerEmail = '',
  }) async {
    int attempts = 0;
    while (attempts < _maxRetries) {
      try {
        final token = await BabifixUserStore.getApiToken();
        final response = await http
            .post(
              Uri.parse('${babifixApiBaseUrl()}/api/paiements/geniuspay/initiate/'),
              headers: {
                'Content-Type': 'application/json',
                if (token != null) 'Authorization': 'Bearer $token',
              },
              body: jsonEncode({
                'reservation': reservationId,
                'montant': montant,
                'payment_method': paymentMethod,
                'phone': phone,
                'customer_name': customerName,
                'customer_email': customerEmail,
              }),
            )
            .timeout(const Duration(seconds: 20));

        if (response.statusCode == 200 || response.statusCode == 201) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          return GeniusPayInitResult(
            transactionId: data['transaction_id'] as String? ?? '',
            paymentId:     (data['payment_id'] as num?)?.toInt() ?? 0,
            paymentUrl:    data['payment_url']  as String? ?? '',
            checkoutUrl:   data['checkout_url'] as String? ?? '',
            status:        data['status']       as String? ?? 'pending',
            message:       data['message']      as String? ?? '',
          );
        }

        if (response.statusCode >= 500) {
          attempts++;
          if (attempts < _maxRetries) {
            await Future.delayed(_retryDelay * attempts);
            continue;
          }
        }
        return null;
      } catch (_) {
        attempts++;
        if (attempts < _maxRetries) await Future.delayed(_retryDelay * attempts);
      }
    }
    return null;
  }

  /// Vérifie le statut d'un paiement GeniusPay.
  static Future<GeniusPayStatusResult?> checkStatus(String reference) async {
    try {
      final token = await BabifixUserStore.getApiToken();
      final response = await http
          .get(
            Uri.parse('${babifixApiBaseUrl()}/api/paiements/geniuspay/status/$reference/'),
            headers: {if (token != null) 'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return GeniusPayStatusResult(
          reference:    data['reference']  as String? ?? reference,
          status:       data['status']     as String? ?? 'pending',
          amount:       data['amount']     as String? ?? '0',
          paymentRef:   data['payment_ref'] as String? ?? '',
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}

class GeniusPayInitResult {
  final String transactionId;
  final int paymentId;
  final String paymentUrl;
  final String checkoutUrl;
  final String status;
  final String message;

  const GeniusPayInitResult({
    required this.transactionId,
    required this.paymentId,
    required this.paymentUrl,
    required this.checkoutUrl,
    required this.status,
    required this.message,
  });

  bool get hasDirectUrl => paymentUrl.isNotEmpty;
  bool get hasCheckoutUrl => checkoutUrl.isNotEmpty;
  String get bestUrl => paymentUrl.isNotEmpty ? paymentUrl : checkoutUrl;
}

class GeniusPayStatusResult {
  final String reference;
  final String status;
  final String amount;
  final String paymentRef;

  const GeniusPayStatusResult({
    required this.reference,
    required this.status,
    required this.amount,
    required this.paymentRef,
  });

  bool get isCompleted => status == 'completed';
  bool get isPending   => status == 'pending' || status == 'processing';
  bool get isFailed    => status == 'failed' || status == 'cancelled' || status == 'expired';
}
