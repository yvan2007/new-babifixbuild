import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../user_store.dart';
import '../../babifix_money.dart';
import '../../shared/widgets/payment_method_logo.dart';
import '../auth/biometric_login_screen.dart';

// ---------------------------------------------------------------------------
// Opérateurs Mobile Money disponibles via CinetPay (Côte d'Ivoire)
// ---------------------------------------------------------------------------
const _kOperators = [
  _OpDef(
    'ORANGE_MONEY',
    'Orange Money',
    Color(0xFFFF6600),
    'assets/payment_logos/orange_money.png',
  ),
  _OpDef(
    'MTN_MOMO',
    'MTN MoMo',
    Color(0xFFFFCC00),
    'assets/payment_logos/mtn_momo.png',
  ),
  _OpDef('WAVE', 'Wave', Color(0xFF1A9BFC), 'assets/payment_logos/wave.png'),
  _OpDef(
    'MOOV',
    'Moov Africa',
    Color(0xFF007AC1),
    'assets/payment_logos/moov.png',
  ),
];

class _OpDef {
  const _OpDef(this.id, this.label, this.color, this.assetPath);
  final String id;
  final String label;
  final Color color;
  final String assetPath;
}

// ---------------------------------------------------------------------------

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({
    super.key,
    required this.reservationId,
    this.amount,
    this.serviceTitle,
    this.providerName,
  });

  final int reservationId;
  final int? amount;
  final String? serviceTitle;
  final String? providerName;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen>
    with TickerProviderStateMixin {
  // ── méthode et opérateur ──────────────────────────────────────────────────
  String _method = 'MOBILE_MONEY';
  String _operator = 'ORANGE_MONEY';

  // ── états ─────────────────────────────────────────────────────────────────
  bool _loading = false;
  bool _done = false;
  bool _polling = false;
  int _pollCount = 0;
  String? _error;
  String? _transactionId;
  Timer? _pollTimer;

  // ── données réservation ───────────────────────────────────────────────────
  Map<String, dynamic>? _reservation;
  bool _fetching = true;

  // ── formulaire Mobile Money ───────────────────────────────────────────────
  final _phoneCtrl = TextEditingController();
  final _phoneFocus = FocusNode();

  // ── animation pulsation attente ───────────────────────────────────────────
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(
      begin: 0.85,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _fetchReservation();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pulseCtrl.dispose();
    _phoneCtrl.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }

  // ── chargement réservation ────────────────────────────────────────────────
  Future<void> _fetchReservation() async {
    try {
      final token = await BabifixUserStore.getApiToken();
      if (token == null) throw Exception('Non connecté');
      final res = await http.get(
        Uri.parse(
          '${babifixApiBaseUrl()}/api/reservations/${widget.reservationId}/',
        ),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (!mounted) return;
        setState(() {
          _reservation = data;
          _fetching = false;
          // Pré-remplir le téléphone depuis le profil client si disponible
          final phone = (data['client']?['phone_e164'] as String? ?? '').trim();
          if (phone.isNotEmpty && _phoneCtrl.text.isEmpty) {
            _phoneCtrl.text = phone;
          }
        });
        return;
      }
    } catch (_) {}
    if (mounted)
      setState(() {
        _reservation = null;
        _fetching = false;
      });
  }

  // ── getters utilitaires ───────────────────────────────────────────────────
  int get _amount =>
      widget.amount ?? ((_reservation?['montant'] as num?)?.toInt() ?? 10000);

  String get _serviceTitle =>
      widget.serviceTitle ??
      (_reservation?['service']?['titre'] as String?) ??
      'Service BABIFIX';

  String get _providerName =>
      widget.providerName ??
      (_reservation?['prestataire']?['nom'] as String?) ??
      'Prestataire';

  _OpDef get _currentOp => _kOperators.firstWhere(
    (o) => o.id == _operator,
    orElse: () => _kOperators.first,
  );

  // ── PAIEMENT MOBILE MONEY (CinetPay) ─────────────────────────────────────
  Future<void> _payCinetPay() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.length < 8) {
      setState(
        () => _error =
            'Veuillez entrer votre numéro de téléphone Mobile Money (min. 8 chiffres).',
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final token = await BabifixUserStore.getApiToken();
      if (token == null) throw Exception('Non connecté');

      final res = await http.post(
        Uri.parse(
          '${babifixApiBaseUrl()}/api/bookings/${widget.reservationId}/pay/',
        ),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'mode_paiement': 'MOBILE_MONEY',
          'operator': _operator,
          'phone': phone,
        }),
      );

      if (!mounted) return;

      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final txId = (data['transaction_id'] as String?)?.trim() ?? '';
        if (txId.isNotEmpty) {
          setState(() {
            _loading = false;
            _polling = true;
            _transactionId = txId;
            _pollCount = 0;
          });
          _startPolling(txId, token);
        } else {
          // Paiement initié — le serveur va traiter la transaction
          setState(() {
            _loading = false;
            _done = true;
          });
        }
      } else {
        String msg = 'Erreur de paiement.';
        try {
          final d = jsonDecode(res.body) as Map<String, dynamic>;
          final raw = d['detail'] ?? d['error'] ?? d['message'];
          if (raw != null) msg = '$raw';
        } catch (_) {}
        setState(() {
          _loading = false;
          _error = msg;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Erreur réseau : vérifiez votre connexion et réessayez.';
      });
    }
  }

  // ── Polling statut CinetPay (toutes les 5 s, max 2 min) ──────────────────
  void _startPolling(String txId, String token) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (t) async {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_pollCount >= 24) {
        t.cancel();
        if (mounted) {
          setState(() {
            _polling = false;
            _error =
                'Délai de 2 minutes dépassé. Vérifiez votre téléphone ou relancez le paiement.';
          });
        }
        return;
      }
      setState(() => _pollCount++);
      try {
        final res = await http.get(
          Uri.parse(
            '${babifixApiBaseUrl()}/api/reservations/${widget.reservationId}/',
          ),
          headers: {'Authorization': 'Bearer $token'},
        );
        if (!mounted) {
          t.cancel();
          return;
        }
        if (res.statusCode == 200) {
          final d = jsonDecode(res.body) as Map<String, dynamic>;
          final bookingStatus = '${d['status'] ?? ''}'.toUpperCase();
          if (bookingStatus == 'PAID' ||
              bookingStatus == 'DONE' ||
              bookingStatus == 'COMPLETED') {
            t.cancel();
            setState(() {
              _polling = false;
              _done = true;
            });
          }
          // Autres statuts → continuer à poller
        }
      } catch (_) {}
    });
  }

  // ── PAIEMENT ESPÈCES ─────────────────────────────────────────────────────
  Future<void> _payEspeces() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = await BabifixUserStore.getApiToken();
      if (token == null) throw Exception('Non connecté');
      final res = await http.post(
        Uri.parse('${babifixApiBaseUrl()}/api/paiements/'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'reservation': widget.reservationId,
          'mode_paiement': 'ESPECES',
          'montant': _amount,
        }),
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        setState(() {
          _done = true;
          _loading = false;
        });
      } else {
        String msg = 'Erreur de paiement.';
        try {
          final d = jsonDecode(res.body) as Map<String, dynamic>;
          msg = (d['detail'] ?? msg) as String;
        } catch (_) {}
        setState(() {
          _error = msg;
          _loading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Erreur réseau.';
        _loading = false;
      });
    }
  }

  void _pay() {
    _error = null;
    if (_method == 'MOBILE_MONEY') {
      _payCinetPay();
    } else {
      _payEspeces();
    }
  }

  void _cancelPolling() {
    _pollTimer?.cancel();
    setState(() {
      _polling = false;
      _pollCount = 0;
      _transactionId = null;
    });
  }

  // =========================================================================
  // BUILD
  // =========================================================================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final text = cs.onSurface;
    final sub = cs.onSurfaceVariant;

    // ── Succès ───────────────────────────────────────────────────────────────
    if (_done) return _buildSuccessScreen(text, sub, cs);

    // ── Attente CinetPay ─────────────────────────────────────────────────────
    if (_polling) return _buildPollingScreen(text, sub, cs);

    // ── Écran principal ───────────────────────────────────────────────────────
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        foregroundColor: text,
        title: Text(
          'Paiement',
          style: TextStyle(fontWeight: FontWeight.w800, color: text),
        ),
        elevation: 0,
      ),
      body: _fetching
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Résumé commande ─────────────────────────────────────
                  _buildOrderSummary(cs, text, sub),
                  const SizedBox(height: 24),

                  // ── Sélection méthode ───────────────────────────────────
                  Text(
                    'Mode de paiement',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: text,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _PaymentMethodTile(
                    id: 'MOBILE_MONEY',
                    label: 'Mobile Money',
                    sub: 'Orange · MTN · Wave · Moov',
                    icon: Icons.phone_android_rounded,
                    iconColor: BabifixDesign.ciOrange,
                    customSubtitle: const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: BabifixMobileMoneyLogoStrip(height: 22),
                    ),
                    selected: _method == 'MOBILE_MONEY',
                    textColor: text,
                    subColor: sub,
                    onTap: () => setState(() => _method = 'MOBILE_MONEY'),
                  ),
                  _PaymentMethodTile(
                    id: 'ESPECES',
                    label: 'Espèces',
                    sub: 'Règlement à la livraison — validé par l\'admin',
                    icon: Icons.payments_rounded,
                    iconColor: BabifixDesign.ciGreen,
                    selected: _method == 'ESPECES',
                    textColor: text,
                    subColor: sub,
                    onTap: () => setState(() => _method = 'ESPECES'),
                  ),

                  // ── Opérateur + Téléphone (Mobile Money uniquement) ─────
                  if (_method == 'MOBILE_MONEY') ...[
                    const SizedBox(height: 20),
                    _buildOperatorSelector(text, sub),
                    const SizedBox(height: 16),
                    _buildPhoneField(cs, text, sub),
                  ],

                  const SizedBox(height: 20),

                  // ── Note escrow ─────────────────────────────────────────
                  _buildEscrowNote(),

                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    _buildErrorBanner(),
                  ],

                  const SizedBox(height: 20),

                  // ── Bouton payer ────────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _loading ? null : _pay,
                      style: FilledButton.styleFrom(
                        backgroundColor: BabifixDesign.cyan,
                        foregroundColor: BabifixDesign.navy,
                        minimumSize: const Size(double.infinity, 58),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        elevation: 3,
                        shadowColor: BabifixDesign.cyan.withValues(alpha: 0.35),
                      ),
                      child: _loading
                          ? SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: BabifixDesign.navy,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _method == 'MOBILE_MONEY'
                                      ? Icons.mobile_friendly_rounded
                                      : Icons.payments_rounded,
                                  size: 22,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Payer ${formatFcfa(_amount)}',
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),

                  // ── Sécurité label ──────────────────────────────────────
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        size: 14,
                        color: sub.withValues(alpha: 0.65),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Paiement sécurisé · Conforme ARTCI CI',
                        style: TextStyle(
                          fontSize: 11,
                          color: sub.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  // ── Résumé commande ─────────────────────────────────────────────────────
  Widget _buildOrderSummary(ColorScheme cs, Color text, Color sub) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: BabifixDesign.cyan.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.home_repair_service_rounded,
                  color: BabifixDesign.cyan,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _serviceTitle,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: text,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _providerName,
                      style: TextStyle(color: sub, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: cs.outlineVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total à régler',
                style: TextStyle(color: sub, fontSize: 14),
              ),
              Text(
                formatFcfa(_amount),
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: BabifixDesign.cyan,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Sélecteur opérateur ─────────────────────────────────────────────────
  Widget _buildOperatorSelector(Color text, Color sub) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Opérateur Mobile Money',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: text,
          ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? op.color.withValues(alpha: 0.12)
                        : Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected
                          ? op.color
                          : Theme.of(context).colorScheme.outlineVariant,
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
                          color: selected
                              ? op.color
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      if (selected) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.check_circle_rounded,
                          color: op.color,
                          size: 16,
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ── Champ téléphone ─────────────────────────────────────────────────────
  Widget _buildPhoneField(ColorScheme cs, Color text, Color sub) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Numéro ${_currentOp.label}',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: text,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _phoneCtrl,
          focusNode: _phoneFocus,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s]')),
          ],
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 17,
            color: text,
          ),
          decoration: InputDecoration(
            hintText: 'Ex. : +225 07 00 00 00 00',
            hintStyle: TextStyle(
              fontWeight: FontWeight.w400,
              fontSize: 14,
              color: sub.withValues(alpha: 0.6),
            ),
            prefixIcon: Container(
              margin: const EdgeInsets.all(10),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _currentOp.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: BabifixPaymentMethodLogo(
                methodId: _currentOp.id,
                height: 20,
              ),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: cs.outlineVariant),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: _currentOp.color, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 13,
              color: sub.withValues(alpha: 0.65),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                'Vous recevrez une notification USSD pour confirmer le paiement.',
                style: TextStyle(
                  fontSize: 11,
                  color: sub.withValues(alpha: 0.7),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Note sécurité paiement ─────────────────────────────────────────
  Widget _buildEscrowNote() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BabifixDesign.ciBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BabifixDesign.ciBlue.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_rounded, color: BabifixDesign.ciBlue, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Votre paiement est sécurisé via CinetPay. '
              'Transférer directement au prestataire après validation de la prestation.',
              style: TextStyle(
                color: BabifixDesign.ciBlue,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bannière erreur ──────────────────────────────────────────────────────
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
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFDC2626),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(
                color: Color(0xFFDC2626),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _error = null),
            child: const Icon(
              Icons.close_rounded,
              size: 18,
              color: Color(0xFFDC2626),
            ),
          ),
        ],
      ),
    );
  }

  // ── Écran attente CinetPay ───────────────────────────────────────────────
  Widget _buildPollingScreen(Color text, Color sub, ColorScheme cs) {
    final op = _currentOp;
    final seconds = _pollCount * 5;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        foregroundColor: text,
        title: Text(
          'En attente de confirmation',
          style: TextStyle(fontWeight: FontWeight.w700, color: text),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () {
            _cancelPolling();
          },
          tooltip: 'Annuler',
        ),
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icône opérateur avec pulsation
              CustomAnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, child) =>
                    Transform.scale(scale: _pulseAnim.value, child: child),
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: op.color.withValues(alpha: 0.12),
                    border: Border.all(
                      color: op.color.withValues(alpha: 0.3),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: BabifixPaymentMethodLogo(
                      methodId: op.id,
                      height: 52,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Confirmation en cours…',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: text,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Nous avons transmis votre paiement de\n${formatFcfa(_amount)} via ${op.label}.',
                textAlign: TextAlign.center,
                style: TextStyle(color: sub, height: 1.5, fontSize: 14),
              ),
              const SizedBox(height: 32),

              // Étapes instructions
              _PollingStep(
                number: '1',
                text: 'Vérifiez votre téléphone au numéro ${_phoneCtrl.text}',
                done: _pollCount >= 2,
                color: op.color,
              ),
              const SizedBox(height: 10),
              _PollingStep(
                number: '2',
                text: 'Acceptez la notification USSD de ${op.label}',
                done: _pollCount >= 5,
                color: op.color,
              ),
              const SizedBox(height: 10),
              _PollingStep(
                number: '3',
                text: 'Entrez votre code PIN Mobile Money',
                done: _pollCount >= 8,
                color: op.color,
              ),
              const SizedBox(height: 32),

              // Barre de progression
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
              Text(
                'Vérification ${_pollCount}/24 · ${seconds}s écoulées',
                style: TextStyle(fontSize: 12, color: sub),
              ),
              const SizedBox(height: 24),

              OutlinedButton.icon(
                onPressed: _cancelPolling,
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('Annuler le paiement'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFDC2626),
                  side: const BorderSide(color: Color(0xFFFCA5A5)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Écran succès ─────────────────────────────────────────────────────────
  Widget _buildSuccessScreen(Color text, Color sub, ColorScheme cs) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          BabifixDesign.ciGreen.withValues(alpha: 0.18),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 72,
                      color: BabifixDesign.ciGreen,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Paiement confirmé !',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: text,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${formatFcfa(_amount)} sont sécurisés en séquestre.\n'
                'Le prestataire sera payé après validation de la mission.',
                textAlign: TextAlign.center,
                style: TextStyle(color: sub, height: 1.55, fontSize: 15),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: BabifixDesign.ciGreen.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: BabifixDesign.ciGreen.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock_rounded,
                      size: 16,
                      color: BabifixDesign.ciGreen,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Fonds sécurisés · Escrow BABIFIX',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: BabifixDesign.ciGreen,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.calendar_today_rounded),
                  label: const Text('Retour à mes réservations'),
                  style: FilledButton.styleFrom(
                    backgroundColor: BabifixDesign.ciGreen,
                    minimumSize: const Size(double.infinity, 54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
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

// =============================================================================
// Widgets helpers
// =============================================================================

class _PaymentMethodTile extends StatelessWidget {
  const _PaymentMethodTile({
    required this.id,
    required this.label,
    required this.sub,
    required this.icon,
    required this.iconColor,
    this.customSubtitle,
    required this.selected,
    required this.textColor,
    required this.subColor,
    required this.onTap,
  });

  final String id;
  final String label;
  final String sub;
  final IconData icon;
  final Color iconColor;
  final Widget? customSubtitle;
  final bool selected;
  final Color textColor;
  final Color subColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? iconColor.withValues(alpha: 0.09) : cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? iconColor : cs.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                  if (customSubtitle != null)
                    customSubtitle!
                  else
                    Text(sub, style: TextStyle(fontSize: 12, color: subColor)),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? iconColor : subColor,
                  width: selected ? 7 : 2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PollingStep extends StatelessWidget {
  const _PollingStep({
    required this.number,
    required this.text,
    required this.done,
    required this.color,
  });

  final String number;
  final String text;
  final bool done;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? color : color.withValues(alpha: 0.12),
            border: Border.all(
              color: done ? color : color.withValues(alpha: 0.3),
            ),
          ),
          child: Center(
            child: done
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                : Text(
                    number,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: color,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: done
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.55),
              fontWeight: done ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}
