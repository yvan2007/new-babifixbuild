/// ProviderProfilePremiumScreen — Refonte premium de la fiche prestataire.
///
/// Sections (de haut en bas, dans un SliverList) :
///  1. Hero collapsing : photo de couverture + parallax + photo ronde
///  2. Identité : nom + spécialité + ville + badges (certifié, premium)
///  3. Status pill animé : "Disponible" / "Occupé" + distance GPS
///  4. Stats compactes : note ⭐ / missions ✅ / années 📅
///  5. Bio (collapse si > 3 lignes)
///  6. Portfolio (galerie scrollable horizontale)
///  7. Services proposés (chips)
///  8. Avis clients (3 derniers + lien)
///  9. Bottom bar fixe : Message · Appel · Réserver
///
/// PAS de tarif horaire — chaque devis est sur mesure.
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../models/client_models.dart';
import '../../services/call_service.dart';
import '../../shared/widgets/babifix_ring_loader.dart';
import '../../user_store.dart';
import '../booking/booking_flow_screen.dart';
import '../chat/chat_room_screen.dart';

class ProviderProfilePremiumScreen extends StatefulWidget {
  const ProviderProfilePremiumScreen({
    super.key,
    required this.providerId,
    this.onStartReservation,
  });

  final int providerId;
  final Future<bool> Function(ClientService service)? onStartReservation;

  @override
  State<ProviderProfilePremiumScreen> createState() =>
      _ProviderProfilePremiumScreenState();
}

class _ProviderProfilePremiumScreenState
    extends State<ProviderProfilePremiumScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _p;
  List<Map<String, dynamic>> _reviews = [];
  bool _loading = true;
  String? _error;
  bool _bioExpanded = false;
  final ScrollController _scroll = ScrollController();
  double _scrollOffset = 0;
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _scroll.addListener(() {
      setState(() => _scrollOffset = _scroll.offset);
    });
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = await BabifixUserStore.getApiToken();
      final headers = <String, String>{
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };
      final r = await http.get(
        Uri.parse(
            '${babifixApiBaseUrl()}/api/client/prestataires/${widget.providerId}/'),
        headers: headers,
      ).timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) {
        _error = 'HTTP ${r.statusCode}';
      } else {
        _p = jsonDecode(r.body) as Map<String, dynamic>;
        // Charger les avis si endpoint disponible
        try {
          final rr = await http.get(
            Uri.parse(
                '${babifixApiBaseUrl()}/api/client/prestataires/${widget.providerId}/reviews'),
            headers: headers,
          ).timeout(const Duration(seconds: 6));
          if (rr.statusCode == 200) {
            final j = jsonDecode(rr.body);
            _reviews = ((j['reviews'] ?? j['items'] ?? []) as List)
                .whereType<Map>()
                .map((m) => Map<String, dynamic>.from(m))
                .toList();
          }
        } catch (_) {}
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      body: _loading
          ? const Center(child: BabifixRingLoader.dark(size: 90))
          : _error != null
              ? _errorView()
              : _content(),
      bottomNavigationBar: _p == null ? null : _bottomBar(),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 56, color: BabifixDesign.error),
              const SizedBox(height: 12),
              Text(_error ?? '', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(
                  onPressed: _load, child: const Text('Réessayer')),
            ],
          ),
        ),
      );

  Widget _content() {
    final p = _p!;
    final name = ('${p['prenom'] ?? ''} ${p['nom'] ?? ''}').trim();
    final metier =
        (p['metier'] ?? p['specialite'] ?? p['category_nom'] ?? '') as String;
    final ville = (p['ville'] ?? '') as String;
    final note = (p['average_rating'] ?? p['note'] ?? 0.0) as num? ?? 0.0;
    final nbAvis = (p['rating_count'] ?? p['nb_avis'] ?? 0) as int? ?? 0;
    final nbMissions = (p['nb_missions'] ?? 0) as int? ?? 0;
    final yearsExp = (p['years_experience'] ?? 0) as int? ?? 0;
    final desc = (p['description'] ?? p['bio'] ?? '') as String;
    final disponible = (p['disponible'] ?? true) as bool;
    final isCertified = (p['is_certified'] ?? false) as bool;
    final isPremium = (p['is_premium'] ?? false) as bool;
    final photoUrl = (p['photo_portrait_url'] ?? p['photo_url'] ?? '') as String;
    final portfolio =
        (p['portfolio_photos'] as List? ?? []).whereType<String>().toList();
    final distanceKm = (p['distance_km'] as num?)?.toDouble();
    final sameCity = (p['same_city'] ?? false) as bool;

    return CustomScrollView(
      controller: _scroll,
      slivers: [
        _hero(name, metier, photoUrl, isCertified, isPremium),
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _identity(name, metier, ville, note, nbAvis),
              const SizedBox(height: 14),
              _statusBar(disponible, distanceKm, sameCity),
              const SizedBox(height: 18),
              _stats(note, nbAvis, nbMissions, yearsExp),
              if (desc.isNotEmpty) ...[
                const SizedBox(height: 22),
                _bio(desc),
              ],
              if (portfolio.isNotEmpty) ...[
                const SizedBox(height: 22),
                _portfolio(portfolio),
              ],
              if (_reviews.isNotEmpty) ...[
                const SizedBox(height: 22),
                _reviewsSection(note, nbAvis),
              ],
              const SizedBox(height: 22),
              _trustBadges(isCertified, isPremium, yearsExp),
              const SizedBox(height: 120),
            ],
          ),
        ),
      ],
    );
  }

  // ── Hero collapsible ─────────────────────────────────────────────
  Widget _hero(String name, String metier, String photoUrl,
      bool isCertified, bool isPremium) {
    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      backgroundColor: BabifixDesign.navy,
      foregroundColor: Colors.white,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.25),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.arrow_back, color: Colors.white, size: 18),
        ),
        onPressed: () => Navigator.of(context).pop(),
      ),
      actions: [
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.25),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.ios_share, color: Colors.white, size: 16),
          ),
          onPressed: () => Share.share(
            '🔧 Découvrez $name sur BABIFIX\n${babifixApiBaseUrl()}/prestataire/${widget.providerId}',
          ),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Fond avec dégradé navy
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF0B1B34),
                    Color(0xFF1E3A8A),
                    Color(0xFF0E2A56),
                  ],
                ),
              ),
            ),
            // Halos décoratifs (parallax léger via scroll)
            Positioned(
              top: -50 + _scrollOffset * 0.3,
              right: -40,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      BabifixDesign.cyan.withValues(alpha: 0.25),
                      BabifixDesign.cyan.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -60,
              left: -60 + _scrollOffset * 0.2,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF22C55E).withValues(alpha: 0.18),
                      const Color(0xFF22C55E).withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            // Photo de profil centrée
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Anneau lumineux + photo
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 138,
                        height: 138,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              BabifixDesign.cyan,
                              const Color(0xFFE87722),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        width: 128,
                        height: 128,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF0B1B34),
                        ),
                        padding: const EdgeInsets.all(4),
                        child: ClipOval(
                          child: photoUrl.isNotEmpty &&
                                  photoUrl.startsWith('http')
                              ? Image.network(
                                  photoUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      _placeholderAvatar(name),
                                )
                              : _placeholderAvatar(name),
                        ),
                      ),
                      // Badge certification
                      if (isCertified)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: BabifixDesign.ciGreen,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: const Color(0xFF0B1B34), width: 3),
                            ),
                            child: const Icon(Icons.verified,
                                color: Colors.white, size: 18),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Premium badge
                  if (isPremium)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFF59E0B), Color(0xFFE87722)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFE87722)
                                .withValues(alpha: 0.4),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.workspace_premium,
                              size: 14, color: Colors.white),
                          SizedBox(width: 4),
                          Text(
                            'PREMIUM',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 1.5,
                            ),
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

  Widget _placeholderAvatar(String name) {
    return Container(
      color: BabifixDesign.cyan.withValues(alpha: 0.2),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(
          fontSize: 48,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
      ),
    );
  }

  // ── Identité ─────────────────────────────────────────────────────
  Widget _identity(String name, String metier, String ville, num note,
      int nbAvis) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            name.isEmpty ? 'Prestataire' : name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0B1B34),
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            metier,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (ville.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.place,
                    size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 3),
                Text(
                  ville,
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade600),
                ),
                if (note > 0) ...[
                  const SizedBox(width: 10),
                  Icon(Icons.star_rounded,
                      size: 14, color: Colors.amber.shade600),
                  const SizedBox(width: 2),
                  Text(
                    '${(note as num).toStringAsFixed(1)} ($nbAvis avis)',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0B1B34),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Status pill animé ────────────────────────────────────────────
  Widget _statusBar(bool disponible, double? distanceKm, bool sameCity) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, child) {
              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: (disponible
                          ? BabifixDesign.ciGreen
                          : Colors.orange.shade700)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: (disponible
                            ? BabifixDesign.ciGreen
                            : Colors.orange.shade700)
                        .withValues(alpha: 0.30),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: disponible
                            ? BabifixDesign.ciGreen
                            : Colors.orange.shade700,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (disponible
                                    ? BabifixDesign.ciGreen
                                    : Colors.orange.shade700)
                                .withValues(
                                    alpha: 0.6 + 0.4 * _pulseCtrl.value),
                            blurRadius: 8 + 4 * _pulseCtrl.value,
                            spreadRadius: 1 + _pulseCtrl.value,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      disponible ? 'Disponible' : 'Occupé',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: disponible
                            ? BabifixDesign.ciGreen
                            : Colors.orange.shade700,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const Spacer(),
          if (distanceKm != null)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: BabifixDesign.cyan.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.near_me_outlined,
                      size: 12, color: BabifixDesign.cyan),
                  const SizedBox(width: 4),
                  Text(
                    distanceKm < 1
                        ? '${(distanceKm * 1000).round()} m'
                        : '${distanceKm.toStringAsFixed(1)} km',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: BabifixDesign.cyan,
                    ),
                  ),
                  if (sameCity) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.location_city,
                        size: 12, color: BabifixDesign.cyan),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Stats compactes ──────────────────────────────────────────────
  Widget _stats(num note, int nbAvis, int nbMissions, int yearsExp) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          _statCell(
            value: note > 0 ? (note as num).toStringAsFixed(1) : '—',
            label: '$nbAvis avis',
            icon: Icons.star_rounded,
            color: const Color(0xFFF59E0B),
          ),
          _statDivider(),
          _statCell(
            value: nbMissions > 0 ? '$nbMissions' : '—',
            label: 'missions',
            icon: Icons.check_circle_rounded,
            color: BabifixDesign.cyan,
          ),
          _statDivider(),
          _statCell(
            value: yearsExp > 0 ? '$yearsExp an${yearsExp > 1 ? 's' : ''}' : '—',
            label: 'expérience',
            icon: Icons.workspace_premium_rounded,
            color: const Color(0xFF8B5CF6),
          ),
        ],
      ),
    );
  }

  Widget _statCell({
    required String value,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.13),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0B1B34),
            ),
          ),
          Text(
            label,
            style: TextStyle(
                fontSize: 10.5,
                color: Colors.grey.shade600,
                letterSpacing: 0.3),
          ),
        ],
      ),
    );
  }

  Widget _statDivider() => Container(
        width: 1,
        height: 50,
        color: Colors.grey.withValues(alpha: 0.12),
      );

  // ── Bio ──────────────────────────────────────────────────────────
  Widget _bio(String desc) {
    final showFull = _bioExpanded || desc.length < 220;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline,
                    size: 16, color: BabifixDesign.cyan),
                const SizedBox(width: 6),
                Text(
                  'À propos',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: BabifixDesign.cyan,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              child: Text(
                showFull
                    ? desc
                    : '${desc.substring(0, math.min(220, desc.length))}…',
                style: TextStyle(
                    fontSize: 14, color: Colors.grey.shade800, height: 1.45),
              ),
            ),
            if (desc.length >= 220)
              TextButton(
                onPressed: () =>
                    setState(() => _bioExpanded = !_bioExpanded),
                child: Text(_bioExpanded ? 'Réduire' : 'Lire plus'),
              ),
          ],
        ),
      ),
    );
  }

  // ── Portfolio ────────────────────────────────────────────────────
  Widget _portfolio(List<String> photos) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Row(
            children: [
              Icon(Icons.photo_library_outlined,
                  size: 18, color: BabifixDesign.cyan),
              const SizedBox(width: 6),
              const Text(
                'Portfolio',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0B1B34)),
              ),
              const Spacer(),
              Text(
                '${photos.length} photos',
                style:
                    TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 140,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: photos.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final u = photos[i];
              return GestureDetector(
                onTap: () => _openPhotoFullscreen(u),
                child: Hero(
                  tag: 'portfolio_${widget.providerId}_$i',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: u.startsWith('http')
                        ? Image.network(
                            u,
                            width: 140,
                            height: 140,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _photoBroken(),
                          )
                        : _photoBroken(),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _photoBroken() => Container(
        width: 140,
        height: 140,
        color: Colors.grey.shade200,
        child: const Icon(Icons.broken_image_outlined),
      );

  void _openPhotoFullscreen(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            InteractiveViewer(
              child: Image.network(url, fit: BoxFit.contain),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Avis clients ─────────────────────────────────────────────────
  Widget _reviewsSection(num note, int nbAvis) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.reviews_outlined,
                  size: 18, color: BabifixDesign.cyan),
              const SizedBox(width: 6),
              const Text(
                'Avis clients',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0B1B34)),
              ),
              const Spacer(),
              Row(
                children: [
                  Icon(Icons.star_rounded,
                      size: 16, color: Colors.amber.shade600),
                  const SizedBox(width: 2),
                  Text(
                    '${(note as num).toStringAsFixed(1)} · $nbAvis',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          ..._reviews.take(3).map(_reviewCard),
        ],
      ),
    );
  }

  Widget _reviewCard(Map<String, dynamic> r) {
    final author = (r['author'] ?? r['client_name'] ?? 'Client') as String;
    final rate = (r['rate'] ?? r['note'] ?? 0).toString();
    final text = (r['text'] ?? r['comment'] ?? '') as String;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: BabifixDesign.cyan.withValues(alpha: 0.18),
                child: Text(
                  author.isNotEmpty ? author[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: BabifixDesign.cyan,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  author,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0B1B34),
                  ),
                ),
              ),
              Row(
                children: List.generate(5, (i) {
                  final filled = i < (double.tryParse(rate) ?? 0);
                  return Icon(
                    filled ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 14,
                    color: Colors.amber.shade600,
                  );
                }),
              ),
            ],
          ),
          if (text.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(text,
                style: TextStyle(
                    fontSize: 13, color: Colors.grey.shade800, height: 1.4)),
          ],
        ],
      ),
    );
  }

  // ── Trust badges ─────────────────────────────────────────────────
  Widget _trustBadges(bool isCertified, bool isPremium, int yearsExp) {
    final items = <_Trust>[
      if (isCertified)
        _Trust(Icons.verified, 'Identité vérifiée',
            'Pièce d\'identité validée par BABIFIX'),
      _Trust(Icons.lock, 'Paiement sécurisé',
          'Votre argent est bloqué tant que le travail n\'est pas confirmé'),
      _Trust(Icons.support_agent, 'Support 7j/7',
          'Une équipe BABIFIX répond aux litiges'),
      if (yearsExp >= 3)
        _Trust(Icons.workspace_premium, 'Expérimenté',
            '$yearsExp ans dans le métier'),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.security, size: 18, color: BabifixDesign.ciGreen),
              const SizedBox(width: 6),
              const Text(
                'Garanties BABIFIX',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0B1B34)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...items.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: BabifixDesign.ciGreen.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child:
                          Icon(t.icon, size: 18, color: BabifixDesign.ciGreen),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.title,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0B1B34)),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            t.desc,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  // ── Bottom action bar ────────────────────────────────────────────
  Widget _bottomBar() {
    final p = _p!;
    final name = ('${p['prenom'] ?? ''} ${p['nom'] ?? ''}').trim();
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 14,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            _circleAction(
              icon: Icons.chat_bubble_outline,
              color: BabifixDesign.cyan,
              onTap: () {
                final uid = p['user_id'] as int?;
                if (uid == null) return;
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ChatRoomScreen(
                    name: name,
                    peerUserId: uid,
                    apiBase: babifixApiBaseUrl(),
                  ),
                ));
              },
            ),
            const SizedBox(width: 8),
            _circleAction(
              icon: Icons.call_outlined,
              color: BabifixDesign.ciGreen,
              onTap: () {
                final uid = p['user_id'] as int?;
                if (uid == null) return;
                // Pas de réservation encore créée, on initie depuis le profil
                CallService.startOutgoing(
                  context: context,
                  reservationReference: 'prestataire_${widget.providerId}',
                  targetName: name,
                );
              },
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => BookingFlowScreen(
                        serviceTitle:
                            (p['specialite'] ?? p['category_nom'] ?? 'Service')
                                .toString(),
                        servicePrice: 0, // devis sur mesure, pas de prix fixe
                        providerId: widget.providerId,
                        providerName: name,
                        providerSpecialite:
                            (p['specialite'] ?? '').toString(),
                        providerRating:
                            (p['average_rating'] as num?)?.toDouble() ?? 0,
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: BabifixDesign.cyan,
                  foregroundColor: const Color(0xFF0B1B34),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.calendar_month_rounded, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Réserver',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleAction({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(50),
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.10),
          border: Border.all(color: color.withValues(alpha: 0.30)),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }
}

class _Trust {
  final IconData icon;
  final String title;
  final String desc;
  _Trust(this.icon, this.title, this.desc);
}
