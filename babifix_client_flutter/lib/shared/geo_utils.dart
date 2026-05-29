/// Utilitaires géographiques BABIFIX (zone d'opération = Côte d'Ivoire).
///
/// Permet d'écarter les coordonnées clairement hors-CI — typiquement
/// renvoyées par les émulateurs (Mountain View, lat≈37°) — pour ne pas
/// fausser les calculs de distance et l'expérience cartographique.

/// Boîte englobante (très large) de la Côte d'Ivoire :
///   latitude  : 4.0° N  → 11.0° N
///   longitude : -9.0° W → -2.0° W
const double kCiMinLat = 4.0;
const double kCiMaxLat = 11.0;
const double kCiMinLon = -9.0;
const double kCiMaxLon = -2.0;

/// Coordonnées par défaut : centre d'Abidjan (Plateau).
const double kAbidjanLat = 5.354;
const double kAbidjanLon = -3.989;

bool isInCotedIvoire(double lat, double lon) {
  return lat >= kCiMinLat &&
      lat <= kCiMaxLat &&
      lon >= kCiMinLon &&
      lon <= kCiMaxLon;
}
