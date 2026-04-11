import 'package:flutter/material.dart';

import '../../models/client_models.dart';

class ActualiteDetailScreen extends StatelessWidget {
  const ActualiteDetailScreen({
    super.key,
    required this.item,
    required this.isLight,
  });

  final ClientActualiteItem item;
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    final bg = isLight ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    final card = isLight ? Colors.white : const Color(0xFF1E293B);
    final text = isLight ? const Color(0xFF0F172A) : Colors.white;
    final sub = isLight ? const Color(0xFF64748B) : const Color(0xFF94A3B8);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: card,
        foregroundColor: text,
        elevation: 0,
        title: const Text('Actualité'),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (item.imageUrl.isNotEmpty)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  item.imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: const Color(0xFFE2E8F0),
                    child: const Icon(Icons.image_not_supported_outlined,
                        size: 48),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.categorieTag.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        item.categorieTag.replaceAll('_', ' '),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0284C7),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  Text(
                    item.titre,
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: text,
                        height: 1.25),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    item.dateLabel,
                    style: TextStyle(fontSize: 13, color: sub),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    item.description,
                    style: TextStyle(
                        fontSize: 16,
                        color: text.withValues(alpha: 0.92),
                        height: 1.55),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
