import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:ui';
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
// import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';  // désactivé : voir services/zego_call_service.dart
// import 'package:zego_uikit_signaling_plugin/zego_uikit_signaling_plugin.dart';

import 'babifix_design_system.dart';
import 'babifix_api_config.dart';
import 'babifix_fcm.dart';
import 'babifix_money.dart';
import 'json_utils.dart';
import 'user_store.dart';

import 'models/client_models.dart';
import 'shared/geo_utils.dart';
import 'shared/widgets/babifix_distance_chip.dart';
import 'shared/widgets/babifix_slide_to_confirm.dart';
import 'shared/widgets/babifix_prestation_timer.dart';
import 'shared/in_app_notifications.dart';
import 'shared/offline_cache.dart';
import 'services/notification_sound_service.dart';
import 'services/zego_call_service.dart';
import 'shared/widgets/auth_required_dialog.dart';
import 'shared/widgets/category_strip.dart';
import 'shared/services/real_time_sync.dart';
import 'features/auth/onboarding_screen.dart';
import 'features/auth/auth_screen.dart';
import 'features/auth/forgot_password_screen.dart';
import 'features/disputes/my_disputes_screen.dart';
import 'features/disputes/dispute_open_screen.dart';
import 'features/profile/edit_profile_screen.dart';
import 'features/profile/my_addresses_screen.dart';
import 'features/map/providers_map_screen.dart';
import 'features/chat/messages_screen.dart';
import 'features/chat/chat_room_screen.dart' hide ClientChatMsg;
import 'features/booking/booking_flow_screen.dart';
import 'features/booking/devis_kanban_screen.dart';
import 'features/booking/devis_detail_screen.dart';
import 'features/booking/escrow_quote_screen.dart';
import 'features/booking/confirm_completion_screen.dart';
import 'features/booking/client_journal_screen.dart';
import 'features/reservations/premium_receipt_screen.dart';
import 'features/call/call_history_screen.dart';
import 'shared/widgets/babifix_osm_map.dart';
import 'shared/widgets/message_with_photos_field.dart';
import 'shared/widgets/payment_method_logo.dart';
import 'package:latlong2/latlong.dart';
import 'features/providers/provider_profile_premium_screen.dart';
import 'features/notifications/notifications_screen.dart';
import 'features/payment/payment_screen.dart';
import 'features/fidelite/fidelite_screen.dart';
import 'package:go_router/go_router.dart';
import 'theme/app_theme.dart';
import 'router/babifix_client_router.dart';
import 'services/fcm_router.dart';
import 'splash_screen.dart';
import 'shared/widgets/babifix_snackbar.dart';
import 'shared/widgets/app_version_gate.dart';
import 'shared/widgets/error_reporter.dart';

// Le navigatorKey est partagé entre l'ancien Zego (legacy) et le nouveau
// BabifixFcmRouter qui ouvre IncomingCallScreen sur FCM call.incoming.
final GlobalKey<NavigatorState> zegoNavigatorKey =
    BabifixFcmRouter.navigatorKey;

/// Retourne null si la coordonnée est invalide (null, 0, ou hors CI).
double? _validCoord(double? v) {
  if (v == null || v == 0.0) return null;
  return v;
}

/// Aligne sur [adminpanel.views._normalize_category_key] : espaces → underscores, max 24.
String babifixCategoryFilterKey(String nom) {
  final x = nom.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '_');
  return x.length > 24 ? x.substring(0, 24) : x;
}

/// Date/heure du flux reservation → libelle API (`when_label`).
String reservationWhenLabelFromFlowData(Map<String, dynamic> flowData) {
  final timeStr = '${flowData['time'] ?? ''}'.trim();
  final dateStr = '${flowData['date'] ?? ''}'.trim();
  if (dateStr.isEmpty) return timeStr;
  try {
    final d = DateTime.parse(dateStr).toLocal();
    final dh = '${d.day}/${d.month}/${d.year}';
    if (timeStr.isNotEmpty) return '$dh a $timeStr';
    return dh;
  } catch (_) {
    if (timeStr.isNotEmpty) return '$dateStr $timeStr'.trim();
    return dateStr;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Monitoring : capter les crashs et les remonter au backend (→ Sentry).
  initErrorReporter(app: 'client', version: kAppVersion);

  try {
    await dotenv.load(fileName: ".env");
  } catch (_) {}

  await BabifixFcm.ensureInitialized();
  
  // Zego SDK temporairement désactivé — voir services/zego_call_service.dart
  // if (isZegoConfigured) {
  //   ZegoUIKitPrebuiltCallInvitationService().setNavigatorKey(zegoNavigatorKey);
  // }
  
  runApp(const BabifixClientApp());
}

Future<void> _initLiveKitForClientIfNeeded(String? authToken, BuildContext? context) async {
  debugPrint('[LiveKit Client Init] token=${authToken != null}, alreadyInit=${BabifixLiveKitService.isInitialized}');
  // URL et clés LiveKit ne sont plus dans l'app — récupérées au runtime
  // depuis /api/livekit/token (backend authoritative).

  if (authToken == null || authToken.isEmpty) {
    debugPrint('[LiveKit Client Init] No auth token, skipping');
    return;
  }
  if (BabifixLiveKitService.isInitialized) {
    debugPrint('[LiveKit Client Init] Already initialized');
    return;
  }

  try {
    debugPrint('[LiveKit Client Init] Fetching /api/auth/me...');
    final res = await http.get(
      Uri.parse('${babifixApiBaseUrl()}/api/auth/me'),
      headers: {'Authorization': 'Bearer $authToken'},
    );
    debugPrint('[LiveKit Client Init] /api/auth/me status=${res.statusCode}');

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final userId = data['id'] as int?;
      final userName = '${data['username'] ?? 'Client'}';

      debugPrint('[LiveKit Client Init] Got userId=$userId, userName=$userName');

      if (userId != null) {
        await BabifixLiveKitService.init(
          userId: userId,
          userName: userName,
          context: context,
        );
        debugPrint('[LiveKit Client Init] INITIALIZED SUCCESS! isInitialized=${BabifixLiveKitService.isInitialized}');
      }
    }
  } catch (e, stack) {
    debugPrint('[LiveKit Client Init] ERROR: $e');
    debugPrint('[LiveKit Client Init] Stack: $stack');
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
    BabifixNotificationSoundService.ensureInitialized();
  }

  Future<void> _loadPrefs() async {
    // Charge les prefs ET force un délai minimum pour que l'animation
    // du splash ait le temps de se jouer (1800ms = entrée + ~1 cycle loader).
    final started = DateTime.now();
    final p = await SharedPreferences.getInstance();
    final newPalette = switch (p.getString(_kPaletteKey)) {
      'blue' => AppPaletteMode.blue,
      'white' => AppPaletteMode.white,
      _ => AppPaletteMode.light,
    };
    final newSeen = p.getBool(_kOnboardingKey) ?? false;
    final elapsed = DateTime.now().difference(started);
    const minSplash = Duration(milliseconds: 1800);
    if (elapsed < minSplash) {
      await Future.delayed(minSplash - elapsed);
    }
    if (!mounted) return;
    setState(() {
      paletteMode = newPalette;
      hasSeenOnboarding = newSeen;
      _prefsLoaded = true;
    });
  }

  Future<void> _persistPalette(AppPaletteMode mode) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _kPaletteKey,
      switch (mode) {
        AppPaletteMode.blue => 'blue',
        AppPaletteMode.white => 'white',
        AppPaletteMode.light => 'light',
      },
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
      return const BabifixSplashScreen();
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
          ProviderProfilePremiumScreen(providerId: int.tryParse(id) ?? 0),
      bookingBuilder: (context, sid) => Builder(
        builder: (ctx) {
          return BookingFlowScreen(
            serviceTitle: sid,
            servicePrice: 0,
            onConfirm: (data) async {
              final token = await BabifixUserStore.getApiToken();
              if (token == null) return {'ok': false, 'error': 'Non connecté'};

              debugPrint('📤 BOOKING BUILDER — provider_id: ${data['provider_id'] ?? "null"}, title: ${data['title']}');
              try {
                final resp = await http.post(
                  Uri.parse('${babifixApiBaseUrl()}/api/client/reservations'),
                  headers: {
                    'Authorization': 'Bearer $token',
                    'Content-Type': 'application/json',
                  },
                  body: jsonEncode(data),
                );
                debugPrint('📥 BOOKING BUILDER — status: ${resp.statusCode}, body: ${resp.body}');

                if (resp.statusCode == 201) {
                  final result = jsonDecode(resp.body);
                  return {'ok': true, 'reference': result['reference']};
                } else {
                  final err = jsonDecode(resp.body);
                  return {'ok': false, 'error': err['error'] ?? resp.body};
                }
              } catch (e) {
                debugPrint('❌ BOOKING BUILDER ERROR: $e');
                return {'ok': false, 'error': '$e'};
              }
            },
          );
        },
      ),
      providerProfileBuilder: (_, id) =>
          ProviderProfilePremiumScreen(providerId: int.tryParse(id) ?? 0),
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
          DevisKanbanScreen(reservationReference: ref),
      navigatorKey: zegoNavigatorKey,
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
  DateTime? _lastBackPress;

  // ── Recherche et filtres services ────────────────────────────────────────
  String _searchQuery = '';
  Timer? _searchDebounce;
  final _searchCtrl = TextEditingController();
  // Filtres avances
  double _filterMinRating = 0;
  int _filterMaxPrice = 0; // 0 = pas de limite
  double _filterMaxDistance = 0; // 0 = toutes distances (km)
  bool _filterDispoOnly = false; // disponibles uniquement
  bool _filterVerifiedOnly = false; // vérifiés uniquement
  String _filterSort = 'default'; // default | distance | rating | price_asc | price_desc

  String profileName = '';
  String profileEmail = '';
  String profilePhone = '';
  String profileAddress = '';
  Uint8List? profileAvatarBytes;
  bool sessionLoggedIn = false;

  String? authToken;
  bool loadingRemote = false;
  bool _showEmptyAfterDelay = false;

  /// Onglets categories : « Tous » + entrees API `/api/public/categories/`.
  List<CategoryTab> categoryTabs = const [
    CategoryTab(
      icon: Icons.grid_view_rounded,
      label: 'Tous',
      filterKey: 'TOUS',
    ),
  ];

  /// Donnees 100 % issues de l'API — aucune liste locale fictive.
  List<ClientService> services = <ClientService>[];

  /// Nombre de tentatives de chargement (retry auto si serveur froid au boot).
  int _remoteLoadAttempts = 0;

  /// Moyens de paiement (logos) — home + fallback public.
  List<PaymentMethodOption> paymentMethodsRemote = <PaymentMethodOption>[];

  /// Prestataires recents (carousel accueil).
  List<RecentProviderCard> recentProviders = <RecentProviderCard>[];

  /// Rayon adaptatif renvoyé par le backend (km) — pour afficher un bandeau
  /// "Recherche élargie à X km" quand le serveur a dû élargir.
  double? _radiusUsedKm;
  bool _radiusAdaptive = false;

  /// Email support (parametre site Django).
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
    // Chargement immediat des categories (sans authentification)
    _loadPublicCategories();
    // Synchronisation temps réel (WebSocket + fallback polling 30 s).
    RealTimeSyncService.instance.startSync();
    RealTimeSyncService.instance.categoriesStream.listen((_) {
      if (mounted) {
        // Auto-refresh sans afficher de banniere
        _loadRemoteData();
      }
    });
    RealTimeSyncService.instance.providersStream.listen((_) {
      if (mounted) {
        // Recharger les prestataires en temps réel (force update)
        _loadPublicProviders(forceUpdate: true);
      }
    });
    // Contrôle de version (force update) — non bloquant si tout est à jour.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) checkAppVersionGate(context, app: 'client');
    });
  }

  Future<void> _restoreClientNotifsThenInit() async {
    // La restauration des notifications NE DOIT JAMAIS bloquer le démarrage :
    // si le stockage local est corrompu et que ça lève une exception, on
    // n'appellerait jamais _initSession() → l'app resterait VIDE (ni catégories,
    // ni prestataires, ni actualités, ni prompt GPS). On isole donc cette étape.
    try {
      final list = await loadInAppNotifList(BabifixInAppNotifStorageKeys.client);
      if (mounted) _clientInAppNotifs.value = list;
    } catch (e) {
      debugPrint('BABIFIX: restore notifs échoué (ignoré): $e');
    }
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
    });
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
        // Ouvre DIRECTEMENT la réservation concernée si la référence est fournie.
        final ref = '${data['reference'] ?? ''}';
        if (ref.isNotEmpty) _openClientReservationByRef(ref);
        break;
      case 'notification':
      case 'broadcast':
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

  /// Ouvre le détail de la réservation `ref` après un tap sur une notification.
  /// Si elle n'est pas encore chargée, on recharge puis on réessaie.
  void _openClientReservationByRef(String ref) {
    ClientReservation? find() {
      for (final r in reservations) {
        if (r.reference == ref) return r;
      }
      return null;
    }

    final r = find();
    if (r != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showReservationDetails(r);
      });
      return;
    }
    _loadRemoteData().then((_) {
      if (!mounted) return;
      final r2 = find();
      if (r2 != null) _showReservationDetails(r2);
    });
  }

  /// Message SPÉCIFIQUE (titre, corps) côté CLIENT selon le statut, pour les
  /// événements temps réel (WebSocket) qui n'ont pas de texte prêt.
  (String, String) _clientReservationNotifText(String statut, String ref) {
    final r = ref.isNotEmpty ? ' ($ref)' : '';
    switch (statut) {
      case 'DEVIS_ENVOYE':
        return ('Devis reçu', 'Vous avez reçu un devis pour votre réservation$r.');
      case 'DEVIS_ACCEPTE':
        return ('Devis accepté', 'Votre devis$r est accepté. Le prestataire va intervenir.');
      case 'INTERVENTION_EN_COURS':
        return ('Intervention démarrée', 'L\'intervention$r a commencé.');
      case 'En attente client':
        return ('Prestation terminée', 'Confirmez la prestation$r pour finaliser.');
      case 'Terminee':
        return ('Prestation confirmée', 'Vous avez confirmé la prestation$r. Merci !');
      case 'Annulee':
        return ('Réservation annulée', 'La réservation$r a été annulée.');
      default:
        return ('Votre réservation', 'Le statut de votre réservation$r a évolué.');
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
                      'Reservations, litiges, messages et actus : selon votre profil client.',
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
                              'Aucune alerte recente dans l\'app.',
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
      final uri = Uri.parse('${babifixWsBaseUrl()}/ws/client/events/');
      _clientWsChannel?.sink.close();
      _clientWsChannel = WebSocketChannel.connect(
        uri,
        protocols: ['BABIFIX $t'],
      );
      final ch = _clientWsChannel!;
      _clientWsSub = ch.stream.listen((raw) {
        try {
          final m = jsonDecode(raw as String) as Map<String, dynamic>;
          final typ = '${m['type'] ?? ''}';
          if (typ == 'provider.approved' ||
              typ == 'provider.updated' ||
              typ == 'providers.updated' ||
              typ == 'actualite.published') {
            _loadRemoteData();
            if (typ == 'provider.approved' ||
                typ == 'provider.updated' ||
                typ == 'providers.updated') {
              _pushClientNotif(
                category: 'actu',
                title: 'Catalogue mis a jour',
                body: 'Un nouveau prestataire est disponible pres de vous.',
                actionRoute: 'services',
                severity: BabifixNotifSeverity.important,
              );
            } else {
              _pushClientNotif(
                category: 'actu',
                title: 'Actualite BABIFIX',
                body: 'Une nouvelle annonce a ete publiee.',
                actionRoute: 'actus',
                severity: BabifixNotifSeverity.important,
              );
            }
            if (mounted) {
              showBabifixToast(
        context,
        type: BabifixToastType.success,
        message: typ == 'provider.approved'
                        ? 'Catalogue mis a jour : nouveau prestataire.'
                        : 'Nouvelle actualite BABIFIX.',
      );
            }
          } else if (typ == 'chat.message') {
            _refreshUnreadChat();
            _pushClientNotif(
              category: 'message',
              title: 'Nouveau message',
              body: 'Votre prestataire ou le support vous a ecrit.',
              actionRoute: 'messages',
            );
          } else if (typ.contains('reservation') ||
              typ.contains('booking') ||
              typ == 'prestation.updated') {
            _loadRemoteData();
            final pl = m['payload'];
            final ref = (pl is Map) ? '${pl['reference'] ?? ''}' : '';
            final statut = (pl is Map) ? '${pl['statut'] ?? ''}' : '';
            final txt = _clientReservationNotifText(statut, ref);
            _pushClientNotif(
              category: 'demande',
              title: txt.$1,
              body: txt.$2,
              actionRoute: 'reservations',
              severity: BabifixNotifSeverity.important,
            );
          } else if (typ.contains('dispute') || typ == 'litige.ouvert') {
            _pushClientNotif(
              category: 'litige',
              title: 'Litige / reclamation',
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
    // iOS sans config Firebase → ne pas accéder à FirebaseMessaging (crash).
    if (!BabifixFcm.isReady) return;
    _clientFcmSub = FirebaseMessaging.onMessage.listen((msg) {
      final d = msg.data;
      final ty = '${d['type'] ?? ''}';
      if (ty == 'provider.approved' ||
          ty == 'provider.updated' ||
          ty == 'actualite.published') {
        _loadRemoteData();
        if (ty == 'provider.approved' || ty == 'provider.updated') {
          _pushClientNotif(
            category: 'actu',
            title: 'Nouveau prestataire',
            body: 'Le catalogue BABIFIX a ete enrichi.',
            actionRoute: 'services',
            severity: BabifixNotifSeverity.important,
          );
        } else {
          _pushClientNotif(
            category: 'actu',
            title: 'Actualite',
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
        // Message SPÉCIFIQUE du serveur (ex. « Vous avez reçu un devis pour
        // RES-003. ») au lieu d'un texte générique.
        final specTitle = msg.notification?.title;
        final specBody = msg.notification?.body;
        _pushClientNotif(
          category: 'demande',
          title: (specTitle != null && specTitle.isNotEmpty)
              ? specTitle
              : 'Votre réservation',
          body: (specBody != null && specBody.isNotEmpty)
              ? specBody
              : 'Le statut d\'une de vos réservations a évolué.',
          actionRoute: 'reservations',
          severity: BabifixNotifSeverity.important,
        );
      } else if (ty.contains('dispute') || ty == 'litige.ouvert') {
        _pushClientNotif(
          category: 'litige',
          title: 'Litige',
          body: 'Signalement en cours : consultez vos rendez-vous.',
          actionRoute: 'reservations',
          severity: BabifixNotifSeverity.urgent,
        );
      }
    });
    _clientFcmOpenedSub = FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      _handleFcmNavigation(msg.data);
    });

    // Message qui a lance l\'app depuis etat termine
    FirebaseMessaging.instance.getInitialMessage().then((msg) {
      if (msg != null && mounted) {
        _handleFcmNavigation(msg.data);
      }
    });
  }

  Future<void> _loadProfile() async {
    final logged = await BabifixUserStore.isLoggedIn();
    // Récupère nom/téléphone réels du serveur (corrige le nom = email hérité,
    // et remonte le téléphone saisi à l'inscription). Sans réseau : valeurs locales.
    if (logged) {
      await BabifixUserStore.hydrateProfileFromServer();
    }
    final m = await BabifixUserStore.loadProfile();
    final av = await BabifixUserStore.loadAvatarBytes();
    if (!mounted) return;
    setState(() {
      sessionLoggedIn = logged;
      profileName = (m['name'] ?? '').trim().isEmpty
          ? 'Invite'
          : (m['name'] ?? '').trim();
      profileEmail = (m['email'] ?? '').trim();
      profilePhone = (m['phone'] ?? '').trim();
      profileAddress = (m['address'] ?? '').trim();
      profileAvatarBytes = av;
    });
  }

  Future<void> _logout() async {
    // Confirmation explicite avant de déconnecter
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.logout_rounded,
            size: 48, color: Color(0xFFEF4444)),
        title: const Text(
          'Se déconnecter ?',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: const Text(
          'Vous serez déconnecté de votre compte BABIFIX et devrez vous '
          'reconnecter pour accéder à vos réservations et conversations.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.logout_rounded, size: 16),
            label: const Text('Déconnecter'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (ok != true) return;
    _clientWsSub?.cancel();
    _clientFcmSub?.cancel();
    _clientFcmOpenedSub?.cancel();
    await BabifixLiveKitService.uninit();
    await BabifixUserStore.logout();
    authToken = null;
    if (mounted) {
      await _loadProfile();
      setState(() {});
    }
  }

  Future<void> _deleteAccount() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.delete_forever_rounded,
            size: 48, color: Color(0xFFEF4444)),
        title: const Text('Supprimer mon compte ?',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text(
          'Cette action est définitive. Vos données personnelles seront '
          'effacées (loi n°2013-450). Possible uniquement sans réservation '
          'ni litige en cours.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.delete_forever_rounded, size: 16),
            label: const Text('Supprimer'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final token = await BabifixUserStore.getApiToken();
    if (token == null || token.isEmpty) return;
    try {
      final resp = await http.delete(
        Uri.parse('${babifixApiBaseUrl()}/api/auth/delete-account'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'confirmation': 'supprimer'}),
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        _clientWsSub?.cancel();
        _clientFcmSub?.cancel();
        _clientFcmOpenedSub?.cancel();
        await BabifixLiveKitService.uninit();
        await BabifixUserStore.logout();
        authToken = null;
        if (mounted) {
          await _loadProfile();
          setState(() {});
        }
        if (mounted) {
          showBabifixToast(context,
              type: BabifixToastType.success,
              title: 'Compte supprimé',
              message: 'Votre compte a bien été supprimé.');
        }
      } else {
        String msg = 'Suppression impossible pour le moment.';
        try {
          msg = (jsonDecode(resp.body)['message'] ?? msg).toString();
        } catch (_) {}
        showBabifixToast(context,
            type: BabifixToastType.error, title: 'Impossible', message: msg);
      }
    } catch (_) {
      if (mounted) {
        showBabifixToast(context,
            type: BabifixToastType.error,
            message: 'Erreur réseau. Réessayez.');
      }
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
    if (!await _ensureAuthOrPrompt('activer la connexion biométrique')) {
      return;
    }
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
              'Connexion biometrique',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: _textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Activez Face ID ou l\'empreinte digitale pour acceder a votre compte rapidement.',
              style: TextStyle(color: _textSecondary, height: 1.45),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Configurer dans Parametres'),
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
      final wantLogin = await promptLoginRequired(
        context,
        action: 'modifier votre profil',
      );
      if (!mounted || !wantLogin) return;
      await _openAuth();
      // Si la connexion a réussi, on rouvre l'écran d'édition.
      if (mounted && await BabifixUserStore.isLoggedIn()) {
        await _openEditProfile();
      }
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

  // "white" ET "light" sont des thèmes clairs ; seul "blue" (navy) est sombre.
  bool get _isLight => widget.paletteMode != AppPaletteMode.blue;
  Color get _textPrimary => _isLight ? const Color(0xFF0F172A) : Colors.white;
  Color get _textSecondary =>
      _isLight ? const Color(0xFF475569) : const Color(0xFF9CA3AF);
  Color get _cardBg =>
      _isLight ? const Color(0xFFF8FAFC) : const Color(0xFF1A1F28);

  @override
  Widget build(BuildContext context) {
    final activeTab = categoryTabs.isEmpty
        ? null
        : categoryTabs[categoryIndex.clamp(0, categoryTabs.length - 1)];
    final activeKey = activeTab?.filterKey ?? 'TOUS';
    final activeLabel = (activeTab?.label ?? '').trim().toLowerCase();
    final visibleServices = activeKey == 'TOUS'
        ? services
        : services.where((s) {
            // Match principal : même clé de catégorie.
            if (babifixCategoryFilterKey(s.category) == activeKey) return true;
            // Repli TOLÉRANT (données incohérentes : catégorie du presta ≠ libellé
            // exact de l'onglet) → on compare aussi les libellés en souple.
            final sc = s.category.trim().toLowerCase();
            if (sc.isEmpty || activeLabel.isEmpty) return false;
            return sc == activeLabel ||
                sc.contains(activeLabel) ||
                activeLabel.contains(sc);
          }).toList();
    return Scaffold(
      extendBody: true,
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (bool didPop, _) {
          if (didPop) return;
          // Si on n'est pas sur l'onglet Accueil → y revenir (ne PAS quitter).
          if (navIndex != 0) {
            setState(() => navIndex = 0);
            return;
          }
          // Sur l'Accueil → double appui en moins de 2 s pour quitter.
          final now = DateTime.now();
          if (_lastBackPress != null &&
              now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
            SystemNavigator.pop();
          } else {
            _lastBackPress = now;
            showBabifixToast(
              context,
              message: 'Appuyez une seconde fois pour quitter',
              type: BabifixToastType.info,
              title: 'Quitter',
              duration: const Duration(seconds: 2),
            );
          }
        },
        child: Container(
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
                    const Icon(
                      Icons.chat_bubble_rounded,
                      size: 22,
                      color: BabifixDesign.cyan,
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
              PopupMenuButton<String>(
                tooltip: 'Plus',
                offset: const Offset(0, 44),
                icon: Icon(
                  Icons.more_horiz_rounded,
                  size: 24,
                  color: iconColor,
                ),
                onSelected: (value) async {
                  switch (value) {
                    case 'help':
                      _showHelpSheet();
                      break;
                    case 'support':
                      _contactAdminMail();
                      break;
                    case 'settings':
                      setState(() => navIndex = 4);
                      break;
                    case 'about':
                      _showAboutDialog();
                      break;
                    case 'logout':
                      await _confirmLogout();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'settings',
                    child: Row(
                      children: [
                        Icon(Icons.settings_rounded, size: 20, color: iconColor),
                        const SizedBox(width: 12),
                        const Text('Paramètres'),
                      ],
                    ),
                  ),
                  if (showHelp)
                    PopupMenuItem(
                      value: 'help',
                      child: Row(
                        children: [
                          Icon(Icons.help_outline_rounded, size: 20, color: iconColor),
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
                          Icon(Icons.support_agent_rounded, size: 20, color: iconColor),
                          const SizedBox(width: 12),
                          const Text("Contacter l'admin"),
                        ],
                      ),
                    ),
                  PopupMenuItem(
                    value: 'about',
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 20, color: iconColor),
                        const SizedBox(width: 12),
                        const Text('À propos de BABIFIX'),
                      ],
                    ),
                  ),
                  if (authToken != null) const PopupMenuDivider(),
                  if (authToken != null)
                    PopupMenuItem(
                      value: 'logout',
                      child: Row(
                        children: [
                          const Icon(Icons.logout_rounded,
                              size: 20, color: Color(0xFFEF4444)),
                          const SizedBox(width: 12),
                          const Text('Se déconnecter',
                              style: TextStyle(color: Color(0xFFEF4444))),
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

  void _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: 'BABIFIX',
      applicationVersion: 'v1.0.0',
      applicationIcon: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [BabifixDesign.darkNavy, BabifixDesign.cyan],
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.home_work_rounded, color: Colors.white, size: 32),
      ),
      applicationLegalese: '© 2026 BABIFIX SARL : Plateforme de services à '
          "domicile en Côte d'Ivoire.\nTous droits réservés.",
      children: const [
        SizedBox(height: 16),
        Text(
          "BABIFIX met en relation les clients avec des artisans qualifiés "
          "et vérifiés pour tout type de prestation à domicile : plomberie, "
          "électricité, peinture, ménage et bien plus.\n\n"
          "Paiement sécurisé en Mobile Money, géolocalisation des prestataires "
          "et garantie BABIFIX sur chaque intervention.",
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
        SizedBox(height: 12),
        Text('contact@babifix.ci  •  www.babifix.ci',
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
      ],
    );
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: Icon(Icons.logout_rounded,
            color: const Color(0xFFEF4444), size: 32),
        title: const Text('Se déconnecter ?',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text(
          'Vous devrez vous reconnecter avec vos identifiants pour accéder à '
          'votre profil et à vos réservations.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Se déconnecter'),
          ),
        ],
      ),
    );
    if (ok == true) await _logout();
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
              'Comment utiliser l\'app',
              style: TextStyle(color: _textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 16),
            _HelpRow(
              icon: Icons.home_repair_service,
              title: 'Reserver',
              body:
                  'Onglet Services : choisissez une prestation, puis Reserver. Vous pouvez indiquer le mode de paiement et un message.',
            ),
            _HelpRow(
              icon: Icons.calendar_month,
              title: 'Suivre vos rendez-vous',
              body:
                  'Onglet Rendez-vous : statut, paiement especes, notation apres prestation terminee.',
            ),
            _HelpRow(
              icon: Icons.chat_bubble_outline,
              title: 'Messages',
              body:
                  'Échangez avec le prestataire depuis l\'icone message en haut a droite.',
            ),
            _HelpRow(
              icon: Icons.palette_outlined,
              title: 'Theme & coordonnees',
              body:
                  'Profil -> Parametres : theme clair / bleu BABIFIX, telephone et adresse d\'intervention.',
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

  /// Accueil : un seul scroll vertical (evite les bugs Windows où seul le bas defilait).
  Widget _buildNews() {
    return RefreshIndicator(
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
                    // Raccourci découverte : carte interactive des prestataires
                    // à proximité (rayon adaptatif + radar pulsant animé).
                    _HomeQuickChip(
                      icon: Icons.map_outlined,
                      label: 'Carte',
                      isLight: _isLight,
                      onTap: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => const ProvidersMapScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
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
              // Bandeau « recherche élargie » (mode adaptatif backend).
              if (_radiusAdaptive && _radiusUsedKm != null)
                _RadiusBanner(radiusKm: _radiusUsedKm!),
              SizedBox(
                // 144 = 132 d'origine + ~12 pour accommoder le chip distance
                // (vert/cyan/orange/rouge) ajouté en dessous de la ville.
                height: 144,
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
                        child: Opacity(
                          opacity: p.disponible ? 1.0 : 0.5,
                          child: Material(
                          color: _cardBg,
                          borderRadius: BorderRadius.circular(20),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () {
                              if (p.id > 0) {
                                Navigator.of(context).push<void>(
                                  MaterialPageRoute(
                                    builder: (_) => ProviderProfilePremiumScreen(
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
                                            : const DecoratedBox(
                                                decoration: BoxDecoration(
                                                  color: BabifixDesign.navy,
                                                ),
                                                child: Icon(
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
                                          if (p.distanceKm != null) ...[
                                            const SizedBox(height: 4),
                                            BabifixDistanceChip(
                                              distanceKm: p.distanceKm!,
                                              compact: true,
                                            ),
                                          ],
                                          // Badge abonnement (visible sur la card,
                                          // pas seulement sur le détail).
                                          if (p.isPremium) ...[
                                            const SizedBox(height: 4),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF59E0B),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(
                                                      Icons.workspace_premium_rounded,
                                                      size: 12,
                                                      color: Colors.white),
                                                  const SizedBox(width: 3),
                                                  Text(
                                                    p.premiumBadge.isNotEmpty
                                                        ? p.premiumBadge
                                                        : 'Premium',
                                                    style: const TextStyle(
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        color: Colors.white),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                          if (!p.disponible) ...[
                                            const SizedBox(height: 4),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 3,
                                              ),
                                              decoration: BoxDecoration(
                                                color: const Color(0x1FF59E0B),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: const Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.event_busy_rounded,
                                                    size: 12,
                                                    color: Color(0xFFB45309),
                                                  ),
                                                  SizedBox(width: 4),
                                                  Text(
                                                    'Indisponible',
                                                    style: TextStyle(
                                                      fontSize: 10.5,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: Color(0xFFB45309),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                          // Prix supprimé — chaque devis est sur mesure
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
                                '${categoryTabs.length > 1 ? categoryTabs.length - 1 : ''} categories disponibles',
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
                      'Offres, actus et nouveautes BABIFIX',
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

  // ── ACCUEIL : Hero banner personnalise ───────────────────────────────────
  Widget _buildHomeHero() {
    final firstName = profileName.split(' ').first;
    final greet = (firstName.isEmpty || firstName == 'Invite')
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
                    'Cote d\'Ivoire',
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
              'Trouvez un artisan qualifie et verifiable\nen quelques secondes.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.72),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            // Barre de recherche simulee → onglet Services
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
                        'Plombier, electricien, peintre…',
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

  // ── ACCUEIL : Comment ca marche (3 etapes) ───────────────────────────────
  Widget _buildHowItWorksSection() {
    const steps = [
      (Icons.search_rounded, 'Recherchez', '0xFF4CC9F0'),
      (Icons.calendar_today_rounded, 'Reservez', '0xFFE87722'),
      (Icons.verified_rounded, 'Profitez', '0xFF22C55E'),
    ];
    const stepColors = [
      Color(0xFF4CC9F0),
      Color(0xFFE87722),
      Color(0xFF22C55E),
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
                'Comment ca marche',
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
                'Paiements 100 % securises en FCFA',
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
      child: GestureDetector(
        onTap: () => _openActualiteDetail(item),
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
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.white),
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
                    // Extrait court : l'accueil ne montre qu'un aperçu ;
                    // le texte complet s'ouvre au clic (détail actualité).
                    Text(
                      item.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: _textSecondary, height: 1.35),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          'Lire la suite',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: BabifixDesign.ciOrange,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Icon(Icons.arrow_forward_rounded,
                            size: 14, color: BabifixDesign.ciOrange),
                      ],
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
      if (_filterMaxDistance > 0 &&
          s.distanceKm != null &&
          s.distanceKm! > _filterMaxDistance) return false;
      if (_filterDispoOnly && !s.disponible) return false;
      if (_filterVerifiedOnly && !s.verified) return false;
      return true;
    }).toList();
    if (_filterSort == 'distance') {
      filtered.sort((a, b) =>
          (a.distanceKm ?? 1e9).compareTo(b.distanceKm ?? 1e9));
    } else if (_filterSort == 'rating') {
      filtered.sort((a, b) => b.rating.compareTo(a.rating));
    } else if (_filterSort == 'price_asc') {
      filtered.sort((a, b) => a.price.compareTo(b.price));
    } else if (_filterSort == 'price_desc') {
      filtered.sort((a, b) => b.price.compareTo(a.price));
    }

    return RefreshIndicator(
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
            // ── Filtres avances ──────────────────────────────────────────
            _buildFilterChipsRow(filtered.length),
            if (categoryTabs.isNotEmpty)
              CategoryStrip(
                categories: categoryTabs,
                active: categoryIndex.clamp(0, categoryTabs.length - 1),
                onTap: (index) {
                  setState(() => categoryIndex = index);
                  // Reload all providers with force update
                  _loadPublicProviders(forceUpdate: true);
                },
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
                          ? '${filtered.length} resultat(s) pour "$_searchQuery"'
                          : filtered.isEmpty
                          ? 'Aucun service dans cette categorie'
                          : 'Reservez en un clic : ${filtered.length} prestation(s)',
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
      _filterMinRating > 0 ||
      _filterMaxPrice > 0 ||
      _filterMaxDistance > 0 ||
      _filterDispoOnly ||
      _filterVerifiedOnly ||
      _filterSort != 'default';

  Widget _buildFilterChipsRow(int count) {
    final sortLabels = {
      'default': 'Par defaut',
      'distance': 'Plus proche',
      'rating': 'Mieux notes',
      'price_asc': 'Prix croissant',
      'price_desc': 'Prix decroissant',
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
          if (_filterMaxDistance > 0)
            _filterChip(
              label: '≤ ${_filterMaxDistance.toStringAsFixed(0)} km',
              onRemove: () => setState(() => _filterMaxDistance = 0),
            ),
          if (_filterDispoOnly)
            _filterChip(
              label: 'Disponibles',
              onRemove: () => setState(() => _filterDispoOnly = false),
            ),
          if (_filterVerifiedOnly)
            _filterChip(
              label: 'Vérifiés',
              onRemove: () => setState(() => _filterVerifiedOnly = false),
            ),
          if (_hasActiveFilters) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => setState(() {
                _filterMinRating = 0;
                _filterMaxPrice = 0;
                _filterMaxDistance = 0;
                _filterDispoOnly = false;
                _filterVerifiedOnly = false;
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
              color: BabifixDesign.iconOnLight,
            ),
          ),
        ],
      ),
    );
  }

  void _openFilterSheet() {
    double tempMinRating = _filterMinRating;
    int tempMaxPrice = _filterMaxPrice;
    double tempMaxDistance = _filterMaxDistance;
    bool tempDispoOnly = _filterDispoOnly;
    bool tempVerifiedOnly = _filterVerifiedOnly;
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
                        tempMaxDistance = 0;
                        tempDispoOnly = false;
                        tempVerifiedOnly = false;
                        tempSort = 'default';
                      });
                    },
                    child: const Text('Reinitialiser'),
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
                    'default': 'Par defaut',
                    'distance': '📍 Plus proche',
                    'rating': 'Mieux notes',
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
              const SizedBox(height: 8),
              // ── Distance maximale ────────────────────────────────────
              Row(
                children: [
                  const Icon(Icons.place_rounded, size: 16, color: BabifixDesign.ciOrange),
                  const SizedBox(width: 4),
                  const Text(
                    'Distance max : ',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  Text(
                    tempMaxDistance == 0
                        ? 'Toutes'
                        : '${tempMaxDistance.toStringAsFixed(0)} km',
                  ),
                ],
              ),
              Slider(
                value: tempMaxDistance,
                min: 0,
                max: 50,
                divisions: 10,
                label: tempMaxDistance == 0
                    ? 'Toutes'
                    : '${tempMaxDistance.toStringAsFixed(0)} km',
                activeColor: BabifixDesign.ciOrange,
                onChanged: (v) => setSheetState(() => tempMaxDistance = v),
              ),
              // Raccourcis proximité
              Wrap(
                spacing: 8,
                children: [
                  for (final km in [0, 5, 15, 30, 50])
                    ChoiceChip(
                      label: Text(km == 0 ? 'Tous' : '≤ $km km'),
                      selected: tempMaxDistance == km.toDouble(),
                      onSelected: (_) =>
                          setSheetState(() => tempMaxDistance = km.toDouble()),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              // ── Disponibilité + vérifiés ─────────────────────────────
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                activeThumbColor: BabifixDesign.ciOrange,
                title: const Text('Disponibles uniquement',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                value: tempDispoOnly,
                onChanged: (v) => setSheetState(() => tempDispoOnly = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                activeThumbColor: BabifixDesign.ciOrange,
                title: const Text('Prestataires vérifiés uniquement',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                value: tempVerifiedOnly,
                onChanged: (v) => setSheetState(() => tempVerifiedOnly = v),
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
                      _filterMaxDistance = tempMaxDistance;
                      _filterDispoOnly = tempDispoOnly;
                      _filterVerifiedOnly = tempVerifiedOnly;
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
            'Aucun resultat pour "$_searchQuery"',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Essayez un autre mot-cle ou consultez\ntoutes les categories.',
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
              'De nouveaux prestataires arrivent bientot.\nExplore les autres categories !',
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
    final outlineStyle = OutlinedButton.styleFrom(
      foregroundColor: _textPrimary,
      side: BorderSide(
        color: BabifixDesign.cyan.withValues(alpha: _isLight ? 0.55 : 0.65),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
    final filledStyle = FilledButton.styleFrom(
      backgroundColor: BabifixDesign.ciOrange,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                            item.category.replaceAll('_', ' '),
                            style: TextStyle(
                              color: BabifixDesign.navy,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
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
                        'Prestataire verifie',
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
                  if (item.distanceKm != null) ...[
                    const SizedBox(height: 8),
                    BabifixDistanceChip(
                      distanceKm: item.distanceKm!,
                      compact: true,
                    ),
                  ],
                  // Tarif indicatif « à partir de » — même repère de prix que
                  // sur la fiche, l'accueil et la maquette (accent orange).
                  if (item.price > 0) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.payments_outlined,
                            size: 16, color: BabifixDesign.ciOrange),
                        const SizedBox(width: 5),
                        Text(
                          'Dès ${formatFcfa(item.price)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: BabifixDesign.ciOrange,
                          ),
                        ),
                      ],
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
                              // Même fiche prestataire que l'Accueil (profil
                              // premium) pour un rendu identique partout.
                              builder: (_) => ProviderProfilePremiumScreen(
                                providerId: item.providerId,
                                onStartReservation: (service) async {
                                  final result = await Navigator.of(context)
                                      .push<Map<String, dynamic>?>(
                                    MaterialPageRoute(
                                      builder: (_) => BookingFlowScreen(
                                        serviceTitle: service.title,
                                        servicePrice: service.price,
                                        onConfirm: (data) async {
                                          final ok = await _createReservation(
                                            service,
                                            flowData: data,
                                          );
                                          if (ok && mounted) {
                                            setState(() => navIndex = 3);
                                          }
                                          return ok
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
                          ),
                          icon: const Icon(
                            Icons.info_outline_rounded,
                            size: 18,
                          ),
                          label: const Text('Details'),
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
                          child: const Text('Reserver'),
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
        return 'Especes';
      case 'MOBILE_MONEY':
        return 'Mobile Money';
      case 'CARTE':
        return 'Carte';
      default:
        return code.isEmpty ? 'N/A' : code;
    }
  }

  Widget _buildReservations() {
    final cancelled = reservations.where((r) =>
        r.status == 'Annulee' ||
        r.status == 'CANCELLED').toList();

    // « En attente client » = le presta a terminé mais le client n'a PAS encore
    // confirmé → ça reste ACTIF (à confirmer), jamais dans « Terminées », même
    // si un flag résiduel (reçu/solde) traîne d'un test précédent.
    final completed = reservations.where((r) =>
        !cancelled.contains(r) &&
        !(r.status == 'En attente client' && !r.clientConfirmed) && (
        r.status == 'Terminee' ||
        r.status == 'DONE' ||
        // Espèces : le statut backend reste « Confirmee » après la fin du
        // chantier — on s'appuie sur la confirmation client / le reçu.
        r.clientConfirmed ||
        r.receiptAvailable)).toList();

    final active = reservations.where((r) =>
        !cancelled.contains(r) &&
        !completed.contains(r) && (
        r.status == 'Confirmee' ||
        r.status == 'DEVIS_ACCEPTE' ||
        r.status == 'INTERVENTION_EN_COURS' ||
        r.status == 'En attente client' ||
        r.status == 'En cours' ||
        r.canConfirmService ||
        r.canPay ||
        _canDeclareCash(r))).toList();

    final pending = reservations.where((r) =>
        !cancelled.contains(r) &&
        !completed.contains(r) &&
        !active.contains(r)).toList();

    // Tri : le plus RÉCENT en haut dans CHAQUE section. On s'appuie sur le
    // numéro de référence (RES-005 > RES-004 …), qui est séquentiel.
    int seq(ClientReservation r) {
      final m = RegExp(r'(\d+)\s*$').firstMatch(r.reference);
      return m != null ? (int.tryParse(m.group(1)!) ?? 0) : 0;
    }
    for (final list in [active, completed, pending, cancelled]) {
      list.sort((a, b) => seq(b).compareTo(seq(a)));
    }

    return Column(
      children: [
        _buildTopBar('Rendez-vous'),
        // Raccourci historique des appels
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => const CallHistoryScreen(),
                ),
              ),
              icon: const Icon(Icons.history, size: 18),
              label: const Text('Historique des appels'),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mes reservations',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: _textPrimary,
                  ),
                ),
                Text(
                  '${reservations.length} element(s) : tirez pour actualiser',
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
                  onRefresh: _loadRemoteData,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(28, 70, 28, 120),
                    children: [
                      Center(
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                BabifixDesign.cyan.withValues(alpha: 0.22),
                                BabifixDesign.cyan.withValues(alpha: 0.05),
                              ],
                            ),
                            border: Border.all(
                              color: BabifixDesign.cyan.withValues(alpha: 0.25),
                            ),
                          ),
                          child: const Icon(
                            Icons.event_available_rounded,
                            size: 54,
                            color: BabifixDesign.cyan,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Aucune réservation pour l\'instant',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          color: _textPrimary,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Trouvez un prestataire vérifié et réservez en quelques clics. Vos demandes apparaîtront ici.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _textSecondary,
                          height: 1.5,
                          fontSize: 14.5,
                        ),
                      ),
                      const SizedBox(height: 28),
                      Center(
                        child: FilledButton.icon(
                          onPressed: () => setState(() => navIndex = 1),
                          icon: const Icon(Icons.home_repair_service_rounded),
                          label: const Text('Découvrir les services'),
                          style: FilledButton.styleFrom(
                            backgroundColor: BabifixDesign.cyan,
                            foregroundColor: BabifixDesign.navy,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 26, vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            textStyle: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 15),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadRemoteData,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 120),
                    children: [
                      // ── Pipeline visuel en haut ──────────────────────
                      _buildReservationPipeline(
                        pending: pending.length,
                        active: active.length,
                        completed: completed.length,
                        total: reservations.length,
                      ),
                      const SizedBox(height: 16),
                      // ── En attente / Devis (Nouvelles) ────────────────
                      if (pending.isNotEmpty) ...[
                        _buildSectionHeader(
                          title: 'En attente',
                          subtitle: 'Action requise de votre part',
                          count: pending.length,
                          color: const Color(0xFFF59E0B),
                          icon: Icons.hourglass_empty_rounded,
                        ),
                        ...pending.map((r) => _buildReservationCard(r, isPending: true)),
                        const SizedBox(height: 8),
                      ],
                      // ── En cours / Actives ────────────────────────────
                      if (active.isNotEmpty) ...[
                        _buildSectionHeader(
                          title: 'En cours',
                          subtitle: 'Intervention programmee ou en cours',
                          count: active.length,
                          color: const Color(0xFF4CC9F0),
                          icon: Icons.play_circle_rounded,
                        ),
                        ...active.map((r) => _buildReservationCard(r, isActive: true)),
                        const SizedBox(height: 8),
                      ],
                      // ── Terminées ─────────────────────────────────────
                      if (completed.isNotEmpty) ...[
                        _buildSectionHeader(
                          title: 'Terminées',
                          subtitle: 'Prestations finalisees',
                          count: completed.length,
                          color: const Color(0xFF22C55E),
                          icon: Icons.check_circle_rounded,
                          muted: true,
                        ),
                        ...completed.map((r) => _buildReservationCard(r, isCompleted: true)),
                        const SizedBox(height: 8),
                      ],
                      // ── Annulées ──────────────────────────────────────
                      if (cancelled.isNotEmpty) ...[
                        _buildSectionHeader(
                          title: 'Annulées',
                          subtitle: 'Reservations annulees',
                          count: cancelled.length,
                          color: const Color(0xFFEF4444),
                          icon: Icons.cancel_rounded,
                          muted: true,
                        ),
                        ...cancelled.map((r) => _buildReservationCard(r, isCancelled: true)),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildReservationPipeline({
    required int pending,
    required int active,
    required int completed,
    required int total,
  }) {
    final steps = [
      _PipelineStep(
        label: 'Demande',
        count: pending,
        icon: Icons.send_rounded,
        color: pending > 0 ? const Color(0xFFF59E0B) : const Color(0xFF475569),
        active: pending > 0,
      ),
      _PipelineStep(
        label: 'En cours',
        count: active,
        icon: Icons.build_rounded,
        color: active > 0 ? const Color(0xFF4CC9F0) : const Color(0xFF475569),
        active: active > 0,
      ),
      _PipelineStep(
        label: 'Termine',
        count: completed,
        icon: Icons.check_circle_rounded,
        color: completed > 0 ? const Color(0xFF22C55E) : const Color(0xFF475569),
        active: completed > 0,
      ),
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x22FFFFFF)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: BabifixDesign.cyan.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.route_rounded,
                  color: BabifixDesign.iconOnLight,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Suivi global',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$total total',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF7C3AED),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              for (int i = 0; i < steps.length; i++) ...[
                Expanded(
                  child: _PipelineStepWidget(step: steps[i]),
                ),
                if (i < steps.length - 1)
                  Container(
                    width: 24,
                    height: 2,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          steps[i].active ? steps[i].color : const Color(0xFF334155),
                          steps[i + 1].active ? steps[i + 1].color : const Color(0xFF334155),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    required int count,
    required Color color,
    required IconData icon,
    bool muted = false,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              color: muted ? color.withValues(alpha: 0.4) : color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 10),
          Icon(icon, size: 18, color: muted ? color.withValues(alpha: 0.6) : color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: muted ? _textSecondary : color,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: _textSecondary.withValues(alpha: muted ? 0.5 : 0.7),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: muted ? 0.1 : 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: muted ? color.withValues(alpha: 0.5) : color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReservationCard(
    ClientReservation r, {
    bool isPending = false,
    bool isActive = false,
    bool isCompleted = false,
    bool isCancelled = false,
  }) {
    final isDevis = r.status == 'DEVIS_ENVOYE' || r.canViewDevis || r.canAcceptDevis;
    final showActions = r.canConfirmService ||
        r.canPay ||
        r.canRate ||
        r.canViewDevis ||
        r.canAcceptDevis ||
        r.canPayDeposit ||
        r.canPayRemainder ||
        r.canPayCaution ||
        r.needCashRemainder ||
        _canDeclareCash(r);

    return GestureDetector(
      onTap: () => _showReservationDetails(r),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: isPending
              ? const Color(0xFF1E1508)
              : isActive
                  ? const Color(0xFF0A1B26)
                  : _cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isPending
                ? const Color(0xFFF59E0B).withValues(alpha: 0.3)
                : isActive
                    ? const Color(0xFF4CC9F0).withValues(alpha: 0.2)
                    : isCancelled
                        ? _isLight
                            ? const Color(0x0A0F172A)
                            : const Color(0x10FFFFFF)
                        : _isLight
                            ? const Color(0x120F172A)
                            : const Color(0x22FFFFFF),
            width: isPending ? 1.5 : 1,
          ),
          boxShadow: isPending
              ? [
                  BoxShadow(
                    color: const Color(0x140F172A),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : isActive
                  ? [
                      BoxShadow(
                        color: const Color(0x140F172A),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : isCancelled
                      ? null
                      : [
                          // Ombre douce pour la profondeur (cartes terminées/standard).
                          BoxShadow(
                            color: _isLight
                                ? const Color(0x140F172A)
                                : const Color(0x33000000),
                            blurRadius: 14,
                            offset: const Offset(0, 5),
                          ),
                        ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (isPending)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.access_time_rounded, size: 10, color: Color(0xFFF59E0B)),
                                    SizedBox(width: 3),
                                    Text(
                                      'Nouveau',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFFF59E0B),
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (isActive)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF4CC9F0).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.play_circle_rounded, size: 10, color: Color(0xFF4CC9F0)),
                                    SizedBox(width: 3),
                                    Text(
                                      'Actif',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF4CC9F0),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                r.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: isPending || isActive
                                      ? Colors.white
                                      : _textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (r.serviceTitle.isNotEmpty ||
                            r.providerName.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            [
                              if (r.serviceTitle.isNotEmpty) r.serviceTitle,
                              if (r.providerName.isNotEmpty) r.providerName,
                            ].join('  ·  '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12.5,
                              color: isPending || isActive
                                  ? Colors.white.withValues(alpha: 0.82)
                                  : _textPrimary,
                            ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          r.whenLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isPending || isActive
                                ? Colors.white.withValues(alpha: 0.5)
                                : _textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        // Date prévue choisie par le client (bien visible).
                        if (r.scheduledDate.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.event_rounded,
                                  size: 13,
                                  color: isPending || isActive
                                      ? const Color(0xFF7EC8E3)
                                      : const Color(0xFF0084D1)),
                              const SizedBox(width: 4),
                              Text(
                                'Prévu le ${r.scheduledDate.split('-').reversed.join('/')}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: isPending || isActive
                                      ? const Color(0xFF7EC8E3)
                                      : const Color(0xFF0084D1),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isPending || isActive
                          ? Colors.white.withValues(alpha: 0.08)
                          : isCancelled
                              ? const Color(0xFFEF4444).withValues(alpha: 0.08)
                              : const Color(0xFFE0F2FE),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _paymentLabelClient(r.paymentType),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isPending || isActive
                            ? Colors.white.withValues(alpha: 0.6)
                            : isCancelled
                                ? const Color(0xFFEF4444)
                                : const Color(0xFF0369A1),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (r.disputeOuverte) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(Icons.warning_rounded, size: 14, color: Colors.orange.shade700),
                    const SizedBox(width: 4),
                    Text(
                      'Litige signalé',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // Chrono de la prestation : live pendant l'intervention, durée
            // figée (preuve horodatée) une fois les travaux terminés.
            if (r.interventionStartedAt != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: BabifixPrestationTimer(
                  startedAt: r.interventionStartedAt,
                  endedAt: r.prestationTermineeAt,
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Row(
                children: [
                  Text(
                    _formatAmountLabel(r.amount),
                    style: TextStyle(
                      color: isPending
                          ? const Color(0xFFF59E0B)
                          : isActive
                              ? const Color(0xFF7EC8E3)
                              : _textSecondary,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  _ReservationStatusPill(
                    status: r.status,
                    statusLabel: r.statusLabel,
                    isDevis: isDevis,
                  ),
                ],
              ),
            ),
            // Actions rapides
            if (showActions) ...[
              const Divider(height: 1, color: Color(0x15FFFFFF)),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (r.canViewDevis || r.canAcceptDevis)
                      _QuickActionChip(
                        icon: Icons.description_outlined,
                        label: r.canAcceptDevis ? 'Voir & accepter' : 'Voir le devis',
                        isPrimary: r.canAcceptDevis,
                        onTap: () {
                          Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => DevisKanbanScreen(
                                reservationReference: r.reference,
                              ),
                            ),
                          );
                        },
                      ),
                    if (r.canConfirmService)
                      _QuickActionChip(
                        icon: Icons.check_circle_outline,
                        label: 'Confirmer',
                        isPrimary: true,
                        onTap: () {
                          Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => ConfirmCompletionScreen(
                                reservationReference: r.reference,
                              ),
                            ),
                          );
                        },
                      ),
                    // Mon journal — disponible dès que la prestation est terminée
                    _QuickActionChip(
                      icon: Icons.menu_book_outlined,
                      label: 'Mon journal',
                      color: const Color(0xFF0EA5E9),
                      onTap: () {
                        Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => ClientJournalScreen(
                              reservationReference: r.reference,
                            ),
                          ),
                        );
                      },
                    ),
                    // Reçu PDF — disponible après paiement complet
                    if (r.receiptAvailable)
                      _QuickActionChip(
                        icon: Icons.receipt_long_outlined,
                        label: 'Reçu',
                        color: const Color(0xFF6366F1),
                        onTap: () {
                          Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => PremiumReceiptScreen(
                                reservationReference: r.reference,
                              ),
                            ),
                          );
                        },
                      ),
                    if (r.canPay)
                      _QuickActionChip(
                        icon: Icons.payment_rounded,
                        label: 'Payer',
                        isPrimary: true,
                        onTap: () {
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
                      ),
                    if (r.canPayCaution)
                      _QuickActionChip(
                        icon: Icons.home_repair_service_rounded,
                        label: 'Caution visite',
                        isPrimary: true,
                        onTap: () => _payCaution(r),
                      ),
                    if (r.canPayDeposit)
                      _QuickActionChip(
                        icon: Icons.download_rounded,
                        label: 'Acompte',
                        isPrimary: true,
                        onTap: () => _payDeposit(r),
                      ),
                    if (r.canPayRemainder)
                      _QuickActionChip(
                        icon: Icons.done_all_rounded,
                        label: 'Solde final',
                        isPrimary: true,
                        onTap: () => _payRemainder(r),
                      ),
                    if (r.needCashRemainder)
                      _QuickActionChip(
                        icon: Icons.money_rounded,
                        label: 'Régler en espèces',
                        isPrimary: true,
                        onTap: () {
                          showBabifixToast(
                            context,
                            type: BabifixToastType.info,
                            message: 'Payez le solde directement au prestataire en espèces.',
                          );
                        },
                      ),
                    if (r.canRate)
                      _QuickActionChip(
                        icon: r.rated ? Icons.star_rounded : Icons.star_outline_rounded,
                        label: r.rated ? 'Déjà noté' : 'Noter',
                        color: r.rated ? const Color(0xFFCBD5E1) : const Color(0xFF7C3AED),
                        onTap: r.rated ? null : () => _rateReservation(r),
                      ),
                  ],
                ),
              ),
              if (_canDeclareCash(r)) ...[
                const SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: SizedBox(
                    height: 46,
                    child: Dismissible(
                      key: ValueKey('cash_${r.reference}'),
                      direction: DismissDirection.startToEnd,
                      confirmDismiss: (_) async {
                        await _declareCashPayment(r);
                        return false;
                      },
                      background: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                            SizedBox(width: 6),
                            Text('Lâcher pour confirmer',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.3)),
                          color: const Color(0xFF22C55E).withValues(alpha: 0.05),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.swipe_rounded, color: Color(0xFF22C55E), size: 18),
                            SizedBox(width: 6),
                            Text('Glissez → pour déclarer le paiement espèces',
                              style: TextStyle(color: Color(0xFF22C55E), fontWeight: FontWeight.w700, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActualites() {
    return Column(
      children: [
        _buildTopBar('Actualites'),
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
                        'Aucune actualite publiee',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: _textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'L\'equipe BABIFIX publiera ici les annonces et mises a jour.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _textSecondary, height: 1.4),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
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
                                          color: const Color(0xFF4CC9F0),
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
    final isPublic = t == null;
    try {
      final uri = Uri.parse(
        '${babifixApiBaseUrl()}/api/${isPublic ? "public" : "client"}/actualites/${a.id}',
      );
      final res = await http.get(
        uri,
        headers: isPublic ? {} : {'Authorization': 'Bearer $t'},
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
      context.push('/actualite/${full.id}', extra: full);
    } catch (_) {}
  }

  /// Explique le système d'escrow (argent bloqué) au client.
  Future<void> _showEscrowExplanation() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _isLight ? Colors.white : const Color(0xFF152A45),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.shield_rounded,
            size: 44, color: Color(0xFF22C55E)),
        title: Text(
          'Paiement sécurisé (escrow)',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: _textPrimary,
            fontSize: 18,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quand vous payez une intervention, votre argent n\'est PAS '
              'versé directement au prestataire.',
              style: TextStyle(color: _textSecondary, fontSize: 13.5, height: 1.5),
            ),
            const SizedBox(height: 12),
            _escrowStep('1', 'Vous payez', 'Le montant est conservé en '
                'sécurité par BABIFIX (ni vous, ni le prestataire ne peut y toucher).'),
            _escrowStep('2', 'Le travail est fait', 'Le prestataire réalise '
                'la mission à votre domicile.'),
            _escrowStep('3', 'Vous confirmez', 'Une fois satisfait, vous '
                'validez. L\'argent est alors libéré au prestataire.'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '🛡️ En cas de problème, vous pouvez ouvrir un litige : '
                'l\'argent reste bloqué jusqu\'à la décision de BABIFIX.',
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(
              backgroundColor: BabifixDesign.cyan,
              foregroundColor: const Color(0xFF0B1B34),
            ),
            child: const Text('J\'ai compris',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _escrowStep(String n, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF4CC9F0),
            ),
            alignment: Alignment.center,
            child: Text(n,
                style: const TextStyle(
                    color: Color(0xFF0B1B34),
                    fontWeight: FontWeight.w900,
                    fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: _textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
                Text(desc,
                    style: TextStyle(
                        color: _textSecondary, fontSize: 12, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfile() {
    // « En cours » = réservation engagée mais pas encore terminée/annulée
    // (le statut brut n'est jamais littéralement « En cours » : c'est
    // INTERVENTION_EN_COURS, En attente client, Confirmee, DEVIS_ACCEPTE…).
    const _terminal = {'Terminée', 'Terminee', 'DONE', 'Annulee', 'Annulée'};
    const _devisPhase = {'DEMANDE_ENVOYEE', 'DEVIS_EN_COURS', 'DEVIS_ENVOYE'};
    final activeCount = reservations
        .where((r) =>
            !_terminal.contains(r.status) && !_devisPhase.contains(r.status))
        .length;
    final completedCount = reservations
        .where((r) => r.status == 'Terminée' || r.status == 'Terminee')
        .length;
    // « Bloqué » = somme des montants réellement séquestrés (payés en ligne,
    // pas encore libérés au prestataire).
    final totalEscrow = reservations
        .where((r) => !r.fundsReleased && r.montantVerse > 0)
        .map((r) => r.montantVerse.round())
        .fold<int>(0, (sum, value) => sum + value);

    final hasCompleteProfile = sessionLoggedIn &&
        profileName.isNotEmpty &&
        profileEmail.isNotEmpty &&
        profilePhone.isNotEmpty;

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
                // ── Hero card profil — navy PLAT (charte sobre) ──
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 22, 16, 20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: const Color(0xFF0B1B34),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1A0F172A),
                        blurRadius: 14,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Avatar plat (sans halo cyan)
                          Container(
                            child: Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF1B4B7C),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  width: 2,
                                ),
                              ),
                              child: profileAvatarBytes != null
                                  ? ClipOval(
                                      child: Image.memory(
                                        profileAvatarBytes!,
                                        fit: BoxFit.cover,
                                        width: 72,
                                        height: 72,
                                      ),
                                    )
                                  : Center(
                                      child: Text(
                                        profileName.isNotEmpty
                                            ? profileName[0].toUpperCase()
                                            : '?',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 28,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        profileName.isEmpty
                                            ? 'Mon compte'
                                            : profileName,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.white,
                                          letterSpacing: 0.2,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (hasCompleteProfile) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Color(0xFF22C55E),
                                        ),
                                        child: const Icon(
                                          Icons.check_rounded,
                                          color: Colors.white,
                                          size: 12,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  profileEmail.isEmpty
                                      ? 'Connectez-vous ou créez un compte'
                                      : profileEmail,
                                  style: TextStyle(
                                    color: Colors.white
                                        .withValues(alpha: 0.78),
                                    fontSize: 12.5,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (profilePhone.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.phone_rounded,
                                        size: 12,
                                        color: Colors.white
                                            .withValues(alpha: 0.7),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        profilePhone,
                                        style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.78),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          // Bouton édition discret en haut à droite
                          Material(
                            color: Colors.white.withValues(alpha: 0.12),
                            shape: const CircleBorder(),
                            child: InkWell(
                              onTap: _openEditProfile,
                              customBorder: const CircleBorder(),
                              child: const Padding(
                                padding: EdgeInsets.all(10),
                                child: Icon(
                                  Icons.edit_outlined,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (sessionLoggedIn) ...[
                        const SizedBox(height: 18),
                        // 3 stats utiles, fond blanc translucide pour bon contraste
                        Row(
                          children: [
                            _HeroStat(
                              icon: Icons.event_available_rounded,
                              value: '${reservations.length}',
                              label: 'Réservations',
                            ),
                            const SizedBox(width: 10),
                            _HeroStat(
                              icon: Icons.pending_actions_rounded,
                              value: '$activeCount',
                              label: 'En cours',
                              accent: const Color(0xFFFFC857),
                            ),
                            const SizedBox(width: 10),
                            _HeroStat(
                              icon: Icons.lock_clock_rounded,
                              value: totalEscrow > 0
                                  ? formatFcfa(totalEscrow)
                                  : '0 F',
                              label: 'Bloqué',
                              accent: const Color(0xFF4ADE80),
                              valueFontSize: 13,
                            ),
                          ],
                        ),
                        if (totalEscrow > 0) ...[
                          const SizedBox(height: 10),
                          GestureDetector(
                            onTap: _showEscrowExplanation,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF22C55E)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFF22C55E)
                                      .withValues(alpha: 0.30),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.shield_rounded,
                                      color: Color(0xFF4ADE80), size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '${formatFcfa(totalEscrow)} bloqués en sécurité : '
                                      'libérés au prestataire une fois la mission terminée.',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11.5,
                                        height: 1.35,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  const Icon(Icons.info_outline_rounded,
                                      color: Colors.white54, size: 14),
                                ],
                              ),
                            ),
                          ),
                        ],
                        if (completedCount > 0) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.workspace_premium_rounded,
                                  color: Color(0xFFFFC857),
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '$completedCount chantier${completedCount > 1 ? "s" : ""} terminé${completedCount > 1 ? "s" : ""} avec BABIFIX',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
                // ── Section : Mon Compte ─────────────────────────────
                const SizedBox(height: 20),
                _SectionLabel(label: 'MON COMPTE', icon: Icons.person_rounded, color: BabifixDesign.cyan, isLight: _isLight),
                const SizedBox(height: 8),
                _PremiumActionTile(
                  icon: Icons.person_outline_rounded,
                  title: 'Modifier le profil',
                  subtitle: 'Photo, nom, coordonnees',
                  onTap: _openEditProfile,
                ),
                const SizedBox(height: 8),
                _PremiumActionTile(
                  icon: Icons.location_on_outlined,
                  title: 'Mes adresses',
                  subtitle: 'Maison, bureau… pour réserver au bon endroit',
                  onTap: () async {
                    if (!await _ensureAuthOrPrompt('gérer vos adresses')) {
                      return;
                    }
                    if (!mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const MyAddressesScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                _PremiumActionTile(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: 'Messages',
                  subtitle: 'Échanger avec vos prestataires',
                  onTap: _openMessages,
                ),
                const SizedBox(height: 8),
                _PremiumActionTile(
                  icon: Icons.emoji_events_rounded,
                  title: 'Mon Programme',
                  subtitle: 'Fidélité, garanties & parrainage',
                  onTap: () async {
                    if (!await _ensureAuthOrPrompt(
                        'accéder à votre programme de fidélité')) {
                      return;
                    }
                    if (!mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FideliteScreen(isLight: _isLight),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                _PremiumActionTile(
                  icon: Icons.gavel_rounded,
                  title: 'Mes litiges',
                  subtitle: 'Suivre l\'état de vos signalements',
                  onTap: () async {
                    if (!await _ensureAuthOrPrompt('voir vos litiges')) return;
                    if (!mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const MyDisputesScreen(),
                      ),
                    );
                  },
                ),

                // ── Section : Preferences ─────────────────────────────
                const SizedBox(height: 20),
                _SectionLabel(label: 'PRÉFÉRENCES', icon: Icons.palette_outlined, color: const Color(0xFF7C3AED), isLight: _isLight),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: _cardBg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _isLight ? const Color(0x10000000) : const Color(0x18FFFFFF)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF7C3AED).withValues(alpha: 0.12)),
                        child: const Icon(Icons.brightness_6_rounded, color: Color(0xFF7C3AED), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text("Theme d'affichage", style: TextStyle(fontWeight: FontWeight.w700, color: _textPrimary, fontSize: 14)),
                        Text(
                          switch (widget.paletteMode) {
                            AppPaletteMode.white => 'Blanc (actif)',
                            AppPaletteMode.blue => 'Bleu BABIFIX (actif)',
                            AppPaletteMode.light => 'Clair (actif)',
                          },
                          style: TextStyle(color: _textSecondary, fontSize: 12),
                        ),
                      ])),
                    ]),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final m in const [
                        (AppPaletteMode.white, 'Blanc'),
                        (AppPaletteMode.light, 'Clair'),
                        (AppPaletteMode.blue, 'Bleu BABIFIX'),
                      ])
                        ChoiceChip(
                          label: Text(m.$2),
                          selected: widget.paletteMode == m.$1,
                          onSelected: (_) => widget.onPaletteChanged(m.$1),
                        ),
                    ]),
                  ]),
                ),

                // ── Section : Securite ────────────────────────────────
                const SizedBox(height: 20),
                _SectionLabel(label: 'SÉCURITÉ', icon: Icons.lock_outline_rounded, color: const Color(0xFFF59E0B), isLight: _isLight),
                const SizedBox(height: 8),
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

                // ── Section : Support & Aide ─────────────────────────
                const SizedBox(height: 20),
                _SectionLabel(label: 'SUPPORT & AIDE', icon: Icons.support_agent_rounded, color: const Color(0xFF22C55E), isLight: _isLight),
                const SizedBox(height: 8),
                _PremiumActionTile(
                  icon: Icons.support_agent_rounded,
                  title: "Contacter l\'administrateur",
                  subtitle: contactAdminEmail.isEmpty ? 'Email support BABIFIX' : contactAdminEmail,
                  onTap: _contactAdminMail,
                ),
                const SizedBox(height: 8),
                _PremiumActionTile(
                  icon: Icons.help_center_outlined,
                  title: 'FAQ & aide',
                  subtitle: 'Guide reservation, paiement, avis',
                  onTap: _showHelpSheet,
                ),
                const SizedBox(height: 8),
                _PremiumActionTile(
                  icon: Icons.info_outline_rounded,
                  title: 'À propos de BABIFIX',
                  subtitle: 'Version, mentions legales et support',
                  onTap: () => showAboutDialog(
                    context: context,
                    applicationName: 'BABIFIX',
                    applicationVersion: '1.0.0',
                    applicationIcon: const CircleAvatar(backgroundImage: AssetImage(_logoAsset)),
                    children: const [Text('Plateforme premium de services a domicile avec reservation et paiement securise.')],
                  ),
                ),

                // ── Section : Legal ───────────────────────────────────
                const SizedBox(height: 20),
                _SectionLabel(label: 'LÉGAL', icon: Icons.description_outlined, color: const Color(0xFF64748B), isLight: _isLight),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: _cardBg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _isLight ? const Color(0x10000000) : const Color(0x18FFFFFF)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _LegalLink(label: 'CGU', icon: Icons.description_outlined, isLight: _isLight,
                          onTap: () => _launchUrl('https://babifix.ci/cgu')),
                      _VerticalDivider(isLight: _isLight),
                      _LegalLink(label: 'Confidentialite', icon: Icons.privacy_tip_outlined, isLight: _isLight,
                          onTap: () => _launchUrl('https://babifix.ci/privacy')),
                      _VerticalDivider(isLight: _isLight),
                      _LegalLink(label: 'Aide', icon: Icons.help_outline_rounded, isLight: _isLight,
                          onTap: _showHelpSheet),
                    ],
                  ),
                ),

                // ── Badge BABIFIX Protect ─────────────────────────────
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: _isLight
                          ? const [Color(0xFFF0FDF4), Color(0xFFDCFCE7)]
                          : const [Color(0xFF052010), Color(0xFF073318)],
                    ),
                    border: Border.all(color: _isLight ? const Color(0xFF86EFAC) : const Color(0x3322C55E)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.verified_user_rounded, color: Color(0xFF22C55E), size: 22),
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
                              'Paiement securise · Prestataires verifies · Support 7j/7',
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

                // ── Zone Deconnexion ──────────────────────────────────
                const SizedBox(height: 20),
                if (sessionLoggedIn) ...[
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                      gradient: LinearGradient(
                        colors: _isLight
                            ? const [Color(0xFFFFF5F5), Color(0xFFFFEBEB)]
                            : const [Color(0xFF1A0808), Color(0xFF220E0E)],
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        onTap: _logout,
                        borderRadius: BorderRadius.circular(18),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(children: [
                            Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFEF4444).withValues(alpha: 0.12)),
                              child: const Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Text('Deconnexion', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFEF4444), fontSize: 14)),
                              Text('Quitter ce compte sur cet appareil', style: TextStyle(color: const Color(0xFFEF4444).withValues(alpha: 0.7), fontSize: 12)),
                            ])),
                            const Icon(Icons.chevron_right_rounded, color: Color(0xFFEF4444)),
                          ]),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton.icon(
                      onPressed: _deleteAccount,
                      icon: Icon(Icons.delete_forever_rounded,
                          size: 16,
                          color: const Color(0xFFEF4444).withValues(alpha: 0.8)),
                      label: Text('Supprimer mon compte',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFFEF4444).withValues(alpha: 0.8))),
                    ),
                  ),
                  Center(
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 4,
                      children: [
                        TextButton(
                          onPressed: () =>
                              _launchUrl('https://babifix.ci/confidentialite/'),
                          child: const Text('Confidentialité',
                              style: TextStyle(
                                  fontSize: 11.5, color: Color(0xFF94A3B8))),
                        ),
                        const Text('·',
                            style: TextStyle(color: Color(0xFF94A3B8))),
                        TextButton(
                          onPressed: () => _launchUrl('https://babifix.ci/cgu/'),
                          child: const Text('CGU',
                              style: TextStyle(
                                  fontSize: 11.5, color: Color(0xFF94A3B8))),
                        ),
                      ],
                    ),
                  ),
                ]
                else
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: BabifixDesign.cyan.withValues(alpha: 0.3)),
                      gradient: LinearGradient(
                        colors: _isLight
                            ? const [Color(0xFFEFFAFF), Color(0xFFE0F7FE)]
                            : const [Color(0xFF071523), Color(0xFF0B2035)],
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        onTap: _openAuth,
                        borderRadius: BorderRadius.circular(18),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(children: [
                            Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(shape: BoxShape.circle, color: BabifixDesign.cyan.withValues(alpha: 0.12)),
                              child: const Icon(Icons.login_rounded, color: Color(0xFF4CC9F0), size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Text('Connexion', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF4CC9F0), fontSize: 14)),
                              Text('Se connecter ou creer un compte', style: TextStyle(color: _textSecondary, fontSize: 12)),
                            ])),
                            const Icon(Icons.chevron_right_rounded, color: Color(0xFF4CC9F0)),
                          ]),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    "BABIFIX v1.0.0 · Abidjan, Cote d'Ivoire",
                    style: TextStyle(fontSize: 11, color: _textSecondary.withValues(alpha: 0.5)),
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
    // PRIORITÉ : charger les données tout de suite. On ne bloque JAMAIS le
    // chargement de l'écran derrière l'enregistrement FCM ou LiveKit (qui
    // peuvent traîner/échouer au réveil du serveur).
    await _loadRemoteData();
    // Le reste en best-effort, non bloquant (erreurs ignorées).
    if (authToken != null) {
      BabifixFcm.registerTokenWithBackend(authToken!).catchError((_) {});
    }
    _initLiveKitForClientIfNeeded(authToken, context).catchError((_) {});
    _refreshUnreadChat().catchError((_) {});
    _attachClientRealtime().catchError((_) {});
  }

  Future<void> _loadRemoteData() async {
    if (mounted) setState(() => loadingRemote = true);

    // try/finally : quoi qu'il arrive (timeout, erreur réseau, cold start),
    // on éteint TOUJOURS le loader → l'app ne reste jamais figée sur l'écran vide.
    try {
      // Chargements EN PARALLÈLE : chaque bloc a son propre try/catch + timeout.
      // Avant, c'était séquentiel → la demande de permission GPS (dans
      // _loadPublicProviders) bloquait le chargement des actualités/catégories
      // tant que l'utilisateur n'avait pas répondu au dialogue. En parallèle,
      // les catégories et actualités s'affichent même si le GPS est en attente.
      final futures = <Future<void>>[
        _loadPublicCategories(),
        _loadPublicProviders(forceUpdate: true),
      ];
      if (authToken != null) {
        futures.add(_loadClientHomeData());
      } else {
        futures.add(_loadPublicActualites());
      }
      // Demande de localisation EN ARRIÈRE-PLAN (le dialogue système apparaît)
      // SANS bloquer l'affichage des prestataires. Une fois accordée, on
      // recharge la liste avec les distances.
      _requestLocationInBackground();
      await Future.wait(futures);
    } catch (e) {
      debugPrint('BABIFIX: _loadRemoteData error: $e');
    } finally {
      if (mounted) {
        setState(() => loadingRemote = false);
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) setState(() => _showEmptyAfterDelay = true);
        });
        // COLD START : si rien n'a chargé (serveur Render endormi → tous les
        // appels ont timeout au 1er essai), on retente automatiquement quelques
        // fois. Le serveur se réveille en ~10-50 s ; sans ce retry l'app restait
        // « vide » jusqu'à ce que l'utilisateur tire pour rafraîchir.
        _remoteLoadAttempts++;
        final rienCharge = services.isEmpty && categoryTabs.length <= 1;
        if (rienCharge && _remoteLoadAttempts < 4) {
          final delay = Duration(seconds: 3 * _remoteLoadAttempts);
          debugPrint('BABIFIX: rien chargé (essai $_remoteLoadAttempts) → retry dans ${delay.inSeconds}s');
          Future.delayed(delay, () {
            if (mounted) _loadRemoteData();
          });
        } else if (!rienCharge) {
          _remoteLoadAttempts = 0; // reset une fois des données obtenues
        }
      }
    }
  }

  /// Charge les prestataires publics sans authentification.
  /// Si la permission GPS est déjà accordée, filtre par position en temps réel.
  /// Si [forceUpdate] est true, met à jour services même si déjà chargés.
  // Demande la permission de localisation EN ARRIÈRE-PLAN (le dialogue système
  // apparaît) sans bloquer l'affichage. Si l'utilisateur accorde, on recharge
  // les prestataires pour renseigner les distances. Ne JAMAIS attendre ceci
  // dans le chemin critique d'affichage.
  bool _locationAsked = false;
  Future<void> _requestLocationInBackground() async {
    if (_locationAsked) return;
    _locationAsked = true;
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission(); // ← dialogue système
      }
      final ok = perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse;
      if (ok && mounted) {
        // On récupère une position FRAÎCHE en arrière-plan (réchauffe le cache
        // que lira ensuite _loadPublicProviders), sans bloquer l'affichage déjà
        // fait. Puis on recharge pour renseigner les distances.
        try {
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
            ),
          ).timeout(const Duration(seconds: 12));
        } catch (_) {/* pas grave : la liste est déjà affichée */}
        if (mounted) await _loadPublicProviders(forceUpdate: true);
      }
    } catch (_) {}
  }

  Future<void> _loadPublicProviders({int? categoryId, bool forceUpdate = false}) async {
    try {
      final base = babifixApiBaseUrl();
      final params = <String, String>{};

      // Filtrer par catégorie si spécifié
      if (categoryId != null) {
        params['category'] = categoryId.toString();
      }

      // Ajouter les coordonnées GPS si la permission est déjà accordée (non bloquant).
      // On vérifie via Geolocator (le plugin qui sert réellement le GPS) — son
      // check est plus fiable que permission_handler côté émulateur / certains
      // ROM Android où les deux plugins peuvent désynchroniser leur état.
      try {
        debugPrint('BABIFIX-GPS: STEP 1 checkPermission()');
        final gperm = await Geolocator.checkPermission();
        debugPrint('BABIFIX-GPS: STEP 1 result = $gperm');
        // IMPORTANT : on NE DEMANDE PAS la permission ici. Le dialogue système
        // bloquait le chargement des prestataires tant que l'utilisateur n'avait
        // pas répondu (→ catégories visibles mais prestataires absents). On
        // utilise le GPS uniquement s'il est DÉJÀ accordé ; la demande se fait à
        // l'ouverture de la carte « Prestataires près de moi ».
        final gpsOK = gperm == LocationPermission.always
            || gperm == LocationPermission.whileInUse;
        debugPrint('BABIFIX-GPS: STEP 3 gpsOK=$gpsOK');
        if (gpsOK) {
          // IMPORTANT : ici on n'utilise QUE la position en CACHE (instantanée).
          // On NE fait PLUS de getCurrentPosition (qui pouvait bloquer ~12 s sur
          // émulateur) → les prestataires s'affichent TOUT DE SUITE. La position
          // fraîche est récupérée séparément en arrière-plan
          // (_requestLocationInBackground) puis la liste se recharge.
          debugPrint('BABIFIX-GPS: STEP 4 getLastKnownPosition (cache only)...');
          final Position? pos = await Geolocator.getLastKnownPosition();
          // On n'utilise la position que si elle est en Côte d'Ivoire.
          if (pos != null && isInCotedIvoire(pos.latitude, pos.longitude)) {
            params['lat'] = pos.latitude.toStringAsFixed(6);
            params['lon'] = pos.longitude.toStringAsFixed(6);
            params['radius'] = 'auto';
            debugPrint('BABIFIX: position GPS cache (${params['lat']}, ${params['lon']}) radius=auto');
          }
        }
      } catch (e) {
        debugPrint('BABIFIX-GPS: EXCEPTION $e');
      }

      // Repli sans GPS : si aucune position n'a pu être obtenue (permission
      // refusée, GPS coupé), on utilise l'adresse enregistrée au profil pour
      // calculer quand même la distance en km vers les prestataires.
      if (!params.containsKey('lat')) {
        final saved = await BabifixUserStore.loadAddressCoords();
        if (saved != null) {
          params['lat'] = saved.lat.toStringAsFixed(6);
          params['lon'] = saved.lng.toStringAsFixed(6);
          params['radius'] = 'auto';
          debugPrint('BABIFIX-GPS: repli adresse enregistrée (${params['lat']}, ${params['lon']})');
        }
      }

      final uri = Uri.parse('$base/api/public/providers/').replace(queryParameters: params);
      debugPrint('BABIFIX: Fetching providers from: $uri');
      final pres = await http.get(uri).timeout(const Duration(seconds: 15));
      if (pres.statusCode == 200) {
        final pdata = jsonDecode(pres.body) as Map<String, dynamic>;
        final rows = (pdata['providers'] as List<dynamic>? ?? []);
        debugPrint('BABIFIX: Found ${rows.length} providers');

        // Rayon adaptatif backend : on lit ce que le serveur a réellement utilisé.
        final ru = pdata['radius_used'];
        if (ru is num) _radiusUsedKm = ru.toDouble();
        _radiusAdaptive = pdata['radius_adaptive'] == true;

        final rp = rows.map((x) {
          final dk = jsonDoubleNullable(x['distance_km']);
          return RecentProviderCard(
            id: jsonInt(x['id']),
            nom: '${x['nom'] ?? ''}',
            specialite: '${x['specialite'] ?? ''}',
            ville: '${x['ville'] ?? ''}',
            imageUrl: '${x['photo_portrait_url'] ?? x['image_url'] ?? ''}',
            tarif: null,
            disponible: x['disponible'] != false,
            distanceKm: dk,
            premiumTier: '${x['premium_tier'] ?? 'standard'}',
            premiumBadge: '${x['premium_badge'] ?? ''}',
          );
        }).toList();

        // Convertir aussi en ClientService pour l'onglet Services (fallback sans auth)
        final publicServices = rp.map((p) {
          // Use category_nom from API for proper category filtering
          final raw = rows.firstWhere(
            (r) => jsonInt(r['id']) == p.id,
            orElse: () => <String, dynamic>{},
          );
          final catName = '${raw['category_nom'] ?? ''}'.trim();
          return ClientService(
            title: p.nom,
            category: catName.isNotEmpty ? catName : p.specialite,
            duration: 'Disponible',
            price: 0,
            rating: 0.0,
            verified: true,
            color: const Color(0xFF0284c7),
            imageUrl: p.imageUrl.isNotEmpty
                ? p.imageUrl
                : 'assets/images/service-plomberie.jpg',
            providerId: p.id,
            distanceKm: p.distanceKm,
            disponible: p.disponible,
          );
        }).toList();

        if (mounted) {
          setState(() {
            recentProviders = rp;
            // Met à jour services si forceUpdate (refresh/realtime) ou si pas encore chargés
            if (forceUpdate || services.isEmpty) {
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
      final cres = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 40));
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
          // Filtre : on cache les catégories sans aucun prestataire (UX propre).
          final pc = m['providers_count'];
          if (pc is num && pc <= 0) continue;
          final fk = babifixCategoryFilterKey(nom);
          final iconUrl = '${m['icone_url'] ?? ''}'.trim();
          nextTabs = [
            ...nextTabs,
            CategoryTab(
              iconNetworkUrl: iconUrl.isNotEmpty ? iconUrl : null,
              label: nom,
              filterKey: fk,
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
    // Note : le loader est éteint par le finally de _loadRemoteData.
  }

  Future<void> _loadPublicActualites() async {
    try {
      final base = babifixApiBaseUrl();
      final url = '$base/api/public/actualites';
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 40));
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final items = (data['items'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
        setState(() {
          actualites = items.map((m) => ClientActualiteItem(
            id: jsonInt(m['id']),
            titre: '${m['titre'] ?? ''}',
            description: '${m['description'] ?? ''}',
            imageUrl: '${m['image_url'] ?? ''}',
            categorieTag: '${m['categorie_tag'] ?? ''}',
            dateLabel: '${m['date_publication'] ?? ''}'.split('T').first,
          )).toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _loadClientHomeData() async {
    try {
      final base = babifixApiBaseUrl();
      final params = <String, String>{};
      try {
        var gperm = await Geolocator.checkPermission();
        if (gperm == LocationPermission.denied) {
          gperm = await Geolocator.requestPermission();
        }
        if (gperm == LocationPermission.always || gperm == LocationPermission.whileInUse) {
          Position? pos = await Geolocator.getLastKnownPosition();
          if (pos != null && pos.timestamp != null) {
            final age = DateTime.now().difference(pos.timestamp!);
            if (age.inMinutes > 5) pos = null;
          }
          if (pos == null || !isInCotedIvoire(pos.latitude, pos.longitude)) {
            pos = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.high,
              ),
            ).timeout(
              const Duration(seconds: 12),
              onTimeout: () => throw TimeoutException('GPS timeout'),
            );
          }
          if (isInCotedIvoire(pos.latitude, pos.longitude)) {
            params['lat'] = pos.latitude.toStringAsFixed(6);
            params['lon'] = pos.longitude.toStringAsFixed(6);
          } else {
            // Hors CI (émulateur) : on préfère l'adresse réelle enregistrée.
            final saved = await BabifixUserStore.loadAddressCoords();
            params['lat'] = (saved?.lat ?? kAbidjanLat).toStringAsFixed(6);
            params['lon'] = (saved?.lng ?? kAbidjanLon).toStringAsFixed(6);
          }
        } else {
          // Pas de GPS : repli sur l'adresse enregistrée, sinon centre d'Abidjan.
          final saved = await BabifixUserStore.loadAddressCoords();
          params['lat'] = (saved?.lat ?? kAbidjanLat).toStringAsFixed(6);
          params['lon'] = (saved?.lng ?? kAbidjanLon).toStringAsFixed(6);
        }
      } catch (_) {
        final saved = await BabifixUserStore.loadAddressCoords();
        params['lat'] = (saved?.lat ?? kAbidjanLat).toStringAsFixed(6);
        params['lon'] = (saved?.lng ?? kAbidjanLon).toStringAsFixed(6);
      }
      final uri = Uri.parse('$base/api/client/home').replace(queryParameters: params.isNotEmpty ? params : null);
      final res = await BabifixUserStore.authGet(uri.toString());
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
        final cres = await http.get(Uri.parse(url));
        if (cres.statusCode == 200) {
          final cdata = jsonDecode(cres.body) as Map<String, dynamic>;
          final rows = (cdata['categories'] as List<dynamic>? ?? []);
          for (final raw in rows) {
            final m = raw as Map<String, dynamic>;
            final nom = '${m['nom'] ?? m['name'] ?? ''}'.trim();
            if (nom.isEmpty) continue;
            final fk = babifixCategoryFilterKey(nom);
            final iconUrl = '${m['icone_url'] ?? ''}'.trim();
            nextTabs = [
              ...nextTabs,
              CategoryTab(
                iconNetworkUrl: iconUrl.isNotEmpty ? iconUrl : null,
                label: nom,
                filterKey: fk,
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
              price: 0,
              rating: jsonDouble(item['rating']),
              verified: item['verified'] == true,
              color: _parseHexColor('${item['color'] ?? '#244B5A'}'),
              imageUrl: (item['image_url'] as String?)?.isNotEmpty == true
                  ? item['image_url'] as String
                  : 'assets/images/service-plomberie.jpg',
              providerId: jsonInt(item['provider_id']),
              disponible: item['disponible'] != false,
              distanceKm: jsonDoubleNullable(item['distance_km']),
            ),
          )
          .toList();

      final remoteReservations = (data['reservations'] as List<dynamic>? ?? [])
          .map(
            (item) => ClientReservation(
              title: '${item['title'] ?? ''}',
              whenLabel: '${item['when_label'] ?? ''}',
              scheduledDate: '${item['scheduled_date'] ?? ''}',
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
              canPayDeposit: jsonBool(item['can_pay_deposit']),
              canPayRemainder: jsonBool(item['can_pay_remainder']),
              cautionMontant: jsonDoubleNullable(item['caution_montant']) ?? 0,
              cautionMotif: '${item['caution_motif'] ?? ''}',
              cautionPayee: jsonBool(item['caution_payee']),
              canPayCaution: jsonBool(item['can_pay_caution']),
              needCashRemainder: jsonBool(item['need_cash_remainder']),
              receiptAvailable: jsonBool(item['receipt_available']),
              clientConfirmed:
                  '${item['client_confirme_prestation_at'] ?? ''}'.isNotEmpty,
              disputeOuverte: jsonBool(item['dispute_ouverte']),
              statusLabel: '${item['status_label'] ?? ''}'.trim(),
              latitude: _validCoord(jsonDoubleNullable(item['latitude'])),
              longitude: _validCoord(jsonDoubleNullable(item['longitude'])),
                            addressLabel: '${item['address_label'] ?? ''}'.trim(),
              addressStreet: '${item['address_street'] ?? ''}'.trim(),
              addressQuartier: '${item['address_quartier'] ?? ''}'.trim(),
              addressVille: '${item['address_ville'] ?? ''}'.trim(),
              addressPays: '${item['address_pays'] ?? ''}'.trim(),
              addressRepere: '${item['address_repere'] ?? ''}'.trim(),
              addressIsApproximate: item['address_is_approximate'] == true,
              interventionStartedAt: DateTime.tryParse(
                      '${item['intervention_started_at'] ?? ''}')
                  ?.toLocal(),
              prestationTermineeAt: DateTime.tryParse(
                      '${item['prestation_terminee_at'] ?? ''}')
                  ?.toLocal(),
              montantVerse: jsonDoubleNullable(item['montant_verse']) ?? 0,
              fundsReleased: item['funds_released'] == true,
              serviceTitle: '${item['service_title'] ?? ''}'.trim(),
              providerName: '${item['provider_name'] ?? ''}'.trim(),
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
        return RecentProviderCard(
          id: jsonInt(x['id']),
          nom: '${x['nom'] ?? ''}',
          specialite: '${x['specialite'] ?? ''}',
          ville: '${x['ville'] ?? ''}',
          imageUrl: '${x['image_url'] ?? ''}',
          tarif: null,
          disponible: x['disponible'] != false,
          distanceKm: jsonDoubleNullable(x['distance_km']),
          premiumTier: '${x['premium_tier'] ?? 'standard'}',
          premiumBadge: '${x['premium_badge'] ?? ''}',
        );
      }).toList();
      final adminMail = '${data['contact_admin_email'] ?? ''}'.trim();

      if (!mounted) return;
      setState(() {
        // Ne remplacer les categories que si nextTabs contient plus que "Tous"
        // (evite d'ecraser les 77 categories deja chargees si la requête interne a echoue)
        if (nextTabs.length > 1) {
          categoryTabs = nextTabs;
          if (categoryIndex >= categoryTabs.length) {
            categoryIndex = 0;
          }
        }
        // Si l'API retourne des services auth → ils remplacent les services publics
        // Sinon on garde les services publics deja charges
        if (remoteServices.isNotEmpty) {
          services = remoteServices;
        }
        reservations = remoteReservations;
        news = remoteNews;
        actualites = remoteActualites;
        paymentMethodsRemote = pm;
        // N'écraser les prestataires que si le home en renvoie (sinon on
        // garderait ceux déjà chargés par _loadPublicProviders au lieu de vider).
        if (rp.isNotEmpty) recentProviders = rp;
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
                    label: const Text('Especes'),
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
      if (!mounted) return false;
      // Dialog premium avec 2 choix : Se connecter / Continuer à visiter.
      final wantLogin = await promptLoginRequired(
        context,
        action: 'finaliser votre réservation',
      );
      if (!mounted) return false;
      if (wantLogin) {
        // Bascule sur l'onglet Profil + ouvre directement l'écran d'auth.
        setState(() => navIndex = 4);
        await _openAuth();
        // Connexion réussie → on REPREND la réservation automatiquement
        // (avant : on retournait false → le client devait tout recommencer).
        final t2 = await BabifixUserStore.getApiToken();
        if (mounted && t2 != null && t2.isNotEmpty) {
          return _createReservation(service, flowData: flowData);
        }
      }
      // Sinon (connexion annulée) : on reste là où on était, sans bruit.
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
    bool isUrgent = false;
    String descriptionProbleme = '';
    String disponibilites = '';
    String addressRepere = '';

    if (flowData != null) {
      whenLabel = reservationWhenLabelFromFlowData(flowData);
      paymentType = '${flowData['payment_type'] ?? 'ESPECES'}';
      // Le formulaire envoie « client_message » / « address_label » (pas
      // « message » / « address ») : on lit les bonnes clés, avec repli.
      message =
          '${flowData['client_message'] ?? flowData['message'] ?? ''}'.trim();
      addressLabel =
          '${flowData['address_label'] ?? flowData['address'] ?? ''}'.trim();
      addressRepere = '${flowData['address_repere'] ?? ''}'.trim();
      descriptionProbleme = '${flowData['description_probleme'] ?? ''}'.trim();
      disponibilites = '${flowData['disponibilites_client'] ?? ''}'.trim();
      isUrgent = flowData['is_urgent'] == true;
      // L'opérateur Mobile Money n'est plus choisi à la réservation : il sera
      // sélectionné au paiement (après le devis). On le transmet seulement
      // s'il est explicitement présent (compat. anciens flux).
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
        // pas de GPS : la reservation part quand même sans coordonnees
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
        if (message.isNotEmpty) 'client_message': message,
        if (descriptionProbleme.isNotEmpty)
          'description_probleme': descriptionProbleme,
        if (disponibilites.isNotEmpty) 'disponibilites_client': disponibilites,
        if (addressRepere.isNotEmpty) 'address_repere': addressRepere,
        if (isUrgent) 'is_urgent': true,
        if (whenLabel.isNotEmpty) 'when_label': whenLabel,
        if (service.providerId > 0) 'provider_id': service.providerId,
        if (lat != null) 'latitude': lat,
        if (lon != null) 'longitude': lon,
        if (addressLabel.isNotEmpty) 'address_label': addressLabel,
        if (photoAttachments.isNotEmpty) 'photo_attachments': photoAttachments,
      };
      debugPrint('📤 CREATE RESERVATION — URL: $uri');
      debugPrint('📤 BODY: provider_id=${body['provider_id'] ?? "null"}, title=${body['title']}, price=${body['price_fcfa']}');
      final res = await BabifixUserStore.authPost(
        uri.toString(),
        body: jsonEncode(body),
      );
      debugPrint('📥 RESPONSE — status: ${res.statusCode}, body: ${res.body}');
      if (res.statusCode == 201) {
        final respJson = jsonDecode(res.body) as Map<String, dynamic>;
        final ref = respJson['reference'] ?? '?';
        debugPrint('✅ RESERVATION CREATED — ref: $ref');
        if (mounted) {
          showBabifixToast(
        context,
        type: BabifixToastType.success,
        message: 'Réservation créée: $ref (prestataire #${service.providerId})',
        duration: const Duration(seconds: 4),
      );
          await _loadRemoteData();
        }
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
            : 'Reservation impossible (${res.statusCode})';
        showBabifixToast(
        context,
        type: BabifixToastType.info,
        message: msg,
      );
      }
    } catch (_) {
      if (mounted) {
        showBabifixToast(
        context,
        type: BabifixToastType.error,
        message: 'Erreur reseau : reessayez dans un instant.',
      );
      }
    }
    return false;
  }

  bool _canDeclareCash(ClientReservation r) {
    if (r.status.trim() != 'Terminee') return false;
    if (r.paymentType != 'ESPECES') return false;
    // Le client peut déclarer « j'ai remis l'argent » tant qu'il ne l'a pas
    // encore fait. Après paiement de la commission (acompte), cash_flow_status
    // vaut « pending_admin » — il ne faut donc PAS exiger une valeur vide
    // (c'était le bug : le slide n'apparaissait jamais). On bloque seulement une
    // fois que le presta attend (pending_prestataire), validé ou refusé.
    final s = r.cashFlowStatus.trim();
    return s != 'pending_prestataire' && s != 'validated' && s != 'refused';
  }

  /// Retourne un message utilisateur lisible selon le code HTTP.
  String _friendlyHttpError(int code) {
    switch (code) {
      case 400:
        return 'Données invalides. Vérifiez les informations saisies.';
      case 401:
        return 'Votre session a expiré. Veuillez vous reconnecter.';
      case 403:
        return 'Vous n\'avez pas les droits pour effectuer cette action.';
      case 404:
        return 'Ressource introuvable. Veuillez réessayer.';
      case 409:
        return 'Conflit détecté. Le paiement pourrait être déjà en cours.';
      case 422:
        return 'Données incomplètes. Remplissez tous les champs requis.';
      case 429:
        return 'Trop de tentatives. Patientez quelques instants.';
      case 500:
        return 'Erreur serveur. Notre équipe est informée.';
      default:
        if (code >= 500) return 'Erreur serveur temporaire. Réessayez dans un instant.';
        return 'Une erreur est survenue (code $code). Veuillez réessayer.';
    }
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
        showBabifixToast(
        context,
        type: BabifixToastType.info,
        message: 'Paiement especes declare : en attente du prestataire.',
      );
        await _loadRemoteData();
      } else {
        showBabifixToast(
        context,
        type: BabifixToastType.error,
        message: _friendlyHttpError(res.statusCode),
      );
      }
    } catch (e) {
      if (mounted) {
        showBabifixToast(
        context,
        type: BabifixToastType.error,
        message: 'Une erreur est survenue. Veuillez réessayer.',
      );
      }
    }
  }

  void _showSwipeConfirmCash(ClientReservation r) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.paddingOf(ctx).bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(
                color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2),
              )),
              const SizedBox(height: 16),
              const Icon(Icons.money_rounded, size: 48, color: Color(0xFF22C55E)),
              const SizedBox(height: 12),
              const Text('Confirmer le paiement en espèces',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text('Glissez le bouton pour confirmer que vous avez payé ${r.amount} en espèces au prestataire.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.4),
              ),
              const SizedBox(height: 24),
              BabifixSlideToConfirm(
                label: 'Glissez → j\'ai payé en espèces',
                color: const Color(0xFF22C55E),
                icon: Icons.money_rounded,
                onConfirmed: () async {
                  Navigator.pop(ctx);
                  await _declareCashPayment(r);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _payDeposit(ClientReservation r) async {
    if (authToken == null || r.reference.isEmpty) return;
    // Acompte payé via l'écran escrow (GeniusPay) — opérateur déjà choisi à la
    // réservation, montant calculé côté serveur (30 % en mobile money).
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EscrowQuoteScreen(reservationReference: r.reference),
      ),
    );
    await _loadRemoteData();
  }

  Future<void> _payCaution(ClientReservation r) async {
    if (authToken == null || r.reference.isEmpty) return;
    // Écran d'info clair AVANT de payer : le client comprend ce qu'est la
    // visite, combien et pourquoi (montant + motif + déductible du devis).
    final confirm = await _showCautionInfoSheet(r);
    if (confirm != true) return;
    final op = await _pickMobileMoneyOperator();
    if (op == null) return;
    await _sendPaymentAction(
      r: r,
      endpoint: 'pay-caution',
      successMsg: 'Caution réglée. Le prestataire va organiser la visite.',
      body: {'mobile_money_operator': op},
    );
  }

  Future<bool?> _showCautionInfoSheet(ClientReservation r) {
    final montant = r.cautionMontant.toStringAsFixed(0);
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: _cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: _textSecondary.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: BabifixDesign.ciBlue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.home_repair_service_rounded,
                        color: BabifixDesign.ciBlue, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Visite de diagnostic',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: _textPrimary)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Le prestataire souhaite se déplacer pour évaluer votre demande '
                'avant de vous proposer un devis précis.',
                style: TextStyle(
                    fontSize: 13.5, height: 1.45, color: _textSecondary),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: BabifixDesign.ciBlue.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: BabifixDesign.ciBlue.withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Caution demandée',
                        style: TextStyle(
                            fontSize: 12, color: _textSecondary)),
                    const SizedBox(height: 4),
                    Text('$montant FCFA',
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: _textPrimary)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.info_outline_rounded,
                            size: 14, color: BabifixDesign.ciBlue),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            'Entièrement déduite de votre devis final si vous '
                            'l\'acceptez.',
                            style: TextStyle(
                                fontSize: 11.5,
                                color: _textSecondary,
                                height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (r.cautionMotif.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Motif du prestataire',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _textSecondary)),
                const SizedBox(height: 3),
                Text(r.cautionMotif,
                    style: TextStyle(
                        fontSize: 13.5, height: 1.4, color: _textPrimary)),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        side: BorderSide(
                            color: _textSecondary.withValues(alpha: 0.3)),
                      ),
                      child: Text('Plus tard',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _textPrimary)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: BabifixDesign.ciOrange,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: const Text('Payer la caution',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15)),
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

  Future<void> _payRemainder(ClientReservation r) async {
    if (authToken == null || r.reference.isEmpty) return;
    // Solde (70 %) payé via le même écran escrow/GeniusPay : il détecte la
    // phase "solde" et facture uniquement le reste dû.
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EscrowQuoteScreen(reservationReference: r.reference),
      ),
    );
    await _loadRemoteData();
  }

  Future<void> _sendPaymentAction({
    required ClientReservation r,
    required String endpoint,
    required String successMsg,
    required Map<String, String> body,
  }) async {
    if (authToken == null || r.reference.isEmpty) return;
    try {
      final uri = Uri.parse(
        '${babifixApiBaseUrl()}/api/client/reservations/${Uri.encodeComponent(r.reference)}/$endpoint',
      );
      final res = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $authToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        showBabifixToast(context, type: BabifixToastType.success, message: successMsg);
        await _loadRemoteData();
      } else {
        final detail = _extractDetail(res.body);
        showBabifixToast(
          context,
          type: BabifixToastType.error,
          message: detail ?? _friendlyHttpError(res.statusCode),
        );
      }
    } catch (e) {
      if (mounted) {
        showBabifixToast(
          context,
          type: BabifixToastType.error,
          message: 'Erreur réseau. Veuillez réessayer.',
        );
      }
    }
  }

  Future<String?> _pickMobileMoneyOperator() async {
    final op = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Opérateur mobile money'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'ORANGE_MONEY'),
            child: const ListTile(
              leading: Icon(Icons.phone_android),
              title: Text('Orange Money'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'MTN_MOMO'),
            child: const ListTile(
              leading: Icon(Icons.phone_android),
              title: Text('MTN Mobile Money'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'WAVE'),
            child: const ListTile(
              leading: Icon(Icons.phone_android),
              title: Text('Wave'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'MOOV'),
            child: const ListTile(
              leading: Icon(Icons.phone_android),
              title: Text('Moov'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
    return op;
  }

  String? _extractDetail(String body) {
    try {
      final d = jsonDecode(body);
      if (d is Map && d['detail'] != null && '${d['detail']}'.isNotEmpty) {
        return '${d['detail']}';
      }
    } catch (_) {}
    return null;
  }

  // ── Statut → style visuel (couleur, icône, libellé, étape timeline) ──
  ({Color color, IconData icon, String label, int step}) _resaStatusMeta(
      ClientReservation r) {
    final s = r.status.trim();
    final low = s.toLowerCase();
    if (low.contains('annul')) {
      return (color: const Color(0xFFEF4444), icon: Icons.cancel_rounded,
          label: 'Annulée', step: 0);
    }
    // Le prestataire a terminé mais le CLIENT n'a pas encore confirmé.
    // État DISTINCT (surtout pas « Terminée ») : il reste l'étape de
    // confirmation. Timeline : intervention faite, « Terminé » encore en attente.
    // On le place avant le test « terminé » pour ignorer d'éventuels flags
    // résiduels (receipt/solde) tant que le client n'a pas confirmé.
    if (s == 'En attente client' && !r.clientConfirmed) {
      return (color: const Color(0xFFF59E0B), icon: Icons.fact_check_rounded,
          label: 'À confirmer', step: 3);
    }
    // Terminée : statut backend « Terminee/DONE », OU prestation confirmée par
    // le client / reçu disponible (cas espèces où le statut reste « Confirmee »).
    // Aligne la fiche détail sur le regroupement « Terminées » de la liste :
    // timeline complète (étape 4) + bouton « Voir le reçu ».
    if (low.contains('termin') || r.clientConfirmed || r.receiptAvailable) {
      return (color: const Color(0xFF22C55E), icon: Icons.verified_rounded,
          label: 'Terminée', step: 4);
    }
    if (s == 'INTERVENTION_EN_COURS' || low == 'en cours' ||
        low.contains('cours')) {
      return (color: const Color(0xFF4CC9F0), icon: Icons.build_circle_rounded,
          label: 'Intervention en cours', step: 3);
    }
    if (s == 'DEVIS_ACCEPTE' || low.contains('confirm')) {
      return (color: const Color(0xFF4CC9F0), icon: Icons.task_alt_rounded,
          label: 'Devis accepté', step: 2);
    }
    if (s == 'DEVIS_ENVOYE') {
      return (color: const Color(0xFFF59E0B), icon: Icons.description_rounded,
          label: 'Devis reçu', step: 2);
    }
    if (s == 'DEVIS_EN_COURS') {
      return (color: const Color(0xFFF59E0B), icon: Icons.hourglass_top_rounded,
          label: 'Devis en préparation', step: 1);
    }
    // DEMANDE_ENVOYEE / En attente
    return (color: const Color(0xFFF59E0B), icon: Icons.send_rounded,
        label: r.statusLabel.isNotEmpty ? r.statusLabel : 'Demande envoyée',
        step: 1);
  }

  String _formatAmountLabel(String raw) {
    final n = double.tryParse(raw);
    if (n == null || n == 0) return raw;
    return formatFcfa(n.round());
  }

  void _showReservationDetails(ClientReservation r) {
    final meta = _resaStatusMeta(r);
    final isCompleted = meta.step == 4;
    final isCancelled = r.status.toLowerCase().contains('annul');
    // "Payer" en ligne : seulement si pas terminé/annulé.
    final showPayOnline = r.canPay && !isCompleted && !isCancelled;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.68,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        builder: (_, controller) => Container(
          decoration: BoxDecoration(
            color: _isLight ? const Color(0xFFF8FAFC) : const Color(0xFF0F1F38),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: controller,
            padding: EdgeInsets.zero,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  decoration: BoxDecoration(
                    color: _textSecondary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),

              // ── Header coloré selon le statut ──
              Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      meta.color.withValues(alpha: 0.20),
                      meta.color.withValues(alpha: 0.06),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: meta.color.withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: meta.color.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(meta.icon, color: meta.color, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r.title,
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  color: _textPrimary,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                meta.label,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: meta.color,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Montant',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: _textSecondary,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(
                              _formatAmountLabel(r.amount),
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF4CC9F0),
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: _isLight
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                r.paymentType == 'MOBILE_MONEY'
                                    ? Icons.phone_iphone_rounded
                                    : Icons.payments_rounded,
                                size: 13,
                                color: _textSecondary,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                r.paymentType == 'MOBILE_MONEY'
                                    ? 'Mobile Money'
                                    : 'Espèces',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    color: _textSecondary,
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Timeline de progression ──
              if (!isCancelled)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                  child: _ResaTimeline(currentStep: meta.step),
                ),

              // ── Infos détaillées ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: Column(
                  children: [
                    if (r.whenLabel.isNotEmpty)
                      _detailRow(Icons.schedule_rounded, 'Quand', r.whenLabel),
                    if (r.addressLabel.isNotEmpty)
                      _detailRow(Icons.location_on_outlined, 'Adresse',
                          r.addressLabel),
                    if (r.reference.isNotEmpty)
                      _detailRow(Icons.tag_rounded, 'Référence', r.reference),
                  ],
                ),
              ),

              // ── Carte du lieu d'intervention ──
              if (r.latitude != null && r.longitude != null &&
                  isInCotedIvoire(r.latitude!, r.longitude!))
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: BabifixOsmStaticPreview(
                      center: LatLng(r.latitude!, r.longitude!),
                      height: 140,
                    ),
                  ),
                ),

              // ── Litige ouvert (si applicable) ──
              if (r.disputeOuverte)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.gavel_rounded,
                          color: Color(0xFFF59E0B), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Litige en cours : suivi avec BABIFIX',
                          style: TextStyle(
                            color: _textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // ── Actions contextuelles ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
                child: _buildResaActions(
                  ctx, r, meta,
                  showPayOnline: showPayOnline,
                  isCompleted: isCompleted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: _textSecondary),
          const SizedBox(width: 10),
          Text('$label : ',
              style: TextStyle(
                  fontSize: 13,
                  color: _textSecondary,
                  fontWeight: FontWeight.w600)),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 13,
                    color: _textPrimary,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildResaActions(
    BuildContext ctx,
    ClientReservation r,
    ({Color color, IconData icon, String label, int step}) meta, {
    required bool showPayOnline,
    required bool isCompleted,
  }) {
    final actions = <Widget>[];

    if (r.canConfirmService) {
      actions.add(_resaActionBtn(
        icon: Icons.check_circle_outline_rounded,
        label: 'Confirmer la prestation',
        primary: true,
        onTap: () {
          Navigator.pop(ctx);
          _confirmPrestationClient(r);
        },
      ));
    }
    if (r.canViewDevis || r.canAcceptDevis || r.status == 'DEVIS_ENVOYE') {
      actions.add(_resaActionBtn(
        icon: Icons.description_outlined,
        label: r.canAcceptDevis ? 'Voir & accepter le devis' : 'Voir le devis',
        primary: true,
        onTap: () {
          Navigator.pop(ctx);
          Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => DevisKanbanScreen(
                reservationReference: r.reference,
              ),
            ),
          );
        },
      ));
    }
    if (r.canPayDeposit) {
      actions.add(_resaActionBtn(
        icon: Icons.download_rounded,
        label: "Payer l'acompte (30%)",
        primary: true,
        onTap: () {
          Navigator.pop(ctx);
          _payDeposit(r);
        },
      ));
    }
    if (r.canPayRemainder) {
      actions.add(_resaActionBtn(
        icon: Icons.done_all_rounded,
        label: "Payer le solde final",
        primary: true,
        onTap: () {
          Navigator.pop(ctx);
          _payRemainder(r);
        },
      ));
    }
    if (r.needCashRemainder) {
      actions.add(_resaActionBtn(
        icon: Icons.money_rounded,
        label: "Solde à régler en espèces",
        accent: const Color(0xFF22C55E),
        onTap: () {
          Navigator.pop(ctx);
          showBabifixToast(
            context,
            type: BabifixToastType.info,
            message: 'Payez le solde de ${r.amount} directement au prestataire en espèces.',
          );
        },
      ));
    }
    if (showPayOnline) {
      actions.add(_resaActionBtn(
        icon: Icons.payment_rounded,
        label: 'Payer en ligne',
        primary: true,
        onTap: () {
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
      ));
    }
    if (_canDeclareCash(r)) {
      actions.add(_resaActionBtn(
        icon: Icons.swipe_rounded,
        label: 'Glisser pour confirmer espèces',
        accent: const Color(0xFF22C55E),
        onTap: () {
          Navigator.pop(ctx);
          _showSwipeConfirmCash(r);
        },
      ));
    }
    if (r.canRate) {
      actions.add(_resaActionBtn(
        icon: r.rated ? Icons.star_rounded : Icons.star_outline_rounded,
        label: r.rated ? 'Déjà noté' : 'Noter le prestataire',
        accent: r.rated ? const Color(0xFFCBD5E1) : const Color(0xFFF59E0B),
        onTap: r.rated
            ? null
            : () {
                Navigator.pop(ctx);
                _rateReservation(r);
              },
      ));
    }
    // Devis : consultable dès qu'un devis a été envoyé (étape ≥ 2), y compris
    // sur une réservation terminée — photos, diagnostic, montant restent visibles.
    if (meta.step >= 2) {
      actions.add(_resaActionBtn(
        icon: Icons.description_rounded,
        label: 'Voir le devis',
        accent: const Color(0xFF4CC9F0),
        onTap: () {
          Navigator.pop(ctx);
          Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => DevisDetailScreen(
                reservationReference: r.reference,
                onBack: () => Navigator.of(context).maybePop(),
              ),
            ),
          );
        },
      ));
    }
    if (isCompleted) {
      // Reçu
      actions.add(_resaActionBtn(
        icon: Icons.receipt_long_rounded,
        label: 'Voir le reçu',
        onTap: () {
          Navigator.pop(ctx);
          Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => PremiumReceiptScreen(
                reservationReference: r.reference,
              ),
            ),
          );
        },
      ));
    }
    // Signaler un problème : possible tant que pas déjà en litige et résa avancée
    if (!r.disputeOuverte && (isCompleted || meta.step >= 3)) {
      actions.add(_resaActionBtn(
        icon: Icons.report_problem_outlined,
        label: 'Signaler un problème',
        accent: const Color(0xFFEF4444),
        onTap: () {
          Navigator.pop(ctx);
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DisputeOpenScreen(
                reservationReference: r.reference,
                reservationTitle: r.title,
              ),
            ),
          );
        },
      ));
    }

    if (actions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _isLight
              ? Colors.white
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded,
                size: 18, color: _textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Aucune action requise pour le moment.',
                style: TextStyle(color: _textSecondary, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Actions',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: _textPrimary)),
        const SizedBox(height: 12),
        ...actions
            .expand((w) => [w, const SizedBox(height: 10)])
            .toList()
          ..removeLast(),
      ],
    );
  }

  Widget _resaActionBtn({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    bool primary = false,
    Color? accent,
  }) {
    final c = accent ?? const Color(0xFF4CC9F0);
    if (primary) {
      return SizedBox(
        height: 50,
        child: FilledButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          label: Text(label,
              style: const TextStyle(fontWeight: FontWeight.w800)),
          style: FilledButton.styleFrom(
            backgroundColor: c,
            foregroundColor: const Color(0xFF0B1B34),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
        ),
      );
    }
    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18, color: c),
        label: Text(label,
            style: TextStyle(color: c, fontWeight: FontWeight.w700)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: c.withValues(alpha: 0.6), width: 1.4),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  /// Télécharge le reçu PDF (le backend accepte ?token= en query).
  Future<void> _downloadReceipt(ClientReservation r) async {
    final token = await BabifixUserStore.getApiToken();
    if (token == null || r.reference.isEmpty) return;
    final uri = Uri.parse(
      '${babifixApiBaseUrl()}/api/client/reservations/${Uri.encodeComponent(r.reference)}/receipt/pdf/',
    ).replace(queryParameters: {'token': token});
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      showBabifixToast(
        context,
        type: BabifixToastType.error,
        message: 'Impossible d\'ouvrir le reçu.',
      );
    }
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
        showBabifixToast(
        context,
        type: BabifixToastType.success,
        message: 'Prestation confirmee : vous pouvez choisir le mode de paiement.',
      );
        await _loadRemoteData();
      } else {
        showBabifixToast(
        context,
        type: BabifixToastType.error,
        message: _friendlyHttpError(res.statusCode),
      );
      }
    } catch (e) {
      if (mounted) {
        showBabifixToast(
        context,
        type: BabifixToastType.error,
        message: 'Une erreur est survenue. Veuillez réessayer.',
      );
      }
    }
  }

  Future<void> _openPostPrestationPaySheet(ClientReservation r) async {
    if (authToken == null || r.reference.isEmpty) return;
    final methods = paymentMethodsRemote.isNotEmpty
        ? paymentMethodsRemote
        : const [
            PaymentMethodOption(id: 'ESPECES', label: 'Especes', logoUrl: ''),
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
                  'Paiement : ${r.reference}',
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
        showBabifixToast(
        context,
        type: BabifixToastType.success,
        message: 'Paiement enregistre (MVP).',
      );
        await _loadRemoteData();
      } else {
        showBabifixToast(
        context,
        type: BabifixToastType.error,
        message: _friendlyHttpError(res.statusCode),
      );
      }
    } catch (e) {
      if (mounted) {
        showBabifixToast(
        context,
        type: BabifixToastType.error,
        message: 'Une erreur est survenue. Veuillez réessayer.',
      );
      }
    }
  }

  Future<void> _contactAdminMail() async {
    final e = contactAdminEmail.trim();
    if (e.isEmpty) {
      if (mounted) {
        showBabifixToast(
        context,
        type: BabifixToastType.info,
        message: 'Email admin non configure.',
      );
      }
      return;
    }
    final uri = Uri(
      scheme: 'mailto',
      path: e,
      queryParameters: {'subject': 'BABIFIX : Support client'},
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
                        'La prestation est passee',
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
                    if (r.latitude != null && r.longitude != null &&
                        isInCotedIvoire(r.latitude!, r.longitude!)) ...[
                      const SizedBox(height: 20),
                      Text(
                        'Lieu de l\'intervention',
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
                      hint: 'Commentaire ou details utiles (optionnel)',
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
        r.rated = true;
        showBabifixToast(
        context,
        type: BabifixToastType.info,
        message: 'Merci pour votre avis !',
      );
        await _loadRemoteData();
      } else {
        showBabifixToast(
        context,
        type: BabifixToastType.error,
        message: _friendlyHttpError(res.statusCode),
      );
      }
    } catch (e) {
      if (mounted) {
        showBabifixToast(
        context,
        type: BabifixToastType.info,
        message: 'Une erreur est survenue lors de l\'envoi de votre avis.',
      );
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
    if (path.isEmpty) {
      return const AssetImage('assets/images/babifix-logo.png');
    }
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
    if (token == null || token.isEmpty) {
      final wantLogin = await promptLoginRequired(
        context,
        action: 'voir vos messages',
      );
      if (!mounted || !wantLogin) return;
      setState(() => navIndex = 4);
      await _openAuth();
      return;
    }
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

  /// Helper réutilisable pour toute action exigeant un compte.
  /// Retourne `true` si l'utilisateur est connecté (ou vient de l'être),
  /// `false` s'il préfère continuer à visiter.
  Future<bool> _ensureAuthOrPrompt(String action) async {
    final token = await BabifixUserStore.getApiToken();
    if (token != null && token.isNotEmpty) return true;
    if (!mounted) return false;
    final wantLogin = await promptLoginRequired(context, action: action);
    if (!mounted || !wantLogin) return false;
    setState(() => navIndex = 4);
    await _openAuth();
    final again = await BabifixUserStore.getApiToken();
    return again != null && again.isNotEmpty;
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
                      ? const Color(0xFF4CC9F0)
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

class _ReservationStatusPill extends StatelessWidget {
  const _ReservationStatusPill({
    required this.status,
    required this.statusLabel,
    required this.isDevis,
  });

  final String status;
  final String statusLabel;
  final bool isDevis;

  @override
  Widget build(BuildContext context) {
    final label = statusLabel.isNotEmpty
        ? statusLabel
        : (isDevis ? 'Devis reçu' : status);

    late Color bg;
    late Color fg;
    if (isDevis) {
      bg = const Color(0xFFF59E0B).withValues(alpha: 0.15);
      fg = const Color(0xFFF59E0B);
    } else if (status == 'Confirmee' || status == 'DEVIS_ACCEPTE') {
      bg = const Color(0xFF4CC9F0).withValues(alpha: 0.15);
      fg = const Color(0xFF4CC9F0);
    } else if (status == 'INTERVENTION_EN_COURS') {
      bg = const Color(0xFF7C3AED).withValues(alpha: 0.15);
      fg = const Color(0xFF7C3AED);
    } else if (status == 'Terminee' || status == 'DONE') {
      bg = const Color(0xFF22C55E).withValues(alpha: 0.15);
      fg = const Color(0xFF22C55E);
    } else if (status == 'Annulee') {
      bg = const Color(0xFFEF4444).withValues(alpha: 0.15);
      fg = const Color(0xFFEF4444);
    } else {
      bg = const Color(0x1AFFFFFF);
      fg = const Color(0xFF94A3B8);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  const _QuickActionChip({
    required this.icon,
    required this.label,
    this.color,
    this.isPrimary = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  /// Conservé pour compat. d'appel ; ignoré au profit d'un rendu sobre
  /// (1 seul accent par écran : orange pour l'action principale, ardoise
  /// neutre pour les actions secondaires — fini l'arc‑en‑ciel « IA »).
  final Color? color;
  final bool isPrimary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Action principale = bouton plein orange (CTA). Secondaire = puce
    // neutre ardoise, discrète et uniforme.
    const primary = Color(0xFFE87722);
    const neutral = Color(0xFF64748B);
    final fg = isPrimary ? Colors.white : neutral;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: isPrimary ? primary : neutral.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: isPrimary
              ? null
              : Border.all(color: neutral.withValues(alpha: 0.22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PipelineStep {
  final String label;
  final int count;
  final IconData icon;
  final Color color;
  final bool active;
  const _PipelineStep({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
    required this.active,
  });
}

class _PipelineStepWidget extends StatelessWidget {
  const _PipelineStepWidget({required this.step});
  final _PipelineStep step;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: step.color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(
              color: step.color.withValues(alpha: step.active ? 0.4 : 0.15),
              width: step.active ? 2 : 1,
            ),
          ),
          child: Icon(
            step.icon,
            size: 18,
            color: step.color,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${step.count}',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: step.color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          step.label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: step.active ? Colors.white.withValues(alpha: 0.8) : const Color(0xFF64748B),
          ),
        ),
      ],
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

/// Raccourcis visibles sur l'onglet Accueil.
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

/// Puce operateur Mobile Money (logo + libelle).
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
          Icon(icon, size: 22, color: const Color(0xFF4CC9F0)),
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
// ── Statistique du hero profil (fond translucide sur gradient sombre) ───────
/// Timeline horizontale de progression d'une réservation.
/// 4 étapes : Demande → Devis → Intervention → Terminé.
class _ResaTimeline extends StatelessWidget {
  final int currentStep; // 1..4
  const _ResaTimeline({required this.currentStep});

  static const _steps = [
    (icon: Icons.send_rounded, label: 'Demande'),
    (icon: Icons.description_rounded, label: 'Devis'),
    (icon: Icons.build_circle_rounded, label: 'Intervention'),
    (icon: Icons.verified_rounded, label: 'Terminé'),
  ];

  @override
  Widget build(BuildContext context) {
    const cyan = Color(0xFF4CC9F0);
    const green = Color(0xFF22C55E);
    final isLight = Theme.of(context).brightness == Brightness.light;
    final idleColor = isLight
        ? const Color(0xFFCBD5E1)
        : Colors.white.withValues(alpha: 0.18);
    final idleText = isLight
        ? const Color(0xFF94A3B8)
        : Colors.white.withValues(alpha: 0.5);

    return Row(
      children: List.generate(_steps.length * 2 - 1, (i) {
        // Connecteurs aux index impairs.
        if (i.isOdd) {
          final leftStep = (i ~/ 2) + 1; // étape à gauche du connecteur
          final done = currentStep > leftStep;
          return Expanded(
            child: Container(
              height: 3,
              margin: const EdgeInsets.only(bottom: 18),
              color: done ? green : idleColor,
            ),
          );
        }
        final stepIndex = i ~/ 2; // 0..3
        final stepNum = stepIndex + 1;
        final reached = currentStep >= stepNum;
        final isCurrent = currentStep == stepNum;
        final c = currentStep == 4 && stepNum == 4
            ? green
            : (reached ? cyan : idleColor);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: reached ? c : Colors.transparent,
                border: Border.all(
                    color: reached ? c : idleColor, width: 2),
                boxShadow: isCurrent
                    ? [BoxShadow(color: c.withValues(alpha: 0.4), blurRadius: 8)]
                    : null,
              ),
              child: Icon(
                _steps[stepIndex].icon,
                size: 16,
                color: reached ? Colors.white : idleText,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              _steps[stepIndex].label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w500,
                color: reached
                    ? (isLight ? const Color(0xFF0F172A) : Colors.white)
                    : idleText,
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color accent;
  final double valueFontSize;

  const _HeroStat({
    required this.icon,
    required this.value,
    required this.label,
    this.accent = const Color(0xFF4CC9F0),
    this.valueFontSize = 15,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.14),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: accent, size: 18),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: valueFontSize,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Lien legal compact ────────────────────────────────────────────────────────
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

// ─────────────────────────────────────────────────────────────────────────────
// Section label with colored icon stripe
// ─────────────────────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isLight;

  const _SectionLabel({required this.label, required this.icon, required this.color, required this.isLight});

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
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Blanc'),
                    selected: widget.currentMode == AppPaletteMode.white,
                    onSelected: (_) =>
                        widget.onModeChanged(AppPaletteMode.white),
                  ),
                  ChoiceChip(
                    label: const Text('Clair'),
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

// ─────────────────────────────────────────────────────────────────────────────
// _RadiusBanner — bandeau "Recherche élargie à X km" affiché au-dessus de la
// liste des prestataires quand le backend a dû élargir le rayon en mode auto.
// ─────────────────────────────────────────────────────────────────────────────
class _RadiusBanner extends StatefulWidget {
  const _RadiusBanner({required this.radiusKm});
  final double radiusKm;

  @override
  State<_RadiusBanner> createState() => _RadiusBannerState();
}

class _RadiusBannerState extends State<_RadiusBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: BabifixDesign.cyan.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: BabifixDesign.cyan.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _ctl,
            builder: (_, _) {
              return Transform.rotate(
                angle: _ctl.value * 6.283,
                child: Icon(Icons.radar_rounded,
                    size: 18, color: BabifixDesign.cyan),
              );
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Recherche élargie à ${widget.radiusKm.round()} km pour trouver des prestataires.',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
