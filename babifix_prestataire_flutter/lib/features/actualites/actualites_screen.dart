import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../babifix_api_config.dart';
import '../../json_utils.dart';
import '../../shared/app_palette_mode.dart';
import '../../shared/auth_utils.dart';
import 'actualite_detail_screen.dart';

class PrestataireActuItem {
  const PrestataireActuItem({
    required this.id,
    required this.titre,
    required this.description,
    required this.imageUrl,
    required this.categorieTag,
    required this.dateLabel,
  });

  final int id;
  final String titre;
  final String description;
  final String imageUrl;
  final String categorieTag;
  final String dateLabel;
}

class PrestataireActualitesScreen extends StatefulWidget {
  const PrestataireActualitesScreen({
    super.key,
    required this.onBack,
    required this.refreshVersion,
    required this.paletteMode,
  });

  final VoidCallback onBack;
  final ValueNotifier<int> refreshVersion;
  final AppPaletteMode paletteMode;

  @override
  State<PrestataireActualitesScreen> createState() => _PrestataireActualitesScreenState();
}

class _PrestataireActualitesScreenState extends State<PrestataireActualitesScreen> {
  List<PrestataireActuItem> items = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    widget.refreshVersion.addListener(_onRefreshTick);
    _load();
  }

  @override
  void dispose() {
    widget.refreshVersion.removeListener(_onRefreshTick);
    super.dispose();
  }

  void _onRefreshTick() {
    _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => loading = true);
    try {
      final t = await readStoredApiToken();
      if (t == null || t.isEmpty) {
        if (mounted) setState(() => loading = false);
        return;
      }
      final res = await http.get(
        Uri.parse('${babifixApiBaseUrl()}/api/client/actualites'),
        headers: {'Authorization': 'Bearer $t'},
      );
      if (res.statusCode != 200) {
        if (mounted) setState(() => loading = false);
        return;
      }
      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (data['items'] as List<dynamic>? ?? [])
          .map(
            (item) => PrestataireActuItem(
              id: jsonInt(item['id']),
              titre: '${item['titre'] ?? ''}',
              description: '${item['description'] ?? ''}',
              imageUrl: '${item['image_url'] ?? ''}',
              categorieTag: '${item['categorie_tag'] ?? ''}',
              dateLabel: '${item['date_publication'] ?? ''}'.split('T').first,
            ),
          )
          .toList();
      setState(() {
        items = list;
        loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _openDetail(PrestataireActuItem a) async {
    final t = await readStoredApiToken();
    if (t == null) return;
    try {
      final res = await http.get(
        Uri.parse('${babifixApiBaseUrl()}/api/client/actualites/${a.id}'),
        headers: {'Authorization': 'Bearer $t'},
      );
      if (res.statusCode != 200 || !mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final item = data['item'] as Map<String, dynamic>? ?? {};
      final full = PrestataireActuItem(
        id: jsonInt(item['id']),
        titre: '${item['titre'] ?? ''}',
        description: '${item['description'] ?? ''}',
        imageUrl: '${item['image_url'] ?? ''}',
        categorieTag: '${item['categorie_tag'] ?? ''}',
        dateLabel: '${item['date_publication'] ?? ''}'.split('T').first,
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (ctx) => PrestataireActuDetailScreen(
            item: full,
            isLight: widget.paletteMode == AppPaletteMode.light,
          ),
        ),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isLight = widget.paletteMode == AppPaletteMode.light;
    final bg = isLight ? const Color(0xFFF6F8FC) : const Color(0xFF0B1B34);
    final card = isLight ? Colors.white : const Color(0xFF151D2E);
    final text = isLight ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final sub = isLight ? const Color(0xFF64748B) : const Color(0xFFB4C2D9);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        leading: IconButton(onPressed: widget.onBack, icon: const Icon(Icons.arrow_back)),
        title: const Text('Actualit\u00e9s'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF4CC9F0)))
          : RefreshIndicator(
              color: const Color(0xFF4CC9F0),
              onRefresh: () => _load(),
              child: items.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(32),
                      children: [
                        Icon(Icons.article_outlined, size: 64, color: sub),
                        const SizedBox(height: 16),
                        Text(
                          'Aucune actualit\u00e9 pour le moment',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: text),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final a = items[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Material(
                            color: card,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => _openDetail(a),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (a.imageUrl.isNotEmpty)
                                    ClipRRect(
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                                      child: AspectRatio(
                                        aspectRatio: 16 / 9,
                                        child: Image.network(
                                          a.imageUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) => Container(
                                            color: const Color(0xFFE2E8F0),
                                            child: const Icon(Icons.image_not_supported_outlined),
                                          ),
                                        ),
                                      ),
                                    ),
                                  Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (a.categorieTag.isNotEmpty)
                                          Text(
                                            a.categorieTag.replaceAll('_', ' '),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF0284C7),
                                              fontSize: 12,
                                            ),
                                          ),
                                        const SizedBox(height: 4),
                                        Text(
                                          a.titre,
                                          style: TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w800,
                                            color: text,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          a.description,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(color: sub, height: 1.35),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          a.dateLabel,
                                          style: TextStyle(fontSize: 12, color: sub.withValues(alpha: 0.9)),
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
    );
  }
}
