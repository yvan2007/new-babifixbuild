/// Écran "Mes paiements en attente" : liste des montants bloqués en
/// escrow + état (acompte reçu / intervention en cours / en attente de
/// confirmation client) avec montant net à recevoir par réservation.
///
/// Utile quand un prestataire jongle entre plusieurs chantiers en
/// simultané : il voit d'un coup d'œil tout ce qui est verrouillé
/// chez BABIFIX et qui sera libéré dès que les clients confirment.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../babifix_design_system.dart';
import '../../models/babifix_models.dart';
import '../../services/babifix_api.dart';
import '../../shared/services/babifix_user_store.dart';
import '../../shared/widgets/animated_list_item.dart';
import '../../shared/widgets/animated_money.dart';
import '../../shared/widgets/babifix_phase_widgets.dart';
import '../../shared/widgets/babifix_ring_loader.dart';

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
      // 1. Liste des demandes presta (toutes — on filtre côté client)
      final r = await BabifixUserStore.authGet('/api/prestataire/requests');
      if (r.statusCode >= 400) {
        throw BabifixApiException(
            r.statusCode, 'http_error', 'HTTP ${r.statusCode}');
      }
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final items = (j['items'] as List? ??
              j['requests'] as List? ??
              const [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();

      // 2. Pour chacune dans un état "argent en escrow", on tire la quote
      final entries = <_EscrowEntry>[];
      for (final it in items) {
        final statut = (it['status'] ?? it['statut'] ?? '').toString();
        // On garde les états où il peut y avoir de l'argent en attente
        if (![
          'DEVIS_ACCEPTE',
          'INTERVENTION_EN_COURS',
          'En cours',
          'Terminee',
        ].contains(statut)) {
          continue;
        }
        final ref = (it['reference'] ?? '').toString();
        if (ref.isEmpty) continue;
        try {
          final quote = await EscrowApi.quote(ref);
          if (quote.fundsReleasedAt != null) continue;
          entries.add(_EscrowEntry(
            reference: ref,
            clientName: (it['client'] ?? it['client_name'] ?? '').toString(),
            service: (it['service'] ?? it['title'] ?? '').toString(),
            statut: statut,
            quote: quote,
          ));
        } catch (_) {
          // Pas grave si une résa n'a pas de quote (pas de devis)
        }
      }
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
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Paiements en attente'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: BabifixRingLoader.dark(size: 80))
          : _error != null
              ? _errorView()
              : _entries.isEmpty
                  ? _emptyView()
                  : _content(),
    );
  }

  Widget _errorView() => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  color: BabifixDesign.error, size: 56),
              const SizedBox(height: 12),
              Text(_error ?? '', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _load,
                child: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );

  Widget _emptyView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_open,
                  size: 60, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                'Aucun paiement bloqué',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade700),
              ),
              const SizedBox(height: 6),
              Text(
                'Toutes vos prestations sont soldées.\n'
                'Les fonds en escrow apparaîtront ici quand un client réservera.',
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      );

  Widget _content() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _totalBanner(),
          const SizedBox(height: 14),
          Text(
            '${_entries.length} chantier${_entries.length > 1 ? 's' : ''} en cours',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700),
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
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            BabifixDesign.ciBlue.withValues(alpha: 0.10),
            BabifixDesign.ciGreen.withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BabifixDesign.ciBlue.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance, color: BabifixDesign.iconOnLight),
              const SizedBox(width: 8),
              Text(
                'Total bloqué en escrow',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: BabifixDesign.ciBlue,
                    letterSpacing: 0.3),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AnimatedMoney(
            value: _totalLocked,
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              color: Colors.grey.shade900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Libéré dans votre wallet dès que chaque client confirme les travaux.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Modèle local + carte de chaque escrow
// ---------------------------------------------------------------------------
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

  /// Combien je toucherai au final (libération escrow)
  double get netExpected => quote.netPrestataire;

  /// Phase actuelle : 1=acompte, 2=en cours, 3=terminé attente client
  ({String label, Color color, IconData icon, double progress}) get phase {
    if (statut == 'Terminee') {
      return (
        label: 'En attente de confirmation client',
        color: const Color(0xFF7C3AED),
        icon: Icons.hourglass_top,
        progress: 0.85,
      );
    }
    if (statut == 'INTERVENTION_EN_COURS' || statut == 'En cours') {
      return (
        label: 'Intervention en cours',
        color: BabifixDesign.ciBlue,
        icon: Icons.engineering,
        progress: 0.55,
      );
    }
    if (quote.acompteValide) {
      return (
        label: 'Acompte reçu : prêt à démarrer',
        color: BabifixDesign.ciGreen,
        icon: Icons.check_circle_outline,
        progress: 0.30,
      );
    }
    return (
      label: 'En attente d\'acompte client',
      color: Colors.orange.shade700,
      icon: Icons.hourglass_empty,
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: ph.color.withValues(alpha: 0.15),
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
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (entry.service.isNotEmpty)
                      Text(
                        entry.service,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${fmt.format(entry.netExpected.round())} F',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: BabifixDesign.ciGreen,
                    ),
                  ),
                  Text(
                    'à recevoir',
                    style: TextStyle(
                        fontSize: 10, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Progress bar de phase
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ph.progress,
              minHeight: 6,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation(ph.color),
            ),
          ),
          const SizedBox(height: 6),
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
                    fontSize: 10, color: Colors.grey.shade500),
              ),
            ],
          ),
          if (entry.quote.isCash) ...[
            const SizedBox(height: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(Icons.payments_outlined,
                      size: 12, color: Colors.orange.shade700),
                  const SizedBox(width: 4),
                  Text(
                    'Mode cash : ${fmt.format(entry.quote.cashRemainderDueToProvider.round())} F à percevoir en main propre',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: Colors.orange.shade900,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
          // Status badge escrow strategy
          const SizedBox(height: 6),
          EscrowStatusBadge.fromQuote(entry.quote),
        ],
      ),
    );
  }
}
