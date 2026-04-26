import 'dart:convert';
import 'dart:math' as math;

import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../babifix_money.dart';
import '../../models/client_models.dart';
import '../../services/zego_call_service.dart';
import '../../user_store.dart';
import '../booking/booking_flow_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class ProviderProfileScreen extends StatefulWidget {
  const ProviderProfileScreen({
    super.key,
    required this.providerId,
    this.onStartReservation,
  });

  final int providerId;
  final Future<bool> Function(ClientService service)? onStartReservation;

  @override
  State<ProviderProfileScreen> createState() => _ProviderProfileScreenState();
}

class _ProviderProfileScreenState extends State<ProviderProfileScreen>
    with TickerProviderStateMixin {
  Map<String, dynamic>? _provider;
  List<Map<String, dynamic>> _services = [];
  List<Map<String, dynamic>> _reviews = [];
  bool _loading = true;
  String? _error;
  bool _bioExpanded = false;

  late AnimationController _pulseCtrl;
  late AnimationController _entryCtrl;
  late Animation<double> _entryAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _entryAnim = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);

    _load();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _entryCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final token = await BabifixUserStore.getApiToken();
      final headers = token != null ? {'Authorization': 'Bearer $token'} : <String, String>{};
      final res = await http.get(
        Uri.parse('${babifixApiBaseUrl()}/api/client/prestataires/${widget.providerId}/'),
        headers: headers,
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _provider = data;
          _services = (data['services'] as List? ?? []).cast<Map<String, dynamic>>();
          _reviews = (data['avis'] as List? ?? []).cast<Map<String, dynamic>>();
          _loading = false;
        });
        _entryCtrl.forward();
      } else {
        setState(() { _error = 'Profil introuvable (${res.statusCode})'; _loading = false; });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() { _error = 'Connexion impossible. Réessayez.'; _loading = false; });
    }
  }

  ClientService _serviceForBooking() {
    final p = _provider ?? {};
    final first = _services.isNotEmpty ? _services.first : null;
    return ClientService(
      title: first?['titre'] as String? ?? (p['metier'] as String? ?? 'Prestation'),
      category: '',
      duration: 'Sur devis',
      price: (first?['tarif'] as num?)?.toInt() ?? 15000,
      rating: (p['note'] as num?)?.toDouble() ?? 4.5,
      verified: true,
      color: BabifixDesign.ciBlue,
      imageUrl: 'assets/images/service-plomberie.jpg',
      providerId: widget.providerId,
    );
  }

  Future<void> _openReservation() async {
    final service = _serviceForBooking();
    final p = _provider ?? {};
    if (widget.onStartReservation != null) {
      await widget.onStartReservation!(service);
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => BookingFlowScreen(
        serviceTitle: service.title,
        servicePrice: service.price,
        providerName: p['nom'] as String? ?? '',
        providerPhoto: p['photo_portrait_url'] as String?,
        providerRating: (p['average_rating'] as num?)?.toDouble(),
        providerSpecialite: p['specialite'] as String?,
        providerId: widget.providerId,
      ),
    ));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) return _buildLoading();
    if (_error != null && _provider == null) return _buildError();

    final p = _provider!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final name = '${p['prenom'] ?? p['user']?['first_name'] ?? ''} ${p['nom'] ?? p['user']?['last_name'] ?? ''}'.trim();
    final metier = p['metier'] as String? ?? p['specialite'] as String? ?? '';
    final ville = p['ville'] as String? ?? '';
    final note = (p['note'] ?? p['average_rating'] as num?)?.toDouble() ?? 0.0;
    final nbAvis = (p['nb_avis'] ?? p['rating_count'] ?? 0) as int;
    final nbMissions = p['nb_missions'] as int? ?? 0;
    final tauxReussite = p['taux_reussite'] as int? ?? 0;
    final yearsExp = p['years_experience'] as int? ?? 0;
    final desc = (p['description'] ?? p['bio'] ?? '') as String;
    final disponible = (p['disponible'] ?? true) as bool;
    final tarif = (p['tarif_horaire'] as num?)?.toInt() ?? 0;
    final isCertified = (p['is_certified'] ?? false) as bool;
    final isPremium = (p['is_premium'] ?? false) as bool;
    final premiumTier = (p['premium_tier'] ?? '') as String;
    final photoUrl = (p['photo_portrait_url'] ?? p['photo_url'] ?? '') as String;
    final portfolioPhotos = (p['portfolio_photos'] as List? ?? []);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D1117) : const Color(0xFFF0F2F5),
      body: FadeTransition(
        opacity: _entryAnim,
        child: CustomScrollView(
          slivers: [
            _buildHeroAppBar(
              context: context,
              name: name,
              metier: metier,
              ville: ville,
              photoUrl: photoUrl,
              disponible: disponible,
              isCertified: isCertified,
              isPremium: isPremium,
              premiumTier: premiumTier,
              note: note,
              nbAvis: nbAvis,
            ),
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Stats row
                  _buildStatsRow(
                    context,
                    note: note,
                    nbAvis: nbAvis,
                    nbMissions: nbMissions,
                    tauxReussite: tauxReussite,
                    yearsExp: yearsExp,
                  ),
                  const SizedBox(height: 20),

                  // Bio
                  if (desc.isNotEmpty) _buildBioSection(context, desc),

                  // Portfolio
                  if (portfolioPhotos.isNotEmpty)
                    _buildPortfolio(context, portfolioPhotos),

                  // Services
                  if (_services.isNotEmpty)
                    _buildServices(context, _services, tarif),

                  // Reviews
                  if (_reviews.isNotEmpty)
                    _buildReviews(context, _reviews, note, nbAvis),

                  const SizedBox(height: 120),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomBar(
        context,
        name: name,
        disponible: disponible,
        tarif: tarif,
      ),
    );
  }

  // ── Hero AppBar ─────────────────────────────────────────────────────────────

  Widget _buildHeroAppBar({
    required BuildContext context,
    required String name,
    required String metier,
    required String ville,
    required String photoUrl,
    required bool disponible,
    required bool isCertified,
    required bool isPremium,
    required String premiumTier,
    required double note,
    required int nbAvis,
  }) {
    final tierColors = _premiumColors(premiumTier);

    return SliverAppBar(
      expandedHeight: 300,
      pinned: true,
      stretch: true,
      backgroundColor: const Color(0xFF0A1628),
      foregroundColor: Colors.white,
      elevation: 0,
      actions: [
        IconButton(
          icon: const Icon(Icons.share_rounded, color: Colors.white70),
          onPressed: () => Share.share(
            '🔧 Découvrez $name sur BABIFIX\n${babifixApiBaseUrl()}/prestataire/${widget.providerId}',
            subject: 'Prestataire BABIFIX — $name',
          ),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [StretchMode.blurBackground, StretchMode.zoomBackground],
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Gradient background
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF0A1628),
                    isPremium ? tierColors[0].withValues(alpha: 0.6) : const Color(0xFF0D2137),
                    const Color(0xFF0A1628),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),

            // Premium shimmer effect
            if (isPremium)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (_, __) => CustomPaint(
                    painter: _ShimmerPainter(_pulseCtrl.value, tierColors[0]),
                  ),
                ),
              ),

            // Content
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  // Avatar
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      // Premium ring
                      if (isPremium)
                        AnimatedBuilder(
                          animation: _pulseCtrl,
                          builder: (_, __) => Container(
                            width: 108 + _pulseCtrl.value * 8,
                            height: 108 + _pulseCtrl.value * 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: SweepGradient(colors: [...tierColors, tierColors[0]]),
                            ),
                          ),
                        ),
                      if (!isPremium)
                        Container(
                          width: 104,
                          height: 104,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: disponible ? BabifixDesign.cyan : Colors.grey,
                              width: 2.5,
                            ),
                          ),
                        ),
                      // Photo
                      CircleAvatar(
                        radius: 46,
                        backgroundColor: const Color(0xFF1E3A5F),
                        backgroundImage: photoUrl.startsWith('http')
                            ? NetworkImage(photoUrl) as ImageProvider
                            : null,
                        child: photoUrl.startsWith('http')
                            ? null
                            : Text(
                                name.isNotEmpty ? name[0].toUpperCase() : 'P',
                                style: const TextStyle(
                                  fontSize: 38,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                      // Disponible dot
                      Positioned(
                        bottom: 2,
                        right: 2,
                        child: AnimatedBuilder(
                          animation: _pulseCtrl,
                          builder: (_, __) => Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: disponible ? const Color(0xFF22C55E) : Colors.grey,
                              border: Border.all(color: const Color(0xFF0A1628), width: 2.5),
                              boxShadow: disponible
                                  ? [
                                      BoxShadow(
                                        color: const Color(0xFF22C55E)
                                            .withValues(alpha: 0.4 + 0.4 * _pulseCtrl.value),
                                        blurRadius: 8,
                                        spreadRadius: 2,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Name + badges
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                name,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                            if (isCertified) ...[
                              const SizedBox(width: 6),
                              const _VerifiedBadge(),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              metier,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (ville.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Container(
                                width: 3,
                                height: 3,
                                decoration: const BoxDecoration(
                                  color: Colors.white38,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(Icons.place_rounded, size: 13, color: Colors.white54),
                              const SizedBox(width: 2),
                              Text(
                                ville,
                                style: const TextStyle(color: Colors.white54, fontSize: 13),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (isPremium) ...[
                              _PremiumBadge(tier: premiumTier, colors: tierColors),
                              const SizedBox(width: 8),
                            ],
                            _ChipBadge(
                              label: disponible ? '● Disponible' : '● Indisponible',
                              color: disponible ? const Color(0xFF22C55E) : Colors.grey,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Stats Row ──────────────────────────────────────────────────────────────

  Widget _buildStatsRow(
    BuildContext context, {
    required double note,
    required int nbAvis,
    required int nbMissions,
    required int tauxReussite,
    required int yearsExp,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          _StatCell(
            value: note > 0 ? note.toStringAsFixed(1) : '—',
            label: '$nbAvis avis',
            icon: Icons.star_rounded,
            color: const Color(0xFFF59E0B),
          ),
          _divider(),
          _StatCell(
            value: '$nbMissions',
            label: 'Missions',
            icon: Icons.check_circle_rounded,
            color: BabifixDesign.cyan,
          ),
          _divider(),
          _StatCell(
            value: tauxReussite > 0 ? '$tauxReussite%' : '—',
            label: 'Réussite',
            icon: Icons.thumb_up_rounded,
            color: const Color(0xFF10B981),
          ),
          _divider(),
          _StatCell(
            value: yearsExp > 0 ? '${yearsExp}an${yearsExp > 1 ? 's' : ''}' : '—',
            label: 'Expérience',
            icon: Icons.workspace_premium_rounded,
            color: const Color(0xFF8B5CF6),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 40,
        color: Colors.grey.withValues(alpha: 0.15),
      );

  // ── Bio ────────────────────────────────────────────────────────────────────

  Widget _buildBioSection(BuildContext context, String desc) {
    final cs = Theme.of(context).colorScheme;
    final isLong = desc.length > 180;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(title: 'À propos', icon: Icons.person_rounded),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 3)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isLong && !_bioExpanded ? '${desc.substring(0, 180)}…' : desc,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
                if (isLong) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => setState(() => _bioExpanded = !_bioExpanded),
                    child: Text(
                      _bioExpanded ? 'Voir moins' : 'Lire la suite',
                      style: TextStyle(
                        color: BabifixDesign.cyan,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ── Portfolio ──────────────────────────────────────────────────────────────

  Widget _buildPortfolio(BuildContext context, List photos) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: _SectionTitle(title: 'Portfolio', icon: Icons.photo_library_rounded),
        ),
        CarouselSlider(
          options: CarouselOptions(
            height: 200,
            enlargeCenterPage: true,
            enlargeFactor: 0.25,
            viewportFraction: 0.72,
            autoPlay: true,
            autoPlayInterval: const Duration(seconds: 4),
            autoPlayCurve: Curves.easeInOutCubic,
          ),
          items: photos.map((photo) {
            String url = '';
            String caption = '';
            if (photo is Map) {
              url = photo['photo']?.toString() ?? '';
              caption = photo['caption']?.toString() ?? '';
            } else if (photo is String) {
              url = photo;
            }
            return _PortfolioCard(url: url, caption: caption);
          }).toList(),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // ── Services ───────────────────────────────────────────────────────────────

  Widget _buildServices(BuildContext context, List<Map<String, dynamic>> services, int tarif) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(title: 'Services proposés', icon: Icons.home_repair_service_rounded),
          const SizedBox(height: 12),
          ...services.asMap().entries.map((entry) {
            final i = entry.key;
            final s = entry.value;
            final colors = [BabifixDesign.cyan, BabifixDesign.ciBlue, const Color(0xFF10B981), const Color(0xFF8B5CF6)];
            final color = colors[i % colors.length];
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withValues(alpha: 0.25)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3)),
                ],
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.home_repair_service_rounded, color: color, size: 22),
                ),
                title: Text(
                  s['titre'] as String? ?? '',
                  style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface, fontSize: 14),
                ),
                subtitle: s['description'] != null
                    ? Text(s['description'] as String, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)
                    : null,
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatFcfa(s['tarif'] as num? ?? tarif),
                      style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                    Text('/ heure', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 10)),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Reviews ────────────────────────────────────────────────────────────────

  Widget _buildReviews(BuildContext context, List<Map<String, dynamic>> reviews, double note, int nbAvis) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SectionTitle(title: 'Avis clients', icon: Icons.format_quote_rounded),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.star_rounded, size: 14, color: Color(0xFFF59E0B)),
                    const SizedBox(width: 4),
                    Text(
                      note.toStringAsFixed(1),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFFB45309)),
                    ),
                    Text(
                      ' · $nbAvis',
                      style: const TextStyle(color: Color(0xFFB45309), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...reviews.take(5).map((r) => _ReviewCard(review: r, cs: cs)),
        ],
      ),
    );
  }

  // ── Bottom bar ─────────────────────────────────────────────────────────────

  Widget _buildBottomBar(
    BuildContext context, {
    required String name,
    required bool disponible,
    required int tarif,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, -4)),
        ],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  ZegoCallBtn(
                    targetUserID: 'babifix_prestataire_${widget.providerId}',
                    targetUserName: name,
                    reservationRef: 'prestaire_${widget.providerId}',
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: disponible ? _openReservation : null,
                      icon: const Icon(Icons.calendar_month_rounded, size: 20),
                      label: Text(
                        disponible
                            ? (tarif > 0 ? 'Réserver · ${formatFcfa(tarif)}/h' : 'Réserver')
                            : 'Indisponible',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: disponible ? BabifixDesign.cyan : Colors.grey.shade300,
                        foregroundColor: disponible ? BabifixDesign.navy : Colors.grey.shade600,
                        minimumSize: const Size(0, 54),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                ],
              ),
              if (!disponible) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.info_outline_rounded, size: 14, color: Colors.grey.shade500),
                    const SizedBox(width: 6),
                    Text(
                      'Ce prestataire n\'accepte pas de nouvelles missions.',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Loading / Error ────────────────────────────────────────────────────────

  Widget _buildLoading() {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1628),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: BabifixDesign.cyan,
              ),
            ),
            const SizedBox(height: 16),
            const Text('Chargement du profil…', style: TextStyle(color: Colors.white54)),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1628),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 72, color: Colors.white24),
              const SizedBox(height: 20),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 15),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Réessayer'),
                style: FilledButton.styleFrom(
                  backgroundColor: BabifixDesign.cyan,
                  foregroundColor: BabifixDesign.navy,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  List<Color> _premiumColors(String tier) {
    return switch (tier) {
      'gold' => [const Color(0xFFFFD700), const Color(0xFFFF8C00), const Color(0xFFFFA500)],
      'silver' => [const Color(0xFFC0C0C0), const Color(0xFF808080), const Color(0xFFD0D0D0)],
      _ => [const Color(0xFFCD7F32), const Color(0xFF8B4513), const Color(0xFFCD853F)], // bronze
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: BabifixDesign.cyan),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: cs.onSurface,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 17,
              color: cs.onSurface,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ChipBadge extends StatelessWidget {
  const _ChipBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _PremiumBadge extends StatelessWidget {
  const _PremiumBadge({required this.tier, required this.colors});
  final String tier;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final label = switch (tier) {
      'gold' => '★ Premium Or',
      'silver' => '★ Premium Argent',
      _ => '★ Premium',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [colors[0], colors[1]]),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: colors[0].withValues(alpha: 0.4), blurRadius: 8)],
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _VerifiedBadge extends StatelessWidget {
  const _VerifiedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)]),
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: const Color(0xFF3B82F6).withValues(alpha: 0.4), blurRadius: 6)],
      ),
      child: const Icon(Icons.check_rounded, size: 14, color: Colors.white),
    );
  }
}

class _PortfolioCard extends StatelessWidget {
  const _PortfolioCard({required this.url, required this.caption});
  final String url;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            url.startsWith('http')
                ? Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: const Color(0xFF1E2A3A),
                      child: const Icon(Icons.image_not_supported_rounded, color: Colors.white30, size: 40),
                    ),
                  )
                : Container(
                    color: const Color(0xFF1E2A3A),
                    child: const Icon(Icons.photo_rounded, color: Colors.white30, size: 40),
                  ),
            if (caption.isNotEmpty)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 24, 12, 10),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                  child: Text(
                    caption,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review, required this.cs});
  final Map<String, dynamic> review;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final r = review;
    final auteur = (r['auteur'] ?? r['client_name'] ?? 'Client') as String;
    final note = (r['note'] as num?)?.toInt() ?? 0;
    final commentaire = (r['commentaire'] ?? '') as String;
    final date = (r['date'] ?? r['created_at'] ?? '') as String;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: BabifixDesign.cyan.withValues(alpha: 0.12),
                child: Text(
                  auteur.isNotEmpty ? auteur[0].toUpperCase() : 'C',
                  style: TextStyle(color: BabifixDesign.ciBlue, fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(auteur, style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface, fontSize: 14)),
                    if (date.isNotEmpty)
                      Text(date, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
                  ],
                ),
              ),
              // Stars
              Row(
                children: List.generate(
                  5,
                  (i) => Icon(
                    i < note ? Icons.star_rounded : Icons.star_border_rounded,
                    size: 16,
                    color: i < note ? const Color(0xFFF59E0B) : Colors.grey.shade300,
                  ),
                ),
              ),
            ],
          ),
          if (commentaire.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                commentaire,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, height: 1.5),
              ),
            ),
          ],
          // Photos preuve
          if ((r['photo_proof'] as List? ?? []).isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 72,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final photoUrl in (r['photo_proof'] as List))
                    if ((photoUrl as String).isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            photoUrl,
                            width: 72,
                            height: 72,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 72,
                              height: 72,
                              color: const Color(0xFFF1F5F9),
                              child: const Icon(Icons.photo_outlined, color: Color(0xFFCBD5E1)),
                            ),
                          ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Shimmer painter for premium background effect
// ─────────────────────────────────────────────────────────────────────────────

class _ShimmerPainter extends CustomPainter {
  const _ShimmerPainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = RadialGradient(
        center: Alignment(math.cos(t * math.pi * 2) * 0.5, math.sin(t * math.pi * 2) * 0.3 - 0.3),
        radius: 0.8,
        colors: [
          color.withValues(alpha: 0.12),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(_ShimmerPainter old) => old.t != t;
}
