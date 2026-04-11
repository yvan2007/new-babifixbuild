import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';

import '../../babifix_design_system.dart';
import '../../user_store.dart';

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

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController nameCtrl;
  late final TextEditingController emailCtrl;
  late final TextEditingController phoneCtrl;
  late final TextEditingController addressCtrl;
  Uint8List? _avatarBytes;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    nameCtrl = TextEditingController(text: widget.initialName);
    emailCtrl = TextEditingController(text: widget.initialEmail);
    phoneCtrl = TextEditingController(text: widget.initialPhone);
    addressCtrl = TextEditingController(text: widget.initialAddress);
    _avatarBytes = widget.initialAvatarBytes;
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    emailCtrl.dispose();
    phoneCtrl.dispose();
    addressCtrl.dispose();
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
      name: nameCtrl.text.trim(),
      email: emailCtrl.text.trim(),
      phone: phoneCtrl.text.trim(),
      address: addressCtrl.text.trim(),
    );
    if (_avatarBytes != null) {
      await BabifixUserStore.saveAvatarBytes(_avatarBytes!);
    }
    if (!mounted) return;
    widget.onSaved();
  }

  Widget _svg(String a) => Padding(
        padding: const EdgeInsets.only(left: 14, right: 4),
        child: SvgPicture.asset(a, width: 22, height: 22),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final titleColor = cs.onSurface;
    final muted = cs.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(title: const Text('Modifier mon profil')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 52,
                  backgroundColor: BabifixDesign.navy,
                  backgroundImage: _avatarBytes != null
                      ? MemoryImage(_avatarBytes!) as ImageProvider
                      : const AssetImage('assets/images/babifix-logo.png'),
                ),
                Positioned(
                  right: -4,
                  bottom: 0,
                  child: Material(
                    color: BabifixDesign.cyan,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _pickPhoto,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Icon(Icons.camera_alt_rounded,
                            color: BabifixDesign.navy, size: 22),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Photo, identite et coordonnees pour vos interventions avec les prestataires.',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, fontSize: 13),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: nameCtrl,
            textCapitalization: TextCapitalization.words,
            style: TextStyle(color: titleColor),
            decoration: InputDecoration(
              labelText: 'Nom complet',
              prefixIcon: _svg('assets/illustrations/icons/icon_user.svg'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: emailCtrl,
            keyboardType: TextInputType.emailAddress,
            style: TextStyle(color: titleColor),
            decoration: InputDecoration(
              labelText: 'Email',
              prefixIcon: _svg('assets/illustrations/icons/icon_mail.svg'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: phoneCtrl,
            keyboardType: TextInputType.phone,
            style: TextStyle(color: titleColor),
            decoration: InputDecoration(
              labelText: 'Telephone',
              prefixIcon: _svg('assets/illustrations/icons/icon_phone.svg'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: addressCtrl,
            maxLines: 3,
            style: TextStyle(color: titleColor),
            decoration: InputDecoration(
              labelText: "Adresse exacte d'intervention",
              alignLabelWithHint: true,
              prefixIcon: Padding(
                padding:
                    const EdgeInsets.only(top: 12, left: 12, right: 8),
                child: SvgPicture.asset(
                    'assets/illustrations/icons/icon_map_pin.svg',
                    width: 22,
                    height: 22),
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _save,
            child: const Text('Enregistrer les modifications'),
          ),
        ],
      ),
    );
  }
}
