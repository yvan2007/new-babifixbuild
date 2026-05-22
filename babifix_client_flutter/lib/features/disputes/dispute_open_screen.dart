import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../user_store.dart';
import '../../shared/widgets/babifix_ring_loader.dart';
import '../../shared/widgets/babifix_snackbar.dart';

/// Catégories de litige proposées au client.
/// Doivent rester alignées avec `Dispute.Category` côté backend.
const _kCategories = [
  _Cat('travail_non_fait', 'Travail non réalisé', Icons.cancel_outlined,
      Color(0xFFEF4444)),
  _Cat('travail_bacle', 'Travail bâclé / mal fait', Icons.build_outlined,
      Color(0xFFF59E0B)),
  _Cat('presta_absent', 'Prestataire absent', Icons.person_off_outlined,
      Color(0xFFEF4444)),
  _Cat('retard', 'Retard important', Icons.schedule_outlined,
      Color(0xFFF59E0B)),
  _Cat('prix_non_conforme', 'Prix non conforme', Icons.payments_outlined,
      Color(0xFFF59E0B)),
  _Cat('degats', 'Dégâts causés', Icons.warning_amber_outlined,
      Color(0xFFEF4444)),
  _Cat('comportement', 'Comportement inapproprié',
      Icons.sentiment_dissatisfied_outlined, Color(0xFFEF4444)),
  _Cat('autre', 'Autre raison', Icons.more_horiz_rounded, Color(0xFF64748B)),
];

class _Cat {
  final String id;
  final String label;
  final IconData icon;
  final Color color;
  const _Cat(this.id, this.label, this.icon, this.color);
}

/// Écran plein-écran pour ouvrir un litige.
/// Plus pro qu'un AlertDialog — l'utilisateur a besoin d'espace
/// pour catégoriser, décrire et joindre des photos.
class DisputeOpenScreen extends StatefulWidget {
  const DisputeOpenScreen({
    super.key,
    required this.reservationReference,
    required this.reservationTitle,
  });

  final String reservationReference;
  final String reservationTitle;

  @override
  State<DisputeOpenScreen> createState() => _DisputeOpenScreenState();
}

class _DisputeOpenScreenState extends State<DisputeOpenScreen> {
  String? _categoryId;
  String _priority = 'Moyenne';
  final _motifCtrl = TextEditingController();
  final List<Uint8List> _photos = [];
  bool _submitting = false;

  static const _kNavy = Color(0xFF0B1B34);
  static const _kCyan = Color(0xFF4CC9F0);
  static const _kAmber = Color(0xFFF59E0B);
  static const _kError = Color(0xFFEF4444);
  static const _kSuccess = Color(0xFF22C55E);

  final _picker = ImagePicker();

  @override
  void dispose() {
    _motifCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    if (_photos.length >= 5) {
      _showSnack('Maximum 5 photos.', color: _kAmber);
      return;
    }
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: _kNavy,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Ajouter une photo preuve',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _sheetRow(ctx, Icons.photo_library_rounded, 'Galerie',
                  ImageSource.gallery),
              const SizedBox(height: 8),
              _sheetRow(ctx, Icons.photo_camera_rounded, 'Appareil photo',
                  ImageSource.camera),
            ],
          ),
        ),
      ),
    );
    if (src == null) return;
    try {
      final x = await _picker.pickImage(
        source: src,
        maxWidth: 1024,
        imageQuality: 78,
      );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      if (bytes.lengthInBytes > 2 * 1024 * 1024) {
        if (!mounted) return;
        _showSnack('Photo trop lourde (2 Mo max).', color: _kError);
        return;
      }
      if (!mounted) return;
      setState(() => _photos.add(bytes));
    } catch (_) {
      if (!mounted) return;
      _showSnack('Impossible de charger la photo.', color: _kError);
    }
  }

  Widget _sheetRow(
      BuildContext ctx, IconData icon, String label, ImageSource src) {
    return Material(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => Navigator.pop(ctx, src),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: _kCyan, size: 20),
              const SizedBox(width: 14),
              Text(label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  void _showSnack(String msg, {Color color = _kCyan}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    showBabifixToast(
        context,
        type: BabifixToastType.info,
        message: msg,
      );
  }

  Future<void> _submit() async {
    if (_categoryId == null) {
      _showSnack('Choisissez d\'abord une catégorie.', color: _kAmber);
      return;
    }
    final motif = _motifCtrl.text.trim();
    if (motif.length < 20) {
      _showSnack('Décrivez le problème (au moins 20 caractères).',
          color: _kAmber);
      return;
    }
    setState(() => _submitting = true);
    try {
      final token = await BabifixUserStore.getApiToken();
      final photos = _photos
          .map((b) => 'data:image/jpeg;base64,${base64Encode(b)}')
          .toList();
      final res = await http.post(
        Uri.parse(
            '${babifixApiBaseUrl()}/api/client/reservations/${widget.reservationReference}/dispute'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'motif': motif,
          'categorie': _categoryId,
          'priorite': _priority,
          'photos': photos,
        }),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        _showSnack('Litige envoyé. L\'équipe BABIFIX va trancher.',
            color: _kSuccess);
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) Navigator.of(context).pop(true);
      } else {
        String err = 'Erreur ${res.statusCode}';
        try {
          err = (jsonDecode(res.body)['error'] ?? err).toString();
        } catch (_) {}
        _showSnack(err, color: _kError);
      }
    } catch (e) {
      if (!mounted) return;
      _showSnack('Erreur réseau : $e', color: _kError);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050D1A),
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF050D1A), _kNavy, Color(0xFF060E1C)],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    children: [
                      _buildResaCard(),
                      const SizedBox(height: 22),
                      _sectionTitle('1. Catégorie du problème'),
                      const SizedBox(height: 10),
                      _buildCategoryGrid(),
                      const SizedBox(height: 22),
                      _sectionTitle('2. Niveau d\'urgence'),
                      const SizedBox(height: 10),
                      _buildPriorityRow(),
                      const SizedBox(height: 22),
                      _sectionTitle('3. Décrivez le problème'),
                      const SizedBox(height: 10),
                      _buildMotifField(),
                      const SizedBox(height: 22),
                      _sectionTitle(
                          '4. Photos preuves (optionnel · max 5)'),
                      const SizedBox(height: 10),
                      _buildPhotosRow(),
                      const SizedBox(height: 28),
                      _buildSubmitButton(),
                      const SizedBox(height: 14),
                      const Center(
                        child: Text(
                          'Notre équipe étudie chaque litige en 48 h.\nLes fonds restent bloqués jusqu\'à décision.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 11.5,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 16, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white70, size: 20),
          ),
          const SizedBox(width: 4),
          const Text(
            'Signaler un problème',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResaCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _kError.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _kError.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _kError.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.report_problem_rounded,
                    color: _kError, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.reservationTitle.isEmpty
                          ? 'Réservation'
                          : widget.reservationTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.reservationReference,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 11.5,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      );

  Widget _buildCategoryGrid() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _kCategories.map((cat) {
        final sel = _categoryId == cat.id;
        return GestureDetector(
          onTap: () => setState(() => _categoryId = cat.id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: sel
                  ? cat.color.withValues(alpha: 0.18)
                  : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: sel
                    ? cat.color
                    : Colors.white.withValues(alpha: 0.12),
                width: sel ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(cat.icon, color: cat.color, size: 17),
                const SizedBox(width: 8),
                Text(
                  cat.label,
                  style: TextStyle(
                    color: sel ? Colors.white : Colors.white.withValues(alpha: 0.78),
                    fontSize: 12.5,
                    fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPriorityRow() {
    const items = [
      ('Basse', Color(0xFF22C55E), Icons.low_priority_rounded),
      ('Moyenne', _kAmber, Icons.priority_high_rounded),
      ('Haute', _kError, Icons.local_fire_department_rounded),
    ];
    return Row(
      children: [
        for (final (label, color, icon) in items) ...[
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _priority = label),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _priority == label
                      ? color.withValues(alpha: 0.18)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _priority == label
                        ? color
                        : Colors.white.withValues(alpha: 0.12),
                    width: _priority == label ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(icon, color: color, size: 18),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: TextStyle(
                        color: _priority == label
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.78),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (label != 'Haute') const SizedBox(width: 8),
        ],
      ],
    );
  }

  Widget _buildMotifField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: TextField(
        controller: _motifCtrl,
        maxLines: 5,
        maxLength: 500,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText:
              'Soyez précis : dates, faits, conséquences. Plus c\'est détaillé, plus on tranche vite.',
          hintStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 13,
            height: 1.5,
          ),
          border: InputBorder.none,
          counterStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 11,
          ),
          contentPadding: const EdgeInsets.all(14),
        ),
      ),
    );
  }

  Widget _buildPhotosRow() {
    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          // Bouton "+ Photo"
          GestureDetector(
            onTap: _pickPhoto,
            child: Container(
              width: 96,
              decoration: BoxDecoration(
                color: _kCyan.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _kCyan.withValues(alpha: 0.45),
                  width: 1.5,
                ),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_a_photo_rounded, color: _kCyan, size: 26),
                  SizedBox(height: 6),
                  Text(
                    'Ajouter',
                    style: TextStyle(
                      color: _kCyan,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          for (int i = 0; i < _photos.length; i++) ...[
            const SizedBox(width: 10),
            Stack(
              clipBehavior: Clip.none,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.memory(
                    _photos[i],
                    width: 96,
                    height: 96,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  top: -6,
                  right: -6,
                  child: GestureDetector(
                    onTap: () => setState(() => _photos.removeAt(i)),
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: _kError,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: const Color(0xFF050D1A), width: 2),
                      ),
                      child: const Icon(Icons.close_rounded,
                          color: Colors.white, size: 14),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    final enabled = _categoryId != null &&
        _motifCtrl.text.trim().length >= 20 &&
        !_submitting;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: enabled ? 1.0 : 0.55,
      child: GestureDetector(
        onTap: enabled ? _submit : null,
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_kError, Color(0xFFB91C1C)],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: _kError.withValues(alpha: 0.45),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : [],
          ),
          child: Center(
            child: _submitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: BabifixRingLoader.cyan(size: 28),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.send_rounded,
                          color: Colors.white, size: 19),
                      SizedBox(width: 10),
                      Text(
                        'Envoyer le litige',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
