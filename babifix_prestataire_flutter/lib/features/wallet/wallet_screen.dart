import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../shared/auth_utils.dart';
import '../../shared/services/babifix_remote_config.dart';
import '../../shared/services/confetti_toast_service.dart';
import '../../shared/services/haptics_service.dart';
import '../../shared/services/wallet_pin_dialog.dart';
import '../../shared/services/wallet_pin_service.dart';
import '../../shared/widgets/animated_check_circle.dart';
import '../../shared/widgets/animated_money.dart';
import '../../shared/widgets/babifix_button.dart';
import '../../shared/widgets/babifix_sheet.dart';
import '../../shared/widgets/babifix_skeleton.dart';
import '../../shared/widgets/babifix_snackbar.dart';
import '../../shared/widgets/payment_method_logo.dart';
import 'babifix_wallet_card.dart';
import 'wallet_escrow_panel.dart';

final _fcfa =
    NumberFormat.currency(locale: 'fr_FR', symbol: 'FCFA ', decimalDigits: 0);
final _dateFmt = DateFormat('dd/MM/yyyy HH:mm');

String _fmtDate(String? iso) {
  if (iso == null) return '';
  try {
    return _dateFmt.format(DateTime.parse(iso).toLocal());
  } catch (_) {
    return iso;
  }
}

const _operatorNames = {
  'mtn': 'MTN Mobile Money',
  'orange': 'Orange Money',
  'wave': 'Wave',
  'moov': 'Moov Money',
};

const _operatorLogoId = {
  'mtn': 'MTN_MOMO',
  'orange': 'ORANGE_MONEY',
  'wave': 'WAVE',
  'moov': 'MOOV',
};

Color _txColor(String type) {
  return switch (type) {
    'credit' => const Color(0xFF16A34A),
    'debit' => const Color(0xFFDC2626),
    'commission' => const Color(0xFF7C3AED),
    'refund' => const Color(0xFF0284C7),
    _ => const Color(0xFF64748B),
  };
}

String _txLabel(String type) {
  return switch (type) {
    'credit' => 'Paiement recu',
    'debit' => 'Retrait Mobile Money',
    'commission' => 'Commission BABIFIX',
    'refund' => 'Remboursement',
    _ => type,
  };
}

IconData _txIcon(String type) {
  return switch (type) {
    'credit' => Icons.arrow_downward_rounded,
    'debit' => Icons.arrow_upward_rounded,
    'commission' => Icons.percent_rounded,
    'refund' => Icons.replay_rounded,
    _ => Icons.swap_horiz_rounded,
  };
}

(String, Color) _statusChip(String status) {
  return switch (status) {
    'pending' => ('En attente', const Color(0xFFF59E0B)),
    'processing' => ('Versement en cours', const Color(0xFF0284C7)),
    'failed' => ('Echoue : recredite', const Color(0xFFEF4444)),
    _ => ('', const Color(0xFF64748B)),
  };
}

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key, this.onBack, this.paletteMode});

  final VoidCallback? onBack;
  final dynamic paletteMode;

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  bool _balanceHidden = false;
  bool _pinActive = false;
  String? _error;
  double _solde = 0;
  String _walletPhone = '';
  String _walletOperator = '';
  String _walletPhone2 = '';
  String _walletOperator2 = '';
  String _lastPhone = '';
  String _lastOperator = '';
  String _prestataireName = '';
  String _cardLast4 = '';
  String _cardTier = 'standard';
  String _verifyQrUrl = '';
  bool _kycVerified = false;
  List<Map<String, dynamic>> _transactions = [];

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: BabifixDesign.curveOut);
    _load();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pinFuture = WalletPinService.hasPin();
      final resp = await babifixAuthGet(
        '${babifixApiBaseUrl()}/api/prestataire/wallet/',
      );
      final pin = await pinFuture;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        if (!mounted) return;
        setState(() {
          _pinActive = pin;
          _solde = (data['solde_fcfa'] as num?)?.toDouble() ?? 0;
          _walletPhone = data['wallet_phone'] as String? ?? '';
          _walletOperator = data['wallet_operator'] as String? ?? '';
          _walletPhone2 = data['wallet_phone_2'] as String? ?? '';
          _walletOperator2 = data['wallet_operator_2'] as String? ?? '';
          _lastPhone = data['wallet_last_phone'] as String? ?? '';
          _lastOperator = data['wallet_last_operator'] as String? ?? '';
          _prestataireName = data['prestataire_nom'] as String? ?? 'PRESTATAIRE';
          _cardLast4 = (data['card_last4'] as String?) ?? '';
          _cardTier = (data['premium_tier'] as String?) ?? 'standard';
          _verifyQrUrl = (data['verify_qr_url'] as String?) ?? '';
          _kycVerified = data['kyc_verified'] == true;
          _transactions = List<Map<String, dynamic>>.from(
            (data['transactions'] as List?) ?? [],
          );
        });
        _fadeCtrl.forward(from: 0);
      } else {
        if (!mounted) return;
        setState(() => _error = 'Erreur serveur (${resp.statusCode})');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Connexion impossible');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openWithdrawSheet() {
    showBabifixModalSheet<void>(
      context: context,
      builder: (ctx) => _WithdrawSheet(
        currentBalance: _solde,
        phone1: _walletPhone,
        operator1: _walletOperator,
        phone2: _walletPhone2,
        operator2: _walletOperator2,
        lastPhone: _lastPhone,
        lastOperator: _lastOperator,
        onManageNumbers: () {
          Navigator.of(ctx).pop();
          _openInfoSheet();
        },
        onSuccess: (amount) {
          Navigator.of(ctx).pop();
          _load();
          _showWithdrawSuccess(amount);
        },
      ),
    );
  }

  void _showWithdrawSuccess(double amount) {
    HapticsService.medium();
    ConfettiService.show(context);
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (ctx) {
        Future.delayed(const Duration(milliseconds: 2800), () {
          if (ctx.mounted && Navigator.of(ctx).canPop()) {
            Navigator.of(ctx).pop();
          }
        });
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 32),
          child: Container(
            padding: const EdgeInsets.fromLTRB(26, 30, 26, 26),
            decoration: BoxDecoration(
              color: BabifixDesign.navy,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: BabifixDesign.goldBrass.withValues(alpha: 0.45),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AnimatedCheckCircle(
                  size: 84,
                  color: BabifixDesign.goldBrass,
                ),
                const SizedBox(height: 18),
                AnimatedMoney(
                  value: amount,
                  suffix: ' FCFA',
                  style: BabifixDesign.amountStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Retrait demande',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: BabifixDesign.goldBrass,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Vous recevrez le versement sur votre compte Mobile Money des validation.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: Colors.white.withValues(alpha: 0.78),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _managePin() async {
    final hasPin = await WalletPinService.hasPin();
    if (!mounted) return;
    if (!hasPin) {
      final ok = await showWalletPinDialog(context);
      if (ok && mounted) {
        setState(() => _pinActive = true);
        showBabifixToast(
          context,
          type: BabifixToastType.success,
          message: 'Code PIN de retrait cree.',
        );
      }
      return;
    }
    final verified = await showWalletPinDialog(context);
    if (!verified || !mounted) return;
    await WalletPinService.clearPin();
    if (!mounted) return;
    final created = await showWalletPinDialog(context);
    if (created && mounted) {
      setState(() => _pinActive = true);
      showBabifixToast(
        context,
        type: BabifixToastType.success,
        message: 'Code PIN modifie.',
      );
    }
  }

  void _openInfoSheet() {
    showBabifixModalSheet<void>(
      context: context,
      builder: (ctx) => _MoMoInfoSheet(
        phone1: _walletPhone,
        operator1: _walletOperator,
        phone2: _walletPhone2,
        operator2: _walletOperator2,
        onSaved: (p1, o1, p2, o2) {
          Navigator.of(ctx).pop();
          setState(() {
            _walletPhone = p1;
            _walletOperator = o1;
            _walletPhone2 = p2;
            _walletOperator2 = o2;
          });
          showBabifixToast(
            context,
            type: BabifixToastType.info,
            message: 'Numeros de retrait mis a jour',
          );
        },
      ),
    );
  }

  String _getMaskedCardNumber() {
    if (_cardLast4.length == 4) {
      return '**** **** **** $_cardLast4';
    }
    if (_walletPhone.length >= 4) {
      return '**** **** **** ${_walletPhone.substring(_walletPhone.length - 4)}';
    }
    return '**** **** **** ****';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = BabifixDesign.isDark(context);
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final titleColor = BabifixDesign.textPrimaryOf(context);
    final muted = BabifixDesign.textMutedOf(context);
    final tier = BabifixWalletTier.fromString(_cardTier);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: widget.onBack != null
            ? IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded, color: titleColor, size: 20),
                onPressed: widget.onBack,
              )
            : null,
        title: Text(
          'Mon Wallet',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            color: titleColor,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _balanceHidden ? Icons.visibility_off_rounded : Icons.visibility_rounded,
              color: muted,
            ),
            tooltip: _balanceHidden ? 'Afficher le solde' : 'Masquer le solde',
            onPressed: () => setState(() => _balanceHidden = !_balanceHidden),
          ),
          IconButton(
            icon: Icon(
              _pinActive ? Icons.lock_rounded : Icons.lock_open_rounded,
              color: _pinActive ? BabifixDesign.success : BabifixDesign.ciOrange,
            ),
            tooltip: 'Code PIN de retrait',
            onPressed: _managePin,
          ),
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: muted),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const BabifixSkeletonWallet()
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _load)
              : FadeTransition(
                  opacity: _fadeAnim,
                  child: RefreshIndicator(
                    onRefresh: _load,
                    color: isDark ? BabifixDesign.cyan : BabifixDesign.ciOrange,
                    backgroundColor: BabifixDesign.surfaceOf(context),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
                      children: [
                        BabifixWalletCard(
                          soldeFcfa: _solde,
                          hidden: _balanceHidden,
                          prestataireName: _prestataireName,
                          maskedCardNumber: _getMaskedCardNumber(),
                          tier: tier,
                          phonePrimary: _walletPhone,
                          operatorPrimary: _walletOperator,
                          phoneSecondary: _walletPhone2,
                          operatorSecondary: _walletOperator2,
                          pinActive: _pinActive,
                          verifyQrUrl: _verifyQrUrl,
                          kycVerified: _kycVerified,
                          onToggleHidden: () =>
                              setState(() => _balanceHidden = !_balanceHidden),
                        ),
                        const SizedBox(height: 14),
                        // Dock d'actions principal place sous la carte (Planche 4)
                        Builder(
                          builder: (context) {
                            final minW = BabifixRemoteConfig.instance.current.minWithdrawalFcfa;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: BabifixButton(
                                        label: 'Retirer des fonds',
                                        icon: Icons.arrow_upward_rounded,
                                        variant: BabifixButtonVariant.primary,
                                        onPressed: _solde >= minW ? _openWithdrawSheet : null,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      flex: 2,
                                      child: BabifixButton(
                                        label: 'Comptes',
                                        icon: Icons.phone_android_rounded,
                                        variant: BabifixButtonVariant.outlined,
                                        onPressed: _openInfoSheet,
                                      ),
                                    ),
                                  ],
                                ),
                                if (_solde < minW) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(Icons.info_outline_rounded, size: 14, color: muted),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Retrait possible des $minW FCFA disponibles.',
                                        style: TextStyle(fontSize: 12, color: muted),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        WalletEscrowPanel(
                          soldeDisponibleFcfa: _solde,
                          hidden: _balanceHidden,
                        ),
                        const SizedBox(height: 22),
                        if (_transactions.isEmpty)
                          const _EmptyTransactions()
                        else ...[
                          Row(
                            children: [
                              Text(
                                'Historique des transactions',
                                style: TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w800,
                                  color: titleColor,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${_transactions.length} op.',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: muted,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ..._transactions.map(_TxTile.new),
                        ],
                      ],
                    ),
                  ),
                ),
    );
  }
}

class _TxTile extends StatelessWidget {
  const _TxTile(this.tx);
  final Map<String, dynamic> tx;

  @override
  Widget build(BuildContext context) {
    final type = tx['type'] as String? ?? '';
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
    final status = tx['status'] as String? ?? 'success';
    final date = _fmtDate(tx['created_at'] as String?);
    final desc = tx['description'] as String? ?? '';
    final color = _txColor(type);
    final isDebit = type == 'debit' || type == 'commission';

    final surface = BabifixDesign.surfaceOf(context);
    final border = BabifixDesign.borderOf(context);
    final titleColor = BabifixDesign.textPrimaryOf(context);
    final subColor = BabifixDesign.textMutedOf(context);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _showTxDetail(context, tx),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_txIcon(type), color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _txLabel(type),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: titleColor,
                    ),
                  ),
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      desc,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: subColor),
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(date, style: TextStyle(fontSize: 11, color: subColor)),
                  if (status == 'pending' || status == 'processing' || status == 'failed')
                    Builder(
                      builder: (_) {
                        final cfg = _statusChip(status);
                        return Container(
                          margin: const EdgeInsets.only(top: 5),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: cfg.$2.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            cfg.$1,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: cfg.$2,
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${isDebit ? '-' : '+'}${_fcfa.format(amount.round())}',
              style: BabifixDesign.amountStyle(
                color: isDebit ? const Color(0xFFEF4444) : BabifixDesign.success,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTxDetail(BuildContext context, Map<String, dynamic> tx) {
    final type = tx['type'] as String? ?? '';
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
    final ref = (tx['reference'] ?? tx['id'] ?? '').toString();
    final desc = (tx['description'] ?? '').toString();
    final date = _fmtDate(tx['created_at'] as String?);
    final isDebit = type == 'debit' || type == 'commission';
    final titleColor = BabifixDesign.textPrimaryOf(context);
    final subColor = BabifixDesign.textMutedOf(context);

    showBabifixModalSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _txColor(type).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(_txIcon(type), color: _txColor(type)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _txLabel(type),
                          style: TextStyle(
                            color: titleColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (date.isNotEmpty)
                          Text(date, style: TextStyle(color: subColor, fontSize: 12)),
                      ],
                    ),
                  ),
                  Text(
                    '${isDebit ? '-' : '+'}${_fcfa.format(amount.round())}',
                    style: BabifixDesign.amountStyle(
                      color: isDebit ? const Color(0xFFEF4444) : BabifixDesign.success,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              if (desc.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(desc, style: TextStyle(color: titleColor, fontSize: 13.5, height: 1.4)),
              ],
              if (ref.isNotEmpty) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text('Reference : $ref', style: TextStyle(color: subColor, fontSize: 12)),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: ref));
                        Navigator.of(ctx).pop();
                        showBabifixToast(
                          context,
                          type: BabifixToastType.success,
                          message: 'Reference copiee',
                        );
                      },
                      icon: const Icon(Icons.copy_rounded, size: 15),
                      label: const Text('Copier'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PayoutOption {
  const _PayoutOption({
    required this.phone,
    required this.channel,
    required this.isWave,
    required this.isPrimary,
  });

  final String phone;
  final String channel;
  final bool isWave;
  final bool isPrimary;

  String get key => '$phone|$channel';
}

List<_PayoutOption> _buildPayoutOptions({
  required String phone1,
  required String operator1,
  required String phone2,
  required String operator2,
}) {
  final out = <_PayoutOption>[];
  void addFor(String phone, String nativeOp, bool primary) {
    final p = phone.trim();
    if (p.isEmpty) return;
    final native = nativeOp.trim().toLowerCase();
    if (native.isNotEmpty && native != 'wave') {
      out.add(_PayoutOption(
        phone: p,
        channel: native,
        isWave: false,
        isPrimary: primary,
      ));
    }
    out.add(_PayoutOption(
      phone: p,
      channel: 'wave',
      isWave: true,
      isPrimary: primary,
    ));
  }

  addFor(phone1, operator1, true);
  addFor(phone2, operator2, false);
  return out;
}

class _WithdrawSheet extends StatefulWidget {
  const _WithdrawSheet({
    required this.currentBalance,
    required this.phone1,
    required this.operator1,
    required this.phone2,
    required this.operator2,
    required this.lastPhone,
    required this.lastOperator,
    required this.onManageNumbers,
    required this.onSuccess,
  });

  final double currentBalance;
  final String phone1;
  final String operator1;
  final String phone2;
  final String operator2;
  final String lastPhone;
  final String lastOperator;
  final VoidCallback onManageNumbers;
  final ValueChanged<double> onSuccess;

  @override
  State<_WithdrawSheet> createState() => _WithdrawSheetState();
}

class _WithdrawSheetState extends State<_WithdrawSheet> {
  final _amountCtrl = TextEditingController();
  late final List<_PayoutOption> _options;
  String? _selectedKey;
  bool _sending = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _options = _buildPayoutOptions(
      phone1: widget.phone1,
      operator1: widget.operator1,
      phone2: widget.phone2,
      operator2: widget.operator2,
    );
    if (_options.isNotEmpty) {
      final lastKey =
          '${widget.lastPhone.trim()}|${widget.lastOperator.trim().toLowerCase()}';
      final match = _options.where((o) => o.key == lastKey);
      _selectedKey = match.isNotEmpty ? match.first.key : _options.first.key;
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final minW = BabifixRemoteConfig.instance.current.minWithdrawalFcfa;
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount < minW) {
      setState(() => _err = 'Montant minimum : $minW FCFA');
      return;
    }
    if (amount > widget.currentBalance) {
      setState(() => _err = 'Montant superieur au solde disponible');
      return;
    }
    final sel = _options.where((o) => o.key == _selectedKey);
    if (sel.isEmpty) {
      setState(() => _err = 'Choisissez un numero de reception');
      return;
    }
    final chosen = sel.first;

    final pinOk = await showWalletPinDialog(context);
    if (!pinOk) return;

    setState(() {
      _sending = true;
      _err = null;
    });

    try {
      final resp = await babifixAuthPost(
        '${babifixApiBaseUrl()}/api/prestataire/wallet/withdraw/',
        body: jsonEncode({
          'amount_fcfa': amount,
          'phone': chosen.phone,
          'operator': chosen.channel,
        }),
      );
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode == 200) {
        widget.onSuccess(amount);
      } else {
        setState(() => _err = data['detail'] as String? ?? 'Erreur retrait');
      }
    } catch (_) {
      setState(() => _err = 'Connexion impossible');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _optionTile(_PayoutOption o) {
    final selected = o.key == _selectedKey;
    final logoId = _operatorLogoId[o.channel] ?? o.channel;
    final opLabel = _operatorNames[o.channel] ?? o.channel.toUpperCase();
    final isDark = BabifixDesign.isDark(context);
    final surface = BabifixDesign.surfaceOf(context);
    final border = BabifixDesign.borderOf(context);
    final titleColor = BabifixDesign.textPrimaryOf(context);
    final muted = BabifixDesign.textMutedOf(context);

    return GestureDetector(
      onTap: () {
        HapticsService.selection();
        setState(() => _selectedKey = o.key);
      },
      child: AnimatedContainer(
        duration: BabifixDesign.durationFast,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: selected
              ? (isDark
                  ? BabifixDesign.cyan.withValues(alpha: 0.12)
                  : BabifixDesign.ciOrange.withValues(alpha: 0.07))
              : surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? (isDark ? BabifixDesign.cyan : BabifixDesign.ciOrange)
                : border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            BabifixPaymentMethodBadge(
              methodId: logoId,
              size: 40,
              selected: selected,
              onDarkSurface: isDark,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          o.phone,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14.5,
                            color: titleColor,
                            fontFeatures: BabifixDesign.tabularFigures,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: muted.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          o.isPrimary ? 'Principal' : 'Secondaire',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    o.isWave ? 'Via Wave ($opLabel)' : opLabel,
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ],
              ),
            ),
            Icon(
              selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              color: selected
                  ? (isDark ? BabifixDesign.cyan : BabifixDesign.ciOrange)
                  : muted,
              size: 21,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titleColor = BabifixDesign.textPrimaryOf(context);
    final muted = BabifixDesign.textMutedOf(context);
    final isDark = BabifixDesign.isDark(context);
    final quickAmounts = [5000, 10000, 25000]
        .where((v) => v <= widget.currentBalance)
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Retirer des fonds',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: titleColor,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Disponible : ${_fcfa.format(widget.currentBalance.round())}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: BabifixDesign.success,
                        fontFeatures: BabifixDesign.tabularFigures,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: widget.onManageNumbers,
                icon: const Icon(Icons.edit_rounded, size: 15),
                label: const Text('Comptes'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_options.isEmpty) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: BabifixDesign.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: BabifixDesign.warning.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: BabifixDesign.warning),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Configurez d abord au moins un numero Mobile Money.',
                      style: TextStyle(fontSize: 13, color: titleColor),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            BabifixButton(
              label: 'Configurer mes numeros',
              icon: Icons.phone_android_rounded,
              width: double.infinity,
              onPressed: widget.onManageNumbers,
            ),
          ] else ...[
            Text(
              'Canal de versement',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: muted,
              ),
            ),
            const SizedBox(height: 8),
            ..._options.map(_optionTile),
            const SizedBox(height: 10),
            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: BabifixDesign.amountStyle(
                color: titleColor,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
              decoration: const InputDecoration(
                labelText: 'Montant a retirer (FCFA)',
                hintText: 'Minimum 1 000 FCFA',
                suffixText: 'FCFA',
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ...quickAmounts.map(
                  (v) => ActionChip(
                    backgroundColor: isDark
                        ? BabifixDesign.navyElevated
                        : const Color(0xFFF1F5F9),
                    side: BorderSide(
                      color: isDark ? BabifixDesign.borderDark : BabifixDesign.borderLight,
                    ),
                    labelStyle: TextStyle(
                      color: titleColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                    label: Text('${NumberFormat('#,##0', 'fr_FR').format(v)} F'),
                    onPressed: () {
                      HapticsService.selection();
                      setState(() {
                        _amountCtrl.text = '$v';
                        _err = null;
                      });
                    },
                  ),
                ),
                ActionChip(
                  label: const Text('Tout retirer'),
                  backgroundColor: isDark
                      ? BabifixDesign.cyan.withValues(alpha: 0.16)
                      : BabifixDesign.ciOrange.withValues(alpha: 0.12),
                  side: BorderSide(
                    color: isDark
                        ? BabifixDesign.cyan.withValues(alpha: 0.45)
                        : BabifixDesign.ciOrange.withValues(alpha: 0.4),
                  ),
                  labelStyle: TextStyle(
                    color: isDark ? BabifixDesign.cyan : BabifixDesign.ciOrange,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                  onPressed: () {
                    HapticsService.selection();
                    setState(() {
                      _amountCtrl.text = '${widget.currentBalance.floor()}';
                      _err = null;
                    });
                  },
                ),
              ],
            ),
            if (_err != null) ...[
              const SizedBox(height: 10),
              Text(
                _err!,
                style: const TextStyle(
                  color: BabifixDesign.error,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 16),
            BabifixButton(
              label: 'Confirmer le retrait',
              icon: Icons.lock_rounded,
              width: double.infinity,
              isLoading: _sending,
              loadingLabel: 'Envoi en cours...',
              onPressed: _submit,
            ),
          ],
        ],
      ),
    );
  }
}

class _MoMoInfoSheet extends StatefulWidget {
  const _MoMoInfoSheet({
    required this.phone1,
    required this.operator1,
    required this.phone2,
    required this.operator2,
    required this.onSaved,
  });

  final String phone1;
  final String operator1;
  final String phone2;
  final String operator2;
  final void Function(String p1, String o1, String p2, String o2) onSaved;

  @override
  State<_MoMoInfoSheet> createState() => _MoMoInfoSheetState();
}

class _MoMoInfoSheetState extends State<_MoMoInfoSheet> {
  late final TextEditingController _phone1Ctrl;
  late final TextEditingController _phone2Ctrl;
  late String _operator1;
  late String _operator2;
  bool _saving = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _phone1Ctrl = TextEditingController(text: widget.phone1);
    _phone2Ctrl = TextEditingController(text: widget.phone2);
    _operator1 = widget.operator1.isNotEmpty ? widget.operator1 : 'orange';
    _operator2 = widget.operator2.isNotEmpty ? widget.operator2 : 'mtn';
  }

  @override
  void dispose() {
    _phone1Ctrl.dispose();
    _phone2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final p1 = _phone1Ctrl.text.trim();
    final p2 = _phone2Ctrl.text.trim();
    if (p1.isEmpty) {
      setState(() => _err = 'Le numero principal est requis');
      return;
    }
    if (p1.length != 10) {
      setState(() => _err = 'Le numero principal doit faire 10 chiffres');
      return;
    }
    if (p2.isNotEmpty && p2.length != 10) {
      setState(() => _err = 'Le numero secondaire doit faire 10 chiffres');
      return;
    }
    if (p2.isNotEmpty && p1 == p2) {
      setState(() => _err = 'Les deux numeros doivent etre differents');
      return;
    }
    setState(() {
      _saving = true;
      _err = null;
    });
    try {
      final resp = await babifixAuthPost(
        '${babifixApiBaseUrl()}/api/prestataire/wallet/info/',
        body: jsonEncode({
          'phone': p1,
          'operator': _operator1,
          'phone_2': p2,
          'operator_2': p2.isEmpty ? '' : _operator2,
        }),
      );
      if (resp.statusCode == 200) {
        widget.onSaved(p1, _operator1, p2, p2.isEmpty ? '' : _operator2);
      } else {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        setState(() => _err = data['error'] as String? ?? 'Erreur enregistrement');
      }
    } catch (_) {
      setState(() => _err = 'Connexion impossible');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _operatorChips(String selected, ValueChanged<String> onPick) {
    final isDark = BabifixDesign.isDark(context);
    final surface = BabifixDesign.surfaceOf(context);
    final border = BabifixDesign.borderOf(context);
    final textColor = BabifixDesign.textPrimaryOf(context);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: ['mtn', 'orange', 'wave', 'moov'].map((op) {
        final sel = selected == op;
        final logoId = _operatorLogoId[op] ?? op;
        final shortLabel = switch (op) {
          'orange' => 'Orange',
          'mtn' => 'MTN',
          'wave' => 'Wave',
          _ => 'Moov',
        };
        return GestureDetector(
          onTap: () {
            HapticsService.selection();
            onPick(op);
          },
          child: AnimatedContainer(
            duration: BabifixDesign.durationFast,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: sel
                  ? (isDark
                      ? BabifixDesign.cyan.withValues(alpha: 0.14)
                      : BabifixDesign.ciOrange.withValues(alpha: 0.09))
                  : surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: sel
                    ? (isDark ? BabifixDesign.cyan : BabifixDesign.ciOrange)
                    : border,
                width: sel ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                BabifixPaymentMethodBadge(
                  methodId: logoId,
                  size: 26,
                  selected: sel,
                  onDarkSurface: isDark,
                ),
                const SizedBox(width: 7),
                Text(
                  shortLabel,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titleColor = BabifixDesign.textPrimaryOf(context);
    final muted = BabifixDesign.textMutedOf(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Numeros Mobile Money',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: titleColor,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Enregistrez jusqu a 2 numeros pour recevoir vos retraits instantanes.',
            style: TextStyle(fontSize: 13, color: muted),
          ),
          const SizedBox(height: 16),
          Text(
            'Numero principal',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: titleColor,
            ),
          ),
          const SizedBox(height: 8),
          _operatorChips(_operator1, (v) => setState(() => _operator1 = v)),
          const SizedBox(height: 10),
          TextField(
            controller: _phone1Ctrl,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Telephone principal (10 chiffres)',
              hintText: '07XXXXXXXX',
              counterText: '',
              prefixIcon: Icon(Icons.phone_android_rounded),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Numero secondaire (optionnel)',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: titleColor,
            ),
          ),
          const SizedBox(height: 8),
          _operatorChips(_operator2, (v) => setState(() => _operator2 = v)),
          const SizedBox(height: 10),
          TextField(
            controller: _phone2Ctrl,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Telephone secondaire (10 chiffres)',
              hintText: '05XXXXXXXX',
              counterText: '',
              prefixIcon: Icon(Icons.phone_android_rounded),
            ),
          ),
          if (_err != null) ...[
            const SizedBox(height: 10),
            Text(
              _err!,
              style: const TextStyle(
                color: BabifixDesign.error,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 18),
          BabifixButton(
            label: 'Enregistrer',
            icon: Icons.check_rounded,
            width: double.infinity,
            isLoading: _saving,
            loadingLabel: 'Enregistrement...',
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}

class _EmptyTransactions extends StatelessWidget {
  const _EmptyTransactions();

  @override
  Widget build(BuildContext context) {
    final surface = BabifixDesign.surfaceOf(context);
    final border = BabifixDesign.borderOf(context);
    final titleColor = BabifixDesign.textPrimaryOf(context);
    final muted = BabifixDesign.textMutedOf(context);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: muted.withValues(alpha: 0.10),
            ),
            child: Icon(Icons.receipt_long_rounded, size: 28, color: muted),
          ),
          const SizedBox(height: 14),
          Text(
            'Aucune transaction pour le moment',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: titleColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Vos paiements clients et retraits Mobile Money apparaitront ici.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: muted),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final muted = BabifixDesign.textMutedOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: BabifixDesign.error.withValues(alpha: 0.12),
              ),
              child: const Icon(
                Icons.cloud_off_rounded,
                size: 36,
                color: BabifixDesign.error,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 14),
            ),
            const SizedBox(height: 16),
            BabifixButton(
              label: 'Reessayer',
              icon: Icons.refresh_rounded,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
