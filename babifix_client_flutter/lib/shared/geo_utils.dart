/// Utilitaires géographiques BABIFIX (zone d'opération = Côte d'Ivoire).
///
/// Permet d'écarter les coordonnées clairement hors-CI — typiquement
/// renvoyées par les émulateurs (Mountain View, lat≈37°) — pour ne pas
/// fausser les calculs de distance et l'expérience cartographique.
///
/// La validation utilise un polygone détaillé (~32 sommets) des frontières
/// de la Côte d'Ivoire avec un algorithme de ray-casting, précédé d'un
/// pré-filtre par boîte englobante pour les cas triviaux.

/// Boîte englobante (large) — pré-filtre rapide avant le ray-casting.
const double kCiMinLat = 4.0;
const double kCiMaxLat = 11.0;
const double kCiMinLon = -9.0;
const double kCiMaxLon = -2.0;

/// Coordonnées par défaut : centre d'Abidjan (Plateau).
const double kAbidjanLat = 5.354;
const double kAbidjanLon = -3.989;

/// Polygone simplifié des frontières de la Côte d'Ivoire (~32 sommets,
/// sens horaire depuis le sud-ouest). Sources : OSM / Natural Earth.
///
/// Chaque paire est (latitude, longitude).
const List<List<double>> kCiBorder = [
  [4.357, -7.540], // Tabou
  [4.384, -7.683],
  [4.420, -7.917],
  [4.477, -8.194],
  [4.556, -8.424],
  [4.622, -8.537],
  [4.721, -8.584],
  [4.856, -8.600], // frontière Liberia (côte)
  [6.451, -8.660], // tripoint Liberia/Guinée
  [7.550, -8.500], // frontière Guinée
  [8.500, -8.600], // tripoint Guinée/Mali
  [9.362, -8.536], // frontière Mali
  [10.175, -7.985],
  [10.686, -6.832],
  [10.755, -5.928], // tripoint Mali/Burkina
  [10.745, -5.190], // frontière Burkina
  [10.385, -4.430],
  [9.718, -4.241],
  [9.096, -3.805],
  [8.581, -3.000], // tripoint Burkina/Ghana
  [7.772, -2.590], // frontière Ghana
  [6.949, -2.659],
  [6.214, -3.086],
  [5.527, -2.674],
  [5.131, -2.586],
  [5.108, -3.147], // coin SE (Ghana)
  [5.058, -3.550],
  [4.921, -3.997],
  [4.886, -4.498],
  [4.799, -5.249],
  [4.698, -5.755],
  [4.662, -6.754],
  [4.537, -7.192],
];

bool isInCotedIvoire(double lat, double lon) {
  // Pré-filtre rapide : boîte englobante
  if (lat < kCiMinLat || lat > kCiMaxLat || lon < kCiMinLon || lon > kCiMaxLon) {
    return false;
  }

  // Ray-casting algorithm : on compte les intersections entre une demi-droite
  // vers l'est et les arêtes du polygone. Si le nombre est impair → inside.
  bool inside = false;
  int j = kCiBorder.length - 1;
  for (int i = 0; i < kCiBorder.length; i++) {
    final latI = kCiBorder[i][0], lonI = kCiBorder[i][1];
    final latJ = kCiBorder[j][0], lonJ = kCiBorder[j][1];
    if ((lonI > lon) != (lonJ > lon)) {
      final intersectLat = latJ + (latI - latJ) * (lon - lonJ) / (lonI - lonJ);
      if (lat < intersectLat) {
        inside = !inside;
      }
    }
    j = i;
  }
  return inside;
}
