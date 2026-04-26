import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../user_store.dart';

class FideliteScreen extends StatefulWidget {
  const FideliteScreen({super.key, required this.isLight});
  final bool isLight;

  @override
  State<FideliteScreen> createState() => _FideliteScreenState();
}

class _FideliteScreenState extends State<FideliteScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  Map<String, dynamic>? _data;
  String? _error;
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
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
      final token = await BabifixUserStore.getApiToken();
      final res = await http.get(
        Uri.parse('${babifixApiBaseUrl()}/api/client/fidelite/'),
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

  @override
  Widget build(BuildContext context) {
    final isLight = widget.isLight;
    final bg = isLight ? const Color(0xFFF6F8FC) : const Color(0xFF0B1B34);
    final cardBg = isLight ? Colors.white : const Color(0xFF1A2744);
    final textPrimary =
        isLight ? const Color(0xFF0F172A) : Colors.white;
    final textSecondary =
        isLight ? const Color(0xFF64748B) : const Color(0xFFB4C2D9);

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
                padding:
                    const EdgeInsets.fromLTRB(16, 0, 16, 32),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _NiveauCard(
                      data: _data!,
                      cardBg: cardBg,
                      textPrimary: textPrimary,
                      textSecondary: textSecondary,
                      isLight: isLight,
                    ),
                    const SizedBox(height: 20),
                    _SectionHeader(
                      label: 'GARANTIES BABIFIX',
                      icon: Icons.shield_rounded,
                      color: const Color(0xFF22C55E),
                      isLight: isLight,
                    ),
                    const SizedBox(height: 10),
                    _GarantiesCard(
                      garanties: (_data!['garanties'] as List? ?? [])
                          .cast<Map<String, dynamic>>(),
                      cardBg: cardBg,
                      textPrimary: textPrimary,
                      textSecondary: textSecondary,
                      isLight: isLight,
                    ),
                    const SizedBox(height: 20),
                    _SectionHeader(
                      label: 'PARRAINAGE',
                      icon: Icons.people_rounded,
                      color: const Color(0xFFA855F7),
                      isLight: isLight,
                    ),
                    const SizedBox(height: 10),
                    _ParrainageCard(
                      data: _data!,
                      cardBg: cardBg,
                      textPrimary: textPrimary,
                      textSecondary: textSecondary,
                      isLight: isLight,
                    ),
                    const SizedBox(height: 20),
                    _SectionHeader(
                      label: 'NIVEAUX DE FIDÉLITÉ',
                      icon: Icons.emoji_events_rounded,
                      color: const Color(0xFFF59E0B),
                      isLight: isLight,
                    ),
                    const SizedBox(height: 10),
                    _NiveauxTable(
                      cardBg: cardBg,
                      textPrimary: textPrimary,
                      textSecondary: textSecondary,
                      niveauActuel: _data!['niveau'] as String? ?? 'Bronze',
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
      backgroundColor:
          isLight ? const Color(0xFF0D1F3C) : const Color(0xFF0B1B34),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: FlexibleSpaceBar(
        titlePadding:
            const EdgeInsets.fromLTRB(56, 0, 16, 14),
        title: const Text(
          'Mon Programme',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 18,
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
                  colors: [Color(0xFF0D1F3C), Color(0xFF1A3A6B)],
                ),
              ),
            ),
            Positioned(
              right: -20,
              top: -20,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF4CC9F0).withValues(alpha: 0.08),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Carte Niveau ────────────────────────────────────────────────────────────

class _NiveauCard extends StatelessWidget {
  const _NiveauCard({
    required this.data,
    required this.cardBg,
    required this.textPrimary,
    required this.textSecondary,
    required this.isLight,
  });

  final Map<String, dynamic> data;
  final Color cardBg;
  final Color textPrimary;
  final Color textSecondary;
  final bool isLight;

  Color get _niveauColor {
    final hex = data['couleur'] as String? ?? '#CD7F32';
    return Color(int.parse(hex.replaceFirst('#', '0xFF')));
  }

  @override
  Widget build(BuildContext context) {
    final niveau = data['niveau'] as String? ?? 'Bronze';
    final nbRes = data['nb_reservations'] as int? ?? 0;
    final reduction = data['reduction_pct'] as int? ?? 0;
    final prochainNiveau = data['prochain_niveau'] as String?;
    final prochainSeuil = data['prochain_seuil'] as int?;
    final progress = prochainSeuil != null && prochainSeuil > 0
        ? (nbRes / prochainSeuil).clamp(0.0, 1.0)
        : 1.0;
    final niveauColor = _niveauColor;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            niveauColor.withValues(alpha: 0.18),
            niveauColor.withValues(alpha: 0.06),
          ],
        ),
        border: Border.all(color: niveauColor.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: niveauColor.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: niveauColor.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: niveauColor.withValues(alpha: 0.4), width: 2),
                  ),
                  child: Icon(Icons.emoji_events_rounded,
                      color: niveauColor, size: 28),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Niveau $niveau',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: niveauColor,
                      ),
                    ),
                    Text(
                      '$nbRes mission${nbRes > 1 ? 's' : ''} réalisée${nbRes > 1 ? 's' : ''}',
                      style: TextStyle(
                        fontSize: 13,
                        color: textSecondary,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                if (reduction > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: niveauColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: niveauColor.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      '-$reduction%',
                      style: TextStyle(
                        color: niveauColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
              ],
            ),
            if (reduction > 0) ...[
              const SizedBox(height: 12),
              Text(
                'Vous bénéficiez de $reduction% de réduction sur vos prochaines réservations.',
                style: TextStyle(
                    fontSize: 13, color: textSecondary, height: 1.4),
              ),
            ],
            if (prochainNiveau != null && prochainSeuil != null) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Progression vers $prochainNiveau',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: textSecondary),
                  ),
                  Text(
                    '$nbRes / $prochainSeuil',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: niveauColor),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 7,
                  backgroundColor: niveauColor.withValues(alpha: 0.12),
                  valueColor:
                      AlwaysStoppedAnimation<Color>(niveauColor),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Encore ${prochainSeuil - nbRes} mission${prochainSeuil - nbRes > 1 ? 's' : ''} pour atteindre $prochainNiveau.',
                style:
                    TextStyle(fontSize: 12, color: textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Section Header ──────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.icon,
    required this.color,
    required this.isLight,
  });
  final String label;
  final IconData icon;
  final Color color;
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.15),
          ),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: isLight
                ? const Color(0xFF64748B)
                : const Color(0xFF9CA3AF),
          ),
        ),
      ],
    );
  }
}

// ─── Garanties Card ──────────────────────────────────────────────────────────

class _GarantiesCard extends StatelessWidget {
  const _GarantiesCard({
    required this.garanties,
    required this.cardBg,
    required this.textPrimary,
    required this.textSecondary,
    required this.isLight,
  });
  final List<Map<String, dynamic>> garanties;
  final Color cardBg;
  final Color textPrimary;
  final Color textSecondary;
  final bool isLight;

  static const _iconMap = {
    'verified_rounded': Icons.verified_rounded,
    'shield_rounded': Icons.shield_rounded,
    'lock_rounded': Icons.lock_rounded,
    'support_agent_rounded': Icons.support_agent_rounded,
    'star_rounded': Icons.star_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        boxShadow: isLight
            ? [
                BoxShadow(
                    color: const Color(0x0F000000),
                    blurRadius: 16,
                    offset: const Offset(0, 4)),
              ]
            : null,
        border: !isLight
            ? Border.all(color: Colors.white.withValues(alpha: 0.07))
            : null,
      ),
      child: Column(
        children: [
          for (int i = 0; i < garanties.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: 60,
                color: isLight
                    ? const Color(0xFFE2E8F0)
                    : Colors.white.withValues(alpha: 0.07),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _iconMap[garanties[i]['icon']] ??
                          Icons.check_circle_rounded,
                      size: 20,
                      color: const Color(0xFF22C55E),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          garanties[i]['titre'] as String? ?? '',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          garanties[i]['description'] as String? ?? '',
                          style: TextStyle(
                            fontSize: 12,
                            color: textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ],
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

// ─── Parrainage Card ─────────────────────────────────────────────────────────

class _ParrainageCard extends StatefulWidget {
  const _ParrainageCard({
    required this.data,
    required this.cardBg,
    required this.textPrimary,
    required this.textSecondary,
    required this.isLight,
  });
  final Map<String, dynamic> data;
  final Color cardBg;
  final Color textPrimary;
  final Color textSecondary;
  final bool isLight;

  @override
  State<_ParrainageCard> createState() => _ParrainageCardState();
}

class _ParrainageCardState extends State<_ParrainageCard> {
  bool _copied = false;

  void _copy(String code) {
    Clipboard.setData(ClipboardData(text: code));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2),
        () => mounted ? setState(() => _copied = false) : null);
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.data['referral_code'] as String? ?? '—';
    final credits = widget.data['referral_credits'] as num? ?? 0;
    final filleuls = widget.data['filleuls_count'] as int? ?? 0;
    const purple = Color(0xFFA855F7);

    return Container(
      decoration: BoxDecoration(
        color: widget.cardBg,
        borderRadius: BorderRadius.circular(18),
        boxShadow: widget.isLight
            ? [
                BoxShadow(
                    color: const Color(0x0F000000),
                    blurRadius: 16,
                    offset: const Offset(0, 4)),
              ]
            : null,
        border: !widget.isLight
            ? Border.all(color: Colors.white.withValues(alpha: 0.07))
            : null,
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Parrainez vos proches, gagnez des crédits',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: widget.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Votre filleul reçoit 1 000 FCFA de crédit à sa première réservation, vous recevez 2 000 FCFA.',
            style: TextStyle(
                fontSize: 13,
                color: widget.textSecondary,
                height: 1.4),
          ),
          const SizedBox(height: 16),
          // Code parrainage
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: purple.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: purple.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                const Icon(Icons.qr_code_rounded,
                    color: purple, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    code,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: purple,
                      letterSpacing: 3,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => _copy(code),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _copied
                          ? const Color(0xFF22C55E).withValues(alpha: 0.15)
                          : purple.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _copied ? 'Copié !' : 'Copier',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _copied
                            ? const Color(0xFF22C55E)
                            : purple,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Stats parrainage
          Row(
            children: [
              Expanded(
                child: _StatChip(
                  icon: Icons.group_rounded,
                  label: 'Filleuls',
                  value: '$filleuls',
                  color: purple,
                  isLight: widget.isLight,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatChip(
                  icon: Icons.savings_rounded,
                  label: 'Crédits gagnés',
                  value: '${credits.toInt()} FCFA',
                  color: const Color(0xFF22C55E),
                  isLight: widget.isLight,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.isLight,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: isLight
                  ? const Color(0xFF64748B)
                  : const Color(0xFF9CA3AF),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Tableau niveaux ─────────────────────────────────────────────────────────

class _NiveauxTable extends StatelessWidget {
  const _NiveauxTable({
    required this.cardBg,
    required this.textPrimary,
    required this.textSecondary,
    required this.niveauActuel,
  });
  final Color cardBg;
  final Color textPrimary;
  final Color textSecondary;
  final String niveauActuel;

  static const _niveaux = [
    _NiveauInfo('Bronze', '0–4 missions', '0%', Color(0xFFCD7F32)),
    _NiveauInfo('Argent', '5–9 missions', '-5%', Color(0xFF64748B)),
    _NiveauInfo('Or', '10–19 missions', '-10%', Color(0xFFF59E0B)),
    _NiveauInfo('Platine', '20+ missions', '-15%', Color(0xFFA855F7)),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          for (int i = 0; i < _niveaux.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, color: Color(0xFFE2E8F0)),
            _NiveauRow(
              info: _niveaux[i],
              isActuel: _niveaux[i].nom == niveauActuel,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
            ),
          ],
        ],
      ),
    );
  }
}

class _NiveauInfo {
  const _NiveauInfo(this.nom, this.condition, this.reduction, this.color);
  final String nom;
  final String condition;
  final String reduction;
  final Color color;
}

class _NiveauRow extends StatelessWidget {
  const _NiveauRow({
    required this.info,
    required this.isActuel,
    required this.textPrimary,
    required this.textSecondary,
  });
  final _NiveauInfo info;
  final bool isActuel;
  final Color textPrimary;
  final Color textSecondary;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: isActuel
          ? BoxDecoration(
              color: info.color.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(0),
            )
          : null,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: info.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.emoji_events_rounded,
                color: info.color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      info.nom,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: info.color,
                      ),
                    ),
                    if (isActuel) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: info.color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Actuel',
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: info.color),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  info.condition,
                  style: TextStyle(
                      fontSize: 12, color: textSecondary),
                ),
              ],
            ),
          ),
          Text(
            info.reduction,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: info.color,
            ),
          ),
        ],
      ),
    );
  }
}
