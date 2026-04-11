import 'package:flutter/material.dart';

import '../../babifix_design_system.dart';
import '../../models/client_models.dart';
import '../../babifix_money.dart';

class ServiceDetailScreen extends StatelessWidget {
  const ServiceDetailScreen({
    super.key,
    required this.service,
    required this.isLight,
    this.onReserve,
  });

  final ClientService service;
  final bool isLight;
  final Future<void> Function()? onReserve;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bg = theme.scaffoldBackgroundColor;
    final card = cs.surface;
    final text = cs.onSurface;
    final sub = cs.onSurfaceVariant;

    return Scaffold(
      backgroundColor: bg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            backgroundColor: card,
            foregroundColor: text,
            flexibleSpace: FlexibleSpaceBar(
              background: Hero(
                tag: 'babifix-service-${service.providerId}',
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    service.imageUrl.startsWith('http')
                        ? Image.network(service.imageUrl, fit: BoxFit.cover)
                        : Image.asset(service.imageUrl, fit: BoxFit.cover),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.7),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              title: Text(
                service.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Badges
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: BabifixDesign.cyan.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: BabifixDesign.cyan.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          service.category.replaceAll('_', ' '),
                          style: TextStyle(
                            color: BabifixDesign.ciBlue,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (service.verified)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: BabifixDesign.ciGreen
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.verified_rounded,
                                  size: 14, color: BabifixDesign.ciGreen),
                              const SizedBox(width: 4),
                              Text(
                                'Vérifié',
                                style: TextStyle(
                                    color: BabifixDesign.ciGreen,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Note et durée
                  Row(
                    children: [
                      Icon(Icons.star_rounded,
                          color: Colors.amber.shade600, size: 22),
                      const SizedBox(width: 4),
                      Text(
                        service.rating.toStringAsFixed(1),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: text,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Icon(Icons.schedule_rounded,
                          color: sub, size: 20),
                      const SizedBox(width: 4),
                      Text(
                        service.duration,
                        style: TextStyle(fontSize: 15, color: sub),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Prix
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tarif estimé',
                              style: TextStyle(
                                  fontSize: 13, color: sub),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              formatFcfa(service.price),
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                color: BabifixDesign.cyan,
                              ),
                            ),
                          ],
                        ),
                        Icon(
                          Icons.info_outline_rounded,
                          color: sub,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Description
                  Text(
                    'À propos de ce service',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Ce prestataire est disponible pour intervenir à votre domicile. '
                    'Le tarif indiqué est une estimation basée sur des prestations similaires. '
                    'Le prix définitif sera établi après le diagnostic sur place.',
                    style: TextStyle(
                      color: sub,
                      height: 1.55,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 120),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton(
            onPressed: onReserve,
            style: FilledButton.styleFrom(
              backgroundColor: BabifixDesign.cyan,
              foregroundColor: BabifixDesign.navy,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.calendar_month_rounded, size: 22),
                SizedBox(width: 8),
                Text(
                  'Réserver ce service',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
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
