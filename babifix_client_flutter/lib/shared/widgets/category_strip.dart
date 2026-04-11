import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../babifix_design_system.dart';
import '../../models/client_models.dart';

class CategoryStrip extends StatelessWidget {
  const CategoryStrip({
    super.key,
    required this.categories,
    required this.active,
    required this.onTap,
  });

  final List<CategoryTab> categories;
  final int active;
  final ValueChanged<int> onTap;

  static const double _chipW = 80;
  static const double _stripH = 82;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: _stripH,
      child: ListView.separated(
        primary: false,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final selected = index == active;
          final tab = categories[index];
          final offBg = isLight
              ? const Color(0xFFF1F5F9)
              : const Color(0xFF1E293B);
          final offBorder = isLight
              ? const Color(0x1A0F172A)
              : const Color(0x22FFFFFF);
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onTap(index),
              borderRadius: BorderRadius.circular(16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: _chipW,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  gradient: selected
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            BabifixDesign.cyan.withValues(alpha: 0.95),
                            BabifixDesign.ciBlue.withValues(alpha: 0.88),
                          ],
                        )
                      : LinearGradient(colors: [offBg, offBg]),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selected
                        ? BabifixDesign.navy.withValues(alpha: 0.12)
                        : offBorder,
                    width: selected ? 1.5 : 1,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: BabifixDesign.ciBlue.withValues(
                              alpha: isLight ? 0.22 : 0.35,
                            ),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isLight ? 0.04 : 0.2,
                            ),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      height: 36,
                      width: 36,
                      decoration: BoxDecoration(
                        color:
                            tab.color?.withValues(alpha: 0.15) ??
                            (selected
                                ? BabifixDesign.ciBlue.withValues(alpha: 0.15)
                                : (isLight
                                      ? const Color(0xFFE2E8F0)
                                      : const Color(0xFF334155))),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child:
                            tab.iconNetworkUrl != null &&
                                tab.iconNetworkUrl!.isNotEmpty
                            ? SvgPicture.network(
                                tab.iconNetworkUrl!,
                                fit: BoxFit.contain,
                                width: 22,
                                height: 22,
                                placeholderBuilder: (_) => Icon(
                                  tab.icon ?? Icons.category_rounded,
                                  size: 20,
                                  color: tab.color ?? BabifixDesign.navy,
                                ),
                              )
                            : Icon(
                                tab.icon ?? Icons.category_rounded,
                                size: 20,
                                color:
                                    tab.color ??
                                    (selected
                                        ? BabifixDesign.navy
                                        : (isLight
                                              ? cs.onSurfaceVariant
                                              : const Color(0xFFCBD5E1))),
                              ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tab.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.1,
                        color: selected
                            ? BabifixDesign.navy
                            : (isLight
                                  ? cs.onSurfaceVariant
                                  : const Color(0xFFCBD5E1)),
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
