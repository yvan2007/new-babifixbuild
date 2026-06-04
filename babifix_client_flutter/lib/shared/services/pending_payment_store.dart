import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Représente un paiement Mobile Money lancé mais pas encore confirmé.
///
/// On le persiste localement dès qu'on obtient la référence GeniusPay, afin
/// de pouvoir REPRENDRE le suivi si l'utilisateur ferme l'application (ou si
/// elle plante) pendant que le paiement est en cours côté opérateur.
class PendingPayment {
  final String reference; // identifiant de transaction GeniusPay
  final String reservationRef; // réservation concernée
  final double amount;
  final String operator; // ORANGE_MONEY / MTN_MOMO / WAVE / MOOV
  final String kind; // 'acompte' | 'solde' | 'post'
  final int startedAtMs; // horodatage de départ (epoch ms)

  const PendingPayment({
    required this.reference,
    required this.reservationRef,
    required this.amount,
    required this.operator,
    required this.kind,
    required this.startedAtMs,
  });

  Map<String, dynamic> toJson() => {
        'reference': reference,
        'reservationRef': reservationRef,
        'amount': amount,
        'operator': operator,
        'kind': kind,
        'startedAtMs': startedAtMs,
      };

  factory PendingPayment.fromJson(Map<String, dynamic> j) => PendingPayment(
        reference: j['reference'] as String? ?? '',
        reservationRef: j['reservationRef'] as String? ?? '',
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        operator: j['operator'] as String? ?? '',
        kind: j['kind'] as String? ?? 'post',
        startedAtMs: j['startedAtMs'] as int? ?? 0,
      );

  /// Âge du paiement en cours. Au-delà d'un certain délai, on considère qu'il
  /// est périmé (l'opérateur l'a expiré) et on cesse de le proposer à reprendre.
  Duration get age =>
      Duration(milliseconds: DateTime.now().millisecondsSinceEpoch - startedAtMs);
}

/// Stockage d'UN seul paiement en cours à la fois (un client ne paie qu'une
/// chose à la fois). Basé sur SharedPreferences — donnée non sensible
/// (référence publique, pas d'identifiant Mobile Money).
class PendingPaymentStore {
  static const String _key = 'babifix_pending_payment_v1';

  /// Au-delà de cette durée, un paiement en attente est considéré périmé.
  static const Duration maxResumeWindow = Duration(minutes: 15);

  static Future<void> save(PendingPayment p) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(p.toJson()));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// Lit le paiement en cours s'il existe ET n'est pas périmé.
  /// Si périmé, le nettoie automatiquement et renvoie null.
  static Future<PendingPayment?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final p = PendingPayment.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      if (p.reference.isEmpty || p.age > maxResumeWindow) {
        await clear();
        return null;
      }
      return p;
    } catch (_) {
      await clear();
      return null;
    }
  }

  /// Paiement en cours pour une réservation précise (ou null).
  static Future<PendingPayment?> readForReservation(String reservationRef) async {
    final p = await read();
    if (p == null) return null;
    return p.reservationRef == reservationRef ? p : null;
  }
}
