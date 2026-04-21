import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../babifix_api_config.dart';
import '../../shared/auth_utils.dart' show readStoredApiToken;

class WaitingPaymentScreen extends StatefulWidget {
  final String reservationReference;
  final VoidCallback onBack;
  final VoidCallback onPaymentReceived;
  final VoidCallback onCancelled;

  const WaitingPaymentScreen({
    super.key,
    required this.reservationReference,
    required this.onBack,
    required this.onPaymentReceived,
    required this.onCancelled,
  });

  @override
  State<WaitingPaymentScreen> createState() => _WaitingPaymentScreenState();
}

class _WaitingPaymentScreenState extends State<WaitingPaymentScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _reservation;
  Timer? _pollTimer;
  late AnimationController _animController;
  late Animation<double> _pulseAnimation;

  static const _navy = Color(0xFF0F172A);
  static const _emerald = Color(0xFF10B981);
  static const _amber = Color(0xFFF59E0B);
  static const _slate50 = Color(0xFFF8FAFC);
  static const _slate400 = Color(0xFF94A3B8);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
    _loadReservation();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _checkStatus(),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadReservation() async {
    final token = await readStoredApiToken();
    if (token == null) {
      setState(() {
        _loading = false;
        _error = 'Non connecté';
      });
      return;
    }
    try {
      final res = await http.get(
        Uri.parse('${babifixApiBaseUrl()}/api/prestataire/requests/'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final requests = data['requests'] as List<dynamic>? ?? [];
        final found = requests.cast<Map<String, dynamic>>().firstWhere(
          (r) => r['reference'] == widget.reservationReference,
          orElse: () => <String, dynamic>{},
        );
        if (found.isNotEmpty) {
          setState(() {
            _reservation = found;
            _loading = false;
          });
        } else {
          setState(() {
            _error = 'Réservation non trouvée';
            _loading = false;
          });
        }
      } else {
        setState(() {
          _error = 'Erreur ${res.statusCode}';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Erreur de connexion';
        _loading = false;
      });
    }
  }

  Future<void> _checkStatus() async {
    if (!mounted) return;
    final token = await readStoredApiToken();
    if (token == null) return;
    try {
      final res = await http.get(
        Uri.parse('${babifixApiBaseUrl()}/api/prestataire/requests/'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final requests = data['requests'] as List<dynamic>? ?? [];
        final found = requests.cast<Map<String, dynamic>>().firstWhere(
          (r) => r['reference'] == widget.reservationReference,
          orElse: () => <String, dynamic>{},
        );
        if (found.isEmpty) return;
        final status = '${found['status'] ?? ''}'.toUpperCase();
        if (status == 'CONFIRMEE' || status == 'DEVIS_ACCEPTE') {
          if (mounted) widget.onPaymentReceived();
        } else if (status == 'ANNULEE' || status.contains('ANNUL')) {
          if (mounted) widget.onCancelled();
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _slate50,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _navy),
          onPressed: widget.onBack,
        ),
        title: const Text(
          'En attente de paiement',
          style: TextStyle(color: _navy, fontWeight: FontWeight.w600),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _emerald))
          : _error != null
          ? _buildError()
          : _buildContent(),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: _slate400),
          const SizedBox(height: 16),
          Text(
            _error ?? 'Erreur',
            style: const TextStyle(fontSize: 18, color: _slate400),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () {
              setState(() => _loading = true);
              _loadReservation();
            },
            child: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 40),
          ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                color: _amber.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.hourglass_empty_rounded,
                size: 64,
                color: _amber,
              ),
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'En attente de paiement client',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: _navy,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Le client doit procéder au paiement\npour confirmer la réservation.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: _slate400, height: 1.5),
          ),
          const SizedBox(height: 40),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: _navy.withValues(alpha: 0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                _detailRow(
                  'R��servation',
                  _reservation?['reference'] ?? widget.reservationReference,
                ),
                const Divider(height: 24),
                _detailRow('Service', _reservation?['service'] ?? '-'),
                const Divider(height: 24),
                _detailRow('Client', _reservation?['client'] ?? '-'),
                const Divider(height: 24),
                _detailRow('Statut', 'En attente paiement...'),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _slate400.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: _slate400, size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Vous serez notifié automatiquement dès que le client aura payé.',
                    style: TextStyle(
                      fontSize: 13,
                      color: _slate400,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: widget.onBack,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _slate400),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Retour aux demandes'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, color: _slate400)),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: _navy,
          ),
        ),
      ],
    );
  }
}
