import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../json_utils.dart';
import '../../shared/app_palette_mode.dart';
import '../../shared/auth_utils.dart';
import '../auth/registration_screen.dart';
import '../availability/availability_screen.dart';
import '../dashboard/floating_nav_bar.dart';
import 'edit_profile_screen.dart' show EditProfilePrestataireScreen;

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.onBack,
    required this.paletteMode,
    required this.onPaletteChanged,
    required this.onLogout,
    required this.onNavigate,
    this.unreadChat,
    this.onMessagesOpened,
  });

  final VoidCallback onBack;
  final AppPaletteMode paletteMode;
  final ValueChanged<AppPaletteMode> onPaletteChanged;
  final VoidCallback onLogout;
  final ValueChanged<String> onNavigate;
  final ValueNotifier<int>? unreadChat;
  final VoidCallback? onMessagesOpened;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const _logoAsset = 'assets/images/babifix-logo.png';

  bool _loading = true;
  Map<String, dynamic> _prov = {};
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _avis = [];
  String _contactAdminEmail = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var contact = '';
    try {
      final vr = await http.get(Uri.parse('${babifixApiBaseUrl()}/api/public/vitrine/'));
      if (vr.statusCode == 200) {
        final vd = jsonDecode(vr.body) as Map<String, dynamic>;
        contact = '${vd['contact_admin_email'] ?? ''}'.trim();
      }
    } catch (_) {}
    final t = await readStoredApiToken();
    if (t == null || t.isEmpty) {
      if (mounted) {
        setState(() {
          _contactAdminEmail = contact;
          _loading = false;
        });
      }
      return;
    }
    try {
      final res = await http.get(
        Uri.parse('${babifixApiBaseUrl()}/api/prestataire/me'),
        headers: {'Authorization': 'Bearer $t'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        // Charger les avis reçus
        List<Map<String, dynamic>> avisList = [];
        try {
          final avisRes = await http.get(
            Uri.parse('${babifixApiBaseUrl()}/api/prestataire/ratings/'),
            headers: {'Authorization': 'Bearer $t'},
          );
          if (avisRes.statusCode == 200) {
            final avisData = jsonDecode(avisRes.body);
            final raw = avisData is List ? avisData : (avisData['results'] as List? ?? []);
            avisList = raw.cast<Map<String, dynamic>>();
          }
        } catch (_) {}
        if (mounted) {
          setState(() {
            _contactAdminEmail = contact;
            _prov = data['provider'] as Map<String, dynamic>? ?? {};
            _stats = data['stats'] as Map<String, dynamic>? ?? {};
            _avis = avisList;
            _loading = false;
          });
        }
        return;
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _contactAdminEmail = contact;
        _loading = false;
      });
    }
  }

  Future<void> _openContactAdmin() async {
    final e = _contactAdminEmail.trim();
    if (e.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email admin non configure (parametres site).')),
        );
      }
      return;
    }
    final uri = Uri(scheme: 'mailto', path: e, queryParameters: {'subject': 'BABIFIX \u2014 Support prestataire'});
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _handleNavSelect(int index) {
    if (index == 0) {
      widget.onNavigate('dashboard');
    } else if (index == 1) {
      widget.onNavigate('requests');
    } else if (index == 2) {
      widget.onNavigate('earnings');
    } else if (index == 3) {
      widget.onMessagesOpened?.call();
      widget.onNavigate('messages');
    }
  }

  Future<void> _openEditRegistration() async {
    final approved = '${_prov['statut'] ?? ''}' == 'Valide';
    if (!approved) return;
    final token = await readStoredApiToken();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => EditProfilePrestataireScreen(
          apiBase: babifixApiBaseUrl(),
          authToken: token,
        ),
      ),
    );
    if (mounted) _load();
  }

  void _showHelpSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.92,
        minChildSize: 0.35,
        builder: (_, scrollCtrl) => ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            const Text(
              'Aide BABIFIX',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
            ),
            const SizedBox(height: 6),
            const Text('Espace prestataire', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
            const SizedBox(height: 16),
            _PrestHelpRow(
              icon: Icons.calendar_month,
              title: 'Exigences & r\u00e9servations',
              body: 'Consultez vos demandes, confirmez ou refusez selon vos disponibilit\u00e9s.',
            ),
            _PrestHelpRow(
              icon: Icons.account_balance_wallet,
              title: 'Gains',
              body: 'Suivez vos paiements et l\u2019historique des missions r\u00e9mun\u00e9r\u00e9es.',
            ),
            _PrestHelpRow(
              icon: Icons.chat_bubble_outline,
              title: 'Messages',
              body: '\u00c9changez avec les clients depuis l\u2019onglet Messages ou l\u2019ic\u00f4ne en haut \u00e0 droite.',
            ),
            _PrestHelpRow(
              icon: Icons.palette_outlined,
              title: 'Th\u00e8me',
              body: 'Profil \u2192 Param\u00e8tres : blanc ou bleu BABIFIX.',
            ),
          ],
        ),
      ),
    );
  }

  void _openSettings() {
    final isLight = widget.paletteMode == AppPaletteMode.light;
    final fg = isLight ? const Color(0xFF0F172A) : Colors.white;
    final sub = isLight ? const Color(0xFF64748B) : const Color(0xFF9CA3AF);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Param\u00e8tres', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: fg)),
            const SizedBox(height: 6),
            Text('Th\u00e8me d\u2019affichage', style: TextStyle(color: sub, fontSize: 14)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Blanc (par d\u00e9faut)'),
                  selected: widget.paletteMode == AppPaletteMode.light,
                  onSelected: (_) => widget.onPaletteChanged(AppPaletteMode.light),
                ),
                ChoiceChip(
                  label: const Text('Bleu BABIFIX'),
                  selected: widget.paletteMode == AppPaletteMode.blue,
                  onSelected: (_) => widget.onPaletteChanged(AppPaletteMode.blue),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(bool isLight) {
    final width = MediaQuery.sizeOf(context).width;
    final titleSize = width < 360 ? 28.0 : width < 430 ? 33.0 : 38.0;
    final textPrimary = isLight ? const Color(0xFF0F172A) : Colors.white;
    final iconMuted = isLight ? const Color(0xFF334155) : Colors.white70;
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x1AFFFFFF))),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  image: DecorationImage(image: AssetImage(_logoAsset), fit: BoxFit.cover),
                  boxShadow: [
                    BoxShadow(color: Color(0x5509AEEF), blurRadius: 12, offset: Offset(0, 4)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Profil',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: titleSize,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    color: textPrimary,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Aide',
                onPressed: _showHelpSheet,
                icon: Icon(Icons.help_outline_rounded, size: 24, color: iconMuted),
              ),
              if (_contactAdminEmail.isNotEmpty)
                IconButton(
                  tooltip: 'Contacter administrateur',
                  onPressed: _openContactAdmin,
                  icon: Icon(Icons.support_agent_rounded, size: 24, color: iconMuted),
                ),
              IconButton(
                tooltip: 'Notifications',
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Aucune nouvelle notification pour l\u2019instant.')),
                  );
                },
                icon: Icon(Icons.notifications_outlined, size: 24, color: iconMuted),
              ),
              IconButton(
                tooltip: 'Messages',
                onPressed: () {
                  widget.onMessagesOpened?.call();
                  widget.onNavigate('messages');
                },
                icon: widget.unreadChat == null
                    ? Icon(Icons.chat_bubble_outline_rounded, size: 24, color: iconMuted)
                    : ValueListenableBuilder<int>(
                        valueListenable: widget.unreadChat!,
                        builder: (context, count, _) {
                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Icon(Icons.chat_bubble_outline_rounded, size: 24, color: iconMuted),
                              if (count > 0)
                                Positioned(
                                  right: -4,
                                  top: -4,
                                  child: Container(
                                    padding: EdgeInsets.symmetric(horizontal: count > 9 ? 5 : 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFF3B30),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: Colors.white, width: 1),
                                    ),
                                    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                                    child: Text(
                                      count > 99 ? '99+' : '$count',
                                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLight = widget.paletteMode == AppPaletteMode.light;
    final textPrimary = isLight ? const Color(0xFF0F172A) : Colors.white;
    final textSecondary = isLight ? const Color(0xFF475569) : const Color(0xFF9CA3AF);
    final cardBg = isLight ? const Color(0xFFF8FAFC) : const Color(0xFF1A1F28);

    final nom = '${_prov['nom'] ?? ''}'.trim();
    final spec = '${_prov['specialite'] ?? ''}';
    final ville = '${_prov['ville'] ?? ''}';
    final bio = '${_prov['bio'] ?? ''}';
    final cat = '${_prov['category_nom'] ?? ''}';
    final email = '${_prov['email'] ?? ''}'.trim();
    final phone = '${_prov['telephone'] ?? _prov['phone'] ?? ''}'.trim();
    final tarif = _prov['tarif_horaire'];
    final tarifStr = tarif != null ? '${(tarif as num).toStringAsFixed(0)} FCFA/h' : '\u2014';
    final note = _prov['average_rating'];
    final nnote = note != null ? (note as num).toStringAsFixed(1) : '\u2014';
    final rc = jsonInt(_prov['rating_count']);
    final approved = '${_prov['statut'] ?? ''}' == 'Valide';
    final photo = '${_prov['photo_url'] ?? ''}'.trim();
    ImageProvider? avatarProvider;
    if (photo.startsWith('http://') || photo.startsWith('https://')) {
      avatarProvider = NetworkImage(photo);
    } else if (photo.isNotEmpty) {
      final f = File(photo);
      if (f.existsSync()) avatarProvider = FileImage(f);
    }

    final gradient = isLight ? BabifixDesign.pageGradientLight : BabifixDesign.pageGradientDark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) widget.onBack();
      },
      child: Scaffold(
        extendBody: true,
        body: Container(
          decoration: BoxDecoration(gradient: gradient),
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF4CC9F0)))
              : Column(
                  children: [
                    _buildTopBar(isLight),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _load,
                        color: const Color(0xFF4CC9F0),
                        backgroundColor: isLight ? Colors.white : const Color(0xFF1A1F28),
                        child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          // ── Hero card premium ───────────────────────────
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(22),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: isLight
                                    ? const [Color(0xFFE0F2FE), Color(0xFFF0F9FF)]
                                    : const [Color(0xFF0C1A2E), Color(0xFF1A2A42)],
                              ),
                              border: Border.all(
                                color: isLight ? const Color(0xFF7DD3FC) : const Color(0x334CC9F0),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF4CC9F0).withValues(alpha: isLight ? 0.12 : 0.08),
                                  blurRadius: 20, offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Stack(
                                      children: [
                                        Container(
                                          width: 64, height: 64,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            gradient: const LinearGradient(colors: [Color(0xFF4CC9F0), Color(0xFF0284C7)]),
                                            boxShadow: [BoxShadow(color: const Color(0xFF4CC9F0).withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4))],
                                          ),
                                          child: avatarProvider != null
                                              ? ClipOval(child: Image(image: avatarProvider, fit: BoxFit.cover, width: 64, height: 64))
                                              : Center(child: Text(nom.isNotEmpty ? nom[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900))),
                                        ),
                                        if (_prov['disponible'] == true)
                                          Positioned(
                                            bottom: 2, right: 2,
                                            child: Container(
                                              width: 14, height: 14,
                                              decoration: BoxDecoration(color: const Color(0xFF10B981), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(nom.isEmpty ? 'Prestataire' : nom,
                                              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: textPrimary)),
                                          const SizedBox(height: 3),
                                          if (spec.isNotEmpty)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(color: const Color(0xFF4CC9F0).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                                              child: Text(spec, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF0284C7))),
                                            ),
                                          const SizedBox(height: 4),
                                          if (email.isNotEmpty)
                                            Text(email, style: TextStyle(color: textSecondary, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                                          if (ville.isNotEmpty)
                                            Row(children: [
                                              Icon(Icons.location_on_rounded, size: 11, color: textSecondary),
                                              const SizedBox(width: 2),
                                              Text(ville, style: TextStyle(color: textSecondary, fontSize: 12)),
                                            ]),
                                        ],
                                      ),
                                    ),
                                    if (approved)
                                      GestureDetector(
                                        onTap: _openEditRegistration,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(colors: [Color(0xFF4CC9F0), Color(0xFF0284C7)]),
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: const Text('Modifier', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                // ── Stat chips ──────────────────────────────
                                Row(
                                  children: [
                                    _StatChip(label: 'Note', value: nnote, icon: Icons.star_rounded, color: const Color(0xFFF59E0B), isLight: isLight),
                                    const SizedBox(width: 8),
                                    _StatChip(label: 'Avis', value: '$rc', icon: Icons.chat_bubble_rounded, color: const Color(0xFF4CC9F0), isLight: isLight),
                                    const SizedBox(width: 8),
                                    _StatChip(label: 'Missions', value: '${jsonInt(_stats['reservations_total'])}', icon: Icons.task_alt_rounded, color: const Color(0xFF10B981), isLight: isLight),
                                    const SizedBox(width: 8),
                                    _StatChip(label: 'Tarif', value: tarifStr, icon: Icons.payments_rounded, color: const Color(0xFFF97316), isLight: isLight),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (approved)
                            _PrestProfileActionTile(
                              icon: Icons.person_outline_rounded,
                              title: 'Modifier le profil',
                              subtitle: 'Photo, sp\u00e9cialit\u00e9, coordonn\u00e9es',
                              isLight: isLight,
                              onTap: _openEditRegistration,
                            ),
                          if (approved) const SizedBox(height: 10),
                          if (approved)
                            _PrestProfileActionTile(
                              icon: Icons.schedule_rounded,
                              title: 'Mes disponibilités',
                              subtitle: 'Créneaux hebdomadaires & congés',
                              isLight: isLight,
                              onTap: () => Navigator.of(context).push<void>(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      const AvailabilityScreen(),
                                ),
                              ),
                            ),
                          if (approved) const SizedBox(height: 10),
                          _PrestProfileActionTile(
                            icon: Icons.chat_bubble_outline_rounded,
                            title: 'Messages',
                            subtitle: '\u00c9changer avec vos clients',
                            isLight: isLight,
                            onTap: () {
                              widget.onMessagesOpened?.call();
                              widget.onNavigate('messages');
                            },
                          ),
                          const SizedBox(height: 10),
                          _PrestProfileActionTile(
                            icon: Icons.support_agent_rounded,
                            title: 'Contacter l\u2019administrateur',
                            subtitle: _contactAdminEmail.isEmpty ? 'Email support (serveur)' : _contactAdminEmail,
                            isLight: isLight,
                            onTap: _openContactAdmin,
                          ),
                          const SizedBox(height: 10),
                          _PrestProfileActionTile(
                            icon: Icons.help_center_outlined,
                            title: 'FAQ & aide',
                            subtitle: 'Guide missions, gains, avis',
                            isLight: isLight,
                            onTap: _showHelpSheet,
                          ),
                          const SizedBox(height: 10),
                          _PrestProfileActionTile(
                            icon: Icons.palette_outlined,
                            title: 'Param\u00e8tres',
                            subtitle: 'Th\u00e8me d\u2019affichage',
                            isLight: isLight,
                            onTap: _openSettings,
                          ),
                          const SizedBox(height: 10),
                          _PrestProfileActionTile(
                            icon: Icons.info_outline_rounded,
                            title: '\u00c0 propos de BABIFIX',
                            subtitle: 'Version, mentions et support',
                            isLight: isLight,
                            onTap: () {
                              showAboutDialog(
                                context: context,
                                applicationName: 'BABIFIX Prestataire',
                                applicationVersion: '1.0.0',
                                applicationIcon: const CircleAvatar(
                                  backgroundImage: AssetImage(_logoAsset),
                                ),
                                children: const [
                                  Text('Application prestataire BABIFIX \u2014 missions, gains et messagerie.'),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 10),
                          if (bio.isNotEmpty || ville.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(14)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Fiche pro', style: TextStyle(fontWeight: FontWeight.w700, color: textPrimary)),
                                  if (bio.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(bio, style: TextStyle(color: textSecondary, height: 1.35)),
                                  ],
                                  if (ville.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text('Ville : $ville', style: TextStyle(color: textSecondary)),
                                  ],
                                  const SizedBox(height: 6),
                                  Text(
                                    'Disponibilit\u00e9 : ${_prov['disponible'] == true ? 'Disponible' : 'Indisponible'}',
                                    style: TextStyle(color: textSecondary, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          if (bio.isNotEmpty || ville.isNotEmpty) const SizedBox(height: 10),
                          // ── Section avis clients ──────────────────────────
                          if (_avis.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.star_rounded, color: Colors.amber, size: 18),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Avis reçus (${_avis.length})',
                                        style: TextStyle(fontWeight: FontWeight.w700, color: textPrimary, fontSize: 15),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  for (final r in _avis.take(5)) ...[
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      margin: const EdgeInsets.only(bottom: 8),
                                      decoration: BoxDecoration(
                                        color: isLight ? Colors.white : const Color(0xFF242B38),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: isLight ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              CircleAvatar(
                                                radius: 14,
                                                backgroundColor: const Color(0xFF4CC9F0).withValues(alpha: 0.15),
                                                child: Text(
                                                  ((r['client_name'] ?? r['auteur'] ?? 'C') as String)
                                                      .isNotEmpty
                                                      ? ((r['client_name'] ?? r['auteur']) as String)[0].toUpperCase()
                                                      : 'C',
                                                  style: TextStyle(
                                                    color: const Color(0xFF4CC9F0),
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  (r['client_name'] ?? r['auteur'] ?? 'Client') as String,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    color: textPrimary,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ),
                                              Row(
                                                children: List.generate(5, (i) => Icon(
                                                  i < (r['note'] as int? ?? 0)
                                                      ? Icons.star_rounded
                                                      : Icons.star_border_rounded,
                                                  size: 13,
                                                  color: Colors.amber,
                                                )),
                                              ),
                                            ],
                                          ),
                                          if ((r['commentaire'] as String? ?? '').isNotEmpty) ...[
                                            const SizedBox(height: 6),
                                            Text(
                                              r['commentaire'] as String,
                                              style: TextStyle(color: textSecondary, fontSize: 13, height: 1.4),
                                            ),
                                          ],
                                          // Photos preuve
                                          if ((r['photo_proof'] as List? ?? []).isNotEmpty) ...[
                                            const SizedBox(height: 8),
                                            SizedBox(
                                              height: 60,
                                              child: ListView(
                                                scrollDirection: Axis.horizontal,
                                                children: [
                                                  for (final ph in (r['photo_proof'] as List))
                                                    if ((ph as String).startsWith('http'))
                                                      Container(
                                                        width: 60,
                                                        height: 60,
                                                        margin: const EdgeInsets.only(right: 6),
                                                        decoration: BoxDecoration(
                                                          borderRadius: BorderRadius.circular(8),
                                                          image: DecorationImage(
                                                            image: NetworkImage(ph),
                                                            fit: BoxFit.cover,
                                                          ),
                                                        ),
                                                      ),
                                                ],
                                              ),
                                            ),
                                          ],
                                          const SizedBox(height: 4),
                                          Text(
                                            (r['created_at'] ?? r['date'] ?? '') as String,
                                            style: TextStyle(color: textSecondary, fontSize: 11),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          _PrestProfileActionTile(
                            icon: Icons.logout_rounded,
                            title: 'D\u00e9connexion',
                            subtitle: 'Quitter ce compte sur cet appareil',
                            isLight: isLight,
                            onTap: widget.onLogout,
                          ),
                        ],
                      ),
                      ), // RefreshIndicator
                    ),
                  ],
                ),
        ),
        bottomNavigationBar: PrestataireFloatingNavBar(
          selectedIndex: 4,
          isLight: isLight,
          unreadChat: widget.unreadChat,
          onMessagesOpened: widget.onMessagesOpened,
          onSelect: _handleNavSelect,
        ),
      ),
    );
  }
}

/// Tuile menu profil \u2014 m\u00eame logique visuelle que l\u2019app client.
class _PrestProfileActionTile extends StatelessWidget {
  const _PrestProfileActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.isLight,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isLight
                ? const [Color(0xFFF8FAFC), Color(0xFFF1F5F9)]
                : const [Color(0xFF1A2234), Color(0xFF121926)],
          ),
          border: Border.all(color: isLight ? const Color(0x120F172A) : const Color(0x22FFFFFF)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: isLight ? const Color(0x1A0284C7) : const Color(0x337EC8E3),
              child: Icon(icon, color: isLight ? const Color(0xFF0369A1) : const Color(0xFF9FE6FF)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: isLight ? const Color(0xFF0F172A) : Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: isLight ? const Color(0xFF475569) : const Color(0xFF9CA3AF),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: isLight ? const Color(0xFF334155) : Colors.white70),
          ],
        ),
      ),
    );
  }
}

class _PrestHelpRow extends StatelessWidget {
  const _PrestHelpRow({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: const Color(0xFF0284C7)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 4),
                Text(body, style: const TextStyle(color: Color(0xFF64748B), height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stat chip compact
// ─────────────────────────────────────────────────────────────────────────────
class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool isLight;

  const _StatChip({required this.label, required this.value, required this.icon, required this.color, required this.isLight});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isLight ? 0.08 : 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(height: 3),
            Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(label, style: TextStyle(color: color.withValues(alpha: 0.75), fontSize: 9, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
