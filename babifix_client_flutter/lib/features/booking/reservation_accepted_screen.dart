import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../babifix_api_config.dart';
import '../../user_store.dart';

class ReservationAcceptedScreen extends StatefulWidget {
  final String reservationReference;
  final VoidCallback onBack;

  const ReservationAcceptedScreen({
    super.key,
    required this.reservationReference,
    required this.onBack,
  });

  @override
  State<ReservationAcceptedScreen> createState() =>
      _ReservationAcceptedScreenState();
}

class _ReservationAcceptedScreenState extends State<ReservationAcceptedScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _reservation;
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  static const _navy = Color(0xFF0F172A);
  static const _emerald = Color(0xFF10B981);
  static const _slate50 = Color(0xFFF8FAFC);
  static const _slate400 = Color(0xFF94A3B8);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.elasticOut),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
      ),
    );
    _animController.forward();
    _loadReservation();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
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
      final res = await http.get(
        Uri.parse('${babifixApiBaseUrl()}/api/client/reservations/'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final reservations = data['reservations'] as List<dynamic>? ?? [];
        final found = reservations.cast<Map<String, dynamic>>().firstWhere(
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
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _emerald))
          : _error != null
          ? _buildErrorState()
          : _buildContent(),
    );
  }

  Widget _buildErrorState() {
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
    final amount = _reservation?['montant'] is int
        ? _reservation!['montant'] as int
        : int.tryParse(
                '${_reservation?['montant'] ?? 0}'.replaceAll(
                  RegExp(r'\D'),
                  '',
                ),
              ) ??
              0;
    final commission = (amount * 0.18).round();
    final total = amount + commission;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 20),
            ScaleTransition(
              scale: _scaleAnimation,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  color: _emerald.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 80,
                  color: _emerald,
                ),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'Réservation confirmée !',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: _navy,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Le prestataire a accepté votre demande.\nProcédez au paiement pour lancer l\'intervention.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                color: _slate400,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 40),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: _navy.withValues(alpha: 0.06),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Récapitulatif',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _navy,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _summaryRow(
                    'Réservation',
                    _reservation?['reference'] ?? widget.reservationReference,
                  ),
                  const Divider(height: 24),
                  _summaryRow('Montant prestation', _formatFcfa(amount)),
                  const Divider(height: 24),
                  _summaryRow(
                    'Commission BABIFIX (18%)',
                    '- ${_formatFcfa(commission)}',
                    isNegative: true,
                  ),
                  const Divider(height: 24),
                  _summaryRow(
                    'Total à payer',
                    _formatFcfa(total),
                    isBold: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _emerald.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _emerald.withValues(alpha: 0.2)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.shield_outlined, color: _emerald, size: 24),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Paiement sécurisé. Remboursement garanti en cas de problème.',
                      style: TextStyle(
                        fontSize: 13,
                        color: _emerald,
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
              height: 56,
              child: FilledButton(
                onPressed: _proceedToPayment,
                style: FilledButton.styleFrom(
                  backgroundColor: _emerald,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Payer maintenant',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(
    String label,
    String value, {
    bool isBold = false,
    bool isNegative = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 15, color: _slate400)),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
            color: isNegative ? _emerald : _navy,
          ),
        ),
      ],
    );
  }

  String _formatFcfa(int amount) {
    if (amount <= 0) return '0 fcfa';
    final str = amount.toString();
    final formatted = str.replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]} ',
    );
    return '$formatted fcfa';
  }

  void _proceedToPayment() {
    if (_reservation == null) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _PaymentScreenPlaceholder(
          reservationId: _reservation!['id'] ?? 0,
          serviceTitle: _reservation!['title'] ?? 'Service BABIFIX',
        ),
      ),
    );
  }
}

class _PaymentScreenPlaceholder extends StatelessWidget {
  final int reservationId;
  final String serviceTitle;

  const _PaymentScreenPlaceholder({
    required this.reservationId,
    required this.serviceTitle,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Paiement')),
      body: Center(child: Text('Écran de paiement pour $serviceTitle')),
    );
  }
}
