import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../babifix_api_config.dart';
import '../../shared/auth_utils.dart';
import '../../shared/widgets/babifix_ring_loader.dart';

class PaymentHistoryScreen extends StatefulWidget {
  final dynamic paletteMode;
  const PaymentHistoryScreen({super.key, this.paletteMode});

  @override
  State<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends State<PaymentHistoryScreen> {
  List<Map<String, dynamic>> _payments = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final token = await readStoredApiToken();
      if (token == null) {
        if (mounted) setState(() => _error = 'Non connecté');
        return;
      }
      final res = await http.get(
        Uri.parse('${babifixApiBaseUrl()}/api/prestataire/payments/history/'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final list = (data['payments'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        if (mounted) setState(() { _payments = list; _loading = false; });
      } else {
        if (mounted) setState(() { _error = 'Erreur ${res.statusCode}'; _loading = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _error = 'Impossible de charger'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLight = widget.paletteMode.toString().contains('light');
    final bg = isLight ? const Color(0xFFF8FAFC) : const Color(0xFF0B1B34);
    final card = isLight ? Colors.white : const Color(0xFF152A45);
    final text = isLight ? const Color(0xFF0F172A) : Colors.white;
    final sub = isLight ? const Color(0xFF64748B) : const Color(0xFFB4C2D9);
    const cyan = Color(0xFF4CC9F0);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: isLight ? Colors.white : const Color(0xFF0B1B34),
        foregroundColor: text,
        elevation: 0,
        title: Text('Historique des paiements', style: TextStyle(fontWeight: FontWeight.w800, color: text)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: BabifixRingLoader.cyan(size: 28))
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, size: 48, color: sub),
                        const SizedBox(height: 12),
                        Text(_error!, style: TextStyle(color: sub)),
                        const SizedBox(height: 12),
                        TextButton(onPressed: _load, child: const Text('Réessayer')),
                      ],
                    ),
                  )
                : _payments.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.receipt_long_outlined, size: 64, color: sub),
                            const SizedBox(height: 12),
                            Text('Aucun paiement', style: TextStyle(color: text, fontWeight: FontWeight.w700, fontSize: 16)),
                            const SizedBox(height: 4),
                            Text('Vos paiements apparaîtront ici.', style: TextStyle(color: sub)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _payments.length,
                        itemBuilder: (_, i) {
                          final p = _payments[i];
                          final isCompleted = (p['etat'] as String?) == 'COMPLETE';
                          final date = (p['date'] as String? ?? '').split('T')[0];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: card,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: isLight ? const Color(0xFFE2E8F0) : const Color(0x22FFFFFF)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        p['client_name'] as String? ?? 'Client',
                                        style: TextStyle(fontWeight: FontWeight.w700, color: text),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isCompleted
                                            ? const Color(0xFF059669).withValues(alpha: 0.12)
                                            : const Color(0xFFF59E0B).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        isCompleted ? 'Payé' : 'En attente',
                                        style: TextStyle(
                                          color: isCompleted ? const Color(0xFF059669) : const Color(0xFFD97706),
                                          fontSize: 12, fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(p['service_title'] as String? ?? '', style: TextStyle(color: sub, fontSize: 13)),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text('Réf: ', style: TextStyle(color: sub, fontSize: 11)),
                                    Text(p['reservation_reference'] as String? ?? '', style: TextStyle(color: text, fontSize: 11)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(date, style: TextStyle(color: sub, fontSize: 11)),
                                const SizedBox(height: 10),
                                const Divider(height: 1),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Text('Brut', style: TextStyle(color: sub, fontSize: 12)),
                                    const Spacer(),
                                    Text('${p['montant_brut'] ?? 0} FCFA', style: TextStyle(color: text, fontSize: 12)),
                                  ],
                                ),
                                Row(
                                  children: [
                                    Text('Commission', style: TextStyle(color: sub, fontSize: 12)),
                                    const Spacer(),
                                    Text('-${p['commission'] ?? 0} FCFA', style: const TextStyle(color: Colors.red, fontSize: 12)),
                                  ],
                                ),
                                Row(
                                  children: [
                                    Text('Net reçu', style: TextStyle(fontWeight: FontWeight.w700, color: text, fontSize: 12)),
                                    const Spacer(),
                                    Text('${p['net'] ?? 0} FCFA', style: TextStyle(color: cyan, fontWeight: FontWeight.w800, fontSize: 13)),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}
