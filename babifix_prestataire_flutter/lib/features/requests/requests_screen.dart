import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../babifix_api_config.dart';
import '../../shared/auth_utils.dart';
import '../../shared/widgets/payment_method_logo.dart';
import 'rate_client_screen.dart';

class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  bool loading = false;
  String? authToken;
  late List<_RequestItem> items;

  @override
  void initState() {
    super.initState();
    items = <_RequestItem>[];
    _initSession();
  }

  /// Align\u00e9 UML / API : pending, active (Confirm\u00e9e/En cours), completed (Termin\u00e9e), refused.
  static String _bucketFromApi(String raw) {
    final t = raw.trim();
    if (t == 'Annulee' || t.toLowerCase().contains('annul')) return 'refused';
    if (t == 'En attente' || t.toLowerCase().contains('attente')) return 'pending';
    if (t == 'Terminee' || t.toLowerCase().contains('termin')) return 'completed';
    return 'active';
  }

  static String _labelStatut(String apiStatus) {
    switch (apiStatus) {
      case 'Confirmee':
        return 'Confirm\u00e9e';
      case 'Terminee':
        return 'Termin\u00e9e';
      case 'Annulee':
        return 'Annul\u00e9e';
      case 'En cours':
        return 'En cours';
      default:
        return apiStatus;
    }
  }

  bool _canConfirmCash(_RequestItem it) {
    return it.paymentType == 'ESPECES' &&
        it.cashFlowStatus == 'pending_prestataire' &&
        (it.apiStatus == 'Terminee');
  }

  @override
  Widget build(BuildContext context) {
    final pending = items.where((e) => e.status == 'pending').toList();
    final active = items.where((e) => e.status == 'active').toList();
    final completed = items.where((e) => e.status == 'completed').toList();
    final refused = items.where((e) => e.status == 'refused').toList();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: widget.onBack, icon: const Icon(Icons.arrow_back)),
        title: const Text('Exigences'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (loading) const LinearProgressIndicator(),
          Text('Nouvelles demandes (${pending.length})', style: const TextStyle(fontWeight: FontWeight.w800)),
          if (pending.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.swipe_rounded, size: 14, color: Color(0xFF94A3B8)),
                const SizedBox(width: 4),
                Text(
                  'Glissez \u2192 pour accepter  \u2022  \u2190 pour refuser',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          ...pending.map((item) => _buildCard(item)),
          const SizedBox(height: 8),
          const Text('Confirm\u00e9es / en cours', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          ...active.map((item) => _buildCard(item)),
          if (completed.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Termin\u00e9es (${completed.length})', style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            ...completed.map((item) => _buildCard(item)),
          ],
          if (refused.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Annul\u00e9es (${refused.length})', style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            ...refused.map((item) => _buildCard(item)),
          ],
        ],
      ),
    );
  }

  Widget _buildCard(_RequestItem it) {
    final card = _buildCardInner(it);
    if (it.status != 'pending') return card;
    return Dismissible(
      key: ValueKey(it.reference),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        final decision = direction == DismissDirection.startToEnd ? 'accept' : 'refuse';
        await _decide(it, decision);
        return false; // list updates via setState in _decide
      },
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: const Color(0xFF22C55E),
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.centerLeft,
        child: const Row(
          children: [
            Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 28),
            SizedBox(width: 8),
            Text('Accepter', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
          ],
        ),
      ),
      secondaryBackground: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444),
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.centerRight,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('Refuser', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
            SizedBox(width: 8),
            Icon(Icons.cancel_outlined, color: Colors.white, size: 28),
          ],
        ),
      ),
      child: card,
    );
  }

  Widget _buildCardInner(_RequestItem it) {
    final tagText = _labelStatut(it.apiStatus);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(it.client, style: const TextStyle(fontWeight: FontWeight.w700))),
              _Tag(text: tagText),
            ],
          ),
          const SizedBox(height: 4),
          Text(it.service, style: const TextStyle(color: Color(0xFF4B5563))),
          const SizedBox(height: 6),
          Text('${it.date} - ${it.hour}'),
          const SizedBox(height: 4),
          Text(it.address, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
          const SizedBox(height: 4),
          Text(it.description, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
          if (it.paymentType.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (it.paymentType == 'MOBILE_MONEY' && it.mobileMoneyOperator.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: BabifixPaymentMethodLogo(
                        methodId: it.mobileMoneyOperator,
                        height: 22,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      'Paiement : ${_paymentLabel(it.paymentType, it.mobileMoneyOperator)}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.star, size: 15, color: Color(0xFFF59E0B)),
              Text('${it.rating}', style: const TextStyle(fontSize: 12)),
              const Spacer(),
              Text(it.amount, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0284C7))),
            ],
          ),
          if (it.status == 'pending') ...[
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton(
                  onPressed: () => _decide(it, 'refuse'),
                  child: const Text('Refuser'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => _decide(it, 'accept'),
                  child: const Text('Accepter'),
                ),
              ],
            ),
          ],
          if (it.status == 'active') ...[
            const SizedBox(height: 8),
            if (it.apiStatus == 'Confirmee')
              FilledButton.icon(
                onPressed: () => _postReservationStatus(it, 'En cours'),
                icon: const Icon(Icons.play_arrow, size: 20),
                label: const Text('D\u00e9marrer la prestation'),
              ),
            if (it.apiStatus == 'En cours')
              FilledButton.icon(
                onPressed: () => _postReservationStatus(it, 'Terminee'),
                icon: const Icon(Icons.check_circle_outline, size: 20),
                label: const Text('Terminer la prestation'),
              ),
          ],
          if (it.status == 'completed' && _canConfirmCash(it)) ...[
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: () => _confirmCashPayment(it),
              child: const Text('Confirmer r\u00e9ception des esp\u00e8ces'),
            ),
          ],
          if (it.status == 'completed') ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => RateClientScreen(
                    reservationRef: it.reference,
                    clientName: it.client,
                  ),
                ),
              ),
              icon: const Icon(Icons.star_border_rounded, size: 18),
              label: const Text('Évaluer le client'),
            ),
          ],
        ],
      ),
    );
  }

  String _paymentLabel(String code, [String mobileOp = '']) {
    switch (code) {
      case 'ESPECES':
        return 'Esp\u00e8ces';
      case 'MOBILE_MONEY':
        final op = _mobileMoneyOpLabel(mobileOp);
        return op.isEmpty ? 'Mobile Money' : 'Mobile Money ($op)';
      case 'CARTE':
        return 'Carte';
      default:
        return code;
    }
  }

  String _mobileMoneyOpLabel(String op) {
    switch (op) {
      case 'ORANGE_MONEY':
        return 'Orange Money';
      case 'MTN_MOMO':
        return 'MTN MoMo';
      case 'WAVE':
        return 'Wave';
      case 'MOOV':
        return 'Moov';
      default:
        return '';
    }
  }

  Future<void> _initSession() async {
    authToken = await readStoredApiToken();
    babifixRegisterFcm(authToken);
    await _loadRequests();
  }

  Future<void> _loadRequests() async {
    if (authToken == null) return;
    setState(() => loading = true);
    try {
      final res = await http.get(
        Uri.parse('${babifixApiBaseUrl()}/api/prestataire/requests'),
        headers: {'Authorization': 'Bearer $authToken'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final remote = (data['items'] as List<dynamic>? ?? []).map((e) {
          final raw = '${e['status']}';
          final bucket = _RequestsScreenState._bucketFromApi(raw);
          final pay = '${e['payment_type'] ?? ''}';
          final mmOp = '${e['mobile_money_operator'] ?? ''}';
          final cash = '${e['cash_flow_status'] ?? ''}';
          return _RequestItem(
            reference: '${e['reference']}',
            client: '${e['client']}',
            service: '${e['service']}',
            date: '${e['date']}',
            hour: '${e['hour']}',
            amount: '${e['amount']}',
            address: '${e['address']}',
            description: '${e['description']}',
            rating: (e['rating'] as num?)?.toDouble() ?? 0,
            status: bucket,
            apiStatus: raw,
            paymentType: pay,
            mobileMoneyOperator: mmOp,
            cashFlowStatus: cash,
          );
        }).toList();
        setState(() => items = remote);
      }
    } catch (_) {
      if (mounted) setState(() => items = []);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _applyStatusFromApi(_RequestItem item, String newApiStatus) {
    item.apiStatus = newApiStatus;
    item.status = _RequestsScreenState._bucketFromApi(newApiStatus);
  }

  Future<void> _decide(_RequestItem item, String decision) async {
    if (authToken == null) return;
    try {
      final res = await http.post(
        Uri.parse('${babifixApiBaseUrl()}/api/prestataire/requests/${item.reference}/decision'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({'decision': decision}),
      );
      if (res.statusCode == 200 && mounted) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final st = '${body['status'] ?? (decision == 'accept' ? 'Confirmee' : 'Annulee')}';
        setState(() => _applyStatusFromApi(item, st));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Action impossible hors connexion API')),
        );
      }
    }
  }

  Future<void> _postReservationStatus(_RequestItem item, String newStatus) async {
    if (authToken == null) return;
    try {
      final res = await http.post(
        Uri.parse('${babifixApiBaseUrl()}/api/prestataire/requests/${item.reference}/status'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({'status': newStatus}),
      );
      if (res.statusCode == 200 && mounted) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final st = '${body['status'] ?? newStatus}';
        setState(() => _applyStatusFromApi(item, st));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Statut : ${_RequestsScreenState._labelStatut(st)}')),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur ${res.statusCode}')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible de mettre \u00e0 jour le statut')),
        );
      }
    }
  }

  Future<void> _confirmCashPayment(_RequestItem item) async {
    if (authToken == null) return;
    try {
      final res = await http.post(
        Uri.parse('${babifixApiBaseUrl()}/api/prestataire/requests/${item.reference}/cash-confirm'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
      );
      if (res.statusCode == 200 && mounted) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final cfs = '${body['cash_flow_status'] ?? 'pending_admin'}';
        setState(() => item.cashFlowStatus = cfs);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Esp\u00e8ces confirm\u00e9es \u2014 en attente validation admin')),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur ${res.statusCode}')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Confirmation impossible')),
        );
      }
    }
  }
}

class _RequestItem {
  _RequestItem({
    required this.reference,
    required this.client,
    required this.service,
    required this.date,
    required this.hour,
    required this.amount,
    required this.address,
    required this.description,
    required this.rating,
    required this.status,
    this.apiStatus = 'En attente',
    this.paymentType = '',
    this.mobileMoneyOperator = '',
    this.cashFlowStatus = '',
  });

  final String reference;
  final String client;
  final String service;
  final String date;
  final String hour;
  final String amount;
  final String address;
  final String description;
  final double rating;
  /// pending | active | completed | refused
  String status;
  /// Statut brut API (En attente, Confirmee, En cours, Terminee, Annulee)
  String apiStatus;
  String paymentType;
  String mobileMoneyOperator;
  String cashFlowStatus;
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = text.toLowerCase();
    late Color bg;
    late Color fg;
    if (t.contains('attente')) {
      bg = const Color(0xFFFEF3C7);
      fg = const Color(0xFF92400E);
    } else if (t.contains('annul')) {
      bg = const Color(0xFFFEE2E2);
      fg = const Color(0xFF991B1B);
    } else if (t.contains('termin')) {
      bg = const Color(0xFFDCFCE7);
      fg = const Color(0xFF166534);
    } else if (t.contains('cours')) {
      bg = const Color(0xFFE0E7FF);
      fg = const Color(0xFF3730A3);
    } else if (t.contains('confirm')) {
      bg = const Color(0xFFDBEAFE);
      fg = const Color(0xFF1D4ED8);
    } else {
      bg = const Color(0xFFF3F4F6);
      fg = const Color(0xFF374151);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w600)),
    );
  }
}
