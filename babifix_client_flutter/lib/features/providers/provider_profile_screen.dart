import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:carousel_slider/carousel_slider.dart';

import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../user_store.dart';
import '../../babifix_money.dart';
import '../../models/client_models.dart';
import '../../services/zego_call_service.dart';
import '../booking/booking_flow_screen.dart';

class ProviderProfileScreen extends StatefulWidget {
  const ProviderProfileScreen({
    super.key,
    required this.providerId,

    /// Depuis l’accueil : branche la réservation réelle (API). Les routes GoRouter sans callback = flux démo.
    this.onStartReservation,
  });

  final int providerId;

  /// Retourne `true` si une réservation a été créée (ex. pour basculer sur l’onglet historique).
  final Future<bool> Function(ClientService service)? onStartReservation;

  @override
  State<ProviderProfileScreen> createState() => _ProviderProfileScreenState();
}

class _ProviderProfileScreenState extends State<ProviderProfileScreen> {
  Map<String, dynamic>? _provider;
  List<Map<String, dynamic>> _services = [];
  List<Map<String, dynamic>> _reviews = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final token = await BabifixUserStore.getApiToken();
      final headers = token != null
          ? {'Authorization': 'Bearer $token'}
          : <String, String>{};
      final uri = Uri.parse(
        '${babifixApiBaseUrl()}/api/client/prestataires/${widget.providerId}/',
      );
      final res = await http.get(uri, headers: headers);
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _provider = data;
          _services = (data['services'] as List? ?? [])
              .cast<Map<String, dynamic>>();
          _reviews = (data['avis'] as List? ?? []).cast<Map<String, dynamic>>();
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Prestataire introuvable (${res.statusCode})';
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Impossible de charger le profil. Vérifiez votre connexion.';
        _loading = false;
      });
    }
  }

  ClientService _serviceForBooking() {
    final p = _provider ?? {};
    final first = _services.isNotEmpty ? _services.first : null;
    final titre =
        first?['titre'] as String? ?? (p['metier'] as String? ?? 'Prestation');
    final tarif = (first?['tarif'] as num?)?.toInt() ?? 15000;
    final note = (p['note'] as num?)?.toDouble() ?? 4.5;
    return ClientService(
      title: titre,
      category: '',
      duration: 'Sur devis',
      price: tarif,
      rating: note,
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
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BookingFlowScreen(
          serviceTitle: service.title,
          servicePrice: service.price,
          providerName: p['nom'] as String? ?? '',
          providerPhoto: p['photo_portrait_url'] as String?,
          providerRating: (p['average_rating'] as num?)?.toDouble(),
          providerSpecialite: p['specialite'] as String?,
          providerId: widget.providerId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bg = theme.scaffoldBackgroundColor;
    final card = cs.surface;
    final text = cs.onSurface;
    final sub = cs.onSurfaceVariant;

    if (_loading) {
      return Scaffold(
        backgroundColor: bg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null && _provider == null) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: BabifixDesign.navy,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_rounded, size: 64, color: cs.outline),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: text),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _load();
                },
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
      );
    }

    final p = _provider ?? {};
    final name =
        '${p['prenom'] ?? p['user']?['first_name'] ?? ''} ${p['nom'] ?? p['user']?['last_name'] ?? ''}'
            .trim();
    final note = (p['note'] ?? p['rating'] as num?)?.toDouble() ?? 0.0;
    final nbAvis = (p['nb_avis'] ?? p['rating_count'] ?? 0) as int;
    final nbMissions = p['nb_missions'] as int? ?? 0;
    final tauxReussite = p['taux_reussite'] as int? ?? 0;
    final desc = (p['description'] ?? p['bio'] ?? '') as String;
    final badges =
        (p['badges'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final disponible = (p['disponible'] ?? true) as bool;
    final tarif = (p['tarif_horaire'] as num?)?.toInt() ?? 0;

    return Scaffold(
      backgroundColor: bg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: BabifixDesign.navy,
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                icon: const Icon(Icons.share_rounded),
                tooltip: 'Partager ce profil',
                onPressed: () async {
                  final base = babifixApiBaseUrl();
                  final shareUrl = '$base/prestataire/${widget.providerId}';
                  Share.share(
                    '🔧 Découvrez ce prestataire sur BABIFIX : $name\n$shareUrl',
                    subject: 'Prestataire BABIFIX — $name',
                  );
                },
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [BabifixDesign.navy, const Color(0xFF1D3461)],
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 40),
                        Stack(
                          children: [
                            CircleAvatar(
                              radius: 44,
                              backgroundColor: disponible
                                  ? BabifixDesign.cyan.withValues(alpha: 0.2)
                                  : Colors.grey.withValues(alpha: 0.3),
                              backgroundImage: () {
                                final photo = '${p['photo_url'] ?? ''}'.trim();
                                if (photo.startsWith('http'))
                                  return NetworkImage(photo) as ImageProvider;
                                return null;
                              }(),
                              child: () {
                                final photo = '${p['photo_url'] ?? ''}'.trim();
                                if (photo.startsWith('http')) return null;
                                return Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : 'P',
                                  style: TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.w900,
                                    color: disponible
                                        ? BabifixDesign.cyan
                                        : Colors.grey,
                                  ),
                                );
                              }(),
                            ),
                            if (!disponible)
                              Positioned.fill(
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.black.withValues(alpha: 0.45),
                                  ),
                                  child: const Icon(
                                    Icons.block_rounded,
                                    color: Colors.white70,
                                    size: 30,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          name,
                          style: TextStyle(
                            color: disponible ? Colors.white : Colors.white60,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: disponible
                                ? const Color(
                                    0xFF22C55E,
                                  ).withValues(alpha: 0.85)
                                : Colors.grey.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            disponible ? '● Disponible' : '● Indisponible',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Métier + note
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          p['metier'] as String? ?? '',
                          style: TextStyle(
                            color: sub,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Icon(
                            Icons.star_rounded,
                            color: Colors.amber.shade600,
                            size: 20,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            note.toStringAsFixed(1),
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: text,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '($nbAvis avis)',
                            style: TextStyle(fontSize: 13, color: sub),
                          ),
],
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Portfolio Photos Carrousel
                  if ((p['portfolio_photos'] as List?)?.isNotEmpty ?? false) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Portfolio',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: text,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 10),
                    CarouselSlider(
                      options: CarouselOptions(
                        height: 160,
                        enlargeCenterPage: true,
                        viewportFraction: 0.7,
                        autoPlay: true,
                        autoPlayInterval: const Duration(seconds: 4),
                      ),
                      items: (p['portfolio_photos'] as List).map((photo) {
                        String imageUrl = '';
                        if (photo is Map) {
                          imageUrl = photo['photo']?.toString() ?? '';
                        } else if (photo is String) {
                          imageUrl = photo;
                        }
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.15),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: imageUrl.startsWith('http')
                                ? Image.network(
                                    imageUrl,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: Colors.grey.shade200,
                                      child: const Icon(Icons.broken_image),
                                    ),
                                  )
                                : Container(
                                    color: Colors.grey.shade200,
                                    child: const Icon(Icons.image, size: 40),
                                  ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Description
                  if (desc.isNotEmpty) ...[
                    Text(
                      'À propos',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: text,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      desc,
                      style: TextStyle(color: sub, height: 1.5, fontSize: 14),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Services
                  if (_services.isNotEmpty) ...[
                    Text(
                      'Services proposés',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: text,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final s in _services)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: theme.dividerColor),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.home_repair_service_rounded,
                              color: BabifixDesign.cyan,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                s['titre'] as String? ?? '',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: text,
                                ),
                              ),
                            ),
                            Text(
                              formatFcfa(s['tarif'] as num? ?? 0),
                              style: TextStyle(
                                color: BabifixDesign.cyan,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 20),
                  ],

                  // Avis clients
                  if (_reviews.isNotEmpty) ...[
                    Row(
                      children: [
                        Text(
                          'Avis clients',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: text,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.amber.shade200),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                size: 13,
                                color: Colors.amber,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                note > 0 ? note.toStringAsFixed(1) : '—',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.amber,
                                ),
                              ),
                              Text(
                                ' · $nbAvis avis',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    for (final r in _reviews)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: card,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: theme.dividerColor),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: BabifixDesign.cyan
                                      .withValues(alpha: 0.15),
                                  child: Text(
                                    ((r['auteur'] ?? r['client_name'] ?? 'U')
                                                as String)
                                            .isNotEmpty
                                        ? ((r['auteur'] ?? r['client_name'])
                                                  as String)[0]
                                              .toUpperCase()
                                        : 'U',
                                    style: TextStyle(
                                      color: BabifixDesign.ciBlue,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        (r['auteur'] ?? r['client_name'] ?? '')
                                            as String,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: text,
                                          fontSize: 14,
                                        ),
                                      ),
                                      Text(
                                        (r['date'] ?? r['created_at'] ?? '')
                                            as String,
                                        style: TextStyle(
                                          color: sub,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Étoiles
                                Row(
                                  children: List.generate(
                                    5,
                                    (i) => Icon(
                                      i < (r['note'] as int? ?? 0)
                                          ? Icons.star_rounded
                                          : Icons.star_border_rounded,
                                      size: 15,
                                      color: Colors.amber,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if ((r['commentaire'] as String? ?? '')
                                .isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                r['commentaire'] as String,
                                style: TextStyle(
                                  color: sub,
                                  fontSize: 14,
                                  height: 1.4,
                                ),
                              ),
                            ],
                            // Photos preuve
                            if ((r['photo_proof'] as List? ?? [])
                                .isNotEmpty) ...[
                              const SizedBox(height: 10),
                              SizedBox(
                                height: 70,
                                child: ListView(
                                  scrollDirection: Axis.horizontal,
                                  children: [
                                    for (final photoUrl
                                        in (r['photo_proof'] as List))
                                      if ((photoUrl as String).isNotEmpty)
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          child: Image.network(
                                            photoUrl,
                                            width: 70,
                                            height: 70,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                Container(
                                                  width: 70,
                                                  height: 70,
                                                  color: const Color(
                                                    0xFFF1F5F9,
                                                  ),
                                                  child: const Icon(
                                                    Icons.photo_outlined,
                                                    color: Color(0xFFCBD5E1),
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
                      ),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: ZegoCallBtn(
                      targetUserID: 'babifix_prestataire_${widget.providerId}',
                      targetUserName: name,
                      reservationRef: 'prestaire_${widget.providerId}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Appelez directement sans révéler votre numéro.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: sub, height: 1.35),
              ),
              const SizedBox(height: 10),
              Text(
                'La messagerie avec le prestataire est disponible après une réservation (ou via le message dans le flux « Réserver »).',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: sub, height: 1.35),
              ),
              const SizedBox(height: 10),
              if (!disponible)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 16,
                  ),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.block_rounded,
                        size: 16,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Ce prestataire n\'accepte pas de nouvelles missions pour l\'instant.',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              FilledButton.icon(
                onPressed: disponible ? _openReservation : null,
                icon: const Icon(Icons.calendar_month_rounded),
                label: Text(
                  disponible
                      ? (tarif > 0
                            ? 'Réserver · ${tarif.toString()} FCFA/h'
                            : 'Réserver')
                      : 'Prestataire indisponible',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: disponible
                      ? BabifixDesign.cyan
                      : Colors.grey.shade300,
                  foregroundColor: disponible
                      ? BabifixDesign.navy
                      : Colors.grey.shade600,
                  minimumSize: const Size(double.infinity, 54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.card,
    required this.text,
    required this.sub,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color card;
  final Color text;
  final Color sub;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: [
          Icon(icon, color: BabifixDesign.cyan, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: text,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: sub),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
