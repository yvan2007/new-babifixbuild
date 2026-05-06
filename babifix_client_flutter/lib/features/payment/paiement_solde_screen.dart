import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../babifix_money.dart';
import '../../user_store.dart';
import '../../shared/services/geniuspay_service.dart';
import '../../shared/widgets/payment_method_logo.dart';

const _kOperators = [
  _OpDef('ORANGE_MONEY', 'Orange Money', Color(0xFFFF6600)),
  _OpDef('MTN_MOMO', 'MTN MoMo', Color(0xFFFFCC00)),
  _OpDef('WAVE', 'Wave', Color(0xFF1A9BFC)),
  _OpDef('MOOV', 'Moov Africa', Color(0xFF007AC1)),
];

class _OpDef {
  const _OpDef(this.id, this.label, this.color);
  final String id;
  final String label;
  final Color color;
}

class PaiementSoldeScreen extends StatefulWidget {
  final String reservationReference;
  final double montantTotal;
  final double acompte;
  final VoidCallback onPaymentComplete;

  const PaiementSoldeScreen({
    super.key,
    required this.reservationReference,
    required this.montantTotal,
    required this.acompte,
    required this.onPaymentComplete,
  });

  @override
  State<PaiementSoldeScreen> createState() => _PaiementSoldeScreenState();
}

class _PaiementSoldeScreenState extends State<PaiementSoldeScreen>
    with TickerProviderStateMixin {
  String _operator = 'ORANGE_MONEY';
  bool _loading = false;
  bool _done = false;
  bool _polling = false;
  int _pollCount = 0;
  String? _error;
  Timer? _pollTimer;
  final _phoneCtrl = TextEditingController();

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  late final double _solde;

  @override
  void initState() {
    super.initState();
    _solde = widget.montantTotal - widget.acompte;

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(
      begin: 0.85,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pulseCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  _OpDef get _currentOp => _kOperators.firstWhere(
        (o) => o.id == _operator,
        orElse: () => _kOperators.first,
      );

  Future<void> _pay() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.length < 8) {
      setState(() => _error = 'Entrez un numéro valide (min. 8 chiffres).');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final token = await BabifixUserStore.getApiToken();
    if (token == null) return;

    try {
      final uri = Uri.parse(
        '${babifixApiBaseUrl()}/api/client/reservations/${widget.reservationReference}/pay-solde',
      );
      final resp = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'payment_method': _operator,
          'phone': phone,
        }),
      );

      if (!mounted) return;

      final data = jsonDecode(resp.body) as Map<String, dynamic>;

      if (resp.statusCode == 200) {
        if (data['mode'] == 'simulated') {
          setState(() {
            _loading = false;
            _done = true;
          });
          return;
        }

        final txId = data['transaction_id'] as String? ?? '';
        if (txId.isNotEmpty) {
          setState(() {
            _loading = false;
            _polling = true;
            _pollCount = 0;
          });
          _startPolling(txId);
        } else {
          setState(() {
            _loading = false;
            _done = true;
          });
        }
      } else {
        setState(() {
          _loading = false;
          _error = data['message'] as String? ?? data['error'] as String? ?? 'Erreur de paiement.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Erreur réseau. Vérifiez votre connexion.';
      });
    }
  }

  void _startPolling(String reference) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (t) async {
      if (!mounted) { t.cancel(); return; }
      if (_pollCount >= 24) {
        t.cancel();
        setState(() {
          _polling = false;
          _error = 'Délai dépassé. Vérifiez votre téléphone.';
        });
        return;
      }
      setState(() => _pollCount++);
      try {
        final status = await GeniusPayService.checkStatus(reference);
        if (!mounted) { t.cancel(); return; }
        if (status != null && status.isCompleted) {
          t.cancel();
          setState(() { _polling = false; _done = true; });
        } else if (status != null && status.isFailed) {
          t.cancel();
          setState(() {
            _polling = false;
            _error = 'Paiement échoué. Réessayez.';
          });
        }
      } catch (_) {}
    });
  }

  void _cancelPolling() {
    _pollTimer?.cancel();
    setState(() { _polling = false; _pollCount = 0; });
  }

  @override
  Widget build(BuildContext context) {
    final text = Colors.white;
    final sub = Colors.white70;

    if (_done) return _buildSuccessScreen(text, sub);
    if (_polling) return _buildPollingScreen(text, sub);

    return Scaffold(
      backgroundColor: BabifixDesign.navy,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A1628),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Payer le solde',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSummaryCard(text, sub),
            const SizedBox(height: 24),
            _buildEscrowInfo(),
            const SizedBox(height: 24),
            Text(
              'Opérateur Mobile Money',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: text),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 68,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: _kOperators.map((op) {
                  final selected = _operator == op.id;
                  return GestureDetector(
                    onTap: () => setState(() => _operator = op.id),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: selected ? op.color.withValues(alpha: 0.12) : const Color(0xFF0D1B2E),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected ? op.color : Colors.white.withValues(alpha: 0.10),
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          BabifixPaymentMethodLogo(methodId: op.id, height: 28),
                          const SizedBox(width: 10),
                          Text(
                            op.label,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: selected ? op.color : text,
                            ),
                          ),
                          if (selected) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.check_circle_rounded, color: op.color, size: 16),
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Numéro ${_currentOp.label}',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: text),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s]'))],
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: text),
              decoration: InputDecoration(
                hintText: 'Ex. : +225 07 00 00 00 00',
                hintStyle: TextStyle(color: sub.withValues(alpha: 0.6), fontSize: 14),
                filled: true,
                fillColor: const Color(0xFF0D1B2E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: _currentOp.color, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 13, color: sub.withValues(alpha: 0.65)),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'Vous recevrez une notification USSD pour confirmer.',
                    style: TextStyle(fontSize: 11, color: sub.withValues(alpha: 0.7)),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              _buildErrorBanner(),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _loading ? null : _pay,
                style: FilledButton.styleFrom(
                  backgroundColor: BabifixDesign.cyan,
                  foregroundColor: BabifixDesign.navy,
                  minimumSize: const Size(double.infinity, 58),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: BabifixDesign.navy),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.mobile_friendly_rounded, size: 22),
                          const SizedBox(width: 10),
                          Text(
                            'Payer le solde ${formatFcfa(_solde.toInt())}',
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.verified_user_outlined, size: 14, color: sub.withValues(alpha: 0.65)),
                const SizedBox(width: 6),
                Text(
                  'Paiement sécurisé · Fin de la prestation',
                  style: TextStyle(fontSize: 11, color: sub.withValues(alpha: 0.65)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(Color text, Color sub) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Montant total', style: TextStyle(color: sub, fontSize: 14)),
              Text(
                formatFcfa(widget.montantTotal.toInt()),
                style: TextStyle(color: text, fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Acompte déjà payé', style: TextStyle(color: BabifixDesign.ciGreen, fontSize: 14)),
              Text(
                '- ${formatFcfa(widget.acompte.toInt())}',
                style: TextStyle(color: BabifixDesign.ciGreen, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const Divider(color: Colors.white24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Solde à payer', style: TextStyle(color: BabifixDesign.cyan, fontWeight: FontWeight.w700)),
              Text(
                formatFcfa(_solde.toInt()),
                style: TextStyle(color: BabifixDesign.cyan, fontWeight: FontWeight.w900, fontSize: 22),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEscrowInfo() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BabifixDesign.cyan.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BabifixDesign.cyan.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_rounded, color: BabifixDesign.cyan, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Après ce paiement, l\'acompte sera libéré au prestataire '
              'et la prestation sera terminée.',
              style: TextStyle(color: BabifixDesign.cyan, fontSize: 12.5, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(_error!, style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13, height: 1.4)),
          ),
          GestureDetector(
            onTap: () => setState(() => _error = null),
            child: const Icon(Icons.close_rounded, size: 18, color: Color(0xFFDC2626)),
          ),
        ],
      ),
    );
  }

  Widget _buildPollingScreen(Color text, Color sub) {
    final op = _currentOp;
    return Scaffold(
      backgroundColor: BabifixDesign.navy,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A1628),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: _cancelPolling,
        ),
        title: const Text(
          'En attente...',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, child) => Transform.scale(scale: _pulseAnim.value, child: child),
                child: Container(
                  width: 110, height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: op.color.withValues(alpha: 0.12),
                    border: Border.all(color: op.color.withValues(alpha: 0.3), width: 2),
                  ),
                  child: Center(
                    child: BabifixPaymentMethodLogo(methodId: op.id, height: 52),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Confirmation en cours…',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: text),
              ),
              const SizedBox(height: 10),
              Text(
                'Solde de ${formatFcfa(_solde.toInt())} via ${op.label}',
                textAlign: TextAlign.center,
                style: TextStyle(color: sub, height: 1.5, fontSize: 14),
              ),
              const SizedBox(height: 32),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: (_pollCount / 24).clamp(0.0, 1.0),
                  backgroundColor: op.color.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation<Color>(op.color),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 8),
              Text('Vérification $_pollCount/24', style: TextStyle(fontSize: 12, color: sub)),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _cancelPolling,
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('Annuler'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFDC2626),
                  side: const BorderSide(color: Color(0xFFFCA5A5)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessScreen(Color text, Color sub) {
    return Scaffold(
      backgroundColor: BabifixDesign.navy,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 800),
                tween: Tween(begin: 0, end: 1),
                curve: Curves.elasticOut,
                builder: (_, v, __) => Transform.scale(
                  scale: v,
                  child: Container(
                    width: 110, height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [BabifixDesign.ciGreen.withValues(alpha: 0.18), Colors.transparent],
                      ),
                    ),
                    child: const Icon(Icons.check_circle_rounded, size: 72, color: BabifixDesign.ciGreen),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Paiement complet !',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: text),
              ),
              const SizedBox(height: 12),
              Text(
                'Le solde de ${formatFcfa(_solde.toInt())} a été payé.\n'
                'Le prestataire a été crédité. Merci !',
                textAlign: TextAlign.center,
                style: TextStyle(color: sub, height: 1.55, fontSize: 15),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    widget.onPaymentComplete();
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.calendar_today_rounded),
                  label: const Text('Retour à mes réservations'),
                  style: FilledButton.styleFrom(
                    backgroundColor: BabifixDesign.ciGreen,
                    minimumSize: const Size(double.infinity, 54),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
