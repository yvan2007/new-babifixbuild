import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../babifix_api_config.dart';
import '../../shared/auth_utils.dart';
import '../../shared/widgets/babifix_ring_loader.dart';
import '../../shared/widgets/babifix_snackbar.dart';

/// Écran pour répondre à un litige.
/// Le presta apporte sa version + ses preuves photos.
class PrestaDisputeRespondScreen extends StatefulWidget {
  const PrestaDisputeRespondScreen({
    super.key,
    required this.disputeRef,
    required this.categorieLabel,
    required this.motif,
    required this.clientName,
    required this.reservationTitle,
    required this.priorite,
    required this.photosClientCount,
    required this.hasAlreadyResponded,
  });

  final String disputeRef;
  final String categorieLabel;
  final String motif;
  final String clientName;
  final String reservationTitle;
  final String priorite;
  final int photosClientCount;
  final bool hasAlreadyResponded;

  @override
  State<PrestaDisputeRespondScreen> createState() =>
      _PrestaDisputeRespondScreenState();
}

class _PrestaDisputeRespondScreenState
    extends State<PrestaDisputeRespondScreen> {
  static const _kNavy = Color(0xFF0B1B34);
  static const _kCyan = Color(0xFF4CC9F0);
  static const _kAmber = Color(0xFFF59E0B);
  static const _kError = Color(0xFFEF4444);
  static const _kSuccess = Color(0xFF22C55E);

  final _responseCtrl = TextEditingController();
  final List<Uint8List> _photos = [];
  bool _submitting = false;
  final _picker = ImagePicker();

  @override
  void dispose() {
    _responseCtrl.dispose();
    super.dispose();
  }

  Color get _priorityColor {
    switch (widget.priorite) {
      case 'Haute':
        return _kError;
      case 'Basse':
        return _kSuccess;
      default:
        return _kAmber;
    }
  }

  void _showSnack(String msg, {Color color = _kCyan}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    showBabifixToast(
        context,
        type: BabifixToastType.info,
        message: msg,
      );
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

  Future<void> _submit() async {
    final text = _responseCtrl.text.trim();
    if (text.length < 20 && _photos.isEmpty) {
      _showSnack('Décrivez votre version (au moins 20 caractères) ou ajoutez une photo.',
          color: _kAmber);
      return;
    }
    setState(() => _submitting = true);
    try {
      final token = await readStoredApiToken();
      final photos = _photos
          .map((b) => 'data:image/jpeg;base64,${base64Encode(b)}')
          .toList();
      final res = await http.post(
        Uri.parse(
            '${babifixApiBaseUrl()}/api/prestataire/disputes/${widget.disputeRef}/respond/'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'response': text, 'photos': photos}),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        _showSnack('Votre version a été envoyée à BABIFIX.',
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
                      _buildDisputeCard(),
                      const SizedBox(height: 20),
                      _buildClientMotifCard(),
                      const SizedBox(height: 22),
                      _sectionTitle('Votre version des faits'),
                      const SizedBox(height: 8),
                      _hint(
                          'Soyez factuel et professionnel. Joignez des photos de votre intervention si possible (avant/après, devis signé, etc.). L\'admin trancher au mieux avec vos éléments.'),
                      const SizedBox(height: 12),
                      _buildResponseField(),
                      const SizedBox(height: 22),
                      _sectionTitle('Photos preuves (optionnel · max 5)'),
                      const SizedBox(height: 10),
                      _buildPhotosRow(),
                      const SizedBox(height: 28),
                      _buildSubmitButton(),
                      const SizedBox(height: 14),
                      const Center(
                        child: Text(
                          'En répondant, vous aidez l\'équipe BABIFIX\nà trancher équitablement en 48 h.',
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
            'Répondre au litige',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: _priorityColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            widget.priorite,
            style: TextStyle(
              color: _priorityColor,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisputeCard() {
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _kError.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.gavel_rounded,
                        color: _kError, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.categorieLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Litige ${widget.disputeRef}',
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
              if (widget.reservationTitle.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.assignment_rounded,
                        color: Colors.white.withValues(alpha: 0.55), size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.reservationTitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 12.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.person_rounded,
                      color: Colors.white.withValues(alpha: 0.55), size: 14),
                  const SizedBox(width: 6),
                  Text(
                    'Client : ${widget.clientName}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClientMotifCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.format_quote_rounded,
                  color: _kCyan, size: 16),
              const SizedBox(width: 6),
              Text(
                'Version du client',
                style: TextStyle(
                  color: _kCyan,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              if (widget.photosClientCount > 0) ...[
                const Icon(Icons.image_rounded, color: _kAmber, size: 13),
                const SizedBox(width: 4),
                Text(
                  '${widget.photosClientCount} photo${widget.photosClientCount > 1 ? "s" : ""}',
                  style: TextStyle(
                    color: _kAmber,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(
            widget.motif,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13.5,
              height: 1.55,
            ),
          ),
        ],
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

  Widget _hint(String text) => Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.55),
          fontSize: 12,
          height: 1.5,
        ),
      );

  Widget _buildResponseField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: TextField(
        controller: _responseCtrl,
        maxLines: 6,
        maxLength: 2000,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText:
              'Exemple : « L\'intervention a bien eu lieu le 14 mai. Le client a signé le devis avant. Voici les photos avant/après. »',
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
    final enabled =
        (_responseCtrl.text.trim().length >= 20 || _photos.isNotEmpty) &&
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
              colors: [_kCyan, Color(0xFF22A6D6)],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: _kCyan.withValues(alpha: 0.45),
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
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.send_rounded,
                          color: Color(0xFF0B1B34), size: 19),
                      const SizedBox(width: 10),
                      Text(
                        widget.hasAlreadyResponded
                            ? 'Mettre à jour ma réponse'
                            : 'Envoyer ma version',
                        style: const TextStyle(
                          color: Color(0xFF0B1B34),
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
