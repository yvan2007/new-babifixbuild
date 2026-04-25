import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:ui';
import 'dart:convert';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'babifix_design_system.dart';
import 'babifix_api_config.dart';
import 'babifix_fcm.dart';
import 'babifix_money.dart';
import 'json_utils.dart';
import 'user_store.dart';
import 'category_icon_mapper.dart';

import 'models/client_models.dart';
import 'shared/in_app_notifications.dart';
import 'shared/offline_cache.dart';
import 'shared/connectivity_banner.dart';
import 'shared/widgets/status_pill.dart';
import 'shared/widgets/category_strip.dart';
import 'shared/services/real_time_sync.dart';
import 'features/auth/onboarding_screen.dart';
import 'features/auth/auth_screen.dart';
import 'features/auth/forgot_password_screen.dart';
import 'features/home/actualite_detail_screen.dart';
import 'features/profile/edit_profile_screen.dart';
import 'features/chat/messages_screen.dart';
import 'features/chat/chat_room_screen.dart' hide ClientChatMsg;
import 'features/services/service_detail_screen.dart';
import 'features/booking/booking_flow_screen.dart';
import 'features/booking/devis_detail_screen.dart';
import 'shared/widgets/babifix_osm_map.dart';
import 'shared/widgets/message_with_photos_field.dart';
import 'shared/widgets/payment_method_logo.dart';
import 'package:latlong2/latlong.dart';
import 'features/providers/provider_profile_screen.dart';
import 'features/notifications/notifications_screen.dart';
import 'features/payment/payment_screen.dart';
import 'theme/app_theme.dart';
import 'router/babifix_client_router.dart';

/// Aligné sur [adminpanel.views._normalize_category_key] : espaces → underscores, max 24.
String babifixCategoryFilterKey(String nom) {
  final x = nom.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '_');
  return x.length > 24 ? x.substring(0, 24) : x;
}

/// Date/heure du flux réservation → libellé API (`when_label`).
String reservationWhenLabelFromFlowData(Map<String, dynamic> flowData) {
  final timeStr = '${flowData['time'] ?? ''}'.trim();
  final dateStr = '${flowData['date'] ?? ''}'.trim();
  if (dateStr.isEmpty) return timeStr;
  try {
    final d = DateTime.parse(dateStr).toLocal();
    final dh = '${d.day}/${d.month}/${d.year}';
    if (timeStr.isNotEmpty) return '$dh à $timeStr';
    return dh;
  } catch (_) {
    if (timeStr.isNotEmpty) return '$dateStr $timeStr'.trim();
    return dateStr;
  }
}

Future<void> main() async {
  const sentryDsn = String.fromEnvironment('SENTRY_DSN', defaultValue: '');
  if (sentryDsn.isNotEmpty) {
    await SentryFlutter.init(
      (options) {
        options.dsn = sentryDsn;
        options.tracesSampleRate = 0.2;
        options.environment = kReleaseMode ? 'production' : 'development';
      },
      appRunner: () async {
        WidgetsFlutterBinding.ensureInitialized();
        await BabifixFcm.ensureInitialized();
        runApp(const BabifixClientApp());
      },
    );
  } else {
    WidgetsFlutterBinding.ensureInitialized();
    await BabifixFcm.ensureInitialized();
    runApp(const BabifixClientApp());
  }
}

// AppPaletteMode is defined in theme/app_theme.dart

class BabifixClientApp extends StatefulWidget {
  const BabifixClientApp({super.key});

  @override
  State<BabifixClientApp> createState() => _BabifixClientAppState();
}

class _BabifixClientAppState extends State<BabifixClientApp> {
  AppPaletteMode paletteMode = AppPaletteMode.light;
  bool hasSeenOnboarding = false;
  bool _prefsLoaded = false;
  final _routerRefresh = ValueNotifier<int>(0);

  static const _kPaletteKey = 'client_palette';
  static const _kOnboardingKey = 'client_onboarding_done';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      paletteMode = p.getString(_kPaletteKey) == 'blue'
          ? AppPaletteMode.blue
          : AppPaletteMode.light;
      hasSeenOnboarding = p.getBool(_kOnboardingKey) ?? false;
      _prefsLoaded = true;
    });
  }

  Future<void> _persistPalette(AppPaletteMode mode) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _kPaletteKey,
      mode == AppPaletteMode.blue ? 'blue' : 'light',
    );
  }

  Future<void> _onOnboardingDone() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kOnboardingKey, true);
    if (!mounted) return;
    setState(() => hasSeenOnboarding = true);
    _routerRefresh.value++;
  }

  void _onPaletteChanged(AppPaletteMode mode) {
    setState(() => paletteMode = mode);
    _persistPalette(mode);
  }

  ThemeData _themeForMode(AppPaletteMode mode) => BabifixTheme.forMode(mode);

  @override
  Widget build(BuildContext context) {
    if (!_prefsLoaded) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _themeForMode(paletteMode),
        home: Scaffold(
          backgroundColor: const Color(0xFF0D1F3C),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CC9F0),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.home_repair_service,
                    size: 64,
                    color: Color(0xFF0D1F3C),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'BABIFIX',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 4,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final router = createBabifixClientRouter(
      hasSeenOnboarding: hasSeenOnboarding,
      refreshListenable: _routerRefresh,
      onboardingBuilder: (_) => OnboardingScreen(onDone: _onOnboardingDone),
      homeBuilder: (_) => ClientHomePage(
        paletteMode: paletteMode,
        onPaletteChanged: _onPaletteChanged,
        onLogout: () {},
      ),
      serviceDetailBuilder: (_, id) =>
          ProviderProfileScreen(providerId: int.tryParse(id) ?? 0),
      bookingBuilder: (context, sid) => Builder(
        builder: (ctx) {
          return BookingFlowScreen(
            serviceTitle: sid,
            servicePrice: 0,
            onConfirm: (data) async {
              final token = await BabifixUserStore.getApiToken();
              if (token == null) return {'ok': false};

              try {
                final resp = await http.post(
                  Uri.parse('${babifixApiBaseUrl()}/api/client/reservations'),
                  headers: {
                    'Authorization': 'Bearer $token',
                    'Content-Type': 'application/json',
                  },
                  body: jsonEncode(data),
                );

                if (resp.statusCode == 201) {
                  final result = jsonDecode(resp.body);
                  return {'ok': true, 'reference': result['reference']};
                }
              } catch (e) {
                // Error
              }
              return {'ok': false};
            },
          );
        },
      ),
      providerProfileBuilder: (_, id) =>
          ProviderProfileScreen(providerId: int.tryParse(id) ?? 0),
      notificationsBuilder: (_) => const NotificationsScreen(),
      paymentBuilder: (_, rid) =>
          PaymentScreen(reservationId: int.tryParse(rid) ?? 0),
      messagesBuilder: (_) => MessagesScreen(apiBase: babifixApiBaseUrl()),
      chatRoomBuilder: (_, pid) =>
          ChatRoomScreen(name: 'Chat', peerUserId: int.tryParse(pid)),
      editProfileBuilder: (_) => EditProfileScreen(
        initialName: '',
        initialEmail: '',
        initialPhone: '',
        initialAddress: '',
        initialAvatarBytes: null,
        onSaved: () {},
      ),
      devisDetailBuilder: (_, ref) =>
          DevisDetailScreen(reservationReference: ref, onBack: () {}),
    );
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'BABIFIX Client',
      theme: _themeForMode(paletteMode),
      routerConfig: router,
    );
  }
}

class ClientHomePage extends StatefulWidget {
  const ClientHomePage({
    super.key,
    required this.paletteMode,
    required this.onPaletteChanged,
    required this.onLogout,
  });

  final AppPaletteMode paletteMode;
  final ValueChanged<AppPaletteMode> onPaletteChanged;
  final VoidCallback onLogout;

  @override
  State<ClientHomePage> createState() => _ClientHomePageState();
}

class _ClientHomePageState extends State<ClientHomePage> {
  static const _logoAsset = 'assets/images/babifix-logo.png';
  int navIndex = 0;
  int categoryIndex = 0;

  // ── Recherche et filtres services ────────────────────────────────────────
  String _searchQuery = '';
  Timer? _searchDebounce;
  final _searchCtrl = TextEditingController();
  // Filtres avancés
  double _filterMinRating = 0;
  int _filterMaxPrice = 0; // 0 = pas de limite
  String _filterSort = 'default'; // default | rating | price_asc | price_desc

  String profileName = '';
  String profileEmail = '';
  String profilePhone = '';
  String profileAddress = '';
  Uint8List? profileAvatarBytes;
  bool sessionLoggedIn = false;

  String? authToken;
  bool loadingRemote = false;
  bool _showEmptyAfterDelay = false;

  /// Onglets catégories : « Tous » + entrées API `/api/public/categories/`.
  List<CategoryTab> categoryTabs = const [
    CategoryTab(
      icon: Icons.grid_view_rounded,
      label: 'Tous',
      filterKey: 'TOUS',
    ),
  ];

  /// Données 100 % issues de l’API — aucune liste locale fictive.
  List<ClientService> services = <ClientService>[];

  /// Moyens de paiement (logos) — home + fallback public.
  List<PaymentMethodOption> paymentMethodsRemote = <PaymentMethodOption>[];

  /// Prestataires récents (carousel accueil).
  List<RecentProviderCard> recentProviders = <RecentProviderCard>[];

  /// Email support (paramètre site Django).
  String contactAdminEmail = '';

  List<ClientReservation> reservations = <ClientReservation>[];
  List<(String, String)> news = <(String, String)>[];
  List<ClientActualiteItem> actualites = <ClientActualiteItem>[];

  int _unreadChatTotal = 0;
  final ValueNotifier<List<BabifixInAppNotif>> _clientInAppNotifs =
      ValueNotifier<List<BabifixInAppNotif>>([]);

  StreamSubscription<dynamic>? _clientWsSub;
  WebSocketChannel? _clientWsChannel;
  StreamSubscription<RemoteMessage>? _clientFcmSub;
  StreamSubscription<RemoteMessage>? _clientFcmOpenedSub;

  late final PageController _recentProvidersCarouselController;

  @override
  void dispose() {
    _recentProvidersCarouselController.dispose();
    _clientInAppNotifs.dispose();
    _clientWsSub?.cancel();
    _clientWsChannel?.sink.close();
    _clientFcmSub?.cancel();
    _clientFcmOpenedSub?.cancel();
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _recentProvidersCarouselController = PageController(viewportFraction: 0.88);
    _restoreClientNotifsThenInit();
    // Chargement immédiat des catégories (sans authentification)
    _loadPublicCategories();
    // Synchronisation temps réel toutes les 3 secondes (auto-refresh)
    RealTimeSyncService.instance.startSync(intervalSeconds: 3);
    RealTimeSyncService.instance.categoriesStream.listen((_) {
      if (mounted) {
        // Auto-refresh sans afficher de bannière
        _loadRemoteData();
      }
    });
  }

  Future<void> _restoreClientNotifsThenInit() async {
    final list = await loadInAppNotifList(BabifixInAppNotifStorageKeys.client);
    if (mounted) _clientInAppNotifs.value = list;
    if (!mounted) return;
    _loadProfile();
    _initSession();
  }

  void _pushClientNotif({
    required String category,
    required String title,
    required String body,
    String? actionRoute,
    BabifixNotifSeverity severity = BabifixNotifSeverity.info,
  }) {
    final n = BabifixInAppNotif(
      id: 'c-${DateTime.now().microsecondsSinceEpoch}',
      audience: BabifixNotifAudience.client,
      category: category,
      title: title,
      body: body,
      createdAt: DateTime.now(),
      severity: severity,
      actionRoute: actionRoute,
    );
    pushInAppNotification(
      _clientInAppNotifs,
      n,
      persistStorageKey: BabifixInAppNotifStorageKeys.client,
    );
    if (severity == BabifixNotifSeverity.urgent) {
      _showClientUrgentDialog(n);
    }
  }

  void _showClientUrgentDialog(BabifixInAppNotif n) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(
            Icons.warning_amber_rounded,
            color: Colors.red.shade700,
            size: 44,
          ),
          title: Text(n.title),
          content: Text(n.body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fermer'),
            ),
            if (n.actionRoute != null && n.actionRoute!.isNotEmpty)
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _applyClientNotifRoute(n.actionRoute);
                },
                child: const Text('Voir'),
              ),
          ],
        ),
);
    );
  }
}

class _SplashScreen extends StatefulWidget {
  const _SplashScreen();

  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutBack,
      ),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1F3C),
      body: Center(
        child: AnimatedBuilder(
          animation: _scaleAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: child,
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: const Color(0xFF4CC9F0),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(
                  Icons.home_repair_service,
                  size: 64,
                  color: Color(0xFF0D1F3C),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'BABIFIX',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Services a domicile',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white70,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

  void _handleFcmNavigation(Map<String, dynamic> data) {
    if (!mounted) return;
    final type = '${data['type'] ?? ''}'.toLowerCase();
    switch (type) {
      case 'chat.message':
        _openMessages();
        break;
      case 'reservation.updated':
      case 'reservation.confirmed':
      case 'payment.success':
      case 'payment.validated':
      case 'litige.ouvert':
      case 'litige.resolved':
        setState(() => navIndex = 3);
        break;
      case 'actualite.published':
        setState(() => navIndex = 2);
        break;
      case 'provider.approved':
      case 'services':
        setState(() => navIndex = 1);
        break;
      default:
        setState(() => navIndex = 0);
    }
  }

  void _applyClientNotifRoute(String? r) {
    if (r == null || r.isEmpty) return;
    switch (r) {
      case 'messages':
        _openMessages();
        break;
      case 'actus':
        setState(() => navIndex = 2);
        break;
      case 'reservations':
        setState(() => navIndex = 3);
        break;
      case 'services':
        setState(() => navIndex = 1);
        break;
      default:
        setState(() => navIndex = 0);
    }
  }

  Future<void> _openClientInAppNotifSheet() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        maxChildSize: 0.92,
        minChildSize: 0.32,
        builder: (ctx, scrollCtrl) {
          return ValueListenableBuilder<List<BabifixInAppNotif>>(
            valueListenable: _clientInAppNotifs,
            builder: (context, all, _) {
              final items = all
                  .where((e) => e.audience == BabifixNotifAudience.client)
                  .toList();
              final unread = items.where((e) => !e.read).length;
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Vos alertes',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (unread > 0)
                          TextButton(
                            onPressed: () => markAllInAppRead(
                              _clientInAppNotifs,
                              BabifixNotifAudience.client,
                              persistStorageKey:
                                  BabifixInAppNotifStorageKeys.client,
                            ),
                            child: Text(
                              'Tout lu',
                              style: TextStyle(color: BabifixDesign.cyan),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Réservations, litiges, messages et actus — selon votre profil client.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: items.isEmpty
                        ? Center(
                            child: Text(
                              'Aucune alerte récente dans l’app.',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: scrollCtrl,
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            itemCount: items.length,
                            itemBuilder: (_, i) {
                              final n = items[i];
                              final c = babifixNotifCategoryColor(n.category);
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Material(
                                  color: n.read
                                      ? Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerHighest
                                            .withValues(alpha: 0.35)
                                      : c.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(16),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () {
                                      markOneRead(
                                        _clientInAppNotifs,
                                        n.id,
                                        persistStorageKey:
                                            BabifixInAppNotifStorageKeys.client,
                                      );
                                      Navigator.pop(ctx);
                                      _applyClientNotifRoute(n.actionRoute);
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            width: 40,
                                            height: 40,
                                            decoration: BoxDecoration(
                                              color: c.withValues(alpha: 0.15),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Icon(
                                              babifixNotifCategoryIcon(
                                                n.category,
                                              ),
                                              color: c,
                                              size: 20,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        n.title,
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          fontSize: 14,
                                                        ),
                                                      ),
                                                    ),
                                                    if (!n.read)
                                                      Container(
                                                        width: 8,
                                                        height: 8,
                                                        decoration:
                                                            BoxDecoration(
                                                              color: c,
                                                              shape: BoxShape
                                                                  .circle,
                                                            ),
                                                      ),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  n.body,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    height: 1.35,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  n.dateLabel,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => const NotificationsScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.cloud_download_outlined, size: 20),
                      label: const Text('Notifications serveur (compte)'),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _refreshUnreadChat() async {
    final t = authToken;
    if (t == null || t.isEmpty) return;
    try {
      final res = await http.get(
        Uri.parse('${babifixApiBaseUrl()}/api/messages/unread-total'),
        headers: {'Authorization': 'Bearer $t'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final n = jsonInt(data['total']);
        if (mounted) setState(() => _unreadChatTotal = n);
      }
    } catch (_) {}
  }

  Future<void> _attachClientRealtime() async {
    _clientWsSub?.cancel();
    _clientFcmSub?.cancel();
    _clientFcmOpenedSub?.cancel();
    final t = authToken;
    if (t == null || t.isEmpty || kIsWeb) return;
    try {
      final uri = Uri.parse(
        '${babifixWsBaseUrl()}/ws/client/events/?token=${Uri.encodeQueryComponent(t)}',
      );
      _clientWsChannel?.sink.close();
      _clientWsChannel = WebSocketChannel.connect(uri);
      final ch = _clientWsChannel!;
      _clientWsSub = ch.stream.listen((raw) {
        try {
          final m = jsonDecode(raw as String) as Map<String, dynamic>;
          final typ = '${m['type'] ?? ''}';
          if (typ == 'provider.approved' || typ == 'actualite.published') {
            _loadRemoteData();
            if (typ == 'provider.approved') {
              _pushClientNotif(
                category: 'actu',
                title: 'Catalogue mis à jour',
                body: 'Un nouveau prestataire est disponible près de vous.',
                actionRoute: 'services',
                severity: BabifixNotifSeverity.important,
              );
            } else {
              _pushClientNotif(
                category: 'actu',
                title: 'Actualité BABIFIX',
                body: 'Une nouvelle annonce a été publiée.',
                actionRoute: 'actus',
                severity: BabifixNotifSeverity.important,
              );
            }
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    typ == 'provider.approved'
                        ? 'Catalogue mis à jour : nouveau prestataire.'
                        : 'Nouvelle actualité BABIFIX.',
                  ),
                ),
              );
            }
          } else if (typ == 'chat.message') {
            _refreshUnreadChat();
            _pushClientNotif(
              category: 'message',
              title: 'Nouveau message',
              body: 'Votre prestataire ou le support vous a écrit.',
              actionRoute: 'messages',
            );
          } else if (typ.contains('reservation') ||
              typ.contains('booking') ||
              typ == 'prestation.updated') {
            _loadRemoteData();
            _pushClientNotif(
              category: 'demande',
              title: 'Votre réservation',
              body: 'Mise à jour sur une de vos demandes de service.',
              actionRoute: 'reservations',
              severity: BabifixNotifSeverity.important,
            );
          } else if (typ.contains('dispute') || typ == 'litige.ouvert') {
            _pushClientNotif(
              category: 'litige',
              title: 'Litige / réclamation',
              body:
                  'Une action est requise sur un dossier. Consultez vos rendez-vous.',
              actionRoute: 'reservations',
              severity: BabifixNotifSeverity.urgent,
            );
          } else if (typ == 'provider.availability_changed') {
            final payload = m['payload'] as Map<String, dynamic>? ?? {};
            final pid = payload['provider_id'] as int?;
            final dispo = payload['disponible'] as bool?;
            if (pid != null && dispo != null && mounted) {
              setState(() {
                services = services
                    .map(
                      (s) => s.providerId == pid
                          ? s.copyWith(disponible: dispo)
                          : s,
                    )
                    .toList();
                recentProviders = recentProviders
                    .map((p) => p.id == pid ? p.copyWith(disponible: dispo) : p)
                    .toList();
              });
            }
          }
        } catch (_) {}
      }, onError: (_) {});
    } catch (_) {}
    _clientFcmSub = FirebaseMessaging.onMessage.listen((msg) {
      final d = msg.data;
      final ty = '${d['type'] ?? ''}';
      if (ty == 'provider.approved' || ty == 'actualite.published') {
        _loadRemoteData();
        if (ty == 'provider.approved') {
          _pushClientNotif(
            category: 'actu',
            title: 'Nouveau prestataire',
            body: 'Le catalogue BABIFIX a été enrichi.',
            actionRoute: 'services',
            severity: BabifixNotifSeverity.important,
          );
        } else {
          _pushClientNotif(
            category: 'actu',
            title: 'Actualité',
            body: 'Nouvelle publication BABIFIX.',
            actionRoute: 'actus',
            severity: BabifixNotifSeverity.important,
          );
        }
      } else if (ty == 'chat.message') {
        _refreshUnreadChat();
        _pushClientNotif(
          category: 'message',
          title: 'Message',
          body: 'Nouveau message dans votre messagerie.',
          actionRoute: 'messages',
        );
      } else if (ty.contains('reservation') || ty.contains('booking')) {
        _loadRemoteData();
        _pushClientNotif(
          category: 'demande',
          title: 'Réservation',
          body: 'Statut ou détail d’une réservation a changé.',
          actionRoute: 'reservations',
          severity: BabifixNotifSeverity.important,
        );
      } else if (ty.contains('dispute') || ty == 'litige.ouvert') {
        _pushClientNotif(
          category: 'litige',
          title: 'Litige',
          body: 'Signalement en cours — consultez vos rendez-vous.',
          actionRoute: 'reservations',
          severity: BabifixNotifSeverity.urgent,
        );
      }
    });
    _clientFcmOpenedSub = FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      _handleFcmNavigation(msg.data);
    });

    // Message qui a lancé l'app depuis état terminé
    FirebaseMessaging.instance.getInitialMessage().then((msg) {
      if (msg != null && mounted) {
        _handleFcmNavigation(msg.data);
      }
    });
  }

  Future<void> _loadProfile() async {
    final m = await BabifixUserStore.loadProfile();
    final av = await BabifixUserStore.loadAvatarBytes();
    final logged = await BabifixUserStore.isLoggedIn();
    if (!mounted) return;
    setState(() {
      sessionLoggedIn = logged;
      profileName = (m['name'] ?? '').trim().isEmpty
          ? 'Invité'
          : (m['name'] ?? '').trim();
      profileEmail = (m['email'] ?? '').trim();
      profilePhone = (m['phone'] ?? '').trim();
      profileAddress = (m['address'] ?? '').trim();
      profileAvatarBytes = av;
    });
  }

  Future<void> _logout() async {
    _clientWsSub?.cancel();
    _clientFcmSub?.cancel();
    _clientFcmOpenedSub?.cancel();
    await BabifixUserStore.logout();
    authToken = null;
    if (mounted) {
      await _loadProfile();
      setState(() {});
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openBiometricSettings() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        decoration: BoxDecoration(
          color: _isLight ? Colors.white : const Color(0xFF0D1B2E),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 20),
            const Icon(
              Icons.fingerprint_rounded,
              size: 56,
              color: Color(0xFF4CC9F0),
            ),
            const SizedBox(height: 14),
            Text(
              'Connexion biométrique',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: _textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Activez Face ID ou l\'empreinte digitale pour accéder à votre compte rapidement.',
              style: TextStyle(color: _textSecondary, height: 1.45),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Configurer dans Paramètres'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4CC9F0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openForgotPassword() async {
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
    );
  }

  Future<void> _openEditProfile() async {
    if (!mounted) return;
    final logged = await BabifixUserStore.isLoggedIn();
    if (!logged) {
      await _openAuth();
      return;
    }
    final p = await BabifixUserStore.loadProfile();
    final av = await BabifixUserStore.loadAvatarBytes();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (ctx) => EditProfileScreen(
          initialName: p['name'] ?? '',
          initialEmail: p['email'] ?? '',
          initialPhone: p['phone'] ?? '',
          initialAddress: p['address'] ?? '',
          initialAvatarBytes: av,
          onSaved: () {
            Navigator.of(ctx).pop();
            _loadProfile();
          },
        ),
      ),
    );
  }

  bool get _isLight => widget.paletteMode == AppPaletteMode.light;
  Color get _textPrimary => _isLight ? const Color(0xFF0F172A) : Colors.white;
  Color get _textSecondary =>
      _isLight ? const Color(0xFF475569) : const Color(0xFF9CA3AF);
  Color get _cardBg =>
      _isLight ? const Color(0xFFF8FAFC) : const Color(0xFF1A1F28);

  @override
  Widget build(BuildContext context) {
    final activeKey = categoryTabs.isEmpty
        ? 'TOUS'
        : categoryTabs[categoryIndex.clamp(0, categoryTabs.length - 1)]
              .filterKey;
    final visibleServices = activeKey == 'TOUS'
        ? services
        : services
              .where((s) => babifixCategoryFilterKey(s.category) == activeKey)
              .toList();
    return Scaffold(
      extendBody: true,
      body: Container(
        decoration: BoxDecoration(
          gradient: _isLight
              ? BabifixDesign.pageGradientLight
              : BabifixDesign.pageGradientDark,
        ),
        child: navIndex == 0
            ? _buildNews()
            : navIndex == 1
            ? _buildServices(visibleServices)
            : navIndex == 2
            ? _buildActualites()
            : navIndex == 3
            ? _buildReservations()
            : _buildProfile(),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _isLight
                      ? const [Color(0xEEF8FAFF), Color(0xEEEFF4FF)]
                      : const [Color(0xE6232A3A), Color(0xE1161B2A)],
                ),
                border: Border.all(
                  color: _isLight
                      ? const Color(0x220F172A)
                      : const Color(0x55FFFFFF),
                ),
                boxShadow: [
                  BoxShadow(
                    color: _isLight
                        ? const Color(0x220F172A)
                        : const Color(0x66000000),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                children: [
                  _buildFloatingNavItem(
                    index: 0,
                    icon: Icons.home_rounded,
                    label: 'Accueil',
                  ),
                  _buildFloatingNavItem(
                    index: 1,
                    icon: Icons.home_repair_service,
                    label: 'Services',
                  ),
                  _buildFloatingNavItem(
                    index: 2,
                    icon: Icons.newspaper_rounded,
                    label: 'Actus',
                  ),
                  _buildFloatingNavItem(
                    index: 3,
                    icon: Icons.calendar_month,
                    label: 'Rendez-vous',
                  ),
                  _buildFloatingNavItem(
                    index: 4,
                    icon: Icons.person,
                    label: 'Profil',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(String title, {bool showHelp = true}) {
    final width = MediaQuery.sizeOf(context).width;
    final titleSize = width < 360
        ? 22.0
        : width < 430
        ? 24.0
        : 26.0;
    final iconColor = _isLight ? const Color(0xFF475569) : Colors.white70;
    final denseStyle = IconButton.styleFrom(
      minimumSize: const Size(40, 40),
      padding: const EdgeInsets.all(8),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: _isLight ? const Color(0x120F172A) : const Color(0x1AFFFFFF),
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 4, 10),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  image: const DecorationImage(
                    image: AssetImage(_logoAsset),
                    fit: BoxFit.cover,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: BabifixDesign.cyan.withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: titleSize,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: _textPrimary,
                    height: 1.1,
                  ),
                ),
              ),
              ValueListenableBuilder<List<BabifixInAppNotif>>(
                valueListenable: _clientInAppNotifs,
                builder: (context, _, __) {
                  final unread = countUnreadInApp(
                    _clientInAppNotifs,
                    BabifixNotifAudience.client,
                  );
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      IconButton(
                        tooltip: 'Notifications',
                        style: denseStyle,
                        onPressed: _openClientInAppNotifSheet,
                        icon: Icon(
                          Icons.notifications_rounded,
                          size: 22,
                          color: iconColor,
                        ),
                      ),
                      if (unread > 0)
                        Positioned(
                          right: 4,
                          top: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF3B30),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _isLight
                                    ? Colors.white
                                    : const Color(0xFF1E293B),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              unread > 99 ? '99+' : '$unread',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              IconButton(
                tooltip: 'Messages',
                style: denseStyle,
                onPressed: _openMessages,
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 22,
                      color: iconColor,
                    ),
                    if (_unreadChatTotal > 0)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: _unreadChatTotal > 9 ? 4 : 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF3B30),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white, width: 1),
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          child: Text(
                            _unreadChatTotal > 99 ? '99+' : '$_unreadChatTotal',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (showHelp || contactAdminEmail.isNotEmpty)
                PopupMenuButton<String>(
                  tooltip: 'Plus',
                  offset: const Offset(0, 44),
                  icon: Icon(
                    Icons.more_horiz_rounded,
                    size: 24,
                    color: iconColor,
                  ),
                  onSelected: (value) {
                    if (value == 'help') _showHelpSheet();
                    if (value == 'support') _contactAdminMail();
                  },
                  itemBuilder: (context) => [
                    if (showHelp)
                      PopupMenuItem(
                        value: 'help',
                        child: Row(
                          children: [
                            Icon(
                              Icons.help_outline_rounded,
                              size: 20,
                              color: iconColor,
                            ),
                            const SizedBox(width: 12),
                            const Text('Aide'),
                          ],
                        ),
                      ),
                    if (contactAdminEmail.isNotEmpty)
                      PopupMenuItem(
                        value: 'support',
                        child: Row(
                          children: [
                            Icon(
                              Icons.support_agent_rounded,
                              size: 20,
                              color: iconColor,
                            ),
                            const SizedBox(width: 12),
                            const Text('Contacter l’admin'),
                          ],
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
            Text(
              'Aide BABIFIX',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: _textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Comment utiliser l’app',
              style: TextStyle(color: _textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 16),
            _HelpRow(
              icon: Icons.home_repair_service,
              title: 'Réserver',
              body:
                  'Onglet Services : choisissez une prestation, puis Réserver. Vous pouvez indiquer le mode de paiement et un message.',
            ),
            _HelpRow(
              icon: Icons.calendar_month,
              title: 'Suivre vos rendez-vous',
              body:
                  'Onglet Rendez-vous : statut, paiement espèces, notation après prestation terminée.',
            ),
            _HelpRow(
              icon: Icons.chat_bubble_outline,
              title: 'Messages',
              body:
                  'Échangez avec le prestataire depuis l’icône message en haut à droite.',
            ),
            _HelpRow(
              icon: Icons.palette_outlined,
              title: 'Thème & coordonnées',
              body:
                  'Profil → Paramètres : thème clair / bleu BABIFIX, téléphone et adresse d’intervention.',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() => navIndex = 1);
              },
              icon: const Icon(Icons.shopping_bag_outlined),
              label: const Text('Voir les services'),
            ),
          ],
        ),
      ),
    );
  }

  /// Accueil : un seul scroll vertical (évite les bugs Windows où seul le bas défilait).
  Widget _buildNews() {
    return RefreshIndicator(
      color: const Color(0xFF4CC9F0),
      onRefresh: _loadRemoteData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTopBar('Accueil'),
            _buildHomeHero(),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: SingleChildScrollView(
                primary: false,
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _HomeQuickChip(
                      icon: Icons.calendar_month_rounded,
                      label: 'Mes RDV',
                      isLight: _isLight,
                      onTap: () => setState(() => navIndex = 3),
                    ),
                    const SizedBox(width: 10),
                    _HomeQuickChip(
                      icon: Icons.newspaper_rounded,
                      label: 'Actus',
                      isLight: _isLight,
                      onTap: () => setState(() => navIndex = 2),
                    ),
                    const SizedBox(width: 10),
                    _HomeQuickChip(
                      icon: Icons.chat_bubble_outline_rounded,
                      label: 'Messages',
                      isLight: _isLight,
                      onTap: _openMessages,
                    ),
                  ],
                ),
              ),
            ),
            if (recentProviders.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 22,
                      decoration: BoxDecoration(
                        color: BabifixDesign.cyan,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Nouveaux prestataires',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: _textPrimary,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 132,
                child: PageView.builder(
                  controller: _recentProvidersCarouselController,
                  itemCount: recentProviders.length,
                  padEnds: false,
                  itemBuilder: (context, i) {
                    final p = recentProviders[i];
                    final img = p.imageUrl.isNotEmpty ? p.imageUrl : '';
                    return Padding(
                      padding: EdgeInsets.only(
                        left: i == 0 ? 16 : 8,
                        right: 8,
                        bottom: 6,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: _isLight
                                  ? const Color(0x120F172A)
                                  : const Color(0x30000000),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Material(
                          color: _cardBg,
                          borderRadius: BorderRadius.circular(20),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () {
                              if (p.id > 0) {
                                Navigator.of(context).push<void>(
                                  MaterialPageRoute(
                                    builder: (_) => ProviderProfileScreen(
                                      providerId: p.id,
                                      onStartReservation: (service) async {
                                        final result =
                                            await Navigator.of(
                                              context,
                                            ).push<Map<String, dynamic>?>(
                                              MaterialPageRoute(
                                                builder: (_) => BookingFlowScreen(
                                                  serviceTitle: service.title,
                                                  servicePrice: service.price,
                                                  onConfirm: (data) async {
                                                    final created =
                                                        await _createReservation(
                                                          service,
                                                          flowData: data,
                                                        );
                                                    if (created && mounted) {
                                                      setState(
                                                        () => navIndex = 3,
                                                      );
                                                    }
                                                    return created
                                                        ? {'ok': true}
                                                        : {'ok': false};
                                                  },
                                                ),
                                              ),
                                            );
                                        return result?['ok'] == true;
                                      },
                                    ),
                                  ),
                                );
                              } else {
                                setState(() {
                                  navIndex = 1;
                                  categoryIndex = 0;
                                });
                              }
                            },
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: _isLight
                                      ? const Color(0x140F172A)
                                      : const Color(0x12FFFFFF),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Hero(
                                    tag: 'babifix-recent-${p.id}',
                                    child: ClipRRect(
                                      borderRadius:
                                          const BorderRadius.horizontal(
                                            left: Radius.circular(19),
                                          ),
                                      child: SizedBox(
                                        width: 100,
                                        height: double.infinity,
                                        child: img.isNotEmpty
                                            ? Image.network(
                                                img,
                                                fit: BoxFit.cover,
                                              )
                                            : DecoratedBox(
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                    colors: [
                                                      BabifixDesign.navy,
                                                      BabifixDesign.navy
                                                          .withValues(
                                                            alpha: 0.85,
                                                          ),
                                                    ],
                                                  ),
                                                ),
                                                child: const Icon(
                                                  Icons.person_rounded,
                                                  size: 40,
                                                  color: Colors.white38,
                                                ),
                                              ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        12,
                                        10,
                                        14,
                                        10,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            p.nom,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 15,
                                              color: _textPrimary,
                                              letterSpacing: -0.2,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            p.specialite,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: BabifixDesign.ciBlue,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            p.ville,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: _textSecondary.withValues(
                                                alpha: 0.95,
                                              ),
                                            ),
                                          ),
                                          if (p.tarif != null) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              formatFcfa(p.tarif!.round()),
                                              style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 13,
                                                color: _isLight
                                                    ? BabifixDesign.ciBlue
                                                    : BabifixDesign.cyan,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            // ── CTA vers l'onglet Services ──────────────────────────────
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: GestureDetector(
                onTap: () => setState(() {
                  navIndex = 1;
                  categoryIndex = 0;
                }),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [BabifixDesign.ciBlue, BabifixDesign.cyan],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: BabifixDesign.cyan.withValues(alpha: 0.25),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.home_repair_service,
                          color: Colors.white,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Explorer les services',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                '${categoryTabs.length > 1 ? categoryTabs.length - 1 : ''} catégories disponibles',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_ios_rounded,
                          color: Colors.white70,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _buildHowItWorksSection(),
            _buildTrustPaymentStrip(),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'À la une',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: _textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Offres, actus et nouveautés BABIFIX',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: _textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  for (int index = 0; index < actualites.length; index++)
                    _buildFeaturedNewsCard(index),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── ACCUEIL : Hero banner personnalisé ───────────────────────────────────
  Widget _buildHomeHero() {
    final firstName = profileName.split(' ').first;
    final greet = (firstName.isEmpty || firstName == 'Invité')
        ? 'Bienvenue sur BABIFIX'
        : 'Bonjour, $firstName !';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _isLight
                ? [BabifixDesign.navy, const Color(0xFF0B3E72)]
                : [const Color(0xFF0B1F3A), const Color(0xFF0A2B50)],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: BabifixDesign.navy.withValues(alpha: 0.38),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Badge localisation
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: BabifixDesign.ciOrange.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: BabifixDesign.ciOrange.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.location_on_rounded,
                    size: 12,
                    color: BabifixDesign.ciOrange,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Côte d\'Ivoire',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: BabifixDesign.ciOrange,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              greet,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Trouvez un artisan qualifié et vérifiable\nen quelques secondes.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.72),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            // Barre de recherche simulée → onglet Services
            GestureDetector(
              onTap: () => setState(() => navIndex = 1),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      color: Colors.white.withValues(alpha: 0.65),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Plombier, électricien, peintre…',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: BabifixDesign.cyan,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Chercher',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: BabifixDesign.navy,
                        ),
                      ),
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

  // ── ACCUEIL : Catégories en accès rapide ─────────────────────────────────
  Widget _buildCategoriesSection() {
    if (categoryTabs.length <= 1) return const SizedBox.shrink();
    final cats = categoryTabs.skip(1).toList(); // skip "Tous"
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                  color: BabifixDesign.ciOrange,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Nos services',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _textPrimary,
                  letterSpacing: -0.4,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => navIndex = 1),
                child: Text(
                  'Voir tout',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: BabifixDesign.cyan,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 90,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: cats.length,
            itemBuilder: (_, i) {
              final cat = cats[i];
              return GestureDetector(
                onTap: () {
                  setState(() {
                    categoryIndex = i + 1;
                    navIndex = 1;
                  });
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: _cardBg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: _isLight
                          ? const Color(0x140F172A)
                          : const Color(0x15FFFFFF),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _isLight
                            ? const Color(0x0A0F172A)
                            : const Color(0x20000000),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(cat.icon, color: BabifixDesign.cyan, size: 28),
                      const SizedBox(height: 6),
                      Text(
                        cat.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── ACCUEIL : Comment ça marche (3 étapes) ───────────────────────────────
  Widget _buildHowItWorksSection() {
    const steps = [
      (Icons.search_rounded, 'Recherchez', '0xFF0066B3'),
      (Icons.calendar_today_rounded, 'Réservez', '0xFFE87722'),
      (Icons.verified_rounded, 'Profitez', '0xFF009A44'),
    ];
    const stepColors = [
      Color(0xFF0066B3),
      Color(0xFFE87722),
      Color(0xFF009A44),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                  color: BabifixDesign.ciGreen,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Comment ça marche',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _textPrimary,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _isLight
                    ? const Color(0x140F172A)
                    : const Color(0x12FFFFFF),
              ),
            ),
            child: Row(
              children: List.generate(5, (i) {
                if (i.isOdd) {
                  return Expanded(
                    child: Container(
                      height: 1,
                      margin: const EdgeInsets.only(bottom: 20),
                      color: _isLight
                          ? const Color(0xFFE2E8F0)
                          : const Color(0xFF374151),
                    ),
                  );
                }
                final idx = i ~/ 2;
                final c = stepColors[idx];
                final step = steps[idx];
                return Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c.withValues(alpha: 0.10),
                          border: Border.all(color: c.withValues(alpha: 0.25)),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(step.$1, color: c, size: 26),
                            Positioned(
                              top: 0,
                              right: 0,
                              child: Container(
                                width: 17,
                                height: 17,
                                decoration: BoxDecoration(
                                  color: c,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '${idx + 1}',
                                    style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        step.$2,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _textPrimary,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // ── ACCUEIL : Bande de confiance Mobile Money ────────────────────────────
  Widget _buildTrustPaymentStrip() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: _isLight
              ? const Color(0xFFF0FDF4)
              : const Color(0xFF052E16).withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isLight
                ? const Color(0xFFBBF7D0)
                : BabifixDesign.ciGreen.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.lock_rounded, size: 18, color: BabifixDesign.ciGreen),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Paiements 100 % sécurisés en FCFA',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: _isLight
                      ? const Color(0xFF166534)
                      : BabifixDesign.ciGreen,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const BabifixMobileMoneyLogoStrip(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildFeaturedNewsCard(int index) {
    if (index >= actualites.length) return const SizedBox.shrink();
    final item = actualites[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TweenAnimationBuilder<double>(
        duration: Duration(milliseconds: 320 + (index * 70)),
        tween: Tween(begin: 0, end: 1),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) => Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 20),
            child: child,
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: _isLight
                  ? const Color(0x140F172A)
                  : const Color(0x12FFFFFF),
            ),
            boxShadow: [
              BoxShadow(
                color: _isLight
                    ? const Color(0x140F172A)
                    : const Color(0x30000000),
                blurRadius: 18,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 168,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  image: DecorationImage(
                    image: _imageProvider(item.imageUrl),
                    fit: BoxFit.cover,
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.12),
                        Colors.black.withValues(alpha: 0.5),
                      ],
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        top: 12,
                        left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            item.categorieTag,
                            style: TextStyle(
                              color: BabifixDesign.navy,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.calendar_today,
                                size: 14,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                item.dateLabel,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.titre,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.description,
                      style: TextStyle(color: _textSecondary, height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildServices(List<ClientService> visibleServices) {
    // Filtrage + tri
    var filtered = visibleServices.where((s) {
      if (_searchQuery.isNotEmpty &&
          !s.title.toLowerCase().contains(_searchQuery) &&
          !s.category.toLowerCase().contains(_searchQuery))
        return false;
      if (_filterMinRating > 0 && s.rating < _filterMinRating) return false;
      if (_filterMaxPrice > 0 && s.price > _filterMaxPrice) return false;
      return true;
    }).toList();
    if (_filterSort == 'rating') {
      filtered.sort((a, b) => b.rating.compareTo(a.rating));
    } else if (_filterSort == 'price_asc') {
      filtered.sort((a, b) => a.price.compareTo(b.price));
    } else if (_filterSort == 'price_desc') {
      filtered.sort((a, b) => b.price.compareTo(a.price));
    }

    return RefreshIndicator(
      color: const Color(0xFF4CC9F0),
      onRefresh: _loadRemoteData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTopBar('Services'),
            // ── Barre de recherche ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (value) {
                  _searchDebounce?.cancel();
                  _searchDebounce = Timer(
                    const Duration(milliseconds: 300),
                    () => setState(() => _searchQuery = value.toLowerCase()),
                  );
                },
                decoration: InputDecoration(
                  hintText: 'Rechercher un service…',
                  hintStyle: TextStyle(
                    color: _textSecondary.withValues(alpha: 0.6),
                  ),
                  prefixIcon: Icon(Icons.search_rounded, color: _textSecondary),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: _cardBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: _isLight
                          ? const Color(0x140F172A)
                          : const Color(0x15FFFFFF),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: _isLight
                          ? const Color(0x140F172A)
                          : const Color(0x15FFFFFF),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: BabifixDesign.cyan, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
            ),
            // ── Filtres avancés ──────────────────────────────────────────
            _buildFilterChipsRow(filtered.length),
            if (categoryTabs.isNotEmpty)
              CategoryStrip(
                categories: categoryTabs,
                active: categoryIndex.clamp(0, categoryTabs.length - 1),
                onTap: (index) => setState(() => categoryIndex = index),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Catalogue',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: _textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      (loadingRemote && services.isEmpty)
                          ? 'Chargement du catalogue...'
                          : _searchQuery.isNotEmpty
                          ? '${filtered.length} résultat(s) pour "$_searchQuery"'
                          : filtered.isEmpty
                          ? 'Aucun service dans cette catégorie'
                          : 'Réservez en un clic — ${filtered.length} prestation(s)',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: _textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  if (loadingRemote && services.isEmpty)
                    ...List<Widget>.generate(
                      3,
                      (i) => _buildCatalogSkeletonCard(i),
                    ),
                  if (!loadingRemote &&
                      filtered.isEmpty &&
                      _showEmptyAfterDelay)
                    _searchQuery.isNotEmpty
                        ? _buildSearchEmptyState()
                        : _buildCategoryEmptyState(),
                  for (int index = 0; index < filtered.length; index++)
                    _buildCatalogServiceCard(filtered[index], index),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _hasActiveFilters =>
      _filterMinRating > 0 || _filterMaxPrice > 0 || _filterSort != 'default';

  Widget _buildFilterChipsRow(int count) {
    final sortLabels = {
      'default': 'Par défaut',
      'rating': 'Mieux notés',
      'price_asc': 'Prix croissant',
      'price_desc': 'Prix décroissant',
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
      child: Row(
        children: [
          // Filter icon button
          GestureDetector(
            onTap: _openFilterSheet,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: _hasActiveFilters
                    ? BabifixDesign.ciOrange.withValues(alpha: 0.15)
                    : _cardBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _hasActiveFilters
                      ? BabifixDesign.ciOrange
                      : _textSecondary.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.tune_rounded,
                    size: 16,
                    color: _hasActiveFilters
                        ? BabifixDesign.ciOrange
                        : _textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Filtres${_hasActiveFilters ? ' ●' : ''}',
                    style: TextStyle(
                      fontSize: 13,
                      color: _hasActiveFilters
                          ? BabifixDesign.ciOrange
                          : _textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Sort chip
          if (_filterSort != 'default')
            _filterChip(
              label: sortLabels[_filterSort] ?? _filterSort,
              onRemove: () => setState(() => _filterSort = 'default'),
            ),
          if (_filterMinRating > 0)
            _filterChip(
              label: '≥ ${_filterMinRating.toStringAsFixed(1)} ★',
              onRemove: () => setState(() => _filterMinRating = 0),
            ),
          if (_filterMaxPrice > 0)
            _filterChip(
              label: '≤ ${_filterMaxPrice.toStringAsFixed(0)} FCFA',
              onRemove: () => setState(() => _filterMaxPrice = 0),
            ),
          if (_hasActiveFilters) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => setState(() {
                _filterMinRating = 0;
                _filterMaxPrice = 0;
                _filterSort = 'default';
              }),
              child: Text(
                'Effacer tout',
                style: TextStyle(
                  fontSize: 12,
                  color: _textSecondary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _filterChip({required String label, required VoidCallback onRemove}) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: BabifixDesign.cyan.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: BabifixDesign.cyan.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: BabifixDesign.cyan,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Icon(
              Icons.close_rounded,
              size: 14,
              color: BabifixDesign.cyan,
            ),
          ),
        ],
      ),
    );
  }

  void _openFilterSheet() {
    double tempMinRating = _filterMinRating;
    int tempMaxPrice = _filterMaxPrice;
    String tempSort = _filterSort;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            20,
            24,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Filtrer les services',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      setSheetState(() {
                        tempMinRating = 0;
                        tempMaxPrice = 0;
                        tempSort = 'default';
                      });
                    },
                    child: const Text('Réinitialiser'),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 8),
              const Text(
                'Trier par',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final entry in {
                    'default': 'Par défaut',
                    'rating': 'Mieux notés',
                    'price_asc': 'Prix ↑',
                    'price_desc': 'Prix ↓',
                  }.entries)
                    ChoiceChip(
                      label: Text(entry.value),
                      selected: tempSort == entry.key,
                      onSelected: (_) =>
                          setSheetState(() => tempSort = entry.key),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text(
                    'Note minimale : ',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  Text(
                    tempMinRating == 0
                        ? 'Toutes'
                        : '${tempMinRating.toStringAsFixed(1)} ★',
                  ),
                ],
              ),
              Slider(
                value: tempMinRating,
                min: 0,
                max: 5,
                divisions: 10,
                label: tempMinRating == 0
                    ? 'Toutes'
                    : '${tempMinRating.toStringAsFixed(1)} ★',
                activeColor: BabifixDesign.ciOrange,
                onChanged: (v) => setSheetState(() => tempMinRating = v),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text(
                    'Prix max (FCFA) : ',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  Text(
                    tempMaxPrice == 0
                        ? 'Sans limite'
                        : '${tempMaxPrice.toStringAsFixed(0)} FCFA',
                  ),
                ],
              ),
              Slider(
                value: tempMaxPrice.toDouble(),
                min: 0,
                max: 100000,
                divisions: 20,
                label: tempMaxPrice == 0
                    ? 'Sans limite'
                    : '${tempMaxPrice.toStringAsFixed(0)} FCFA',
                activeColor: BabifixDesign.ciOrange,
                onChanged: (v) => setSheetState(() => tempMaxPrice = v.round()),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: BabifixDesign.ciOrange,
                  ),
                  onPressed: () {
                    setState(() {
                      _filterMinRating = tempMinRating;
                      _filterMaxPrice = tempMaxPrice;
                      _filterSort = tempSort;
                    });
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('Appliquer'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCatalogSkeletonCard(int index) {
    return _buildShimmerCard(index);
  }

  Widget _buildShimmerCard(int index) {
    final base = _isLight ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B);
    final hi = _isLight ? const Color(0xFFF8FAFC) : const Color(0xFF334155);
    return TweenAnimationBuilder<double>(
      key: ValueKey('shimmer_$index'),
      duration: Duration(milliseconds: 1400 + (index * 180)),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.linear,
      onEnd: () => setState(() {}),
      builder: (context, t, _) {
        final sweep = ((t * 3) - 1).clamp(0.0, 1.0);
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(-1.5 + sweep * 3, 0),
              end: Alignment(-0.5 + sweep * 3, 0),
              colors: [base, hi, base],
            ).createShader(bounds);
          },
          child: Container(
            height: 168,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: base,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 56,
            color: _textSecondary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 14),
          Text(
            'Aucun résultat pour "$_searchQuery"',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Essayez un autre mot-clé ou consultez\ntoutes les catégories.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _textSecondary, height: 1.45),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () {
              _searchCtrl.clear();
              setState(() {
                _searchQuery = '';
                categoryIndex = 0;
              });
            },
            icon: const Icon(Icons.grid_view_rounded, size: 18),
            label: const Text('Voir tout le catalogue'),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryEmptyState() {
    final idx = categoryTabs.isEmpty
        ? 0
        : categoryIndex.clamp(0, categoryTabs.length - 1);
    final tab = categoryTabs.isNotEmpty ? categoryTabs[idx] : null;
    final catColor = tab?.color ?? BabifixDesign.cyan;
    final catIcon = tab?.icon ?? Icons.home_repair_service;
    final catLabel = tab?.label ?? '';
    final isAll = catLabel == 'Tous' || catLabel.isEmpty;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    catColor.withValues(alpha: 0.2),
                    catColor.withValues(alpha: 0.05),
                  ],
                ),
                border: Border.all(
                  color: catColor.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: Icon(catIcon, size: 44, color: catColor),
            ),
            const SizedBox(height: 20),
            Text(
              isAll
                  ? 'Aucun prestataire\ndisponible pour l\'instant'
                  : 'Aucun prestataire\nen $catLabel pour l\'instant',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'De nouveaux prestataires arrivent bientôt.\nExplore les autres catégories !',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: _textSecondary,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 24),
            if (!isAll)
              OutlinedButton.icon(
                onPressed: () => setState(() => categoryIndex = 0),
                icon: const Icon(Icons.grid_view_rounded, size: 16),
                label: const Text('Voir tout'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: BabifixDesign.cyan,
                  side: BorderSide(color: BabifixDesign.cyan),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCatalogServiceCard(ClientService item, int index) {
    final priceColor = _isLight ? BabifixDesign.ciBlue : BabifixDesign.cyan;
    final outlineStyle = OutlinedButton.styleFrom(
      foregroundColor: _textPrimary,
      side: BorderSide(
        color: BabifixDesign.cyan.withValues(alpha: _isLight ? 0.55 : 0.65),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
    final filledStyle = FilledButton.styleFrom(
      backgroundColor: BabifixDesign.cyan,
      foregroundColor: BabifixDesign.navy,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
    );
    return Opacity(
      opacity: item.disponible ? 1.0 : 0.45,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 220 + (index * 40)),
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: item.disponible
                ? (_isLight ? const Color(0x140F172A) : const Color(0x12FFFFFF))
                : (_isLight
                      ? const Color(0x30CC0000)
                      : const Color(0x30FF4444)),
          ),
          boxShadow: [
            BoxShadow(
              color: _isLight
                  ? const Color(0x0F0F172A)
                  : const Color(0x24000000),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Hero(
              tag: 'babifix-service-${item.providerId}',
              child: Material(
                color: Colors.transparent,
                child: Container(
                  height: 160,
                  decoration: BoxDecoration(
                    color: item.color,
                    image: DecorationImage(
                      image: _imageProvider(item.imageUrl),
                      fit: BoxFit.cover,
                      colorFilter: ColorFilter.mode(
                        Colors.black.withValues(alpha: 0.22),
                        BlendMode.darken,
                      ),
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        top: 12,
                        left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.94),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            item.category,
                            style: TextStyle(
                              color: BabifixDesign.navy,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.schedule_rounded,
                                size: 14,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                item.duration,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (!item.disponible)
                        Positioned.fill(
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.45),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF4444),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'Indisponible',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: _textPrimary,
                      letterSpacing: -0.2,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        formatFcfa(item.price),
                        style: TextStyle(
                          color: priceColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(
                        Icons.star_rounded,
                        size: 18,
                        color: Colors.amber.shade600,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${item.rating}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _textPrimary,
                        ),
                      ),
                    ],
                  ),
                  if (item.verified) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _isLight
                            ? const Color(0xFFDCFCE7)
                            : const Color(0xFF14532D).withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Prestataire vérifié',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _isLight
                              ? const Color(0xFF166534)
                              : const Color(0xFF86EFAC),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: outlineStyle,
                          onPressed: () => Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => ServiceDetailScreen(
                                service: item,
                                isLight: _isLight,
                                onReserve: () =>
                                    Navigator.of(context).push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => BookingFlowScreen(
                                          serviceTitle: item.title,
                                          servicePrice: item.price,
                                          onConfirm: (data) async {
                                            final ok = await _createReservation(
                                              item,
                                              flowData: data,
                                            );
                                            if (ok && mounted)
                                              setState(() => navIndex = 3);
                                            return ok
                                                ? {'ok': true}
                                                : {'ok': false};
                                          },
                                        ),
                                      ),
                                    ),
                              ),
                            ),
                          ),
                          icon: const Icon(
                            Icons.info_outline_rounded,
                            size: 18,
                          ),
                          label: const Text('Détails'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          style: filledStyle,
                          onPressed: item.disponible
                              ? () => Navigator.of(context).push<void>(
                                  MaterialPageRoute(
                                    builder: (_) => BookingFlowScreen(
                                      serviceTitle: item.title,
                                      servicePrice: item.price,
                                      onConfirm: (data) async {
                                        final ok = await _createReservation(
                                          item,
                                          flowData: data,
                                        );
                                        if (ok && mounted)
                                          setState(() => navIndex = 3);
                                        return ok
                                            ? {'ok': true}
                                            : {'ok': false};
                                      },
                                    ),
                                  ),
                                )
                              : null,
                          child: const Text('Réserver'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ), // AnimatedContainer
    ); // Opacity
  }

  String _paymentLabelClient(String code) {
    switch (code) {
      case 'ESPECES':
        return 'Espèces';
      case 'MOBILE_MONEY':
        return 'Mobile Money';
      case 'CARTE':
        return 'Carte';
      default:
        return code.isEmpty ? '—' : code;
    }
  }

  Widget _buildReservations() {
    return Column(
      children: [
        _buildTopBar('Rendez-vous'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mes réservations',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: _textPrimary,
                  ),
                ),
                Text(
                  '${reservations.length} élément(s) — tirez pour actualiser',
                  style: TextStyle(fontSize: 13, color: _textSecondary),
                ),
              ],
            ),
          ),
        ),
        if (loadingRemote) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: reservations.isEmpty
              ? RefreshIndicator(
                  color: const Color(0xFF4CC9F0),
                  onRefresh: _loadRemoteData,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(24, 40, 24, 120),
                    children: [
                      Icon(
                        Icons.event_busy_rounded,
                        size: 72,
                        color: _textSecondary.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Aucune réservation pour l’instant',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: _textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Parcourez le catalogue et réservez une prestation. Elle apparaîtra ici.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _textSecondary, height: 1.4),
                      ),
                      const SizedBox(height: 24),
                      Center(
                        child: FilledButton.icon(
                          onPressed: () => setState(() => navIndex = 1),
                          icon: const Icon(Icons.home_repair_service_rounded),
                          label: const Text('Voir les services'),
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: const Color(0xFF4CC9F0),
                  onRefresh: _loadRemoteData,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                    itemCount: reservations.length,
                    itemBuilder: (context, index) {
                      final r = reservations[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _cardBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _isLight
                                ? const Color(0x120F172A)
                                : const Color(0x22FFFFFF),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    r.title,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: _textPrimary,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE0F2FE),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _paymentLabelClient(r.paymentType),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0369A1),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              r.whenLabel,
                              style: TextStyle(
                                color: _textSecondary,
                                fontSize: 13,
                              ),
                            ),
                            if (r.disputeOuverte) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Litige signalé — suivi avec BABIFIX',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.orange.shade800,
                                ),
                              ),
                            ],
                            if (r.rated) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Avis laissé',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _textSecondary,
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Text(
                                  r.amount,
                                  style: const TextStyle(
                                    color: Color(0xFF7EC8E3),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const Spacer(),
                                StatusPill(
                                  text: r.status == 'DEVIS_ENVOYE'
                                      ? 'Devis re\u00e7u'
                                      : r.status,
                                ),
                              ],
                            ),
                            if (r.canConfirmService ||
                                r.canPay ||
                                r.canRate ||
                                r.canViewDevis ||
                                r.canAcceptDevis ||
                                _canDeclareCash(r)) ...[
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  if (r.canConfirmService)
                                    FilledButton(
                                      onPressed: () =>
                                          _confirmPrestationClient(r),
                                      child: const Text(
                                        'Confirmer la prestation',
                                      ),
                                    ),
                                  if (r.canViewDevis || r.canAcceptDevis)
                                    FilledButton.icon(
                                      onPressed: () {
                                        Navigator.of(context).push<void>(
                                          MaterialPageRoute(
                                            builder: (_) => DevisDetailScreen(
                                              reservationReference: r.reference,
                                              onBack: () =>
                                                  Navigator.pop(context),
                                            ),
                                          ),
                                        );
                                      },
                                      icon: const Icon(
                                        Icons.description_outlined,
                                        size: 18,
                                      ),
                                      label: Text(
                                        r.canAcceptDevis
                                            ? 'Voir et accepter le devis'
                                            : 'Voir le devis',
                                      ),
                                    ),
                                  if (r.canPay)
                                    FilledButton.tonal(
                                      onPressed: () {
                                        if (r.id > 0) {
                                          Navigator.of(context).push<void>(
                                            MaterialPageRoute(
                                              builder: (_) => PaymentScreen(
                                                reservationId: r.id,
                                                serviceTitle: r.title,
                                              ),
                                            ),
                                          );
                                        } else {
                                          _openPostPrestationPaySheet(r);
                                        }
                                      },
                                      child: const Text('Choisir le paiement'),
                                    ),
                                  if (r.canRate)
                                    OutlinedButton.icon(
                                      onPressed: () => _rateReservation(r),
                                      icon: const Icon(
                                        Icons.star_outline,
                                        size: 18,
                                      ),
                                      label: const Text('Noter le prestataire'),
                                    ),
                                  if (_canDeclareCash(r))
                                    FilledButton.tonal(
                                      onPressed: () => _declareCashPayment(r),
                                      child: const Text(
                                        'J\'ai payé en espèces',
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildActualites() {
    return Column(
      children: [
        _buildTopBar('Actualités'),
        if (loadingRemote) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: actualites.isEmpty
              ? RefreshIndicator(
                  onRefresh: _loadRemoteData,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(24, 40, 24, 120),
                    children: [
                      Icon(
                        Icons.article_outlined,
                        size: 72,
                        color: _textSecondary.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Aucune actualité publiée',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: _textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'L’équipe BABIFIX publiera ici les annonces et mises à jour.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _textSecondary, height: 1.4),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: const Color(0xFF4CC9F0),
                  onRefresh: _loadRemoteData,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                    itemCount: actualites.length,
                    itemBuilder: (context, index) {
                      final a = actualites[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Material(
                          color: _cardBg,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _openActualiteDetail(a),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (a.imageUrl.isNotEmpty)
                                  ClipRRect(
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(16),
                                    ),
                                    child: AspectRatio(
                                      aspectRatio: 16 / 9,
                                      child: Image.network(
                                        a.imageUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(
                                          color: const Color(0xFFE2E8F0),
                                          child: const Icon(
                                            Icons.image_not_supported_outlined,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        a.categorieTag.replaceAll('_', ' '),
                                        style: TextStyle(
                                          fontSize: 0.75 * 16,
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF0284C7),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        a.titre,
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          color: _textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        a.description,
                                        maxLines: 4,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: _textSecondary,
                                          height: 1.4,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        a.dateLabel,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: _textSecondary.withValues(
                                            alpha: 0.85,
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
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _openActualiteDetail(ClientActualiteItem a) async {
    final t = authToken;
    if (t == null) return;
    try {
      final res = await http.get(
        Uri.parse('${babifixApiBaseUrl()}/api/client/actualites/${a.id}'),
        headers: {'Authorization': 'Bearer $t'},
      );
      if (res.statusCode != 200 || !mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final item = data['item'] as Map<String, dynamic>? ?? {};
      final full = ClientActualiteItem(
        id: jsonInt(item['id']),
        titre: '${item['titre'] ?? ''}',
        description: '${item['description'] ?? ''}',
        imageUrl: '${item['image_url'] ?? ''}',
        categorieTag: '${item['categorie_tag'] ?? ''}',
        dateLabel: '${item['date_publication'] ?? ''}'.split('T').first,
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (ctx) =>
              ActualiteDetailScreen(item: full, isLight: _isLight),
        ),
      );
    } catch (_) {}
  }

  Widget _buildProfile() {
    final totalEscrow = reservations
        .where((r) => r.status == 'En cours')
        .map(
          (e) => int.tryParse(e.amount.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
        )
        .fold<int>(0, (sum, value) => sum + value);
    return Column(
      children: [
        _buildTopBar('Profil'),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadRemoteData,
            color: BabifixDesign.cyan,
            backgroundColor: _cardBg,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                // ── Hero card client premium ────────────────────────────
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: _isLight
                          ? const [Color(0xFFE0F2FE), Color(0xFFF0F9FF)]
                          : const [Color(0xFF0C1729), Color(0xFF162032)],
                    ),
                    border: Border.all(
                      color: _isLight
                          ? const Color(0xFF7DD3FC)
                          : const Color(0x334CC9F0),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: BabifixDesign.cyan.withValues(
                          alpha: _isLight ? 0.1 : 0.07,
                        ),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [Color(0xFF4CC9F0), Color(0xFF0284C7)],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: BabifixDesign.cyan.withValues(
                                    alpha: 0.35,
                                  ),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: profileAvatarBytes != null
                                ? ClipOval(
                                    child: Image.memory(
                                      profileAvatarBytes!,
                                      fit: BoxFit.cover,
                                      width: 64,
                                      height: 64,
                                    ),
                                  )
                                : Center(
                                    child: Text(
                                      profileName.isNotEmpty
                                          ? profileName[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 24,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  profileName.isEmpty
                                      ? 'Mon compte'
                                      : profileName,
                                  style: TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w900,
                                    color: _textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  profileEmail.isEmpty
                                      ? 'Connectez-vous ou créez un compte'
                                      : profileEmail,
                                  style: TextStyle(
                                    color: _textSecondary,
                                    fontSize: 13,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (profilePhone.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.phone_rounded,
                                        size: 11,
                                        color: _textSecondary,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        profilePhone,
                                        style: TextStyle(
                                          color: _textSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: _openEditProfile,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF4CC9F0),
                                    Color(0xFF0284C7),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'Modifier',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (sessionLoggedIn) ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            _MiniStatChip(
                              label: 'Réservations',
                              value: '${reservations.length}',
                              icon: Icons.calendar_today_rounded,
                              color: BabifixDesign.cyan,
                              isLight: _isLight,
                            ),
                            const SizedBox(width: 8),
                            _MiniStatChip(
                              label: 'En cours',
                              value:
                                  '${reservations.where((r) => r.status == 'En cours').length}',
                              icon: Icons.pending_actions_rounded,
                              color: const Color(0xFFF59E0B),
                              isLight: _isLight,
                            ),
                            const SizedBox(width: 8),
                            _MiniStatChip(
                              label: 'En cours',
                              value: totalEscrow > 0
                                  ? formatFcfa(totalEscrow)
                                  : '0 F',
                              icon: Icons.pending_actions_rounded,
                              color: const Color(0xFF10B981),
                              isLight: _isLight,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _PremiumActionTile(
                  icon: Icons.person_outline_rounded,
                  title: 'Modifier le profil',
                  subtitle: 'Photo, nom, coordonnees',
                  onTap: _openEditProfile,
                ),
                const SizedBox(height: 10),
                _PremiumActionTile(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: 'Messages',
                  subtitle: 'Echanger avec vos prestataires',
                  onTap: _openMessages,
                ),
                const SizedBox(height: 10),
                _PremiumActionTile(
                  icon: Icons.support_agent_rounded,
                  title: 'Contacter l’administrateur',
                  subtitle: contactAdminEmail.isEmpty
                      ? 'Email support (configure côté serveur)'
                      : contactAdminEmail,
                  onTap: _contactAdminMail,
                ),
                const SizedBox(height: 10),
                _PremiumActionTile(
                  icon: Icons.help_center_outlined,
                  title: 'FAQ & aide',
                  subtitle: 'Guide reservation, paiement, avis',
                  onTap: _showHelpSheet,
                ),
                const SizedBox(height: 10),
                _PremiumActionTile(
                  icon: Icons.palette_outlined,
                  title: 'Parametres',
                  subtitle: 'Telephone, adresse exacte, theme',
                  onTap: _openSettings,
                ),
                const SizedBox(height: 10),
                _PremiumActionTile(
                  icon: Icons.info_outline_rounded,
                  title: 'A propos de BABIFIX',
                  subtitle: 'Version, mentions et support',
                  onTap: () {
                    showAboutDialog(
                      context: context,
                      applicationName: 'BABIFIX',
                      applicationVersion: '1.0.0',
                      applicationIcon: const CircleAvatar(
                        backgroundImage: AssetImage(_logoAsset),
                      ),
                      children: const [
                        Text(
                          'Plateforme premium de services a domicile avec reservation et paiement securise.',
                        ),
                      ],
                    );
                  },
                ),
                // ── Paiements en attente ─────────────────────────────
                const SizedBox(height: 10),
                if (sessionLoggedIn && totalEscrow > 0)
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: _isLight
                            ? const [Color(0xFFEFFAFF), Color(0xFFE0F7FE)]
                            : const [Color(0xFF071523), Color(0xFF0B2035)],
                      ),
                      border: Border.all(
                        color: _isLight
                            ? const Color(0xFF7DD3FC)
                            : const Color(0x334CC9F0),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(
                              0xFF4CC9F0,
                            ).withValues(alpha: 0.15),
                          ),
                          child: const Icon(
                            Icons.account_balance_wallet_rounded,
                            color: Color(0xFF4CC9F0),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Paiements en attente',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: _textPrimary,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${formatFcfa(totalEscrow)} en attente de validation',
                                style: const TextStyle(
                                  color: Color(0xFF4CC9F0),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF4CC9F0,
                            ).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Sécurisé',
                            style: TextStyle(
                              color: Color(0xFF4CC9F0),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // ── Sécurité & compte ───────────────────────────────────
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _cardBg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: _isLight
                          ? const Color(0x10000000)
                          : const Color(0x18FFFFFF),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          'Sécurité & compte',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _textSecondary,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      _PremiumActionTile(
                        icon: Icons.fingerprint_rounded,
                        title: 'Connexion biométrique',
                        subtitle: 'Face ID / Empreinte pour accéder rapidement',
                        onTap: _openBiometricSettings,
                      ),
                      const SizedBox(height: 8),
                      _PremiumActionTile(
                        icon: Icons.lock_outline_rounded,
                        title: 'Changer le mot de passe',
                        subtitle: 'Modifier votre mot de passe de connexion',
                        onTap: _openForgotPassword,
                      ),
                    ],
                  ),
                ),

                // ── Légal & confidentialité ─────────────────────────────
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: _cardBg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: _isLight
                          ? const Color(0x10000000)
                          : const Color(0x18FFFFFF),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _LegalLink(
                        label: 'CGU',
                        icon: Icons.description_outlined,
                        isLight: _isLight,
                        onTap: () => _launchUrl('https://babifix.ci/cgu'),
                      ),
                      _VerticalDivider(isLight: _isLight),
                      _LegalLink(
                        label: 'Confidentialité',
                        icon: Icons.privacy_tip_outlined,
                        isLight: _isLight,
                        onTap: () => _launchUrl('https://babifix.ci/privacy'),
                      ),
                      _VerticalDivider(isLight: _isLight),
                      _LegalLink(
                        label: 'Aide',
                        icon: Icons.help_outline_rounded,
                        isLight: _isLight,
                        onTap: _showHelpSheet,
                      ),
                    ],
                  ),
                ),

                // ── Badge BABIFIX Protect ───────────────────────────────
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: _isLight
                          ? const [Color(0xFFF0FDF4), Color(0xFFDCFCE7)]
                          : const [Color(0xFF052010), Color(0xFF073318)],
                    ),
                    border: Border.all(
                      color: _isLight
                          ? const Color(0xFF86EFAC)
                          : const Color(0x3322C55E),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.verified_user_rounded,
                        color: Color(0xFF22C55E),
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'BABIFIX Protect',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: _textPrimary,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              'Paiement sécurisé · Prestataires vérifiés · Support 7j/7',
                              style: TextStyle(
                                color: _textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Déconnexion ─────────────────────────────────────────
                const SizedBox(height: 10),
                _PremiumActionTile(
                  icon: sessionLoggedIn
                      ? Icons.logout_rounded
                      : Icons.login_rounded,
                  title: sessionLoggedIn ? 'Déconnexion' : 'Connexion',
                  subtitle: sessionLoggedIn
                      ? 'Quitter ce compte sur cet appareil'
                      : 'Se connecter ou créer un compte',
                  onTap: sessionLoggedIn ? _logout : _openAuth,
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'BABIFIX v1.0.0 · Abidjan, Côte d\'Ivoire',
                    style: TextStyle(
                      fontSize: 11,
                      color: _textSecondary.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ],
            ),
          ), // RefreshIndicator
        ),
      ],
    );
  }

  Future<void> _initSession() async {
    authToken = await BabifixUserStore.getApiToken();
    await _loadRemoteData();
    await _refreshUnreadChat();
    await _attachClientRealtime();
  }

  Future<void> _loadRemoteData() async {
    setState(() => loadingRemote = true);

    // Charger les catégories publiques (sans authentification)
    await _loadPublicCategories();

    // Charger les prestataires sans authentification
    await _loadPublicProviders();

    // Charger les données utilisateur (si connecté)
    if (authToken != null) {
      await _loadClientHomeData();
    } else {
      if (mounted) {
        setState(() => loadingRemote = false);
        // Aucun service sans auth — déclencher le délai pour l'état vide
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) setState(() => _showEmptyAfterDelay = true);
        });
      }
    }
  }

  /// Charge les prestataires publics sans authentification
  Future<void> _loadPublicProviders() async {
    try {
      final base = babifixApiBaseUrl();
      final url = '$base/api/public/providers/';
      debugPrint('BABIFIX: Fetching providers from: $url');
      final pres = await http.get(Uri.parse(url));
      if (pres.statusCode == 200) {
        final pdata = jsonDecode(pres.body) as Map<String, dynamic>;
        final rows = (pdata['providers'] as List<dynamic>? ?? []);
        debugPrint('BABIFIX: Found ${rows.length} providers');

        final rp = rows.map((x) {
          double? tf;
          final th = x['tarif_horaire'];
          if (th is num) {
            tf = th.toDouble();
          } else if (th != null) {
            tf = double.tryParse('$th');
          }
          return RecentProviderCard(
            id: jsonInt(x['id']),
            nom: '${x['nom'] ?? ''}',
            specialite: '${x['specialite'] ?? ''}',
            ville: '${x['ville'] ?? ''}',
            imageUrl: '${x['photo_portrait_url'] ?? x['image_url'] ?? ''}',
            tarif: tf,
            disponible: x['disponible'] != false,
          );
        }).toList();

        // Convertir aussi en ClientService pour l'onglet Services (fallback sans auth)
        final publicServices = rp.map((p) {
          final catName = p.specialite.isNotEmpty ? p.specialite : 'Service';
          return ClientService(
            title: p.nom,
            category: catName,
            duration: 'Disponible',
            price: p.tarif?.toInt() ?? 0,
            rating: 0.0,
            verified: true,
            color: const Color(0xFF0284c7),
            imageUrl: p.imageUrl.isNotEmpty
                ? p.imageUrl
                : 'assets/images/service-plomberie.jpg',
            providerId: p.id,
            disponible: p.disponible,
          );
        }).toList();

        if (mounted) {
          setState(() {
            recentProviders = rp;
            // Peupler services seulement si pas encore chargés (avant auth)
            if (services.isEmpty) {
              services = publicServices;
            }
          });
        }
      }
    } catch (e) {
      debugPrint('BABIFIX: Error loading providers: $e');
    }
  }

  Future<void> _loadPublicCategories() async {
    try {
      final base = babifixApiBaseUrl();
      final url = '$base/api/public/categories/';
      debugPrint('BABIFIX: _loadPublicCategories START');
      final cres = await http.get(Uri.parse(url));
      debugPrint('BABIFIX: Categories response status: ${cres.statusCode}');
      if (cres.statusCode == 200) {
        final cdata = jsonDecode(cres.body) as Map<String, dynamic>;
        final rows = (cdata['categories'] as List<dynamic>? ?? []);
        debugPrint('BABIFIX: Found ${rows.length} categories');

        List<CategoryTab> nextTabs = const [
          CategoryTab(
            icon: Icons.grid_view_rounded,
            label: 'Tous',
            filterKey: 'TOUS',
          ),
        ];

        for (final raw in rows) {
          final m = raw as Map<String, dynamic>;
          final nom = '${m['nom'] ?? m['name'] ?? ''}'.trim();
          if (nom.isEmpty) continue;
          final fk = babifixCategoryFilterKey(nom);
          final slug = '${m['icone_slug'] ?? m['slug'] ?? ''}'.trim();
          final iconUrl = '${m['icone_url'] ?? ''}'.trim();
          final icon = CategoryIconMapper.resolve(slug, '');
          final color = CategoryIconMapper.color(slug);
          nextTabs = [
            ...nextTabs,
            CategoryTab(
              icon: icon,
              iconNetworkUrl: iconUrl.isNotEmpty ? iconUrl : null,
              label: nom,
              filterKey: fk,
              color: color,
            ),
          ];
        }

        if (mounted) {
          setState(() {
            categoryTabs = nextTabs;
            if (categoryIndex >= categoryTabs.length) {
              categoryIndex = 0;
            }
          });
        }
      }
    } catch (e) {
      debugPrint('BABIFIX: Error loading categories: $e');
    }
    if (mounted) {
      setState(() => loadingRemote = false);
    }
  }

  Future<void> _loadClientHomeData() async {
    try {
      final base = babifixApiBaseUrl();
      final uri = Uri.parse('$base/api/client/home');
      http.Response res;
      try {
        res = await http.get(
          uri,
          headers: {'Authorization': 'Bearer $authToken'},
        );
      } catch (_) {
        final cached = await BabifixOfflineCache.loadHomeData();
        if (cached != null && mounted) {
          setState(() => loadingRemote = false);
        }
        return;
      }
      if (res.statusCode != 200) {
        setState(() => loadingRemote = false);
        return;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      BabifixOfflineCache.saveHomeData(data);

      List<CategoryTab> nextTabs = const [
        CategoryTab(
          icon: Icons.grid_view_rounded,
          label: 'Tous',
          filterKey: 'TOUS',
        ),
      ];
      try {
        final url = '$base/api/public/categories/';
        debugPrint('BABIFIX: Fetching categories from: $url');
        final cres = await http.get(Uri.parse(url));
        debugPrint('BABIFIX: Categories response status: ${cres.statusCode}');
        if (cres.statusCode == 200) {
          final cdata = jsonDecode(cres.body) as Map<String, dynamic>;
          final rows = (cdata['categories'] as List<dynamic>? ?? []);
          debugPrint('BABIFIX: Found ${rows.length} categories');
          for (final raw in rows) {
            final m = raw as Map<String, dynamic>;
            final nom = '${m['nom'] ?? m['name'] ?? ''}'.trim();
            if (nom.isEmpty) continue;
            final fk = babifixCategoryFilterKey(nom);
            final slug = '${m['icone_slug'] ?? m['slug'] ?? ''}'.trim();
            final emoji = '${m['icon_emoji'] ?? ''}'.trim();
            final iconUrl = '${m['icone_url'] ?? ''}'.trim();
            final icon = CategoryIconMapper.resolve(slug, emoji);
            final color = CategoryIconMapper.color(slug);
            nextTabs = [
              ...nextTabs,
              CategoryTab(
                icon: icon,
                iconNetworkUrl: iconUrl.isNotEmpty ? iconUrl : null,
                label: nom,
                filterKey: fk,
                color: color,
              ),
            ];
          }
        }
      } catch (e) {}

      final remoteServices = (data['services'] as List<dynamic>? ?? [])
          .map(
            (item) => ClientService(
              title: '${item['title'] ?? ''}',
              category:
                  '${item['category_filter_key'] ?? babifixCategoryFilterKey('${item['category'] ?? ''}')}',
              duration: '${item['duration'] ?? ''}',
              price: jsonInt(item['price']),
              rating: jsonDouble(item['rating']),
              verified: item['verified'] == true,
              color: _parseHexColor('${item['color'] ?? '#244B5A'}'),
              imageUrl: (item['image_url'] as String?)?.isNotEmpty == true
                  ? item['image_url'] as String
                  : 'assets/images/service-plomberie.jpg',
              providerId: jsonInt(item['provider_id']),
              disponible: item['disponible'] != false,
            ),
          )
          .toList();

      final remoteReservations = (data['reservations'] as List<dynamic>? ?? [])
          .map(
            (item) => ClientReservation(
              title: '${item['title'] ?? ''}',
              whenLabel: '${item['when_label'] ?? ''}',
              amount: '${item['amount'] ?? ''}',
              status: '${item['status'] ?? ''}',
              reference: '${item['reference'] ?? item['title'] ?? ''}',
              id: jsonInt(item['id']),
              canRate: jsonBool(item['can_rate']),
              rated: jsonBool(item['rated']),
              paymentType: '${item['payment_type'] ?? 'ESPECES'}',
              cashFlowStatus: '${item['cash_flow_status'] ?? ''}',
              canConfirmService: jsonBool(item['can_confirm_service']),
              canPay: jsonBool(item['can_pay']),
              canViewDevis: jsonBool(item['can_view_devis']),
              canAcceptDevis: jsonBool(item['can_accept_devis']),
              disputeOuverte: jsonBool(item['dispute_ouverte']),
              latitude: jsonDoubleNullable(item['latitude']),
              longitude: jsonDoubleNullable(item['longitude']),
              addressLabel: '${item['address_label'] ?? ''}'.trim(),
            ),
          )
          .toList();

      final remoteNews = (data['news'] as List<dynamic>? ?? [])
          .map<(String, String)>(
            (item) => ('${item['title']}', '${item['subtitle']}'),
          )
          .toList();

      final remoteActualites = (data['actualites'] as List<dynamic>? ?? [])
          .map(
            (item) => ClientActualiteItem(
              id: jsonInt(item['id']),
              titre: '${item['titre'] ?? ''}',
              description: '${item['description'] ?? ''}',
              imageUrl: '${item['image_url'] ?? ''}',
              categorieTag: '${item['categorie_tag'] ?? ''}',
              dateLabel: '${item['date_publication'] ?? ''}'.split('T').first,
            ),
          )
          .toList();

      var pm = (data['payment_methods'] as List<dynamic>? ?? []).map((raw) {
        final x = raw as Map<String, dynamic>;
        return PaymentMethodOption(
          id: '${x['id'] ?? ''}',
          label: '${x['label'] ?? ''}',
          logoUrl: '${x['logo_url'] ?? ''}',
        );
      }).toList();
      if (pm.isEmpty) {
        try {
          final pr = await http.get(
            Uri.parse('$base/api/public/payment-methods/'),
          );
          if (pr.statusCode == 200) {
            final pj = jsonDecode(pr.body) as Map<String, dynamic>;
            pm = (pj['payment_methods'] as List<dynamic>? ?? []).map((raw) {
              final x = raw as Map<String, dynamic>;
              return PaymentMethodOption(
                id: '${x['id'] ?? ''}',
                label: '${x['label'] ?? ''}',
                logoUrl: '${x['logo_url'] ?? ''}',
              );
            }).toList();
          }
        } catch (_) {}
      }
      final rp = (data['recent_providers'] as List<dynamic>? ?? []).map((raw) {
        final x = raw as Map<String, dynamic>;
        double? tf;
        final th = x['tarif_horaire'];
        if (th is num) {
          tf = th.toDouble();
        } else if (th != null) {
          tf = double.tryParse('$th');
        }
        return RecentProviderCard(
          id: jsonInt(x['id']),
          nom: '${x['nom'] ?? ''}',
          specialite: '${x['specialite'] ?? ''}',
          ville: '${x['ville'] ?? ''}',
          imageUrl: '${x['image_url'] ?? ''}',
          tarif: tf,
          disponible: x['disponible'] != false,
        );
      }).toList();
      final adminMail = '${data['contact_admin_email'] ?? ''}'.trim();

      if (!mounted) return;
      setState(() {
        // Ne remplacer les catégories que si nextTabs contient plus que "Tous"
        // (évite d'écraser les 77 catégories déjà chargées si la requête interne a échoué)
        if (nextTabs.length > 1) {
          categoryTabs = nextTabs;
          if (categoryIndex >= categoryTabs.length) {
            categoryIndex = 0;
          }
        }
        // Si l'API retourne des services auth → ils remplacent les services publics
        // Sinon on garde les services publics déjà chargés
        if (remoteServices.isNotEmpty) {
          services = remoteServices;
        }
        reservations = remoteReservations;
        news = remoteNews;
        actualites = remoteActualites;
        paymentMethodsRemote = pm;
        recentProviders = rp;
        contactAdminEmail = adminMail;
        _showEmptyAfterDelay = services.isNotEmpty;
      });
      if (services.isEmpty) {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) setState(() => _showEmptyAfterDelay = true);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          // Ne pas effacer services — garder les services publics
          reservations = [];
          news = [];
          actualites = [];
          paymentMethodsRemote = [];
          recentProviders = [];
        });
      }
    } finally {
      if (mounted) setState(() => loadingRemote = false);
    }
  }

  Future<Map<String, String>?> _promptPaymentAndMessage() async {
    String payment = 'ESPECES';

    /// Operateurs Mobile Money courants en Cote d'Ivoire (libelles + couleurs d'identification).
    String mmOperator = 'ORANGE_MONEY';
    final msgCtrl = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.paddingOf(ctx).bottom + 16,
          top: 8,
        ),
        child: StatefulBuilder(
          builder: (ctx, setModal) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Type de paiement',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Espèces'),
                    selected: payment == 'ESPECES',
                    onSelected: (_) => setModal(() => payment = 'ESPECES'),
                  ),
                  ChoiceChip(
                    label: const Text('Mobile Money'),
                    selected: payment == 'MOBILE_MONEY',
                    onSelected: (_) => setModal(() => payment = 'MOBILE_MONEY'),
                  ),
                ],
              ),
              if (payment == 'MOBILE_MONEY') ...[
                const SizedBox(height: 12),
                const Text(
                  'Operateur (Cote d\'Ivoire)',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MmLogoChip(
                      operatorId: 'ORANGE_MONEY',
                      label: 'Orange Money',
                      selected: mmOperator == 'ORANGE_MONEY',
                      onTap: () => setModal(() => mmOperator = 'ORANGE_MONEY'),
                    ),
                    _MmLogoChip(
                      operatorId: 'MTN_MOMO',
                      label: 'MTN MoMo',
                      selected: mmOperator == 'MTN_MOMO',
                      onTap: () => setModal(() => mmOperator = 'MTN_MOMO'),
                    ),
                    _MmLogoChip(
                      operatorId: 'WAVE',
                      label: 'Wave',
                      selected: mmOperator == 'WAVE',
                      onTap: () => setModal(() => mmOperator = 'WAVE'),
                    ),
                    _MmLogoChip(
                      operatorId: 'MOOV',
                      label: 'Moov',
                      selected: mmOperator == 'MOOV',
                      onTap: () => setModal(() => mmOperator = 'MOOV'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: msgCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Message pour le prestataire (optionnel)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Continuer'),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true) return null;
    final out = <String, String>{
      'payment_type': payment,
      'message': msgCtrl.text.trim(),
    };
    if (payment == 'MOBILE_MONEY') {
      out['mobile_money_operator'] = mmOperator;
    }
    return out;
  }

  Future<bool> _createReservation(
    ClientService service, {
    Map<String, dynamic>? flowData,
  }) async {
    // Refresh token before request to avoid invalid_token
    final freshToken = await BabifixUserStore.getApiToken();
    if (freshToken == null || freshToken.isEmpty) {
      if (mounted) {
        setState(() => navIndex = 4);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connectez-vous d\'abord pour réservés.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return false;
    }
    authToken = freshToken;

    double? lat;
    double? lon;
    String addressLabel = '';
    String whenLabel = '';
    String paymentType;
    String message = '';
    String? mobileMoneyOperator;
    final photoAttachments = <String>[];

    if (flowData != null) {
      whenLabel = reservationWhenLabelFromFlowData(flowData);
      paymentType = '${flowData['payment_type'] ?? 'ESPECES'}';
      message = '${flowData['message'] ?? ''}'.trim();
      addressLabel = '${flowData['address'] ?? ''}'.trim();
      if (paymentType == 'MOBILE_MONEY') {
        final op = flowData['mobile_money_operator'];
        if (op != null && '$op'.trim().isNotEmpty) {
          mobileMoneyOperator = '$op'.trim();
        }
      }
      final la = flowData['latitude'];
      final lo = flowData['longitude'];
      if (la != null && lo != null) {
        if (la is num) {
          lat = la.toDouble();
        } else {
          lat = double.tryParse('$la');
        }
        if (lo is num) {
          lon = lo.toDouble();
        } else {
          lon = double.tryParse('$lo');
        }
      }
      final rawPhotos = flowData['photo_attachments'];
      if (rawPhotos is List) {
        for (final e in rawPhotos) {
          if (e is String && e.startsWith('data:image/')) {
            photoAttachments.add(e);
          }
        }
      }
    } else {
      final choice = await _promptPaymentAndMessage();
      if (choice == null) return false;
      paymentType = choice['payment_type']!;
      message = choice['message'] ?? '';
      if (paymentType == 'MOBILE_MONEY') {
        final op = choice['mobile_money_operator'];
        if (op != null && op.isNotEmpty) mobileMoneyOperator = op;
      }
      try {
        final loc = await Permission.locationWhenInUse.request();
        if (loc.isGranted || loc.isLimited) {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
            ),
          );
          lat = pos.latitude;
          lon = pos.longitude;
          if (addressLabel.isEmpty) {
            addressLabel =
                '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
          }
        }
      } catch (_) {
        // pas de GPS : la réservation part quand même sans coordonnées
      }
    }

    try {
      final uri = Uri.parse('${babifixApiBaseUrl()}/api/client/reservations');
      final body = <String, dynamic>{
        'title': service.title,
        'amount': formatFcfa(service.price),
        'price_fcfa': service.price,
        'payment_type': paymentType,
        if (mobileMoneyOperator != null && mobileMoneyOperator.isNotEmpty)
          'mobile_money_operator': mobileMoneyOperator,
        if (message.isNotEmpty) 'message': message,
        if (whenLabel.isNotEmpty) 'when_label': whenLabel,
        if (service.providerId > 0) 'provider_id': service.providerId,
        if (lat != null) 'latitude': lat,
        if (lon != null) 'longitude': lon,
        if (addressLabel.isNotEmpty) 'address_label': addressLabel,
        if (photoAttachments.isNotEmpty) 'photo_attachments': photoAttachments,
      };
      final res = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode(body),
      );
      if (res.statusCode == 201) {
        if (mounted) await _loadRemoteData();
        return true;
      }
      if (mounted) {
        // If provider is unavailable, mark the card gray immediately so the
        // user sees the feedback without waiting for a WebSocket event.
        try {
          final errJson = jsonDecode(res.body) as Map<String, dynamic>;
          if (errJson['error'] == 'provider_unavailable' &&
              service.providerId > 0) {
            setState(() {
              services = services
                  .map(
                    (s) => s.providerId == service.providerId
                        ? s.copyWith(disponible: false)
                        : s,
                  )
                  .toList();
              recentProviders = recentProviders
                  .map(
                    (p) => p.id == service.providerId
                        ? p.copyWith(disponible: false)
                        : p,
                  )
                  .toList();
            });
          }
        } catch (_) {}
        final detail = babifixFormatApiErrorBody(res.body);
        final msg = detail.isNotEmpty
            ? detail
            : 'Réservation impossible (${res.statusCode})';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erreur réseau — réessayez dans un instant.'),
),
    );
  }
}

class _SplashScreen extends StatefulWidget {
  const _SplashScreen();

  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutBack,
      ),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1F3C),
      body: Center(
        child: AnimatedBuilder(
          animation: _scaleAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: child,
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: const Color(0xFF4CC9F0),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(
                  Icons.home_repair_service,
                  size: 64,
                  color: Color(0xFF0D1F3C),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'BABIFIX',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white.withValues(alpha: 0.95),
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Services a domicile',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.6),
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
    return false;
  }

  bool _canDeclareCash(ClientReservation r) {
    if (r.status.trim() != 'Terminee') return false;
    if (r.paymentType != 'ESPECES') return false;
    return r.cashFlowStatus.isEmpty;
  }

  Future<void> _declareCashPayment(ClientReservation r) async {
    if (authToken == null || r.reference.isEmpty) return;
    try {
      final uri = Uri.parse(
        '${babifixApiBaseUrl()}/api/client/reservations/${Uri.encodeComponent(r.reference)}/cash-declare',
      );
      final res = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $authToken',
          'Content-Type': 'application/json',
        },
        body: '{}',
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Paiement espèces déclaré — en attente du prestataire.',
            ),
          ),
        );
        await _loadRemoteData();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur: ${res.statusCode}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    }
  }

  void _showReservationDetails(ClientReservation r) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (_, controller) => Container(
          decoration: BoxDecoration(
            color: _isLight ? Colors.white : const Color(0xFF1E293B),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                r.title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: _textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                r.whenLabel,
                style: TextStyle(fontSize: 14, color: _textSecondary),
              ),
              const SizedBox(height: 4),
              Text(
                r.addressLabel,
                style: TextStyle(fontSize: 14, color: _textSecondary),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    r.amount,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF7EC8E3),
                    ),
                  ),
                  const Spacer(),
                  StatusPill(
                    text: r.status == 'DEVIS_ENVOYE'
                        ? 'Devis re\u00e7u'
                        : r.status,
                  ),
                ],
              ),
              if (r.disputeOuverte) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_rounded,
                        color: Colors.orange.shade800,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Litige signalé — suivi avec BABIFIX',
                          style: TextStyle(
                            color: Colors.orange.shade800,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              if (r.canConfirmService ||
                  r.canPay ||
                  r.canRate ||
                  _canDeclareCash(r)) ...[
                const Text(
                  'Actions',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (r.canConfirmService)
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _confirmPrestationClient(r);
                        },
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Confirmer'),
                      ),
                    if (r.canPay)
                      FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          if (r.id > 0) {
                            Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                builder: (_) => PaymentScreen(
                                  reservationId: r.id,
                                  serviceTitle: r.title,
                                ),
                              ),
                            );
                          } else {
                            _openPostPrestationPaySheet(r);
                          }
                        },
                        icon: const Icon(Icons.payment),
                        label: const Text('Payer'),
                      ),
                    if (_canDeclareCash(r))
                      FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _declareCashPayment(r);
                        },
                        icon: const Icon(Icons.money),
                        label: const Text('Payé en espèces'),
                      ),
                    if (r.canRate && !r.rated)
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _rateReservation(r);
                        },
                        icon: const Icon(Icons.star_outline),
                        label: const Text('Noter'),
                      ),
                  ],
                ),
              ] else ...[
                const Center(
                  child: Text(
                    'Aucune action disponible pour cette réservation',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmPrestationClient(ClientReservation r) async {
    if (authToken == null || r.reference.isEmpty) return;
    try {
      final uri = Uri.parse(
        '${babifixApiBaseUrl()}/api/client/reservations/${Uri.encodeComponent(r.reference)}/confirm-prestation',
      );
      final res = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $authToken',
          'Content-Type': 'application/json',
        },
        body: '{}',
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Prestation confirmée — vous pouvez choisir le mode de paiement.',
            ),
          ),
        );
        await _loadRemoteData();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur: ${res.statusCode}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    }
  }

  Future<void> _openPostPrestationPaySheet(ClientReservation r) async {
    if (authToken == null || r.reference.isEmpty) return;
    final methods = paymentMethodsRemote.isNotEmpty
        ? paymentMethodsRemote
        : const [
            PaymentMethodOption(id: 'ESPECES', label: 'Espèces', logoUrl: ''),
            PaymentMethodOption(
              id: 'ORANGE_MONEY',
              label: 'Orange Money',
              logoUrl: '',
            ),
            PaymentMethodOption(
              id: 'MTN_MOMO',
              label: 'MTN Mobile Money',
              logoUrl: '',
            ),
            PaymentMethodOption(id: 'WAVE', label: 'Wave', logoUrl: ''),
            PaymentMethodOption(id: 'MOOV', label: 'Moov Money', logoUrl: ''),
          ];
    final selectedRef = <String>[methods.first.id];
    final noteCtrl = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.paddingOf(ctx).bottom + 16,
          top: 8,
        ),
        child: StatefulBuilder(
          builder: (ctx, setModal) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Paiement — ${r.reference}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Choisissez un moyen (MVP : enregistrement du mode)',
                  style: TextStyle(fontSize: 13, color: _textSecondary),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final m in methods)
                      InkWell(
                        onTap: () => setModal(() => selectedRef[0] = m.id),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          width: 158,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: selectedRef[0] == m.id
                                  ? const Color(0xFF4CC9F0)
                                  : const Color(0x220F172A),
                              width: selectedRef[0] == m.id ? 2 : 1,
                            ),
                            color: const Color(0xFFF8FAFC),
                          ),
                          child: Column(
                            children: [
                              SizedBox(
                                height: 44,
                                child: Center(
                                  child: BabifixPaymentMethodLogo(
                                    methodId: m.id,
                                    logoUrl: m.logoUrl.isNotEmpty
                                        ? m.logoUrl
                                        : null,
                                    height: 40,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                m.label,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: noteCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Message (optionnel)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Valider le paiement'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final noteText = noteCtrl.text.trim();
    noteCtrl.dispose();
    if (ok != true) return;
    try {
      final uri = Uri.parse(
        '${babifixApiBaseUrl()}/api/client/reservations/${Uri.encodeComponent(r.reference)}/pay-post-prestation',
      );
      final res = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $authToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'payment_method_id': selectedRef[0],
          'message': noteText,
        }),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Paiement enregistré (MVP).')),
        );
        await _loadRemoteData();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur: ${res.statusCode}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    }
  }

  Future<void> _contactAdminMail() async {
    final e = contactAdminEmail.trim();
    if (e.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email admin non configuré.')),
        );
      }
      return;
    }
    final uri = Uri(
      scheme: 'mailto',
      path: e,
      queryParameters: {'subject': 'BABIFIX — Support client'},
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _rateReservation(ClientReservation r) async {
    if (authToken == null || r.reference.isEmpty) return;
    var stars = 5;
    final commentCtrl = TextEditingController();
    final photos = <Uint8List>[];
    final cs = Theme.of(context).colorScheme;

    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: StatefulBuilder(
            builder: (ctx, setS) {
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  4,
                  20,
                  16 + MediaQuery.paddingOf(ctx).bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Votre avis',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Comment s’est passée la prestation ?',
                      style: TextStyle(
                        fontSize: 14,
                        color: cs.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var n = 1; n <= 5; n++)
                          IconButton(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            onPressed: () => setS(() => stars = n),
                            icon: Icon(
                              n <= stars
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              size: 42,
                              color: n <= stars
                                  ? const Color(0xFFF59E0B)
                                  : cs.outlineVariant,
                            ),
                          ),
                      ],
                    ),
                    Center(
                      child: Text(
                        '$stars / 5',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (r.latitude != null && r.longitude != null) ...[
                      const SizedBox(height: 20),
                      Text(
                        'Lieu de l’intervention',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: cs.onSurface.withValues(alpha: 0.88),
                        ),
                      ),
                      const SizedBox(height: 8),
                      BabifixOsmStaticPreview(
                        center: LatLng(r.latitude!, r.longitude!),
                        height: 140,
                      ),
                      if (r.addressLabel.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          r.addressLabel,
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 20),
                    MessageWithPhotosField(
                      controller: commentCtrl,
                      photos: photos,
                      onPhotosChanged: (p) => setS(() {
                        photos
                          ..clear()
                          ..addAll(p);
                      }),
                      maxPhotos: 5,
                      hint: 'Commentaire ou détails utiles (optionnel)',
                      messageHeading: 'Commentaire',
                      photosHeading: 'Photos avec votre avis',
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Annuler'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Envoyer'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    final commentaire = commentCtrl.text.trim();
    commentCtrl.dispose();

    if (go != true) return;

    final photoRows = photos
        .map((b) => 'data:image/jpeg;base64,${base64Encode(b)}')
        .toList();

    try {
      final uri = Uri.parse(
        '${babifixApiBaseUrl()}/api/client/reservations/${Uri.encodeComponent(r.reference)}/rating',
      );
      final res = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $authToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'note': stars,
          'commentaire': commentaire,
          if (photoRows.isNotEmpty) 'photo_attachments': photoRows,
        }),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Merci pour votre avis !')),
        );
        await _loadRemoteData();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur ${res.statusCode}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Color _parseHexColor(String input) {
    final value = input.replaceFirst('#', '');
    if (value.length == 6) {
      return Color(int.parse('FF$value', radix: 16));
    }
    return const Color(0xFF1F2937);
  }

  ImageProvider _imageProvider(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return NetworkImage(path);
    }
    return AssetImage(path);
  }

  Future<void> _openAuth() async {
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (ctx) => AuthScreen(
          onAuthSuccess: () async {
            Navigator.of(ctx).pop();
            authToken = await BabifixUserStore.getApiToken();
            if (mounted) {
              await _loadRemoteData();
              await _refreshUnreadChat();
              await _attachClientRealtime();
              await _loadProfile();
              setState(() => sessionLoggedIn = true);
            }
          },
        ),
      ),
    );
  }

  Future<void> _openMessages() async {
    if (!mounted) return;
    final token = await BabifixUserStore.getApiToken();
    if (!mounted) return;
    setState(() => authToken = token);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MessagesScreen(apiBase: babifixApiBaseUrl()),
      ),
    );
    final again = await BabifixUserStore.getApiToken();
    if (mounted) {
      setState(() => authToken = again);
      await _refreshUnreadChat();
    }
  }

  Future<void> _openSettings() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SettingsSheet(
        currentMode: widget.paletteMode,
        onModeChanged: widget.onPaletteChanged,
        initialPhone: profilePhone,
        initialAddress: profileAddress,
        isLight: _isLight,
        onProfileSaved: () {
          Navigator.of(context).pop();
          _loadProfile();
        },
      ),
    );
  }

  Widget _buildFloatingNavItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final selected = navIndex == index;
    final iconOff = _isLight
        ? const Color(0xFF475569)
        : const Color(0xFFB4BAC7);
    final textOff = _isLight
        ? const Color(0xFF334155)
        : const Color(0xFFB4BAC7);
    final textOn = _isLight ? const Color(0xFF0F172A) : Colors.white;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => navIndex = index),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: selected
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x4D8FE3FF), Color(0x1F8FE3FF)],
                  )
                : null,
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x440EB8FF),
                      blurRadius: 14,
                      offset: Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: selected ? 18 : 0,
                height: 3,
                margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  color: _isLight
                      ? const Color(0xFF0284C7)
                      : const Color(0xFFA6EBFF),
                ),
              ),
              Icon(
                icon,
                size: 21,
                color: selected
                    ? (_isLight
                          ? const Color(0xFF0369A1)
                          : const Color(0xFF9FE6FF))
                    : iconOff,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? textOn : textOff,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Raccourcis visibles sur l’onglet Accueil.
class _HomeQuickChip extends StatelessWidget {
  const _HomeQuickChip({
    required this.icon,
    required this.label,
    required this.isLight,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isLight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = isLight ? const Color(0xFF0F172A) : Colors.white;
    final bg = isLight ? const Color(0xFFF8FAFC) : const Color(0xFF1E3A5F);
    final border = isLight ? const Color(0xFFCBD5E1) : const Color(0xFF334155);
    final ic = isLight ? BabifixDesign.ciBlue : const Color(0xFF9FE6FF);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: bg,
            border: Border.all(
              color: border.withValues(alpha: isLight ? 0.85 : 1),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isLight ? 0.04 : 0.25),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: ic),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: fg,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Puce opérateur Mobile Money (logo + libellé).
class _MmLogoChip extends StatelessWidget {
  const _MmLogoChip({
    required this.operatorId,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String operatorId;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? cs.primaryContainer.withValues(alpha: 0.45)
          : cs.surfaceContainerHighest.withValues(alpha: 0.65),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 108,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? BabifixDesign.cyan : Colors.transparent,
              width: selected ? 2 : 0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BabifixPaymentMethodLogo(methodId: operatorId, height: 30),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HelpRow extends StatelessWidget {
  const _HelpRow({required this.icon, required this.title, required this.body});

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
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stat chip compact pour le profil client ───────────────────────────────
class _MiniStatChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool isLight;

  const _MiniStatChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.isLight,
  });

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
            Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              label,
              style: TextStyle(
                color: color.withValues(alpha: 0.7),
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Lien légal compact ────────────────────────────────────────────────────────
class _LegalLink extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isLight;
  final VoidCallback onTap;

  const _LegalLink({
    required this.label,
    required this.icon,
    required this.isLight,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 18,
            color: isLight ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isLight
                  ? const Color(0xFF475569)
                  : const Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  final bool isLight;
  const _VerticalDivider({required this.isLight});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 32,
      color: isLight ? const Color(0x15000000) : const Color(0x20FFFFFF),
    );
  }
}

// ── Tuile action premium ──────────────────────────────────────────────────────
class _PremiumActionTile extends StatelessWidget {
  const _PremiumActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
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
          border: Border.all(
            color: isLight ? const Color(0x120F172A) : const Color(0x22FFFFFF),
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: isLight
                  ? const Color(0x1A0284C7)
                  : const Color(0x337EC8E3),
              child: Icon(
                icon,
                color: isLight
                    ? const Color(0xFF0369A1)
                    : const Color(0xFF9FE6FF),
              ),
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
                      color: isLight
                          ? const Color(0xFF475569)
                          : const Color(0xFF9CA3AF),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: isLight ? const Color(0xFF334155) : Colors.white70,
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({
    required this.currentMode,
    required this.onModeChanged,
    required this.initialPhone,
    required this.initialAddress,
    required this.isLight,
    required this.onProfileSaved,
  });

  final AppPaletteMode currentMode;
  final ValueChanged<AppPaletteMode> onModeChanged;
  final String initialPhone;
  final String initialAddress;
  final bool isLight;
  final VoidCallback onProfileSaved;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late final TextEditingController phoneCtrl;
  late final TextEditingController addressCtrl;

  @override
  void initState() {
    super.initState();
    phoneCtrl = TextEditingController(text: widget.initialPhone);
    addressCtrl = TextEditingController(text: widget.initialAddress);
  }

  @override
  void dispose() {
    phoneCtrl.dispose();
    addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await BabifixUserStore.saveProfile(
      phone: phoneCtrl.text.trim(),
      address: addressCtrl.text.trim(),
    );
    if (mounted) widget.onProfileSaved();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final bg = widget.isLight
        ? const Color(0xFFF8FAFC)
        : const Color(0xFF111827);
    final title = widget.isLight ? const Color(0xFF0F172A) : Colors.white;
    final sub = widget.isLight
        ? const Color(0xFF64748B)
        : const Color(0xFF9CA3AF);
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(
            color: const Color(0xFF4CC9F0).withValues(alpha: 0.25),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: widget.isLight ? 0.08 : 0.35,
              ),
              blurRadius: 24,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: sub.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Text(
                'Parametres',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: title,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Telephone et adresse exacte pour vos interventions.',
                style: TextStyle(color: sub, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                style: TextStyle(color: title),
                decoration: InputDecoration(
                  labelText: 'Numero de telephone',
                  prefixIcon: Padding(
                    padding: const EdgeInsets.all(12),
                    child: SvgPicture.asset(
                      'assets/illustrations/icons/icon_phone.svg',
                      width: 22,
                      height: 22,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addressCtrl,
                maxLines: 3,
                style: TextStyle(color: title),
                decoration: InputDecoration(
                  labelText: 'Adresse exacte',
                  alignLabelWithHint: true,
                  prefixIcon: Padding(
                    padding: const EdgeInsets.only(top: 12, left: 12, right: 8),
                    child: SvgPicture.asset(
                      'assets/illustrations/icons/icon_map_pin.svg',
                      width: 22,
                      height: 22,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Theme',
                style: TextStyle(fontWeight: FontWeight.w700, color: title),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Blanc (par défaut)'),
                    selected: widget.currentMode == AppPaletteMode.light,
                    onSelected: (_) =>
                        widget.onModeChanged(AppPaletteMode.light),
                  ),
                  ChoiceChip(
                    label: const Text('Bleu BABIFIX'),
                    selected: widget.currentMode == AppPaletteMode.blue,
                    onSelected: (_) =>
                        widget.onModeChanged(AppPaletteMode.blue),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  child: const Text('Enregistrer'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
