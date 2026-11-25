import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../babifix_api_config.dart';
import '../../user_store.dart';
import '../../shared/in_app_notifications.dart';
import '../../shared/widgets/babifix_button.dart';
import '../../shared/widgets/babifix_ring_loader.dart';
import '../../shared/widgets/babifix_sheet.dart';
import '../../shared/widgets/babifix_snackbar.dart';

class _Notif {
  final int id;
  final String title;
  final String body;
  final String type;
  final String reference;
  final bool lu;
  final String createdAt;

  const _Notif({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.reference,
    required this.lu,
    required this.createdAt,
  });

  factory _Notif.fromJson(Map<String, dynamic> j) => _Notif(
        id: j['id'] as int? ?? 0,
        title: j['title'] as String? ?? '',
        body: j['body'] as String? ?? '',
        type: j['type'] as String? ?? 'general',
        reference: j['reference'] as String? ?? '',
        lu: j['lu'] as bool? ?? false,
        createdAt: j['created_at'] as String? ?? '',
      );

  _Notif copyWith({bool? lu}) => _Notif(
        id: id,
        title: title,
        body: body,
        type: type,
        reference: reference,
        lu: lu ?? this.lu,
        createdAt: createdAt,
      );
}

class NotificationsScreen extends StatefulWidget {
  final String? apiBase;
  final String? authToken;
  final ValueChanged<String>? onNavigateRoute;
  final ValueNotifier<List<BabifixInAppNotif>>? inAppHub;

  const NotificationsScreen({
    super.key,
    this.apiBase,
    this.authToken,
    this.onNavigateRoute,
    this.inAppHub,
  });

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<_Notif> _notifs = [];
  bool _loading = true;
  int _unread = 0;
  bool _showHistory = false;
  String _selectedFilter = 'all'; // all, reservation, payment, dispute, broadcast

  String get _base => widget.apiBase ?? babifixApiBaseUrl();

  Future<String?> _token() async {
    if (widget.authToken != null && widget.authToken!.isNotEmpty) {
      return widget.authToken;
    }
    return BabifixUserStore.getApiToken();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final token = await _token();
    if (token == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final res = await http
          .get(Uri.parse('$_base/api/notifications'),
              headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final rawList = (data['notifications'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        if (widget.inAppHub != null) {
          syncServerInAppNotifications(
            hub: widget.inAppHub!,
            audience: BabifixNotifAudience.client,
            serverItems: rawList,
            persistStorageKey: BabifixInAppNotifStorageKeys.client,
          );
        }
        setState(() {
          _notifs = rawList.map(_Notif.fromJson).toList();
          _unread = data['unread'] as int? ?? _notifs.where((n) => !n.lu).length;
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _markAllRead() async {
    final token = await _token();
    if (widget.inAppHub != null) {
      markAllInAppRead(
        widget.inAppHub!,
        BabifixNotifAudience.client,
        persistStorageKey: BabifixInAppNotifStorageKeys.client,
      );
    }
    setState(() {
      _notifs = _notifs.map((n) => n.copyWith(lu: true)).toList();
      _unread = 0;
    });
    if (token != null) {
      try {
        await http.post(
          Uri.parse('$_base/api/notifications/mark-read'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'ids': <int>[]}),
        );
      } catch (_) {}
    }
    if (mounted) {
      showBabifixToast(
        context,
        type: BabifixToastType.success,
        message: 'Toutes les notifications sont marquées comme lues.',
      );
    }
  }

  Future<void> _markSingleRead(int id) async {
    final token = await _token();
    if (widget.inAppHub != null) {
      markOneRead(
        widget.inAppHub!,
        'srv-$id',
        persistStorageKey: BabifixInAppNotifStorageKeys.client,
      );
    }
    setState(() {
      _notifs = _notifs.map((n) => n.id == id ? n.copyWith(lu: true) : n).toList();
      _unread = _notifs.where((n) => !n.lu).length;
    });
    if (token == null) return;
    try {
      final res = await http.post(
        Uri.parse('$_base/api/notifications/mark-read'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'ids': [id],
        }),
      );
      if (res.statusCode == 200 && mounted) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map && decoded['unread'] is int) {
          setState(() => _unread = decoded['unread'] as int);
        }
      }
    } catch (_) {}
  }

  IconData _typeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'reservation':
      case 'demande':
        return Icons.calendar_today_rounded;
      case 'message':
      case 'chat':
        return Icons.chat_bubble_rounded;
      case 'validation':
      case 'compte':
        return Icons.verified_user_rounded;
      case 'payment':
      case 'paiement':
        return Icons.account_balance_wallet_rounded;
      case 'dispute':
      case 'litige':
        return Icons.gavel_rounded;
      case 'broadcast':
      case 'annonce':
      case 'actu':
        return Icons.campaign_rounded;
      default:
        return Icons.notifications_active_rounded;
    }
  }

  Color _typeColor(String type) {
    switch (type.toLowerCase()) {
      case 'reservation':
      case 'demande':
        return const Color(0xFF0284C7); // Cyan Babifix
      case 'message':
      case 'chat':
        return const Color(0xFF8B5CF6); // Violet
      case 'validation':
      case 'compte':
        return const Color(0xFF059669); // Emeraude
      case 'payment':
      case 'paiement':
        return const Color(0xFF10B981); // Vert
      case 'dispute':
      case 'litige':
        return const Color(0xFFDC2626); // Rouge
      case 'broadcast':
      case 'annonce':
      case 'actu':
        return const Color(0xFFF59E0B); // Ambre
      default:
        return const Color(0xFF64748B); // Slate
    }
  }

  String _typeLabel(String type) {
    switch (type.toLowerCase()) {
      case 'reservation':
      case 'demande':
        return 'Mission & Devis';
      case 'message':
      case 'chat':
        return 'Message';
      case 'validation':
      case 'compte':
        return 'Validation compte';
      case 'payment':
      case 'paiement':
        return 'Paiement & Facture';
      case 'dispute':
      case 'litige':
        return 'Securite & Litige';
      case 'broadcast':
      case 'annonce':
      case 'actu':
        return 'Annonce Babifix';
      default:
        return 'Information';
    }
  }

  String _timeAgo(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'A l\'instant';
      if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
      if (diff.inHours < 24) return 'Il y a ${diff.inHours} h';
      if (diff.inDays == 1) return 'Hier, ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      if (diff.inDays < 7) return 'Il y a ${diff.inDays} j';
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) {
      return '';
    }
  }

  String _fullDateTime(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      const mois = [
        'janv.', 'fevr.', 'mars', 'avr.', 'mai', 'juin',
        'juil.', 'aout', 'sept.', 'oct.', 'nov.', 'dec.'
      ];
      final m = mois[dt.month - 1];
      final h = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return '${dt.day} $m ${dt.year} a $h:$min';
    } catch (_) {
      return iso;
    }
  }

  List<_Notif> get _filteredNotifs {
    final base = _showHistory ? _notifs : _notifs.where((n) => !n.lu).toList();
    if (_selectedFilter == 'all') return base;
    if (_selectedFilter == 'reservation') {
      return base.where((n) => n.type.toLowerCase() == 'reservation' || n.type.toLowerCase() == 'demande').toList();
    }
    if (_selectedFilter == 'payment') {
      return base.where((n) => n.type.toLowerCase() == 'payment' || n.type.toLowerCase() == 'paiement').toList();
    }
    if (_selectedFilter == 'dispute') {
      return base.where((n) => n.type.toLowerCase() == 'dispute' || n.type.toLowerCase() == 'litige').toList();
    }
    if (_selectedFilter == 'system') {
      return base.where((n) =>
          n.type.toLowerCase() == 'broadcast' ||
          n.type.toLowerCase() == 'validation' ||
          n.type.toLowerCase() == 'general' ||
          n.type.toLowerCase() == 'compte' ||
          n.type.toLowerCase() == 'actu').toList();
    }
    return base;
  }

  void _showNotificationDetailModal(_Notif notif) {
    if (!notif.lu) {
      _markSingleRead(notif.id);
    }
    final color = _typeColor(notif.type);
    final cs = Theme.of(context).colorScheme;

    showBabifixModalSheet<void>(
      context: context,
      backgroundColor: cs.surface,
      builder: (ctx) {
        return Container(
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
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(_typeIcon(notif.type), color: color, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              _typeLabel(notif.type).toUpperCase(),
                              style: TextStyle(
                                color: color,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _fullDateTime(notif.createdAt),
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
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
                if (notif.reference.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.tag_rounded, size: 14, color: cs.primary),
                        const SizedBox(width: 4),
                        Text(
                          'Reference : ${notif.reference}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    notif.body.isNotEmpty ? notif.body : 'Aucun detail supplementaire fourni.',
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
                      child: BabifixButton(
                        label: _actionButtonLabel(notif.type),
                        icon: _actionButtonIcon(notif.type),
                        backgroundColor: color,
                        foregroundColor: Colors.white,
                        height: 48,
                        onPressed: () {
                          Navigator.pop(ctx);
                          _handleNotificationAction(notif);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                        shape: RoundedRectangleBeside(borderRadius: BorderRadius.circular(12)),
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

  IconData _actionButtonIcon(String type) {
    switch (type.toLowerCase()) {
      case 'reservation':
      case 'demande':
        return Icons.arrow_forward_rounded;
      case 'payment':
      case 'paiement':
        return Icons.receipt_long_rounded;
      case 'dispute':
      case 'litige':
        return Icons.shield_rounded;
      case 'message':
        return Icons.chat_rounded;
      default:
        return Icons.check_circle_outline_rounded;
    }
  }

  String _actionButtonLabel(String type) {
    switch (type.toLowerCase()) {
      case 'reservation':
      case 'demande':
        return 'Voir la reservation';
      case 'payment':
      case 'paiement':
        return 'Consulter le recu';
      case 'dispute':
      case 'litige':
        return 'Suivre le litige';
      case 'message':
        return 'Ouvrir la conversation';
      default:
        return 'Compris';
    }
  }

  void _handleNotificationAction(_Notif notif) {
    final type = notif.type.toLowerCase();
    if (widget.onNavigateRoute != null) {
      if (type == 'reservation' || type == 'demande') {
        widget.onNavigateRoute!('/reservations');
      } else if (type == 'payment' || type == 'paiement') {
        widget.onNavigateRoute!('/paiements');
      } else if (type == 'dispute' || type == 'litige') {
        widget.onNavigateRoute!('/litiges');
      } else if (type == 'message' || type == 'chat') {
        widget.onNavigateRoute!('/messages');
      }
    } else {
      Navigator.of(context).pop(notif);
    }
  }

  Widget _buildFilterPills(ColorScheme cs) {
    final activeBase = _showHistory ? _notifs : _notifs.where((n) => !n.lu).toList();
    final readCount = _notifs.where((n) => n.lu).length;
    final items = [
      {'id': 'all', 'label': _showHistory ? 'Toutes' : 'Non lues', 'icon': Icons.all_inbox_rounded},
      {'id': 'reservation', 'label': 'Missions', 'icon': Icons.calendar_today_rounded},
      {'id': 'payment', 'label': 'Paiements', 'icon': Icons.payments_rounded},
      {'id': 'dispute', 'label': 'Litiges', 'icon': Icons.gavel_rounded},
      {'id': 'system', 'label': 'Annonces', 'icon': Icons.campaign_rounded},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          ...items.map((f) {
            final isSelected = _selectedFilter == f['id'];
            final count = f['id'] == 'all'
                ? activeBase.length
                : (f['id'] == 'reservation'
                    ? activeBase.where((n) => n.type == 'reservation' || n.type == 'demande').length
                    : (f['id'] == 'payment'
                        ? activeBase.where((n) => n.type == 'payment' || n.type == 'paiement').length
                        : (f['id'] == 'dispute'
                            ? activeBase.where((n) => n.type == 'dispute' || n.type == 'litige').length
                            : activeBase.where((n) => n.type != 'reservation' && n.type != 'payment' && n.type != 'dispute').length)));

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: Icon(
                  f['icon'] as IconData,
                  size: 15,
                  color: isSelected ? Colors.white : cs.onSurfaceVariant,
                ),
                label: Text(
                  '${f['label']} ($count)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                    color: isSelected ? Colors.white : cs.onSurface,
                  ),
                ),
                selected: isSelected,
                selectedColor: const Color(0xFF0284C7),
                backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                showCheckmark: false,
                side: BorderSide(
                  color: isSelected ? const Color(0xFF0284C7) : cs.outlineVariant.withValues(alpha: 0.5),
                ),
                onSelected: (_) {
                  setState(() => _selectedFilter = f['id'] as String);
                },
              ),
            );
          }),
          if (readCount > 0)
            ChoiceChip(
              avatar: Icon(
                Icons.history_rounded,
                size: 15,
                color: _showHistory ? Colors.white : cs.onSurfaceVariant,
              ),
              label: Text(
                _showHistory ? 'Masquer lues' : 'Historique ($readCount)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: _showHistory ? FontWeight.w700 : FontWeight.w600,
                  color: _showHistory ? Colors.white : cs.onSurface,
                ),
              ),
              selected: _showHistory,
              selectedColor: const Color(0xFF334155),
              backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.35),
              showCheckmark: false,
              side: BorderSide(
                color: _showHistory ? const Color(0xFF334155) : cs.outlineVariant.withValues(alpha: 0.5),
              ),
              onSelected: (v) {
                setState(() => _showHistory = v);
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final displayList = _filteredNotifs;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        titleSpacing: 8,
        title: Row(
          children: [
            const Flexible(
              child: Text(
                'Centre de notifications',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_unread > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '$_unread',
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
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        actions: [
          if (_unread > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: TextButton.icon(
                onPressed: _markAllRead,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.done_all_rounded, size: 16),
                label: const Text(
                  'Tout lu',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualiser',
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: BabifixRingLoader.cyan(size: 28))
          : Column(
              children: [
                _buildFilterPills(cs),
                const Divider(height: 1, thickness: 1),
                Expanded(
                  child: displayList.isEmpty
                      ? RefreshIndicator(
                          onRefresh: _load,
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(24, 60, 24, 120),
                            children: [
                              Icon(
                                Icons.notifications_off_rounded,
                                size: 64,
                                color: cs.outline.withValues(alpha: 0.35),
                              ),
                              const SizedBox(height: 18),
                              const Text(
                                'Aucune notification dans cette rubrique',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Vos alertes d\'interventions, devis et paiements apparaitront ici.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 13, color: cs.outline),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                            itemCount: displayList.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (ctx, i) {
                              final n = displayList[i];
                              final color = _typeColor(n.type);
                              return Material(
                                color: n.lu
                                    ? cs.surface
                                    : color.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(14),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () => _showNotificationDetailModal(n),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: n.lu
                                            ? cs.outlineVariant.withValues(alpha: 0.6)
                                            : color.withValues(alpha: 0.35),
                                        width: n.lu ? 1 : 1.5,
                                      ),
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 42,
                                          height: 42,
                                          decoration: BoxDecoration(
                                            color: color.withValues(alpha: 0.14),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Icon(_typeIcon(n.type), color: color, size: 22),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(
                                                        horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: color.withValues(alpha: 0.1),
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: Text(
                                                      _typeLabel(n.type).toUpperCase(),
                                                      style: TextStyle(
                                                        fontSize: 9,
                                                        fontWeight: FontWeight.w800,
                                                        color: color,
                                                      ),
                                                    ),
                                                  ),
                                                  const Spacer(),
                                                  Text(
                                                    _timeAgo(n.createdAt),
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: cs.onSurfaceVariant,
                                                    ),
                                                  ),
                                                  if (!n.lu) ...[
                                                    const SizedBox(width: 6),
                                                    Container(
                                                      width: 8,
                                                      height: 8,
                                                      decoration: BoxDecoration(
                                                        color: color,
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
                                                  fontWeight: n.lu
                                                      ? FontWeight.w600
                                                      : FontWeight.w800,
                                                  fontSize: 14,
                                                  color: cs.onSurface,
                                                ),
                                              ),
                                              if (n.body.isNotEmpty) ...[
                                                const SizedBox(height: 4),
                                                Text(
                                                  n.body,
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 12.5,
                                                    color: cs.onSurfaceVariant,
                                                    height: 1.35,
                                                  ),
                                                ),
                                              ],
                                              if (n.reference.isNotEmpty) ...[
                                                const SizedBox(height: 6),
                                                Text(
                                                  'Ref : ${n.reference}',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: cs.primary,
                                                  ),
                                                ),
                                              ],
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
                ),
              ],
            ),
    );
  }
}

class RoundedRectangleBeside extends RoundedRectangleBorder {
  const RoundedRectangleBeside({super.borderRadius});
}
