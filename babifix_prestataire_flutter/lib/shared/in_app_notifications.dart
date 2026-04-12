import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Clés de stockage local (une par app / rôle).
abstract final class BabifixInAppNotifStorageKeys {
  static const client = 'babifix_in_app_notifs_client_v1';
  static const prestataire = 'babifix_in_app_notifs_prestataire_v1';
}

/// Portée : filtrage par rôle dans l’UI.
enum BabifixNotifAudience { client, prestataire }

/// Gravité : popup système pour [urgent].
enum BabifixNotifSeverity { info, important, urgent }

/// Notification in-app (WebSocket / FCM / événements locaux).
@immutable
class BabifixInAppNotif {
  const BabifixInAppNotif({
    required this.id,
    required this.audience,
    required this.category,
    required this.title,
    required this.body,
    required this.createdAt,
    this.read = false,
    this.severity = BabifixNotifSeverity.info,
    this.actionRoute,
  });

  final String id;
  final BabifixNotifAudience audience;
  /// demande | litige | message | compte | actu | paiement | info
  final String category;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool read;
  final BabifixNotifSeverity severity;
  final String? actionRoute;

  Map<String, dynamic> toJson() => {
        'id': id,
        'audience': audience.name,
        'category': category,
        'title': title,
        'body': body,
        'createdAt': createdAt.toIso8601String(),
        'read': read,
        'severity': severity.name,
        'actionRoute': actionRoute,
      };

  factory BabifixInAppNotif.fromJson(Map<String, dynamic> j) {
    BabifixNotifAudience aud = BabifixNotifAudience.prestataire;
    try {
      aud = BabifixNotifAudience.values.firstWhere((e) => e.name == '${j['audience']}');
    } catch (_) {}
    BabifixNotifSeverity sev = BabifixNotifSeverity.info;
    try {
      sev = BabifixNotifSeverity.values.firstWhere((e) => e.name == '${j['severity']}');
    } catch (_) {}
    DateTime at;
    try {
      at = DateTime.parse('${j['createdAt']}');
    } catch (_) {
      at = DateTime.now();
    }
    return BabifixInAppNotif(
      id: '${j['id'] ?? ''}',
      audience: aud,
      category: '${j['category'] ?? 'info'}',
      title: '${j['title'] ?? ''}',
      body: '${j['body'] ?? ''}',
      createdAt: at,
      read: j['read'] == true,
      severity: sev,
      actionRoute: j['actionRoute'] != null ? '${j['actionRoute']}' : null,
    );
  }

  BabifixInAppNotif copyWith({bool? read}) => BabifixInAppNotif(
        id: id,
        audience: audience,
        category: category,
        title: title,
        body: body,
        createdAt: createdAt,
        read: read ?? this.read,
        severity: severity,
        actionRoute: actionRoute,
      );

  static String _fmtDate(DateTime d) {
    final now = DateTime.now();
    final t =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (now.difference(d).inDays == 0) {
      return "Aujourd'hui, $t";
    }
    if (now.difference(d).inDays == 1) {
      return "Hier, $t";
    }
    return '${d.day}/${d.month}/${d.year}';
  }

  String get dateLabel => _fmtDate(createdAt);
}

IconData babifixNotifCategoryIcon(String category) {
  switch (category) {
    case 'demande':
      return Icons.add_task_rounded;
    case 'litige':
      return Icons.gavel_rounded;
    case 'message':
      return Icons.chat_bubble_rounded;
    case 'compte':
      return Icons.verified_user_rounded;
    case 'actu':
      return Icons.newspaper_rounded;
    case 'paiement':
      return Icons.payments_rounded;
    default:
      return Icons.notifications_active_rounded;
  }
}

Color babifixNotifCategoryColor(String category) {
  switch (category) {
    case 'demande':
      return const Color(0xFF0084D1);
    case 'litige':
      return const Color(0xFFDC2626);
    case 'message':
      return const Color(0xFF8B5CF6);
    case 'compte':
      return const Color(0xFF059669);
    case 'actu':
      return const Color(0xFF2563EB);
    case 'paiement':
      return const Color(0xFF009A44);
    default:
      return const Color(0xFF64748B);
  }
}

Future<void> persistInAppNotifHub(String storageKey, List<BabifixInAppNotif> list) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(storageKey, jsonEncode(list.map((e) => e.toJson()).toList()));
}

Future<List<BabifixInAppNotif>> loadInAppNotifList(String storageKey) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(storageKey);
  if (raw == null || raw.isEmpty) return [];
  try {
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => BabifixInAppNotif.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  } catch (_) {
    return [];
  }
}

void _maybePersist(String? persistStorageKey, List<BabifixInAppNotif> list) {
  if (persistStorageKey == null) return;
  unawaited(persistInAppNotifHub(persistStorageKey, list));
}

void pushInAppNotification(
  ValueNotifier<List<BabifixInAppNotif>> hub,
  BabifixInAppNotif n, {
  String? persistStorageKey,
}) {
  final next = List<BabifixInAppNotif>.from(hub.value)..insert(0, n);
  if (next.length > 80) next.removeRange(80, next.length);
  hub.value = next;
  _maybePersist(persistStorageKey, hub.value);
}

int countUnreadInApp(ValueNotifier<List<BabifixInAppNotif>> hub, BabifixNotifAudience forAudience) {
  return hub.value.where((e) => !e.read && e.audience == forAudience).length;
}

void markAllInAppRead(
  ValueNotifier<List<BabifixInAppNotif>> hub,
  BabifixNotifAudience forAudience, {
  String? persistStorageKey,
}) {
  hub.value = hub.value
      .map((e) => e.audience == forAudience ? e.copyWith(read: true) : e)
      .toList();
  _maybePersist(persistStorageKey, hub.value);
}

void markOneRead(
  ValueNotifier<List<BabifixInAppNotif>> hub,
  String id, {
  String? persistStorageKey,
}) {
  hub.value = hub.value.map((e) => e.id == id ? e.copyWith(read: true) : e).toList();
  _maybePersist(persistStorageKey, hub.value);
}

/// Types d’événements serveur (WebSocket / data FCM) reconnus pour une demande de réservation.
bool babifixEventTypeIsBookingRequest(String t) {
  return t == 'request.new' ||
      t == 'reservation.new' ||
      t == 'booking.pending' ||
      t == 'booking.requested' ||
      t == 'prestation.demande';
}
