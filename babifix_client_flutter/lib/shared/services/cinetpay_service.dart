import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:babifix_client_flutter/babifix_api_config.dart';
import 'package:babifix_client_flutter/user_store.dart';

class CircuitBreaker {
  static int _failureCount = 0;
  static const int _maxFailures = 3;
  static const Duration _resetTimeout = Duration(minutes: 1);
  static DateTime? _lastFailure;

  static bool get isOpen => _failureCount >= _maxFailures;

  static void recordSuccess() {
    _failureCount = 0;
    _lastFailure = null;
  }

  static void recordFailure() {
    _failureCount++;
    _lastFailure = DateTime.now();
    if (_failureCount >= _maxFailures) {
      _lastFailure = DateTime.now();
    }
  }

  static bool get isHalfOpen {
    if (_failureCount < _maxFailures) return false;
    if (_lastFailure == null) return true;
    return DateTime.now().difference(_lastFailure!) > _resetTimeout;
  }
}

class CinetPayService {
  static const int maxRetries = 3;
  static const Duration retryDelay = Duration(seconds: 2);

  static Future<CinetPayInitResult?> initiatePayment({
    required int reservationId,
    required int montant,
    required String operator,
    required String phone,
  }) async {
    if (CircuitBreaker.isOpen && !CircuitBreaker.isHalfOpen) {
      throw CinetPayException(
        'Service temporairement indisponible. Veuillez réessayer dans quelques minutes.',
        isCircuitBreakerOpen: true,
      );
    }

    int attempts = 0;
    while (attempts < maxRetries) {
      try {
        final token = await BabifixUserStore.getApiToken();
        final response = await http
            .post(
              Uri.parse(
                '${babifixApiBaseUrl()}/api/paiements/cinetpay/initiate/',
              ),
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
            )
            .timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          CircuitBreaker.recordSuccess();
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          return CinetPayInitResult(
            transactionId: data['transaction_id'] as String,
            paymentId: data['payment_id'] as int,
            status: data['status'] as String? ?? 'PENDING',
          );
        }

        if (response.statusCode >= 500) {
          attempts++;
          if (attempts < maxRetries) {
            await Future.delayed(retryDelay * attempts);
            continue;
          }
        }
        return null;
      } catch (e) {
        CircuitBreaker.recordFailure();
        attempts++;
        if (attempts < maxRetries) {
          await Future.delayed(retryDelay * attempts);
        }
      }
    }

    throw CinetPayException(
      'Échec du paiement après $maxRetries tentatives. Veuillez réessayer.',
    );
  }

  static Future<CinetPayStatusResult?> checkPaymentStatus(
    String transactionId,
  ) async {
    if (CircuitBreaker.isOpen && !CircuitBreaker.isHalfOpen) {
      throw CinetPayException(
        'Service temporairement indisponible.',
        isCircuitBreakerOpen: true,
      );
    }

    try {
      final token = await BabifixUserStore.getApiToken();
      final response = await http
          .get(
            Uri.parse(
              '${babifixApiBaseUrl()}/api/paiements/cinetpay/status/$transactionId/',
            ),
            headers: {if (token != null) 'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 10));

      CircuitBreaker.recordSuccess();

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
      CircuitBreaker.recordFailure();
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

class CinetPayException implements Exception {
  final String message;
  final bool isCircuitBreakerOpen;

  CinetPayException(this.message, {this.isCircuitBreakerOpen = false});

  @override
  String toString() => message;
}
