import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../shared/auth_utils.dart';

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
  String? _error;
  double _solde = 0;
  String _walletPhone = '';
  String _walletOperator = '';
  String _prestataireName = '';
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
          _prestataireName = data['prestataire_nom'] as String? ?? 'PRESTATAIRE';
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
        currentPhone: _walletPhone,
        currentOperator: _walletOperator,
        onSuccess: () {
          Navigator.of(context).pop();
          _load();
        },
      ),
    );
  }

  void _openInfoSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MoMoInfoSheet(
        currentPhone: _walletPhone,
        currentOperator: _walletOperator,
        onSaved: (phone, op) {
          Navigator.of(context).pop();
          setState(() {
            _walletPhone = phone;
            _walletOperator = op;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Informations Mobile Money mises à jour')),
          );
        },
      ),
    );
  }

  String _getMaskedCardNumber() {
    if (_walletPhone.length >= 4) {
      final last4 = _walletPhone.substring(_walletPhone.length - 4);
      return '**** **** **** $last4';
    }
    return '**** **** **** 5432';
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
              icon: const Icon(Icons.edit_rounded, color: _premiumGold),
              tooltip: 'Gérer mon Mobile Money',
              onPressed: _openInfoSheet,
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
                            phone: _walletPhone,
                            operator: _walletOperator,
                            prestataireName: _prestataireName,
                            maskedCardNumber: _getMaskedCardNumber(),
                            onWithdraw: _solde >= 1000 ? _openWithdrawSheet : null,
                          ),
                          const SizedBox(height: 28),
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
    required this.phone,
    required this.operator,
    required this.prestataireName,
    required this.maskedCardNumber,
    this.onWithdraw,
  });

  final double solde;
  final String phone;
  final String operator;
  final String prestataireName;
  final String maskedCardNumber;
  final VoidCallback? onWithdraw;

  @override
  Widget build(BuildContext context) {
    final opColor = _operatorColors[operator] ?? BabifixDesign.cyan;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: _premiumGold.withValues(alpha: 0.15),
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
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF1A1F3A),
                    Color(0xFF0A0E27),
                    Color(0xFF1A1F3A),
                  ],
                  stops: [0.0, 0.5, 1.0],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: _premiumGold.withValues(alpha: 0.3),
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
                            // BABIFIX PREMIUM branding
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: _premiumGold.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: _premiumGold.withValues(alpha: 0.4),
                                  width: 1,
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'BABIFIX',
                                    style: TextStyle(
                                      color: _premiumGold,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                  SizedBox(width: 3),
                                  Text(
                                    'PREMIUM',
                                    style: TextStyle(
                                      color: Color(0xFFFFF4B0),
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
                                _fcfa.format(solde),
                                style: TextStyle(
                                  color: _premiumGold,
                                  fontSize: cardHeight < 160 ? 24 : 30,
                                  fontWeight: FontWeight.w900,
                                  height: 1.0,
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
            if (status == 'pending')
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.3),
                  ),
                ),
                child: const Text(
                  'En attente',
                  style: TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.w600),
                ),
              ),
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
// Withdraw Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _WithdrawSheet extends StatefulWidget {
  const _WithdrawSheet({
    required this.currentBalance,
    required this.currentPhone,
    required this.currentOperator,
    required this.onSuccess,
  });

  final double currentBalance;
  final String currentPhone;
  final String currentOperator;
  final VoidCallback onSuccess;

  @override
  State<_WithdrawSheet> createState() => _WithdrawSheetState();
}

class _WithdrawSheetState extends State<_WithdrawSheet> {
  final _amountCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String _operator = 'mtn';
  bool _sending = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    if (widget.currentPhone.isNotEmpty) _phoneCtrl.text = widget.currentPhone;
    if (widget.currentOperator.isNotEmpty) _operator = widget.currentOperator;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amountStr = _amountCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final amount = double.tryParse(amountStr);

    if (amount == null || amount < 1000) {
      setState(() => _err = 'Montant minimum : 1 000 FCFA');
      return;
    }
    if (amount > widget.currentBalance) {
      setState(() => _err = 'Montant supérieur au solde disponible');
      return;
    }
    if (phone.isEmpty) {
      setState(() => _err = 'Numéro Mobile Money requis');
      return;
    }

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
          'phone': phone,
          'operator': _operator,
        }),
      );
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode == 200) {
        widget.onSuccess();
      } else {
        setState(() => _err = data['detail'] as String? ?? 'Erreur retrait');
      }
    } catch (_) {
      setState(() => _err = 'Connexion impossible');
    } finally {
      setState(() => _sending = false);
    }
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
          const Text('Opérateur', style: TextStyle(color: _premiumGold, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: ['mtn', 'orange', 'wave', 'moov'].map((op) {
              final selected = _operator == op;
              final color = _operatorColors[op] ?? BabifixDesign.cyan;
              return ChoiceChip(
                label: Text(_operatorNames[op] ?? op),
                selected: selected,
                labelStyle: TextStyle(
                  color: selected ? color : Colors.white,
                  fontWeight: FontWeight.w700,
                ),
                backgroundColor: Colors.white.withValues(alpha: 0.06),
                side: BorderSide(
                  color: selected ? color : Colors.white.withValues(alpha: 0.2),
                  width: selected ? 2 : 1,
                ),
                onSelected: (_) => setState(() => _operator = op),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _phoneCtrl,
            style: const TextStyle(color: Colors.white),
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Numéro Mobile Money',
              labelStyle: const TextStyle(color: Colors.white60),
              prefixIcon: const Icon(Icons.phone_android_rounded, color: _premiumGold),
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
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountCtrl,
            style: const TextStyle(color: Colors.white),
            keyboardType: const TextInputType.numberWithOptions(decimal: false),
            decoration: InputDecoration(
              labelText: 'Montant (FCFA)',
              labelStyle: const TextStyle(color: Colors.white60),
              prefixIcon: const Icon(Icons.account_balance_wallet_rounded, color: _premiumGold),
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
              hintText: 'Min. 1 000 FCFA',
              hintStyle: const TextStyle(color: Colors.white30),
            ),
          ),
          if (_err != null) ...[
            const SizedBox(height: 10),
            Text(_err!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _sending ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: _premiumGold,
                foregroundColor: _deepNavy,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 4,
                shadowColor: _premiumGold.withValues(alpha: 0.4),
              ),
              child: _sending
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _deepNavy),
                    )
                  : const Text(
                      'Confirmer le retrait',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
            ),
          ),
        ],
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
    required this.currentPhone,
    required this.currentOperator,
    required this.onSaved,
  });

  final String currentPhone;
  final String currentOperator;
  final void Function(String phone, String operator) onSaved;

  @override
  State<_MoMoInfoSheet> createState() => _MoMoInfoSheetState();
}

class _MoMoInfoSheetState extends State<_MoMoInfoSheet> {
  late final TextEditingController _phoneCtrl;
  late String _operator;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _phoneCtrl = TextEditingController(text: widget.currentPhone);
    _operator = widget.currentOperator.isNotEmpty ? widget.currentOperator : 'mtn';
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) return;
    setState(() => _saving = true);
    try {
      final token = await readStoredApiToken();
      await http.post(
        Uri.parse('${babifixApiBaseUrl()}/api/prestataire/wallet/info/'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'phone': phone, 'operator': _operator}),
      );
      widget.onSaved(phone, _operator);
    } catch (_) {
    } finally {
      setState(() => _saving = false);
    }
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
              'Informations Mobile Money',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              children: ['mtn', 'orange', 'wave', 'moov'].map((op) {
                final selected = _operator == op;
                final color = _operatorColors[op] ?? BabifixDesign.cyan;
                return ChoiceChip(
                  label: Text(_operatorNames[op] ?? op),
                  selected: selected,
                  labelStyle: TextStyle(
                    color: selected ? color : Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  side: BorderSide(
                    color: selected ? color : Colors.white.withValues(alpha: 0.2),
                    width: selected ? 2 : 1,
                  ),
                onSelected: (_) => setState(() => _operator = op),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _phoneCtrl,
            style: const TextStyle(color: Colors.white),
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Numéro Mobile Money',
              labelStyle: const TextStyle(color: Colors.white60),
              prefixIcon: const Icon(Icons.phone_android_rounded, color: _premiumGold),
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
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: _premiumGold,
                foregroundColor: _deepNavy,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 4,
                shadowColor: _premiumGold.withValues(alpha: 0.4),
              ),
              child: _saving
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _deepNavy))
                  : const Text('Enregistrer', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ],
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
