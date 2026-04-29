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
import '../../shared/widgets/babifix_page_route.dart';
import '../auth/registration_screen.dart';
import '../availability/availability_screen.dart';
import 'contrat_screen.dart';
import '../kyc/kyc_screen.dart';
import '../dashboard/floating_nav_bar.dart';
import 'edit_profile_screen.dart' show EditProfilePrestataireScreen;
import '../parrainage/parrainage_screen.dart';
import '../premium/premium_screen.dart';

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
      babifixRoute(
        (_) => EditProfilePrestataireScreen(
          apiBase: babifixApiBaseUrl(),
          authToken: token,
        ),
      ),
    );
    if (mounted) _load();
  }

  void _showBiometricSheet(bool isLight) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        decoration: BoxDecoration(
          color: isLight ? Colors.white : const Color(0xFF0D1B2E),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(4))),
          const SizedBox(height: 20),
          const Icon(Icons.fingerprint_rounded, size: 56, color: Color(0xFF4CC9F0)),
          const SizedBox(height: 14),
          Text('Connexion biométrique',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                  color: isLight ? const Color(0xFF0F172A) : Colors.white)),
          const SizedBox(height: 8),
          Text('Activez Face ID ou l\'empreinte digitale pour accéder à votre espace prestataire rapidement.',
              style: TextStyle(color: isLight ? const Color(0xFF475569) : const Color(0xFF94A3B8), height: 1.45),
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: () => Navigator.pop(ctx),
            icon: const Icon(Icons.check_rounded),
            label: const Text('Compris'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF4CC9F0),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          )),
        ]),
      ),
    );
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
    final nnote = note != null ? (note as num).toStringAsFixed(1) : '--';
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
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(28),
                              gradient: isLight
                                  ? const LinearGradient(
                                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                                      colors: [Color(0xFF0B1B34), Color(0xFF1A3A6E)],
                                    )
                                  : const LinearGradient(
                                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                                      colors: [Color(0xFF060E1C), Color(0xFF0B1B34)],
                                    ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF4CC9F0).withValues(alpha: 0.15),
                                  blurRadius: 32, offset: const Offset(0, 12),
                                ),
                              ],
                            ),
                            child: Stack(
                              children: [
                                // Orbe décoratif
                                Positioned(
                                  top: -30, right: -30,
                                  child: Container(
                                    width: 140, height: 140,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: RadialGradient(colors: [
                                        const Color(0xFF4CC9F0).withValues(alpha: 0.12),
                                        Colors.transparent,
                                      ]),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(22),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // Avatar grand format avec ring
                                          Stack(
                                            children: [
                                              Container(
                                                width: 84, height: 84,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  gradient: const LinearGradient(
                                                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                                                    colors: [Color(0xFF4CC9F0), Color(0xFF0284C7)],
                                                  ),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: const Color(0xFF4CC9F0).withValues(alpha: 0.45),
                                                      blurRadius: 20, offset: const Offset(0, 6),
                                                    ),
                                                  ],
                                                ),
                                                child: Padding(
                                                  padding: const EdgeInsets.all(3),
                                                  child: ClipOval(
                                                    child: avatarProvider != null
                                                        ? Image(
                                                            image: avatarProvider!,
                                                            fit: BoxFit.cover,
                                                            errorBuilder: (_, __, ___) => Container(
                                                              color: const Color(0xFF0B2845),
                                                              child: Center(
                                                                child: Text(
                                                                  nom.isNotEmpty ? nom[0].toUpperCase() : '?',
                                                                  style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900),
                                                                ),
                                                              ),
                                                            ),
                                                          )
                                                        : Container(
                                                            color: const Color(0xFF0B2845),
                                                            child: Center(
                                                              child: Text(
                                                                nom.isNotEmpty ? nom[0].toUpperCase() : '?',
                                                                style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900),
                                                              ),
                                                            ),
                                                          ),
                                                  ),
                                                ),
                                              ),
                                              // Badge disponible
                                              if (_prov['disponible'] == true)
                                                Positioned(
                                                  bottom: 4, right: 4,
                                                  child: Container(
                                                    width: 18, height: 18,
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFF10B981),
                                                      shape: BoxShape.circle,
                                                      border: Border.all(color: const Color(0xFF0B1B34), width: 2.5),
                                                      boxShadow: [BoxShadow(color: const Color(0xFF10B981).withValues(alpha: 0.6), blurRadius: 8)],
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const SizedBox(height: 2),
                                                Text(
                                                  nom.isEmpty ? 'Prestataire' : nom,
                                                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.3),
                                                ),
                                                const SizedBox(height: 5),
                                                if (spec.isNotEmpty || cat.isNotEmpty)
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFF4CC9F0).withValues(alpha: 0.15),
                                                      borderRadius: BorderRadius.circular(20),
                                                      border: Border.all(color: const Color(0xFF4CC9F0).withValues(alpha: 0.3)),
                                                    ),
                                                    child: Text(
                                                      spec.isNotEmpty ? spec : cat,
                                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF7DD3FC)),
                                                    ),
                                                  ),
                                                const SizedBox(height: 6),
                                                if (ville.isNotEmpty)
                                                  Row(children: [
                                                    Icon(Icons.location_on_rounded, size: 12, color: Colors.white.withValues(alpha: 0.45)),
                                                    const SizedBox(width: 3),
                                                    Text(ville, style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12)),
                                                  ]),
                                                if (tarif != null)
                                                  Row(children: [
                                                    Icon(Icons.payments_outlined, size: 12, color: const Color(0xFFF97316).withValues(alpha: 0.8)),
                                                    const SizedBox(width: 3),
                                                    Text(tarifStr, style: const TextStyle(color: Color(0xFFFB923C), fontSize: 12, fontWeight: FontWeight.w700)),
                                                  ]),
                                              ],
                                            ),
                                          ),
                                          // Bouton modifier
                                          if (approved)
                                            GestureDetector(
                                              onTap: _openEditRegistration,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                                decoration: BoxDecoration(
                                                  gradient: const LinearGradient(colors: [Color(0xFF4CC9F0), Color(0xFF0284C7)]),
                                                  borderRadius: BorderRadius.circular(20),
                                                  boxShadow: [BoxShadow(color: const Color(0xFF4CC9F0).withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 4))],
                                                ),
                                                child: const Text('Modifier', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                                              ),
                                            ),
                                        ],
                                      ),

                                      // Badge vérifié
                                      if (approved) ...[
                                        const SizedBox(height: 16),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(colors: [
                                              const Color(0xFF10B981).withValues(alpha: 0.2),
                                              const Color(0xFF059669).withValues(alpha: 0.1),
                                            ]),
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.verified_rounded, color: Color(0xFF10B981), size: 16),
                                              SizedBox(width: 6),
                                              Text('Prestataire Vérifié BABIFIX', style: TextStyle(color: Color(0xFF34D399), fontSize: 12, fontWeight: FontWeight.w700)),
                                            ],
                                          ),
                                        ),
                                      ],

                                      // Bio
                                      if (bio.isNotEmpty) ...[
                                        const SizedBox(height: 14),
                                        Text(bio,
                                          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13, height: 1.5),
                                          maxLines: 3, overflow: TextOverflow.ellipsis,
                                        ),
                                      ],

                                      const SizedBox(height: 18),

                                      // ── Stats cards premium ─────────────────
                                      Row(
                                        children: [
                                          _StatChip(label: 'Note', value: nnote, icon: Icons.star_rounded, color: const Color(0xFFF59E0B), isLight: isLight),
                                          const SizedBox(width: 8),
                                          _StatChip(label: 'Avis', value: '$rc', icon: Icons.chat_bubble_rounded, color: const Color(0xFF4CC9F0), isLight: isLight),
                                          const SizedBox(width: 8),
                                          _StatChip(label: 'Missions', value: '${jsonInt(_stats['reservations_total'])}', icon: Icons.task_alt_rounded, color: const Color(0xFF10B981), isLight: isLight),
                                          const SizedBox(width: 8),
                                          _StatChip(label: 'Taux', value: '${jsonInt(_stats['taux_completion'])}%', icon: Icons.trending_up_rounded, color: const Color(0xFFF97316), isLight: isLight),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Section : Mon Espace Pro
                          const SizedBox(height: 20),
                          _PrestSectionLabel(label: 'MON ESPACE PRO', icon: Icons.work_outline_rounded, color: const Color(0xFF4CC9F0), isLight: isLight),
                          const SizedBox(height: 8),
                          if (approved) ...[
                            _PrestProfileActionTile(
                              icon: Icons.person_outline_rounded,
                              title: 'Modifier le profil',
                              subtitle: 'Photo, spécialité, coordonnées',
                              isLight: isLight,
                              onTap: _openEditRegistration,
                            ),
                            const SizedBox(height: 8),
                            _PrestProfileActionTile(
                              icon: Icons.schedule_rounded,
                              title: 'Mes disponibilités',
                              subtitle: 'Créneaux hebdomadaires & congés',
                              isLight: isLight,
                              onTap: () => Navigator.of(context).push<void>(
                                babifixRoute((_) => const AvailabilityScreen()),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          _PrestProfileActionTile(
                            icon: Icons.account_balance_wallet_outlined,
                            title: 'Mon Wallet',
                            subtitle: 'Solde, retraits, historique transactions',
                            isLight: isLight,
                            onTap: () => widget.onNavigate('wallet'),
                          ),
                          const SizedBox(height: 8),
                          _KycStatusTile(
                            isLight: isLight,
                            paletteMode: widget.paletteMode,
                          ),
                          const SizedBox(height: 8),
                          _PrestProfileActionTile(
                            icon: Icons.description_outlined,
                            title: 'Mon Contrat',
                            subtitle: 'Charte BABIFIX, commission, conditions',
                            isLight: isLight,
                            onTap: () => Navigator.push(
                              context,
                              babifixRoute(
                                (_) => ContratScreen(
                                  onBack: () => Navigator.pop(context),
                                  paletteMode: widget.paletteMode,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _PrestProfileActionTile(
                            icon: Icons.workspace_premium_rounded,
                            title: 'BABIFIX Premium',
                            subtitle: 'Réduire ma commission, booster ma visibilité',
                            isLight: isLight,
                            onTap: () => Navigator.push(context, babifixRoute((_) => const PremiumScreen())),
                          ),
                          const SizedBox(height: 8),
                          _PrestProfileActionTile(
                            icon: Icons.card_giftcard_rounded,
                            title: 'Parrainage',
                            subtitle: 'Invitez des collègues, gagnez des crédits',
                            isLight: isLight,
                            onTap: () => Navigator.push(context, babifixRoute((_) => const ParrainageScreen())),
                          ),
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () => widget.onNavigate('earnings'),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                gradient: LinearGradient(
                                  colors: isLight
                                      ? const [Color(0xFFF0FDF4), Color(0xFFDCFCE7)]
                                      : const [Color(0xFF052010), Color(0xFF073318)],
                                ),
                                border: Border.all(color: isLight ? const Color(0xFF86EFAC) : const Color(0x3322C55E)),
                              ),
                              child: Row(children: [
                                Container(
                                  width: 40, height: 40,
                                  decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF22C55E).withValues(alpha: 0.15)),
                                  child: const Icon(Icons.trending_up_rounded, color: Color(0xFF22C55E), size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('Mes gains', style: TextStyle(fontWeight: FontWeight.w800,
                                      color: isLight ? const Color(0xFF0F172A) : Colors.white, fontSize: 13)),
                                  Text('${jsonInt(_stats['reservations_total'])} missions complétées',
                                      style: const TextStyle(color: Color(0xFF22C55E), fontSize: 12)),
                                ])),
                                const Icon(Icons.chevron_right_rounded, color: Color(0xFF22C55E)),
                              ]),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _PrestProfileActionTile(
                            icon: Icons.chat_bubble_outline_rounded,
                            title: 'Messages',
                            subtitle: 'Échanger avec vos clients',
                            isLight: isLight,
                            onTap: () {
                              widget.onMessagesOpened?.call();
                              widget.onNavigate('messages');
                            },
                          ),
                          if (bio.isNotEmpty || ville.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: isLight ? const Color(0x10000000) : const Color(0x18FFFFFF)),
                              ),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Container(width: 28, height: 28,
                                    decoration: BoxDecoration(shape: BoxShape.circle,
                                        color: const Color(0xFF4CC9F0).withValues(alpha: 0.12)),
                                    child: const Icon(Icons.badge_outlined, size: 14, color: Color(0xFF4CC9F0)),
                                  ),
                                  const SizedBox(width: 8),
                                  Text('Fiche pro', style: TextStyle(fontWeight: FontWeight.w700, color: textPrimary, fontSize: 14)),
                                ]),
                                if (bio.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Text(bio, style: TextStyle(color: textSecondary, height: 1.45, fontSize: 13)),
                                ],
                                if (ville.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Row(children: [
                                    Icon(Icons.location_on_rounded, size: 14, color: textSecondary),
                                    const SizedBox(width: 4),
                                    Text(ville, style: TextStyle(color: textSecondary, fontSize: 13)),
                                  ]),
                                ],
                                const SizedBox(height: 6),
                                Row(children: [
                                  Icon(_prov['disponible'] == true ? Icons.circle : Icons.circle_outlined,
                                      size: 10,
                                      color: _prov['disponible'] == true ? const Color(0xFF10B981) : Colors.grey),
                                  const SizedBox(width: 6),
                                  Text(
                                    _prov['disponible'] == true ? 'Disponible' : 'Indisponible',
                                    style: TextStyle(
                                        color: _prov['disponible'] == true ? const Color(0xFF10B981) : textSecondary,
                                        fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                ]),
                              ]),
                            ),
                          ],
                          if (_avis.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: isLight ? const Color(0x10000000) : const Color(0x18FFFFFF)),
                              ),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Container(width: 28, height: 28,
                                    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.amber.withValues(alpha: 0.15)),
                                    child: const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
                                  ),
                                  const SizedBox(width: 8),
                                  Text('Avis reçus (${_avis.length})',
                                      style: TextStyle(fontWeight: FontWeight.w700, color: textPrimary, fontSize: 14)),
                                ]),
                                const SizedBox(height: 12),
                                for (final r in _avis.take(5)) ...[
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    margin: const EdgeInsets.only(bottom: 8),
                                    decoration: BoxDecoration(
                                      color: isLight ? Colors.white : const Color(0xFF242B38),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: isLight ? const Color(0xFFE2E8F0) : const Color(0xFF334155)),
                                    ),
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Row(children: [
                                        CircleAvatar(
                                          radius: 14,
                                          backgroundColor: const Color(0xFF4CC9F0).withValues(alpha: 0.15),
                                          child: Text(
                                            ((r['client_name'] ?? r['auteur'] ?? 'C') as String).isNotEmpty
                                                ? ((r['client_name'] ?? r['auteur']) as String)[0].toUpperCase()
                                                : 'C',
                                            style: const TextStyle(color: Color(0xFF4CC9F0), fontWeight: FontWeight.w700, fontSize: 12),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(child: Text(
                                          (r['client_name'] ?? r['auteur'] ?? 'Client') as String,
                                          style: TextStyle(fontWeight: FontWeight.w600, color: textPrimary, fontSize: 13),
                                        )),
                                        Row(children: List.generate(5, (i) => Icon(
                                          i < (r['note'] as int? ?? 0) ? Icons.star_rounded : Icons.star_border_rounded,
                                          size: 13, color: Colors.amber,
                                        ))),
                                      ]),
                                      if ((r['commentaire'] as String? ?? '').isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Text(r['commentaire'] as String,
                                            style: TextStyle(color: textSecondary, fontSize: 13, height: 1.4)),
                                      ],
                                      if ((r['photo_proof'] as List? ?? []).isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        SizedBox(
                                          height: 60,
                                          child: ListView(scrollDirection: Axis.horizontal, children: [
                                            for (final ph in (r['photo_proof'] as List))
                                              if ((ph as String).startsWith('http'))
                                                Container(
                                                  width: 60, height: 60,
                                                  margin: const EdgeInsets.only(right: 6),
                                                  decoration: BoxDecoration(
                                                    borderRadius: BorderRadius.circular(8),
                                                    image: DecorationImage(image: NetworkImage(ph), fit: BoxFit.cover),
                                                  ),
                                                ),
                                          ]),
                                        ),
                                      ],
                                      const SizedBox(height: 4),
                                      Text((r['created_at'] ?? r['date'] ?? '') as String,
                                          style: TextStyle(color: textSecondary, fontSize: 11)),
                                    ]),
                                  ),
                                ],
                              ]),
                            ),
                          ],

                          // Section : Préférences
                          const SizedBox(height: 20),
                          _PrestSectionLabel(label: 'PRÉFÉRENCES', icon: Icons.palette_outlined, color: const Color(0xFFA855F7), isLight: isLight),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: isLight ? const Color(0xFFF8FAFC) : const Color(0xFF121926),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: isLight ? const Color(0x10000000) : const Color(0x18FFFFFF)),
                            ),
                            child: Row(children: [
                              Container(
                                width: 40, height: 40,
                                decoration: BoxDecoration(shape: BoxShape.circle,
                                    color: const Color(0xFFA855F7).withValues(alpha: 0.12)),
                                child: const Icon(Icons.brightness_6_rounded, color: Color(0xFFA855F7), size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text("Thème d'affichage", style: TextStyle(fontWeight: FontWeight.w700, color: textPrimary, fontSize: 14)),
                                Text(
                                  widget.paletteMode == AppPaletteMode.light ? 'Mode blanc (actif)' : 'Bleu BABIFIX (actif)',
                                  style: TextStyle(color: textSecondary, fontSize: 12),
                                ),
                              ])),
                              Switch(
                                value: widget.paletteMode == AppPaletteMode.blue,
                                activeColor: const Color(0xFF4CC9F0),
                                activeTrackColor: const Color(0xFF4CC9F0).withValues(alpha: 0.3),
                                onChanged: (v) => widget.onPaletteChanged(v ? AppPaletteMode.blue : AppPaletteMode.light),
                              ),
                            ]),
                          ),

                          // Section : Sécurité
                          const SizedBox(height: 20),
                          _PrestSectionLabel(label: 'SÉCURITÉ', icon: Icons.lock_outline_rounded, color: const Color(0xFFF59E0B), isLight: isLight),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isLight ? const Color(0xFFF8FAFC) : const Color(0xFF121926),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: isLight ? const Color(0x10000000) : const Color(0x18FFFFFF)),
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              _PrestProfileActionTile(
                                icon: Icons.fingerprint_rounded,
                                title: 'Connexion biométrique',
                                subtitle: 'Face ID / Empreinte pour accéder rapidement',
                                isLight: isLight,
                                onTap: () => _showBiometricSheet(isLight),
                              ),
                              const SizedBox(height: 8),
                              _PrestProfileActionTile(
                                icon: Icons.lock_outline_rounded,
                                title: 'Changer le mot de passe',
                                subtitle: 'Modifier votre mot de passe de connexion',
                                isLight: isLight,
                                onTap: () {},
                              ),
                            ]),
                          ),

                          // Section : Support
                          const SizedBox(height: 20),
                          _PrestSectionLabel(label: 'SUPPORT & AIDE', icon: Icons.support_agent_rounded, color: const Color(0xFF10B981), isLight: isLight),
                          const SizedBox(height: 8),
                          _PrestProfileActionTile(
                            icon: Icons.support_agent_rounded,
                            title: 'Contacter l’administrateur',
                            subtitle: _contactAdminEmail.isEmpty ? 'Email support BABIFIX' : _contactAdminEmail,
                            isLight: isLight,
                            onTap: _openContactAdmin,
                          ),
                          const SizedBox(height: 8),
                          _PrestProfileActionTile(
                            icon: Icons.help_center_outlined,
                            title: 'FAQ & aide',
                            subtitle: 'Guide missions, gains, avis',
                            isLight: isLight,
                            onTap: _showHelpSheet,
                          ),
                          const SizedBox(height: 8),
                          _PrestProfileActionTile(
                            icon: Icons.info_outline_rounded,
                            title: 'À propos de BABIFIX',
                            subtitle: 'Version, mentions légales et support',
                            isLight: isLight,
                            onTap: () => showAboutDialog(
                              context: context,
                              applicationName: 'BABIFIX Prestataire',
                              applicationVersion: '1.0.0',
                              applicationIcon: const CircleAvatar(backgroundImage: AssetImage(_logoAsset)),
                              children: const [Text('Application prestataire BABIFIX — missions, gains et messagerie.')],
                            ),
                          ),

                          // Section : Légal
                          const SizedBox(height: 20),
                          _PrestSectionLabel(label: 'LÉGAL', icon: Icons.description_outlined, color: const Color(0xFF64748B), isLight: isLight),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: isLight ? const Color(0xFFF8FAFC) : const Color(0xFF121926),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: isLight ? const Color(0x10000000) : const Color(0x18FFFFFF)),
                            ),
                            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                              _LegalLink(label: 'CGU', icon: Icons.description_outlined, isLight: isLight, onTap: () {}),
                              Container(width: 1, height: 32, color: isLight ? const Color(0x15000000) : const Color(0x20FFFFFF)),
                              _LegalLink(label: 'Confidentialité', icon: Icons.privacy_tip_outlined, isLight: isLight, onTap: () {}),
                              Container(width: 1, height: 32, color: isLight ? const Color(0x15000000) : const Color(0x20FFFFFF)),
                              _LegalLink(label: 'Aide', icon: Icons.help_outline_rounded, isLight: isLight, onTap: _showHelpSheet),
                            ]),
                          ),

                          // Badge certifié
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: LinearGradient(
                                colors: isLight
                                    ? const [Color(0xFFFFF7ED), Color(0xFFFFEDD5)]
                                    : const [Color(0xFF1A0C00), Color(0xFF251200)],
                              ),
                              border: Border.all(color: isLight ? const Color(0xFFFBBF24) : const Color(0x33F59E0B)),
                            ),
                            child: Row(children: [
                              const Icon(Icons.verified_user_rounded, color: Color(0xFFF59E0B), size: 22),
                              const SizedBox(width: 10),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('BABIFIX Prestataire certifié',
                                    style: TextStyle(fontWeight: FontWeight.w800,
                                        color: isLight ? const Color(0xFF0F172A) : Colors.white, fontSize: 13)),
                                Text('Paiements garantis · Clients vérifiés · Support 7j/7',
                                    style: TextStyle(color: isLight ? const Color(0xFF475569) : const Color(0xFF9CA3AF), fontSize: 11)),
                              ])),
                            ]),
                          ),

                          // Zone Déconnexion
                          const SizedBox(height: 20),
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                              gradient: LinearGradient(
                                colors: isLight
                                    ? const [Color(0xFFFFF5F5), Color(0xFFFFEBEB)]
                                    : const [Color(0xFF1A0808), Color(0xFF220E0E)],
                              ),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(18),
                              child: InkWell(
                                onTap: widget.onLogout,
                                borderRadius: BorderRadius.circular(18),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(children: [
                                    Container(
                                      width: 40, height: 40,
                                      decoration: BoxDecoration(shape: BoxShape.circle,
                                          color: const Color(0xFFEF4444).withValues(alpha: 0.12)),
                                      child: const Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 20),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      const Text('Déconnexion', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFEF4444), fontSize: 14)),
                                      Text('Quitter ce compte sur cet appareil',
                                          style: TextStyle(color: const Color(0xFFEF4444).withValues(alpha: 0.7), fontSize: 12)),
                                    ])),
                                    const Icon(Icons.chevron_right_rounded, color: Color(0xFFEF4444)),
                                  ]),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Center(child: Text('BABIFIX Prestataire v1.0.0',
                              style: TextStyle(fontSize: 11,
                                  color: isLight ? const Color(0xFF94A3B8) : const Color(0xFF475569)))),
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
    this.iconColor,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isLight;
  final Color? iconColor;
  final Widget? trailing;

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
              backgroundColor: (iconColor ?? (isLight ? const Color(0xFF0284C7) : const Color(0xFF7EC8E3))).withValues(alpha: 0.12),
              child: Icon(icon, color: iconColor ?? (isLight ? const Color(0xFF0369A1) : const Color(0xFF9FE6FF))),
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
            if (trailing != null) ...[
              trailing!,
              const SizedBox(width: 4),
            ],
            Icon(Icons.chevron_right_rounded, color: isLight ? const Color(0xFF334155) : Colors.white70),
          ],
        ),
      ),
    );
  }
}

// ── Section label avec icône colorée ─────────────────────────────────────────
class _PrestSectionLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isLight;

  const _PrestSectionLabel({required this.label, required this.icon, required this.color, required this.isLight});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 28, height: 28,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.15)),
        child: Icon(icon, size: 14, color: color),
      ),
      const SizedBox(width: 8),
      Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.0,
            color: isLight ? const Color(0xFF64748B) : const Color(0xFF9CA3AF)),
      ),
    ]);
  }
}

// ── Lien légal compact ────────────────────────────────────────────────────────
class _LegalLink extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isLight;
  final VoidCallback onTap;

  const _LegalLink({required this.label, required this.icon, required this.isLight, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 18, color: isLight ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
            color: isLight ? const Color(0xFF475569) : const Color(0xFF94A3B8))),
      ]),
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

// ─── KYC Status Tile ─────────────────────────────────────────────────────────

class _KycStatusTile extends StatefulWidget {
  const _KycStatusTile({required this.isLight, required this.paletteMode});
  final bool isLight;
  final AppPaletteMode paletteMode;

  @override
  State<_KycStatusTile> createState() => _KycStatusTileState();
}

class _KycStatusTileState extends State<_KycStatusTile> {
  String _status = 'loading';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final t = await readStoredApiToken();
      if (t == null) { setState(() => _status = 'not_submitted'); return; }
      final res = await http.get(
        Uri.parse('${babifixApiBaseUrl()}/api/prestataire/kyc/status/'),
        headers: {'Authorization': 'Bearer $t'},
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() => _status = (d['status'] as String?) ?? 'not_submitted');
      }
    } catch (_) {
      setState(() => _status = 'not_submitted');
    }
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, _KycMeta> meta = {
      'loading':       _KycMeta(Icons.hourglass_empty_rounded, const Color(0xFF94A3B8), 'Vérification KYC', 'Chargement…'),
      'not_submitted': _KycMeta(Icons.shield_outlined, const Color(0xFFF59E0B), 'Vérification KYC', 'Non soumis — requis pour activer votre profil'),
      'pending':       _KycMeta(Icons.hourglass_top_rounded, const Color(0xFF4CC9F0), 'KYC en attente', 'Votre dossier est en cours de vérification'),
      'under_review':  _KycMeta(Icons.manage_search_rounded, const Color(0xFFF59E0B), 'KYC en examen', 'Notre équipe examine votre dossier'),
      'approved':      _KycMeta(Icons.verified_rounded, const Color(0xFF22C55E), 'Identité vérifiée ✓', 'Votre KYC a été approuvé'),
      'rejected':      _KycMeta(Icons.warning_amber_rounded, const Color(0xFFDC2626), 'KYC rejeté', 'Resoumettez votre dossier'),
    };
    final m = meta[_status] ?? meta['not_submitted']!;
    final bool canSubmit = _status == 'not_submitted' || _status == 'rejected';

    return _PrestProfileActionTile(
      icon: m.icon,
      title: m.title,
      subtitle: m.subtitle,
      iconColor: m.color,
      isLight: widget.isLight,
      trailing: canSubmit
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('Action requise',
                  style: TextStyle(fontSize: 10, color: Color(0xFFF59E0B), fontWeight: FontWeight.w700)),
            )
          : null,
      onTap: () async {
        await Navigator.push(
          context,
          babifixRoute((_) => KYCScreen(
            onBack: () => Navigator.pop(context),
            paletteMode: widget.paletteMode,
          )),
        );
        _load(); // Recharger le statut au retour
      },
    );
  }
}

class _KycMeta {
  const _KycMeta(this.icon, this.color, this.title, this.subtitle);
  final IconData icon;
  final Color color;
  final String title, subtitle;
}
