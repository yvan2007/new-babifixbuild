import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Service de notification locale avec son personnalisé.
/// Initialise les canaux Android/iOS et joue un son doux pour chaque notification.
class BabifixNotificationSoundService {
  BabifixNotificationSoundService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  /// Appelé quand l'utilisateur tape la notification locale (celle
  /// réellement affichée en foreground/background — voir showNotification).
  /// Réglé par le shell principal AVANT tout affichage de notification pour
  /// ne rater aucun tap. Si un tap survient avant que le callback ne soit
  /// réglé (notification affichée puis app tuée puis relancée par le tap),
  /// le payload est mémorisé dans [pendingPayload] et consommé au premier
  /// réglage du callback.
  static void Function(String payload)? onTap;
  static String? pendingPayload;

  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    if (kIsWeb) return;
    _initialized = true;

    try {
      // Android initialization settings
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      // iOS initialization settings
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
        defaultPresentAlert: true,
        defaultPresentBadge: true,
        defaultPresentSound: true,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTap,
      );

      // Channel par défaut
      const androidChannel = AndroidNotificationChannel(
        'babifix_notifications',
        'BABIFIX Notifications',
        description: 'Notifications BABIFIX avec son personnalisé',
        importance: Importance.high,
        sound: RawResourceAndroidNotificationSound('notification_soft'),
        playSound: true,
        enableVibration: false,
        enableLights: false,
      );

      // Phase D — S1 : channel haute priorité dédié aux appels entrants,
      // avec vibration + son ringtone système. Crée la sonnerie même
      // quand l'app est en arrière-plan.
      const callsChannel = AndroidNotificationChannel(
        'babifix_calls',
        'BABIFIX Appels',
        description: 'Sonnerie des appels entrants entre client et prestataire',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        enableLights: true,
        showBadge: true,
      );

      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(androidChannel);
      await android?.createNotificationChannel(callsChannel);

      debugPrint('BABIFIX Notification Sound: initialized (incl. babifix_calls)');
    } catch (e) {
      debugPrint('BABIFIX Notification Sound: init failed ($e)');
    }
  }

  static void _onNotificationTap(NotificationResponse response) {
    debugPrint('BABIFIX Notification tapped: ${response.payload}');
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    final cb = onTap;
    if (cb != null) {
      cb(payload);
    } else {
      // Tap survenu avant l'initialisation complète de l'app (cold start) :
      // mémorisé pour être rejoué dès que le callback sera prêt.
      pendingPayload = payload;
    }
  }

  /// Réglé le callback de navigation et rejoue immédiatement un tap qui
  /// serait survenu avant (cold start).
  static void setOnTap(void Function(String payload) callback) {
    onTap = callback;
    final pending = pendingPayload;
    if (pending != null) {
      pendingPayload = null;
      callback(pending);
    }
  }

  /// Affiche une notification locale avec son doux.
  static Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
    NotificationPriority priority = NotificationPriority.normal,
  }) async {
    if (kIsWeb) return;

    try {
      const androidDetails = AndroidNotificationDetails(
        'babifix_notifications',
        'BABIFIX Notifications',
        channelDescription: 'Notifications BABIFIX avec son personnalisé',
        importance: Importance.high,
        priority: Priority.high,
        sound: RawResourceAndroidNotificationSound('notification_soft'),
        playSound: true,
        enableVibration: false,
        enableLights: false,
        styleInformation: DefaultStyleInformation(true, true),
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'notification_soft.mp3',
      );

      const details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _plugin.show(
        id,
        title,
        body,
        details,
        payload: payload,
      );
    } catch (e) {
      debugPrint('BABIFIX Notification Sound: show failed ($e)');
    }
  }
}

enum NotificationPriority { low, normal, high, urgent }
