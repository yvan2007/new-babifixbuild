import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../babifix_design_system.dart';

/// Zone message + miniatures photos (galerie / appareil), avec suppression.
class MessageWithPhotosField extends StatelessWidget {
  const MessageWithPhotosField({
    super.key,
    required this.controller,
    required this.photos,
    required this.onPhotosChanged,
    this.maxPhotos = 4,
    this.hint = 'Message (optionnel)',
    this.messageHeading = 'Message au prestataire',
    this.photosHeading = 'Photos jointes',
  });

  final TextEditingController controller;
  final List<Uint8List> photos;
  final ValueChanged<List<Uint8List>> onPhotosChanged;
  final int maxPhotos;
  final String hint;
  final String messageHeading;
  final String photosHeading;

  Future<void> _addPhoto(BuildContext context, ImageSource source) async {
    if (photos.length >= maxPhotos) return;
    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: source,
      maxWidth: 1400,
      imageQuality: 78,
    );
    if (x == null) return;
    final bytes = await x.readAsBytes();
    if (bytes.isEmpty) return;
    onPhotosChanged([...photos, bytes]);
  }

  Future<void> _addMultipleFromGallery(BuildContext context) async {
    final remaining = maxPhotos - photos.length;
    if (remaining <= 0) return;
    final picker = ImagePicker();
    final files = await picker.pickMultiImage(
      maxWidth: 1400,
      imageQuality: 78,
    );
    if (files.isEmpty) return;
    final next = [...photos];
    final take = files.length > remaining ? remaining : files.length;
    for (var i = 0; i < take; i++) {
      final bytes = await files[i].readAsBytes();
      if (bytes.isNotEmpty) next.add(bytes);
    }
    onPhotosChanged(next);
  }

  void _showSourceSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galerie'),
              subtitle: const Text('Plusieurs photos en une fois'),
              onTap: () {
                Navigator.pop(ctx);
                _addMultipleFromGallery(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Appareil photo'),
              onTap: () {
                Navigator.pop(ctx);
                _addPhoto(context, ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isLight = theme.brightness == Brightness.light;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          messageHeading,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: cs.onSurface.withValues(alpha: 0.85),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: hint,
            alignLabelWithHint: true,
            filled: true,
            prefixIcon: Icon(Icons.chat_bubble_outline_rounded, color: BabifixDesign.cyan.withValues(alpha: 0.9)),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Text(
              photosHeading,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: cs.onSurface.withValues(alpha: 0.85),
              ),
            ),
            const Spacer(),
            Text(
              '${photos.length}/$maxPhotos',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 88,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              Material(
                color: isLight ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  onTap: photos.length >= maxPhotos
                      ? null
                      : () => _showSourceSheet(context),
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: 88,
                    height: 88,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_photo_alternate_outlined,
                          size: 28,
                          color: photos.length >= maxPhotos ? cs.onSurfaceVariant : BabifixDesign.cyan,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Ajouter',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              for (int i = 0; i < photos.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.memory(
                          photos[i],
                          width: 88,
                          height: 88,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: -6,
                        right: -6,
                        child: Material(
                          color: const Color(0xFFEF4444),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () {
                              final next = [...photos]..removeAt(i);
                              onPhotosChanged(next);
                            },
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(Icons.close_rounded, size: 16, color: Colors.white),
                            ),
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
    );
  }
}
