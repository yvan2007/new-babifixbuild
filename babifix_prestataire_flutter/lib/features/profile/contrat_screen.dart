import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../shared/auth_utils.dart';
import '../../shared/app_palette_mode.dart';

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
      duration: const Duration(milliseconds: 600),
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
    // Charger d'abord depuis local (affichage immédiat)
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kAcceptedKey);
    if (stored != null) {
      _acceptedAt = DateTime.tryParse(stored);
    }
    await _load();
    // Après la réponse serveur, utiliser la date de signature serveur si disponible
    if (_data != null && _data!['contrat_accepte_at'] != null) {
      final serverDate = DateTime.tryParse('${_data!['contrat_accepte_at']}');
      if (serverDate != null && mounted) {
        setState(() => _acceptedAt = serverDate);
        // Synchroniser le cache local avec la date serveur
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
            const SnackBar(
              content: Text('Contrat signé et enregistré. Merci !'),
              backgroundColor: Color(0xFF22C55E),
              behavior: SnackBarBehavior.floating,
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
    final isLight = widget.paletteMode == AppPaletteMode.light;
    final bg = isLight ? const Color(0xFFF6F8FC) : const Color(0xFF0B1B34);
    final cardBg = isLight ? Colors.white : const Color(0xFF1A2744);
    final textPrimary = isLight ? const Color(0xFF0F172A) : Colors.white;
    final textSecondary =
        isLight ? const Color(0xFF64748B) : const Color(0xFFB4C2D9);
    final divider = isLight
        ? const Color(0xFFE2E8F0)
        : Colors.white.withValues(alpha: 0.07);

    return Scaffold(
      backgroundColor: bg,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(isLight, textPrimary),
          if (_loading)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFF4CC9F0)),
              ),
            )
          else if (_error != null)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline_rounded,
                        size: 56,
                        color: textSecondary.withValues(alpha: 0.5)),
                    const SizedBox(height: 16),
                    Text(_error!,
                        style: TextStyle(color: textSecondary)),
                    const SizedBox(height: 16),
                    FilledButton(
                        onPressed: _load,
                        child: const Text('Réessayer')),
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
                    _StatsCard(
                        data: _data!,
                        cardBg: cardBg,
                        textPrimary: textPrimary,
                        textSecondary: textSecondary,
                        isLight: isLight,
                        divider: divider),
                    const SizedBox(height: 20),
                    _CommissionCard(
                        data: _data!,
                        cardBg: cardBg,
                        textPrimary: textPrimary,
                        textSecondary: textSecondary,
                        isLight: isLight),
                    const SizedBox(height: 20),
                    _ClausesSection(
                        clauses: (_data!['clauses'] as List? ?? [])
                            .cast<Map<String, dynamic>>(),
                        cardBg: cardBg,
                        textPrimary: textPrimary,
                        textSecondary: textSecondary,
                        isLight: isLight,
                        divider: divider),
                    const SizedBox(height: 24),
                    _AcceptanceFooter(
                      acceptedAt: _acceptedAt,
                      isLight: isLight,
                      textSecondary: textSecondary,
                      onAccept: _acceptedAt == null ? _acceptContrat : null,
                    ),
                  ]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  SliverAppBar _buildAppBar(bool isLight, Color textPrimary) {
    return SliverAppBar(
      expandedHeight: 120,
      pinned: true,
      backgroundColor: const Color(0xFF0B1B34),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        onPressed: widget.onBack,
      ),
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.fromLTRB(56, 0, 16, 14),
        title: const Text(
          'Mon Contrat',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
        ),
        background: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0B1B34), Color(0xFF1E3A6E)],
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
                  color: const Color(0xFF4CC9F0).withValues(alpha: 0.06),
                ),
              ),
            ),
            const Positioned(
              left: 0,
              right: 0,
              bottom: 14,
              child: SizedBox(),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Stats Card ──────────────────────────────────────────────────────────────

class _StatsCard extends StatelessWidget {
  const _StatsCard({
    required this.data,
    required this.cardBg,
    required this.textPrimary,
    required this.textSecondary,
    required this.isLight,
    required this.divider,
  });
  final Map<String, dynamic> data;
  final Color cardBg, textPrimary, textSecondary, divider;
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    final nom = data['nom'] as String? ?? '';
    final specialite = data['specialite'] as String? ?? '';
    final ville = data['ville'] as String? ?? '';
    final rating = (data['average_rating'] as num?)?.toDouble() ?? 0.0;
    final nbMissions = data['nb_missions'] as int? ?? 0;
    final isCertified = data['is_certified'] as bool? ?? false;
    final isPremium = data['is_premium'] as bool? ?? false;
    final tier = data['premium_tier'] as String? ?? 'standard';

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        boxShadow: isLight
            ? [BoxShadow(color: const Color(0x0F000000), blurRadius: 16)]
            : null,
        border: !isLight
            ? Border.all(color: Colors.white.withValues(alpha: 0.07))
            : null,
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFF4CC9F0).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_rounded,
                    color: Color(0xFF4CC9F0), size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nom,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: textPrimary)),
                    Text('$specialite • $ville',
                        style: TextStyle(
                            fontSize: 12, color: textSecondary)),
                  ],
                ),
              ),
              Column(
                children: [
                  if (isCertified)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CC9F0).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified_rounded,
                              color: Color(0xFF4CC9F0), size: 13),
                          SizedBox(width: 3),
                          Text('Certifié',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF4CC9F0))),
                        ],
                      ),
                    ),
                  if (isPremium) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        tier[0].toUpperCase() + tier.substring(1),
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFF59E0B)),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: divider),
          const SizedBox(height: 14),
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
              Expanded(
                child: _MiniStat(
                  icon: Icons.star_rounded,
                  label: 'Note moyenne',
                  value: rating > 0 ? rating.toStringAsFixed(1) : '—',
                  color: const Color(0xFFF59E0B),
                ),
              ),
              Expanded(
                child: _MiniStat(
                  icon: Icons.workspace_premium_rounded,
                  label: 'Statut',
                  value: isPremium
                      ? tier[0].toUpperCase() + tier.substring(1)
                      : 'Standard',
                  color: isPremium
                      ? const Color(0xFFF59E0B)
                      : const Color(0xFF64748B),
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
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w800, color: color)),
        Text(label,
            style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
      ],
    );
  }
}

// ─── Commission Card ─────────────────────────────────────────────────────────

class _CommissionCard extends StatelessWidget {
  const _CommissionCard({
    required this.data,
    required this.cardBg,
    required this.textPrimary,
    required this.textSecondary,
    required this.isLight,
  });
  final Map<String, dynamic> data;
  final Color cardBg, textPrimary, textSecondary;
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    final rate = data['commission_rate'] as int? ?? 18;
    final base = data['commission_base'] as int? ?? 18;
    final reduction = data['premium_reduction'] as int? ?? 0;
    const cyan = Color(0xFF4CC9F0);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cyan.withValues(alpha: 0.14),
            cyan.withValues(alpha: 0.04),
          ],
        ),
        border: Border.all(color: cyan.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: cyan.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.percent_rounded,
                    color: cyan, size: 22),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Commission BABIFIX',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: textPrimary)),
                  Text('Taux appliqué sur vos prestations',
                      style: TextStyle(
                          fontSize: 12, color: textSecondary)),
                ],
              ),
              const Spacer(),
              Text(
                '$rate%',
                style: const TextStyle(
                    fontSize: 32, fontWeight: FontWeight.w900, color: cyan),
              ),
            ],
          ),
          if (reduction > 0) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFF22C55E).withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.workspace_premium_rounded,
                      color: Color(0xFF22C55E), size: 18),
                  const SizedBox(width: 8),
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
          const SizedBox(height: 12),
          Text(
            'Exemple : pour une prestation à 10 000 FCFA, BABIFIX prélève ${(10000 * rate / 100).round()} FCFA — vous recevez ${(10000 * (100 - rate) / 100).round()} FCFA net.',
            style:
                TextStyle(fontSize: 12, color: textSecondary, height: 1.4),
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
    required this.cardBg,
    required this.textPrimary,
    required this.textSecondary,
    required this.isLight,
    required this.divider,
  });
  final List<Map<String, dynamic>> clauses;
  final Color cardBg, textPrimary, textSecondary, divider;
  final bool isLight;

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
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF4CC9F0).withValues(alpha: 0.15),
              ),
              child: const Icon(Icons.description_rounded,
                  size: 15, color: Color(0xFF4CC9F0)),
            ),
            const SizedBox(width: 8),
            Text(
              'CLAUSES DU CONTRAT',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: widget.isLight
                    ? const Color(0xFF64748B)
                    : const Color(0xFF9CA3AF),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: widget.cardBg,
            borderRadius: BorderRadius.circular(18),
            boxShadow: widget.isLight
                ? [
                    BoxShadow(
                        color: const Color(0x0F000000),
                        blurRadius: 16)
                  ]
                : null,
            border: !widget.isLight
                ? Border.all(
                    color: Colors.white.withValues(alpha: 0.07))
                : null,
          ),
          child: Column(
            children: [
              for (int i = 0; i < widget.clauses.length; i++) ...[
                if (i > 0)
                  Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                      color: widget.divider),
                _ClauseTile(
                  index: i + 1,
                  clause: widget.clauses[i],
                  isExpanded: _expanded == i,
                  textPrimary: widget.textPrimary,
                  textSecondary: widget.textSecondary,
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
    required this.textPrimary,
    required this.textSecondary,
    required this.onTap,
  });
  final int index;
  final Map<String, dynamic> clause;
  final bool isExpanded;
  final Color textPrimary, textSecondary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CC9F0).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Text(
                      '$index',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF4CC9F0)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    clause['titre'] as String? ?? '',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: textPrimary),
                  ),
                ),
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: textSecondary,
                  size: 20,
                ),
              ],
            ),
            if (isExpanded) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(left: 34),
                child: Text(
                  clause['contenu'] as String? ?? '',
                  style: TextStyle(
                      fontSize: 13,
                      color: textSecondary,
                      height: 1.5),
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
    required this.isLight,
    required this.textSecondary,
    required this.onAccept,
  });
  final DateTime? acceptedAt;
  final bool isLight;
  final Color textSecondary;
  final VoidCallback? onAccept;

  String _fmt(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} à ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (acceptedAt != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF22C55E).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: const Color(0xFF22C55E).withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: Color(0xFF22C55E), size: 28),
            const SizedBox(width: 12),
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
                  Text(
                    'Le ${_fmt(acceptedAt!)}',
                    style: TextStyle(
                        fontSize: 12, color: textSecondary),
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
          style: TextStyle(
              fontSize: 12, color: textSecondary, height: 1.4),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 52,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4CC9F0), Color(0xFF0EA5E9)],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4CC9F0).withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
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
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800),
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
