import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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
import 'category_icon_mapper.dart';

import 'shared/app_palette_mode.dart';
import 'shared/services/app_lock_gate.dart';
import 'shared/auth_utils.dart';
import 'shared/in_app_notifications.dart';
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
import 'features/requests/requests_screen.dart';
import 'features/messages/messages_screen.dart';
import 'features/profile/contrat_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/actualites/actualites_screen.dart';
import 'features/wallet/wallet_screen.dart' as wallet_feature;
import 'services/fcm_router.dart';
import 'services/location_reporter.dart';
import 'shared/widgets/babifix_ring_loader.dart';
import 'shared/widgets/babifix_snackbar.dart';
import 'shared/widgets/app_version_gate.dart';
import 'shared/widgets/error_reporter.dart';

// Alias avec BabifixFcmRouter — un seul navigatorKey pour tout (calls in/out).
final GlobalKey<NavigatorState> zegoNavigatorKey =
    BabifixFcmRouter.navigatorKey;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Monitoring : capter les crashs et les remonter au backend (→ Sentry).
  initErrorReporter(app: 'prestataire', version: kAppVersion);

  try {
    await dotenv.load(fileName: ".env");
  } catch (_) {}

  await BabifixFcm.ensureInitialized();

  // Géolocalisation auto : push la position GPS du prestataire au backend
  // dès l'ouverture de l'app + à chaque resume foreground. Non bloquant.
  // ignore: unawaited_futures
  LocationReporter.instance.attach();

  // Zego SDK temporairement désactivé — voir services/zego_call_service.dart
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
  AppPaletteMode paletteMode = AppPaletteMode.light;
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
    final vStr = p.getString('prestataire_palette') ?? 'light';
    final elapsed = DateTime.now().difference(started);
    const minSplash = Duration(milliseconds: 1800);
    if (elapsed < minSplash) {
      await Future.delayed(minSplash - elapsed);
    }
    if (!mounted) return;
    setState(() {
      paletteMode = switch (vStr) {
        'blue' => AppPaletteMode.blue,
        'white' => AppPaletteMode.white,
        _ => AppPaletteMode.light,
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
    // "light" et "white" = thèmes clairs ; seul "blue" est sombre.
    final isLight = !isDark;
    final bg = isDark
        ? BabifixDesign.navy
        : (isWhite ? const Color(0xFFFFFFFF) : const Color(0xFFF6F8FC));
    final seed = BabifixDesign.cyan;
    final onBg = isLight ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final muted = isLight ? const Color(0xFF64748B) : const Color(0xFFB4C2D9);
    final surface = isLight ? const Color(0xFFFFFFFF) : const Color(0xFF151D2E);
    final cs =
        ColorScheme.fromSeed(
          seedColor: seed,
          brightness: isLight ? Brightness.light : Brightness.dark,
        ).copyWith(
          surface: surface,
          secondary: BabifixDesign.ciOrange,
          tertiary: BabifixDesign.success,
        );
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      colorScheme: cs,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: onBg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: onBg,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        color: surface,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: BabifixDesign.cyan.withValues(alpha: isLight ? 0.35 : 0.5),
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((s) {
          final bold = s.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            color: bold ? BabifixDesign.navy : muted,
          );
        }),
      ),
      textTheme: base.textTheme.apply(bodyColor: onBg, displayColor: onBg),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? const Color(0xFFF1F5F9) : const Color(0xFF1A2438),
        labelStyle: TextStyle(color: muted),
        hintStyle: TextStyle(color: muted.withValues(alpha: 0.85)),
        prefixIconColor: BabifixDesign.cyan,
        suffixIconColor: muted,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: BabifixDesign.cyan.withValues(alpha: isLight ? 0.35 : 0.5),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: BabifixDesign.cyan, width: 2),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: onBg,
          side: BorderSide(color: BabifixDesign.cyan.withValues(alpha: 0.65)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: BabifixDesign.cyan,
          foregroundColor: BabifixDesign.navy,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: BabifixDesign.cyan),
      ),
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
      title: 'BABIFIX Prestataire',
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

  /// bootstrap → onboarding | landing | dashboard | pending | refused | registration | …
  String current = 'bootstrap';
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
  List<Map<String, dynamic>> _lastCategories = [];

  @override
  void dispose() {
    _categorySyncTimer?.cancel();
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
    // Contrôle de version (force update) — non bloquant si à jour.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) checkAppVersionGate(context, app: 'prestataire');
    });
  }

  void _startCategoryPolling() {
    // Les catégories changent très rarement (ajout admin ponctuel) : inutile de
    // poller toutes les 5 s — ça martelait le serveur en continu. 60 s suffit.
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
    if (severity == BabifixNotifSeverity.urgent) {
      _showPrestataireUrgentDialog(n);
    }
  }

  void _showPrestataireUrgentDialog(BabifixInAppNotif n) {
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
                  setState(() => current = n.actionRoute!);
                },
                child: const Text('Voir'),
              ),
          ],
        ),
      );
    });
  }

  Future<void> _refreshUnreadChat() async {
    final t = await readStoredApiToken();
    if (t == null || t.isEmpty) return;
    try {
      final res = await http.get(
        Uri.parse('${babifixApiBaseUrl()}/api/messages/unread-total'),
        headers: {'Authorization': 'Bearer $t'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final n = jsonInt(data['total']);
        _unreadChat.value = n;
      }
    } catch (_) {}
  }

  /// Auto-login démo : utilise les identifiants du compte seedé
  /// (`horzonzh` / `prest123`) pour entrer directement dans l'app et
  /// montrer toutes les fonctionnalités sans demander à l'utilisateur
  /// de s'inscrire.
  Future<void> _loginAsDemoPrestataire() async {
    if (!mounted) return;
    // Petit feedback visuel pendant le login
    showBabifixToast(
        context,
        type: BabifixToastType.info,
        message: 'Connexion en compte démo…',
        duration: Duration(seconds: 4),
      );
    try {
      final res = await http.post(
        Uri.parse('${babifixApiBaseUrl()}/api/auth/login/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': 'horzonzh',
          'password': 'prest123',
        }),
      );
      if (res.statusCode != 200) {
        if (mounted) {
          showBabifixToast(
        context,
        type: BabifixToastType.warning,
        message: 'Compte démo indisponible (HTTP ${res.statusCode}). '
              'Lancez "python manage.py seed_app_users" côté backend.',
      );
        }
        return;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final tok = (data['token'] ?? data['access']) as String?;
      final refresh = data['refresh'] as String?;
      if (tok == null || tok.isEmpty) return;
      await writeStoredApiToken(tok);
      if (refresh != null) await writeStoredRefreshToken(refresh);
      babifixRegisterFcm(tok);
      // Re-bootstrap pour réévaluer l'état du profil
      await _bootstrapSession();
    } catch (e) {
      if (mounted) {
        showBabifixToast(
        context,
        type: BabifixToastType.warning,
        message: 'Erreur démo : $e',
      );
      }
    }
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
      final res = await http.get(
        Uri.parse('${babifixApiBaseUrl()}/api/prestataire/me'),
        headers: {'Authorization': 'Bearer $t'},
      );
      if (res.statusCode == 404) {
        // L'utilisateur a un token (compte BABIFIX existant) mais pas
        // de profil prestataire. On l'envoie sur l'écran de choix
        // « S'inscrire / Se connecter » plutôt que direct sur le
        // formulaire d'inscription — ça lui laisse la possibilité de
        // se connecter avec un autre compte qui aurait déjà un profil
        // prestataire.
        if (mounted) setState(() => current = 'landing');
        return;
      }
      if (res.statusCode != 200) {
        if (mounted) setState(() => current = 'landing');
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

         if (mounted) {
           try {
             debugPrint('[LiveKit Prestataire] Initializing for provId=$provId, provName=$provName');
             await BabifixLiveKitService.init(
               userId: provId,
               userName: provName,
               context: context,
             );
             debugPrint('[LiveKit Prestataire] INITIALIZED SUCCESS! isInitialized=${BabifixLiveKitService.isInitialized}');
           } catch (e, stack) {
             debugPrint('[LiveKit Prestataire] Init ERROR: $e');
             debugPrint('[LiveKit Prestataire] Stack: $stack');
           }
         } else {
           debugPrint('[LiveKit Prestataire] NOT mounted, skipping init');
         }
       }
      
      final st = '${prov['statut'] ?? ''}';
      final unread = jsonInt(data['unread_chat_messages']);
      _unreadChat.value = unread;
      if (st == 'Valide') {
        // Charte obligatoire avant accès au dashboard : si jamais signée,
        // on redirige sur l'écran contrat en mode bloquant.
        final contratSigne = prov['contrat_signe'] == true;
        if (mounted) {
          setState(() => current = contratSigne ? 'dashboard' : 'contrat_mandatory');
        }
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
        if (mounted) setState(() => current = 'pending');
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
        _pushPrestataireNotif(
          category: 'message',
          title: 'Nouveau message',
          body: 'Un client vous a écrit.',
          actionRoute: 'messages',
        );
      } else if (babifixEventTypeIsBookingRequest(ty)) {
        _pushPrestataireNotif(
          category: 'demande',
          title: 'Nouvelle demande',
          body: 'Une réservation ou une demande nécessite votre attention.',
          actionRoute: 'requests',
          severity: BabifixNotifSeverity.important,
        );
      } else if (ty.contains('dispute') ||
          ty == 'litige.ouvert' ||
          ty == 'litige.updated') {
        _pushPrestataireNotif(
          category: 'litige',
          title: 'Litige / signalement',
          body: 'Un dossier litige a été signalé. Consultez vos demandes.',
          actionRoute: 'requests',
          severity: BabifixNotifSeverity.urgent,
        );
      }
    });
    _fcmOpenedSub = FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      final d = msg.data;
      final ty = '${d['type'] ?? ''}';
      if (ty == 'provider.updated') {
        _handleProviderStatus(
          Map<String, String>.from(
            d.map((k, v) => MapEntry(k.toString(), v.toString())),
          ),
        );
      } else if (ty == 'actualite.published' && mounted) {
        setState(() => current = 'actualites');
      }
    });
    _connectPrestataireWs(jwt);
    _connectClientEventsWs(jwt);
  }

  /// Même flux que l'app client : actualités publiées en temps réel (JWT prestataire).
  void _connectClientEventsWs(String jwt) {
    _clientEventsWsSub?.cancel();
    if (kIsWeb) return;
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
              body: 'Alerte litige — vérifiez la mission concernée.',
              actionRoute: 'requests',
              severity: BabifixNotifSeverity.urgent,
            );
          }
        } catch (_) {}
      }, onError: (_) {});
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
    if (kIsWeb) return;
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
              _pushPrestataireNotif(
                category: 'message',
                title: 'Nouveau message',
                body: 'Un client vous a contacté.',
                actionRoute: 'messages',
              );
            } else if (babifixEventTypeIsBookingRequest(t)) {
              _pushPrestataireNotif(
                category: 'demande',
                title: 'Nouvelle demande',
                body: 'Ouvrez l’onglet Demandes pour traiter la réservation.',
                actionRoute: 'requests',
                severity: BabifixNotifSeverity.important,
              );
            } else if (t.contains('reservation') ||
                t.contains('booking') ||
                t == 'prestation.updated') {
              _pushPrestataireNotif(
                category: 'demande',
                title: 'Mission mise à jour',
                body: 'Le statut d’une réservation a évolué.',
                actionRoute: 'requests',
                severity: BabifixNotifSeverity.info,
              );
            } else if (t.contains('dispute') || t == 'litige.ouvert') {
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
        onError: (_) {},
        onDone: () {},
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
      setState(() => current = 'dashboard');
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
      // dans `splash_screen.dart`) — le splash interne legacy qui
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
        onDemoLogin: _loginAsDemoPrestataire,
      );
    } else if (current == 'registration') {
      child = RegistrationScreen(
        credentialLock: false,
        onBack: () => setState(() => current = 'landing'),
        onSubmit: () => setState(() => current = 'pending'),
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
        onBack: () => setState(() => current = 'dashboard'),
      );
    } else if (current == 'earnings') {
      child = earnings_feature.EarningsScreen(
        onBack: () => setState(() => current = 'dashboard'),
        paletteMode: widget.paletteMode,
      );
    } else if (current == 'wallet') {
      child = wallet_feature.WalletScreen(
        onBack: () => setState(() => current = 'dashboard'),
        paletteMode: widget.paletteMode,
      );
    } else if (current == 'messages') {
      child = MessagesScreen(
        onBack: () {
          _refreshUnreadChat();
          setState(() => current = 'dashboard');
        },
      );
    } else if (current == 'profile') {
      child = ProfileScreen(
        onBack: () => setState(() => current = 'dashboard'),
        paletteMode: widget.paletteMode,
        onPaletteChanged: widget.onPaletteChanged,
         onLogout: () async {
          await BabifixLiveKitService.uninit();
          await writeStoredApiToken(null);
          if (mounted) setState(() => current = 'landing');
        },
        onNavigate: (target) => setState(() => current = target),
        unreadChat: _unreadChat,
        onMessagesOpened: _refreshUnreadChat,
      );
    } else if (current == 'actualites') {
      child = PrestataireActualitesScreen(
        onBack: () => setState(() => current = 'dashboard'),
        refreshVersion: _actualitesVersion,
        paletteMode: widget.paletteMode,
      );
    } else {
      child = PrestataireDashboardScreen(
        paletteMode: widget.paletteMode,
        onNavigate: (target) => setState(() => current = target),
        inAppNotifs: _inAppNotifs,
        unreadChat: _unreadChat,
        onMessagesOpened: _refreshUnreadChat,
      );
    }

    return AnimatedSwitcher(
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
  }
}

class _PrestataireSplashScreen extends StatefulWidget {
  const _PrestataireSplashScreen();
  @override
  State<_PrestataireSplashScreen> createState() =>
      _PrestataireSplashScreenState();
}

class _PrestataireSplashScreenState extends State<_PrestataireSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    );
    _scale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0, 0.6, curve: Curves.easeOutBack)),
    );
    _fade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.3, 1.0, curve: Curves.easeOut)),
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1B34),
      body: Center(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, child) => Transform.scale(
            scale: _scale.value,
            child: Opacity(opacity: _fade.value, child: child),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  color: const Color(0xFF4CC9F0),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4CC9F0).withValues(alpha: 0.35),
                      blurRadius: 32,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.home_repair_service,
                  size: 58,
                  color: Color(0xFF0B1B34),
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'BABIFIX',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Espace Prestataire',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.5),
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 36),
              SizedBox(
                width: 24,
                height: 24,
                child: BabifixRingLoader.cyan(size: 28),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
