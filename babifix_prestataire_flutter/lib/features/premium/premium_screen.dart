import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../shared/auth_utils.dart';
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

  bool _isPremium = false;
  String _currentTier = 'standard';
  String? _premiumUntil;
  int _daysRemaining = 0;
  double _commissionEffective = 18;

  List<Map<String, dynamic>> _tiers = [];

  static const _tierColors = {
    'bronze': Color(0xFFCD7F32),
    'silver': Color(0xFFC0C0C0),
    'gold': Color(0xFFF59E0B),
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
            content: Text('Abonnement ${tier.toUpperCase()} active avec succes'),
            backgroundColor: _tierColors[tier] ?? BabifixDesign.cyan,
          ),
        );
        await _load();
      } else if (resp.statusCode == 402) {
        _showInsufficientFundsDialog(data);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['error'] ?? 'Erreur'), backgroundColor: BabifixDesign.error),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e'), backgroundColor: BabifixDesign.error),
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
        backgroundColor: const Color(0xFF152A45),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Solde insuffisant',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Prix de l\'abonnement : ${price.toStringAsFixed(0)} FCFA\n'
          'Votre solde : ${solde.toStringAsFixed(0)} FCFA\n\n'
          'Rechargez votre wallet ou payez via Mobile Money.',
          style: const TextStyle(color: Color(0xFFB4C2D9), height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fermer', style: TextStyle(color: BabifixDesign.cyan)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BabifixDesign.navy,
      appBar: AppBar(
        title: const Text(
          'BABIFIX Premium',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: BabifixDesign.cyan))
          : _error != null
          ? _buildError()
          : RefreshIndicator(
              onRefresh: _load,
              color: BabifixDesign.cyan,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_isPremium) _buildCurrentStatus(),
                    if (!_isPremium) _buildCommissionInfo(),
                    const SizedBox(height: 8),
                    const Text(
                      'Formules disponibles',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ..._tiers.map((tier) => _buildTierCard(tier)),
                    const SizedBox(height: 20),
                    _buildPaymentNote(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: BabifixDesign.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline, size: 48, color: BabifixDesign.error),
            ),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Erreur inconnue',
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _load,
              style: FilledButton.styleFrom(
                backgroundColor: BabifixDesign.cyan,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Reessayer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentStatus() {
    final color = _tierColors[_currentTier] ?? BabifixDesign.cyan;
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withValues(alpha: 0.6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.workspace_premium_rounded,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Premium ${_currentTier.toUpperCase()}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$_daysRemaining jours restants',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  'Commission : ${_commissionEffective.toStringAsFixed(0)}%',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommissionInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF152A45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BabifixDesign.warning.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: BabifixDesign.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.info_outline_rounded,
              color: BabifixDesign.warning,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Commission actuelle : ${_commissionEffective.toStringAsFixed(0)}%\nPassez Premium pour reduire votre commission !',
              style: const TextStyle(fontSize: 13, color: Color(0xFFB4C2D9), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTierCard(Map<String, dynamic> tier) {
    final isActive = _isPremium && _currentTier == tier['id'];
    final color = _tierColors[tier['id']] ?? BabifixDesign.cyan;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: isActive
            ? LinearGradient(
                colors: [color.withValues(alpha: 0.15), const Color(0xFF152A45)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: isActive ? null : const Color(0xFF152A45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isActive ? color : const Color(0x1AFFFFFF),
          width: isActive ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    tier['id'] == 'gold'
                        ? Icons.star_rounded
                        : tier['id'] == 'silver'
                            ? Icons.star_half_rounded
                            : Icons.star_border_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tier['name'] ?? '',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: color,
                      ),
                    ),
                    Text(
                      '${(tier['price'] ?? 0).toStringAsFixed(0)} FCFA / mois',
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                    ),
                  ],
                ),
                const Spacer(),
                if (isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'ACTIF',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
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
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.check_circle_rounded, color: color, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            f.toString(),
                            style: const TextStyle(fontSize: 13, color: Color(0xFFCBD5E1)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!isActive) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: _subscribing ? null : () => _subscribe(tier['id']),
                      style: FilledButton.styleFrom(
                        backgroundColor: color,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _subscribing
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : Text(
                              'Souscrire ${tier['name']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentNote() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF152A45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.lightbulb_outline_rounded,
            color: BabifixDesign.cyan,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Le montant est deduit de votre wallet BABIFIX. Si votre solde est insuffisant, vous pourrez payer via Mobile Money.',
              style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
