import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../shared/services/babifix_user_store.dart';
import '../../shared/widgets/babifix_page_route.dart';

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  bool _loading = true;
  bool _subscribing = false;
  String? _error;

  // Current subscription
  bool _isPremium = false;
  String _currentTier = 'standard';
  String? _premiumUntil;
  int _daysRemaining = 0;
  double _commissionEffective = 18;

  // Available tiers
  List<Map<String, dynamic>> _tiers = [];

  static const _tierColors = {
    'bronze': Color(0xFFCD7F32),
    'silver': Color(0xFF9E9E9E),
    'gold': Color(0xFFF9A825),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final [statusResp, tiersResp] = await Future.wait<http.Response>([
        BabifixUserStore.authGet('/api/prestataire/premium/subscribe/'),
        BabifixUserStore.authGet('/api/prestataire/premium/tiers/'),
      ]);

      if (statusResp.statusCode == 200) {
        final d = jsonDecode(statusResp.body);
        setState(() {
          _isPremium = d['is_premium'] ?? false;
          _currentTier = d['tier'] ?? 'standard';
          _premiumUntil = d['premium_until'];
          _daysRemaining = d['days_remaining'] ?? 0;
          _commissionEffective = (d['commission_effective'] ?? 18).toDouble();
        });
      }
      if (tiersResp.statusCode == 200) {
        final d = jsonDecode(tiersResp.body);
        setState(() { _tiers = List<Map<String, dynamic>>.from(d['tiers'] ?? []); });
      }
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      setState(() { _loading = false; });
    }
  }

  Future<void> _subscribe(String tier) async {
    setState(() { _subscribing = true; });
    try {
      final resp = await BabifixUserStore.authPost(
        '/api/prestataire/premium/subscribe/',
        body: jsonEncode({'tier': tier, 'duration_days': 30}),
      );
      final data = jsonDecode(resp.body);
      if (resp.statusCode == 200 && data['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 Abonnement ${tier.toUpperCase()} activé !'),
            backgroundColor: _tierColors[tier] ?? const Color(0xFF1565C0),
          ),
        );
        await _load();
      } else if (resp.statusCode == 402) {
        _showInsufficientFundsDialog(data);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['error'] ?? 'Erreur'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() { _subscribing = false; });
    }
  }

  void _showInsufficientFundsDialog(Map data) {
    final price = (data['price'] ?? 0).toDouble();
    final solde = (data['solde_actuel'] ?? 0).toDouble();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Solde insuffisant'),
        content: Text(
          'Prix de l\'abonnement : ${price.toStringAsFixed(0)} FCFA\n'
          'Votre solde : ${solde.toStringAsFixed(0)} FCFA\n\n'
          'Rechargez votre wallet ou payez via Mobile Money.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0D1B2A) : const Color(0xFFF0F4FF);
    final cardBg = isDark ? const Color(0xFF1A2740) : Colors.white;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('BABIFIX Premium'),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Current status
                    if (_isPremium)
                      Container(
                        padding: const EdgeInsets.all(20),
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _tierColors[_currentTier] ?? const Color(0xFF1565C0),
                              (_tierColors[_currentTier] ?? const Color(0xFF1565C0)).withOpacity(0.6),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 40),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Premium ${_currentTier.toUpperCase()}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                                  Text('$_daysRemaining jours restants', style: const TextStyle(color: Colors.white70)),
                                  Text('Commission : ${_commissionEffective.toStringAsFixed(0)}%', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Commission sans premium
                    if (!_isPremium)
                      Container(
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.withOpacity(0.2)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline_rounded, color: Colors.orange[700]),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Commission actuelle : ${_commissionEffective.toStringAsFixed(0)}%\nPassez Premium pour réduire votre commission !',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Tiers
                    ..._tiers.map((tier) {
                      final isActive = _isPremium && _currentTier == tier['id'];
                      final color = _tierColors[tier['id']] ?? const Color(0xFF1565C0);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(20),
                          border: isActive ? Border.all(color: color, width: 2) : null,
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12)],
                        ),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.1),
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                                    child: Icon(
                                      tier['id'] == 'gold'
                                          ? Icons.star_rounded
                                          : tier['id'] == 'silver'
                                              ? Icons.star_half_rounded
                                              : Icons.star_border_rounded,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(tier['name'] ?? '', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: color)),
                                      Text('${(tier['price'] ?? 0).toStringAsFixed(0)} FCFA / mois', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                                    ],
                                  ),
                                  const Spacer(),
                                  if (isActive)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
                                      child: const Text('ACTIF', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                    ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                children: [
                                  ...((tier['features'] as List?) ?? []).map(
                                    (f) => Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Row(
                                        children: [
                                          Icon(Icons.check_circle_rounded, color: color, size: 18),
                                          const SizedBox(width: 10),
                                          Expanded(child: Text(f.toString(), style: const TextStyle(fontSize: 13))),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  if (!isActive)
                                    SizedBox(
                                      width: double.infinity,
                                      child: FilledButton(
                                        onPressed: _subscribing ? null : () => _subscribe(tier['id']),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: color,
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                        child: _subscribing
                                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                            : Text('Souscrire ${tier['name']}'),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),

                    // Note paiement
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1565C0).withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        '💡 Le montant est déduit de votre wallet BABIFIX. Si votre solde est insuffisant, vous pourrez payer via Mobile Money.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
