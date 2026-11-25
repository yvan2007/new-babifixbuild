import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../babifix_api_config.dart';
import 'auth_utils.dart';

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
      return const Color(0xFF7C3AED);
    case 'compte':
      return const Color(0xFF059669);
    case 'actu':
      return const Color(0xFF4CC9F0);
    case 'paiement':
      return const Color(0xFF22C55E);
    default:
      return const Color(0xFF64748B);
  }
}

String babifixNotifCategoryLabel(String category) {
  switch (category) {
    case 'demande':
      return 'Demande & Mission';
    case 'litige':
      return 'Litige & Securite';
    case 'message':
      return 'Message client';
    case 'compte':
      return 'Compte & Profil';
    case 'actu':
      return 'Actualite Babifix';
    case 'paiement':
      return 'Paiement & Wallet';
    default:
      return 'Information';
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
  final dup = hub.value.any(
    (e) =>
        e.id == n.id ||
        (e.audience == n.audience &&
            e.title == n.title &&
            e.body == n.body &&
            n.createdAt.difference(e.createdAt).inSeconds.abs() < 4),
  );
  if (dup) return;
  final next = List<BabifixInAppNotif>.from(hub.value)..insert(0, n);
  if (next.length > 80) next.removeRange(80, next.length);
  hub.value = next;
  _maybePersist(persistStorageKey, hub.value);
}

Future<void> markServerNotificationsRead({List<int>? ids}) async {
  try {
    final t = await readStoredApiToken();
    if (t == null || t.isEmpty) return;
    await http
        .post(
          Uri.parse('${babifixApiBaseUrl()}/api/notifications/mark-read'),
          headers: {
            'Authorization': 'Bearer $t',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'ids': ids ?? <int>[]}),
        )
        .timeout(const Duration(seconds: 6));
  } catch (_) {}
}

void syncServerInAppNotifications({
  required ValueNotifier<List<BabifixInAppNotif>> hub,
  required BabifixNotifAudience audience,
  required List<Map<String, dynamic>> serverItems,
  String? persistStorageKey,
}) {
  String mapCategory(String rawType) {
    switch (rawType.toLowerCase()) {
      case 'reservation':
      case 'demande':
        return 'demande';
      case 'payment':
      case 'paiement':
        return 'paiement';
      case 'dispute':
      case 'litige':
        return 'litige';
      case 'message':
      case 'chat':
        return 'message';
      case 'broadcast':
      case 'annonce':
      case 'actu':
        return 'actu';
      case 'validation':
      case 'compte':
        return 'compte';
      default:
        return 'info';
    }
  }

  String mapRoute(String rawType) {
    switch (rawType.toLowerCase()) {
      case 'reservation':
      case 'demande':
      case 'dispute':
      case 'litige':
        return 'requests';
      case 'payment':
      case 'paiement':
        return 'wallet';
      case 'message':
      case 'chat':
        return 'messages';
      case 'validation':
      case 'compte':
        return 'profile';
      default:
        return 'dashboard';
    }
  }

  final mappedServer = serverItems.map((raw) {
    final t = '${raw['type'] ?? 'info'}';
    DateTime dt;
    try {
      dt = DateTime.parse('${raw['created_at']}').toLocal();
    } catch (_) {
      dt = DateTime.now();
    }
    return BabifixInAppNotif(
      id: 'srv-${raw['id']}',
      audience: audience,
      category: mapCategory(t),
      title: '${raw['title'] ?? 'Notification'}',
      body: '${raw['body'] ?? ''}',
      createdAt: dt,
      read: raw['lu'] == true,
      severity: t.toLowerCase() == 'dispute'
          ? BabifixNotifSeverity.urgent
          : BabifixNotifSeverity.important,
      actionRoute: mapRoute(t),
    );
  }).toList();

  final localOnly = hub.value.where((local) {
    if (local.audience != audience || local.id.startsWith('srv-')) {
      return false;
    }
    return !mappedServer.any(
      (srv) =>
          srv.title == local.title &&
          local.createdAt.difference(srv.createdAt).inMinutes.abs() < 2,
    );
  }).toList();

  final merged = <BabifixInAppNotif>[...mappedServer, ...localOnly]
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  if (merged.length > 80) merged.removeRange(80, merged.length);
  hub.value = merged;
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

/// Affiche la feuille de details complete pour une notification prestataire
void showPrestataireNotifDetailModal(
  BuildContext context,
  BabifixInAppNotif notif, {
  ValueChanged<String>? onNavigate,
  VoidCallback? onMarkRead,
}) {
  onMarkRead?.call();
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  final color = babifixNotifCategoryColor(notif.category);

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(babifixNotifCategoryIcon(notif.category), color: color, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                babifixNotifCategoryLabel(notif.category).toUpperCase(),
                                style: TextStyle(
                                  color: color,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            if (notif.severity == BabifixNotifSeverity.urgent) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDC2626),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: const Text(
                                  'URGENT',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          notif.dateLabel,
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                notif.title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
                ),
                child: Text(
                  notif.body.isNotEmpty ? notif.body : 'Aucun detail supplementaire.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: cs.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        if (notif.actionRoute != null && notif.actionRoute!.isNotEmpty) {
                          onNavigate?.call(notif.actionRoute!);
                        } else {
                          switch (notif.category) {
                            case 'demande':
                              onNavigate?.call('requests');
                              break;
                            case 'paiement':
                              onNavigate?.call('wallet');
                              break;
                            case 'litige':
                              onNavigate?.call('requests');
                              break;
                            case 'message':
                              onNavigate?.call('messages');
                              break;
                            case 'actu':
                              onNavigate?.call('actualites');
                              break;
                            default:
                              break;
                          }
                        }
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                      label: Text(
                        _prestataireActionLabel(notif),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Fermer'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

String _prestataireActionLabel(BabifixInAppNotif notif) {
  if (notif.actionRoute != null && notif.actionRoute!.isNotEmpty) {
    return 'Acceder a l\'action';
  }
  switch (notif.category) {
    case 'demande':
      return 'Voir les demandes';
    case 'paiement':
      return 'Voir le portefeuille';
    case 'litige':
      return 'Suivre les litiges';
    case 'message':
      return 'Ouvrir les messages';
    case 'actu':
      return 'Voir les actualites';
    default:
      return 'Compris';
  }
}

/// Affiche le centre de notifications pro avec filtres par motif et vue de detail
void showPrestataireNotificationHub(
  BuildContext context,
  ValueNotifier<List<BabifixInAppNotif>> hub,
  ValueChanged<String> onNavigate,
) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (ctx) => _PrestataireNotifHubSheet(hub: hub, onNavigate: onNavigate),
  );
}

class _PrestataireNotifHubSheet extends StatefulWidget {
  const _PrestataireNotifHubSheet({required this.hub, required this.onNavigate});

  final ValueNotifier<List<BabifixInAppNotif>> hub;
  final ValueChanged<String> onNavigate;

  @override
  State<_PrestataireNotifHubSheet> createState() => _PrestataireNotifHubSheetState();
}

class _PrestataireNotifHubSheetState extends State<_PrestataireNotifHubSheet> {
  String _filter = 'all'; // all, demande, paiement, litige, message, system
  bool _showHistory = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      maxChildSize: 0.94,
      minChildSize: 0.35,
      builder: (sheetCtx, scrollCtrl) {
        return ValueListenableBuilder<List<BabifixInAppNotif>>(
          valueListenable: widget.hub,
          builder: (context, all, _) {
            final proItems = all
                .where((e) => e.audience == BabifixNotifAudience.prestataire)
                .toList();
            final unread = proItems.where((e) => !e.read).length;
            final readCount = proItems.where((e) => e.read).length;
            final visibleBase =
                _showHistory ? proItems : proItems.where((e) => !e.read).toList();

            final filteredItems = visibleBase.where((n) {
              if (_filter == 'all') return true;
              if (_filter == 'demande') return n.category == 'demande';
              if (_filter == 'paiement') return n.category == 'paiement';
              if (_filter == 'litige') return n.category == 'litige';
              if (_filter == 'message') return n.category == 'message';
              if (_filter == 'system') {
                return n.category == 'compte' || n.category == 'actu' || n.category == 'info';
              }
              return true;
            }).toList();

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 14, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Text(
                              'Notifications Pro',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (unread > 0) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDC2626),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(
                                  '$unread',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (unread > 0)
                        TextButton.icon(
                          onPressed: () {
                            markAllInAppRead(
                              widget.hub,
                              BabifixNotifAudience.prestataire,
                              persistStorageKey: BabifixInAppNotifStorageKeys.prestataire,
                            );
                            unawaited(markServerNotificationsRead());
                          },
                          icon: const Icon(Icons.done_all_rounded, size: 16),
                          label: const Text('Tout lu', style: TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      _buildChip(cs, 'all', _showHistory ? 'Toutes' : 'Non lues', visibleBase.length, Icons.all_inbox_rounded),
                      _buildChip(cs, 'demande', 'Demandes', visibleBase.where((n) => n.category == 'demande').length, Icons.add_task_rounded),
                      _buildChip(cs, 'paiement', 'Paiements', visibleBase.where((n) => n.category == 'paiement').length, Icons.payments_rounded),
                      _buildChip(cs, 'litige', 'Litiges', visibleBase.where((n) => n.category == 'litige').length, Icons.gavel_rounded),
                      _buildChip(cs, 'message', 'Messages', visibleBase.where((n) => n.category == 'message').length, Icons.chat_bubble_rounded),
                      _buildChip(cs, 'system', 'Annonces', visibleBase.where((n) => n.category == 'compte' || n.category == 'actu' || n.category == 'info').length, Icons.campaign_rounded),
                      if (readCount > 0)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            avatar: Icon(
                              Icons.history_rounded,
                              size: 14,
                              color: _showHistory ? Colors.white : cs.onSurfaceVariant,
                            ),
                            label: Text(
                              _showHistory ? 'Masquer lues' : 'Historique ($readCount)',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: _showHistory ? FontWeight.w700 : FontWeight.w600,
                                color: _showHistory ? Colors.white : cs.onSurface,
                              ),
                            ),
                            selected: _showHistory,
                            selectedColor: const Color(0xFF334155),
                            backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                            showCheckmark: false,
                            side: BorderSide(
                              color: _showHistory ? const Color(0xFF334155) : cs.outlineVariant.withValues(alpha: 0.5),
                            ),
                            onSelected: (v) => setState(() => _showHistory = v),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                const Divider(height: 1, thickness: 1),
                Expanded(
                  child: filteredItems.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.notifications_none_rounded,
                                size: 52,
                                color: cs.outline.withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Aucune notification dans cette rubrique.\n'
                                'Vos demandes de missions, virements et alertes apparaitront ici.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: cs.onSurfaceVariant,
                                  height: 1.4,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                          itemCount: filteredItems.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (itemCtx, i) {
                            final n = filteredItems[i];
                            final c = babifixNotifCategoryColor(n.category);
                            return Material(
                              color: n.read
                                  ? cs.surfaceContainerHighest.withValues(alpha: 0.35)
                                  : c.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(16),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () {
                                  markOneRead(
                                    widget.hub,
                                    n.id,
                                    persistStorageKey: BabifixInAppNotifStorageKeys.prestataire,
                                  );
                                  if (n.id.startsWith('srv-')) {
                                    final srvId = int.tryParse(n.id.substring(4));
                                    if (srvId != null) {
                                      unawaited(markServerNotificationsRead(ids: [srvId]));
                                    }
                                  }
                                  showPrestataireNotifDetailModal(
                                    context,
                                    n,
                                    onNavigate: (route) {
                                      Navigator.pop(sheetCtx);
                                      widget.onNavigate(route);
                                    },
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: c.withValues(alpha: 0.16),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Icon(
                                          babifixNotifCategoryIcon(n.category),
                                          color: c,
                                          size: 22,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: c.withValues(alpha: 0.12),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    babifixNotifCategoryLabel(n.category).toUpperCase(),
                                                    style: TextStyle(
                                                      fontSize: 9,
                                                      fontWeight: FontWeight.w800,
                                                      color: c,
                                                    ),
                                                  ),
                                                ),
                                                const Spacer(),
                                                Text(
                                                  n.dateLabel,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: cs.onSurfaceVariant,
                                                  ),
                                                ),
                                                if (!n.read) ...[
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    width: 8,
                                                    height: 8,
                                                    decoration: BoxDecoration(
                                                      color: c,
                                                      shape: BoxShape.circle,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              n.title,
                                              style: TextStyle(
                                                fontWeight: n.read ? FontWeight.w600 : FontWeight.w800,
                                                fontSize: 14,
                                                color: cs.onSurface,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              n.body,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                height: 1.35,
                                                color: cs.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        size: 18,
                                        color: cs.outlineVariant,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildChip(ColorScheme cs, String id, String label, int count, IconData icon) {
    final isSelected = _filter == id;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        avatar: Icon(
          icon,
          size: 14,
          color: isSelected ? Colors.white : cs.onSurfaceVariant,
        ),
        label: Text(
          '$label ($count)',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            color: isSelected ? Colors.white : cs.onSurface,
          ),
        ),
        selected: isSelected,
        selectedColor: const Color(0xFF0084D1),
        backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        showCheckmark: false,
        side: BorderSide(
          color: isSelected ? const Color(0xFF0084D1) : cs.outlineVariant.withValues(alpha: 0.5),
        ),
        onSelected: (_) {
          setState(() => _filter = id);
        },
      ),
    );
  }
}

