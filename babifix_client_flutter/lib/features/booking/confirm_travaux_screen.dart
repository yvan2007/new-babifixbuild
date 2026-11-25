import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../babifix_api_config.dart';
import '../../user_store.dart';
import '../../shared/error_utils.dart';
import '../../shared/widgets/babifix_ring_loader.dart';
import '../../shared/widgets/babifix_snackbar.dart';

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
          _error = apiErrorMessage(resp.body) ?? userFriendlyError(null, resp.statusCode);
        });
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = userFriendlyError(e);
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
        '${babifixApiBaseUrl()}/api/client/reservations/${widget.reservationReference}/confirmer-travaux',
      );
      final resp = await http.post(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (resp.statusCode == 200) {
        if (mounted) {
          showBabifixToast(
        context,
        type: BabifixToastType.success,
        message: 'Travaux confirmés!',
      );
          widget.onConfirmed();
        }
      } else {
        if (mounted) {
          showBabifixToast(
        context,
        type: BabifixToastType.error,
        message: apiErrorMessage(resp.body) ?? userFriendlyError(null, resp.statusCode),
      );
        }
      }
    } catch (e) {
      if (mounted) {
        showBabifixToast(
        context,
        type: BabifixToastType.error,
        message: userFriendlyError(e),
      );
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
          ? const Center(child: BabifixRingLoader.cyan(size: 28))
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
              color: const Color(0xFF4CC9F0).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_outline,
              color: Color(0xFF4CC9F0),
              size: 48,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Les travaux sont terminés',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Vérifiez les photos de l\'artisan et confirmez la réception des travaux.',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          _buildAvantApresShowcase(),
          const SizedBox(height: 24),
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
                      '${montant.toStringAsFixed(0)} francs CFA',
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
                              showBabifixToast(
        context,
        type: BabifixToastType.info,
        message: 'Litige ouvert. Un médiateur vous contactera.',
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
                backgroundColor: const Color(0xFF4CC9F0),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _confirming
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: BabifixRingLoader.cyan(size: 28),
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

  Widget _buildAvantApresShowcase() {
    final avantList = (_reservation?['photos_avant'] as List?)?.cast<String>() ?? [];
    final apresList = (_reservation?['photos_apres'] as List?)?.cast<String>() ?? [];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1E33),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF4CC9F0).withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0A1628).withValues(alpha: 0.5),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_rounded, color: Color(0xFF22C55E), size: 14),
                    SizedBox(width: 4),
                    Text(
                      'CONFORMITÉ BABIFIX',
                      style: TextStyle(
                        color: Color(0xFF22C55E),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              const Text(
                'Preuve visuelle de travail',
                style: TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.history_rounded, size: 13, color: Color(0xFFFF6B00)),
                        SizedBox(width: 4),
                        Text(
                          'AVANT TRAVAUX',
                          style: TextStyle(
                            color: Color(0xFFFF6B00),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _buildPhotoBox(
                      url: avantList.isNotEmpty
                          ? babifixResolveMediaUrl(avantList.first)
                          : null,
                      fallbackIcon: Icons.broken_image_outlined,
                      label: 'État initial',
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.task_alt_rounded, size: 13, color: Color(0xFF22C55E)),
                        SizedBox(width: 4),
                        Text(
                          'RÉSULTAT APRÈS ✓',
                          style: TextStyle(
                            color: Color(0xFF22C55E),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _buildPhotoBox(
                      url: apresList.isNotEmpty
                          ? babifixResolveMediaUrl(apresList.first)
                          : null,
                      fallbackIcon: Icons.check_circle_outline_rounded,
                      label: 'Travaux achevés',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoBox({
    required String? url,
    required IconData fallbackIcon,
    required String label,
  }) {
    return Container(
      height: 110,
      decoration: BoxDecoration(
        color: const Color(0xFF081220),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: url != null && url.isNotEmpty
            ? Image.network(
                url,
                fit: BoxFit.cover,
                width: double.infinity,
                errorBuilder: (_, __, ___) => _buildPlaceholderPhoto(fallbackIcon, label),
              )
            : _buildPlaceholderPhoto(fallbackIcon, label),
      ),
    );
  }

  Widget _buildPlaceholderPhoto(IconData icon, String label) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white38, size: 28),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
        ],
      ),
    );
  }
}
