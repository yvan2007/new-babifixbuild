import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../shared/auth_utils.dart';
import '../../shared/services/wallet_pin_dialog.dart';
import '../../shared/services/wallet_pin_service.dart';
import 'wallet_escrow_panel.dart';
import '../../shared/widgets/babifix_ring_loader.dart';
import '../../shared/widgets/babifix_snackbar.dart';
import '../../shared/widgets/payment_method_logo.dart';
import '../../shared/widgets/animated_check_circle.dart';
import '../../shared/widgets/animated_money.dart';
import '../../shared/services/confetti_toast_service.dart';
import '../../shared/services/haptics_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data helpers
// ─────────────────────────────────────────────────────────────────────────────

final _fcfa = NumberFormat.currency(locale: 'fr_FR', symbol: 'FCFA ', decimalDigits: 0);
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

const _operatorColors = {
  'mtn': Color(0xFFFFC107),
  'orange': Color(0xFFFF6B00),
  'wave': Color(0xFF00B4FF),
  'moov': Color(0xFF1565C0),
};

/// Canal interne (minuscules) -> identifiant logo de [BabifixPaymentMethodLogo].
const _operatorLogoId = {
  'mtn': 'MTN_MOMO',
  'orange': 'ORANGE_MONEY',
  'wave': 'WAVE',
  'moov': 'MOOV',
};

Color _txColor(String type) {
  return switch (type) {
    'credit' => const Color(0xFF2E7D32),
    'debit' => const Color(0xFFC62828),
    'commission' => const Color(0xFF6A1B9A),
    'refund' => const Color(0xFF00838F),
    _ => Colors.grey,
  };
}

String _txLabel(String type) {
  return switch (type) {
    'credit' => 'Paiement reçu',
    'debit' => 'Retrait',
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

/// (libellé, couleur) du statut d'une transaction de retrait.
(String, Color) _statusChip(String status) {
  return switch (status) {
    'pending' => ('En attente', const Color(0xFFF59E0B)),
    'processing' => ('Versement en cours', const Color(0xFF4CC9F0)),
    'failed' => ('Échoué — recrédité', const Color(0xFFEF4444)),
    _ => ('', Colors.grey),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Premium Colors
// ─────────────────────────────────────────────────────────────────────────────

const _premiumGold = Color(0xFFFFD700);
const _deepNavy = Color(0xFF0A0E27);
const _charcoal = Color(0xFF1A1F3A);

// ─────────────────────────────────────────────────────────────────────────────

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
  String? _error;
  double _solde = 0;
  String _walletPhone = '';
  String _walletOperator = '';
  String _walletPhone2 = '';
  String _walletOperator2 = '';
  String _lastPhone = '';
  String _lastOperator = '';
  String _prestataireName = '';
  String _cardLast4 = ''; // 4 derniers chiffres du numéro de carte unique presta
  String _cardTier = 'standard'; // abonnement → finition de la carte
  List<Map<String, dynamic>> _transactions = [];

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
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
      final token = await readStoredApiToken();
      final resp = await http.get(
        Uri.parse('${babifixApiBaseUrl()}/api/prestataire/wallet/'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        setState(() {
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
          _transactions = List<Map<String, dynamic>>.from(
            (data['transactions'] as List?) ?? [],
          );
        });
        _fadeCtrl.forward(from: 0);
      } else {
        setState(() => _error = 'Erreur serveur (${resp.statusCode})');
      }
    } catch (e) {
      setState(() => _error = 'Connexion impossible');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _openWithdrawSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WithdrawSheet(
        currentBalance: _solde,
        phone1: _walletPhone,
        operator1: _walletOperator,
        phone2: _walletPhone2,
        operator2: _walletOperator2,
        lastPhone: _lastPhone,
        lastOperator: _lastOperator,
        onManageNumbers: () {
          Navigator.of(context).pop();
          _openInfoSheet();
        },
        onSuccess: (amount) {
          Navigator.of(context).pop();
          _load();
          _showWithdrawSuccess(amount);
        },
      ),
    );
  }

  /// Animation de célébration après une demande de retrait réussie :
  /// confettis + coche dorée animée + montant qui défile. Auto-fermeture.
  void _showWithdrawSuccess(double amount) {
    HapticsService.medium();
    ConfettiService.show(context);
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (ctx) {
        Future.delayed(const Duration(milliseconds: 2800), () {
          if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
        });
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 36),
          child: Container(
            padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF1A1F3A), Color(0xFF0A0E27)],
              ),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: _premiumGold.withValues(alpha: 0.30)),
              boxShadow: [
                BoxShadow(
                  color: _premiumGold.withValues(alpha: 0.18),
                  blurRadius: 30,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AnimatedCheckCircle(size: 88, color: _premiumGold),
                const SizedBox(height: 20),
                AnimatedMoney(
                  value: amount,
                  suffix: ' FCFA',
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Retrait demandé !',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: _premiumGold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Vous recevrez le montant sur votre compte Mobile Money '
                  'après validation. Vous pouvez suivre l\'opération dans '
                  'votre historique.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Crée le code PIN de retrait (1ʳᵉ fois) ou le modifie (après vérification).
  Future<void> _managePin() async {
    final hasPin = await WalletPinService.hasPin();
    if (!mounted) return;
    if (!hasPin) {
      final ok = await showWalletPinDialog(context); // flux création
      if (ok && mounted) {
        showBabifixToast(context,
            type: BabifixToastType.success,
            message: 'Code PIN de retrait créé.');
      }
      return;
    }
    // PIN existant : on vérifie l'actuel, puis on en définit un nouveau.
    final verified = await showWalletPinDialog(context); // flux vérification
    if (!verified || !mounted) return;
    await WalletPinService.clearPin();
    if (!mounted) return;
    final created = await showWalletPinDialog(context); // re-création
    if (created && mounted) {
      showBabifixToast(context,
          type: BabifixToastType.success,
          message: 'Code PIN modifié.');
    }
  }

  void _openInfoSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MoMoInfoSheet(
        phone1: _walletPhone,
        operator1: _walletOperator,
        phone2: _walletPhone2,
        operator2: _walletOperator2,
        onSaved: (p1, o1, p2, o2) {
          Navigator.of(context).pop();
          setState(() {
            _walletPhone = p1;
            _walletOperator = o1;
            _walletPhone2 = p2;
            _walletOperator2 = o2;
          });
          showBabifixToast(
        context,
        type: BabifixToastType.info,
        message: 'Numéros de retrait mis à jour',
      );
        },
      ),
    );
  }

  String _getMaskedCardNumber() {
    // Numéro de carte UNIQUE par prestataire (fourni par le backend, dérivé de
    // son ID → jamais partagé avec un autre presta). On masque tout sauf les 4
    // derniers chiffres.
    if (_cardLast4.length == 4) {
      return '**** **** **** $_cardLast4';
    }
    // Repli : 4 derniers chiffres du numéro de retrait enregistré (sinon vide).
    if (_walletPhone.length >= 4) {
      return '**** **** **** ${_walletPhone.substring(_walletPhone.length - 4)}';
    }
    return '**** **** **** ****';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_deepNavy, Color(0xFF0D1117), Color(0xFF0A0E27)],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: widget.onBack != null
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70),
                  onPressed: widget.onBack,
                )
              : null,
          title: const Text(
            'Mon Wallet',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 20,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
          actions: [
            IconButton(
              icon: Icon(
                _balanceHidden
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                color: Colors.white70,
              ),
              tooltip: _balanceHidden ? 'Afficher le solde' : 'Masquer le solde',
              onPressed: () =>
                  setState(() => _balanceHidden = !_balanceHidden),
            ),
            IconButton(
              icon: const Icon(Icons.edit_rounded, color: _premiumGold),
              tooltip: 'Gérer mes numéros',
              onPressed: _openInfoSheet,
            ),
            IconButton(
              icon: const Icon(Icons.lock_outline_rounded, color: Colors.white70),
              tooltip: 'Code PIN de retrait',
              onPressed: _managePin,
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
              onPressed: _load,
            ),
          ],
        ),
        body: _loading
            ? const _WalletShimmer()
            : _error != null
                ? _ErrorView(message: _error!, onRetry: _load)
                : FadeTransition(
                    opacity: _fadeAnim,
                    child: RefreshIndicator(
                      onRefresh: _load,
                      color: _premiumGold,
                      backgroundColor: _charcoal,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _BalanceCard(
                            solde: _solde,
                            hidden: _balanceHidden,
                            phone: _walletPhone,
                            operator: _walletOperator,
                            prestataireName: _prestataireName,
                            maskedCardNumber: _getMaskedCardNumber(),
                            premiumTier: _cardTier,
                            onWithdraw: _solde >= 1000 ? _openWithdrawSheet : null,
                          ),
                          const SizedBox(height: 16),
                          // Phase F / Escrow — distinguer Disponible vs En attente
                          WalletEscrowPanel(
                            soldeDisponibleFcfa: _solde,
                            hidden: _balanceHidden,
                          ),
                          const SizedBox(height: 16),
                          if (_transactions.isEmpty)
                            const _EmptyTransactions()
                          else ...[
                            Row(
                              children: [
                                Container(
                                  width: 4,
                                  height: 18,
                                  decoration: BoxDecoration(
                                    color: _premiumGold,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Historique des transactions',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            ..._transactions.map(_TxTile.new),
                          ],
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Premium Balance Card
// ─────────────────────────────────────────────────────────────────────────────

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.solde,
    required this.hidden,
    required this.phone,
    required this.operator,
    required this.prestataireName,
    required this.maskedCardNumber,
    this.premiumTier = 'standard',
    this.onWithdraw,
  });

  final double solde;
  final bool hidden;
  final String phone;
  final String operator;
  final String prestataireName;
  final String maskedCardNumber;
  final String premiumTier;
  final VoidCallback? onWithdraw;

  // Finition de la carte selon l'abonnement : Standard (navy/cyan),
  // Silver (gris métal), Gold (noir + or). Différencie visuellement les tiers.
  ({List<Color> gradient, Color border, Color glow, String label}) get _theme {
    switch (premiumTier.toLowerCase()) {
      case 'gold':
        return (
          gradient: const [Color(0xFF2A2410), Color(0xFF0E0B02), Color(0xFF2A2410)],
          border: const Color(0xFFE7C463),
          glow: const Color(0xFFE7C463),
          label: 'GOLD',
        );
      case 'silver':
        return (
          gradient: const [Color(0xFF3A3F4A), Color(0xFF1A1D24), Color(0xFF3A3F4A)],
          border: const Color(0xFFC0C6D0),
          glow: const Color(0xFFC0C6D0),
          label: 'SILVER',
        );
      default:
        return (
          gradient: const [Color(0xFF1A1F3A), Color(0xFF0A0E27), Color(0xFF1A1F3A)],
          border: const Color(0xFF4CC9F0),
          glow: const Color(0xFF4CC9F0),
          label: 'STANDARD',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final opColor = _operatorColors[operator] ?? BabifixDesign.cyan;
    final th = _theme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: th.glow.withValues(alpha: 0.18),
            blurRadius: 30,
            offset: const Offset(0, 12),
            spreadRadius: 2,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cardWidth = constraints.maxWidth;
          final cardHeight = cardWidth * 0.6;
          final vPad = cardHeight < 160 ? 14.0 : 20.0;
          return SizedBox(
            width: cardWidth,
            height: cardHeight,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: th.gradient,
                  stops: const [0.0, 0.5, 1.0],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: th.border.withValues(alpha: 0.45),
                  width: 1.5,
                ),
              ),
              child: Stack(
                children: [
                  // Geometric pattern overlay
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: CustomPaint(
                        painter: _CardPatternPainter(),
                      ),
                    ),
                  ),
                  // Content
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: vPad + 4, vertical: vPad),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top row: Chip + Brand
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Chip
                            Container(
                              width: cardHeight < 160 ? 36 : 42,
                              height: cardHeight < 160 ? 26 : 30,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFFFD700),
                                    Color(0xFFFFF4B0),
                                    Color(0xFFFFD700),
                                  ],
                                  stops: [0.0, 0.5, 1.0],
                                ),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.3),
                                  width: 0.5,
                                ),
                              ),
                              child: Center(
                                child: Container(
                                  width: cardHeight < 160 ? 28 : 34,
                                  height: cardHeight < 160 ? 20 : 23,
                                  decoration: BoxDecoration(
                                    border: Border(
                                      left: BorderSide(color: Colors.black.withValues(alpha: 0.15), width: 1),
                                      right: BorderSide(color: Colors.black.withValues(alpha: 0.15), width: 1),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // BABIFIX <TIER> branding (couleur = abonnement)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: th.border.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: th.border.withValues(alpha: 0.45),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'BABIFIX',
                                    style: TextStyle(
                                      color: th.border,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    th.label,
                                    style: TextStyle(
                                      color: th.border.withValues(alpha: 0.85),
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Masked card number
                        Row(
                          children: [
                            const Icon(
                              Icons.credit_card_rounded,
                              color: _premiumGold,
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                maskedCardNumber,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.5,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        // Balance
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Flexible(
                              child: Text(
                                hidden ? '•••••• FCFA' : _fcfa.format(solde),
                                style: TextStyle(
                                  color: _premiumGold,
                                  fontSize: cardHeight < 160 ? 24 : 30,
                                  fontWeight: FontWeight.w900,
                                  height: 1.0,
                                  letterSpacing: hidden ? 2 : 0,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Holder name and operator
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'TITULAIRE',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.35),
                                      fontSize: 8,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    prestataireName.toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            if (phone.isNotEmpty) ...[
                              Container(
                                width: 1,
                                height: 24,
                                color: Colors.white.withValues(alpha: 0.15),
                              ),
                              const SizedBox(width: 8),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.phone_android_rounded,
                                    color: opColor,
                                    size: 12,
                                  ),
                                  const SizedBox(width: 3),
                                  Flexible(
                                    child: Text(
                                      phone,
                                      style: TextStyle(
                                        color: opColor.withValues(alpha: 0.9),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 10),
                        // Withdraw button
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: onWithdraw,
                            style: FilledButton.styleFrom(
                              backgroundColor: _premiumGold,
                              foregroundColor: _deepNavy,
                              disabledBackgroundColor: Colors.white.withValues(alpha: 0.1),
                              disabledForegroundColor: Colors.white38,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              padding: EdgeInsets.symmetric(
                                vertical: cardHeight < 160 ? 10 : 12,
                              ),
                              elevation: 2,
                              shadowColor: _premiumGold.withValues(alpha: 0.3),
                            ),
                            icon: const Icon(Icons.account_balance_wallet_rounded, size: 16),
                            label: Text(
                              onWithdraw == null
                                  ? 'Min. 1 000 FCFA'
                                  : 'Demander un retrait',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card Pattern Painter (geometric circles)
// ─────────────────────────────────────────────────────────────────────────────

class _CardPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _premiumGold.withValues(alpha: 0.04)
      ..style = PaintingStyle.fill;

    // Large circle top right
    canvas.drawCircle(
      Offset(size.width * 0.85, -size.height * 0.1),
      size.width * 0.4,
      paint,
    );

    // Medium circle bottom left
    canvas.drawCircle(
      Offset(-size.width * 0.1, size.height * 0.9),
      size.width * 0.3,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Transaction Tile
// ─────────────────────────────────────────────────────────────────────────────

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

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _charcoal.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: 0.2),
                color.withValues(alpha: 0.05),
              ],
            ),
            shape: BoxShape.circle,
            border: Border.all(
              color: color.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: Icon(_txIcon(type), color: color, size: 20),
        ),
        title: Text(
          _txLabel(type),
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: Colors.white,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (desc.isNotEmpty)
              Text(
                desc,
                style: const TextStyle(fontSize: 12, color: Colors.white54),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            Text(
              date,
              style: const TextStyle(fontSize: 11, color: Colors.white38),
            ),
            if (status == 'pending' ||
                status == 'processing' ||
                status == 'failed')
              Builder(builder: (_) {
                final cfg = _statusChip(status);
                return Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: cfg.$2.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: cfg.$2.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    cfg.$1,
                    style: TextStyle(
                      fontSize: 10,
                      color: cfg.$2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }),
          ],
        ),
        trailing: Text(
          '${isDebit ? '−' : '+'}${_fcfa.format(amount)}',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Modèle : une option de retrait = un numéro + un canal (natif OU Wave)
// ─────────────────────────────────────────────────────────────────────────────

class _PayoutOption {
  const _PayoutOption({
    required this.phone,
    required this.channel,
    required this.isWave,
    required this.isPrimary,
  });

  final String phone;
  final String channel; // 'orange' | 'mtn' | 'moov' | 'wave'
  final bool isWave;
  final bool isPrimary;

  String get key => '$phone|$channel';
}

/// Construit la liste des options : pour chaque numéro enregistré, son
/// opérateur natif ET Wave (Wave marche sur presque tous les numéros CI).
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
          phone: p, channel: native, isWave: false, isPrimary: primary));
    }
    out.add(_PayoutOption(
        phone: p, channel: 'wave', isWave: true, isPrimary: primary));
  }

  addFor(phone1, operator1, true);
  addFor(phone2, operator2, false);
  return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// Withdraw Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

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
      // Défaut intelligent : dernier canal utilisé, sinon 1re option.
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
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount < 1000) {
      setState(() => _err = 'Montant minimum : 1 000 FCFA');
      return;
    }
    if (amount > widget.currentBalance) {
      setState(() => _err = 'Montant supérieur au solde disponible');
      return;
    }
    final sel = _options.where((o) => o.key == _selectedKey);
    if (sel.isEmpty) {
      setState(() => _err = 'Choisissez un numéro de réception');
      return;
    }
    final chosen = sel.first;

    // ── Code PIN à 4 chiffres requis pour confirmer la transaction ──
    // (création au 1er retrait, vérification ensuite).
    final pinOk = await showWalletPinDialog(context);
    if (!pinOk) return; // annulé ou code incorrect → on n'envoie rien

    setState(() {
      _sending = true;
      _err = null;
    });

    try {
      final token = await readStoredApiToken();
      final resp = await http.post(
        Uri.parse('${babifixApiBaseUrl()}/api/prestataire/wallet/withdraw/'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
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
      setState(() => _sending = false);
    }
  }

  Widget _optionTile(_PayoutOption o) {
    final selected = o.key == _selectedKey;
    final color = _operatorColors[o.channel] ?? BabifixDesign.cyan;
    final opName = _operatorNames[o.channel] ?? o.channel;
    return GestureDetector(
      onTap: () => setState(() => _selectedKey = o.key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? color : Colors.white.withValues(alpha: 0.12),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: BabifixPaymentMethodLogo(
                methodId: _operatorLogoId[o.channel] ?? '',
                height: 32,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        opName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          o.isPrimary ? 'Principal' : 'Secours',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    o.phone,
                    style: const TextStyle(
                        color: Colors.white60, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: selected ? color : Colors.white30,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Theme(
      data: ThemeData.dark(),
      child: Container(
        margin: EdgeInsets.only(bottom: bottom),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A1F3A), Color(0xFF0A0E27)],
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(
            color: _premiumGold.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _premiumGold.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Demande de retrait',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Solde disponible : ${_fcfa.format(widget.currentBalance)}',
                style: const TextStyle(color: Colors.white60, fontSize: 13),
              ),
              const SizedBox(height: 24),
              if (_options.isEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: _premiumGold.withValues(alpha: 0.25)),
                  ),
                  child: const Text(
                    'Aucun numéro de retrait enregistré. Ajoutez d\'abord '
                    'un numéro Mobile Money pour recevoir votre argent.',
                    style: TextStyle(color: Colors.white70, fontSize: 13.5,
                        height: 1.4),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: widget.onManageNumbers,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Ajouter un numéro'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _premiumGold,
                      foregroundColor: _deepNavy,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ] else ...[
                const Text('Recevoir sur',
                    style: TextStyle(
                        color: _premiumGold,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                ..._options.map(_optionTile),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: widget.onManageNumbers,
                    icon: const Icon(Icons.tune_rounded,
                        size: 16, color: Colors.white60),
                    label: const Text('Gérer mes numéros',
                        style:
                            TextStyle(color: Colors.white60, fontSize: 12.5)),
                    style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 32)),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _amountCtrl,
                  style: const TextStyle(color: Colors.white),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: false),
                  decoration: InputDecoration(
                    labelText: 'Montant (FCFA)',
                    labelStyle: const TextStyle(color: Colors.white60),
                    prefixIcon: const Icon(
                        Icons.account_balance_wallet_rounded,
                        color: _premiumGold),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    hintText: 'Min. 1 000 FCFA',
                    hintStyle: const TextStyle(color: Colors.white30),
                  ),
                ),
                if (_err != null) ...[
                  const SizedBox(height: 10),
                  Text(_err!,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 13)),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(Icons.verified_user_rounded,
                        size: 16, color: Color(0xFF4CC9F0)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Versement sécurisé vers votre Mobile Money, '
                        'traité généralement sous 24 h après validation.',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 11.5,
                            height: 1.35),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _sending ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: _premiumGold,
                      foregroundColor: _deepNavy,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 4,
                      shadowColor: _premiumGold.withValues(alpha: 0.4),
                    ),
                    child: _sending
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: BabifixRingLoader.cyan(size: 28),
                          )
                        : const Text(
                            'Confirmer le retrait',
                            style: TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 16),
                          ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MoMo Info Sheet
// ─────────────────────────────────────────────────────────────────────────────

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
      setState(() => _err = 'Le numéro principal est requis');
      return;
    }
    if (p1.length != 10) {
      setState(() => _err = 'Le numéro principal doit faire 10 chiffres');
      return;
    }
    if (p2.isNotEmpty && p2.length != 10) {
      setState(() => _err = 'Le numéro secondaire doit faire 10 chiffres');
      return;
    }
    if (p2.isNotEmpty && p1 == p2) {
      setState(() => _err = 'Les deux numéros doivent être différents');
      return;
    }
    setState(() {
      _saving = true;
      _err = null;
    });
    try {
      final token = await readStoredApiToken();
      final resp = await http.post(
        Uri.parse('${babifixApiBaseUrl()}/api/prestataire/wallet/info/'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
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
      setState(() => _saving = false);
    }
  }

  Widget _operatorChips(String selected, ValueChanged<String> onPick) {
    return Wrap(
      spacing: 8,
      children: ['mtn', 'orange', 'wave', 'moov'].map((op) {
        final sel = selected == op;
        final color = _operatorColors[op] ?? BabifixDesign.cyan;
        return ChoiceChip(
          avatar: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
            ),
            child: BabifixPaymentMethodLogo(
              methodId: _operatorLogoId[op] ?? '',
              height: 18,
            ),
          ),
          label: Text(_operatorNames[op] ?? op),
          selected: sel,
          labelStyle: TextStyle(
            color: sel ? color : Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
          backgroundColor: Colors.white.withValues(alpha: 0.06),
          side: BorderSide(
            color: sel ? color : Colors.white.withValues(alpha: 0.2),
            width: sel ? 2 : 1,
          ),
          onSelected: (_) => onPick(op),
        );
      }).toList(),
    );
  }

  Widget _phoneField(TextEditingController c, String label) {
    return TextField(
      controller: c,
      style: const TextStyle(color: Colors.white),
      keyboardType: TextInputType.number,
      // Numéros ivoiriens : 10 chiffres, peu importe l'opérateur.
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(10),
      ],
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white60),
        prefixIcon:
            const Icon(Icons.phone_android_rounded, color: _premiumGold),
        counterText: '',
        hintText: '10 chiffres (ex. 0700000000)',
        hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Theme(
      data: ThemeData.dark(),
      child: Container(
        margin: EdgeInsets.only(bottom: bottom),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A1F3A), Color(0xFF0A0E27)],
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(
            color: _premiumGold.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _premiumGold.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Mes numéros de retrait',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Vous pourrez recevoir via l\'opérateur du numéro ou via Wave.',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6), fontSize: 12.5),
              ),
              const SizedBox(height: 20),
              // ── Numéro principal ──
              Row(children: [
                const Icon(Icons.star_rounded, size: 16, color: _premiumGold),
                const SizedBox(width: 6),
                const Text('Numéro principal',
                    style: TextStyle(
                        color: _premiumGold,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 10),
              _operatorChips(_operator1, (op) => setState(() => _operator1 = op)),
              const SizedBox(height: 12),
              _phoneField(_phone1Ctrl, 'Numéro Mobile Money principal'),
              const SizedBox(height: 22),
              // ── Numéro secondaire ──
              Row(children: [
                const Icon(Icons.backup_rounded,
                    size: 16, color: Colors.white60),
                const SizedBox(width: 6),
                const Text('Numéro secondaire (optionnel)',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 10),
              _operatorChips(_operator2, (op) => setState(() => _operator2 = op)),
              const SizedBox(height: 12),
              _phoneField(_phone2Ctrl, 'Numéro Mobile Money secondaire'),
              if (_err != null) ...[
                const SizedBox(height: 12),
                Text(_err!,
                    style:
                        const TextStyle(color: Colors.redAccent, fontSize: 13)),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: _premiumGold,
                    foregroundColor: _deepNavy,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 4,
                    shadowColor: _premiumGold.withValues(alpha: 0.4),
                  ),
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: BabifixRingLoader.cyan(size: 28))
                      : const Text('Enregistrer',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty + Error states
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyTransactions extends StatelessWidget {
  const _EmptyTransactions();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _premiumGold.withValues(alpha: 0.1),
                border: Border.all(
                  color: _premiumGold.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: const Icon(Icons.receipt_long_outlined, size: 48, color: _premiumGold),
            ),
            const SizedBox(height: 20),
            const Text(
              'Aucune transaction',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
            ),
            const SizedBox(height: 8),
            const Text(
              'Vos paiements reçus apparaîtront ici.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shimmer loader
// ─────────────────────────────────────────────────────────────────────────────

class _WalletShimmer extends StatefulWidget {
  const _WalletShimmer();
  @override
  State<_WalletShimmer> createState() => _WalletShimmerState();
}

class _WalletShimmerState extends State<_WalletShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(duration: const Duration(milliseconds: 1300), vsync: this)..repeat();
    _anim = Tween<double>(begin: -1.5, end: 1.5).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Widget _box(double w, double h, {double r = 8}) => Container(
    width: w == double.infinity ? null : w,
    height: h,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(r),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        final grad = LinearGradient(
          begin: Alignment(_anim.value - 1, 0),
          end: Alignment(_anim.value + 1, 0),
          colors: const [Color(0xFF1A1F3A), Color(0xFF2A2F4A), Color(0xFF1A1F3A)],
        );
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Balance card shimmer
            AspectRatio(
              aspectRatio: 16 / 10,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: grad,
                  border: Border.all(color: _premiumGold.withValues(alpha: 0.2)),
                ),
              ),
            ),
            const SizedBox(height: 28),
            _box(140, 16, r: 6),
            const SizedBox(height: 12),
            ...List.generate(5, (_) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: grad,
              ),
              child: Row(
                children: [
                  _box(44, 44, r: 22),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _box(double.infinity, 13, r: 6),
                      const SizedBox(height: 6),
                      _box(100, 11, r: 6),
                    ],
                  )),
                  const SizedBox(width: 12),
                  _box(64, 18, r: 6),
                ],
              ),
            )),
          ],
        );
      },
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.red.withValues(alpha: 0.1),
            ),
            child: const Icon(Icons.cloud_off_rounded, size: 40, color: Colors.white54),
          ),
          const SizedBox(height: 16),
          Text(message, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onRetry,
            style: FilledButton.styleFrom(
              backgroundColor: _premiumGold,
              foregroundColor: _deepNavy,
            ),
            child: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }
}
