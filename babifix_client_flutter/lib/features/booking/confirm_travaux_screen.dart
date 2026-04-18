import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../babifix_api_config.dart';
import '../../user_store.dart';

class ConfirmTravauxScreen extends StatefulWidget {
  final String reservationReference;
  final VoidCallback onBack;
  final VoidCallback onConfirmed;

  const ConfirmTravauxScreen({
    super.key,
    required this.reservationReference,
    required this.onBack,
    required this.onConfirmed,
  });

  @override
  State<ConfirmTravauxScreen> createState() => _ConfirmTravauxScreenState();
}

class _ConfirmTravauxScreenState extends State<ConfirmTravauxScreen> {
  bool _loading = true;
  bool _confirming = false;
  String? _error;
  Map<String, dynamic>? _reservation;

  @override
  void initState() {
    super.initState();
    _loadReservation();
  }

  Future<void> _loadReservation() async {
    final token = await BabifixUserStore.getApiToken();
    if (token == null) {
      setState(() {
        _loading = false;
        _error = 'Non connecté';
      });
      return;
    }

    try {
      final uri = Uri.parse(
        '${babifixApiBaseUrl()}/api/client/reservations/${widget.reservationReference}/detail',
      );
      final resp = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() {
          _reservation = data;
          _loading = false;
        });
      } else {
        setState(() {
          _loading = false;
          _error = 'Erreur: ${resp.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _confirmTravaux() async {
    if (_confirming) return;
    setState(() => _confirming = true);

    final token = await BabifixUserStore.getApiToken();
    if (token == null) return;

    try {
      final uri = Uri.parse(
        '${babifixApiBaseUrl()}/api/client/demandes/${widget.reservationReference}/confirmer-travaux',
      );
      final resp = await http.post(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (resp.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Travaux confirmés!')));
          widget.onConfirmed();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Erreur: ${resp.statusCode}')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    }

    if (mounted) setState(() => _confirming = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
        title: const Text('Confirmer les travaux'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    final montant = (_reservation?['montant'] as num?)?.toDouble() ?? 0;
    final paymentType = _reservation?['payment_type'] as String? ?? 'ESPECES';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_outline,
              color: Color(0xFF2563EB),
              size: 48,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Les travaux sont terminés',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Confirmez la réception des travaux pour procéder au paiement.',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1628),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Montant à payer',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    Text(
                      '${montant.toStringAsFixed(0)} FCA',
                      style: const TextStyle(
                        color: Color(0xFF4CC9F0),
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Mode de paiement',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    Text(
                      paymentType == 'MOBILE_MONEY'
                          ? 'Mobile Money'
                          : 'Espèces',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.amber),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Le paiement sera déclenché après votre confirmation.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Signaler un problème'),
                        content: const Text(
                          'Utilisez cette option si les travaux ne sont pas conformes au devis.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Annuler'),
                          ),
                          FilledButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Litige ouvert. Un médiateur vous contactera.',
                                  ),
                                ),
                              );
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            child: const Text('Ouvrir un litige'),
                          ),
                        ],
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                  ),
                  child: const Text('Signaler un problème'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _confirming ? null : _confirmTravaux,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _confirming
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Confirmer et payer',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
