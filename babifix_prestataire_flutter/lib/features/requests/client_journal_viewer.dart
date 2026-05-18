/// Viewer du journal client côté prestataire (B5).
///
/// Lecture seule du témoignage du client : photos avant/après et
/// commentaire libre. Accessible dès que la prestation est terminée.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../babifix_design_system.dart';
import '../../services/babifix_api.dart' show MediaApi;
import '../../shared/services/babifix_user_store.dart';
import '../../shared/widgets/babifix_ring_loader.dart';

class ClientJournalViewer extends StatefulWidget {
  final String reservationReference;
  const ClientJournalViewer({super.key, required this.reservationReference});

  @override
  State<ClientJournalViewer> createState() => _ClientJournalViewerState();
}

class _ClientJournalViewerState extends State<ClientJournalViewer> {
  bool _loading = true;
  String? _error;
  List<String> _photosAvant = [];
  List<String> _photosApres = [];
  String _note = '';
  DateTime? _updatedAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await BabifixUserStore.authGet(
        '/api/client/reservations/${widget.reservationReference}/journal',
      );
      if (r.statusCode >= 400) {
        _error = 'HTTP ${r.statusCode}';
      } else {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        _photosAvant = (j['client_photos_avant'] as List? ?? [])
            .map((e) => e.toString())
            .toList();
        _photosApres = (j['client_photos_apres'] as List? ?? [])
            .map((e) => e.toString())
            .toList();
        _note = (j['client_journal_note'] ?? '').toString();
        final ts = j['client_journal_updated_at']?.toString();
        _updatedAt = ts != null && ts.isNotEmpty
            ? DateTime.tryParse(ts)
            : null;
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Témoignage du client'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: _loading
          ? const Center(child: BabifixRingLoader.dark(size: 80))
          : _error != null
              ? Center(child: Text(_error!))
              : _empty
                  ? _emptyView()
                  : _body(),
    );
  }

  bool get _empty =>
      _photosAvant.isEmpty && _photosApres.isEmpty && _note.trim().isEmpty;

  Widget _emptyView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.book_outlined, size: 60, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              "Le client n'a pas encore écrit de témoignage pour cette intervention.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Actualiser'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    final f = DateFormat('dd/MM/yyyy HH:mm');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: BabifixDesign.ciGreen.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: BabifixDesign.ciGreen.withValues(alpha: 0.30)),
            ),
            child: Row(
              children: [
                Icon(Icons.person_pin, color: BabifixDesign.ciGreen),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Le témoignage du client',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: BabifixDesign.ciGreen),
                      ),
                      if (_updatedAt != null)
                        Text(
                          'Mis à jour : ${f.format(_updatedAt!.toLocal())}',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade700),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (_photosAvant.isNotEmpty)
            _photoStrip('Photos avant (client)', _photosAvant),
          if (_photosApres.isNotEmpty)
            _photoStrip('Photos après (client)', _photosApres),
          if (_note.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Commentaire du client',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade700)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Text(
                _note,
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
            ),
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _photoStrip(String title, List<String> urls) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700)),
          const SizedBox(height: 6),
          SizedBox(
            height: 110,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: urls.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final u = urls[i];
                final full = u.startsWith('http') ? u : MediaApi.absolute(u);
                return ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    full,
                    width: 110,
                    height: 110,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 110,
                      height: 110,
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
