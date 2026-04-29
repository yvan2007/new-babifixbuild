import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../shared/auth_utils.dart';
import '../../shared/app_palette_mode.dart';

// ─── Constantes ───────────────────────────────────────────────────────────────

const _kMaxImgBytes = 3 * 1024 * 1024; // 3 MB
const _kSteps = ['Pièce d\'identité', 'Recto CNI', 'Verso CNI', 'Selfie'];

// ─── KYCScreen ────────────────────────────────────────────────────────────────

class KYCScreen extends StatefulWidget {
  const KYCScreen({
    super.key,
    required this.onBack,
    required this.paletteMode,
  });

  final VoidCallback onBack;
  final AppPaletteMode paletteMode;

  @override
  State<KYCScreen> createState() => _KYCScreenState();
}

class _KYCScreenState extends State<KYCScreen> {
  int _step = 0; // 0=infos CNI, 1=recto, 2=verso, 3=selfie, 4=récap, 5=done

  // Étape 0
  final _cniCtrl    = TextEditingController();
  final _expiryCtrl = TextEditingController();
  DateTime? _expiryDate;
  String? _cniError;
  String? _expiryError;

  // Étapes 1-3 : photos
  Uint8List? _rectoBytes;
  Uint8List? _versoBytes;
  Uint8List? _selfieBytes;

  bool _loading = false;
  String? _statusKyc; // statut retourné par le serveur
  String? _rejectReason;

  // Statut actuel (chargé au démarrage)
  bool _loadingStatus = true;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _cniCtrl.dispose();
    _expiryCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    setState(() => _loadingStatus = true);
    try {
      final t = await readStoredApiToken();
      if (t == null) return;
      final res = await http.get(
        Uri.parse('${babifixApiBaseUrl()}/api/prestataire/kyc/status/'),
        headers: {'Authorization': 'Bearer $t'},
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _statusKyc   = d['status'] as String?;
          _rejectReason = d['rejection_reason'] as String?;
        });
      }
    } catch (_) {}
    setState(() => _loadingStatus = false);
  }

  Future<void> _pickImage(ImageSource source, void Function(Uint8List) onPick) async {
    final picker = ImagePicker();
    final xf = await picker.pickImage(
      source: source,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 85,
    );
    if (xf == null) return;
    final bytes = await xf.readAsBytes();
    if (bytes.length > _kMaxImgBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Image trop lourde (max 3 MB). Réduisez la résolution.'),
          backgroundColor: Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }
    onPick(bytes);
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      final t = await readStoredApiToken();
      if (t == null) throw Exception('Non authentifié');

      String toB64(Uint8List b) => 'data:image/jpeg;base64,${base64Encode(b)}';

      final body = jsonEncode({
        'cni_number':    _cniCtrl.text.trim(),
        'cni_expiry':    _expiryDate != null
            ? '${_expiryDate!.year}-${_expiryDate!.month.toString().padLeft(2,'0')}-${_expiryDate!.day.toString().padLeft(2,'0')}'
            : '',
        'cni_recto_b64': toB64(_rectoBytes!),
        'cni_verso_b64': toB64(_versoBytes!),
        'selfie_b64':    toB64(_selfieBytes!),
      });

      final res = await http.post(
        Uri.parse('${babifixApiBaseUrl()}/api/prestataire/kyc/submit/'),
        headers: {
          'Authorization': 'Bearer $t',
          'Content-Type': 'application/json',
        },
        body: body,
      ).timeout(const Duration(seconds: 30));

      if (res.statusCode == 200 || res.statusCode == 201) {
        setState(() {
          _statusKyc = 'pending';
          _step = 5;
        });
      } else {
        final err = jsonDecode(res.body);
        final fields = err['fields'] as Map? ?? {};
        final msg = fields.values.isNotEmpty
            ? fields.values.first.toString()
            : (err['message'] ?? 'Erreur serveur (${res.statusCode})');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(msg),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur réseau : $e'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
    setState(() => _loading = false);
  }

  bool get _isLight => widget.paletteMode == AppPaletteMode.light;

  Color get _bg     => _isLight ? const Color(0xFFF6F8FC) : const Color(0xFF0B1B34);
  Color get _card   => _isLight ? Colors.white : const Color(0xFF1A2744);
  Color get _text   => _isLight ? const Color(0xFF0F172A) : Colors.white;
  Color get _muted  => _isLight ? const Color(0xFF64748B) : const Color(0xFFB4C2D9);
  Color get _border => _isLight ? const Color(0xFFE2E8F0) : Colors.white.withValues(alpha: 0.08);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1B34),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: widget.onBack,
        ),
        title: const Text('Vérification KYC',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
      ),
      body: _loadingStatus
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF4CC9F0)))
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    // Si KYC approuvé
    if (_statusKyc == 'approved') return _buildApproved();
    // Si en attente ou en examen
    if (_statusKyc == 'pending' || _statusKyc == 'under_review') return _buildPending();
    // Si done (vient de soumettre)
    if (_step == 5) return _buildDone();

    return Column(
      children: [
        _buildStepper(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: _buildStepContent(),
          ),
        ),
      ],
    );
  }

  Widget _buildStepper() {
    final activeStep = _step.clamp(0, _kSteps.length - 1);
    return Container(
      color: const Color(0xFF0B1B34),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: List.generate(_kSteps.length, (i) {
          final done = i < activeStep;
          final active = i == activeStep;
          return Expanded(
            child: Row(
              children: [
                Column(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: done
                            ? const Color(0xFF22C55E)
                            : active
                                ? const Color(0xFF4CC9F0)
                                : Colors.white.withValues(alpha: 0.15),
                      ),
                      child: Center(
                        child: done
                            ? const Icon(Icons.check, size: 14, color: Colors.white)
                            : Text('${i + 1}',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: active ? Colors.white : Colors.white54)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _kSteps[i],
                      style: TextStyle(
                          fontSize: 9,
                          color: active ? Colors.white : Colors.white38,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w400),
                    ),
                  ],
                ),
                if (i < _kSteps.length - 1)
                  Expanded(
                    child: Container(
                      height: 2,
                      color: done
                          ? const Color(0xFF22C55E)
                          : Colors.white.withValues(alpha: 0.15),
                      margin: const EdgeInsets.only(bottom: 16),
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case 0: return _buildStep0();
      case 1: return _buildPhotoStep(
        label: 'CNI Recto',
        hint: 'Prenez en photo le RECTO de votre Carte Nationale d\'Identité. Assurez-vous que toutes les informations sont lisibles.',
        icon: Icons.badge_rounded,
        bytes: _rectoBytes,
        onPick: (b) => setState(() => _rectoBytes = b),
      );
      case 2: return _buildPhotoStep(
        label: 'CNI Verso',
        hint: 'Prenez en photo le VERSO de votre CNI. La photo doit être nette et non coupée.',
        icon: Icons.flip_rounded,
        bytes: _versoBytes,
        onPick: (b) => setState(() => _versoBytes = b),
      );
      case 3: return _buildPhotoStep(
        label: 'Selfie tenant votre CNI',
        hint: 'Prenez un selfie en tenant votre CNI recto visible à côté de votre visage. Cette étape prouve que vous êtes bien le titulaire.',
        icon: Icons.face_rounded,
        bytes: _selfieBytes,
        onPick: (b) => setState(() => _selfieBytes = b),
        isSelfie: true,
      );
      case 4: return _buildRecap();
      default: return const SizedBox.shrink();
    }
  }

  // ── Étape 0 : Infos CNI ────────────────────────────────────────────────────

  Widget _buildStep0() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SecurityBanner(isLight: _isLight),
        const SizedBox(height: 24),
        _sectionTitle('Informations de la CNI'),
        const SizedBox(height: 12),
        _PremiumField(
          label: 'Numéro de la CNI',
          controller: _cniCtrl,
          hint: 'Ex : CI 0123456789',
          error: _cniError,
          icon: Icons.numbers_rounded,
          isLight: _isLight,
          card: _card,
          text: _text,
          muted: _muted,
          border: _border,
        ),
        const SizedBox(height: 16),
        _DateField(
          label: 'Date d\'expiration',
          value: _expiryDate,
          error: _expiryError,
          isLight: _isLight,
          card: _card,
          text: _text,
          muted: _muted,
          border: _border,
          onPick: (d) => setState(() {
            _expiryDate = d;
            _expiryCtrl.text =
                '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';
            _expiryError = null;
          }),
        ),
        const SizedBox(height: 32),
        _nextButton(
          label: 'Suivant — Photo recto',
          icon: Icons.arrow_forward_rounded,
          enabled: true,
          onTap: () {
            bool ok = true;
            if (_cniCtrl.text.trim().length < 5) {
              setState(() => _cniError = 'Numéro trop court (min 5 caractères)');
              ok = false;
            } else {
              setState(() => _cniError = null);
            }
            if (_expiryDate == null) {
              setState(() => _expiryError = 'Date d\'expiration requise');
              ok = false;
            } else if (_expiryDate!.isBefore(DateTime.now())) {
              setState(() => _expiryError = 'Cette CNI est expirée');
              ok = false;
            } else {
              setState(() => _expiryError = null);
            }
            if (ok) setState(() => _step = 1);
          },
        ),
      ],
    );
  }

  // ── Étape photo (1, 2, 3) ──────────────────────────────────────────────────

  Widget _buildPhotoStep({
    required String label,
    required String hint,
    required IconData icon,
    required Uint8List? bytes,
    required void Function(Uint8List) onPick,
    bool isSelfie = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(label),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF4CC9F0).withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF4CC9F0).withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFF4CC9F0), size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(hint,
                    style: TextStyle(fontSize: 12, color: _muted, height: 1.4)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (bytes != null)
          GestureDetector(
            onTap: () => _showPickOptions(isSelfie, onPick),
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.memory(bytes,
                      width: double.infinity,
                      height: 240,
                      fit: BoxFit.cover),
                ),
                Container(
                  margin: const EdgeInsets.all(8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit_rounded, size: 12, color: Colors.white),
                      SizedBox(width: 4),
                      Text('Modifier', style: TextStyle(color: Colors.white, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          GestureDetector(
            onTap: () => _showPickOptions(isSelfie, onPick),
            child: Container(
              width: double.infinity,
              height: 200,
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: const Color(0xFF4CC9F0).withValues(alpha: 0.3),
                    width: 2,
                    style: BorderStyle.solid),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(isSelfie ? Icons.camera_front_rounded : Icons.add_a_photo_rounded,
                      size: 40, color: const Color(0xFF4CC9F0).withValues(alpha: 0.6)),
                  const SizedBox(height: 12),
                  Text(
                    isSelfie ? 'Prendre un selfie' : 'Prendre une photo',
                    style: const TextStyle(
                        color: Color(0xFF4CC9F0), fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text('Appuyez pour ouvrir l\'appareil photo',
                      style: TextStyle(fontSize: 11, color: _muted)),
                ],
              ),
            ),
          ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _step--),
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text('Retour'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _muted,
                  side: BorderSide(color: _border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: _nextButton(
                label: _step == 3 ? 'Récapitulatif' : 'Suivant',
                icon: Icons.arrow_forward_rounded,
                enabled: bytes != null,
                onTap: bytes != null ? () => setState(() => _step++) : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showPickOptions(bool selfieOnly, void Function(Uint8List) onPick) {
    if (selfieOnly) {
      _pickImage(ImageSource.camera, (b) => setState(() => onPick(b)));
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text('Prendre une photo'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera, (b) => setState(() => onPick(b)));
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choisir depuis la galerie'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery, (b) => setState(() => onPick(b)));
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Récapitulatif ──────────────────────────────────────────────────────────

  Widget _buildRecap() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Récapitulatif du dossier'),
        const SizedBox(height: 4),
        Text('Vérifiez vos informations avant de soumettre.',
            style: TextStyle(fontSize: 13, color: _muted)),
        const SizedBox(height: 20),
        _infoRow('Numéro CNI', _cniCtrl.text.trim()),
        _infoRow(
          'Expiration CNI',
          _expiryDate != null
              ? '${_expiryDate!.day.toString().padLeft(2,'0')}/${_expiryDate!.month.toString().padLeft(2,'0')}/${_expiryDate!.year}'
              : '—',
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _thumbCard('CNI Recto', _rectoBytes)),
            const SizedBox(width: 8),
            Expanded(child: _thumbCard('CNI Verso', _versoBytes)),
            const SizedBox(width: 8),
            Expanded(child: _thumbCard('Selfie', _selfieBytes)),
          ],
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  color: Color(0xFFF59E0B), size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'En soumettant ce dossier, vous certifiez que les documents fournis sont authentiques et vous appartiennent.',
                  style: TextStyle(fontSize: 12, color: _muted, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _loading ? null : () => setState(() => _step--),
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text('Retour'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _muted,
                  side: BorderSide(color: _border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 52,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF4CC9F0), Color(0xFF0EA5E9)]),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                          color: const Color(0xFF4CC9F0).withValues(alpha: 0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 6)),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: _loading ? null : _submit,
                      child: Center(
                        child: _loading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2.5))
                            : const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.send_rounded,
                                      color: Colors.white, size: 18),
                                  SizedBox(width: 8),
                                  Text('Soumettre mon dossier',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800)),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── États finaux ──────────────────────────────────────────────────────────

  Widget _buildDone() => _StatusCard(
        icon: Icons.hourglass_top_rounded,
        color: const Color(0xFFF59E0B),
        title: 'Dossier soumis !',
        body: 'Votre dossier KYC est en attente de vérification par notre équipe.\n'
            'Vous recevrez une notification dès que la décision sera prise (généralement sous 24–48h).',
        onBack: widget.onBack,
      );

  Widget _buildPending() => _StatusCard(
        icon: Icons.hourglass_top_rounded,
        color: const Color(0xFFF59E0B),
        title: _statusKyc == 'under_review' ? 'En cours d\'examen' : 'En attente de vérification',
        body: _statusKyc == 'under_review'
            ? 'Notre équipe examine actuellement votre dossier. Vous serez notifié très prochainement.'
            : 'Votre dossier a bien été reçu. Nous le vérifierons dans les 24–48h.',
        onBack: widget.onBack,
      );

  Widget _buildApproved() => _StatusCard(
        icon: Icons.verified_rounded,
        color: const Color(0xFF22C55E),
        title: 'Identité vérifiée ✓',
        body: 'Votre dossier KYC a été approuvé. Votre profil est maintenant entièrement actif.',
        onBack: widget.onBack,
      );

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _sectionTitle(String t) => Text(t,
      style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: _text));

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Text('$label : ',
                style: TextStyle(fontSize: 13, color: _muted, fontWeight: FontWeight.w600)),
            Text(value,
                style: TextStyle(fontSize: 13, color: _text, fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Widget _thumbCard(String label, Uint8List? bytes) => Container(
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _border),
        ),
        child: Column(
          children: [
            if (bytes != null)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                child: Image.memory(bytes,
                    height: 80, width: double.infinity, fit: BoxFit.cover),
              )
            else
              Container(
                height: 80,
                decoration: BoxDecoration(
                  color: _muted.withValues(alpha: 0.1),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                ),
                child: const Center(child: Icon(Icons.image_outlined, color: Colors.grey)),
              ),
            Padding(
              padding: const EdgeInsets.all(6),
              child: Text(label,
                  style: TextStyle(fontSize: 10, color: _muted, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center),
            ),
          ],
        ),
      );

  Widget _nextButton({
    required String label,
    required IconData icon,
    required bool enabled,
    VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 52,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: enabled
              ? const LinearGradient(
                  colors: [Color(0xFF4CC9F0), Color(0xFF0EA5E9)])
              : LinearGradient(
                  colors: [_muted.withValues(alpha: 0.3), _muted.withValues(alpha: 0.2)]),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: enabled ? onTap : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label,
                    style: TextStyle(
                        color: enabled ? Colors.white : _muted,
                        fontSize: 14,
                        fontWeight: FontWeight.w800)),
                const SizedBox(width: 6),
                Icon(icon, size: 16, color: enabled ? Colors.white : _muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Banner sécurité ──────────────────────────────────────────────────────────

class _SecurityBanner extends StatelessWidget {
  const _SecurityBanner({required this.isLight});
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF4CC9F0).withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF4CC9F0).withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.shield_rounded, color: Color(0xFF4CC9F0), size: 20),
              SizedBox(width: 8),
              Text('Vérification sécurisée de votre identité',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: Color(0xFF4CC9F0))),
            ],
          ),
          const SizedBox(height: 10),
          for (final item in [
            '3 documents requis : CNI recto, verso et selfie tenant votre CNI',
            'Vos documents sont chiffrés et jamais accessibles publiquement',
            'Vérification manuelle par notre équipe sous 24–48h',
            'En cas de refus, vous pouvez soumettre à nouveau',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 3),
                    child: Icon(Icons.check_circle_rounded,
                        size: 13, color: Color(0xFF22C55E)),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(item,
                        style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                            height: 1.4)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Status Card ──────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    required this.onBack,
  });
  final IconData icon;
  final Color color;
  final String title, body;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
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
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 40),
            ),
            const SizedBox(height: 24),
            Text(title,
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800, color: color),
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(body,
                style: const TextStyle(
                    fontSize: 14, color: Color(0xFF64748B), height: 1.5),
                textAlign: TextAlign.center),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Retour au profil'),
              style: FilledButton.styleFrom(backgroundColor: color),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── PremiumField ─────────────────────────────────────────────────────────────

class _PremiumField extends StatelessWidget {
  const _PremiumField({
    required this.label,
    required this.controller,
    required this.hint,
    required this.icon,
    required this.isLight,
    required this.card,
    required this.text,
    required this.muted,
    required this.border,
    this.error,
  });
  final String label, hint;
  final TextEditingController controller;
  final IconData icon;
  final bool isLight;
  final Color card, text, muted, border;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: muted)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          style: TextStyle(color: text, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: muted.withValues(alpha: 0.6)),
            prefixIcon: Icon(icon, color: const Color(0xFF4CC9F0), size: 20),
            filled: true,
            fillColor: card,
            errorText: error,
            errorStyle: const TextStyle(color: Color(0xFFFF8A80), fontSize: 11),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFF4CC9F0), width: 2)),
          ),
        ),
      ],
    );
  }
}

// ─── DateField ────────────────────────────────────────────────────────────────

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onPick,
    required this.isLight,
    required this.card,
    required this.text,
    required this.muted,
    required this.border,
    this.error,
  });
  final String label;
  final DateTime? value;
  final void Function(DateTime) onPick;
  final bool isLight;
  final Color card, text, muted, border;
  final String? error;

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: muted)),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: value ?? DateTime.now().add(const Duration(days: 365)),
              firstDate: DateTime.now(),
              lastDate: DateTime(2040),
            );
            if (d != null) onPick(d);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: error != null ? const Color(0xFFFF8A80) : border),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_rounded,
                    color: Color(0xFF4CC9F0), size: 20),
                const SizedBox(width: 10),
                Text(
                  value != null ? _fmt(value!) : 'Sélectionner la date',
                  style: TextStyle(
                      color: value != null ? text : muted.withValues(alpha: 0.6),
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(error!,
                style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 11)),
          ),
      ],
    );
  }
}
