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
  List<Map<String, dynamic>> _transactions = [];

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D1117) : const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                onPressed: widget.onBack,
              )
            : null,
        title: const Text(
          'Mon Wallet',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            tooltip: 'Gérer mon Mobile Money',
            onPressed: _openInfoSheet,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
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
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _BalanceCard(
                          solde: _solde,
                          phone: _walletPhone,
                          operator: _walletOperator,
                          onWithdraw: _solde >= 1000 ? _openWithdrawSheet : null,
                        ),
                        const SizedBox(height: 24),
                        if (_transactions.isEmpty)
                          const _EmptyTransactions()
                        else ...[
                          Text(
                            'Historique des transactions',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Balance Card
// ─────────────────────────────────────────────────────────────────────────────

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.solde,
    required this.phone,
    required this.operator,
    this.onWithdraw,
  });

  final double solde;
  final String phone;
  final String operator;
  final VoidCallback? onWithdraw;

  @override
  Widget build(BuildContext context) {
    final opColor = _operatorColors[operator] ?? BabifixDesign.cyan;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [BabifixDesign.ciBlue, opColor.withValues(alpha: 0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: BabifixDesign.ciBlue.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Solde disponible',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Text(
            _fcfa.format(solde),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 16),
          if (phone.isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.phone_android_rounded, color: Colors.white70, size: 16),
                const SizedBox(width: 6),
                Text(
                  '$phone · ${_operatorNames[operator] ?? operator}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onWithdraw,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: BabifixDesign.ciBlue,
                disabledBackgroundColor: Colors.white30,
                disabledForegroundColor: Colors.white60,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.account_balance_wallet_rounded),
              label: Text(
                onWithdraw == null
                    ? 'Solde minimum 1 000 FCFA'
                    : 'Demander un retrait',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
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

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(_txIcon(type), color: color, size: 20),
        ),
        title: Text(
          _txLabel(type),
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (desc.isNotEmpty)
              Text(desc, style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(date, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            if (status == 'pending')
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'En attente',
                  style: TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.w600),
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
    return Container(
      margin: EdgeInsets.only(bottom: bottom),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        color: Color(0xFF1A1F2E),
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
                color: Colors.white24,
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
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Solde disponible : ${_fcfa.format(widget.currentBalance)}',
            style: const TextStyle(color: Colors.white60, fontSize: 13),
          ),
          const SizedBox(height: 24),
          // Opérateur
          const Text('Opérateur', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: ['mtn', 'orange', 'wave', 'moov'].map((op) {
              final selected = _operator == op;
              final color = _operatorColors[op] ?? BabifixDesign.cyan;
              return ChoiceChip(
                label: Text(_operatorNames[op] ?? op),
                selected: selected,
                selectedColor: color,
                labelStyle: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
                backgroundColor: Colors.white12,
                onSelected: (_) => setState(() => _operator = op),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          // Numéro
          TextField(
            controller: _phoneCtrl,
            style: const TextStyle(color: Colors.white),
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Numéro Mobile Money',
              labelStyle: const TextStyle(color: Colors.white60),
              prefixIcon: const Icon(Icons.phone_android_rounded, color: Colors.white54),
              filled: true,
              fillColor: Colors.white12,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Montant
          TextField(
            controller: _amountCtrl,
            style: const TextStyle(color: Colors.white),
            keyboardType: const TextInputType.numberWithOptions(decimal: false),
            decoration: InputDecoration(
              labelText: 'Montant (FCFA)',
              labelStyle: const TextStyle(color: Colors.white60),
              prefixIcon: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white54),
              filled: true,
              fillColor: Colors.white12,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
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
                backgroundColor: BabifixDesign.cyan,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _sending
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text(
                      'Confirmer le retrait',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
            ),
          ),
        ],
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
    return Container(
      margin: EdgeInsets.only(bottom: bottom),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        color: Color(0xFF1A1F2E),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
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
                selectedColor: color,
                labelStyle: TextStyle(color: selected ? Colors.white : Colors.white70, fontWeight: FontWeight.w600),
                backgroundColor: Colors.white12,
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
              prefixIcon: const Icon(Icons.phone_android_rounded, color: Colors.white54),
              filled: true,
              fillColor: Colors.white12,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: BabifixDesign.cyan,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _saving
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Enregistrer', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
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
            Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Aucune transaction',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Text(
              'Vos paiements reçus apparaîtront ici.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
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
      color: Colors.white.withValues(alpha: 0.65),
      borderRadius: BorderRadius.circular(r),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final grad = LinearGradient(
          begin: Alignment(_anim.value - 1, 0),
          end: Alignment(_anim.value + 1, 0),
          colors: const [Color(0xFFE2E8F0), Color(0xFFF8FAFC), Color(0xFFE2E8F0)],
        );
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Balance card shimmer
            Container(
              height: 160,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: grad,
              ),
            ),
            const SizedBox(height: 24),
            _box(140, 16, r: 6),
            const SizedBox(height: 12),
            ...List.generate(5, (_) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: grad,
              ),
              child: Row(
                children: [
                  _box(40, 40, r: 20),
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
          const Icon(Icons.cloud_off_rounded, size: 56, color: Colors.grey),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Réessayer')),
        ],
      ),
    );
  }
}
