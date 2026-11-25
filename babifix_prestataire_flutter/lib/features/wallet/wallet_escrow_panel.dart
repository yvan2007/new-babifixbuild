import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../babifix_design_system.dart';
import '../../services/babifix_api.dart';
import '../../shared/services/babifix_user_store.dart';
import 'escrow_payments_screen.dart';

/// Panneau synthese Disponible vs En sequestre (theme-aware white/light/blue).
class WalletEscrowPanel extends StatefulWidget {
  final double soldeDisponibleFcfa;
  final bool hidden;

  const WalletEscrowPanel({
    super.key,
    required this.soldeDisponibleFcfa,
    this.hidden = false,
  });

  @override
  State<WalletEscrowPanel> createState() => _WalletEscrowPanelState();
}

class _WalletEscrowPanelState extends State<WalletEscrowPanel> {
  double _escrowLocked = 0;
  int _activeCount = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _fetchEscrow();
  }

  @override
  void didUpdateWidget(covariant WalletEscrowPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.soldeDisponibleFcfa != widget.soldeDisponibleFcfa) {
      _fetchEscrow();
    }
  }

  Future<void> _fetchEscrow() async {
    try {
      final r = await BabifixUserStore.authGet(
        '/api/prestataire/requests/?statut_in=DEVIS_ACCEPTE,Confirmee,INTERVENTION_EN_COURS,En attente client,Terminee',
      );
      if (r.statusCode >= 400) return;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final items = (j['items'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();

      final refs = items
          .map((it) => (it['reference'] ?? '').toString())
          .where((ref) => ref.isNotEmpty)
          .toList();
      final quotes = await Future.wait(
        refs.map((ref) async {
          try {
            return await EscrowApi.quote(ref);
          } catch (_) {
            return null;
          }
        }),
      );
      double locked = 0;
      int cnt = 0;
      for (final q in quotes) {
        if (q != null && q.fundsReleasedAt == null && q.netPrestataire > 0) {
          locked += q.netPrestataire;
          cnt++;
        }
      }
      if (!mounted) return;
      setState(() {
        _escrowLocked = locked;
        _activeCount = cnt;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  String _fmt(double amount) {
    if (widget.hidden) return '••••• FCFA';
    return '${NumberFormat('#,##0', 'fr_FR').format(amount.round())} FCFA';
  }

  @override
  Widget build(BuildContext context) {
    final surface = BabifixDesign.surfaceOf(context);
    final border = BabifixDesign.borderOf(context);
    final isDark = BabifixDesign.isDark(context);

    final total = widget.soldeDisponibleFcfa + _escrowLocked;
    final availRatio =
        total > 0 ? (widget.soldeDisponibleFcfa / total).clamp(0.0, 1.0) : 1.0;

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.shield_rounded,
                size: 15,
                color: isDark ? BabifixDesign.cyan : BabifixDesign.navy,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Repartition des fonds · Wallet & Sequestre',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: BabifixDesign.textPrimaryOf(context),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: BabifixDesign.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                    color: BabifixDesign.success.withValues(alpha: 0.28),
                  ),
                ),
                child: const Text(
                  'Cantonne',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: BabifixDesign.success,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  label: 'Disponible au retrait',
                  amount: _fmt(widget.soldeDisponibleFcfa),
                  color: BabifixDesign.success,
                  icon: Icons.account_balance_wallet_rounded,
                  subtitle: 'Transferable Mobile Money',
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricTile(
                  label: 'En sequestre',
                  amount: _loaded ? _fmt(_escrowLocked) : '...',
                  color: isDark ? BabifixDesign.cyan : BabifixDesign.ciBlue,
                  icon: Icons.lock_clock_rounded,
                  subtitle: _loaded
                      ? '$_activeCount mission${_activeCount > 1 ? 's' : ''}'
                      : 'Chargement...',
                  isDark: isDark,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PrestataireEscrowPaymentsScreen(),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (total > 0) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: Row(
                children: [
                  Expanded(
                    flex: (availRatio * 100).round().clamp(1, 100),
                    child: Container(
                      height: 5,
                      color: BabifixDesign.success,
                    ),
                  ),
                  if (availRatio < 0.99)
                    Expanded(
                      flex: ((1 - availRatio) * 100).round().clamp(1, 100),
                      child: Container(
                        height: 5,
                        color: isDark
                            ? BabifixDesign.cyan
                            : BabifixDesign.ciBlue,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String amount;
  final Color color;
  final IconData icon;
  final String subtitle;
  final bool isDark;
  final VoidCallback? onTap;

  const _MetricTile({
    required this.label,
    required this.amount,
    required this.color,
    required this.icon,
    required this.subtitle,
    required this.isDark,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textStrong = BabifixDesign.textPrimaryOf(context);
    final textMuted = BabifixDesign.textMutedOf(context);

    final box = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? color.withValues(alpha: 0.12)
            : color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.30 : 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
              if (onTap != null)
                Icon(Icons.arrow_forward_ios_rounded, size: 11, color: color),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              amount,
              style: BabifixDesign.amountStyle(
                color: textStrong,
                fontSize: 15.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10.5, color: textMuted),
          ),
        ],
      ),
    );
    if (onTap == null) return box;
    return GestureDetector(onTap: onTap, child: box);
  }
}
