import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../user_store.dart';

/// Écran de notation du prestataire après prestation terminée.
/// Appelé via : Navigator.push(context, MaterialPageRoute(
///   builder: (_) => RateProviderScreen(bookingId: 42, prestataireName: 'Jean')))
class RateProviderScreen extends StatefulWidget {
  final int bookingId;
  final String prestataireName;
  final String? apiBase;
  final String? authToken;

  const RateProviderScreen({
    super.key,
    required this.bookingId,
    this.prestataireName = 'le prestataire',
    this.apiBase,
    this.authToken,
  });

  @override
  State<RateProviderScreen> createState() => _RateProviderScreenState();
}

class _RateProviderScreenState extends State<RateProviderScreen> {
  int _note = 0;
  final _commentCtrl = TextEditingController();
  bool _submitting = false;
  bool _submitted = false;
  final List<File> _photos = [];
  final _picker = ImagePicker();

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    if (_photos.length >= 3) return;
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 60,
      maxWidth: 1200,
    );
    if (picked == null) return;
    setState(() => _photos.add(File(picked.path)));
  }

  void _removePhoto(int index) => setState(() => _photos.removeAt(index));

  Future<String?> _token() async {
    if (widget.authToken != null && widget.authToken!.isNotEmpty) {
      return widget.authToken;
    }
    return BabifixUserStore.getApiToken();
  }

  String get _base => widget.apiBase ?? babifixApiBaseUrl();

  Future<void> _submit() async {
    if (_note == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez sélectionner une note.')),
      );
      return;
    }
    setState(() => _submitting = true);
    final token = await _token();
    try {
      // Convert selected photos to base64 data URLs
      final photoAttachments = <String>[];
      for (final f in _photos) {
        try {
          final bytes = await f.readAsBytes();
          photoAttachments.add('data:image/jpeg;base64,${base64Encode(bytes)}');
        } catch (_) {}
      }
      final res = await http.post(
        Uri.parse('$_base/api/bookings/${widget.bookingId}/rate/'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'note': _note,
          'commentaire': _commentCtrl.text.trim(),
          if (photoAttachments.isNotEmpty) 'photo_attachments': photoAttachments,
        }),
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        setState(() {
          _submitted = true;
          _submitting = false;
        });
      } else {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
      final err = body['detail'] ?? body['error'] ?? 'Erreur ${res.statusCode}';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Impossible : $err')),
          );
        }
        setState(() => _submitting = false);
      }
    } catch (_) {
      setState(() => _submitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur réseau.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Évaluer la prestation'),
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: _submitted ? _successView() : _formView(cs),
    );
  }

  Widget _successView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: BabifixDesign.success.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded,
                  color: BabifixDesign.success, size: 44),
            ),
            const SizedBox(height: 24),
            const Text('Merci pour votre avis !',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            const Text(
              'Votre évaluation aide la communauté BABIFIX à maintenir la qualité de service.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                  backgroundColor: BabifixDesign.ciOrange),
              child: const Text('Retour'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _formView(ColorScheme cs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── En-tête ──────────────────────────────────────────────────
          Center(
            child: Column(
              children: [
                const Icon(Icons.star_rounded,
                    size: 56, color: Colors.amber),
                const SizedBox(height: 12),
                Text(
                  'Comment était ${widget.prestataireName} ?',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'Mission #${widget.bookingId}',
                  style: TextStyle(fontSize: 12, color: cs.outline),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          // ── Étoiles ───────────────────────────────────────────────────
          const Text('Note',
              style: TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 12),
          _StarSelector(
            note: _note,
            onChanged: (n) => setState(() => _note = n),
          ),
          const SizedBox(height: 8),
          if (_note > 0)
            Center(
              child: Text(
                _noteLabel(_note),
                style: TextStyle(
                    color: _noteColor(_note),
                    fontWeight: FontWeight.w700,
                    fontSize: 14),
              ),
            ),
          const SizedBox(height: 28),
          // ── Commentaire ──────────────────────────────────────────────
          const Text('Commentaire (optionnel)',
              style: TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 8),
          TextField(
            controller: _commentCtrl,
            maxLines: 4,
            maxLength: 500,
            decoration: InputDecoration(
              hintText:
                  'Partagez votre expérience avec ce prestataire…',
              border: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(BabifixDesign.radiusMD),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(BabifixDesign.radiusMD),
                borderSide: const BorderSide(
                    color: BabifixDesign.ciOrange, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // ── Photos preuve (optionnel) ─────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Photos preuve (optionnel)',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              Text('${_photos.length}/3',
                  style: TextStyle(fontSize: 12, color: cs.outline)),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 88,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                if (_photos.length < 3)
                  GestureDetector(
                    onTap: _pickPhoto,
                    child: Container(
                      width: 80,
                      height: 80,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: BabifixDesign.ciOrange.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: BabifixDesign.ciOrange.withValues(alpha: 0.4),
                          style: BorderStyle.solid,
                          width: 1.5,
                        ),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined,
                              color: BabifixDesign.ciOrange, size: 28),
                          SizedBox(height: 4),
                          Text('Ajouter',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: BabifixDesign.ciOrange,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ..._photos.asMap().entries.map((e) => Stack(
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            image: DecorationImage(
                              image: FileImage(e.value),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 3,
                          right: 11,
                          child: GestureDetector(
                            onTap: () => _removePhoto(e.key),
                            child: Container(
                              width: 20,
                              height: 20,
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close,
                                  color: Colors.white, size: 13),
                            ),
                          ),
                        ),
                      ],
                    )),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // ── Bouton ───────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: _submitting ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: BabifixDesign.ciOrange,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                        BabifixDesign.radiusMD)),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white))
                  : const Text('Envoyer mon évaluation',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  String _noteLabel(int n) {
    switch (n) {
      case 1:
        return 'Très insatisfait';
      case 2:
        return 'Insatisfait';
      case 3:
        return 'Moyen';
      case 4:
        return 'Bien';
      case 5:
        return 'Excellent !';
      default:
        return '';
    }
  }

  Color _noteColor(int n) {
    if (n <= 2) return BabifixDesign.error;
    if (n == 3) return BabifixDesign.warning;
    return BabifixDesign.success;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget sélecteur d'étoiles
// ─────────────────────────────────────────────────────────────────────────────
class _StarSelector extends StatelessWidget {
  final int note;
  final void Function(int) onChanged;

  const _StarSelector({required this.note, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        5,
        (i) => GestureDetector(
          onTap: () => onChanged(i + 1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(6),
            child: Icon(
              i < note ? Icons.star_rounded : Icons.star_border_rounded,
              color: i < note ? Colors.amber : Colors.grey,
              size: 40,
            ),
          ),
        ),
      ),
    );
  }
}
