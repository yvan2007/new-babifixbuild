import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'babifix_design_system.dart';
import 'babifix_api_config.dart';
import 'babifix_fcm.dart';
import 'json_utils.dart';
import 'category_icon_mapper.dart';

import 'shared/app_palette_mode.dart';
import 'shared/auth_utils.dart';
import 'shared/in_app_notifications.dart';

import 'features/earnings/earnings_screen.dart' as earnings_feature;
import 'features/auth/landing_screen.dart';
import 'features/auth/registration_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/pending_screen.dart';
import 'features/auth/refused_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/requests/requests_screen.dart';
import 'features/messages/messages_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/actualites/actualites_screen.dart';

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
        runApp(const BabifixPrestataireApp());
      },
    );
  } else {
    WidgetsFlutterBinding.ensureInitialized();
    await BabifixFcm.ensureInitialized();
    runApp(const BabifixPrestataireApp());
  }
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
  }

  Future<void> _loadPalette() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getString('prestataire_palette') ?? 'light';
    if (!mounted) return;
    setState(() {
      paletteMode = v == 'blue' ? AppPaletteMode.blue : AppPaletteMode.light;
      _loadedPrefs = true;
    });
  }

  Future<void> _setPalette(AppPaletteMode m) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      'prestataire_palette',
      m == AppPaletteMode.blue ? 'blue' : 'light',
    );
    if (!mounted) return;
    setState(() => paletteMode = m);
  }

  ThemeData _themeForMode(AppPaletteMode mode) {
    final base = ThemeData(useMaterial3: true);
    final isLight = mode == AppPaletteMode.light;
    const brandNavy = Color(0xFF0B1B34);
    const brandCyan = Color(0xFF4CC9F0);
    final bg = isLight ? const Color(0xFFF6F8FC) : brandNavy;
    final seed = isLight ? BabifixDesign.ciBlue : brandCyan;
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
          tertiary: BabifixDesign.ciGreen,
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
        indicatorColor: brandCyan.withValues(alpha: isLight ? 0.35 : 0.5),
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((s) {
          final bold = s.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            color: bold ? brandNavy : muted,
          );
        }),
      ),
      textTheme: base.textTheme.apply(bodyColor: onBg, displayColor: onBg),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? const Color(0xFFF1F5F9) : const Color(0xFF1A2438),
        labelStyle: TextStyle(color: muted),
        hintStyle: TextStyle(color: muted.withValues(alpha: 0.85)),
        prefixIconColor: brandCyan,
        suffixIconColor: muted,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: brandCyan.withValues(alpha: isLight ? 0.35 : 0.5),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: brandCyan, width: 2),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: onBg,
          side: BorderSide(color: brandCyan.withValues(alpha: 0.65)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brandCyan,
          foregroundColor: brandNavy,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: brandCyan),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loadedPrefs) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: CircularProgressIndicator(color: Color(0xFF4CC9F0)),
          ),
        ),
      );
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BABIFIX Prestataire',
      theme: _themeForMode(paletteMode),
      home: _PrestataireFlow(
        paletteMode: paletteMode,
        onPaletteChanged: _setPalette,
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

  /// bootstrap → landing | dashboard | pending | refused | registration | …
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

  @override
  void dispose() {
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

  Future<void> _bootstrapSession() async {
    final t = await readStoredApiToken();
    if (t == null || t.isEmpty) {
      if (mounted) setState(() => current = 'landing');
      return;
    }
    try {
      final res = await http.get(
        Uri.parse('${babifixApiBaseUrl()}/api/prestataire/me'),
        headers: {'Authorization': 'Bearer $t'},
      );
      if (res.statusCode == 404) {
        if (mounted) setState(() => current = 'registration');
        _attachRealtime(t);
        await _refreshUnreadChat();
        return;
      }
      if (res.statusCode != 200) {
        if (mounted) setState(() => current = 'landing');
        return;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final prov = data['provider'] as Map<String, dynamic>? ?? {};
      final st = '${prov['statut'] ?? ''}';
      final unread = jsonInt(data['unread_chat_messages']);
      _unreadChat.value = unread;
      if (st == 'Valide') {
        if (mounted) setState(() => current = 'dashboard');
        await _maybeShowPremiumOnboarding(prov);
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
                    color: Color(0xFF0284C7),
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
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Nouvelle actualité BABIFIX.')),
              );
            }
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
      child = const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF4CC9F0)),
        ),
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
    } else if (current == 'requests') {
      child = RequestsScreen(
        onBack: () => setState(() => current = 'dashboard'),
      );
    } else if (current == 'earnings') {
      child = earnings_feature.EarningsScreen(
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
