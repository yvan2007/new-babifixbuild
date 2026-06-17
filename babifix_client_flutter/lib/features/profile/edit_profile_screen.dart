import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../babifix_api_config.dart';
import '../../shared/widgets/smart_address_picker.dart';
import '../../user_store.dart';
import '../../shared/widgets/babifix_ring_loader.dart';

// ── Couleurs sémantiques (universelles) ───────────────────────────────────────
const _kCyan = Color(0xFF4CC9F0);
const _kCyanDark = Color(0xFF22A6D6);
const _kNavy = Color(0xFF0B1B34);
const _kSuccess = Color(0xFF22C55E);
const _kError = Color(0xFFEF4444);

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    super.key,
    required this.initialName,
    required this.initialEmail,
    required this.initialPhone,
    required this.initialAddress,
    required this.initialAvatarBytes,
    required this.onSaved,
  });

  final String initialName;
  final String initialEmail;
  final String initialPhone;
  final String initialAddress;
  final Uint8List? initialAvatarBytes;
  final VoidCallback onSaved;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen>
    with SingleTickerProviderStateMixin {
  late final TextEditingController nameCtrl;
  late final TextEditingController emailCtrl;
  late final TextEditingController phoneCtrl;
  late final TextEditingController addressCtrl;
  Uint8List? _avatarBytes;
  bool _avatarChanged = false;

  final _picker = ImagePicker();

  late final AnimationController _anim;
  late final Animation<double> _fadeIn;

  String? _nameError;
  String? _emailError;
  String? _phoneError;
  String? _addressError;

  bool _saving = false;

  // Coordonnées de l'adresse (alimentent le repli de proximité prestataires).
  double? _addrLat;
  double? _addrLng;

  @override
  void initState() {
    super.initState();
    nameCtrl = TextEditingController(text: widget.initialName);
    emailCtrl = TextEditingController(text: widget.initialEmail);
    phoneCtrl = TextEditingController(text: widget.initialPhone);
    addressCtrl = TextEditingController(text: widget.initialAddress);
    _avatarBytes = widget.initialAvatarBytes;

    // Recharge les coordonnées déjà enregistrées (pour rouvrir la carte au
    // bon endroit).
    BabifixUserStore.loadAddressCoords().then((c) {
      if (c != null && mounted) {
        setState(() {
          _addrLat = c.lat;
          _addrLng = c.lng;
        });
      }
    });

    nameCtrl.addListener(_onFieldChange);
    emailCtrl.addListener(_onFieldChange);
    phoneCtrl.addListener(_onFieldChange);
    addressCtrl.addListener(_onFieldChange);

    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeIn = CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic);
    _anim.forward();
  }

  void _onFieldChange() {
    if (_nameError != null && _validName(nameCtrl.text.trim()) == null) {
      setState(() => _nameError = null);
    } else if (_emailError != null &&
        _validEmail(emailCtrl.text.trim()) == null) {
      setState(() => _emailError = null);
    } else if (_phoneError != null &&
        _validPhone(phoneCtrl.text.trim()) == null) {
      setState(() => _phoneError = null);
    } else if (_addressError != null &&
        _validAddress(addressCtrl.text.trim()) == null) {
      setState(() => _addressError = null);
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    emailCtrl.dispose();
    phoneCtrl.dispose();
    addressCtrl.dispose();
    _anim.dispose();
    super.dispose();
  }

  // ── Validation ──────────────────────────────────────────────────────────────
  String? _validName(String v) {
    if (v.isEmpty) return 'Le nom est requis.';
    if (v.length < 2) return 'Au moins 2 caractères.';
    if (v.length > 60) return 'Maximum 60 caractères.';
    return null;
  }

  String? _validEmail(String v) {
    if (v.isEmpty) return null;
    final re = RegExp(r'^[\w.\-+]+@[\w\-]+\.[\w.\-]+$');
    if (!re.hasMatch(v)) return 'Email invalide.';
    return null;
  }

  String? _validPhone(String v) {
    if (v.isEmpty) return 'Le téléphone est requis.';
    final digits = v.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    final re = RegExp(r'^(\+?225)?\d{8,10}$');
    if (!re.hasMatch(digits)) {
      return 'Numéro invalide (ex : +225 01 02 03 04 05).';
    }
    return null;
  }

  String? _validAddress(String v) {
    if (v.isEmpty) return null;
    if (v.length < 5) return 'Adresse trop courte.';
    return null;
  }

  bool get _hasChanges {
    return nameCtrl.text.trim() != widget.initialName.trim() ||
        emailCtrl.text.trim() != widget.initialEmail.trim() ||
        phoneCtrl.text.trim() != widget.initialPhone.trim() ||
        addressCtrl.text.trim() != widget.initialAddress.trim() ||
        _avatarChanged;
  }

  // ── Photo : Galerie / Caméra / Supprimer ───────────────────────────────────
  Future<void> _showPhotoSheet(_Palette p) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
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
                    color: p.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Photo de profil',
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _sheetAction(p,
                  icon: Icons.photo_library_rounded,
                  label: 'Choisir dans la galerie',
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _pickPhoto(ImageSource.gallery);
                  }),
              const SizedBox(height: 8),
              _sheetAction(p,
                  icon: Icons.photo_camera_rounded,
                  label: 'Prendre une photo',
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _pickPhoto(ImageSource.camera);
                  }),
              if (_avatarBytes != null) ...[
                const SizedBox(height: 8),
                _sheetAction(p,
                    icon: Icons.delete_outline_rounded,
                    label: 'Supprimer la photo',
                    destructive: true, onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _avatarBytes = null;
                    _avatarChanged = true;
                  });
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetAction(
    _Palette p, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    final color = destructive ? _kError : _kCyan;
    return Material(
      color: p.subtleBg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: destructive ? _kError : p.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: p.textMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final x = await _picker.pickImage(
          source: source, maxWidth: 1024, imageQuality: 85);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      if (bytes.lengthInBytes > 3 * 1024 * 1024) {
        if (!mounted) return;
        _showSnack('Photo trop lourde (3 Mo max).', error: true);
        return;
      }
      if (!mounted) return;
      setState(() {
        _avatarBytes = bytes;
        _avatarChanged = true;
      });
    } catch (_) {
      if (!mounted) return;
      _showSnack('Impossible de charger la photo.', error: true);
    }
  }

  Future<void> _uploadAvatar(Uint8List bytes) async {
    try {
      final token = await BabifixUserStore.getApiToken();
      if (token == null || token.isEmpty) return;
      final b64 = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      await http
          .post(
            Uri.parse('${babifixApiBaseUrl()}/api/auth/me'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'photo_b64': b64}),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      // Silencieux : la photo locale reste affichée même si l'upload échoue.
    }
  }

  Future<void> _save() async {
    if (_saving) return;

    final nameErr = _validName(nameCtrl.text.trim());
    final emailErr = _validEmail(emailCtrl.text.trim());
    final phoneErr = _validPhone(phoneCtrl.text.trim());
    final addrErr = _validAddress(addressCtrl.text.trim());

    if (nameErr != null ||
        emailErr != null ||
        phoneErr != null ||
        addrErr != null) {
      setState(() {
        _nameError = nameErr;
        _emailError = emailErr;
        _phoneError = phoneErr;
        _addressError = addrErr;
      });
      _showSnack('Veuillez corriger les erreurs avant d\'enregistrer.',
          error: true);
      return;
    }

    if (!_hasChanges) {
      _showSnack('Aucune modification à enregistrer.');
      return;
    }

    setState(() => _saving = true);
    try {
      await BabifixUserStore.saveProfile(
        name: nameCtrl.text.trim(),
        email: emailCtrl.text.trim(),
        phone: phoneCtrl.text.trim(),
        address: addressCtrl.text.trim(),
        addressLat: _addrLat,
        addressLng: _addrLng,
      );
      // Persistance serveur (visible après reconnexion / autre appareil).
      await BabifixUserStore.pushProfileToServer(
        name: nameCtrl.text.trim(),
        email: emailCtrl.text.trim(),
        phone: phoneCtrl.text.trim(),
      );
      if (_avatarChanged) {
        if (_avatarBytes != null) {
          await BabifixUserStore.saveAvatarBytes(_avatarBytes!);
          // Persiste aussi côté serveur (survit à la réinstallation, visible
          // ailleurs). Silencieux si échec — la photo locale reste valable.
          await _uploadAvatar(_avatarBytes!);
        } else {
          try {
            await BabifixUserStore.saveAvatarBytes(Uint8List(0));
          } catch (_) {}
        }
      }
      if (!mounted) return;
      _showSnack('Profil enregistré.', success: true);
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      widget.onSaved();
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      _showSnack('Échec de l\'enregistrement : $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack(String msg, {bool error = false, bool success = false}) {
    final color = error
        ? _kError
        : success
            ? _kSuccess
            : _kCyan;
    final icon = error
        ? Icons.error_outline_rounded
        : success
            ? Icons.check_circle_rounded
            : Icons.info_outline_rounded;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _kNavy,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: color.withValues(alpha: 0.6)),
        ),
        content: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(msg,
                  style:
                      const TextStyle(color: Colors.white, fontSize: 13.5)),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmDiscard(_Palette p) async {
    if (!_hasChanges) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Quitter sans enregistrer ?',
          style: TextStyle(
              color: p.textPrimary, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Vos modifications seront perdues.',
          style: TextStyle(color: p.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Continuer',
                style: TextStyle(color: p.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Quitter',
                style: TextStyle(
                    color: _kError, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final p = _Palette.from(isLight);

    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard(p)) {
          if (mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: p.scaffoldBg,
        body: SafeArea(
          child: FadeTransition(
            opacity: _fadeIn,
            child: Column(
              children: [
                _buildHeader(p),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
                    children: [
                      Center(child: _buildAvatar(p)),
                      const SizedBox(height: 10),
                      Center(
                        child: TextButton.icon(
                          onPressed: () => _showPhotoSheet(p),
                          icon: const Icon(Icons.camera_alt_outlined,
                              color: _kCyan, size: 18),
                          label: const Text(
                            'Modifier la photo',
                            style: TextStyle(
                              color: _kCyan,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Center(
                        child: Text(
                          'Photo, identité et coordonnées pour vos interventions.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: p.textMuted,
                              fontSize: 12.5,
                              height: 1.4),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildFormCard(p),
                      const SizedBox(height: 24),
                      _buildSaveButton(),
                      const SizedBox(height: 12),
                      Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.lock_outline_rounded,
                                size: 13, color: p.textMuted),
                            const SizedBox(width: 5),
                            Text(
                              'Vos données restent privées et chiffrées.',
                              style: TextStyle(
                                  color: p.textMuted, fontSize: 11.5),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(_Palette p) {
    final dirty = _hasChanges;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 16, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: () async {
              if (await _confirmDiscard(p)) {
                if (mounted) Navigator.of(context).maybePop();
              }
            },
            icon: Icon(Icons.arrow_back_ios_new_rounded,
                color: p.textPrimary, size: 20),
          ),
          const SizedBox(width: 4),
          Text(
            'Mon profil',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: p.textPrimary,
            ),
          ),
          const Spacer(),
          if (dirty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _kSuccess.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border:
                    Border.all(color: _kSuccess.withValues(alpha: 0.45)),
              ),
              child: Row(
                children: const [
                  CircleAvatar(radius: 3, backgroundColor: _kSuccess),
                  SizedBox(width: 6),
                  Text(
                    'Modifié',
                    style: TextStyle(
                      color: _kSuccess,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAvatar(_Palette p) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 116,
          height: 116,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [_kCyan, _kCyanDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: _kCyan.withValues(alpha: 0.45),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: CircleAvatar(
              radius: 55,
              backgroundColor: p.cardBg,
              backgroundImage: _avatarBytes != null
                  ? MemoryImage(_avatarBytes!) as ImageProvider
                  : const AssetImage('assets/images/babifix-logo.png'),
            ),
          ),
        ),
        Positioned(
          right: -2,
          bottom: 0,
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: () => _showPhotoSheet(p),
              customBorder: const CircleBorder(),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(colors: [_kCyan, _kCyanDark]),
                  boxShadow: [
                    BoxShadow(
                      color: _kCyan.withValues(alpha: 0.45),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                  border: Border.all(color: p.scaffoldBg, width: 2.5),
                ),
                child: const Icon(Icons.camera_alt_rounded,
                    color: Colors.white, size: 16),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFormCard(_Palette p) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        color: p.cardBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: p.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: p.isLight ? 0.04 : 0.18),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _kCyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.person_outline_rounded,
                    color: _kCyan, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                'Informations personnelles',
                style: TextStyle(
                  color: p.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _AdaptiveField(
            palette: p,
            controller: nameCtrl,
            label: 'Nom complet',
            icon: Icons.badge_outlined,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            errorText: _nameError,
            maxLength: 60,
            isModified: nameCtrl.text.trim() != widget.initialName.trim(),
          ),
          const SizedBox(height: 14),
          _AdaptiveField(
            palette: p,
            controller: emailCtrl,
            label: 'Email',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            errorText: _emailError,
            isModified: emailCtrl.text.trim() != widget.initialEmail.trim(),
          ),
          const SizedBox(height: 14),
          _AdaptiveField(
            palette: p,
            controller: phoneCtrl,
            label: 'Téléphone',
            icon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            errorText: _phoneError,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s\-]')),
            ],
            isModified: phoneCtrl.text.trim() != widget.initialPhone.trim(),
          ),
          const SizedBox(height: 14),
          // Adresse : carte interactive avec GPS auto, plus pro qu'un
          // simple champ texte.
          _AddressPickerField(
            palette: p,
            value: addressCtrl.text,
            isModified:
                addressCtrl.text.trim() != widget.initialAddress.trim(),
            onPick: () async {
              final picked = await Navigator.of(context).push<PickedAddress>(
                MaterialPageRoute(
                  builder: (_) => SmartAddressPicker(
                    initialLabel: addressCtrl.text.isEmpty
                        ? null
                        : addressCtrl.text,
                    initialLat: _addrLat,
                    initialLon: _addrLng,
                  ),
                ),
              );
              if (picked != null) {
                setState(() {
                  addressCtrl.text = picked.label;
                  _addrLat = picked.lat;
                  _addrLng = picked.lon;
                });
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    final enabled = _hasChanges && !_saving;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 220),
      opacity: enabled ? 1.0 : 0.55,
      child: GestureDetector(
        onTap: enabled ? _save : null,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_kCyan, _kCyanDark]),
            borderRadius: BorderRadius.circular(18),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: _kCyan.withValues(alpha: 0.45),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : [],
          ),
          child: Center(
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: BabifixRingLoader.cyan(size: 28),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _hasChanges
                            ? Icons.check_rounded
                            : Icons.lock_outline_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _hasChanges
                            ? 'Enregistrer les modifications'
                            : 'Aucune modification',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
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

// ── Palette adaptative ────────────────────────────────────────────────────────
class _Palette {
  final bool isLight;
  final Color scaffoldBg;
  final Color cardBg;
  final Color cardBorder;
  final Color subtleBg;
  final Color fieldBg;
  final Color fieldBorder;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color divider;

  const _Palette({
    required this.isLight,
    required this.scaffoldBg,
    required this.cardBg,
    required this.cardBorder,
    required this.subtleBg,
    required this.fieldBg,
    required this.fieldBorder,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.divider,
  });

  factory _Palette.from(bool isLight) {
    if (isLight) {
      return const _Palette(
        isLight: true,
        scaffoldBg: Color(0xFFF1F5F9),
        cardBg: Colors.white,
        cardBorder: Color(0xFFE2E8F0),
        subtleBg: Color(0xFFF8FAFC),
        fieldBg: Color(0xFFF8FAFC),
        fieldBorder: Color(0xFFCBD5E1),
        textPrimary: Color(0xFF0F172A),
        textSecondary: Color(0xFF475569),
        textMuted: Color(0xFF94A3B8),
        divider: Color(0xFFE2E8F0),
      );
    }
    return _Palette(
      isLight: false,
      scaffoldBg: const Color(0xFF050D1A),
      cardBg: const Color(0xFF0F1F38),
      cardBorder: Colors.white.withValues(alpha: 0.10),
      subtleBg: Colors.white.withValues(alpha: 0.06),
      fieldBg: Colors.white.withValues(alpha: 0.07),
      fieldBorder: Colors.white.withValues(alpha: 0.15),
      textPrimary: Colors.white,
      textSecondary: const Color(0xFFB4C2D9),
      textMuted: const Color(0xFF94A3B8),
      divider: Colors.white.withValues(alpha: 0.18),
    );
  }
}

// ── Bouton sélecteur d'adresse (carte + GPS) ─────────────────────────────────
class _AddressPickerField extends StatelessWidget {
  const _AddressPickerField({
    required this.palette,
    required this.value,
    required this.isModified,
    required this.onPick,
  });

  final _Palette palette;
  final String value;
  final bool isModified;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final borderColor = isModified
        ? _kSuccess.withValues(alpha: 0.55)
        : palette.fieldBorder;
    final iconColor = isModified ? _kSuccess : palette.textSecondary;
    final hasValue = value.trim().isNotEmpty;
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: palette.fieldBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Icon(Icons.location_on_outlined, color: iconColor, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Adresse exacte d\'intervention',
                    style: TextStyle(
                      color: palette.isLight ? _kNavy : _kCyan,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasValue ? value : 'Ouvrir la carte pour choisir…',
                    style: TextStyle(
                      color: hasValue
                          ? palette.textPrimary
                          : palette.textMuted,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.map_outlined, color: _kCyan, size: 22),
            if (isModified) ...[
              const SizedBox(width: 6),
              const Icon(Icons.check_circle, color: _kSuccess, size: 18),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Champ adaptatif premium ───────────────────────────────────────────────────
class _AdaptiveField extends StatelessWidget {
  const _AdaptiveField({
    required this.palette,
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.textInputAction,
    this.maxLines = 1,
    this.maxLength,
    this.inputFormatters,
    this.errorText,
    this.isModified = false,
  });

  final _Palette palette;
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final TextInputAction? textInputAction;
  final int maxLines;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final String? errorText;
  final bool isModified;

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null;

    final borderColor = hasError
        ? _kError.withValues(alpha: 0.75)
        : isModified
            ? _kSuccess.withValues(alpha: 0.55)
            : palette.fieldBorder;

    final iconColor = hasError
        ? _kError
        : isModified
            ? _kSuccess
            : palette.textSecondary;

    // Label flottant TRÈS lisible : navy en mode clair, cyan en mode sombre.
    final floatingLabelColor = hasError
        ? _kError
        : palette.isLight
            ? _kNavy
            : _kCyan;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: palette.fieldBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: hasError ? 1.5 : 1),
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            textCapitalization: textCapitalization,
            textInputAction: textInputAction,
            maxLines: maxLines,
            maxLength: maxLength,
            inputFormatters: inputFormatters,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
            cursorColor: _kCyan,
            decoration: InputDecoration(
              labelText: label,
              labelStyle: TextStyle(
                color: palette.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              floatingLabelStyle: TextStyle(
                color: floatingLabelColor,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              prefixIcon: Icon(icon, color: iconColor, size: 20),
              suffixIcon: isModified && !hasError
                  ? const Icon(Icons.check_circle, color: _kSuccess, size: 18)
                  : null,
              border: InputBorder.none,
              counterText: '',
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 12),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: _kError, size: 13),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    errorText!,
                    style: const TextStyle(
                      color: _kError,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
