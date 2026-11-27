import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
// import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';  // désactivé : voir services/zego_call_service.dart
// import 'package:zego_uikit_signaling_plugin/zego_uikit_signaling_plugin.dart';

import 'babifix_design_system.dart';
import 'babifix_api_config.dart';
import 'babifix_fcm.dart';
import 'json_utils.dart';

import 'shared/app_palette_mode.dart';
import 'shared/services/app_lock_gate.dart';
import 'shared/services/babifix_remote_config.dart';
import 'shared/auth_utils.dart';
import 'shared/in_app_notifications.dart';
import 'shared/widgets/babifix_button.dart';
import 'services/notification_overlay.dart';
import 'services/notification_sound_service.dart';
import 'services/zego_call_service.dart';

import 'features/earnings/earnings_screen.dart' as earnings_feature;
import 'features/auth/landing_screen.dart';
import 'splash_screen.dart';
import 'features/auth/onboarding_screen.dart';
import 'features/auth/registration_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/pending_screen.dart';
import 'features/auth/refused_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/dashboard/floating_nav_bar.dart'
    show
        babifixNewRequestsCount,
        babifixReservationsTick,
        babifixOpenReservationRef;
import 'features/requests/requests_screen.dart';
import 'features/messages/messages_screen.dart';
import 'features/profile/contrat_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/kyc/kyc_screen.dart';
import 'features/actualites/actualites_screen.dart';
import 'features/wallet/wallet_screen.dart' as wallet_feature;
import 'services/fcm_router.dart';
import 'services/location_reporter.dart';
import 'shared/widgets/babifix_snackbar.dart';
import 'shared/widgets/app_version_gate.dart';
import 'shared/widgets/error_reporter.dart';

// Alias avec BabifixFcmRouter · un seul navigatorKey pour tout (calls in/out).
final GlobalKey<NavigatorState> zegoNavigatorKey =
    BabifixFcmRouter.navigatorKey;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Monitoring : capter les crashs et les remonter au backend (→ Sentry).
  initErrorReporter(app: 'prestataire', version: kAppVersion);

  try {
    await dotenv.load(fileName: ".env");
  } catch (_) {}

  await babifixResolveLocalApiBaseUrl();
  try {
    await BabifixFcm.ensureInitialized();
  } catch (e) {
    debugPrint('BABIFIX FCM init failed: $e');
  }
  // Charge la config dynamique plateforme (commissions, seuils, modes paiement).
  // ignore: unawaited_futures
  BabifixRemoteConfig.instance.initAndSync();

  // Géolocalisation auto : push la position GPS du prestataire au backend
  // dès l'ouverture de l'app + à chaque resume foreground. Non bloquant.
  // ignore: unawaited_futures
  LocationReporter.instance.attach();

  // Zego SDK temporairement désactivé · voir services/zego_call_service.dart
  // if (isZegoConfigured) {
  //   ZegoUIKitPrebuiltCallInvitationService().setNavigatorKey(zegoNavigatorKey);
  // }

  runApp(const BabifixPrestataireApp());
}

class BabifixPrestataireApp extends StatefulWidget {
  const BabifixPrestataireApp({super.key});

  @override
  State<BabifixPrestataireApp> createState() => _BabifixPrestataireAppState();
}

class _BabifixPrestataireAppState extends State<BabifixPrestataireApp> {
  AppPaletteMode paletteMode = AppPaletteMode.white;
  bool _loadedPrefs = false;

  @override
  void initState() {
    super.initState();
    _loadPalette();
    BabifixNotificationSoundService.ensureInitialized();
  }

  Future<void> _loadPalette() async {
    // Charge les prefs ET garde un délai minimum pour laisser l'animation
    // du splash respirer (1800ms ≈ animation entrée + 1 boucle de loader).
    final started = DateTime.now();
    final p = await SharedPreferences.getInstance();
    final vStr = p.getString('prestataire_palette') ?? 'white';
    final elapsed = DateTime.now().difference(started);
    const minSplash = Duration(milliseconds: 1800);
    if (elapsed < minSplash) {
      await Future.delayed(minSplash - elapsed);
    }
    if (!mounted) return;
    setState(() {
      paletteMode = switch (vStr) {
        'blue' => AppPaletteMode.blue,
        'light' => AppPaletteMode.light,
        _ => AppPaletteMode.white,
      };
      _loadedPrefs = true;
    });
  }

  Future<void> _setPalette(AppPaletteMode m) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      'prestataire_palette',
      switch (m) {
        AppPaletteMode.blue => 'blue',
        AppPaletteMode.white => 'white',
        AppPaletteMode.light => 'light',
      },
    );
    if (!mounted) return;
    setState(() => paletteMode = m);
  }

  ThemeData _themeForMode(AppPaletteMode mode) {
    final base = ThemeData(useMaterial3: true);
    final isDark = mode == AppPaletteMode.blue;
    final isWhite = mode == AppPaletteMode.white;
    final isLight = !isDark;
    final bg = isDark
        ? BabifixDesign.navy
        : (isWhite ? BabifixDesign.bgWhite : BabifixDesign.bgLight);
    final onBg = isLight
        ? BabifixDesign.textStrongLight
        : BabifixDesign.textStrongDark;
    final muted = isLight
        ? BabifixDesign.textMutedLight
        : BabifixDesign.textMutedDark;
    final surface = isLight
        ? BabifixDesign.bgWhite
        : BabifixDesign.navySurface;
    final border = isDark ? BabifixDesign.borderDark : BabifixDesign.borderLight;
    final cs = ColorScheme.fromSeed(
      seedColor: BabifixDesign.navy,
      brightness: isLight ? Brightness.light : Brightness.dark,
    ).copyWith(
      primary: isDark ? BabifixDesign.cyan : BabifixDesign.navy,
      onPrimary: isDark ? BabifixDesign.navy : Colors.white,
      surface: surface,
      onSurface: onBg,
      secondary: isDark ? BabifixDesign.ciOrangeBright : BabifixDesign.ciOrange,
      onSecondary: Colors.white,
      tertiary: BabifixDesign.emeraldTint,
      outline: border,
    );
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      colorScheme: cs,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: onBg,
        iconTheme: IconThemeData(color: onBg),
        actionsIconTheme: IconThemeData(color: onBg),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: onBg,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BabifixDesign.radiusLG),
          side: BorderSide(color: border, width: 1),
        ),
        color: surface,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: BabifixDesign.cyan.withValues(alpha: isLight ? 0.22 : 0.28),
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((s) {
          final bold = s.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            color: bold ? onBg : muted,
          );
        }),
      ),
      textTheme: base.textTheme.apply(bodyColor: onBg, displayColor: onBg),
      inputDecorationTheme: InputDecorationTheme(
        alignLabelWithHint: true,
        filled: true,
        fillColor: isDark
            ? BabifixDesign.navyElevated
            : (isWhite ? BabifixDesign.bgWhite : BabifixDesign.bgSoft),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        labelStyle: TextStyle(color: muted, fontWeight: FontWeight.w500),
        hintStyle: TextStyle(color: muted.withValues(alpha: 0.78)),
        prefixIconColor: isDark ? BabifixDesign.cyan : BabifixDesign.navy,
        suffixIconColor: muted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BabifixDesign.radiusMD),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BabifixDesign.radiusMD),
          borderSide: BorderSide(color: border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BabifixDesign.radiusMD),
          borderSide: BorderSide(
            color: isDark ? BabifixDesign.cyan : BabifixDesign.navy,
            width: 1.8,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BabifixDesign.radiusMD),
          borderSide: const BorderSide(color: BabifixDesign.error, width: 1.2),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: onBg,
          side: BorderSide(color: border, width: 1.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BabifixDesign.radiusMD),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: BabifixDesign.ciOrange,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BabifixDesign.radiusMD),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isDark ? BabifixDesign.cyan : BabifixDesign.navy,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loadedPrefs) {
      return const BabifixPrestataireSplashScreen();
    }
    return MaterialApp(
      navigatorKey: zegoNavigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'BABIFIX PRO',
      theme: _themeForMode(paletteMode),
      home: AppLockGate(
        child: _PrestataireFlow(
          paletteMode: paletteMode,
          onPaletteChanged: _setPalette,
        ),
      ),
    );
  }
}

class _PrestataireFlow extends StatefulWidget {
  const _PrestataireFlow({
    required this.paletteMode,
    required this.onPaletteChanged,
  });

  final AppPaletteMode paletteMode;
  final ValueChanged<AppPaletteMode> onPaletteChanged;

  @override
  State<_PrestataireFlow> createState() => _PrestataireFlowState();
}

class _PrestataireFlowState extends State<_PrestataireFlow> {
  static const _coachKey = 'prestataire_coach_profile_photo_v1';
  static const _onboardingKey = 'prestataire_onboarding_done_v1';

  /// bootstrap -> onboarding | landing | dashboard | pending | refused | registration | kyc
  String current = 'bootstrap';
  final List<String> _navHistory = <String>[];

  void _navigateTo(String target) {
    if (target == current) return;
    if (target == 'dashboard') {
      _navHistory.clear();
    } else if (current != 'bootstrap' &&
        (_navHistory.isEmpty || _navHistory.last != current)) {
      _navHistory.add(current);
      if (_navHistory.length > 12) {
        _navHistory.removeAt(0);
      }
    }
    setState(() => current = target);
  }

  void _goBack() {
    if (_navHistory.isNotEmpty) {
      final prev = _navHistory.removeLast();
      setState(() => current = prev);
    } else {
      setState(() => current = 'dashboard');
    }
  }
  // Anti-sortie accidentelle : mémorise le dernier appui « retour » sur le
  // dashboard pour exiger un double appui avant de quitter l'app.
  DateTime? _lastBackPress;
  bool _bypassMaintenanceForActiveMission = false;
  bool _dismissScheduledNotice = false;
  List<Map<String, dynamic>> _detectedActiveMissions =
      <Map<String, dynamic>>[];
  bool _checkingActiveMissions = false;
  bool _hasCheckedActiveOnMaintenance = false;

  void _onRemoteConfigChanged() {
    final cfg = BabifixRemoteConfig.instance.current;
    if (cfg.maintenance) {
      if (!_checkingActiveMissions && !_hasCheckedActiveOnMaintenance) {
        _refreshActiveMissionsForMaintenance();
      }
      if (!cfg.maintenanceAllowActive && _bypassMaintenanceForActiveMission) {
        if (mounted) {
          setState(() => _bypassMaintenanceForActiveMission = false);
        }
      }
    } else {
      if (_bypassMaintenanceForActiveMission ||
          _hasCheckedActiveOnMaintenance ||
          _detectedActiveMissions.isNotEmpty) {
        if (mounted) {
          setState(() {
            _bypassMaintenanceForActiveMission = false;
            _hasCheckedActiveOnMaintenance = false;
            _detectedActiveMissions = <Map<String, dynamic>>[];
          });
        }
      }
    }
  }

  Future<void> _refreshActiveMissionsForMaintenance() async {
    if (_checkingActiveMissions) return;
    if (mounted) setState(() => _checkingActiveMissions = true);
    try {
      final token = await readStoredApiToken();
      final active =
          await BabifixRemoteConfig.instance.fetchActiveMissions(token);
      if (!mounted) return;
      setState(() {
        _detectedActiveMissions = active;
        _hasCheckedActiveOnMaintenance = true;
        _checkingActiveMissions = false;
        if (active.isEmpty && _bypassMaintenanceForActiveMission) {
          _bypassMaintenanceForActiveMission = false;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _hasCheckedActiveOnMaintenance = true;
          _checkingActiveMissions = false;
        });
      }
    }
  }
  String? _refusalReason;
  StreamSubscription<dynamic>? _wsSub;
  StreamSubscription<dynamic>? _clientEventsWsSub;
  StreamSubscription<RemoteMessage>? _fcmSub;
  StreamSubscription<RemoteMessage>? _fcmOpenedSub;
  late final ValueNotifier<int> _actualitesVersion;
  final ValueNotifier<int> _unreadChat = ValueNotifier<int>(0);
  final ValueNotifier<List<BabifixInAppNotif>> _inAppNotifs =
      ValueNotifier<List<BabifixInAppNotif>>([]);

  /// Catégories publiques chargées au démarrage (sans authentification)
  List<Map<String, dynamic>> _publicCategories = [];
  Timer? _categorySyncTimer;
  Timer? _proPollTimer;
  Timer? _proWsReconnectTimer;
  Timer? _clientEventsWsReconnectTimer;
  bool _proSyncSeeded = false;
  final Set<String> _knownProServerNotifIds = <String>{};
  int _proPollCycle = 0;
  int _lastRequestsHash = -1;
  List<Map<String, dynamic>> _lastCategories = [];

  @override
  void dispose() {
    BabifixRemoteConfig.instance.config.removeListener(_onRemoteConfigChanged);
    _categorySyncTimer?.cancel();
    _proPollTimer?.cancel();
    _proWsReconnectTimer?.cancel();
    _clientEventsWsReconnectTimer?.cancel();
    _wsSub?.cancel();
    _clientEventsWsSub?.cancel();
    _fcmSub?.cancel();
    _fcmOpenedSub?.cancel();
    _actualitesVersion.dispose();
    _unreadChat.dispose();
    _inAppNotifs.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _actualitesVersion = ValueNotifier(0);
    _restoreInAppNotifsThenBootstrap();
    // Chargement immédiat des catégories (sans authentification)
    _loadPublicCategories();
    // Polling fallback for real-time category sync
    _startCategoryPolling();
    // Contrôle de version (force update) + pré-prompt notifications après affichage.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) checkAppVersionGate(context, app: 'prestataire');
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted) BabifixFcm.promptForPermissionIfNeeded(context);
      });
    });
    BabifixRemoteConfig.instance.config.addListener(_onRemoteConfigChanged);
    if (BabifixRemoteConfig.instance.current.maintenance) {
      _onRemoteConfigChanged();
    }
    // Tap sur une notification LOCALE (celle réellement visible en haut de
    // l'écran quand l'app est ouverte/en arrière-plan) : brancher le plus
    // tôt possible, indépendamment du login/JWT, pour ne rater aucun tap.
    BabifixNotificationSoundService.setOnTap((payload) {
      try {
        final d = jsonDecode(payload);
        if (d is Map) _navigateFromFcmData(Map<String, dynamic>.from(d));
      } catch (_) {}
    });
    // App tuée puis relancée en tapant la notification (cold start) : le
    // stream onMessageOpenedApp ne voit jamais cet évènement, seul
    // getInitialMessage() le renvoie.
    if (BabifixFcm.isReady) {
      FirebaseMessaging.instance.getInitialMessage().then((msg) {
        if (msg != null) _navigateFromFcmData(msg.data);
      });
    }
  }

  void _startCategoryPolling() {
    // Les catégories changent très rarement (ajout admin ponctuel) : inutile de
    // poller toutes les 5 s · ça martelait le serveur en continu. 60 s suffit.
    _categorySyncTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _checkCategoriesUpdate();
    });
  }

  Future<void> _checkCategoriesUpdate() async {
    try {
      final base = babifixApiBaseUrl();
      final res = await http.get(Uri.parse('$base/api/public/categories/'));
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final categories = (data['categories'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (_categoriesChanged(categories)) {
        debugPrint('Prestataire: Categories updated via polling');
        _lastCategories = categories;
        if (mounted) {
          setState(() => _publicCategories = categories);
        }
      }
    } catch (e) {
      debugPrint('Prestataire: Categories polling error: $e');
    }
  }

  bool _categoriesChanged(List<Map<String, dynamic>> newCategories) {
    if (_lastCategories.isEmpty) {
      _lastCategories = newCategories;
      return newCategories.isNotEmpty;
    }
    if (newCategories.length != _lastCategories.length) return true;
    for (int i = 0; i < newCategories.length; i++) {
      final newCat = newCategories[i];
      final oldCat = i < _lastCategories.length ? _lastCategories[i] : {};
      if (newCat['id'] != oldCat['id'] ||
          newCat['nom'] != oldCat['nom'] ||
          newCat['actif'] != oldCat['actif']) {
        return true;
      }
    }
    return false;
  }

  /// Charge les catégories publiques au démarrage sans authentification
  Future<void> _loadPublicCategories() async {
    try {
      final base = babifixApiBaseUrl();
      final url = '$base/api/public/categories/';
      debugPrint('BABIFIX PRESTATAIRE MAIN: Fetching categories from: $url');
      final cres = await http.get(Uri.parse(url));
      debugPrint(
        'BABIFIX PRESTATAIRE MAIN: Response status: ${cres.statusCode}',
      );
      if (cres.statusCode == 200) {
        final cdata = jsonDecode(cres.body) as Map<String, dynamic>;
        final rows = cdata['categories'] as List<dynamic>? ?? [];
        debugPrint('BABIFIX PRESTATAIRE MAIN: Found ${rows.length} categories');
        if (mounted) {
          setState(() {
            _publicCategories = rows.cast<Map<String, dynamic>>();
          });
        }
      }
    } catch (e) {
      debugPrint('BABIFIX PRESTATAIRE MAIN: Error loading categories: $e');
    }
  }

  Future<void> _restoreInAppNotifsThenBootstrap() async {
    final list = await loadInAppNotifList(
      BabifixInAppNotifStorageKeys.prestataire,
    );
    if (mounted) _inAppNotifs.value = list;
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrapSession());
  }

  void _pushPrestataireNotif({
    required String category,
    required String title,
    required String body,
    String? actionRoute,
    BabifixNotifSeverity severity = BabifixNotifSeverity.info,
  }) {
    final n = BabifixInAppNotif(
      id: 'p-${DateTime.now().microsecondsSinceEpoch}',
      audience: BabifixNotifAudience.prestataire,
      category: category,
      title: title,
      body: body,
      createdAt: DateTime.now(),
      severity: severity,
      actionRoute: actionRoute,
    );
    pushInAppNotification(
      _inAppNotifs,
      n,
      persistStorageKey: BabifixInAppNotifStorageKeys.prestataire,
    );
    BabifixNotificationSoundService.playForegroundChime(
      urgent: severity == BabifixNotifSeverity.urgent,
    );
    if (mounted && severity != BabifixNotifSeverity.urgent) {
      final overlay = zegoNavigatorKey.currentState?.overlay ?? Overlay.maybeOf(context);
      if (overlay != null) {
        BabifixNotificationOverlay.show(
          overlay: overlay,
          title: title,
          body: body,
          onTap: (actionRoute != null && actionRoute.isNotEmpty)
              ? () => _navigateTo(actionRoute)
              : null,
        );
      }
    }
    if (severity == BabifixNotifSeverity.urgent) {
      _showPrestataireUrgentDialog(n);
    }
  }

  /// Message SPÉCIFIQUE (titre, corps) selon le statut d'une réservation ·
  /// pour les événements temps réel (WebSocket) qui n'ont pas de texte prêt.
  (String, String) _reservationNotifText(String statut, String ref) {
    final r = ref.isNotEmpty ? ' ($ref)' : '';
    switch (statut) {
      case 'DEVIS_ACCEPTE':
        return ('Devis accepté', 'Le client a accepté votre devis$r. Vous pourrez démarrer le jour prévu.');
      case 'Confirmee':
        return ('Acompte versé', 'L\'acompte pour la réservation$r est versé. Vous pouvez démarrer.');
      case 'INTERVENTION_EN_COURS':
        return ('Intervention démarrée', 'L\'intervention$r a commencé.');
      case 'En attente client':
        return ('En attente du client', 'Le client doit confirmer la prestation$r.');
      case 'Terminee':
        return ('Prestation confirmée', 'Le client a confirmé$r. Place au paiement.');
      case 'Annulee':
        return ('Réservation annulée', 'La réservation$r a été annulée.');
      default:
        return ('Mission mise à jour', 'Le statut de la réservation$r a évolué.');
    }
  }

  void _showPrestataireUrgentDialog(BabifixInAppNotif n) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final overlay = zegoNavigatorKey.currentState?.overlay ?? Overlay.maybeOf(context);
      if (overlay != null) {
        BabifixNotificationOverlay.show(
          overlay: overlay,
          title: n.title,
          body: n.body,
          isUrgent: true,
          duration: const Duration(seconds: 5),
          onTap: (n.actionRoute != null && n.actionRoute!.isNotEmpty)
              ? () => _navigateTo(n.actionRoute!)
              : null,
        );
      }
    });
  }

  int _countUnreadMissionNotifs() {
    return _inAppNotifs.value
        .where((n) =>
            !n.read &&
            (n.category == 'demande' ||
                n.category == 'litige' ||
                n.actionRoute == 'requests'))
        .length;
  }

  Future<void> _syncServerNotifications(String token) async {
    try {
      final res = await babifixAuthGet(
        '${babifixApiBaseUrl()}/api/notifications',
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final rawList = (data['notifications'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final newlyArrivedUnread = <Map<String, dynamic>>[];
        final fetchedIds = <String>{};
        for (final item in rawList) {
          final idStr = 'srv-${item['id']}';
          fetchedIds.add(idStr);
          if (_proSyncSeeded &&
              !_knownProServerNotifIds.contains(idStr) &&
              item['lu'] != true) {
            newlyArrivedUnread.add(item);
          }
        }
        _knownProServerNotifIds
          ..clear()
          ..addAll(fetchedIds);
        _proSyncSeeded = true;

        syncServerInAppNotifications(
          hub: _inAppNotifs,
          audience: BabifixNotifAudience.prestataire,
          serverItems: rawList,
          persistStorageKey: BabifixInAppNotifStorageKeys.prestataire,
        );

        final unreadMissions = _countUnreadMissionNotifs();
        if (unreadMissions > babifixNewRequestsCount.value) {
          babifixNewRequestsCount.value = unreadMissions;
        }

        if (newlyArrivedUnread.isNotEmpty) {
          final latest = newlyArrivedUnread.first;
          final isUrgent =
              '${latest['type'] ?? ''}'.toLowerCase() == 'dispute';
          BabifixNotificationSoundService.playForegroundChime(urgent: isUrgent);
          final overlay = zegoNavigatorKey.currentState?.overlay ?? Overlay.maybeOf(context);
          if (overlay != null) {
            BabifixNotificationOverlay.show(
              overlay: overlay,
              title: '${latest['title'] ?? 'Nouvelle notification'}',
              body: '${latest['body'] ?? ''}',
              onTap: () => _navigateTo('requests'),
            );
          }
          babifixReservationsTick.value++;
        }
      }
    } catch (_) {}
  }

  Future<void> _refreshPendingRequestsCount() async {
    final t = await readStoredApiToken();
    if (t == null || t.isEmpty) return;
    try {
      final res = await babifixAuthGet(
        '${babifixApiBaseUrl()}/api/prestataire/requests',
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final items = (data['items'] as List? ?? const []);
      int actionable = 0;
      for (final raw in items) {
        if (raw is! Map) continue;
        final st = '${raw['status'] ?? raw['statut'] ?? ''}'.trim();
        if (st == 'En attente' ||
            st == 'DEMANDE_ENVOYEE' ||
            st == 'DEVIS_EN_COURS' ||
            st == 'DEVIS_ACCEPTE' ||
            st == 'Confirmee' ||
            st == 'Litige') {
          actionable++;
        }
      }
      final unreadMissions = _countUnreadMissionNotifs();
      babifixNewRequestsCount.value =
          actionable > unreadMissions ? actionable : unreadMissions;
      final activeList = <Map<String, dynamic>>[];
      for (final raw in items) {
        if (raw is Map) {
          final m = Map<String, dynamic>.from(raw);
          final st = '${m['statut'] ?? m['status'] ?? ''}';
          if (BabifixRemoteConfig.isMissionStatusActive(st)) {
            activeList.add(m);
          }
        }
      }
      if (mounted) {
        final shouldRelock = BabifixRemoteConfig.instance.current.maintenance &&
            _bypassMaintenanceForActiveMission &&
            activeList.isEmpty;
        setState(() {
          _detectedActiveMissions = activeList;
          _hasCheckedActiveOnMaintenance = true;
          if (shouldRelock) {
            _bypassMaintenanceForActiveMission = false;
          }
        });
      }
      final nextHash = Object.hashAll(
        items.take(25).map((e) => e is Map ? '${e['id']}:${e['status']}' : '$e'),
      );
      if (_lastRequestsHash != -1 && nextHash != _lastRequestsHash) {
        babifixReservationsTick.value++;
      }
      _lastRequestsHash = nextHash;
    } catch (_) {}
  }

  void _startProRealtimePolling() {
    _proPollTimer?.cancel();
    _refreshPendingRequestsCount();
    _proPollTimer = Timer.periodic(const Duration(seconds: 8), (_) async {
      if (!mounted) return;
      final t = await readStoredApiToken();
      if (t == null || t.isEmpty) return;
      _proPollCycle++;
      await _syncServerNotifications(t);
      await _refreshPendingRequestsCount();
      if (_proPollCycle % 2 == 0) {
        await _refreshUnreadChat();
        await BabifixRemoteConfig.instance.refresh();
      }
    });
  }

  Future<void> _refreshUnreadChat() async {
    final t = await readStoredApiToken();
    if (t == null || t.isEmpty) return;
    try {
      final res = await babifixAuthGet(
        '${babifixApiBaseUrl()}/api/messages/unread-total',
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final n = jsonInt(data['total']);
        _unreadChat.value = n;
      }
    } catch (_) {}
  }


  Future<void> _bootstrapSession() async {
    final t = await readStoredApiToken();
    if (t == null || t.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final seenOnboarding = prefs.getBool(_onboardingKey) ?? false;
      if (mounted) setState(() => current = seenOnboarding ? 'landing' : 'onboarding');
      return;
    }
    try {
      final res = await babifixAuthGet(
        '${babifixApiBaseUrl()}/api/prestataire/me',
      ).timeout(const Duration(seconds: 60));
      if (res.statusCode == 404) {
        await writeStoredApiToken(null);
        if (mounted) {
          showBabifixToast(
            context,
            type: BabifixToastType.warning,
            message: 'Aucun profil prestataire trouvé pour ce compte.',
          );
          setState(() => current = 'landing');
        }
        return;
      }
      if (res.statusCode == 401 || res.statusCode == 403) {
        await writeStoredApiToken(null);
        if (mounted) {
          showBabifixToast(
            context,
            type: BabifixToastType.warning,
            message: 'Session expirée. Veuillez vous reconnecter.',
          );
          setState(() => current = 'landing');
        }
        return;
      }
      if (res.statusCode != 200) {
        if (mounted) {
          showBabifixToast(
            context,
            type: BabifixToastType.error,
            message: 'Erreur de connexion serveur (${res.statusCode}).',
          );
          setState(() => current = 'landing');
        }
        return;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final prov = data['provider'] as Map<String, dynamic>? ?? {};
      
      final provId = prov['id'] as int?;
      final provName = '${prov['nom'] ?? prov['prenom'] ?? 'Prestataire'}'.trim();
       if (provName.isNotEmpty && provId != null) {
         await babifixSaveProfile(
           name: provName,
           email: '${prov['email'] ?? ''}',
           id: provId,
         );
       }

      // ── ROUTAGE D'ABORD ─────────────────────────────────────────────────
      // On dirige vers le bon écran IMMÉDIATEMENT, avant toute init lourde.
      // AVANT : l'init LiveKit était `await`ée ICI → si elle traînait/bloquait
      // au 1er lancement (permissions/réseau), `current` n'était jamais mis à
      // jour → ROUE QUI TOURNE À L'INFINI. On la lance donc en arrière-plan.
      final st = '${prov['statut'] ?? ''}';
      final unread = jsonInt(data['unread_chat_messages']);
      _unreadChat.value = unread;
      if (st == 'Valide') {
        // Charte obligatoire avant acces au dashboard : si jamais signee,
        // on redirige sur l'ecran contrat en mode bloquant.
        final contratSigne = prov['contrat_signe'] == true;
        if (mounted) {
          setState(() {
            current = contratSigne ? 'dashboard' : 'contrat_mandatory';
          });
        }
        _syncServerNotifications(t);
        if (contratSigne) {
          await _maybeShowPremiumOnboarding(prov);
        }
      } else if (st == 'Refuse') {
        if (mounted) {
          setState(() {
            _refusalReason = '${prov['refusal_reason'] ?? ''}'.trim();
            current = 'refused';
          });
        }
      } else {
        // Statut "En attente" (inscription rapide ou dossier complet soumis) :
        // meme ecran d'attente PendingScreen dans tous les cas.
        if (mounted) {
          setState(() {
            current = 'pending';
          });
        }
      }

      // ── Init LiveKit EN ARRIÈRE-PLAN (ne doit JAMAIS bloquer l'affichage) ──
      if (provId != null && mounted) {
        BabifixLiveKitService.init(
          userId: provId,
          userName: provName,
          context: context,
        ).then((_) {
          debugPrint('[LiveKit Prestataire] init ok (arrière-plan)');
        }).catchError((Object e) {
          debugPrint('[LiveKit Prestataire] init échouée (ignorée): $e');
        });
      }
      _attachRealtime(t);
    } catch (_) {
      if (mounted) setState(() => current = 'landing');
    }
  }

  Future<void> _maybeShowPremiumOnboarding(Map<String, dynamic> prov) async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyShown = prefs.getBool(_coachKey) ?? false;
    if (alreadyShown || !mounted) return;
    final photo = '${prov['photo_url'] ?? ''}'.trim();
    final hasPhoto = photo.isNotEmpty;
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F2FE),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: Color(0xFF4CC9F0),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Bienvenue sur votre espace Pro',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              hasPhoto
                  ? 'Votre compte est actif. Continuez à enrichir votre profil pour augmenter vos missions.'
                  : 'Astuce premium : ajoutez une photo de profil claire, c’est primordial pour inspirer confiance et activer de meilleures conversions.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.35,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Plus tard'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      if (mounted) setState(() => current = 'profile');
                    },
                    icon: const Icon(Icons.person_rounded),
                    label: Text(
                      hasPhoto ? 'Voir mon profil' : 'Ajouter ma photo',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    await prefs.setBool(_coachKey, true);
  }

  void _attachRealtime(String jwt) {
    _fcmSub?.cancel();
    // iOS sans config Firebase → ne pas accéder à FirebaseMessaging (crash).
    if (!BabifixFcm.isReady) return;
    _fcmSub = FirebaseMessaging.onMessage.listen((msg) {
      final d = msg.data;
      final ty = '${d['type'] ?? ''}';
      if (ty == 'provider.updated') {
        _handleProviderStatus(
          Map<String, String>.from(
            d.map((k, v) => MapEntry(k.toString(), v.toString())),
          ),
        );
      } else if (ty == 'actualite.published') {
        _actualitesVersion.value++;
        _pushPrestataireNotif(
          category: 'actu',
          title: 'Actualité BABIFIX',
          body: 'Une nouvelle annonce a été publiée.',
          actionRoute: 'actualites',
          severity: BabifixNotifSeverity.important,
        );
      } else if (ty == 'chat.message') {
        _refreshUnreadChat();
        _syncServerNotifications(jwt);
        _pushPrestataireNotif(
          category: 'message',
          title: 'Nouveau message',
          body: 'Un client vous a écrit.',
          actionRoute: 'messages',
        );
      } else if (babifixEventTypeIsBookingRequest(ty) ||
          ty.contains('reservation') ||
          ty == 'prestation.updated') {
        // Badge sur l'onglet Exigences + rechargement des écrans ouverts.
        babifixNewRequestsCount.value = babifixNewRequestsCount.value + 1;
        babifixReservationsTick.value++;
        _syncServerNotifications(jwt);
        final specTitle = msg.notification?.title;
        final specBody = msg.notification?.body;
        _pushPrestataireNotif(
          category: 'demande',
          title: (specTitle != null && specTitle.isNotEmpty)
              ? specTitle
              : 'Mise à jour réservation',
          body: (specBody != null && specBody.isNotEmpty)
              ? specBody
              : 'Une de vos réservations a évolué.',
          actionRoute: 'requests',
          severity: BabifixNotifSeverity.important,
        );
      } else if (ty.contains('dispute') ||
          ty == 'litige.ouvert' ||
          ty == 'litige.updated') {
        _syncServerNotifications(jwt);
        _pushPrestataireNotif(
          category: 'litige',
          title: 'Litige / signalement',
          body: 'Un dossier litige a été signalé. Consultez vos demandes.',
          actionRoute: 'requests',
          severity: BabifixNotifSeverity.urgent,
        );
      } else if (ty.contains('payment')) {
        _syncServerNotifications(jwt);
        _pushPrestataireNotif(
          category: 'paiement',
          title: msg.notification?.title ?? 'Paiement BABIFIX',
          body: msg.notification?.body ?? 'Mise a jour de votre paiement.',
          actionRoute: 'wallet',
          severity: BabifixNotifSeverity.important,
        );
      } else if (ty == 'notification') {
        _syncServerNotifications(jwt);
        _pushPrestataireNotif(
          category: 'actu',
          title: msg.notification?.title ?? '${d['title'] ?? 'BABIFIX PRO'}',
          body: msg.notification?.body ?? '${d['body'] ?? ''}',
          actionRoute: 'dashboard',
          severity: BabifixNotifSeverity.important,
        );
      }
    });
    _fcmOpenedSub =
        FirebaseMessaging.onMessageOpenedApp.listen(_navigateFromFcmMessage);
    _connectPrestataireWs(jwt);
    _connectClientEventsWs(jwt);
  }

  /// Navigation déclenchée par un tap sur une notification, quelle que soit
  /// son origine : `onMessageOpenedApp` (tap système, app en arrière-plan),
  /// `getInitialMessage` (app tuée, relancée par le tap) OU la notification
  /// LOCALE affichée par flutter_local_notifications (app au premier plan ·
  /// voir BabifixNotificationSoundService.setOnTap ci-dessous). Avant ce
  /// correctif, seul le premier cas était câblé : taper la notification
  /// visible à l'écran (le cas le plus fréquent) ne faisait RIEN.
  void _navigateFromFcmMessage(RemoteMessage msg) =>
      _navigateFromFcmData(msg.data);

  void _navigateFromFcmData(Map<String, dynamic> d) {
    final ty = '${d['type'] ?? ''}';
    if (ty == 'provider.updated') {
      _handleProviderStatus(
        Map<String, String>.from(
          d.map((k, v) => MapEntry(k.toString(), v.toString())),
        ),
      );
    } else if (ty == 'actualite.published' && mounted) {
      setState(() => current = 'actualites');
    } else if (ty == 'chat.message' && mounted) {
      setState(() => current = 'messages');
    } else if (babifixEventTypeIsBookingRequest(ty) ||
        ty.contains('reservation') ||
        ty == 'prestation.updated' ||
        ty.contains('dispute')) {
      // Tap sur la notification → on ouvre l'onglet Demandes ET, si la
      // référence est fournie, on ouvre DIRECTEMENT la bonne réservation.
      final ref = '${d['reference'] ?? ''}';
      if (mounted) setState(() => current = 'requests');
      if (ref.isNotEmpty) babifixOpenReservationRef.value = ref;
    }
  }

  /// Même flux que l'app client : actualités publiées en temps réel (JWT prestataire).
  void _connectClientEventsWs(String jwt) {
    _clientEventsWsSub?.cancel();
    _clientEventsWsReconnectTimer?.cancel();
    try {
      final uri = Uri.parse(
        '${babifixWsBaseUrl()}/ws/client/events/?token=${Uri.encodeQueryComponent(jwt)}',
      );
      final ch = WebSocketChannel.connect(uri);
      _clientEventsWsSub = ch.stream.listen((raw) {
        try {
          final m = jsonDecode(raw as String) as Map<String, dynamic>;
          final typ = '${m['type'] ?? ''}';
          if (typ == 'actualite.published') {
            _actualitesVersion.value++;
            _pushPrestataireNotif(
              category: 'actu',
              title: 'Actualité BABIFIX',
              body: 'Une nouvelle annonce plateforme est disponible.',
              actionRoute: 'actualites',
              severity: BabifixNotifSeverity.important,
            );
            if (mounted) {
              showBabifixToast(
        context,
        type: BabifixToastType.info,
        message: 'Nouvelle actualité BABIFIX.',
      );
            }
          } else if (typ == 'categories.updated' ||
              typ == 'category.created' ||
              typ == 'category.updated' ||
              typ == 'category.deleted') {
            _loadPublicCategories();
          } else if (typ == 'chat.message') {
            _refreshUnreadChat();
            _pushPrestataireNotif(
              category: 'message',
              title: 'Nouveau message',
              body: 'Message reçu sur votre messagerie.',
              actionRoute: 'messages',
            );
          } else if (babifixEventTypeIsBookingRequest(typ)) {
            _pushPrestataireNotif(
              category: 'demande',
              title: 'Nouvelle demande client',
              body: 'Une réservation est en attente de votre réponse.',
              actionRoute: 'requests',
              severity: BabifixNotifSeverity.important,
            );
          } else if (typ.contains('dispute') || typ == 'litige.ouvert') {
            _pushPrestataireNotif(
              category: 'litige',
              title: 'Litige',
              body: 'Alerte litige : vérifiez la mission concernée.',
              actionRoute: 'requests',
              severity: BabifixNotifSeverity.urgent,
            );
          }
        } catch (_) {}
      }, onError: (_) {
        _clientEventsWsReconnectTimer?.cancel();
        _clientEventsWsReconnectTimer = Timer(const Duration(seconds: 4), () {
          if (mounted) _connectClientEventsWs(jwt);
        });
      }, onDone: () {
        _clientEventsWsReconnectTimer?.cancel();
        _clientEventsWsReconnectTimer = Timer(const Duration(seconds: 4), () {
          if (mounted) _connectClientEventsWs(jwt);
        });
      });
    } catch (_) {}
  }

  Future<void> _registerRealtimeAfterAuth() async {
    final t = await readStoredApiToken();
    if (t != null && t.isNotEmpty) {
      _attachRealtime(t);
    }
  }

  void _connectPrestataireWs(String jwt) {
    _wsSub?.cancel();
    _proWsReconnectTimer?.cancel();
    _startProRealtimePolling();
    try {
      final base = babifixWsBaseUrl();
      final uri = Uri.parse(
        '$base/ws/prestataire/events/?token=${Uri.encodeQueryComponent(jwt)}',
      );
      final ch = WebSocketChannel.connect(uri);
      _wsSub = ch.stream.listen(
        (raw) {
          try {
            final m = jsonDecode(raw as String) as Map<String, dynamic>;
            final t = '${m['type'] ?? ''}';
            if (t == 'provider.updated') {
              final p = m['payload'];
              if (p is Map) {
                _handleProviderStatus(
                  Map<String, String>.from(
                    p.map((k, v) => MapEntry('$k', '$v')),
                  ),
                );
              }
            } else if (t == 'chat.message') {
              _refreshUnreadChat();
              _syncServerNotifications(jwt);
              _pushPrestataireNotif(
                category: 'message',
                title: 'Nouveau message',
                body: 'Un client vous a contacté.',
                actionRoute: 'messages',
              );
            } else if (t == 'notification.created') {
              _syncServerNotifications(jwt);
              final pl = m['payload'];
              if (pl is Map) {
                final nt = '${pl['notif_type'] ?? 'general'}'.toLowerCase();
                _pushPrestataireNotif(
                  category: nt == 'dispute'
                      ? 'litige'
                      : (nt == 'payment' ? 'paiement' : 'demande'),
                  title: '${pl['title'] ?? 'Notification'}',
                  body: '${pl['body'] ?? ''}',
                  actionRoute: nt == 'payment' ? 'wallet' : 'requests',
                  severity: nt == 'dispute'
                      ? BabifixNotifSeverity.urgent
                      : BabifixNotifSeverity.important,
                );
              }
            } else if (t.contains('payment')) {
              _syncServerNotifications(jwt);
              _pushPrestataireNotif(
                category: 'paiement',
                title: 'Paiement mis a jour',
                body: 'Un mouvement financier a ete enregistre.',
                actionRoute: 'wallet',
                severity: BabifixNotifSeverity.important,
              );
            } else if (t == 'call.incoming' || t == 'call.ended' || t == 'call.rejected' || t == 'call.answered') {
              final pl = m['payload'];
              if (pl is Map) {
                BabifixFcmRouter.route({
                  'type': t,
                  ...Map<String, dynamic>.from(pl),
                });
              }
            } else if (t == 'reservations.sync') {
              babifixReservationsTick.value++;
            } else if (babifixEventTypeIsBookingRequest(t)) {
              // Nouvelle demande → recharge les écrans ouverts + notif avec réf.
              babifixReservationsTick.value++;
              _syncServerNotifications(jwt);
              final pl = m['payload'];
              final ref = (pl is Map) ? '${pl['reference'] ?? ''}' : '';
              _pushPrestataireNotif(
                category: 'demande',
                title: 'Nouvelle demande',
                body: ref.isNotEmpty
                    ? 'Nouvelle réservation ($ref) à traiter.'
                    : 'Une nouvelle réservation nécessite votre attention.',
                actionRoute: 'requests',
                severity: BabifixNotifSeverity.important,
              );
            } else if (t.contains('reservation') ||
                t.contains('booking') ||
                t == 'prestation.updated') {
              babifixReservationsTick.value++;
              _syncServerNotifications(jwt);
              final pl = m['payload'];
              final ref = (pl is Map) ? '${pl['reference'] ?? ''}' : '';
              final statut = (pl is Map) ? '${pl['statut'] ?? ''}' : '';
              const proNotifStatuts = {'DEVIS_ACCEPTE', 'Terminee', 'Annulee'};
              if (proNotifStatuts.contains(statut)) {
                final txt = _reservationNotifText(statut, ref);
                _pushPrestataireNotif(
                  category: 'demande',
                  title: txt.$1,
                  body: txt.$2,
                  actionRoute: 'requests',
                  severity: BabifixNotifSeverity.important,
                );
              }
            } else if (t.contains('dispute') || t == 'litige.ouvert') {
              _syncServerNotifications(jwt);
              _pushPrestataireNotif(
                category: 'litige',
                title: 'Litige signalé',
                body: 'Action requise sur un dossier.',
                actionRoute: 'requests',
                severity: BabifixNotifSeverity.urgent,
              );
            }
          } catch (_) {}
        },
        onError: (_) {
          _proWsReconnectTimer?.cancel();
          _proWsReconnectTimer = Timer(const Duration(seconds: 4), () {
            if (mounted) _connectPrestataireWs(jwt);
          });
        },
        onDone: () {
          _proWsReconnectTimer?.cancel();
          _proWsReconnectTimer = Timer(const Duration(seconds: 4), () {
            if (mounted) _connectPrestataireWs(jwt);
          });
        },
      );
    } catch (_) {}
  }

  void _handleProviderStatus(Map<String, String> d) {
    final st = d['statut'] ?? '';
    if (st == 'Valide') {
      _pushPrestataireNotif(
        category: 'compte',
        title: 'Compte approuvé',
        body: 'Votre profil est visible par les clients. Bonnes missions !',
        actionRoute: 'profile',
        severity: BabifixNotifSeverity.important,
      );
      if (!mounted) return;
      // Compte approuvé EN TEMPS RÉEL (alors que le presta est sur l'écran
      // d'attente) : on NE va PAS directement au dashboard. On repasse par
      // _bootstrapSession pour appliquer le MÊME gate que le login → la charte
      // (contrat) est exigée AVANT toute navigation si elle n'a jamais été
      // signée. Avant : on filait au dashboard, le contrat n'était demandé qu'à
      // la reconnexion.
      _bootstrapSession();
      _refreshUnreadChat();
      return;
    }
    if (st == 'Refuse') {
      final reason = (d['refusal_reason'] ?? '').trim();
      _pushPrestataireNotif(
        category: 'compte',
        title: 'Dossier refusé',
        body: reason.isNotEmpty
            ? reason
            : 'Votre dossier a été refusé. Vous pouvez le corriger et renvoyer.',
        severity: BabifixNotifSeverity.urgent,
      );
      if (!mounted) return;
      setState(() {
        _refusalReason = reason;
        current = 'refused';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (current == 'bootstrap') {
      // Un seul splash partagé (le BabifixPrestataireSplashScreen défini
      // dans `splash_screen.dart`) · le splash interne legacy qui
      // utilisait une icône Material est désormais inutilisé.
      child = const BabifixPrestataireSplashScreen();
    } else if (current == 'onboarding') {
      child = PrestataireOnboardingScreen(
        onDone: () async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool(_onboardingKey, true);
          if (mounted) setState(() => current = 'landing');
        },
      );
    } else if (current == 'landing') {
      child = LandingScreen(
        onCreateAccount: () => setState(() => current = 'registration'),
        onLogin: () => setState(() => current = 'login'),
      );
    } else if (current == 'registration') {
      child = RegistrationScreen(
        credentialLock: false,
        onBack: () => setState(() => current = 'landing'),
        onSubmit: () {
          _bootstrapSession();
        },
        onAuthReady: _registerRealtimeAfterAuth,
        preloadedCategories: _publicCategories,
      );
    } else if (current == 'pending') {
      child = PendingScreen(
        onContinue: () async {
          await _bootstrapSession();
        },
      );
    } else if (current == 'registration_resubmit') {
      child = RegistrationScreen(
        credentialLock: true,
        onBack: () => setState(() => current = 'refused'),
        onSubmit: () => setState(() => current = 'pending'),
        onAuthReady: _registerRealtimeAfterAuth,
        preloadedCategories: _publicCategories,
      );
    } else if (current == 'refused') {
      child = ProviderRefusedScreen(
        reason: _refusalReason ?? '',
        onEdit: () => setState(() => current = 'registration_resubmit'),
      );
    } else if (current == 'login') {
      child = LoginScreen(
        onBack: () => setState(() => current = 'landing'),
        // « Créer un compte » depuis le login → on va DIRECTEMENT à
        // l'inscription (au lieu de repasser par l'écran d'accueil).
        onCreateAccount: () => setState(() => current = 'registration'),
        onSuccess: () {
          _bootstrapSession();
        },
      );
    } else if (current == 'contrat_mandatory') {
      // Affiché après login si le prestataire n'a jamais signé la charte.
      // Bloquant : pas de back, scroll obligatoire, case engagement.
      child = ContratScreen(
        mustAccept: true,
        paletteMode: widget.paletteMode,
        // Le back système est bloqué via PopScope dans l'écran ;
        // ce callback ne sert qu'au cas où l'utilisateur a déjà signé
        // (mode normal). Ici on ne devrait jamais y arriver.
        onBack: () {},
        onAccepted: () {
          // Charte signée → on rebascule sur le dashboard via bootstrap.
          _bootstrapSession();
        },
      );
    } else if (current == 'requests') {
      child = RequestsScreen(
        onBack: _goBack,
      );
    } else if (current == 'earnings') {
      child = earnings_feature.EarningsScreen(
        onBack: _goBack,
        paletteMode: widget.paletteMode,
      );
    } else if (current == 'wallet') {
      child = wallet_feature.WalletScreen(
        onBack: _goBack,
        paletteMode: widget.paletteMode,
      );
    } else if (current == 'messages') {
      child = MessagesScreen(
        onBack: () {
          _refreshUnreadChat();
          _goBack();
        },
      );
    } else if (current == 'profile') {
      child = ProfileScreen(
        onBack: _goBack,
        paletteMode: widget.paletteMode,
        onPaletteChanged: widget.onPaletteChanged,
         onLogout: () async {
          await BabifixLiveKitService.uninit();
          await writeStoredApiToken(null);
          _navHistory.clear();
          if (mounted) setState(() => current = 'landing');
        },
        onNavigate: _navigateTo,
        unreadChat: _unreadChat,
        onMessagesOpened: _refreshUnreadChat,
        inAppNotifs: _inAppNotifs,
      );
    } else if (current == 'kyc') {
      child = KYCScreen(
        onBack: () {
          _bootstrapSession();
        },
        paletteMode: widget.paletteMode,
      );
    } else if (current == 'actualites') {
      child = PrestataireActualitesScreen(
        onBack: _goBack,
        refreshVersion: _actualitesVersion,
        paletteMode: widget.paletteMode,
      );
    } else {
      child = PrestataireDashboardScreen(
        paletteMode: widget.paletteMode,
        onNavigate: _navigateTo,
        inAppNotifs: _inAppNotifs,
        unreadChat: _unreadChat,
        onMessagesOpened: _refreshUnreadChat,
      );
    }

    // Interception du RETOUR système (Android) : sans ça, comme la navigation
    // presta repose sur `current` (et non des routes empilées), le retour
    // faisait SORTIR de l'app. On revient à l'écran précédent (ou au dashboard),
    // et on exige un double appui pour quitter depuis le dashboard.
    const authFlowScreens = {
      'bootstrap',
      'landing',
      'login',
      'registration',
      'registration_resubmit',
      'onboarding',
      'pending',
      'refused',
      'contrat_mandatory',
    };
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Sous-écran de l'app connectée → revenir à l'écran précédent réel.
        if (current != 'dashboard' && !authFlowScreens.contains(current)) {
          _goBack();
          return;
        }
        // Dashboard (ou écran d'accueil/auth) → double appui en < 2 s pour quitter.
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
      // Fond navy PERMANENT derrière le switcher : pendant le crossfade entre
      // deux écrans, les deux sont brièvement semi-transparents ; sans ce fond,
      // on voit le noir de l'app → « clignotement noir » à l'entrée d'un écran.
      child: ColoredBox(
        color: BabifixDesign.navy,
        child: ValueListenableBuilder<BabifixRemoteConfigData>(
          valueListenable: BabifixRemoteConfig.instance.config,
          builder: (context, remoteCfg, _) {
            final canBypass = _bypassMaintenanceForActiveMission &&
                remoteCfg.maintenanceAllowActive &&
                _detectedActiveMissions.isNotEmpty;
            if (remoteCfg.maintenance && !canBypass) {
              final customMsg = remoteCfg.maintenanceMessage.isNotEmpty
                  ? remoteCfg.maintenanceMessage
                  : 'Une operation de maintenance est en cours. Votre espace artisan reviendra automatiquement des la fin de l intervention.';
              final hasActive = _detectedActiveMissions.isNotEmpty;
              final isDark = widget.paletteMode == AppPaletteMode.blue;
              final pageBg =
                  isDark ? BabifixDesign.navy : const Color(0xFFF8FAFC);
              final cardBg = isDark ? const Color(0xFF102342) : Colors.white;
              final cardBorder =
                  isDark ? const Color(0xFF1E3A63) : const Color(0xFFE2E8F0);
              final titleColor = isDark ? Colors.white : BabifixDesign.navy;
              final bodyColor =
                  isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569);
              final boxBg =
                  isDark ? const Color(0xFF0B1B34) : const Color(0xFFF8FAFC);
              return Scaffold(
                backgroundColor: pageBg,
                body: SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 24,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: cardBorder,
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: (isDark
                                        ? Colors.black
                                        : const Color(0xFF0F172A))
                                    .withValues(alpha: isDark ? 0.28 : 0.06),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Image.asset(
                                'assets/images/babifix-logo.png',
                                height: 48,
                                fit: BoxFit.contain,
                              ),
                              const SizedBox(height: 18),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: BabifixDesign.ciOrange.withValues(
                                    alpha: isDark ? 0.16 : 0.10,
                                  ),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: BabifixDesign.ciOrange.withValues(
                                      alpha: 0.40,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.build_circle_rounded,
                                      size: 15,
                                      color: BabifixDesign.ciOrange,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'MAINTENANCE BABIFIX PRO',
                                      style: TextStyle(
                                        color: isDark
                                            ? const Color(0xFFFDBA74)
                                            : const Color(0xFFC2410C),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'Mise a jour de l espace artisan',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: titleColor,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              if (remoteCfg.maintenanceScheduledAt.isNotEmpty ||
                                  remoteCfg.maintenanceEndAt.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF4CC9F0)
                                            .withValues(alpha: 0.12)
                                        : const Color(0xFFE0F2FE),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isDark
                                          ? const Color(0xFF4CC9F0)
                                              .withValues(alpha: 0.35)
                                          : const Color(0xFF7DD3FC),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.schedule_rounded,
                                        size: 16,
                                        color: isDark
                                            ? const Color(0xFF4CC9F0)
                                            : const Color(0xFF0284C7),
                                      ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          [
                                            if (remoteCfg.maintenanceScheduledAt
                                                .isNotEmpty)
                                              'Debut : ${remoteCfg.maintenanceScheduledAt}',
                                            if (remoteCfg
                                                .maintenanceEndAt.isNotEmpty)
                                              'Reprise prevue : ${remoteCfg.maintenanceEndAt}',
                                          ].join(' · '),
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: isDark
                                                ? const Color(0xFFE0F2FE)
                                                : const Color(0xFF0369A1),
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 14),
                              Text(
                                customMsg,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: bodyColor,
                                  fontSize: 13.5,
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 18),
                              if (_checkingActiveMissions)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: boxBg,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: cardBorder),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: isDark
                                              ? const Color(0xFF4CC9F0)
                                              : BabifixDesign.navy,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        'Detection de vos interventions en cours...',
                                        style: TextStyle(
                                          color: bodyColor,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else if (remoteCfg.maintenanceAllowActive &&
                                  hasActive)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF0E3B2E)
                                            .withValues(alpha: 0.72)
                                        : const Color(0xFFECFDF5),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: const Color(0xFF10B981).withValues(
                                        alpha: isDark ? 0.5 : 0.45,
                                      ),
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.handyman_rounded,
                                            color: isDark
                                                ? const Color(0xFF34D399)
                                                : const Color(0xFF059669),
                                            size: 18,
                                          ),
                                          const SizedBox(width: 7),
                                          Flexible(
                                            child: Text(
                                              '${_detectedActiveMissions.length} intervention${_detectedActiveMissions.length > 1 ? 's' : ''} active${_detectedActiveMissions.length > 1 ? 's' : ''} detectee${_detectedActiveMissions.length > 1 ? 's' : ''}',
                                              style: TextStyle(
                                                color: isDark
                                                    ? Colors.white
                                                    : const Color(0xFF065F46),
                                                fontWeight: FontWeight.w800,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      ..._detectedActiveMissions.take(2).map(
                                        (m) {
                                          final ref =
                                              (m['reference'] ?? '').toString();
                                          final titre = (m['title'] ??
                                                  m['service'] ??
                                                  'Intervention')
                                              .toString();
                                          final st = (m['status'] ??
                                                  m['statut'] ??
                                                  '')
                                              .toString();
                                          return Container(
                                            width: double.infinity,
                                            margin: const EdgeInsets.only(
                                                bottom: 6),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 7,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isDark
                                                  ? Colors.black
                                                      .withValues(alpha: 0.22)
                                                  : Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              border: isDark
                                                  ? null
                                                  : Border.all(
                                                      color: const Color(
                                                          0xFFA7F3D0),
                                                    ),
                                            ),
                                            child: Text(
                                              '$ref · $titre · $st',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: isDark
                                                    ? const Color(0xFFD1FAE5)
                                                    : const Color(0xFF047857),
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Finalisez vos interventions deja acceptees. L acceptation de nouvelles demandes reste suspendue.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: isDark
                                              ? const Color(0xFFA7F3D0)
                                              : const Color(0xFF047857),
                                          fontSize: 11.5,
                                          height: 1.35,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton.icon(
                                          onPressed: () {
                                            setState(() {
                                              _bypassMaintenanceForActiveMission =
                                                  true;
                                            });
                                          },
                                          icon: const Icon(
                                            Icons.play_arrow_rounded,
                                            size: 20,
                                          ),
                                          label: const Text(
                                            'Continuer mon intervention',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 13.5,
                                            ),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                const Color(0xFF059669),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 12,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: boxBg,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: cardBorder),
                                  ),
                                  child: Text(
                                    'Aucune intervention en cours sur votre compte. Les nouvelles demandes reprendront des la fin de la maintenance.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: bodyColor,
                                      fontSize: 12,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              if (remoteCfg.supportPhone.isNotEmpty) ...[
                                const SizedBox(height: 14),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.support_agent_rounded,
                                      size: 16,
                                      color: isDark
                                          ? const Color(0xFF4CC9F0)
                                          : const Color(0xFF0284C7),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Support : ${remoteCfg.supportPhone}',
                                      style: TextStyle(
                                        color: isDark
                                            ? const Color(0xFFBAE6FD)
                                            : BabifixDesign.navy,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 18),
                              BabifixButton(
                                label: "Actualiser le statut",
                                icon: Icons.refresh_rounded,
                                onPressed: () async {
                                  await BabifixRemoteConfig.instance.refresh();
                                  if (BabifixRemoteConfig
                                      .instance.current.maintenance) {
                                    await _refreshActiveMissionsForMaintenance();
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }

            final showPreBanner = !remoteCfg.maintenance &&
                remoteCfg.maintenanceScheduledAt.isNotEmpty &&
                !_dismissScheduledNotice;
            final showBypassBanner = remoteCfg.maintenance && canBypass;
            final switcher = AnimatedSwitcher(
              duration: const Duration(milliseconds: 420),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.02),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
              child: child,
            );
            if (!showPreBanner && !showBypassBanner) {
              return switcher;
            }
            return Column(
              children: [
                Material(
                  color: showBypassBanner
                      ? const Color(0xFF0E3B2E)
                      : const Color(0xFF9A3412),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            showBypassBanner
                                ? Icons.shield_rounded
                                : Icons.schedule_rounded,
                            size: 16,
                            color: const Color(0xFFE7C463),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              showBypassBanner
                                  ? 'Maintenance active · Mode continuite pour vos missions en cours'
                                  : 'Maintenance prevue a ${remoteCfg.maintenanceScheduledAt}${remoteCfg.maintenanceEndAt.isNotEmpty ? ' (fin ${remoteCfg.maintenanceEndAt})' : ''}${remoteCfg.maintenanceMessage.isNotEmpty ? ' · ${remoteCfg.maintenanceMessage}' : ''}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                if (showBypassBanner) {
                                  _bypassMaintenanceForActiveMission = false;
                                } else {
                                  _dismissScheduledNotice = true;
                                }
                              });
                            },
                            child: const Icon(
                              Icons.close_rounded,
                              size: 16,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(child: switcher),
              ],
            );
          },
        ),
      ),
    );
  }
}
