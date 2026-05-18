/// Journal client post-intervention.
///
/// Le client peut :
/// - voir ce qui a été réalisé (lignes du devis + photos du presta),
/// - ajouter ses propres photos avant/après (facultatif),
/// - laisser un commentaire libre (facultatif).
///
/// Endpoint backend : GET/POST /api/client/reservations/<ref>/journal
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../babifix_design_system.dart';
import '../../models/babifix_models.dart';
import '../../services/babifix_api.dart';
import '../../shared/widgets/babifix_phase_widgets.dart';
import '../../user_store.dart';
import '../../shared/widgets/babifix_ring_loader.dart';

class ClientJournalScreen extends StatefulWidget {
  final String reservationReference;
  const ClientJournalScreen({super.key, required this.reservationReference});

  @override
  State<ClientJournalScreen> createState() => _ClientJournalScreenState();
}

class _ClientJournalScreenState extends State<ClientJournalScreen> {
  final _noteCtl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  List<String> _clientPhotosAvant = [];
  List<String> _clientPhotosApres = [];
  List<String> _prestaPhotosAvant = [];
  List<String> _prestaPhotosApres = [];
  Devis? _devis;
  String _statut = '';
  DateTime? _updatedAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _noteCtl.dispose();
    super.dispose();
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
        _clientPhotosAvant = (j['client_photos_avant'] as List? ?? [])
            .map((e) => e.toString())
            .toList();
        _clientPhotosApres = (j['client_photos_apres'] as List? ?? [])
            .map((e) => e.toString())
            .toList();
        _prestaPhotosAvant = (j['prestataire_photos_avant'] as List? ?? [])
            .map((e) => e.toString())
            .toList();
        _prestaPhotosApres = (j['prestataire_photos_apres'] as List? ?? [])
            .map((e) => e.toString())
            .toList();
        _noteCtl.text = (j['client_journal_note'] ?? '').toString();
        _statut = (j['statut'] ?? '').toString();
        final ts = j['client_journal_updated_at']?.toString();
        _updatedAt = ts != null && ts.isNotEmpty ? DateTime.tryParse(ts) : null;
      }
      // Charger le devis pour montrer ce qui a été fait
      try {
        _devis = await DevisApi.get(widget.reservationReference);
      } catch (_) {}
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addPhotos({required bool avant}) async {
    final picker = ImagePicker();
    final files = await picker.pickMultiImage(imageQuality: 70);
    if (files.isEmpty) return;
    // B7 — Upload chaque image et stocke les URLs canoniques.
    final urls = <String>[];
    for (final f in files) {
      try {
        final url = await MediaApi.uploadFile(f.path);
        if (url.isNotEmpty) urls.add(url);
      } catch (e) {
        _snack('Une photo n\'a pas pu être envoyée : $e');
      }
    }
    if (urls.isEmpty) return;
    setState(() {
      if (avant) {
        _clientPhotosAvant = [..._clientPhotosAvant, ...urls];
      } else {
        _clientPhotosApres = [..._clientPhotosApres, ...urls];
      }
    });
  }

  void _removePhoto(int index, {required bool avant}) {
    setState(() {
      if (avant) {
        _clientPhotosAvant = [..._clientPhotosAvant]..removeAt(index);
      } else {
        _clientPhotosApres = [..._clientPhotosApres]..removeAt(index);
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final r = await BabifixUserStore.authPost(
        '/api/client/reservations/${widget.reservationReference}/journal',
        body: jsonEncode({
          'mode': 'replace',
          'photos_avant': _clientPhotosAvant,
          'photos_apres': _clientPhotosApres,
          'note': _noteCtl.text.trim(),
        }),
      );
      if (r.statusCode >= 400) {
        _snack('Erreur ${r.statusCode}');
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: BabifixDesign.ciGreen,
        content: const Text('Journal enregistré.'),
      ));
      _updatedAt = DateTime.now();
      setState(() {});
    } catch (e) {
      _snack('Erreur : $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Mon journal'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: _loading
          ? const Center(child: BabifixRingLoader.dark(size: 80))
          : _error != null
              ? Center(child: Text(_error!))
              : _body(),
      bottomNavigationBar: _loading || _error != null ? null : _saveBar(),
    );
  }

  Widget _body() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: BabifixDesign.ciBlue.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: BabifixDesign.ciBlue.withValues(alpha: 0.20)),
          ),
          child: Row(
            children: [
              Icon(Icons.menu_book, color: BabifixDesign.ciBlue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Documentez vous-même ce qui a été fait. '
                  'Photos et commentaire sont facultatifs.',
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey.shade800),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Ce qui a été annoncé / fait (devis + photos presta)
        Text('Ce qui a été annoncé',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700)),
        const SizedBox(height: 6),
        if (_devis != null) DevisCardWidget(devis: _devis!, compact: true),
        if (_prestaPhotosAvant.isNotEmpty || _prestaPhotosApres.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_prestaPhotosAvant.isNotEmpty)
                  _photoStrip('Photos avant (prestataire)',
                      _prestaPhotosAvant, editable: false, avant: true),
                if (_prestaPhotosApres.isNotEmpty)
                  _photoStrip('Photos après (prestataire)',
                      _prestaPhotosApres, editable: false, avant: false),
              ],
            ),
          ),
        const SizedBox(height: 22),
        // Section client
        Row(
          children: [
            Icon(Icons.person_pin, color: BabifixDesign.ciGreen),
            const SizedBox(width: 6),
            Text('Mon témoignage',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: BabifixDesign.ciGreen)),
            if (_updatedAt != null) ...[
              const SizedBox(width: 6),
              Text('· dernière maj : ${_updatedAt!.toLocal()}',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade600)),
            ],
          ],
        ),
        const SizedBox(height: 10),
        _photoStrip(
          'Mes photos avant (facultatif)',
          _clientPhotosAvant,
          editable: true,
          avant: true,
        ),
        _photoStrip(
          'Mes photos après (facultatif)',
          _clientPhotosApres,
          editable: true,
          avant: false,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _noteCtl,
          maxLines: 6,
          maxLength: 5000,
          decoration: InputDecoration(
            labelText: 'Mon commentaire (facultatif)',
            hintText:
                'Décrivez votre ressenti, la qualité du travail, des détails à retenir…',
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10)),
            filled: true,
            fillColor: Colors.white,
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _photoStrip(
    String title,
    List<String> urls, {
    required bool editable,
    required bool avant,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade700)),
              ),
              if (editable)
                TextButton.icon(
                  onPressed: () => _addPhotos(avant: avant),
                  icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                  label: const Text('Ajouter'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 96,
            child: urls.isEmpty
                ? Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      editable ? 'Aucune photo. Tapez "Ajouter".' : 'Aucune photo.',
                      style: TextStyle(
                          color: Colors.grey.shade500, fontSize: 12),
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: urls.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => _thumb(urls[i],
                        onRemove: editable ? () => _removePhoto(i, avant: avant) : null),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _thumb(String u, {VoidCallback? onRemove}) {
    Widget img;
    if (u.startsWith('data:image')) {
      try {
        final b = base64Decode(u.substring(u.indexOf(',') + 1));
        img = Image.memory(Uint8List.fromList(b),
            width: 96, height: 96, fit: BoxFit.cover);
      } catch (_) {
        img = _broken();
      }
    } else {
      // URL relative (`/media/...`) ou absolue (`http(s)://...`)
      final full = MediaApi.absolute(u);
      img = Image.network(full,
          width: 96,
          height: 96,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _broken());
    }
    return Stack(
      children: [
        ClipRRect(borderRadius: BorderRadius.circular(8), child: img),
        if (onRemove != null)
          Positioned(
            top: 2,
            right: 2,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onRemove,
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _broken() => Container(
        width: 96,
        height: 96,
        color: Colors.grey.shade300,
        child: const Icon(Icons.broken_image_outlined),
      );

  Widget _saveBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save),
            label: const Text('Enregistrer mon journal'),
            style: ElevatedButton.styleFrom(
              backgroundColor: BabifixDesign.ciBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
          ),
        ),
      ),
    );
  }
}
