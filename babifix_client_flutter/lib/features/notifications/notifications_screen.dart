import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../user_store.dart';

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
}

class NotificationsScreen extends StatefulWidget {
  final String? apiBase;
  final String? authToken;

  const NotificationsScreen({super.key, this.apiBase, this.authToken});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<_Notif> _notifs = [];
  bool _loading = true;
  int _unread = 0;

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
        setState(() {
          _notifs = (data['notifications'] as List? ?? [])
              .map((e) => _Notif.fromJson(e as Map<String, dynamic>))
              .toList();
          _unread = data['unread'] as int? ?? 0;
          _loading = false;
        });
        if (_unread > 0) _markAllRead(token);
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _markAllRead(String token) async {
    try {
      await http.post(
        Uri.parse('$_base/api/notifications/mark-read'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'ids': <int>[]}),
      );
      setState(() {
        _notifs = _notifs.map((n) => _Notif(
          id: n.id, title: n.title, body: n.body, type: n.type,
          reference: n.reference, lu: true, createdAt: n.createdAt,
        )).toList();
        _unread = 0;
      });
    } catch (_) {}
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'reservation': return Icons.calendar_today_rounded;
      case 'message': return Icons.chat_rounded;
      case 'validation': return Icons.verified_rounded;
      case 'payment': return Icons.payments_rounded;
      case 'dispute': return Icons.report_rounded;
      case 'broadcast': return Icons.campaign_rounded;
      default: return Icons.notifications_rounded;
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'reservation': return BabifixDesign.ciBlue;
      case 'message': return BabifixDesign.ciGreen;
      case 'validation': return BabifixDesign.success;
      case 'payment': return BabifixDesign.ciOrange;
      case 'dispute': return BabifixDesign.error;
      case 'broadcast': return BabifixDesign.info;
      default: return Colors.grey;
    }
  }

  String _timeAgo(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'À l\'instant';
      if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
      if (diff.inHours < 24) return 'Il y a ${diff.inHours} h';
      if (diff.inDays == 1) return 'Hier';
      if (diff.inDays < 7) return 'Il y a ${diff.inDays} j';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) { return ''; }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Notifications'),
            if (_unread > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: BabifixDesign.error,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text('$_unread',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ],
          ],
        ),
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notifs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.notifications_off_rounded,
                          size: 64, color: cs.outline.withValues(alpha: 0.3)),
                      const SizedBox(height: 16),
                      const Text('Aucune notification',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _notifs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (ctx, i) {
                      final n = _notifs[i];
                      final color = _typeColor(n.type);
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: n.lu ? cs.surface : color.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(BabifixDesign.radiusMD),
                          border: Border.all(
                            color: n.lu ? cs.outlineVariant : color.withValues(alpha: 0.3),
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(_typeIcon(n.type), color: color, size: 20),
                          ),
                          title: Text(
                            n.title,
                            style: TextStyle(
                              fontWeight: n.lu ? FontWeight.w500 : FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (n.body.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(n.body,
                                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                ),
                              const SizedBox(height: 4),
                              Text(_timeAgo(n.createdAt),
                                  style: TextStyle(fontSize: 11, color: cs.outline)),
                            ],
                          ),
                          trailing: n.lu
                              ? null
                              : Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                                ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
