import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../models/client_models.dart';

String normalizeBabifixSearch(String input) {
  const accented = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿÀÁÂÃÄÅÇÈÉÊËÌÍÎÏÑÒÓÔÕÖÙÚÛÜÝ';
  const plain = 'aaaaaaceeeeiiiinooooouuuuyyAAAAAACEEEEIIIINOOOOOUUUUY';
  final buf = StringBuffer();
  for (final rune in input.trim().toLowerCase().runes) {
    final ch = String.fromCharCode(rune);
    final idx = accented.indexOf(ch);
    buf.write(idx >= 0 ? plain[idx] : ch);
  }
  return buf.toString();
}

/// Pilules horizontales a largeur adaptative (sans troncature), conformes
/// a la maquette validee + bouton "Toutes (N)" ouvrant un repertoire groupe.
class CategoryStrip extends StatelessWidget {
  const CategoryStrip({
    super.key,
    required this.categories,
    required this.active,
    required this.isLight,
    required this.onSelect,
    this.showAllButton = true,
  });

  final List<CategoryTab> categories;
  final int active;
  final bool isLight;
  final ValueChanged<int> onSelect;
  final bool showAllButton;

  @override
  Widget build(BuildContext context) {
    final safeActive = categories.isEmpty
        ? 0
        : active.clamp(0, categories.length - 1);

    return SizedBox(
      height: 52,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final c = categories[index];
                final isSelected = index == safeActive;
                return _CategoryPill(
                  category: c,
                  selected: isSelected,
                  isLight: isLight,
                  onTap: () => onSelect(index),
                );
              },
            ),
          ),
          if (showAllButton && categories.length > 4)
            Padding(
              padding: const EdgeInsets.only(right: 14, left: 4),
              child: GestureDetector(
                onTap: () => _openAllCategoriesSheet(context, safeActive),
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: isLight
                        ? const Color(0xFFF1F5F9)
                        : const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: isLight
                          ? const Color(0xFFCBD5E1)
                          : const Color(0xFF334155),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.apps_rounded,
                        size: 16,
                        color: isLight ? BabifixDesign.navy : Colors.white,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Tout (${categories.length - 1})',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: isLight ? BabifixDesign.navy : Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _openAllCategoriesSheet(BuildContext context, int activeIndex) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isLight ? Colors.white : const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _AllCategoriesModal(
        categories: categories,
        activeIndex: activeIndex,
        isLight: isLight,
        onSelect: (idx) {
          Navigator.of(ctx).pop();
          onSelect(idx);
        },
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({
    required this.category,
    required this.selected,
    required this.isLight,
    required this.onTap,
  });

  final CategoryTab category;
  final bool selected;
  final bool isLight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = category.color ?? BabifixDesign.ciBlue;
    final bgColor = selected
        ? (isLight ? BabifixDesign.navy : BabifixDesign.cyan)
        : (isLight ? Colors.white : const Color(0xFF17223B));
    final borderColor = selected
        ? Colors.transparent
        : (isLight ? const Color(0xFFE2E8F0) : const Color(0xFF283554));
    final textColor = selected
        ? (isLight ? Colors.white : BabifixDesign.navy)
        : (isLight ? BabifixDesign.navy : const Color(0xFFE2E8F0));

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: borderColor, width: 1.1),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: (isLight ? BabifixDesign.navy : BabifixDesign.cyan)
                        .withValues(alpha: 0.24),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isLight ? 0.04 : 0.14),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CategoryIcon(
              category: category,
              selected: selected,
              isLight: isLight,
              accent: accent,
            ),
            const SizedBox(width: 8),
            Text(
              category.label,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: textColor,
                letterSpacing: -0.1,
              ),
            ),
            if (category.isSensitive) ...[
              const SizedBox(width: 5),
              Icon(
                Icons.verified_user_rounded,
                size: 13,
                color: selected
                    ? (isLight ? const Color(0xFF67E8F9) : BabifixDesign.navy)
                    : const Color(0xFF0F766E),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CategoryIcon extends StatelessWidget {
  const _CategoryIcon({
    required this.category,
    required this.selected,
    required this.isLight,
    required this.accent,
  });

  final CategoryTab category;
  final bool selected;
  final bool isLight;
  final Color accent;

  static IconData _resolveCategoryIcon(CategoryTab c) {
    if (c.icon != null) return c.icon!;
    final norm = normalizeBabifixSearch('${c.label} ${c.searchKeywords}');
    if (norm.contains('plomb') || norm.contains('sanit') || norm.contains('eau')) {
      return Icons.plumbing_rounded;
    }
    if (norm.contains('electr')) return Icons.electrical_services_rounded;
    if (norm.contains('chauff') || norm.contains('eau chaude')) {
      return Icons.whatshot_rounded;
    }
    if (norm.contains('clim') || norm.contains('froid')) {
      return Icons.ac_unit_rounded;
    }
    if (norm.contains('animal') || norm.contains('chien') || norm.contains('chat')) {
      return Icons.pets_rounded;
    }
    if (norm.contains('garde') || norm.contains('nounou') || norm.contains('enfant')) {
      return Icons.child_care_rounded;
    }
    if (norm.contains('menage') || norm.contains('nettoy')) {
      return Icons.cleaning_services_rounded;
    }
    if (norm.contains('jardin') || norm.contains('espace')) {
      return Icons.park_rounded;
    }
    if (norm.contains('peint')) return Icons.format_paint_rounded;
    if (norm.contains('menuis') || norm.contains('eben')) {
      return Icons.carpenter_rounded;
    }
    if (norm.contains('serrur') || norm.contains('cle')) {
      return Icons.vpn_key_rounded;
    }
    if (norm.contains('macon') || norm.contains('batiment') || norm.contains('renov')) {
      return Icons.foundation_rounded;
    }
    if (norm.contains('auto') || norm.contains('mecan')) {
      return Icons.build_circle_rounded;
    }
    return Icons.handyman_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final fallbackIcon = Icon(
      _resolveCategoryIcon(category),
      size: 14,
      color: selected
          ? (isLight ? Colors.white : BabifixDesign.navy)
          : accent,
    );

    if (category.icon != null) {
      return Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: selected
              ? (isLight
                  ? Colors.white.withValues(alpha: 0.22)
                  : BabifixDesign.navy.withValues(alpha: 0.14))
              : accent.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: fallbackIcon,
      );
    }

    final slug = category.iconeSlug.trim();
    final netUrl = (category.iconNetworkUrl ?? '').trim().isNotEmpty
        ? babifixResolveMediaUrl(category.iconNetworkUrl!)
        : '';

    Widget svgOrFallback() {
      if (slug.isNotEmpty) {
        return SvgPicture.asset(
          'assets/category-icons/$slug.svg',
          width: 17,
          height: 17,
          fit: BoxFit.contain,
          placeholderBuilder: (_) => fallbackIcon,
          errorBuilder: (_, __, ___) {
            if (netUrl.isNotEmpty) {
              return SvgPicture.network(
                netUrl,
                width: 17,
                height: 17,
                fit: BoxFit.contain,
                placeholderBuilder: (_) => fallbackIcon,
                errorBuilder: (_, __, ___) => fallbackIcon,
              );
            }
            return fallbackIcon;
          },
        );
      }
      if (netUrl.isNotEmpty) {
        return SvgPicture.network(
          netUrl,
          width: 17,
          height: 17,
          fit: BoxFit.contain,
          placeholderBuilder: (_) => fallbackIcon,
          errorBuilder: (_, __, ___) => fallbackIcon,
        );
      }
      return fallbackIcon;
    }

    // Fond clair neutre pour preserver les couleurs exactes des SVG d Admin.
    return Container(
      width: 26,
      height: 26,
      padding: const EdgeInsets.all(4.5),
      decoration: BoxDecoration(
        color: selected
            ? Colors.white.withValues(alpha: 0.94)
            : (isLight
                ? const Color(0xFFF1F5F9)
                : const Color(0xFFF8FAFC).withValues(alpha: 0.92)),
        shape: BoxShape.circle,
      ),
      child: Center(child: svgOrFallback()),
    );
  }
}

class _AllCategoriesModal extends StatefulWidget {
  const _AllCategoriesModal({
    required this.categories,
    required this.activeIndex,
    required this.isLight,
    required this.onSelect,
  });

  final List<CategoryTab> categories;
  final int activeIndex;
  final bool isLight;
  final ValueChanged<int> onSelect;

  @override
  State<_AllCategoriesModal> createState() => _AllCategoriesModalState();
}

class _AllCategoriesModalState extends State<_AllCategoriesModal> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final textPrimary = widget.isLight ? BabifixDesign.navy : Colors.white;
    final textSecondary =
        widget.isLight ? const Color(0xFF475569) : const Color(0xFF94A3B8);
    final qNorm = normalizeBabifixSearch(_q);

    // Grouper les categories par univers en preservant l'index original
    final Map<String, List<MapEntry<int, CategoryTab>>> grouped = {};
    for (int i = 0; i < widget.categories.length; i++) {
      final c = widget.categories[i];
      if (qNorm.isNotEmpty) {
        final h = normalizeBabifixSearch(
          '${c.label} ${c.groupe} ${c.searchKeywords}',
        );
        if (!qNorm.split(RegExp(r'\s+')).every((t) => h.contains(t))) {
          continue;
        }
      }
      final g = c.filterKey == 'TOUS'
          ? 'Acces rapide'
          : (c.groupe.isNotEmpty ? c.groupe : 'Maison & Services');
      grouped.putIfAbsent(g, () => []).add(MapEntry(i, c));
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
      minChildSize: 0.5,
      maxChildSize: 0.94,
      builder: (_, scrollCtrl) => Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tous les corps de metiers',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: textPrimary,
                        ),
                      ),
                      Text(
                        '${widget.categories.length - 1} specialites classees par univers',
                        style: TextStyle(fontSize: 12.5, color: textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close_rounded, color: textPrimary),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            child: TextField(
              onChanged: (v) => setState(() => _q = v),
              style: TextStyle(color: textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Filtrer un metier (plombier, nounou, clim...)',
                hintStyle: TextStyle(color: textSecondary, fontSize: 13.5),
                prefixIcon: Icon(Icons.search_rounded, color: textSecondary),
                filled: true,
                fillColor: widget.isLight
                    ? const Color(0xFFF1F5F9)
                    : const Color(0xFF1E293B),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: grouped.isEmpty
                ? Center(
                    child: Text(
                      'Aucun metier ne correspond a "$_q".',
                      style: TextStyle(color: textSecondary, fontSize: 14),
                    ),
                  )
                : ListView.builder(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
                    itemCount: grouped.length,
                    itemBuilder: (_, gIdx) {
                      final entry = grouped.entries.elementAt(gIdx);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.key.toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.7,
                                color: textSecondary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: entry.value.map((item) {
                                return _CategoryPill(
                                  category: item.value,
                                  selected: item.key == widget.activeIndex,
                                  isLight: widget.isLight,
                                  onTap: () => widget.onSelect(item.key),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
