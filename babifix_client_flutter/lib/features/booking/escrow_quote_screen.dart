import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../babifix_design_system.dart';
import '../../babifix_money.dart';
import '../../models/babifix_models.dart';
import '../../services/babifix_api.dart';
import '../../shared/services/geniuspay_service.dart';
import '../../shared/widgets/babifix_phase_widgets.dart';
import '../../user_store.dart';
import '../../shared/widgets/babifix_ring_loader.dart';
import '../../shared/widgets/babifix_payment_error_banner.dart';
import '../../shared/widgets/payment_method_logo.dart';
import '../../shared/services/pending_payment_store.dart';
import '../../shared/widgets/babifix_snackbar.dart';

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

class EscrowQuoteScreen extends StatefulWidget {
  final String reservationReference;
  const EscrowQuoteScreen({super.key, required this.reservationReference});

  @override
  State<EscrowQuoteScreen> createState() => _EscrowQuoteScreenState();
}

class _EscrowQuoteScreenState extends State<EscrowQuoteScreen>
    with TickerProviderStateMixin {
  EscrowQuote? _quote;
  bool _loading = true;
  bool _paying = false;
  bool _polling = false;
  bool _done = false;
  String? _error;
  int _pollCount = 0;
  Timer? _pollTimer;
  final _phoneCtl = TextEditingController();
  String _operator = 'ORANGE_MONEY';

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _load();
    _prefillPhone();
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
    _phoneCtl.dispose();
    super.dispose();
  }

  Future<void> _prefillPhone() async {
    try {
      final profile = await BabifixUserStore.loadProfile();
      final raw = '${profile['phone'] ?? ''}';
      // Normaliser au format national ivoirien (10 chiffres) : on retire
      // l'indicatif +225 / 225 et tout caractère non numérique.
      var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.startsWith('225') && digits.length == 13) {
        digits = digits.substring(3);
      }
      if (digits.length > 10) digits = digits.substring(digits.length - 10);
      if (digits.isNotEmpty && mounted) {
        _phoneCtl.text = digits;
      }
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _quote = await EscrowApi.quote(widget.reservationReference);
      // Opérateur choisi à la réservation → pré-sélectionné ici (pas de
      // double demande). Repli sur Orange Money si non renseigné.
      final op = _quote?.mobileMoneyOperator ?? '';
      if (op.isNotEmpty && _kOperators.any((o) => o.id == op)) {
        _operator = op;
      }
    } on BabifixApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  _OpDef get _currentOp => _kOperators.firstWhere(
    (o) => o.id == _operator,
    orElse: () => _kOperators.first,
  );

  Future<void> _pay() async {
    final q = _quote;
    if (q == null) return;
    if (q.reservationId == null) {
      setState(() => _error = 'Réservation introuvable.');
      return;
    }
    final phone = _phoneCtl.text.trim();
    if (phone.length != 10) {
      setState(() => _error = 'Entrez un numéro à 10 chiffres (ex. 0700000000).');
      return;
    }

    setState(() {
      _paying = true;
      _error = null;
    });

    try {
      final r = await BabifixUserStore.authPost(
        '/api/paiements/geniuspay/initiate/',
        body: jsonEncode({
          'reservation': q.reservationId,
          'montant': q.amountDueOnline.toInt(),
          'customer_name': 'Client BABIFIX',
          'phone': phone,
          'payment_method': _operator,
        }),
      );

      if (!mounted) return;

      if (r.statusCode >= 400) {
        final err = r.body;
        setState(() {
          _paying = false;
          _error = 'Erreur de paiement.';
        });
        return;
      }

      final data = jsonDecode(r.body) as Map<String, dynamic>;
      final txId = data['transaction_id'] as String? ?? '';
      final status = data['status'] as String? ?? '';
      if (txId.isEmpty) {
        setState(() {
          _paying = false;
          _done = true;
        });
        return;
      }
      if (status == 'COMPLETE') {
        setState(() {
          _paying = false;
          _done = true;
        });
        return;
      }
      setState(() {
        _paying = false;
        _polling = true;
        _pollCount = 0;
      });
      _startPolling(txId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _paying = false;
        _error = 'Erreur réseau. Vérifiez votre connexion.';
      });
    }
  }

  void _startPolling(String reference) {
    _pollTimer?.cancel();
    final q = _quote;
    final amount = q?.amountDueOnline ?? 0;
    PendingPaymentStore.save(PendingPayment(
      reference: reference,
      reservationRef: widget.reservationReference,
      amount: amount,
      operator: _operator,
      kind: 'acompte',
      startedAtMs: DateTime.now().millisecondsSinceEpoch,
    ));
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
          await PendingPaymentStore.clear();
          setState(() { _polling = false; _done = true; });
        } else if (status != null && status.isFailed) {
          t.cancel();
          await PendingPaymentStore.clear();
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

  void _snack(String s) {
    if (!mounted) return;
    showBabifixToast(
      context,
      type: BabifixToastType.info,
      message: s,
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Colors.white;
    final sub = Colors.white70;

    if (_done) {
      return _buildSuccessScreen(text, sub);
    }

    if (_polling) {
      return _buildPollingScreen(text, sub);
    }

    return Scaffold(
      backgroundColor: BabifixDesign.navy,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A1628),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          (_quote != null && _quote!.isMobile && _quote!.acompteValide)
              ? 'Paiement du solde'
              : 'Paiement de l\'acompte',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
      ),
      body: _loading
          ? const Center(child: BabifixRingLoader.dark(size: 80))
          : _error != null && _quote == null
              ? _errorView()
              : _content(_quote!),
    );
  }

  Widget _errorView() => Padding(
    padding: const EdgeInsets.all(24),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: BabifixDesign.error, size: 48),
          const SizedBox(height: 10),
          Text(_error ?? '', textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _load,
            style: ElevatedButton.styleFrom(
              backgroundColor: BabifixDesign.ciBlue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Réessayer'),
          ),
        ],
      ),
    ),
  );

  Widget _content(EscrowQuote q) {
    final color = q.isCash ? Colors.orange.shade700 : BabifixDesign.ciBlue;
    // Phase de paiement :
    //  - cash : payé dès que l'acompte (commission) est versé.
    //  - mobile : acompte 30 % puis solde 70 % ; "fini" quand plus rien n'est dû.
    final alreadyPaid = q.isCash
        ? q.acompteValide
        : (q.acompteValide && q.amountDueOnline <= 0);
    final canPayNow = !alreadyPaid && q.amountDueOnline > 0;
    final isSoldePhase = q.isMobile && q.acompteValide && q.amountDueOnline > 0;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: color.withValues(alpha: 0.30)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            q.isCash
                                ? Icons.handshake
                                : Icons.lock_outline,
                            color: color, size: 26,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              q.isCash
                                  ? 'Paiement cash en main propre'
                                  : 'Paiement Mobile Money',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: color,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        q.isCash
                            ? "Vous versez maintenant uniquement la commission "
                                "de la plateforme (${q.commissionMontant.toInt()} F CFA). "
                                "Le reste (${q.cashRemainderDueToProvider.toInt()} F CFA) "
                                "sera payé en cash directement au prestataire à la fin du chantier."
                            : isSoldePhase
                                ? "Vous payez maintenant le solde restant. L'argent "
                                    "reste sécurisé chez BABIFIX ; le prestataire est "
                                    "payé après votre confirmation des travaux."
                                : "Vous payez l'acompte (30 %) maintenant. Le solde "
                                    "(70 %) sera payé en ligne à la fin, avant votre "
                                    "confirmation. L'argent reste sécurisé chez BABIFIX.",
                        style: const TextStyle(fontSize: 13, height: 1.4, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                MoneyBreakdownWidget(
                  sousTotal: q.totalDevis,
                  // Taux RÉEL envoyé par le serveur (reflète le tarif premium
                  // du prestataire, ex. 8 % en GOLD). NE PAS le reconstituer
                  // en divisant commissionMontant par totalDevis : la
                  // commission est calculée sur le reste APRÈS caution, pas
                  // sur le total brut — cette division donnait un pourcentage
                  // faux (13 % au lieu de 18 %) dès qu'une caution existait.
                  commissionRate: q.commissionRate,
                  commissionMontant: q.commissionMontant,
                  totalTtc: q.totalDevis,
                  netPrestataire: q.netPrestataire,
                  // "Total à payer" par défaut suggérait que ce montant était
                  // dû MAINTENANT (juste sous "Commission (X%)"), alors que
                  // seul un acompte/solde partiel l'est en Mobile Money — le
                  // vrai montant demandé est dans l'encart vert ci-dessous.
                  totalLabel: 'Total du devis (référence)',
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: BabifixDesign.ciGreen.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: BabifixDesign.ciGreen.withValues(alpha: 0.30)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.payment,
                          color: BabifixDesign.ciGreen, size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              q.isCash
                                  ? 'À payer maintenant (commission)'
                                  : (isSoldePhase
                                      ? 'À payer maintenant (solde, 70 %)'
                                      : 'À payer maintenant (acompte, 30 %)'),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white60),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              fmtMoney(q.amountDueOnline),
                              style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: BabifixDesign.ciGreen),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (q.isCash) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.payments_outlined,
                            size: 18, color: Colors.white60),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Reste à payer en cash au prestataire : '
                            '${fmtMoney(q.cashRemainderDueToProvider)}',
                            style: const TextStyle(
                                fontSize: 13, color: Colors.white70),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                if (alreadyPaid)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: BabifixDesign.ciGreen.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: BabifixDesign.ciGreen.withValues(alpha: 0.30)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle,
                            color: BabifixDesign.ciGreen),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            q.isMobile
                                ? 'Paiement complet effectué (acompte + solde).'
                                : 'Acompte déjà versé.',
                            style: TextStyle(
                                color: BabifixDesign.ciGreen,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (isSoldePhase)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: BabifixDesign.ciGreen.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: BabifixDesign.ciGreen.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_outline,
                              color: BabifixDesign.ciGreen, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Acompte (30 %) déjà versé. Il reste le solde à régler.',
                              style: TextStyle(
                                  color: BabifixDesign.ciGreen,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (canPayNow) ...[
                  const SizedBox(height: 14),
                  Text(
                    'Choisissez votre opérateur Mobile Money',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: Colors.white),
                  ),
                  const SizedBox(height: 10),
                  // Choix de l'opérateur au moment du paiement (le montant exact
                  // est désormais connu grâce au devis).
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
                                horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: selected
                                  ? op.color.withValues(alpha: 0.12)
                                  : const Color(0xFF0D1B2E),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: selected
                                    ? op.color
                                    : Colors.white.withValues(alpha: 0.10),
                                width: selected ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                BabifixPaymentMethodLogo(
                                    methodId: op.id, height: 28),
                                const SizedBox(width: 10),
                                Text(
                                  op.label,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: selected ? op.color : Colors.white,
                                  ),
                                ),
                                if (selected) ...[
                                  const SizedBox(width: 8),
                                  Icon(Icons.check_circle_rounded,
                                      color: op.color, size: 16),
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
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _phoneCtl,
                    keyboardType: TextInputType.number,
                    // Numéros ivoiriens : 10 chiffres, peu importe l'opérateur.
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                        color: Colors.white),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: 'Ex. : 0700000000 (10 chiffres)',
                      hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 14),
                      filled: true,
                      fillColor: const Color(0xFF0D1B2E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.12)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide:
                            BorderSide(color: _currentOp.color, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 13,
                          color: Colors.white.withValues(alpha: 0.5)),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          'Vous recevrez une notification USSD pour confirmer le paiement.',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.55)),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  'Opérateurs supportés : Orange Money · MTN MoMo · Wave · Moov',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.45)),
                  textAlign: TextAlign.center,
                ),
                if (_error != null && canPayNow) ...[
                  const SizedBox(height: 14),
                  BabifixPaymentErrorBanner(
                    message: _error!,
                    onDismiss: () => setState(() => _error = null),
                  ),
                ],
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed:
                    (!canPayNow || _paying) ? null : _pay,
                icon: _paying
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: BabifixRingLoader.cyan(size: 28))
                    : const Icon(Icons.mobile_friendly_rounded, size: 22),
                label: Text(
                  alreadyPaid
                      ? 'Déjà payé'
                      : _paying
                          ? 'Paiement en cours…'
                          : 'Payer ${fmtMoney(q.amountDueOnline)}',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: BabifixDesign.ciGreen,
                  foregroundColor: BabifixDesign.navy,
                  minimumSize: const Size(double.infinity, 58),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPollingScreen(Color text, Color sub) {
    final op = _currentOp;
    const cardBg = Color(0xFF112138);
    return Scaffold(
      backgroundColor: BabifixDesign.navy,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: _cancelPolling,
        ),
        title: const Text(
          'Paiement',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 16),
              // ── Héros : anneaux pulsants + anneau de progression + icône ──
              SizedBox(
                width: 168,
                height: 168,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _pulseAnim,
                      builder: (_, __) => Container(
                        width: 168 * _pulseAnim.value,
                        height: 168 * _pulseAnim.value,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: op.color.withValues(alpha: 0.10),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 124,
                      height: 124,
                      child: CircularProgressIndicator(
                        value: (_pollCount / 24).clamp(0.02, 1.0),
                        strokeWidth: 5,
                        backgroundColor: Colors.white.withValues(alpha: 0.08),
                        valueColor: AlwaysStoppedAnimation<Color>(op.color),
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    // Pastille blanche + vrai logo de l'opérateur (Orange Money,
                    // MTN MoMo, Wave, Moov) — plus parlant que l'icône générique.
                    Container(
                      width: 96,
                      height: 96,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: op.color.withValues(alpha: 0.45),
                            blurRadius: 22,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: BabifixPaymentMethodLogo(
                        methodId: op.id,
                        height: 56,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // ── Puce opérateur ──
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: op.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: op.color.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 9, height: 9,
                      decoration:
                          BoxDecoration(color: op.color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text(op.label,
                        style: TextStyle(
                            color: op.color,
                            fontWeight: FontWeight.w800,
                            fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Confirmation du paiement',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w900, color: text),
              ),
              const SizedBox(height: 10),
              Text(
                'Validez la demande reçue sur votre téléphone, puis patientez. '
                'Nous confirmons automatiquement le paiement.',
                textAlign: TextAlign.center,
                style: TextStyle(color: sub, height: 1.5, fontSize: 14),
              ),
              const SizedBox(height: 26),
              // ── Carte étapes ──
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: Column(
                  children: [
                    _pollStep(op.color, Icons.notifications_active_rounded,
                        'Validez la demande sur votre téléphone', true),
                    Divider(
                        height: 18,
                        color: Colors.white.withValues(alpha: 0.06)),
                    _pollStep(op.color, Icons.verified_rounded,
                        'Confirmation automatique par BABIFIX', false),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_rounded,
                      size: 13, color: sub),
                  const SizedBox(width: 6),
                  Text('Paiement sécurisé · vérification en cours…',
                      style: TextStyle(fontSize: 11.5, color: sub)),
                ],
              ),
              const SizedBox(height: 22),
              TextButton.icon(
                onPressed: _cancelPolling,
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Annuler le paiement'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFF87171),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pollStep(Color color, IconData icon, String label, bool active) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: active ? 0.18 : 0.07),
            shape: BoxShape.circle,
          ),
          child: Icon(icon,
              size: 18, color: active ? color : Colors.white38),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: active ? 0.95 : 0.55),
              fontSize: 13.5,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
        if (active)
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
      ],
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
                        colors: [
                          BabifixDesign.ciGreen.withValues(alpha: 0.18),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: const Icon(Icons.check_circle_rounded,
                        size: 72, color: BabifixDesign.ciGreen),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                (_quote != null && _quote!.isMobile && _quote!.acompteValide)
                    ? 'Solde payé !'
                    : 'Acompte payé !',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: text),
              ),
              const SizedBox(height: 12),
              Text(
                (_quote != null && _quote!.isMobile && _quote!.acompteValide)
                    ? 'Le paiement a bien été reçu.\n'
                        'Confirmez les travaux pour libérer le paiement au prestataire.'
                    : 'Le paiement a bien été reçu.\n'
                        'Le prestataire peut maintenant démarrer les travaux.',
                textAlign: TextAlign.center,
                style: TextStyle(color: sub, height: 1.55, fontSize: 15),
              ),
              if (widget.reservationReference.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: BabifixDesign.cyan.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: BabifixDesign.cyan.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.receipt_long_rounded,
                          size: 16, color: BabifixDesign.cyan),
                      const SizedBox(width: 8),
                      Text(
                        'Réservation N° ${widget.reservationReference}',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                            color: BabifixDesign.cyan),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: BabifixDesign.ciGreen.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: BabifixDesign.ciGreen.withValues(alpha: 0.25)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_rounded,
                        size: 16, color: BabifixDesign.ciGreen),
                    const SizedBox(width: 8),
                    Text(
                      'Fonds sécurisés · Escrow BABIFIX',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: BabifixDesign.ciGreen),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.check_circle_outline_rounded),
                  label: const Text('Terminé'),
                  style: FilledButton.styleFrom(
                    backgroundColor: BabifixDesign.ciGreen,
                    foregroundColor: BabifixDesign.navy,
                    minimumSize: const Size(double.infinity, 54),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
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
