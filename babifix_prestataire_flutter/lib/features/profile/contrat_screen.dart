import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../shared/auth_utils.dart';
import '../../shared/app_palette_mode.dart';

// ─── Premium Colors ────────────────────────────────────────────────────────

const _premiumGold = Color(0xFFFFD700);
const _premiumGoldLight = Color(0xFFFFF4B0);
const _deepNavy = Color(0xFF0B1B34);
const _charcoal = Color(0xFF1A2744);
const _darkSurface = Color(0xFF0A0E27);
const _cardBg = Color(0xFF151B30);

class ContratScreen extends StatefulWidget {
  const ContratScreen({
    super.key,
    required this.onBack,
    required this.paletteMode,
  });
  final VoidCallback onBack;
  final AppPaletteMode paletteMode;

  @override
  State<ContratScreen> createState() => _ContratScreenState();
}

class _ContratScreenState extends State<ContratScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  Map<String, dynamic>? _data;
  String? _error;
  DateTime? _acceptedAt;
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fade;

  static const _kAcceptedKey = 'contrat_accepte_at_v1';

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _loadAll();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kAcceptedKey);
    if (stored != null) {
      _acceptedAt = DateTime.tryParse(stored);
    }
    await _load();
    if (_data != null && _data!['contrat_accepte_at'] != null) {
      final serverDate = DateTime.tryParse('${_data!['contrat_accepte_at']}');
      if (serverDate != null && mounted) {
        setState(() => _acceptedAt = serverDate);
        await prefs.setString(_kAcceptedKey, serverDate.toIso8601String());
      }
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = await readStoredApiToken();
      final res = await http.get(
        Uri.parse('${babifixApiBaseUrl()}/api/prestataire/contrat/'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        setState(() {
          _data = jsonDecode(res.body) as Map<String, dynamic>;
          _loading = false;
        });
        _fadeCtrl.forward();
      } else {
        setState(() {
          _error = 'Erreur serveur (${res.statusCode})';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Erreur réseau';
        _loading = false;
      });
    }
  }

  Future<void> _acceptContrat() async {
    final token = await readStoredApiToken();
    if (token == null || token.isEmpty) return;
    try {
      final res = await http.post(
        Uri.parse('${babifixApiBaseUrl()}/api/prestataire/contrat/sign/'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: '{"version":"${_data?['contrat_version'] ?? '1.0'}"}',
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final now = DateTime.now();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kAcceptedKey, now.toIso8601String());
        if (mounted) {
          setState(() => _acceptedAt = now);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Contrat signé et enregistré. Merci !'),
              backgroundColor: const Color(0xFF22C55E),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Erreur lors de la signature. Réessayez.'),
              backgroundColor: Color(0xFFDC2626),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erreur réseau. Vérifiez votre connexion.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_deepNavy, _darkSurface, _deepNavy],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: CustomScrollView(
          slivers: [
            _buildAppBar(),
            if (_loading)
              const SliverFillRemaining(
                child: Center(
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      color: _premiumGold,
                      strokeWidth: 3,
                    ),
                  ),
                ),
              )
            else if (_error != null)
              SliverFillRemaining(
                child: Center(
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
                        child: const Icon(Icons.error_outline_rounded,
                            size: 40, color: Colors.white54),
                      ),
                      const SizedBox(height: 16),
                      Text(_error!, style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _load,
                        style: FilledButton.styleFrom(
                          backgroundColor: _premiumGold,
                          foregroundColor: _deepNavy,
                        ),
                        child: const Text('Réessayer'),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverFadeTransition(
                opacity: _fade,
                sliver: SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _StatsCard(data: _data!),
                      const SizedBox(height: 20),
                      _CommissionCard(data: _data!),
                      const SizedBox(height: 20),
                      _ClausesSection(
                        clauses: (_data!['clauses'] as List? ?? [])
                            .cast<Map<String, dynamic>>(),
                      ),
                      const SizedBox(height: 24),
                      _AcceptanceFooter(
                        acceptedAt: _acceptedAt,
                        onAccept: _acceptedAt == null ? _acceptContrat : null,
                      ),
                    ]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  SliverAppBar _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 130,
      pinned: true,
      backgroundColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        onPressed: widget.onBack,
      ),
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.fromLTRB(56, 0, 16, 16),
        title: const Text(
          'Mon Contrat',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 20,
            letterSpacing: 0.3,
          ),
        ),
        background: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_deepNavy, Color(0xFF1E3A6E), _deepNavy],
                ),
              ),
            ),
            Positioned(
              right: -30,
              top: -30,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _premiumGold.withValues(alpha: 0.08),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: -40,
              bottom: -40,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _premiumGold.withValues(alpha: 0.05),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Stats Card ──────────────────────────────────────────────────────────────

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final nom = data['nom'] as String? ?? 'PRESTATAIRE';
    final specialite = data['specialite'] as String? ?? '';
    final ville = data['ville'] as String? ?? '';
    final rating = (data['average_rating'] as num?)?.toDouble() ?? 0.0;
    final nbMissions = data['nb_missions'] as int? ?? 0;
    final isCertified = data['is_certified'] as bool? ?? false;
    final isPremium = data['is_premium'] as bool? ?? false;
    final tier = data['premium_tier'] as String? ?? 'standard';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_cardBg, const Color(0xFF1A2744)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _premiumGold.withValues(alpha: 0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: _premiumGold.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _premiumGold.withValues(alpha: 0.2),
                      _premiumGold.withValues(alpha: 0.05),
                    ],
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _premiumGold.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: const Icon(Icons.person_rounded,
                    color: _premiumGold, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nom,
                        style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.3)),
                    const SizedBox(height: 2),
                    Text('$specialite • $ville',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white70)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (isCertified)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _premiumGold.withValues(alpha: 0.2),
                            _premiumGold.withValues(alpha: 0.05),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _premiumGold.withValues(alpha: 0.4),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified_rounded,
                              color: _premiumGold, size: 14),
                          SizedBox(width: 4),
                          Text('Certifié',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: _premiumGold)),
                        ],
                      ),
                    ),
                  if (isPremium) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _premiumGold.withValues(alpha: 0.2),
                            _premiumGold.withValues(alpha: 0.05),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _premiumGold.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.workspace_premium_rounded,
                              color: _premiumGold, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            '${tier[0].toUpperCase()}${tier.substring(1)}',
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: _premiumGold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  _premiumGold.withValues(alpha: 0.3),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  icon: Icons.assignment_turned_in_rounded,
                  label: 'Missions',
                  value: '$nbMissions',
                  color: const Color(0xFF22C55E),
                ),
              ),
              Container(width: 1, height: 40, color: Colors.white.withValues(alpha: 0.1)),
              Expanded(
                child: _MiniStat(
                  icon: Icons.star_rounded,
                  label: 'Note moyenne',
                  value: rating > 0 ? rating.toStringAsFixed(1) : '—',
                  color: _premiumGold,
                ),
              ),
              Container(width: 1, height: 40, color: Colors.white.withValues(alpha: 0.1)),
              Expanded(
                child: _MiniStat(
                  icon: Icons.workspace_premium_rounded,
                  label: 'Statut',
                  value: isPremium
                      ? '${tier[0].toUpperCase()}${tier.substring(1)}'
                      : 'Standard',
                  color: isPremium ? _premiumGold : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label, value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 6),
        Text(value,
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w900, color: color)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(fontSize: 10, color: Colors.white54)),
      ],
    );
  }
}

// ─── Commission Card ─────────────────────────────────────────────────────────

class _CommissionCard extends StatelessWidget {
  const _CommissionCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final rate = data['commission_rate'] as int? ?? 18;
    final base = data['commission_base'] as int? ?? 18;
    final reduction = data['premium_reduction'] as int? ?? 0;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1A2744),
            _cardBg,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _premiumGold.withValues(alpha: 0.25),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: _premiumGold.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _premiumGold.withValues(alpha: 0.2),
                      _premiumGold.withValues(alpha: 0.05),
                    ],
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _premiumGold.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: const Icon(Icons.percent_rounded,
                    color: _premiumGold, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Commission BABIFIX',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.3)),
                    const SizedBox(height: 2),
                    const Text('Taux appliqué sur vos prestations',
                        style: TextStyle(
                            fontSize: 12, color: Colors.white70)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _premiumGold.withValues(alpha: 0.2),
                      _premiumGold.withValues(alpha: 0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _premiumGold.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  '$rate%',
                  style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.w900, color: _premiumGold),
                ),
              ),
            ],
          ),
          if (reduction > 0) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF0A2E0A),
                    const Color(0xFF0D3A0D),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF22C55E).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.workspace_premium_rounded,
                      color: Color(0xFF22C55E), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Réduction Premium : -$reduction% (taux de base $base% → $rate% effectif)',
                      style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF22C55E),
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
            child: Text(
              'Exemple : pour une prestation à 10 000 FCFA, BABIFIX prélève ${(10000 * rate / 100).round()} FCFA — vous recevez ${(10000 * (100 - rate) / 100).round()} FCFA net.',
              style: const TextStyle(
                  fontSize: 12, color: Colors.white54, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Clauses Section ─────────────────────────────────────────────────────────

class _ClausesSection extends StatefulWidget {
  const _ClausesSection({
    required this.clauses,
  });
  final List<Map<String, dynamic>> clauses;

  @override
  State<_ClausesSection> createState() => _ClausesSectionState();
}

class _ClausesSectionState extends State<_ClausesSection> {
  int? _expanded;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _premiumGold.withValues(alpha: 0.2),
                    _premiumGold.withValues(alpha: 0.05),
                  ],
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _premiumGold.withValues(alpha: 0.4),
                ),
              ),
              child: const Icon(Icons.description_rounded,
                  size: 16, color: _premiumGold),
            ),
            const SizedBox(width: 10),
            const Text(
              'CLAUSES DU CONTRAT',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: Colors.white54,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_cardBg, Color(0xFF1A2744)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _premiumGold.withValues(alpha: 0.2),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: _premiumGold.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              for (int i = 0; i < widget.clauses.length; i++) ...[
                if (i > 0)
                  Container(
                    height: 1,
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          _premiumGold.withValues(alpha: 0.2),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                _ClauseTile(
                  index: i + 1,
                  clause: widget.clauses[i],
                  isExpanded: _expanded == i,
                  onTap: () =>
                      setState(() => _expanded = _expanded == i ? null : i),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ClauseTile extends StatelessWidget {
  const _ClauseTile({
    required this.index,
    required this.clause,
    required this.isExpanded,
    required this.onTap,
  });
  final int index;
  final Map<String, dynamic> clause;
  final bool isExpanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _premiumGold.withValues(alpha: 0.2),
                        _premiumGold.withValues(alpha: 0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _premiumGold.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '$index',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: _premiumGold),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    clause['titre'] as String? ?? '',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                  ),
                ),
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: Colors.white54,
                  size: 20,
                ),
              ],
            ),
            if (isExpanded) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.only(left: 40),
                child: Text(
                  clause['contenu'] as String? ?? '',
                  style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white70,
                      height: 1.6),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Acceptance Footer ───────────────────────────────────────────────────────

class _AcceptanceFooter extends StatelessWidget {
  const _AcceptanceFooter({
    required this.acceptedAt,
    required this.onAccept,
  });
  final DateTime? acceptedAt;
  final VoidCallback? onAccept;

  String _fmt(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} à ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (acceptedAt != null) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF0A2E0A),
              const Color(0xFF0D3A0D),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF22C55E).withValues(alpha: 0.3),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF22C55E).withValues(alpha: 0.1),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E).withValues(alpha: 0.2),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF22C55E).withValues(alpha: 0.4),
                ),
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF22C55E), size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Contrat accepté',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF22C55E)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Le ${_fmt(acceptedAt!)}',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'En acceptant ce contrat, vous confirmez avoir lu et compris l\'ensemble des clauses ci-dessus et vous engagez à les respecter.',
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 12, color: Colors.white54, height: 1.5),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 56,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_premiumGold, Color(0xFFFFE55C)],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: _premiumGold.withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onAccept,
                child: const Center(
                  child: Text(
                    'J\'accepte le contrat',
                    style: TextStyle(
                        color: _deepNavy,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.3),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
