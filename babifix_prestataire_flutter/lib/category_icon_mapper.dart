import 'package:flutter/material.dart';

class CategoryIconMapper {
  CategoryIconMapper._();

  static const _defaultIcon = Icons.home_repair_service_rounded;
  static const _defaultColor = Color(0xFF0284C7);

  static final Map<String, _CatMeta> _map = {
    // Admin constants.py - CATEGORY_ICON_SLUGS
    'goutte': _CatMeta(Icons.water_drop_rounded, Color(0xFF3B82F6)),
    'eclair': _CatMeta(Icons.bolt_rounded, Color(0xFFF59E0B)),
    'climatisation': _CatMeta(Icons.ac_unit_rounded, Color(0xFF0EA5E9)),
    'chauffage': _CatMeta(Icons.whatshot_rounded, Color(0xFFDC2626)),
    'cle': _CatMeta(Icons.lock_rounded, Color(0xFF64748B)),
    'fenetre': _CatMeta(Icons.window_rounded, Color(0xFF7C3AED)),
    'pinceau': _CatMeta(Icons.brush_rounded, Color(0xFF8B5CF6)),
    'carrelage': _CatMeta(Icons.grid_view_rounded, Color(0xFF64748B)),
    'menuiserie': _CatMeta(Icons.carpenter_rounded, Color(0xFFD97706)),
    'tondeuse': _CatMeta(Icons.grass_rounded, Color(0xFF16A34A)),
    'elagage': _CatMeta(Icons.forest_rounded, Color(0xFF92400E)),
    'balai': _CatMeta(Icons.cleaning_services_rounded, Color(0xFF06B6D4)),
    'nettoyage': _CatMeta(Icons.cleaning_services_rounded, Color(0xFF06B6D4)),
    'demenagement': _CatMeta(Icons.local_shipping_rounded, Color(0xFFF59E0B)),
    'escalier': _CatMeta(Icons.stairs_rounded, Color(0xFF92400E)),
    'marteau': _CatMeta(Icons.build_rounded, Color(0xFFB91C1C)),
    'frigo': _CatMeta(Icons.kitchen_rounded, Color(0xFF06B6D4)),
    'ordinateur': _CatMeta(Icons.computer_rounded, Color(0xFF1D4ED8)),
    'domotique': _CatMeta(Icons.home_rounded, Color(0xFF0891B2)),
    'assistance': _CatMeta(Icons.people_rounded, Color(0xFFF97316)),
    'enfant': _CatMeta(Icons.child_care_rounded, Color(0xFFF97316)),
    'animal': _CatMeta(Icons.pets_rounded, Color(0xFFEC4899)),
    'toilettage': _CatMeta(Icons.pets_rounded, Color(0xFFEC4899)),
    'cours': _CatMeta(Icons.school_rounded, Color(0xFF4F46E5)),
    'sport': _CatMeta(Icons.fitness_center_rounded, Color(0xFF16A34A)),
    'ciseaux': _CatMeta(Icons.content_cut_rounded, Color(0xFFBE185D)),
    'massage': _CatMeta(Icons.spa_rounded, Color(0xFF7C3AED)),
    'photo': _CatMeta(Icons.camera_alt_rounded, Color(0xFF1D4ED8)),
    'musique': _CatMeta(Icons.music_note_rounded, Color(0xFF7C3AED)),
    'voiture': _CatMeta(Icons.directions_car_rounded, Color(0xFF64748B)),
    'lavage-auto': _CatMeta(Icons.local_car_wash_rounded, Color(0xFF06B6D4)),
    'casserole': _CatMeta(Icons.restaurant_rounded, Color(0xFFF97316)),
    'telephone': _CatMeta(Icons.smartphone_rounded, Color(0xFF1D4ED8)),
    'vitrage': _CatMeta(Icons.window_rounded, Color(0xFF7C3AED)),
    'desinfection': _CatMeta(Icons.pest_control_rounded, Color(0xFF65A30D)),
    'piscine': _CatMeta(Icons.pool_rounded, Color(0xFF0284C7)),
    'arrosage': _CatMeta(Icons.water_rounded, Color(0xFF0369A1)),
    'maison': _CatMeta(Icons.home_rounded, Color(0xFF78716C)),
    'inspection': _CatMeta(Icons.search_rounded, Color(0xFF64748B)),
    'securite': _CatMeta(Icons.security_rounded, Color(0xFF475569)),
    'outils': _CatMeta(Icons.handyman_rounded, Color(0xFF78716C)),
    'multiservices': _CatMeta(Icons.handyman_rounded, Color(0xFFF59E0B)),
    'toiture': _CatMeta(Icons.roofing_rounded, Color(0xFF374151)),
    'maconnerie': _CatMeta(Icons.foundation_rounded, Color(0xFF78716C)),
    'isolation': _CatMeta(Icons.home_work_rounded, Color(0xFF78350F)),
    'ravalement': _CatMeta(
      Icons.home_repair_service_rounded,
      Color(0xFF78716C),
    ),
    'sol-souple': _CatMeta(Icons.layers_rounded, Color(0xFF64748B)),
    'tapisserie-deco': _CatMeta(Icons.wallpaper_rounded, Color(0xFF8B5CF6)),
    'metallier': _CatMeta(Icons.fence_rounded, Color(0xFF475569)),
    'stores-volets': _CatMeta(Icons.blinds_rounded, Color(0xFF64748B)),
    'placo': _CatMeta(Icons.wallpaper_rounded, Color(0xFF78716C)),
    'etancheite': _CatMeta(Icons.water_drop_rounded, Color(0xFF0284C7)),
    'cloture': _CatMeta(Icons.fence_rounded, Color(0xFF475569)),
    'forage': _CatMeta(Icons.water_drop_rounded, Color(0xFF0369A1)),
    'demoussage': _CatMeta(Icons.cleaning_services_rounded, Color(0xFF16A34A)),
    'taille-haies': _CatMeta(Icons.content_cut_rounded, Color(0xFF22C55E)),
    'engazonnement': _CatMeta(Icons.grass_rounded, Color(0xFF22C55E)),
    'potager': _CatMeta(Icons.eco_rounded, Color(0xFF16A34A)),
    'bassin': _CatMeta(Icons.water_rounded, Color(0xFF0284C7)),
    'repassage': _CatMeta(Icons.iron_rounded, Color(0xFFDB2777)),
    'courses': _CatMeta(Icons.shopping_cart_rounded, Color(0xFFF59E0B)),
    'conciergerie': _CatMeta(Icons.key_rounded, Color(0xFF64748B)),
    'aide-quotidien': _CatMeta(Icons.people_rounded, Color(0xFFF97316)),
    'traiteur': _CatMeta(Icons.restaurant_rounded, Color(0xFFF97316)),
    'animation': _CatMeta(Icons.celebration_rounded, Color(0xFFEC4899)),
    'deco-fetes': _CatMeta(Icons.celebration_rounded, Color(0xFFEC4899)),
    'antenne': _CatMeta(Icons.tv_rounded, Color(0xFF1D4ED8)),
    'couture': _CatMeta(Icons.content_cut_rounded, Color(0xFFEC4899)),
    'debarras': _CatMeta(Icons.delete_rounded, Color(0xFF64748B)),
    'montage-velo': _CatMeta(Icons.directions_bike_rounded, Color(0xFF22C55E)),
    'home-staging': _CatMeta(Icons.home_rounded, Color(0xFF8B5CF6)),
    'rideaux': _CatMeta(Icons.door_sliding_rounded, Color(0xFF8B5CF6)),
    'vmc': _CatMeta(Icons.air_rounded, Color(0xFF06B6D4)),
    'luminaires': _CatMeta(Icons.lightbulb_rounded, Color(0xFFF59E0B)),
    'pressing': _CatMeta(
      Icons.local_laundry_service_rounded,
      Color(0xFF7C3AED),
    ),
    'gaz-cuisson': _CatMeta(
      Icons.local_fire_department_rounded,
      Color(0xFFDC2626),
    ),
    'soudure': _CatMeta(Icons.construction_rounded, Color(0xFF78716C)),

    // Additional slugs from fixtures/admin
    'plomberie': _CatMeta(Icons.water_drop_rounded, Color(0xFF3B82F6)),
    'electricite': _CatMeta(Icons.bolt_rounded, Color(0xFFF59E0B)),
    'informatique': _CatMeta(Icons.computer_rounded, Color(0xFF1D4ED8)),
    'wifi': _CatMeta(Icons.wifi_rounded, Color(0xFF0891B2)),
    'television': _CatMeta(Icons.tv_rounded, Color(0xFF1D4ED8)),
    'menage': _CatMeta(Icons.cleaning_services_rounded, Color(0xFF06B6D4)),
    'peinture': _CatMeta(Icons.brush_rounded, Color(0xFF8B5CF6)),
    'jardinage': _CatMeta(Icons.yard_rounded, Color(0xFF22C55E)),
    'serrurerie': _CatMeta(Icons.lock_rounded, Color(0xFF64748B)),
    'coiffure': _CatMeta(Icons.content_cut_rounded, Color(0xFFBE185D)),
    'esthetique': _CatMeta(
      Icons.face_retouching_natural_rounded,
      Color(0xFFEC4899),
    ),
    'baby-sitting': _CatMeta(Icons.child_care_rounded, Color(0xFFF97316)),
    'aide-devoirs': _CatMeta(Icons.menu_book_rounded, Color(0xFF4F46E5)),
    'administratif': _CatMeta(Icons.description_rounded, Color(0xFF64748B)),
    'repas': _CatMeta(Icons.restaurant_rounded, Color(0xFFF97316)),
    'cuisine': _CatMeta(Icons.restaurant_rounded, Color(0xFFF97316)),
    'chef': _CatMeta(Icons.soup_kitchen_rounded, Color(0xFFF59E0B)),
    'livraison': _CatMeta(Icons.local_shipping_rounded, Color(0xFFF59E0B)),
    'blanchisserie': _CatMeta(
      Icons.local_laundry_service_rounded,
      Color(0xFF7C3AED),
    ),
    'aide_domicile': _CatMeta(Icons.people_rounded, Color(0xFFF97316)),
    'renovation-sdb': _CatMeta(Icons.bathtub_rounded, Color(0xFF0369A1)),
    'parquet': _CatMeta(Icons.format_paint_rounded, Color(0xFFB45309)),
    'bricolage': _CatMeta(Icons.build_rounded, Color(0xFFB91C1C)),
    'montage-meubles': _CatMeta(Icons.chair_rounded, Color(0xFF92400E)),
    'vitrerie': _CatMeta(Icons.window_rounded, Color(0xFF7C3AED)),
    'nettoyage-vitres': _CatMeta(Icons.window_rounded, Color(0xFF7C3AED)),
    'desinsectisation': _CatMeta(Icons.pest_control_rounded, Color(0xFF65A30D)),
    'lavage-tapis': _CatMeta(Icons.layers_rounded, Color(0xFFBE185D)),
    'garde-animaux': _CatMeta(Icons.pets_rounded, Color(0xFFEC4899)),
    'compagnie': _CatMeta(Icons.people_rounded, Color(0xFFEC4899)),
    'rangement': _CatMeta(Icons.inventory_2_rounded, Color(0xFF7C3AED)),
    'elagation': _CatMeta(Icons.forest_rounded, Color(0xFF92400E)),
    'elamage': _CatMeta(Icons.forest_rounded, Color(0xFF92400E)),
    'tonte-pelouse': _CatMeta(Icons.grass_rounded, Color(0xFF16A34A)),
    'engazonnement': _CatMeta(Icons.grass_rounded, Color(0xFF22C55E)),
  };

  static IconData icon(String slug) => _map[slug]?.icon ?? _defaultIcon;
  static Color color(String slug) => _map[slug]?.color ?? _defaultColor;

  static IconData resolve(String slug) {
    final normalizedSlug = slug.toLowerCase().trim();
    if (_map.containsKey(normalizedSlug)) {
      return _map[normalizedSlug]!.icon;
    }
    return _defaultIcon;
  }
}

class _CatMeta {
  final IconData icon;
  final Color color;
  const _CatMeta(this.icon, this.color);
}
