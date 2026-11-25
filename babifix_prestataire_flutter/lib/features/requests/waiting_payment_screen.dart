import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../shared/auth_utils.dart' show readStoredApiToken;
import '../../shared/widgets/babifix_button.dart';
import '../../shared/widgets/babifix_ring_loader.dart';

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

  static const _emerald = BabifixDesign.success;
  static const _amber = BabifixDesign.warning;
  static const _slate400 = BabifixDesign.textMutedLight;

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
        Uri.parse(
          '${babifixApiBaseUrl()}/api/prestataire/requests'
          '?reference=${Uri.encodeComponent(widget.reservationReference)}',
        ),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final requests = data['requests'] as List<dynamic>? ?? [];
        final found = requests.cast<Map<String, dynamic>>().firstWhere(
          (r) => r['reference'] == widget.reservationReference,
          orElse: () => requests.isNotEmpty
              ? requests.first as Map<String, dynamic>
              : <String, dynamic>{},
        );
        if (found.isNotEmpty) {
          setState(() {
            _reservation = found;
            _loading = false;
          });
        } else {
          setState(() {
            _error = 'introuvable';
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
        Uri.parse(
          '${babifixApiBaseUrl()}/api/prestataire/requests'
          '?reference=${Uri.encodeComponent(widget.reservationReference)}',
        ),
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
        // Garder la fiche à jour (montant, statut) pendant l'attente.
        if (mounted) setState(() => _reservation = found);
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
    final textPrimary = BabifixDesign.textPrimaryOf(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textPrimary),
          onPressed: widget.onBack,
        ),
        title: Text(
          'En attente de paiement',
          style: TextStyle(color: textPrimary, fontWeight: FontWeight.w700),
        ),
      ),
      body: _loading
          ? const Center(child: BabifixRingLoader.cyan(size: 36))
          : _error != null
          ? _buildError()
          : _buildContent(),
    );
  }

  Widget _buildError() {
    final notFound = _error == 'introuvable';
    final title = notFound
        ? 'Suivi indisponible'
        : (_error == 'Non connecté' ? 'Session expirée' : 'Connexion perdue');
    final message = notFound
        ? "Cette réservation n'est plus en attente de paiement, "
              "ou son suivi n'est pas disponible ici. Retrouvez-la dans "
              "« Demandes » avec son statut à jour."
        : (_error == 'Non connecté'
              ? 'Reconnectez-vous pour suivre le paiement.'
              : 'Vérifiez votre connexion internet puis réessayez.');
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              color: (notFound ? _amber : _slate400).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              notFound
                  ? Icons.fact_check_outlined
                  : Icons.wifi_off_rounded,
              size: 52,
              color: notFound ? _amber : _slate400,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: BabifixDesign.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14.5,
              color: BabifixDesign.textMutedOf(context),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          if (!notFound)
            BabifixButton(
              label: 'Réessayer',
              backgroundColor: _emerald,
              onPressed: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _loadReservation();
              },
            ),
          const SizedBox(height: 12),
          BabifixButton(
            label: 'Retour aux demandes',
            variant: BabifixButtonVariant.outlined,
            onPressed: widget.onBack,
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
          Text(
            'En attente de paiement client',
            style: TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w800,
              color: BabifixDesign.textPrimaryOf(context),
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Le client doit procéder au paiement\npour confirmer la réservation.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: BabifixDesign.textMutedOf(context),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 36),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: BabifixDesign.surfaceOf(context),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: BabifixDesign.borderOf(context)),
            ),
            child: Column(
              children: [
                _detailRow(
                  'Réservation',
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
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: BabifixDesign.elevatedSurfaceOf(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: BabifixDesign.borderOf(context)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: BabifixDesign.textMutedOf(context), size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Vous serez notifié automatiquement dès que le client aura payé.',
                    style: TextStyle(
                      fontSize: 13,
                      color: BabifixDesign.textMutedOf(context),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          BabifixButton(
            label: 'Retour aux demandes',
            variant: BabifixButtonVariant.outlined,
            onPressed: widget.onBack,
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 14, color: BabifixDesign.textMutedOf(context)),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: BabifixDesign.textPrimaryOf(context),
              fontFeatures: BabifixDesign.tabularFigures,
            ),
          ),
        ),
      ],
    );
  }
}
