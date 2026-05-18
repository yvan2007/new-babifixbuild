import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../user_store.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
const _kNavyDeep = Color(0xFF050D1A);
const _kNavy = Color(0xFF0A1628);
const _kBlue = Color(0xFF4CC9F0);
const _kBlueDark = Color(0xFF1D4ED8);
const _kCyan = Color(0xFF4CC9F0);
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

  // Erreurs inline par champ
  String? _nameError;
  String? _emailError;
  String? _phoneError;
  String? _addressError;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    nameCtrl = TextEditingController(text: widget.initialName);
    emailCtrl = TextEditingController(text: widget.initialEmail);
    phoneCtrl = TextEditingController(text: widget.initialPhone);
    addressCtrl = TextEditingController(text: widget.initialAddress);
    _avatarBytes = widget.initialAvatarBytes;

    // Re-render à chaque frappe pour le badge "Modifié" et le bouton.
    nameCtrl.addListener(_onFieldChange);
    emailCtrl.addListener(_onFieldChange);
    phoneCtrl.addListener(_onFieldChange);
    addressCtrl.addListener(_onFieldChange);

    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fadeIn = CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic);
    _anim.forward();
  }

  void _onFieldChange() {
    // Clear inline errors as the user fixes them.
    if (_nameError != null && _validName(nameCtrl.text.trim()) == null) {
      setState(() => _nameError = null);
    } else if (_emailError != null && _validEmail(emailCtrl.text.trim()) == null) {
      setState(() => _emailError = null);
    } else if (_phoneError != null && _validPhone(phoneCtrl.text.trim()) == null) {
      setState(() => _phoneError = null);
    } else if (_addressError != null &&
        _validAddress(addressCtrl.text.trim()) == null) {
      setState(() => _addressError = null);
    } else {
      // toujours redraw pour mettre à jour le badge "Modifié"
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
    if (v.isEmpty) return null; // email facultatif si pas requis dans le compte
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

  // ── Photo : bottom sheet (Galerie / Caméra / Supprimer) ─────────────────────
  Future<void> _showPhotoSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _kNavy,
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
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Photo de profil',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _sheetAction(
                icon: Icons.photo_library_rounded,
                label: 'Choisir dans la galerie',
                onTap: () async {
                  Navigator.pop(ctx);
                  await _pickPhoto(ImageSource.gallery);
                },
              ),
              const SizedBox(height: 8),
              _sheetAction(
                icon: Icons.photo_camera_rounded,
                label: 'Prendre une photo',
                onTap: () async {
                  Navigator.pop(ctx);
                  await _pickPhoto(ImageSource.camera);
                },
              ),
              if (_avatarBytes != null) ...[
                const SizedBox(height: 8),
                _sheetAction(
                  icon: Icons.delete_outline_rounded,
                  label: 'Supprimer la photo',
                  destructive: true,
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _avatarBytes = null;
                      _avatarChanged = true;
                    });
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    final color = destructive ? _kError : _kBlue;
    return Material(
      color: Colors.white.withValues(alpha: 0.06),
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
                    color: destructive ? _kError : Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.35),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final x = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        imageQuality: 85,
      );
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
    } catch (e) {
      if (!mounted) return;
      _showSnack('Impossible de charger la photo.', error: true);
    }
  }

  // ── Save flow avec validation + loading + try/catch ─────────────────────────
  Future<void> _save() async {
    if (_saving) return;

    final nameErr = _validName(nameCtrl.text.trim());
    final emailErr = _validEmail(emailCtrl.text.trim());
    final phoneErr = _validPhone(phoneCtrl.text.trim());
    final addrErr = _validAddress(addressCtrl.text.trim());

    if (nameErr != null || emailErr != null || phoneErr != null || addrErr != null) {
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
      );
      if (_avatarChanged) {
        if (_avatarBytes != null) {
          await BabifixUserStore.saveAvatarBytes(_avatarBytes!);
        } else {
          // Suppression : on enregistre un tableau vide si l'API le supporte.
          try {
            await BabifixUserStore.saveAvatarBytes(Uint8List(0));
          } catch (_) {}
        }
      }
      if (!mounted) return;
      _showSnack('Profil enregistré.', success: true);
      // Petit délai pour que l'utilisateur voie le feedback avant le pop.
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      widget.onSaved();
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      _showSnack('Échec de l\'enregistrement : ${e.toString()}', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack(String msg, {bool error = false, bool success = false}) {
    final color = error ? _kError : success ? _kSuccess : _kBlue;
    final icon = error
        ? Icons.error_outline_rounded
        : success
            ? Icons.check_circle_rounded
            : Icons.info_outline_rounded;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _kNavyDeep,
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
              child: Text(
                msg,
                style: const TextStyle(color: Colors.white, fontSize: 13.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Quitter sans enregistrer : confirmation si modifications ────────────────
  Future<bool> _confirmDiscard() async {
    if (!_hasChanges) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kNavy,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Quitter sans enregistrer ?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Vos modifications seront perdues.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Continuer',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Quitter',
              style: TextStyle(color: _kError, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard()) {
          if (mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: _kNavyDeep,
        body: Stack(
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_kNavyDeep, _kNavy, Color(0xFF060E1C)],
                  ),
                ),
              ),
            ),
            Positioned(
              top: -60,
              left: -50,
              child: _Orbe(color: _kBlue, size: 200, alpha: 0.16),
            ),
            Positioned(
              bottom: -70,
              right: -60,
              child: _Orbe(color: _kCyan, size: 240, alpha: 0.10),
            ),
            SafeArea(
              child: FadeTransition(
                opacity: _fadeIn,
                child: Column(
                  children: [
                    _buildHeader(context),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                        children: [
                          Center(child: _buildAvatar()),
                          const SizedBox(height: 10),
                          Center(
                            child: TextButton.icon(
                              onPressed: _showPhotoSheet,
                              icon: const Icon(Icons.camera_alt_outlined,
                                  color: _kBlue, size: 18),
                              label: const Text(
                                'Modifier la photo',
                                style: TextStyle(
                                  color: _kBlue,
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
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 12.5,
                                height: 1.4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          _buildFormCard(),
                          const SizedBox(height: 24),
                          _buildSaveButton(),
                          const SizedBox(height: 12),
                          Center(
                            child: Text(
                              'Vos données restent privées et chiffrées.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.35),
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final dirty = _hasChanges;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 16, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () async {
              if (await _confirmDiscard()) {
                if (mounted) Navigator.of(context).maybePop();
              }
            },
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white70, size: 20),
          ),
          const SizedBox(width: 4),
          const Text(
            'Mon Profil',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          if (dirty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _kSuccess.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _kSuccess.withValues(alpha: 0.45)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: _kSuccess,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
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

  Widget _buildAvatar() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 116,
          height: 116,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [_kBlue, _kBlueDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: _kBlue.withValues(alpha: 0.45),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: CircleAvatar(
              radius: 55,
              backgroundColor: _kNavyDeep,
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
              onTap: _showPhotoSheet,
              customBorder: const CircleBorder(),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [_kBlue, _kBlueDark],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _kBlue.withValues(alpha: 0.5),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                  border: Border.all(color: _kNavyDeep, width: 2.5),
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

  Widget _buildFormCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _kBlue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.person_outline_rounded,
                        color: _kBlue, size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Informations personnelles',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _DarkField(
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
              _DarkField(
                controller: emailCtrl,
                label: 'Email',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                errorText: _emailError,
                isModified:
                    emailCtrl.text.trim() != widget.initialEmail.trim(),
              ),
              const SizedBox(height: 14),
              _DarkField(
                controller: phoneCtrl,
                label: 'Téléphone',
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                errorText: _phoneError,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s\-]')),
                ],
                isModified:
                    phoneCtrl.text.trim() != widget.initialPhone.trim(),
              ),
              const SizedBox(height: 14),
              _DarkField(
                controller: addressCtrl,
                label: "Adresse exacte d'intervention",
                icon: Icons.location_on_outlined,
                maxLines: 3,
                textInputAction: TextInputAction.done,
                errorText: _addressError,
                isModified:
                    addressCtrl.text.trim() != widget.initialAddress.trim(),
              ),
            ],
          ),
        ),
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
            gradient: const LinearGradient(
              colors: [_kBlue, _kBlueDark],
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: _kBlue.withValues(alpha: 0.45),
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
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
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

// ── Widgets premium ───────────────────────────────────────────────────────────

class _Orbe extends StatelessWidget {
  const _Orbe({required this.color, required this.size, required this.alpha});
  final Color color;
  final double size;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: alpha), Colors.transparent],
        ),
      ),
    );
  }
}

class _DarkField extends StatelessWidget {
  const _DarkField({
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
        ? _kError.withValues(alpha: 0.55)
        : isModified
            ? _kSuccess.withValues(alpha: 0.45)
            : Colors.white.withValues(alpha: 0.10);
    final iconColor = hasError
        ? _kError
        : isModified
            ? _kSuccess
            : Colors.white.withValues(alpha: 0.4);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(16),
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
            style: const TextStyle(color: Colors.white, fontSize: 15),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 14,
              ),
              floatingLabelStyle: TextStyle(
                color: hasError ? _kError : _kBlue,
                fontSize: 12,
              ),
              prefixIcon: Icon(icon, color: iconColor, size: 20),
              suffixIcon: isModified && !hasError
                  ? const Icon(Icons.check_circle, color: _kSuccess, size: 18)
                  : null,
              border: InputBorder.none,
              counterText: '',
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 16),
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
