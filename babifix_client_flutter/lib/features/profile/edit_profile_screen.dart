import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';

import '../../babifix_design_system.dart';
import '../../user_store.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
const _kNavyDeep = Color(0xFF050D1A);
const _kNavy     = Color(0xFF0A1628);
const _kBlue     = Color(0xFF2563EB);
const _kBlueDark = Color(0xFF1D4ED8);
const _kCyan     = Color(0xFF4CC9F0);

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
  final _picker = ImagePicker();

  late final AnimationController _anim;
  late final Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    nameCtrl    = TextEditingController(text: widget.initialName);
    emailCtrl   = TextEditingController(text: widget.initialEmail);
    phoneCtrl   = TextEditingController(text: widget.initialPhone);
    addressCtrl = TextEditingController(text: widget.initialAddress);
    _avatarBytes = widget.initialAvatarBytes;

    _anim   = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _fadeIn = CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic);
    _anim.forward();
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

  Future<void> _pickPhoto() async {
    final x = await _picker.pickImage(
        source: ImageSource.gallery, maxWidth: 1024, imageQuality: 85);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    if (!mounted) return;
    setState(() => _avatarBytes = bytes);
  }

  Future<void> _save() async {
    await BabifixUserStore.saveProfile(
      name:    nameCtrl.text.trim(),
      email:   emailCtrl.text.trim(),
      phone:   phoneCtrl.text.trim(),
      address: addressCtrl.text.trim(),
    );
    if (_avatarBytes != null) {
      await BabifixUserStore.saveAvatarBytes(_avatarBytes!);
    }
    if (!mounted) return;
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kNavyDeep,
      body: Stack(
        children: [
          // Fond gradient
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
          // Orbe orange haut-gauche
          Positioned(
            top: -60, left: -50,
            child: _Orbe(color: _kBlue, size: 200, alpha: 0.16),
          ),
          // Orbe cyan bas-droite
          Positioned(
            bottom: -70, right: -60,
            child: _Orbe(color: _kCyan, size: 240, alpha: 0.10),
          ),

          SafeArea(
            child: FadeTransition(
              opacity: _fadeIn,
              child: Column(
                children: [
                  // Header
                  _buildHeader(context),

                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                      children: [
                        // Avatar
                        Center(child: _buildAvatar()),
                        const SizedBox(height: 8),
                        Center(
                          child: Text(
                            'Photo, identité et coordonnées pour vos interventions.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 13, height: 1.4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),

                        // Carte glassmorphisme
                        ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.10),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Section title
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
                                  ),
                                  const SizedBox(height: 14),
                                  _DarkField(
                                    controller: emailCtrl,
                                    label: 'Email',
                                    icon: Icons.email_outlined,
                                    keyboardType: TextInputType.emailAddress,
                                    textInputAction: TextInputAction.next,
                                  ),
                                  const SizedBox(height: 14),
                                  _DarkField(
                                    controller: phoneCtrl,
                                    label: 'Téléphone',
                                    icon: Icons.phone_outlined,
                                    keyboardType: TextInputType.phone,
                                    textInputAction: TextInputAction.next,
                                  ),
                                  const SizedBox(height: 14),
                                  _DarkField(
                                    controller: addressCtrl,
                                    label: "Adresse exacte d'intervention",
                                    icon: Icons.location_on_outlined,
                                    maxLines: 3,
                                    textInputAction: TextInputAction.done,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 28),

                        // Bouton enregistrer
                        GestureDetector(
                          onTap: _save,
                          child: Container(
                            height: 56,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [_kBlue, _kBlueDark],
                              ),
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  color: _kBlue.withValues(alpha: 0.45),
                                  blurRadius: 20, offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.check_rounded, color: Colors.white, size: 20),
                                SizedBox(width: 10),
                                Text(
                                  'Enregistrer les modifications',
                                  style: TextStyle(
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
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
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
            'Mon Profil',
            style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: _kBlue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _kBlue.withValues(alpha: 0.30)),
            ),
            child: const Text(
              'BABIFIX',
              style: TextStyle(
                color: _kBlue, fontSize: 11,
                fontWeight: FontWeight.w800, letterSpacing: 2,
              ),
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
        // Anneau gradient extérieur
        Container(
          width: 108, height: 108,
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
                blurRadius: 24, offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: CircleAvatar(
              radius: 51,
              backgroundColor: _kNavyDeep,
              backgroundImage: _avatarBytes != null
                  ? MemoryImage(_avatarBytes!) as ImageProvider
                  : const AssetImage('assets/images/babifix-logo.png'),
            ),
          ),
        ),
        // Bouton caméra
        Positioned(
          right: -2, bottom: 0,
          child: GestureDetector(
            onTap: _pickPhoto,
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [_kBlue, _kBlueDark],
                ),
                boxShadow: [
                  BoxShadow(
                    color: _kBlue.withValues(alpha: 0.5),
                    blurRadius: 10, offset: const Offset(0, 3),
                  ),
                ],
                border: Border.all(color: _kNavyDeep, width: 2.5),
              ),
              child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 16),
            ),
          ),
        ),
      ],
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
      width: size, height: size,
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
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final TextInputAction? textInputAction;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        textInputAction: textInputAction,
        maxLines: maxLines,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.5), fontSize: 14,
          ),
          floatingLabelStyle: const TextStyle(color: _kBlue, fontSize: 12),
          prefixIcon: Icon(icon, color: Colors.white.withValues(alpha: 0.4), size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }
}
