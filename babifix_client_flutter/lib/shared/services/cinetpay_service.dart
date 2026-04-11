import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:babifix_client_flutter/babifix_api_config.dart';
import 'package:babifix_client_flutter/user_store.dart';

class CinetPayService {
  static Future<CinetPayInitResult?> initiatePayment({
    required int reservationId,
    required int montant,
    required String operator,
    required String phone,
  }) async {
    try {
      final token = await BabifixUserStore.getApiToken();
      final response = await http.post(
        Uri.parse('${babifixApiBaseUrl()}/api/paiements/cinetpay/initiate/'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'reservation': reservationId,
          'montant': montant,
          'operator': operator,
          'phone': phone,
          'mode_paiement': 'MOBILE_MONEY',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return CinetPayInitResult(
          transactionId: data['transaction_id'] as String,
          paymentId: data['payment_id'] as int,
          status: data['status'] as String? ?? 'PENDING',
        );
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<CinetPayStatusResult?> checkPaymentStatus(
    String transactionId,
  ) async {
    try {
      final token = await BabifixUserStore.getApiToken();
      final response = await http.get(
        Uri.parse(
          '${babifixApiBaseUrl()}/api/paiements/cinetpay/status/$transactionId/',
        ),
        headers: {if (token != null) 'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return CinetPayStatusResult(
          transactionId: data['transaction_id'] as String,
          status: data['status'] as String,
          amount: data['amount'] as int,
          reference: data['reference'] as String,
        );
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}

class CinetPayInitResult {
  final String transactionId;
  final int paymentId;
  final String status;

  CinetPayInitResult({
    required this.transactionId,
    required this.paymentId,
    required this.status,
  });
}

class CinetPayStatusResult {
  final String transactionId;
  final String status;
  final int amount;
  final String reference;

  CinetPayStatusResult({
    required this.transactionId,
    required this.status,
    required this.amount,
    required this.reference,
  });

  bool get isSuccess => status == 'SUCCESS';
  bool get isPending => status == 'PENDING';
  bool get isFailed => status == 'FAILED';
}
