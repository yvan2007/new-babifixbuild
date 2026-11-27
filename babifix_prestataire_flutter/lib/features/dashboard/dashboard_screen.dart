import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../shared/app_palette_mode.dart';
import '../../shared/auth_utils.dart';
import '../../shared/in_app_notifications.dart';
import 'floating_nav_bar.dart';
import '../../shared/widgets/babifix_button.dart';
import '../../shared/widgets/babifix_ring_loader.dart';
import '../../shared/widgets/babifix_prestation_timer.dart';
import '../../shared/widgets/babifix_skeleton.dart';
import 'package:url_launcher/url_launcher.dart';

/// Salutation selon l'heure (petite touche personnalisée).
String babifixGreeting() {
  final h = DateTime.now().hour;
  if (h < 5) return 'Bonne nuit';
  if (h < 12) return 'Bonjour';
  if (h < 18) return 'Bon après-midi';
  return 'Bonsoir';
}

class PrestataireDashboardScreen extends StatefulWidget {
  const PrestataireDashboardScreen({
    super.key,
    required this.paletteMode,
    required this.onNavigate,
    required this.inAppNotifs,
    this.unreadChat,
    this.onMessagesOpened,
  });

  final AppPaletteMode paletteMode;
  final ValueChanged<String> onNavigate;
  final ValueNotifier<List<BabifixInAppNotif>> inAppNotifs;
  final ValueNotifier<int>? unreadChat;
  final VoidCallback? onMessagesOpened;

  @override
  State<PrestataireDashboardScreen> createState() => _PrestataireDashboardScreenState();
}

class _PrestataireDashboardScreenState extends State<PrestataireDashboardScreen> {
  int selected = 0;
  bool _loadingMe = true;
  String _greetingName = 'Prestataire';
  String _gainsMonth = '0';
  String _prestations = '0';
  String _noteAvg = '\u2014';
  String? _provStatut;
  String? _refusalReason;
  String providerVille = '';

  bool _isAvailable = true;
  bool _togglingAvail = false;
  String? _photoUrl;
  // Checklist de démarrage (onboarding guidé)
  bool _contratSigne = false;
  bool _aNumeroRetrait = false;
  bool _bioOk = false;
  bool _onboardingDismissed = false;
  // Données graphique revenus (6 derniers mois)
  List<double> _revenueByMonth = [0, 0, 0, 0, 0, 0];
  List<String> _revenueMonthLabels = ['M-5', 'M-4', 'M-3', 'M-2', 'M-1', 'Ce mois'];

  // Intervention en cours / prochaine (carte « Prochaine intervention »).
  Map<String, dynamic>? _activeIntervention;
  bool _loadingActive = true;

  // Fiabilité + avertissement anti-contournement (Phase 5).
  int _fiabiliteScore = 100;
  String _fiabiliteNiveau = 'Excellent';
  String _fiabiliteNiveauCode = 'excellent';
  int _visitesSuspectes = 0;
  bool _avertActif = false;
  String _avertNiveau = 'attention'; // attention | critique
  String _avertTitre = '';
  String _avertMessage = '';

  bool get _isWhite => widget.paletteMode == AppPaletteMode.white;
  bool get _isLight => widget.paletteMode != AppPaletteMode.blue;

  @override
  void initState() {
    super.initState();
    _loadMe();
    _loadRevenueChart();
    _loadActiveIntervention();
    // Rafraîchissement instantané de « Prochaine intervention » quand une
    // réservation change en temps réel (statut/démarrage/fin…).
    babifixReservationsTick.addListener(_onReservationsTick);
  }

  void _onReservationsTick() {
    if (mounted) _loadActiveIntervention();
  }

  @override
  void dispose() {
    babifixReservationsTick.removeListener(_onReservationsTick);
    super.dispose();
  }

  /// Charge la VRAIE intervention en cours / prochaine (au lieu du placeholder).
  /// Priorité : en cours > terminée en attente client > confirmée/acceptée.
  Future<void> _loadActiveIntervention() async {
    try {
      final tok = await readStoredApiToken();
      if (tok == null || tok.isEmpty) {
        if (mounted) setState(() => _loadingActive = false);
        return;
      }
      // 60 s (et non 30) : le serveur Render se réveille après inactivité en
      // ~40-60 s. Un timeout trop court laissait l'intervention en cours VIDE.
      final res = await babifixAuthGet(
        '${babifixApiBaseUrl()}/api/prestataire/requests',
      ).timeout(const Duration(seconds: 60));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final items = (data['items'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        int rank(String s) {
          switch (s) {
            case 'INTERVENTION_EN_COURS':
              return 0;
            case 'En attente client':
              return 1;
            case 'Confirmee':
            case 'DEVIS_ACCEPTE':
              return 2;
            default:
              return 99;
          }
        }
        Map<String, dynamic>? best;
        int bestRank = 99;
        for (final it in items) {
          final r = rank('${it['status'] ?? ''}');
          if (r < bestRank) {
            bestRank = r;
            best = it;
          }
        }
        if (mounted) {
          setState(() {
            _activeIntervention = bestRank < 99 ? best : null;
            _loadingActive = false;
          });
        }
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingActive = false);
  }

  Future<void> _loadMe() async {
    try {
      final tok = await readStoredApiToken();
      if (tok == null || tok.isEmpty) {
        if (mounted) setState(() => _loadingMe = false);
        return;
      }
      babifixRegisterFcm(tok);
      for (int attempt = 0; attempt < 3; attempt++) {
        if (!mounted) return;
        try {
          final res = await babifixAuthGet(
            '${babifixApiBaseUrl()}/api/prestataire/me',
          ).timeout(const Duration(seconds: 60));
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body) as Map<String, dynamic>;
            final prov = data['provider'] as Map<String, dynamic>? ?? {};
            final st = data['stats'] as Map<String, dynamic>? ?? {};
            final fi = data['fiabilite'] as Map<String, dynamic>? ?? {};
            final avert = fi['avertissement'] as Map<String, dynamic>? ?? {};
            final nom = '${prov['nom'] ?? 'Prestataire'}';
            final rc = (st['reservations_total'] as num?)?.toInt() ?? 0;
            final ch = (st['chiffre_paiements'] as num?)?.toInt() ?? 0;
            final avg = prov['average_rating'];
            final cnt = (prov['rating_count'] as num?)?.toInt() ?? 0;
            final rr = '${prov['refusal_reason'] ?? ''}'.trim();
            final dispo = prov['disponible'];
            final photo = '${prov['photo_portrait_url'] ?? ''}'.trim();
            if (!mounted) return;
            setState(() {
              _greetingName = nom;
              _gainsMonth = '$ch';
              _prestations = '$rc';
              _noteAvg = (cnt > 0 && avg != null) ? (avg as num).toStringAsFixed(1) : '\u2014';
              _provStatut = '${prov['statut'] ?? ''}';
              _refusalReason = rr.isEmpty ? null : rr;
              _isAvailable = dispo == true || dispo == 1;
              _photoUrl = photo.isEmpty ? null : photo;
              // Fiabilité + avertissement anti-contournement.
              _fiabiliteScore = (fi['score'] as num?)?.toInt() ??
                  (prov['fiabilite_score'] as num?)?.toInt() ?? 100;
              _fiabiliteNiveau = '${fi['niveau'] ?? 'Excellent'}';
              _fiabiliteNiveauCode = '${fi['niveau_code'] ?? 'excellent'}';
              _visitesSuspectes = (fi['visites_suspectes'] as num?)?.toInt() ?? 0;
              _avertActif = avert['actif'] == true;
              _avertNiveau = '${avert['niveau'] ?? 'attention'}';
              _avertTitre = '${avert['titre'] ?? ''}';
              _avertMessage = '${avert['message'] ?? ''}';
              providerVille = '${prov['ville'] ?? ''}'.trim();
              _contratSigne = prov['contrat_signe'] == true;
              _aNumeroRetrait = prov['a_numero_retrait'] == true;
              _bioOk = '${prov['bio'] ?? ''}'.trim().length >= 10;
              _loadingMe = false;
            });
            return;
          }
        } catch (_) {
          if (attempt < 2) await Future.delayed(const Duration(milliseconds: 800));
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingMe = false);
  }

  /// Checklist de démarrage : guide le prestataire pour activer son compte.
  /// Disparaît automatiquement quand toutes les étapes sont faites (ou ignorée).
  Color _fiabiliteColor() {
    switch (_fiabiliteNiveauCode) {
      case 'excellent':
        return const Color(0xFF22C55E);
      case 'bon':
        return const Color(0xFF06B6D4);
      case 'moyen':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFFEF4444);
    }
  }

  /// Carte de fiabilité : jauge + niveau + conseil. Toujours visible.
  Widget _buildFiabiliteCard() {
    final c = _fiabiliteColor();
    final bg = BabifixDesign.surfaceOf(context);
    final textPrimary = BabifixDesign.textPrimaryOf(context);
    final textSec = BabifixDesign.textMutedOf(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: BabifixDesign.borderOf(context)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 64,
                  height: 64,
                  child: CircularProgressIndicator(
                    value: _fiabiliteScore.clamp(0, 100) / 100.0,
                    strokeWidth: 6,
                    strokeCap: StrokeCap.round,
                    backgroundColor: c.withValues(alpha: 0.14),
                    valueColor: AlwaysStoppedAnimation<Color>(c),
                  ),
                ),
                Text(
                  '$_fiabiliteScore',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: textPrimary,
                    fontFeatures: BabifixDesign.tabularFigures,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Fiabilité',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: textSec)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                          color: c.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(999)),
                      child: Text(_fiabiliteNiveau,
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: c)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _fiabiliteScore >= 80
                      ? 'Excellent ! Continuez à honorer vos rendez-vous et à envoyer vos devis dans l\'application.'
                      : _fiabiliteScore >= 60
                          ? 'Bon niveau. Passez toujours vos devis via BABIFIX pour progresser.'
                          : 'Votre score doit remonter : honorez vos visites et envoyez vos devis dans l\'app.',
                  style: TextStyle(fontSize: 12, height: 1.35, color: textSec),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Carte d'avertissement anti-contournement (suspension si récidive).
  Widget _buildAvertissementCard() {
    final suspendu = _avertNiveau == 'suspendu';
    final critique = suspendu || _avertNiveau == 'critique';
    final c = suspendu
        ? const Color(0xFFB91C1C)
        : (critique ? const Color(0xFFEF4444) : const Color(0xFFF59E0B));
    final light = _isLight;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [c.withValues(alpha: 0.18), c.withValues(alpha: 0.06)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: c.withValues(alpha: 0.18), shape: BoxShape.circle),
                child: Icon(
                    suspendu
                        ? Icons.lock_rounded
                        : (critique
                            ? Icons.gpp_maybe_rounded
                            : Icons.warning_amber_rounded),
                    color: c,
                    size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _avertTitre.isEmpty ? 'Attention' : _avertTitre,
                  style: TextStyle(
                      fontSize: 15.5, fontWeight: FontWeight.w900, color: c),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _avertMessage,
            style: TextStyle(
                fontSize: 12.8,
                height: 1.45,
                color:
                    light ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
          ),
          if (_visitesSuspectes > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.flag_rounded, size: 16, color: c),
                  const SizedBox(width: 8),
                  Text('$_visitesSuspectes visite(s) signalée(s)',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w800, color: c)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOnboardingChecklist() {
    if (_loadingMe || _onboardingDismissed) return const SizedBox.shrink();
    final steps = <({bool done, String label, String target, IconData icon})>[
      (done: _photoUrl != null, label: 'Ajouter une photo de profil', target: 'profile', icon: Icons.photo_camera_rounded),
      (done: _bioOk, label: 'Compléter votre description', target: 'profile', icon: Icons.edit_note_rounded),
      (done: _contratSigne, label: 'Signer le contrat prestataire', target: 'contrat_mandatory', icon: Icons.assignment_turned_in_rounded),
      (done: _aNumeroRetrait, label: 'Ajouter un numéro de retrait', target: 'wallet', icon: Icons.account_balance_wallet_rounded),
    ];
    final doneCount = steps.where((s) => s.done).length;
    if (doneCount >= steps.length) return const SizedBox.shrink();

    const cyan = BabifixDesign.cyanDeep;
    final light = _isLight;
    final cardBg = BabifixDesign.surfaceOf(context);
    final titleColor = BabifixDesign.textPrimaryOf(context);
    final stepActiveColor = BabifixDesign.textPrimaryOf(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: BabifixDesign.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.rocket_launch_rounded, color: cyan, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Activez votre compte',
                    style: TextStyle(color: titleColor, fontWeight: FontWeight.w800, fontSize: 15)),
              ),
              Text('$doneCount/${steps.length}',
                  style: const TextStyle(color: cyan, fontWeight: FontWeight.w700, fontSize: 13)),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 18),
                tooltip: 'Plus tard',
                onPressed: () => setState(() => _onboardingDismissed = true),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: doneCount / steps.length,
              minHeight: 6,
              backgroundColor: light
                  ? const Color(0xFFE2E8F0)
                  : Colors.white.withValues(alpha: 0.08),
              valueColor: const AlwaysStoppedAnimation(cyan),
            ),
          ),
          const SizedBox(height: 8),
          ...steps.map((s) => InkWell(
                onTap: s.done ? null : () => widget.onNavigate(s.target),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                  child: Row(
                    children: [
                      Icon(
                        s.done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        color: s.done ? const Color(0xFF22C55E) : const Color(0xFF94A3B8),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          s.label,
                          style: TextStyle(
                            color: s.done ? const Color(0xFF94A3B8) : stepActiveColor,
                            fontWeight: s.done ? FontWeight.w500 : FontWeight.w600,
                            fontSize: 13.5,
                            decoration: s.done ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                      if (!s.done)
                        const Icon(Icons.chevron_right_rounded, color: cyan, size: 20),
                    ],
                  ),
                ),
              )),
        ],
      ),
    );
  }

  Future<void> _loadRevenueChart() async {
    try {
      final tok = await readStoredApiToken();
      if (tok == null || tok.isEmpty) return;
      final res = await babifixAuthGet(
        '${babifixApiBaseUrl()}/api/prestataire/earnings/monthly/',
      ).timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final months = (data['months'] as List<dynamic>? ?? []);
      if (months.isEmpty) return;
      final revenues = months.map<double>((m) {
        final amount = (m as Map<String, dynamic>)['total_amount'];
        return (amount is num ? amount.toDouble() : 0.0);
      }).toList();
      final labels = months.map<String>((m) => '${(m as Map)['label'] ?? ''}').toList();
      if (mounted) {
        setState(() {
          _revenueByMonth = revenues;
          _revenueMonthLabels = labels;
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleAvailability(bool value) async {
    if (_togglingAvail) return;
    setState(() {
      _isAvailable = value;
      _togglingAvail = true;
    });
    try {
      final tok = await readStoredApiToken();
      if (tok == null || tok.isEmpty) return;
      await http.patch(
        Uri.parse('${babifixApiBaseUrl()}/api/prestataire/availability/'),
        headers: {
          'Authorization': 'Bearer $tok',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'disponible': value}),
      ).timeout(const Duration(seconds: 60));
    } catch (_) {
      // revert on error
      if (mounted) setState(() => _isAvailable = !value);
    } finally {
      if (mounted) setState(() => _togglingAvail = false);
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([_loadMe(), _loadRevenueChart(), _loadActiveIntervention()]);
  }

  @override
  Widget build(BuildContext context) {
    final topBleedColor = _isLight
        ? (_isWhite ? BabifixDesign.bgWhite : const Color(0xFF0084D1))
        : BabifixDesign.navy;
    return Scaffold(
      extendBody: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Container(
        color: topBleedColor,
        child: SafeArea(
          bottom: false,
          child: Container(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: RefreshIndicator(
              onRefresh: _refreshAll,
              color: const Color(0xFF4CC9F0),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: _isLight
                        ? _VibrantBlueDashboardHeader(
                            topInset: 0,
                            greetingName: _greetingName,
                            gainsMonth: _gainsMonth,
                            prestations: _prestations,
                            noteAvg: _noteAvg,
                            loading: _loadingMe,
                            inAppNotifs: widget.inAppNotifs,
                            onNavigate: widget.onNavigate,
                            photoUrl: _photoUrl,
                            isPureWhite: _isWhite,
                            onboardingChecklist: _buildOnboardingChecklist(),
                          )
                        : Container(
                            padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                            decoration: const BoxDecoration(
                              color: BabifixDesign.navy,
                              border: Border(
                                bottom: BorderSide(color: BabifixDesign.borderDark),
                              ),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(right: 12),
                                      child: CircleAvatar(
                                        radius: 24,
                                        backgroundImage: _photoUrl != null ? NetworkImage(_photoUrl!) : null,
                                        backgroundColor: const Color(0xFF1E3A5F),
                                        child: _photoUrl == null
                                            ? Text(
                                                _greetingName.isNotEmpty ? _greetingName[0].toUpperCase() : 'P',
                                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18),
                                              )
                                            : null,
                                      ),
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Tableau de bord',
                                            style: TextStyle(
                                              fontSize: 26,
                                              fontWeight: FontWeight.w800,
                                              color: Color(0xFFF8FAFC),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${babifixGreeting()}, $_greetingName',
                                            style: const TextStyle(color: Color(0xFFB4C2D9), fontSize: 15),
                                          ),
                                        ],
                                      ),
                                    ),
                                    _DashboardNotificationButton(
                                      lightStyle: false,
                                      hub: widget.inAppNotifs,
                                      onNavigate: widget.onNavigate,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                _buildOnboardingChecklist(),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _Stat(
                                        value: _loadingMe ? '\u2026' : '$_gainsMonth FCFA',
                                        label: 'Gains (total paiements)',
                                        variant: _StatVariant.onGradient,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _Stat(
                                        value: _loadingMe ? '\u2026' : _prestations,
                                        label: 'R\u00e9servations li\u00e9es',
                                        variant: _StatVariant.onGradient,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _Stat(
                                        value: _loadingMe ? '\u2026' : _noteAvg,
                                        label: 'Note moy.',
                                        variant: _StatVariant.onGradient,
                                        valueSuffix: const Icon(
                                          Icons.star_rounded,
                                          size: 18,
                                          color: Color(0xFFFFC107),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                  ),
                  if (_provStatut == 'En attente')
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Material(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(12),
                          child: const Padding(
                            padding: EdgeInsets.all(12),
                            child: Text(
                              'Votre dossier est en cours de v\u00e9rification par l\u2019administrateur BABIFIX. '
                              'Les clients ne vous voient pas encore dans l\u2019app tant que le compte n\u2019est pas valid\u00e9.',
                              style: TextStyle(color: Color(0xFF9A3412), height: 1.35),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_refusalReason != null && _refusalReason!.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Material(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: Text(
                              'Dossier refus\u00e9. Motif communiqu\u00e9 par l\u2019administration :\n$_refusalReason',
                              style: const TextStyle(color: Color(0xFF991B1B), height: 1.35),
                            ),
                          ),
                        ),
                      ),
                    ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList.list(
              children: [
                // Avertissement anti-contournement (visible en haut si actif).
                if (_avertActif && !_loadingMe) ...[
                  _buildAvertissementCard(),
                  const SizedBox(height: 14),
                ],
                // Carte de fiabilité, toujours visible.
                if (!_loadingMe) ...[
                  _buildFiabiliteCard(),
                  const SizedBox(height: 18),
                ],
                Text(
                  'Prochaine intervention',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                _AppointmentCard(
                  intervention: _activeIntervention,
                  loading: _loadingActive,
                  fallbackVille: providerVille,
                  onOpen: () => widget.onNavigate('requests'),
                ),
                const SizedBox(height: 16),
                _AvailabilityToggleCard(
                  isAvailable: _isAvailable,
                  toggling: _togglingAvail,
                  onChanged: _toggleAvailability,
                ),
                const SizedBox(height: 20),
                // ── Graphique revenus ────────────────────────────────────────
                Text(
                  'Revenus : 6 derniers mois',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: BabifixDesign.surfaceOf(context),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: BabifixDesign.borderOf(context)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 18, 14, 10),
                    child: SizedBox(
                      height: 185,
                      child: _revenueByMonth.isEmpty
                          ? Center(
                              child: Text(
                                'Aucune donn\u00e9e de revenus',
                                style: TextStyle(color: BabifixDesign.textMutedOf(context)),
                              ),
                            )
                          : BarChart(
                              BarChartData(
                                alignment: BarChartAlignment.spaceAround,
                                maxY: (_revenueByMonth.reduce((a, b) => a > b ? a : b) * 1.3).clamp(1000, double.infinity),
                                barTouchData: BarTouchData(
                                  touchTooltipData: BarTouchTooltipData(
                                    getTooltipColor: (_) => BabifixDesign.navy,
                                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                      final label = groupIndex >= 0 && groupIndex < _revenueMonthLabels.length
                                          ? _revenueMonthLabels[groupIndex]
                                          : '';
                                      return BarTooltipItem(
                                        '$label\n${rod.toY.round()} FCFA',
                                        const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 11.5,
                                          fontFeatures: BabifixDesign.tabularFigures,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                barGroups: List.generate(
                                  _revenueByMonth.length,
                                  (i) => BarChartGroupData(
                                    x: i,
                                    barRods: [
                                      BarChartRodData(
                                        toY: _revenueByMonth[i],
                                        color: i == _revenueByMonth.length - 1
                                            ? BabifixDesign.ciOrange
                                            : BabifixDesign.cyanDeep,
                                        width: 22,
                                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                                      ),
                                    ],
                                  ),
                                ),
                                gridData: FlGridData(
                                  show: true,
                                  drawVerticalLine: false,
                                  getDrawingHorizontalLine: (_) => FlLine(
                                    color: BabifixDesign.borderOf(context),
                                    strokeWidth: 1,
                                  ),
                                ),
                                borderData: FlBorderData(show: false),
                                titlesData: FlTitlesData(
                                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      getTitlesWidget: (val, _) {
                                        final idx = val.round();
                                        if (idx < 0 || idx >= _revenueMonthLabels.length) return const SizedBox.shrink();
                                        return Padding(
                                          padding: const EdgeInsets.only(top: 6),
                                          child: Text(
                                            _revenueMonthLabels[idx],
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w600,
                                              color: BabifixDesign.textMutedOf(context),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Actions rapides',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ValueListenableBuilder<int>(
                        valueListenable: babifixNewRequestsCount,
                        builder: (_, pendingCount, __) => _QuickAction(
                          title: 'Demandes',
                          subtitle: pendingCount > 0
                              ? '$pendingCount nouvelle${pendingCount > 1 ? 's' : ''}'
                              : 'Voir les missions',
                          icon: Icons.calendar_month,
                          badgeCount: pendingCount,
                          onTap: () => widget.onNavigate('requests'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _QuickAction(
                        title: 'Gains',
                        subtitle: 'Voir d\u00e9tails',
                        icon: Icons.account_balance_wallet,
                        onTap: () => widget.onNavigate('earnings'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _QuickAction(
                        title: 'Mon Wallet',
                        subtitle: 'Solde & retraits',
                        icon: Icons.savings_rounded,
                        onTap: () => widget.onNavigate('wallet'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _QuickAction(
                        title: 'Actualités',
                        subtitle: 'Annonces BABIFIX',
                        icon: Icons.newspaper_rounded,
                        onTap: () => widget.onNavigate('actualites'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 90),
              ],
            ),
          ),
        ],
        ),
      ),
      ),
      ),
      ),
      bottomNavigationBar: PrestataireFloatingNavBar(
        selectedIndex: selected,
        isLight: _isLight,
        unreadChat: widget.unreadChat,
        onMessagesOpened: widget.onMessagesOpened,
        onSelect: (value) {
          setState(() => selected = value);
          if (value == 1) {
            widget.onNavigate('requests');
          } else if (value == 2) {
            widget.onNavigate('wallet');
          } else if (value == 3) {
            widget.onMessagesOpened?.call();
            widget.onNavigate('messages');
          } else if (value == 4) {
            widget.onNavigate('profile');
          }
        },
      ),
    );
  }
}

/// En-tête Tableau de bord adapté aux modes Blanc et Clair.
class _VibrantBlueDashboardHeader extends StatelessWidget {
  const _VibrantBlueDashboardHeader({
    required this.topInset,
    required this.greetingName,
    required this.gainsMonth,
    required this.prestations,
    required this.noteAvg,
    required this.loading,
    required this.inAppNotifs,
    required this.onNavigate,
    this.photoUrl,
    this.isPureWhite = false,
    this.onboardingChecklist,
  });

  final double topInset;
  final String greetingName;
  final String gainsMonth;
  final String prestations;
  final String noteAvg;
  final bool loading;
  final ValueNotifier<List<BabifixInAppNotif>> inAppNotifs;
  final ValueChanged<String> onNavigate;
  final String? photoUrl;
  final bool isPureWhite;
  final Widget? onboardingChecklist;

  static const _blue = Color(0xFF0084D1);
  static const _cyan = Color(0xFF4CC9F0);
  static const _navy = Color(0xFF0B1B34);

  @override
  Widget build(BuildContext context) {
    final vG = loading ? '\u2026' : '$gainsMonth FCFA';
    final vP = loading ? '\u2026' : prestations;
    final vN = loading ? '\u2026' : noteAvg;
    final whiteMode = isPureWhite;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, topInset + 18, 16, 20),
      decoration: BoxDecoration(
        color: whiteMode ? Colors.white : _blue,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
        border: whiteMode
            ? const Border(
                bottom: BorderSide(
                  color: BabifixDesign.borderLight,
                  width: 1,
                ),
              )
            : null,
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: CircleAvatar(
                  radius: 26,
                  backgroundImage: photoUrl != null ? NetworkImage(photoUrl!) : null,
                  backgroundColor: whiteMode
                      ? _cyan.withValues(alpha: 0.16)
                      : const Color(0xFF006DAE),
                  child: photoUrl == null
                      ? Text(
                          greetingName.isNotEmpty ? greetingName[0].toUpperCase() : 'P',
                          style: TextStyle(
                            color: whiteMode ? _navy : Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                          ),
                        )
                      : null,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tableau de bord',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: whiteMode ? _navy : Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${babifixGreeting()}, $greetingName',
                      style: TextStyle(
                        color: whiteMode ? const Color(0xFF475569) : Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              _DashboardNotificationButton(
                lightStyle: !whiteMode,
                hub: inAppNotifs,
                onNavigate: onNavigate,
              ),
            ],
          ),
          if (onboardingChecklist != null) ...[
            const SizedBox(height: 16),
            onboardingChecklist!,
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  value: vG,
                  label: 'Gains (total)',
                  variant: whiteMode ? _StatVariant.onCard : _StatVariant.onGradient,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Stat(
                  value: vP,
                  label: 'R\u00e9servations',
                  variant: whiteMode ? _StatVariant.onCard : _StatVariant.onGradient,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Stat(
                  value: vN,
                  label: 'Note moy.',
                  variant: whiteMode ? _StatVariant.onCard : _StatVariant.onGradient,
                  valueSuffix: const Icon(
                    Icons.star_rounded,
                    size: 18,
                    color: Color(0xFFFFC107),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DashboardNotificationButton extends StatelessWidget {
  const _DashboardNotificationButton({
    required this.lightStyle,
    required this.hub,
    required this.onNavigate,
  });

  final bool lightStyle;
  final ValueNotifier<List<BabifixInAppNotif>> hub;
  final ValueChanged<String> onNavigate;

  void _openSheet(BuildContext context) {
    showPrestataireNotificationHub(context, hub, onNavigate);
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = lightStyle ? Colors.white : const Color(0xFF4CC9F0);
    return ValueListenableBuilder<List<BabifixInAppNotif>>(
      valueListenable: hub,
      builder: (context, list, _) {
        final unread = countUnreadInApp(hub, BabifixNotifAudience.prestataire);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              tooltip: 'Notifications',
              onPressed: () => _openSheet(context),
              icon: Icon(Icons.notifications_rounded, color: iconColor, size: 26),
            ),
            if (unread > 0)
              Positioned(
                right: 6,
                top: 6,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF3B30),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: lightStyle ? const Color(0xFF0084D1) : const Color(0xFF0B1B34),
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

enum _StatVariant { onGradient, onCard }

class _Stat extends StatelessWidget {
  const _Stat({
    required this.value,
    required this.label,
    this.variant = _StatVariant.onGradient,
    this.valueSuffix,
  });

  final String value;
  final String label;
  final _StatVariant variant;
  final Widget? valueSuffix;

  @override
  Widget build(BuildContext context) {
    if (variant == _StatVariant.onCard) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: BabifixDesign.borderLight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: const Color(0xFF0B1B34).withValues(alpha: 0.55),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0B1B34),
                    fontFeatures: BabifixDesign.tabularFigures,
                  ),
                ),
                if (valueSuffix != null) valueSuffix!,
              ],
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xFFE0F2FE)),
          ),
          const SizedBox(height: 4),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFF8FAFC),
                  fontFeatures: BabifixDesign.tabularFigures,
                ),
              ),
              if (valueSuffix != null) valueSuffix!,
            ],
          ),
        ],
      ),
    );
  }
}

/// Carte « Prochaine intervention » premium, branchée sur la VRAIE intervention
/// en cours / à venir (plus de placeholder). Affiche statut, client, service,
/// adresse, paiement, chrono live si en cours, et un bouton d'ouverture.
class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({
    required this.intervention,
    required this.loading,
    required this.fallbackVille,
    required this.onOpen,
  });

  final Map<String, dynamic>? intervention;
  final bool loading;
  final String fallbackVille;
  final VoidCallback onOpen;

  ({Color color, String label, IconData icon}) _statusMeta(String s) {
    switch (s) {
      case 'INTERVENTION_EN_COURS':
        return (color: const Color(0xFF7C3AED), label: 'En cours', icon: Icons.bolt_rounded);
      case 'En attente client':
        return (color: const Color(0xFFF59E0B), label: 'À confirmer (client)', icon: Icons.hourglass_top_rounded);
      case 'Confirmee':
        return (color: const Color(0xFF0084D1), label: 'Confirmée', icon: Icons.event_available_rounded);
      case 'DEVIS_ACCEPTE':
        return (color: const Color(0xFF0084D1), label: 'Devis accepté', icon: Icons.description_rounded);
      default:
        return (color: const Color(0xFF64748B), label: s, icon: Icons.event_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final cardBg = BabifixDesign.surfaceOf(context);
    final borderCol = BabifixDesign.borderOf(context);
    final titleCol = BabifixDesign.textPrimaryOf(context);
    final subCol = BabifixDesign.textMutedOf(context);
    final card = BoxDecoration(
      color: cardBg,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: borderCol),
    );

    if (loading) {
      return const BabifixSkeletonScope(
        child: BabifixSkeletonCard(),
      );
    }

    final it = intervention;
    if (it == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: card,
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: isLight ? const Color(0xFFEFF6FF) : const Color(0xFF1E3A5F),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.event_busy_rounded, color: subCol),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Aucune intervention en cours',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: titleCol)),
                  const SizedBox(height: 3),
                  Text('Vos demandes acceptées apparaîtront ici.',
                      style: TextStyle(fontSize: 12.5, color: subCol)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final status = '${it['status'] ?? ''}';
    final meta = _statusMeta(status);
    final client = '${it['client'] ?? 'Client BABIFIX'}'.trim();
    final service = '${it['service'] ?? 'Intervention'}'.trim();
    final addr = '${it['address'] ?? ''}'.trim();
    final ville = addr.isNotEmpty
        ? addr
        : (fallbackVille.isNotEmpty ? fallbackVille : 'Côte d\'Ivoire');
    final date = '${it['date'] ?? ''}'.trim();
    final hour = '${it['hour'] ?? ''}'.trim();
    final whenLabel =
        [date, if (hour.isNotEmpty) 'à $hour'].where((e) => e.isNotEmpty).join(' ');
    final pay = '${it['payment_type'] ?? ''}'.trim();
    final mmOp = '${it['mobile_money_operator'] ?? ''}'.trim();
    final started =
        DateTime.tryParse('${it['intervention_started_at'] ?? ''}')?.toLocal();
    final ended =
        DateTime.tryParse('${it['prestation_terminee_at'] ?? ''}')?.toLocal();
    final isUrgent = it['is_urgent'] == true;
    // Date prévue (créneau choisi) → « Prévu le … · dans X jours ».
    final schedIso = '${it['scheduled_date'] ?? ''}'.trim();
    int schedDays = 0;
    String schedLabel = '';
    if (schedIso.isNotEmpty) {
      final d = DateTime.tryParse(schedIso);
      if (d != null) {
        final now = DateTime.now();
        schedDays = DateTime(d.year, d.month, d.day)
            .difference(DateTime(now.year, now.month, now.day))
            .inDays;
        schedLabel =
            '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
      }
    }
    final clat = (it['address_lat'] as num?)?.toDouble();
    final clon = (it['address_lon'] as num?)?.toDouble();
    final hasItinerary = clat != null && clon != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: card.copyWith(
            border: Border.all(color: meta.color.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: meta.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(meta.icon, size: 14, color: meta.color),
                        const SizedBox(width: 5),
                        Text(meta.label,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: meta.color)),
                      ],
                    ),
                  ),
                  if (isUrgent) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('URGENT',
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFEF4444))),
                    ),
                  ],
                  const Spacer(),
                  if (whenLabel.isNotEmpty)
                    Text(whenLabel,
                        style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF94A3B8),
                            fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 12),
              Text(service,
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w900, color: titleCol)),
              const SizedBox(height: 10),
              _line(Icons.person_outline_rounded, meta.color, client, isLight),
              const SizedBox(height: 6),
              _line(Icons.location_on_outlined, meta.color, ville, isLight),
              if (schedLabel.isNotEmpty) ...[
                const SizedBox(height: 6),
                _line(
                  Icons.event_available_rounded,
                  meta.color,
                  schedDays > 0
                      ? 'Prévu le $schedLabel · dans $schedDays jour${schedDays > 1 ? 's' : ''}'
                      : 'Prévu aujourd\'hui ($schedLabel)',
                  isLight,
                ),
              ],
              if (pay.isNotEmpty) ...[
                const SizedBox(height: 6),
                _line(
                  pay == 'ESPECES' ? Icons.payments_outlined : Icons.smartphone_rounded,
                  meta.color,
                  pay == 'ESPECES'
                      ? 'Paiement : Espèces'
                      : 'Paiement : Mobile Money${mmOp.isNotEmpty ? ' ($mmOp)' : ''}',
                  isLight,
                ),
              ],
              if (started != null) ...[
                const SizedBox(height: 12),
                BabifixPrestationTimer(startedAt: started, endedAt: ended),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  // Surprise utile : itinéraire GPS vers le client en 1 tap.
                  if (hasItinerary) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _openItinerary(clat, clon),
                        icon: const Icon(Icons.directions_rounded, size: 18),
                        label: const Text('Itinéraire'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: meta.color,
                          side: BorderSide(color: meta.color.withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    flex: hasItinerary ? 1 : 2,
                    child: BabifixButton(
                      label: 'Ouvrir',
                      icon: Icons.open_in_new_rounded,
                      height: 46,
                      borderRadius: 12,
                      backgroundColor: meta.color,
                      onPressed: onOpen,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openItinerary(double lat, double lon) async {
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lon');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Widget _line(IconData icon, Color color, String text, bool isLight) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 19),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  fontSize: 14,
                  color: isLight ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                  fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.badgeCount = 0,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final cardBg = BabifixDesign.surfaceOf(context);
    final borderCol = BabifixDesign.borderOf(context);
    final titleCol = BabifixDesign.textPrimaryOf(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: badgeCount > 0 ? const Color(0xFFEF4444).withValues(alpha: 0.45) : borderCol,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: (isLight ? BabifixDesign.cyanDeep : BabifixDesign.cyan)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: isLight ? BabifixDesign.cyanDeep : BabifixDesign.cyan,
                    size: 21,
                  ),
                ),
                if (badgeCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      badgeCount > 99 ? '99+' : '$badgeCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(title,
                style: TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 15, color: titleCol)),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12.5,
                color: BabifixDesign.textMutedOf(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvailabilityToggleCard extends StatelessWidget {
  const _AvailabilityToggleCard({
    required this.isAvailable,
    required this.toggling,
    required this.onChanged,
  });

  final bool isAvailable;
  final bool toggling;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeColor = BabifixDesign.success;
    final inactiveColor = BabifixDesign.textMutedOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: BabifixDesign.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isAvailable
              ? activeColor.withValues(alpha: 0.45)
              : BabifixDesign.borderOf(context),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isAvailable
                  ? activeColor.withValues(alpha: 0.12)
                  : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isAvailable
                  ? Icons.wifi_tethering_rounded
                  : Icons.wifi_tethering_off_rounded,
              color: isAvailable ? activeColor : inactiveColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAvailable ? 'Disponible' : 'Indisponible',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: isAvailable ? activeColor : BabifixDesign.textPrimaryOf(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isAvailable
                      ? 'Les clients peuvent vous r\u00e9server'
                      : 'Vous n\u2019apparaissez plus dans les recherches',
                  style: TextStyle(
                    fontSize: 12,
                    color: BabifixDesign.textMutedOf(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          toggling
              ? const SizedBox(
                  width: 28,
                  height: 28,
                  child: BabifixRingLoader.cyan(size: 28),
                )
              : Switch(
                  value: isAvailable,
                  onChanged: onChanged,
                  activeThumbColor: activeColor,
                ),
        ],
      ),
    );
  }
}
