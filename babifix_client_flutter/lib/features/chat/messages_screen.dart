import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../babifix_design_system.dart';
import '../../json_utils.dart';
import '../../user_store.dart';
import 'chat_room_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key, required this.apiBase});

  final String apiBase;

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  bool resolvingToken = true;
  bool loading = false;
  String? token;
  bool sessionLocal = false;
  List<Map<String, dynamic>> rows = [];
  List<Map<String, dynamic>> _filtered = [];
  final _searchCtrl = TextEditingController();
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _searchCtrl.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final t = await BabifixUserStore.getApiToken();
    final sess = await BabifixUserStore.isLoggedIn();
    if (!mounted) return;
    setState(() {
      token = t;
      sessionLocal = sess;
      resolvingToken = false;
      loading = t != null && t.isNotEmpty;
    });
    if (t != null && t.isNotEmpty) await _load();
  }

  Future<void> _load() async {
    final t = await BabifixUserStore.getApiToken();
    if (!mounted) return;
    setState(() {
      token = t;
      loading = true;
    });
    if (t == null || t.isEmpty) {
      if (mounted) setState(() => loading = false);
      return;
    }
    try {
      final res = await http.get(
        Uri.parse('${widget.apiBase}/api/client/conversations'),
        headers: {'Authorization': 'Bearer $t'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final list = (data['conversations'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();
        if (mounted) {
          setState(() {
            rows = list;
            _applyFilter();
          });
        }
      }
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  void _applyFilter() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? List.from(rows)
          : rows.where((r) {
              final name = '${r['prestataire_username'] ?? ''}'.toLowerCase();
              final msg = '${r['last_message'] ?? ''}'.toLowerCase();
              return name.contains(q) || msg.contains(q);
            }).toList();
    });
  }

  Color _avatarColor(String name) {
    const palette = [
      Color(0xFF4CC9F0),
      Color(0xFFF97316),
      Color(0xFF10B981),
      Color(0xFF8B5CF6),
      Color(0xFFF59E0B),
      Color(0xFFEF4444),
      Color(0xFF0284C7),
      Color(0xFF7C3AED),
    ];
    final idx = name.isNotEmpty ? name.codeUnitAt(0) % palette.length : 0;
    return palette[idx];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isLight = cs.brightness == Brightness.light;
    final bg = isLight ? const Color(0xFFF8FAFC) : const Color(0xFF0D1117);
    final cardBg = isLight ? Colors.white : const Color(0xFF161B22);
    final textPrimary = isLight ? const Color(0xFF0F172A) : Colors.white;
    final textSecondary = isLight
        ? const Color(0xFF64748B)
        : const Color(0xFF9CA3AF);
    final divColor = isLight
        ? const Color(0xFFE2E8F0)
        : const Color(0xFF21262D);

    if (resolvingToken || loading) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: cardBg,
          elevation: 0,
          title: Text(
            'Messages',
            style: TextStyle(fontWeight: FontWeight.w800, color: textPrimary),
          ),
        ),
        body: Center(
          child: CircularProgressIndicator(
            color: BabifixDesign.cyan,
            strokeWidth: 2.5,
          ),
        ),
      );
    }

    if (token == null || token!.isEmpty) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: cardBg,
          elevation: 0,
          title: Text(
            'Messages',
            style: TextStyle(fontWeight: FontWeight.w800, color: textPrimary),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: BabifixDesign.cyan.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.lock_outline_rounded,
                    size: 36,
                    color: BabifixDesign.cyan,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Connexion requise',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  sessionLocal
                      ? 'Session locale — reconnectez-vous avec le serveur actif.'
                      : 'Connectez-vous pour voir vos conversations.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: textSecondary, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── AppBar premium ─────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              decoration: BoxDecoration(
                color: cardBg,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isLight ? 0.04 : 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_rounded, color: textPrimary),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Messages',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: textPrimary,
                            letterSpacing: -0.5,
                          ),
                        ),
                        if (rows.isNotEmpty)
                          Text(
                            '${rows.length} conversation${rows.length > 1 ? 's' : ''}',
                            style: TextStyle(
                              fontSize: 12,
                              color: textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Total unread badge
                  Builder(
                    builder: (_) {
                      final totalUnread = rows.fold<int>(
                        0,
                        (s, r) => s + ((r['unread_count'] as int?) ?? 0),
                      );
                      if (totalUnread > 0) {
                        return Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: BabifixDesign.cyan,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            '$totalUnread non lu${totalUnread > 1 ? 's' : ''}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                  IconButton(
                    onPressed: () => setState(() {
                      _searching = !_searching;
                      if (!_searching) _searchCtrl.clear();
                    }),
                    icon: Icon(
                      _searching
                          ? Icons.search_off_rounded
                          : Icons.search_rounded,
                      color: textSecondary,
                    ),
                    tooltip: 'Rechercher',
                  ),
                ],
              ),
            ),
            // ── Barre de recherche ─────────────────────────────────────────
            if (_searching)
              Container(
                color: cardBg,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Rechercher un prestataire…',
                    hintStyle: TextStyle(color: textSecondary, fontSize: 14),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: textSecondary,
                      size: 20,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: divColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: divColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: BabifixDesign.cyan.withValues(alpha: 0.7),
                        width: 1.5,
                      ),
                    ),
                    filled: true,
                    fillColor: bg,
                  ),
                ),
              ),
            // ── Liste ──────────────────────────────────────────────────────
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                color: BabifixDesign.cyan,
                backgroundColor: cardBg,
                child: _filtered.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(40),
                        children: [
                          const SizedBox(height: 48),
                          Center(
                            child: Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: BabifixDesign.cyan.withValues(
                                  alpha: 0.08,
                                ),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: BabifixDesign.cyan.withValues(
                                    alpha: 0.2,
                                  ),
                                  width: 1.5,
                                ),
                              ),
                              child: Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 38,
                                color: BabifixDesign.cyan,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            _searchCtrl.text.isNotEmpty
                                ? 'Aucun résultat'
                                : 'Aucune conversation',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _searchCtrl.text.isNotEmpty
                                ? 'Aucune conversation ne correspond à votre recherche.'
                                : 'Réservez un prestataire pour démarrer une discussion.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: textSecondary, height: 1.5),
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: _filtered.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          indent: 78,
                          endIndent: 16,
                          color: divColor,
                        ),
                        itemBuilder: (context, i) {
                          final r = _filtered[i];
                          final name =
                              '${r['prestataire_username'] ?? 'Prestataire'}';
                          final words = name.trim().split(RegExp(r'\s+'));
                          final initials = words.length >= 2
                              ? '${words[0][0]}${words[1][0]}'.toUpperCase()
                              : (name.isNotEmpty ? name[0].toUpperCase() : '?');
                          final pid = jsonInt(r['prestataire_id']);
                          final lastMessage = '${r['last_message'] ?? ''}';
                          final lastDate = r['last_date'] as String? ?? '';
                          final unread = (r['unread_count'] as int?) ?? 0;
                          final hasUnread = unread > 0;
                          final avatarColor = _avatarColor(name);

                          return InkWell(
                            onTap: () async {
                              final fresh =
                                  await BabifixUserStore.getApiToken();
                              if (!context.mounted) return;
                              await Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => ChatRoomScreen(
                                    name: name,
                                    peerUserId: pid,
                                    authToken: fresh,
                                    apiBase: widget.apiBase,
                                  ),
                                ),
                              );
                              _load();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 13,
                              ),
                              color: hasUnread
                                  ? avatarColor.withValues(
                                      alpha: isLight ? 0.04 : 0.06,
                                    )
                                  : null,
                              child: Row(
                                children: [
                                  // Avatar coloré
                                  Stack(
                                    children: [
                                      Container(
                                        width: 50,
                                        height: 50,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: LinearGradient(
                                            colors: [
                                              avatarColor,
                                              avatarColor.withValues(
                                                alpha: 0.65,
                                              ),
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: avatarColor.withValues(
                                                alpha: 0.25,
                                              ),
                                              blurRadius: 8,
                                              offset: const Offset(0, 3),
                                            ),
                                          ],
                                        ),
                                        child: Center(
                                          child: Text(
                                            initials,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 17,
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (hasUnread)
                                        Positioned(
                                          top: 0,
                                          right: 0,
                                          child: Container(
                                            width: 16,
                                            height: 16,
                                            decoration: BoxDecoration(
                                              color: BabifixDesign.ciOrange,
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: cardBg,
                                                width: 2,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(width: 14),
                                  // Texte
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                name,
                                                style: TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: hasUnread
                                                      ? FontWeight.w800
                                                      : FontWeight.w600,
                                                  color: textPrimary,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (lastDate.isNotEmpty) ...[
                                              const SizedBox(width: 8),
                                              Text(
                                                lastDate,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: hasUnread
                                                      ? BabifixDesign.cyan
                                                      : textSecondary,
                                                  fontWeight: hasUnread
                                                      ? FontWeight.w700
                                                      : FontWeight.normal,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                lastMessage.isEmpty
                                                    ? 'Nouvelle conversation'
                                                    : lastMessage,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: hasUnread
                                                      ? textPrimary.withValues(
                                                          alpha: 0.75,
                                                        )
                                                      : textSecondary,
                                                  fontWeight: hasUnread
                                                      ? FontWeight.w500
                                                      : FontWeight.normal,
                                                  height: 1.3,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (hasUnread) ...[
                                              const SizedBox(width: 8),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 7,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: BabifixDesign.cyan,
                                                  borderRadius:
                                                      BorderRadius.circular(99),
                                                ),
                                                child: Text(
                                                  unread > 99
                                                      ? '99+'
                                                      : '$unread',
                                                  style: TextStyle(
                                                    color: BabifixDesign.navy,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    color: textSecondary.withValues(alpha: 0.4),
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
