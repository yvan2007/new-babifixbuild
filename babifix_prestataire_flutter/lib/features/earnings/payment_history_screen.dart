import 'dart:convert';
import 'package:flutter/material.dart';
import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../shared/auth_utils.dart';
import '../../shared/widgets/babifix_button.dart';
import '../../shared/widgets/babifix_skeleton.dart';

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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = await readStoredApiToken();
      if (token == null) {
        if (mounted) {
          setState(() {
            _error = 'Non connecte';
            _loading = false;
          });
        }
        return;
      }
      final res = await babifixAuthGet(
        '${babifixApiBaseUrl()}/api/prestataire/payments/history/',
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final list =
            (data['payments'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        if (mounted) {
          setState(() {
            _payments = list;
            _loading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _error = 'Erreur ${res.statusCode}';
            _loading = false;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Impossible de charger';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final card = BabifixDesign.surfaceOf(context);
    final border = BabifixDesign.borderOf(context);
    final text = BabifixDesign.textPrimaryOf(context);
    final sub = BabifixDesign.textMutedOf(context);
    final isDark = BabifixDesign.isDark(context);
    final accent = isDark ? BabifixDesign.cyan : BabifixDesign.ciOrange;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Historique des paiements',
          style: TextStyle(fontWeight: FontWeight.w800, color: text),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? BabifixSkeletonScope(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: List.generate(
                    5,
                    (_) => const BabifixSkeletonCard(lines: 2),
                  ),
                ),
              )
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline_rounded, size: 48, color: sub),
                          const SizedBox(height: 12),
                          Text(_error!, style: TextStyle(color: sub)),
                          const SizedBox(height: 16),
                          BabifixButton(
                            label: 'Reessayer',
                            icon: Icons.refresh_rounded,
                            onPressed: _load,
                          ),
                        ],
                      ),
                    ),
                  )
                : _payments.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.receipt_long_outlined, size: 58, color: sub),
                            const SizedBox(height: 12),
                            Text(
                              'Aucun paiement',
                              style: TextStyle(
                                color: text,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Vos paiements apparaitront ici.',
                              style: TextStyle(color: sub),
                            ),
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
                            padding: const EdgeInsets.all(15),
                            decoration: BoxDecoration(
                              color: card,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        p['client_name'] as String? ?? 'Client',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14.5,
                                          color: text,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: (isCompleted
                                                ? BabifixDesign.success
                                                : BabifixDesign.warning)
                                            .withValues(alpha: 0.14),
                                        borderRadius: BorderRadius.circular(99),
                                      ),
                                      child: Text(
                                        isCompleted ? 'Paye' : 'En attente',
                                        style: TextStyle(
                                          color: isCompleted
                                              ? BabifixDesign.success
                                              : BabifixDesign.warning,
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  p['service_title'] as String? ?? '',
                                  style: TextStyle(color: sub, fontSize: 13),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(
                                      'Ref: ${p['reservation_reference'] as String? ?? ''}',
                                      style: TextStyle(
                                        color: sub,
                                        fontSize: 11.5,
                                        fontFeatures: BabifixDesign.tabularFigures,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      date,
                                      style: TextStyle(
                                        color: sub,
                                        fontSize: 11.5,
                                        fontFeatures: BabifixDesign.tabularFigures,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Divider(height: 1, color: border),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Text('Brut', style: TextStyle(color: sub, fontSize: 12.5)),
                                    const Spacer(),
                                    Text(
                                      '${p['montant_brut'] ?? 0} FCFA',
                                      style: TextStyle(
                                        color: text,
                                        fontSize: 12.5,
                                        fontFeatures: BabifixDesign.tabularFigures,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    Text('Commission', style: TextStyle(color: sub, fontSize: 12.5)),
                                    const Spacer(),
                                    Text(
                                      '-${p['commission'] ?? 0} FCFA',
                                      style: const TextStyle(
                                        color: BabifixDesign.error,
                                        fontSize: 12.5,
                                        fontFeatures: BabifixDesign.tabularFigures,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    Text(
                                      'Net recu',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: text,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      '${p['net'] ?? 0} FCFA',
                                      style: TextStyle(
                                        color: accent,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13.5,
                                        fontFeatures: BabifixDesign.tabularFigures,
                                      ),
                                    ),
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
