import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../babifix_design_system.dart';
import '../../models/babifix_models.dart';
import '../../services/babifix_api.dart';
import '../../shared/services/babifix_user_store.dart';
import '../../shared/widgets/animated_list_item.dart';
import '../../shared/widgets/animated_money.dart';
import '../../shared/widgets/babifix_button.dart';
import '../../shared/widgets/babifix_phase_widgets.dart';
import '../../shared/widgets/babifix_skeleton.dart';
import '../requests/devis_kanban_editor_screen.dart';

/// Ecran Paiements en attente (sequestre BABIFIX).
class PrestataireEscrowPaymentsScreen extends StatefulWidget {
  const PrestataireEscrowPaymentsScreen({super.key});

  @override
  State<PrestataireEscrowPaymentsScreen> createState() =>
      _PrestataireEscrowPaymentsScreenState();
}

class _PrestataireEscrowPaymentsScreenState
    extends State<PrestataireEscrowPaymentsScreen> {
  bool _loading = true;
  String? _error;
  List<_EscrowEntry> _entries = [];

  double get _totalLocked =>
      _entries.fold<double>(0, (s, e) => s + e.netExpected);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await BabifixUserStore.authGet('/api/prestataire/requests');
      if (r.statusCode >= 400) {
        throw BabifixApiException(
          r.statusCode,
          'http_error',
          'HTTP ${r.statusCode}',
        );
      }
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final items = (j['items'] as List? ?? j['requests'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();

      final candidates = <Map<String, dynamic>>[];
      for (final it in items) {
        final statut = (it['status'] ?? it['statut'] ?? '').toString();
        if (![
          'DEVIS_ACCEPTE',
          'Confirmee',
          'INTERVENTION_EN_COURS',
          'En cours',
          'En attente client',
          'Terminee',
        ].contains(statut)) {
          continue;
        }
        final ref = (it['reference'] ?? '').toString();
        if (ref.isNotEmpty) candidates.add(it);
      }

      final fetched = await Future.wait(
        candidates.map((it) async {
          final ref = (it['reference'] ?? '').toString();
          final statut = (it['status'] ?? it['statut'] ?? '').toString();
          try {
            final quote = await EscrowApi.quote(ref);
            if (quote.fundsReleasedAt != null) return null;
            return _EscrowEntry(
              reference: ref,
              clientName: (it['client'] ?? it['client_name'] ?? '').toString(),
              service: (it['service'] ?? it['title'] ?? '').toString(),
              statut: statut,
              quote: quote,
            );
          } catch (_) {
            return null;
          }
        }),
      );
      final entries = fetched.whereType<_EscrowEntry>().toList();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final text = BabifixDesign.textPrimaryOf(context);
    final muted = BabifixDesign.textMutedOf(context);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('Paiements en sequestre'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: Icon(Icons.refresh_rounded, color: muted),
          ),
        ],
      ),
      body: _loading
          ? BabifixSkeletonScope(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const BabifixSkeletonBox(height: 112, borderRadius: 18),
                  const SizedBox(height: 16),
                  ...List.generate(4, (_) => const BabifixSkeletonCard(lines: 2)),
                ],
              ),
            )
          : _error != null
              ? _errorView()
              : _entries.isEmpty
                  ? _emptyView()
                  : _content(),
    );
  }

  Widget _errorView() {
    final muted = BabifixDesign.textMutedOf(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: BabifixDesign.error, size: 52),
            const SizedBox(height: 12),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 16),
            BabifixButton(
              label: 'Reessayer',
              icon: Icons.refresh_rounded,
              onPressed: _load,
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyView() {
    final text = BabifixDesign.textPrimaryOf(context);
    final muted = BabifixDesign.textMutedOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_open_rounded, size: 54, color: muted),
            const SizedBox(height: 14),
            Text(
              'Aucun paiement bloque',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Toutes vos prestations sont soldees. Les fonds en sequestre apparaitront ici des reservation.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: muted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    final muted = BabifixDesign.textMutedOf(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _totalBanner(),
          const SizedBox(height: 16),
          Text(
            '${_entries.length} chantier${_entries.length > 1 ? 's' : ''} en cours',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: muted,
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < _entries.length; i++)
            AnimatedListItem(
              index: i,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _EscrowCard(entry: _entries[i]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _totalBanner() {
    final isDark = BabifixDesign.isDark(context);
    final surface = BabifixDesign.surfaceOf(context);
    final border = BabifixDesign.borderOf(context);
    final text = BabifixDesign.textPrimaryOf(context);
    final muted = BabifixDesign.textMutedOf(context);
    final accent = isDark ? BabifixDesign.cyan : BabifixDesign.ciBlue;

    return Container(
      padding: const EdgeInsets.all(18),
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
              Icon(Icons.account_balance_rounded, color: accent, size: 18),
              const SizedBox(width: 8),
              Text(
                'Total bloque en sequestre',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AnimatedMoney(
            value: _totalLocked,
            style: BabifixDesign.amountStyle(
              color: text,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Libere dans votre wallet des confirmation client de fin de travaux.',
            style: TextStyle(fontSize: 12, color: muted),
          ),
        ],
      ),
    );
  }
}

class _EscrowEntry {
  final String reference;
  final String clientName;
  final String service;
  final String statut;
  final EscrowQuote quote;

  _EscrowEntry({
    required this.reference,
    required this.clientName,
    required this.service,
    required this.statut,
    required this.quote,
  });

  double get netExpected => quote.netPrestataire;

  ({String label, Color color, IconData icon, double progress}) get phase {
    if (statut == 'Terminee') {
      return (
        label: 'En attente de confirmation client',
        color: const Color(0xFF7C3AED),
        icon: Icons.hourglass_top_rounded,
        progress: 0.85,
      );
    }
    if (statut == 'INTERVENTION_EN_COURS' || statut == 'En cours') {
      return (
        label: 'Intervention en cours',
        color: BabifixDesign.ciBlue,
        icon: Icons.engineering_rounded,
        progress: 0.55,
      );
    }
    if (quote.acompteValide) {
      return (
        label: 'Acompte recu : pret a demarrer',
        color: BabifixDesign.ciGreen,
        icon: Icons.check_circle_outline_rounded,
        progress: 0.30,
      );
    }
    return (
      label: 'En attente d acompte client',
      color: BabifixDesign.ciOrange,
      icon: Icons.hourglass_empty_rounded,
      progress: 0.10,
    );
  }
}

class _EscrowCard extends StatelessWidget {
  final _EscrowEntry entry;
  const _EscrowCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final ph = entry.phase;
    final fmt = NumberFormat.decimalPattern('fr_FR');
    final surface = BabifixDesign.surfaceOf(context);
    final border = BabifixDesign.borderOf(context);
    final text = BabifixDesign.textPrimaryOf(context);
    final muted = BabifixDesign.textMutedOf(context);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              DevisKanbanEditorScreen(reservationReference: entry.reference),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: ph.color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(ph.icon, color: ph.color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.clientName.isEmpty ? 'Client' : entry.clientName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: text,
                      ),
                    ),
                    if (entry.service.isNotEmpty)
                      Text(
                        entry.service,
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${fmt.format(entry.netExpected.round())} F',
                    style: BabifixDesign.amountStyle(
                      color: BabifixDesign.success,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    'a recevoir',
                    style: TextStyle(fontSize: 10.5, color: muted),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ph.progress,
              minHeight: 6,
              backgroundColor: muted.withValues(alpha: 0.16),
              valueColor: AlwaysStoppedAnimation(ph.color),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  ph.label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: ph.color,
                  ),
                ),
              ),
              Text(
                entry.reference,
                style: TextStyle(
                  fontSize: 10.5,
                  color: muted,
                  fontFeatures: BabifixDesign.tabularFigures,
                ),
              ),
            ],
          ),
          if (entry.quote.isCash) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: BabifixDesign.ciOrange.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.payments_outlined,
                    size: 13,
                    color: BabifixDesign.ciOrange,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Cash : ${fmt.format(entry.quote.cashRemainderDueToProvider.round())} F a percevoir sur place',
                      style: const TextStyle(
                        fontSize: 11,
                        color: BabifixDesign.ciOrange,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          EscrowStatusBadge.fromQuote(entry.quote),
        ],
      ),
      ),
    );
  }
}
