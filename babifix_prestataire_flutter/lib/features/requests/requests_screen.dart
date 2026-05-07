import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../shared/auth_utils.dart';
import '../../shared/widgets/babifix_page_route.dart';
import '../../shared/widgets/payment_method_logo.dart';
import 'create_devis_screen.dart';
import 'rate_client_screen.dart';
import 'request_detail_screen.dart';
import 'waiting_payment_screen.dart';

class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  bool loading = false;
  String? authToken;
  late List<_RequestItem> items;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String? _selectedBucket;

  @override
  void initState() {
    super.initState();
    items = <_RequestItem>[];
    _initSession();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<_RequestItem> get _filteredItems {
    if (_searchQuery.isEmpty && _selectedBucket == null) return items;
    return items.where((item) {
      final matchesSearch = _searchQuery.isEmpty ||
          item.client.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          item.service.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          item.reference.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          item.description.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesBucket =
          _selectedBucket == null ||
          (_selectedBucket == 'devis'
              ? (item.status == 'devis_pending' || item.status == 'devis_sent')
              : item.status == _selectedBucket);
      return matchesSearch && matchesBucket;
    }).toList();
  }

  /// Align\u00e9 UML / API : nouveau flow devis
  /// pending (DEMANDE_ENVOYEE), devis_pending (DEVIS_EN_COURS), devis_sent (DEVIS_ENVOYE),
  /// active (DEVIS_ACCEPTE, INTERVENTION_EN_COURS, Confirmee, En cours), completed, refused.
  static String _bucketFromApi(String raw) {
    final t = raw.trim();
    if (t == 'Annulee' || t.toLowerCase().contains('annul')) return 'refused';
    if (t == 'En attente' || t.toLowerCase().contains('attente'))
      return 'pending';
    if (t == 'Terminee' || t.toLowerCase().contains('termin'))
      return 'completed';
    if (t == 'DEMANDE_ENVOYEE') return 'pending';
    if (t == 'DEVIS_EN_COURS') return 'devis_pending';
    if (t == 'DEVIS_ENVOYE') return 'devis_sent';
    return 'active';
  }

  static String _labelStatut(String apiStatus) {
    switch (apiStatus) {
      case 'Confirmee':
        return 'Confirm\u00e9e';
      case 'Terminee':
        return 'Termin\u00e9e';
      case 'Annulee':
        return 'Annul\u00e9e';
      case 'En cours':
        return 'En cours';
      case 'DEMANDE_ENVOYEE':
        return 'Demande envoy\u00e9e';
      case 'DEVIS_EN_COURS':
        return 'Devis en cours';
      case 'DEVIS_ENVOYE':
        return 'Devis envoy\u00e9';
      case 'DEVIS_ACCEPTE':
        return 'Devis accept\u00e9';
      case 'INTERVENTION_EN_COURS':
        return 'Intervention en cours';
      default:
        return apiStatus;
    }
  }

  bool _canConfirmCash(_RequestItem it) {
    return it.paymentType == 'ESPECES' &&
        it.cashFlowStatus == 'pending_prestataire' &&
        (it.apiStatus == 'Terminee');
  }

  @override
  Widget build(BuildContext context) {
    final pending = items.where((e) => e.status == 'pending').toList();
    final devisPending = items
        .where((e) => e.status == 'devis_pending')
        .toList();
    final devisSent = items.where((e) => e.status == 'devis_sent').toList();
    final active = items.where((e) => e.status == 'active').toList();
    final completed = items.where((e) => e.status == 'completed').toList();
    final refused = items.where((e) => e.status == 'refused').toList();

    final total = items.length;
    final steps = [
      _KanbanStep(
        label: 'Nouveau',
        count: pending.length,
        icon: Icons.notifications_active_rounded,
        color: pending.isNotEmpty ? const Color(0xFF38BDF8) : const Color(0xFF475569),
        bucket: 'pending',
      ),
      _KanbanStep(
        label: 'Devis',
        count: devisPending.length + devisSent.length,
        icon: Icons.request_quote_rounded,
        color: (devisPending.isNotEmpty || devisSent.isNotEmpty) ? const Color(0xFF60A5FA) : const Color(0xFF475569),
        bucket: 'devis',
      ),
      _KanbanStep(
        label: 'En cours',
        count: active.length,
        icon: Icons.build_rounded,
        color: active.isNotEmpty ? const Color(0xFFA78BFA) : const Color(0xFF475569),
        bucket: 'active',
      ),
      _KanbanStep(
        label: 'Terminé',
        count: completed.length,
        icon: Icons.task_alt_rounded,
        color: completed.isNotEmpty ? const Color(0xFF22C55E) : const Color(0xFF475569),
        bucket: 'completed',
      ),
    ];

    return Scaffold(
      backgroundColor: BabifixDesign.navy,
      body: loading
          ? _buildShimmer()
          : RefreshIndicator(
              onRefresh: _loadRequests,
              color: const Color(0xFF38BDF8),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
          SliverAppBar(
            backgroundColor: BabifixDesign.navy,
            elevation: 0,
            leading: IconButton(
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back, color: Colors.white),
            ),
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Demandes',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$total mission${total > 1 ? "s" : ""}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF38BDF8),
                    ),
                  ),
                ),
              ],
            ),
            centerTitle: true,
          ),
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (int i = 0; i < steps.length; i++) ...[
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedBucket = _selectedBucket == steps[i].bucket
                                ? null
                                : steps[i].bucket;
                          });
                        },
                        child: Column(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: steps[i].color.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: steps[i].color.withValues(alpha: steps[i].count > 0 ? 0.5 : 0.15),
                                  width: steps[i].count > 0 ? 2 : 1,
                                ),
                              ),
                              child: Icon(
                                steps[i].icon,
                                size: 18,
                                color: steps[i].color,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${steps[i].count}',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: steps[i].color,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              steps[i].label,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: steps[i].count > 0
                                    ? Colors.white.withValues(alpha: 0.6)
                                    : const Color(0xFF64748B),
                              ),
                            ),
                            if (_selectedBucket == steps[i].bucket)
                              Container(
                                height: 3,
                                margin: const EdgeInsets.only(top: 4),
                                decoration: BoxDecoration(
                                  color: steps[i].color,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (i < steps.length - 1)
                      Expanded(
                        flex: 1,
                        child: Container(
                          height: 2,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                steps[i].color.withValues(alpha: 0.3),
                                steps[i + 1].color.withValues(alpha: 0.3),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          // Search bar
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _searchQuery = v),
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Rechercher client, service, reference…',
                  hintStyle: TextStyle(color: const Color(0xFF64748B).withValues(alpha: 0.8)),
                  prefixIcon: const Icon(Icons.search_rounded, color: BabifixDesign.cyan, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, color: Color(0xFF64748B), size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFF151D2E),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: BabifixDesign.cyan.withValues(alpha: 0.25)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: BabifixDesign.cyan, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      if (_filteredItems.isEmpty && (items.isNotEmpty))
                        Padding(
                          padding: const EdgeInsets.only(top: 40),
                          child: Center(
                            child: Text(
                              'Aucun résultat pour votre recherche.',
                              style: TextStyle(
                                fontSize: 14,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                          ),
                        ),
                      if (_selectedBucket != null)
                        // Flat list when a bucket is selected
                        ..._filteredItems.map((item) => _buildCardTappable(item)),
                      if (_selectedBucket == null && _searchQuery.isEmpty)
                        // Full grouped view when no filter
                        ...[
                          if (pending.isNotEmpty) ...[
                            _buildKanbanSectionHeader(
                              title: 'Nouvelles demandes',
                              subtitle: 'Glissez → accepter  •  ← refuser',
                              count: pending.length,
                              color: const Color(0xFF38BDF8),
                              icon: Icons.notifications_active_rounded,
                              accentGradient: const LinearGradient(
                                colors: [Color(0xFF38BDF8), Color(0xFF0EA5E9)],
                              ),
                            ),
                            ...pending.map((item) => _buildCardTappable(item)),
                          ],
                          if (devisPending.isNotEmpty || devisSent.isNotEmpty) ...[
                            _buildKanbanSectionHeader(
                              title: 'Devis',
                              subtitle: devisPending.isNotEmpty && devisSent.isNotEmpty
                                  ? '${devisPending.length} à faire  •  ${devisSent.length} envoyés'
                                  : devisPending.isNotEmpty
                                      ? 'Devis à rédiger'
                                      : 'Devis envoyés en attente',
                              count: devisPending.length + devisSent.length,
                              color: const Color(0xFF60A5FA),
                              icon: Icons.request_quote_rounded,
                              accentGradient: const LinearGradient(
                                colors: [Color(0xFF60A5FA), Color(0xFF3B82F6)],
                              ),
                            ),
                            ...devisPending.map((item) => _buildCardTappable(item)),
                            ...devisSent.map((item) => _buildCardTappable(item)),
                          ],
                          if (active.isNotEmpty) ...[
                            _buildKanbanSectionHeader(
                              title: 'En cours',
                              subtitle: 'Interventions actives',
                              count: active.length,
                              color: const Color(0xFFA78BFA),
                              icon: Icons.build_rounded,
                              accentGradient: const LinearGradient(
                                colors: [Color(0xFFA78BFA), Color(0xFF8B5CF6)],
                              ),
                            ),
                            ...active.map((item) => _buildCardTappable(item)),
                          ],
                          if (completed.isNotEmpty) ...[
                            _buildKanbanSectionHeader(
                              title: 'Terminées',
                              subtitle: 'Missions achevées',
                              count: completed.length,
                              color: const Color(0xFF22C55E),
                              icon: Icons.task_alt_rounded,
                              accentGradient: const LinearGradient(
                                colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
                              ),
                            ),
                            ...completed.map((item) => _buildCardTappable(item)),
                          ],
                          if (refused.isNotEmpty) ...[
                            _buildKanbanSectionHeader(
                              title: 'Refusées / Annulées',
                              subtitle: 'Demandes non retenues',
                              count: refused.length,
                              color: const Color(0xFFEF4444),
                              icon: Icons.cancel_rounded,
                              accentGradient: const LinearGradient(
                                colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                              ),
                            ),
                            ...refused.map((item) => _buildCardTappable(item)),
                          ],
                          if (_filteredItems.isEmpty && items.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 40),
                              child: Center(
                                child: Text(
                                  'Aucun résultat pour votre recherche.',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      // Empty state quand tout est vide
                      if (items.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 60),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  color: BabifixDesign.cyan.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.assignment_outlined,
                                  size: 40,
                                  color: BabifixDesign.cyan,
                                ),
                              ),
                              const SizedBox(height: 20),
                              const Text(
                                'Aucune mission',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Vos demandes de clients apparaîtront ici.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF64748B),
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ]),
                  ),
                ),
              ],
            ),
          ),
    );
  }

  Widget _buildKanbanSectionHeader({
    required String title,
    required String subtitle,
    required int count,
    required Color color,
    required IconData icon,
    required Gradient accentGradient,
    bool muted = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: muted ? 0.05 : 0.08),
            color.withValues(alpha: muted ? 0.02 : 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withValues(alpha: muted ? 0.1 : 0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: accentGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: muted ? Colors.white.withValues(alpha: 0.5) : Colors.white,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: muted
                        ? Colors.white.withValues(alpha: 0.3)
                        : Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              gradient: accentGradient,
              borderRadius: BorderRadius.circular(10),
              boxShadow: muted
                  ? null
                  : [
                      BoxShadow(
                        color: color.withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmer() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (_, __) => const _ShimmerCard(),
    );
  }

  Widget _buildCardTappable(_RequestItem it) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => RequestDetailScreen(
            reference: it.reference,
            client: it.client,
            service: it.service,
            date: it.date,
            hour: it.hour,
            amount: it.amount,
            address: it.address,
            description: it.description,
            apiStatus: it.apiStatus,
            paymentType: it.paymentType,
            mobileMoneyOperator: it.mobileMoneyOperator,
            rating: it.rating,
            clientMessage: it.clientMessage,
            clientPhotos: it.clientPhotos,
            disponibilitesClient: it.disponibilitesClient,
            isUrgent: it.isUrgent,
            prixPropose: it.prixPropose,
          ),
        ),
      ),
      child: _buildCard(it),
    );
  }

  Widget _buildCard(_RequestItem it) {
    final card = _buildCardInner(it);
    if (it.status != 'pending') return card;
    return Dismissible(
      key: ValueKey(it.reference),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        final decision = direction == DismissDirection.startToEnd
            ? 'accept'
            : 'refuse';
        await _decide(it, decision);
        return false; // list updates via setState in _decide
      },
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: const Color(0xFF22C55E),
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.centerLeft,
        child: const Row(
          children: [
            Icon(
              Icons.check_circle_outline_rounded,
              color: Colors.white,
              size: 28,
            ),
            SizedBox(width: 8),
            Text(
              'Accepter',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
      secondaryBackground: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444),
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.centerRight,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              'Refuser',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            SizedBox(width: 8),
            Icon(Icons.cancel_outlined, color: Colors.white, size: 28),
          ],
        ),
      ),
      child: card,
    );
  }

  Widget _buildCardInner(_RequestItem it) {
    final tagText = _labelStatut(it.apiStatus);
    final hasClientMsg = it.clientMessage.isNotEmpty;
    final hasPhotos = it.clientPhotos.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF152A45), Color(0xFF1A3355)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── En-tête client + tag ──────────────────────────────────────
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: BabifixDesign.cyan.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.person_outline_rounded,
                  color: BabifixDesign.cyan,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  it.client,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Colors.white,
                  ),
                ),
              ),
              _TagPremium(text: tagText),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            it.service,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.schedule_rounded,
                size: 14,
                color: Color(0xFF64748B),
              ),
              const SizedBox(width: 4),
              Text(
                '${it.date}  ${it.hour}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.location_on_outlined,
                size: 14,
                color: Color(0xFF64748B),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  it.address,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ),
            ],
          ),

          // ── Exigences du client ───────────────────────────────────────
          if (it.isUrgent || it.disponibilitesClient.isNotEmpty || it.prixPropose != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: it.isUrgent
                    ? const Color(0xFFEF4444).withValues(alpha: 0.1)
                    : const Color(0xFF8B5CF6).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: it.isUrgent
                      ? const Color(0xFFEF4444).withValues(alpha: 0.2)
                      : const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        it.isUrgent ? Icons.priority_high_rounded : Icons.assignment_turned_in_outlined,
                        size: 14,
                        color: it.isUrgent ? const Color(0xFFEF4444) : const Color(0xFF8B5CF6),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Exigences du client',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: it.isUrgent ? const Color(0xFFEF4444) : const Color(0xFF8B5CF6),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (it.isUrgent) ...[
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.flash_on_rounded, size: 10, color: Color(0xFFEF4444)),
                              SizedBox(width: 3),
                              Text(
                                'URGENT',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFEF4444),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Intervention rapide demandée',
                          style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],
                  if (it.disponibilitesClient.isNotEmpty) ...[
                    Row(
                      children: [
                        const Icon(Icons.schedule_rounded, size: 12, color: Color(0xFF64748B)),
                        const SizedBox(width: 6),
                        const Text(
                          'Dispo :',
                          style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            it.disponibilitesClient,
                            style: const TextStyle(fontSize: 11, color: Color(0xFFCBD5E1)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                  if (it.prixPropose != null && it.prixPropose! > 0) ...[
                    Row(
                      children: [
                        const Icon(Icons.monetization_on_outlined, size: 12, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 6),
                        const Text(
                          'Budget :',
                          style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${it.prixPropose!.toStringAsFixed(0)} FCFA',
                          style: const TextStyle(fontSize: 12, color: Color(0xFFF59E0B), fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],

          // ── Message du client ─────────────────────────────────────────
          if (hasClientMsg) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF4CC9F0).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF4CC9F0).withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 14,
                        color: Color(0xFF60A5FA),
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Message du client',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF60A5FA),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    it.clientMessage,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFFCBD5E1),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Photos du client ──────────────────────────────────────────
          if (hasPhotos) ...[
            const SizedBox(height: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.photo_library_outlined,
                      size: 14,
                      color: Color(0xFF64748B),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Photos (${it.clientPhotos.length})',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 80,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: it.clientPhotos.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (ctx, i) => ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: _SafeImage(src: it.clientPhotos[i], size: 80),
                    ),
                  ),
                ),
              ],
            ),
          ],

          // ── Description (si pas de message client dédié) ──────────────
          if (!hasClientMsg && it.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              it.description,
              style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
            ),
          ],

          // ── Paiement ──────────────────────────────────────────────────
          if (it.paymentType.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (it.paymentType == 'MOBILE_MONEY' &&
                      it.mobileMoneyOperator.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: BabifixPaymentMethodLogo(
                        methodId: it.mobileMoneyOperator,
                        height: 22,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      'Paiement : ${_paymentLabel(it.paymentType, it.mobileMoneyOperator)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: BabifixDesign.ciOrange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.star_rounded, size: 16, color: Color(0xFFF59E0B)),
                const SizedBox(width: 6),
                Text(
                  it.rating.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFF59E0B),
                  ),
                ),
                const Spacer(),
                Text(
                  it.amount,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: BabifixDesign.cyan,
                  ),
                ),
              ],
            ),
          ),

          // ── Actions ───────────────────────────────────────────────────
          // Nouvelles demandes: Accepter / Refuser (pas de devis)
          if (it.status == 'pending') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _decide(it, 'refuse'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: BabifixDesign.error,
                      side: BorderSide(color: BabifixDesign.error.withValues(alpha: 0.3)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Refuser', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _decide(it, 'accept'),
                    style: FilledButton.styleFrom(
                      backgroundColor: BabifixDesign.success,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Accepter', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
          // Devis à préparer: bouton créer devis
          if (it.status == 'devis_pending') ...[
            const SizedBox(height: 12),
            if (it.bookingId != null) ...[
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).push<void>(
                    babifixRoute(
                      (_) => CreateDevisScreen(
                        reservationReference: it.reference,
                        reservationDetails: {
                          'client': it.client,
                          'title': it.service,
                          'description_probleme': it.clientMessage,
                          'address': it.address ?? '',
                          'payment_type': it.paymentType ?? '',
                          'mobile_money_operator': it.mobileMoneyOperator ?? '',
                          'disponibilites': it.disponibilitesClient ?? '',
                          'is_urgent': it.isUrgent,
                          'prix_propose': it.prixPropose,
                        },
                        onBack: () => Navigator.pop(context),
                        onDevisCreated: () {
                          Navigator.pop(context);
                          _loadRequests();
                        },
                      ),
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF4CC9F0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.request_quote_rounded, size: 20),
                  label: const Text(
                    'Créer un devis',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
              ),
            ],
          ],
          // Devis envoyés: juste info, pas d'actions
          if (it.status == 'devis_sent') ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: BabifixDesign.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.hourglass_empty_rounded, size: 16, color: Color(0xFFF59E0B)),
                  SizedBox(width: 8),
                  Text(
                    'En attente de réponse du client',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFFF59E0B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
          // Confirmées / en cours: Démarrer / Terminer
          if (it.status == 'active') ...[
            const SizedBox(height: 10),
            if (it.apiStatus == 'DEVIS_ACCEPTE')
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: () => _demarrerIntervention(it),
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: const Text(
                    'Démarrer la prestation',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: BabifixDesign.ciOrange,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            if (it.apiStatus == 'INTERVENTION_EN_COURS')
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: () async {
                    await _terminerIntervention(it);
                    if (mounted) _navigateToWaitingPayment(it);
                  },
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
                  label: const Text(
                    'Déclarer travaux terminés',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: BabifixDesign.success,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
          ],
          if (it.status == 'completed' && _canConfirmCash(it)) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: () => _confirmCashPayment(it),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: BabifixDesign.success.withValues(alpha: 0.3)),
                  foregroundColor: BabifixDesign.success,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text(
                  'Confirmer réception des espèces',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
          if (it.status == 'completed') ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push<void>(
                  babifixRoute(
                    (_) => RateClientScreen(
                      reservationRef: it.reference,
                      clientName: it.client,
                    ),
                  ),
                ),
                icon: const Icon(Icons.star_border_rounded, size: 18),
                label: const Text(
                  'Évaluer le client',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: BabifixDesign.warning.withValues(alpha: 0.3)),
                  foregroundColor: BabifixDesign.warning,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _paymentLabel(String code, [String mobileOp = '']) {
    switch (code) {
      case 'ESPECES':
        return 'Esp\u00e8ces';
      case 'MOBILE_MONEY':
        final op = _mobileMoneyOpLabel(mobileOp);
        return op.isEmpty ? 'Mobile Money' : 'Mobile Money ($op)';
      case 'CARTE':
        return 'Carte';
      default:
        return code;
    }
  }

  String _mobileMoneyOpLabel(String op) {
    switch (op) {
      case 'ORANGE_MONEY':
        return 'Orange Money';
      case 'MTN_MOMO':
        return 'MTN MoMo';
      case 'WAVE':
        return 'Wave';
      case 'MOOV':
        return 'Moov';
      default:
        return '';
    }
  }

  Future<void> _initSession() async {
    authToken = await readStoredApiToken();
    babifixRegisterFcm(authToken);
    await _loadRequests();
  }

  Future<void> _loadRequests() async {
    if (authToken == null) return;
    setState(() => loading = true);
    try {
      final url = '${babifixApiBaseUrl()}/api/prestataire/requests';
      debugPrint('📥 PRESTATAIRE LOAD REQUESTS — URL: $url');
      final res = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $authToken'},
      );
      debugPrint('📥 RESPONSE — status: ${res.statusCode}, body: ${res.body}');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final itemsList = data['items'] as List<dynamic>? ?? [];
        debugPrint('📥 ITEMS COUNT: ${itemsList.length}');
        final remote = itemsList.map((e) {
          final raw = '${e['status']}';
          final bucket = _RequestsScreenState._bucketFromApi(raw);
          final pay = '${e['payment_type'] ?? ''}';
          final mmOp = '${e['mobile_money_operator'] ?? ''}';
          final cash = '${e['cash_flow_status'] ?? ''}';
          final photos = (e['client_photos'] as List<dynamic>? ?? [])
              .map((p) => '$p'.trim())
              .where((p) => p.isNotEmpty)
              .toList();
          return _RequestItem(
            reference: '${e['reference'] ?? e['id'] ?? ''}',
            client: '${e['client']}',
            service: '${e['service']}',
            date: '${e['date']}',
            hour: '${e['hour']}',
            amount: '${e['amount']}',
            address: '${e['address']}',
            description: '${e['description']}',
            rating: (e['rating'] as num?)?.toDouble() ?? 0,
            status: bucket,
            apiStatus: raw,
            paymentType: pay,
            mobileMoneyOperator: mmOp,
            cashFlowStatus: cash,
            clientMessage: '${e['client_message'] ?? ''}',
            clientPhotos: photos,
            bookingId: (e['id'] as num?)?.toInt(),
            disponibilitesClient: '${e['disponibilites_client'] ?? ''}',
            isUrgent: e['is_urgent'] == true,
            prixPropose: (e['prix_propose'] as num?)?.toDouble(),
          );
        }).toList();
        setState(() => items = remote);
        debugPrint('✅ LOADED ${remote.length} requests');
      } else {
        debugPrint('❌ LOAD FAILED — status: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ LOAD ERROR: $e');
      if (mounted) setState(() => items = []);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _applyStatusFromApi(_RequestItem item, String newApiStatus) {
    item.apiStatus = newApiStatus;
    item.status = _RequestsScreenState._bucketFromApi(newApiStatus);
  }

  Future<void> _decide(_RequestItem item, String decision) async {
    if (authToken == null) return;
    try {
      final res = await http.post(
        Uri.parse(
          '${babifixApiBaseUrl()}/api/prestataire/requests/${item.reference}/decision',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({'decision': decision}),
      );
      if (res.statusCode == 200 && mounted) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final st =
            '${body['status'] ?? (decision == 'accept' ? 'DEVIS_EN_COURS' : 'Annulee')}';
        setState(() => _applyStatusFromApi(item, st));

        // Si acceptation → rediriger directement vers CreateDevisScreen
        if (decision == 'accept') {
          if (!mounted) return;
          await Navigator.of(context).push<void>(
            babifixRoute(
              (_) => CreateDevisScreen(
                reservationReference: item.reference,
                reservationDetails: {
                  'client': item.client,
                  'title': item.service,
                  'description_probleme': item.clientMessage,
                  'address': item.address,
                  'payment_type': item.paymentType,
                  'mobile_money_operator': item.mobileMoneyOperator,
                  'disponibilites': item.disponibilitesClient,
                  'is_urgent': item.isUrgent,
                  'prix_propose': item.prixPropose,
                  'date': item.date,
                  'hour': item.hour,
                },
                onBack: () => Navigator.pop(context),
                onDevisCreated: () {
                  Navigator.pop(context);
                  _loadRequests();
                },
              ),
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Action impossible hors connexion API')),
        );
      }
    }
  }

  Future<void> _postReservationStatus(
    _RequestItem item,
    String newStatus,
  ) async {
    if (authToken == null) return;
    try {
      final res = await http.post(
        Uri.parse(
          '${babifixApiBaseUrl()}/api/prestataire/requests/${item.reference}/status',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({'status': newStatus}),
      );
      if (res.statusCode == 200 && mounted) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final st = '${body['status'] ?? newStatus}';
        setState(() => _applyStatusFromApi(item, st));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Statut : ${_RequestsScreenState._labelStatut(st)}'),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur ${res.statusCode}')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impossible de mettre à jour le statut'),
          ),
        );
      }
    }
  }

  Future<void> _demarrerIntervention(_RequestItem item) async {
    if (authToken == null) return;
    try {
      final res = await http.post(
        Uri.parse(
          '${babifixApiBaseUrl()}/api/prestataire/requests/${item.reference}/demarrer',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: '{}',
      );
      if (res.statusCode == 200 && mounted) {
        setState(() => _applyStatusFromApi(item, 'INTERVENTION_EN_COURS'));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Intervention démarrée')),
        );
        _loadRequests();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur ${res.statusCode}')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible de démarrer l\'intervention')),
        );
      }
    }
  }

  Future<void> _terminerIntervention(_RequestItem item) async {
    if (authToken == null) return;
    try {
      final res = await http.post(
        Uri.parse(
          '${babifixApiBaseUrl()}/api/prestataire/requests/${item.reference}/terminer',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: '{}',
      );
      if (res.statusCode == 200 && mounted) {
        setState(() => _applyStatusFromApi(item, 'En attente client'));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Travaux déclarés terminés')),
        );
      } else if (mounted) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${body['error'] ?? 'Erreur ${res.statusCode}'}')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible de terminer l\'intervention')),
        );
      }
    }
  }

  Future<void> _confirmCashPayment(_RequestItem item) async {
    if (authToken == null) return;
    try {
      final res = await http.post(
        Uri.parse(
          '${babifixApiBaseUrl()}/api/prestataire/requests/${item.reference}/cash-confirm',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
      );
      if (res.statusCode == 200 && mounted) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final cfs = '${body['cash_flow_status'] ?? 'pending_admin'}';
        setState(() => item.cashFlowStatus = cfs);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Esp\u00e8ces confirm\u00e9es \u2014 en attente validation admin',
            ),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur ${res.statusCode}')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Confirmation impossible')),
        );
      }
    }
  }

  void _navigateToWaitingPayment(_RequestItem item) {
    Navigator.of(context).push<void>(
      babifixRoute(
        (_) => WaitingPaymentScreen(
          reservationReference: item.reference,
          onBack: () {
            Navigator.pop(context);
            _loadRequests();
          },
          onPaymentReceived: () {
            Navigator.pop(context);
            _loadRequests();
          },
          onCancelled: () {
            Navigator.pop(context);
            _loadRequests();
          },
        ),
      ),
    );
  }

  void _showWaitingPaymentDialog(_RequestItem item) {
    Navigator.of(context).push<void>(
      babifixRoute(
        (_) => WaitingPaymentScreen(
          reservationReference: item.reference,
          onBack: () => Navigator.pop(context),
          onPaymentReceived: () {
            Navigator.pop(context);
            _loadRequests();
          },
          onCancelled: () {
            Navigator.pop(context);
            _loadRequests();
          },
        ),
      ),
    );
  }
}

// ── Modèle de données pour une demande de réservation ───────────────────────
class _RequestItem {
  final String reference;
  final String client;
  final String service;
  final String date;
  final String hour;
  final String amount;
  final String address;
  final String description;
  final double rating;

  /// pending | active | completed | refused
  late String status;

  /// Statut brut API (En attente, Confirmee, En cours, Terminee, Annulee)
  late String apiStatus;
  late String paymentType;
  late String mobileMoneyOperator;
  late String cashFlowStatus;

  /// Message du client décrivant le problème
  final String clientMessage;

  /// Photos envoyées par le client (base64 data URI ou URL HTTP)
  final List<String> clientPhotos;

  /// ID numérique pour les endpoints devis
  final int? bookingId;

  /// Exigences du client
  final String disponibilitesClient;
  final bool isUrgent;
  final double? prixPropose;

  _RequestItem({
    required this.reference,
    required this.client,
    required this.service,
    required this.date,
    required this.hour,
    required this.amount,
    required this.address,
    required this.description,
    required this.rating,
    required this.status,
    this.apiStatus = 'En attente',
    this.paymentType = '',
    this.mobileMoneyOperator = '',
    this.cashFlowStatus = '',
    this.clientMessage = '',
    this.clientPhotos = const [],
    this.bookingId,
    this.disponibilitesClient = '',
    this.isUrgent = false,
    this.prixPropose,
  });
}

// ── Widget d'image sécurisé : gère base64, HTTP et fichier local ──────────────
class _SafeImage extends StatelessWidget {
  const _SafeImage({required this.src, this.size = 80});
  final String src;
  final double size;

  static Widget _placeholder(double sz) => Container(
    width: sz,
    height: sz,
    decoration: BoxDecoration(
      color: const Color(0xFF152A45),
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Icon(Icons.photo_outlined, color: Color(0xFF64748B), size: 28),
  );

  @override
  Widget build(BuildContext context) {
    if (src.isEmpty) return _placeholder(size);

    // Cas 1 : data URI base64
    if (src.startsWith('data:image/')) {
      try {
        final bytes = base64Decode(src.split(',').last);
        return Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(size),
        );
      } catch (_) {
        return _placeholder(size);
      }
    }

    // Cas 2 : URL réseau
    if (src.startsWith('http://') || src.startsWith('https://')) {
      return Image.network(
        src,
        width: size,
        height: size,
        fit: BoxFit.cover,
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: const Color(0xFF152A45),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: BabifixDesign.cyan,
                  ),
                ),
              ),
        errorBuilder: (_, __, ___) => _placeholder(size),
      );
    }

    // Cas 3 : chemin fichier local
    try {
      final file = File(src);
      if (file.existsSync()) {
        return Image.file(
          file,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(size),
        );
      }
    } catch (_) {}

    return _placeholder(size);
  }
}

class _TagPremium extends StatelessWidget {
  const _TagPremium({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = text.toLowerCase();
    late Color bg;
    late Color fg;
    if (t.contains('attente')) {
      bg = const Color(0xFFF59E0B).withValues(alpha: 0.15);
      fg = const Color(0xFFF59E0B);
    } else if (t.contains('annul')) {
      bg = BabifixDesign.error.withValues(alpha: 0.15);
      fg = BabifixDesign.error;
    } else if (t.contains('termin')) {
      bg = BabifixDesign.success.withValues(alpha: 0.15);
      fg = BabifixDesign.success;
    } else if (t.contains('cours')) {
      bg = const Color(0xFF818CF8).withValues(alpha: 0.15);
      fg = const Color(0xFF818CF8);
    } else if (t.contains('confirm')) {
      bg = const Color(0xFF60A5FA).withValues(alpha: 0.15);
      fg = const Color(0xFF60A5FA);
    } else if (t.contains('devis')) {
      bg = BabifixDesign.cyan.withValues(alpha: 0.15);
      fg = BabifixDesign.cyan;
    } else if (t.contains('demande')) {
      bg = const Color(0xFF94A3B8).withValues(alpha: 0.15);
      fg = const Color(0xFF94A3B8);
    } else {
      bg = const Color(0x1AFFFFFF);
      fg = const Color(0xFF94A3B8);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _KanbanStep {
  final String label;
  final int count;
  final IconData icon;
  final Color color;
  final String? bucket;
  _KanbanStep({required this.label, required this.count, required this.icon, required this.color, this.bucket});
}

class _ShimmerCard extends StatefulWidget {
  const _ShimmerCard();
  @override
  State<_ShimmerCard> createState() => _ShimmerCardState();
}

class _ShimmerCardState extends State<_ShimmerCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();
    _anim = Tween<double>(begin: -1.5, end: 1.5).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment(_anim.value - 1, 0),
              end: Alignment(_anim.value + 1, 0),
              colors: const [
                Color(0xFF152A45),
                Color(0xFF1A3355),
                Color(0xFF152A45),
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _Box(w: 48, h: 48, r: 12),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Box(w: double.infinity, h: 14, r: 6),
                        const SizedBox(height: 6),
                        _Box(w: 120, h: 12, r: 6),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _Box(w: 60, h: 28, r: 14),
                ],
              ),
              const SizedBox(height: 12),
              _Box(w: double.infinity, h: 12, r: 6),
              const SizedBox(height: 6),
              _Box(w: 180, h: 12, r: 6),
            ],
          ),
        );
      },
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.w, required this.h, required this.r});
  final double w;
  final double h;
  final double r;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: w == double.infinity ? null : w,
      height: h,
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(r),
      ),
    );
  }
}
