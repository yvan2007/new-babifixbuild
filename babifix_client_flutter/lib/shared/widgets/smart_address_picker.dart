/// SmartAddressPicker — Sélecteur d'adresse pro pour BABIFIX.
///
/// Flow :
/// 1. À l'ouverture, l'app détecte automatiquement la position GPS
///    (avec demande de permission silencieuse).
/// 2. Reverse-geocoding via Nominatim (OpenStreetMap, gratuit) →
///    affiche l'adresse trouvée + une carte centrée dessus.
/// 3. L'utilisateur peut :
///    - Valider directement « Utiliser cette adresse »
///    - Déplacer le marker sur la carte (drag)
///    - Lancer une recherche textuelle (autocomplete Nominatim)
///
/// Retourne un `PickedAddress(label, lat, lon)` via `Navigator.pop`.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'babifix_ring_loader.dart';
import 'babifix_snackbar.dart';

class PickedAddress {
  final String label;
  final double lat;
  final double lon;
  const PickedAddress(
      {required this.label, required this.lat, required this.lon});

  Map<String, dynamic> toJson() => {
        'address': label,
        'latitude': lat,
        'longitude': lon,
      };
}

class SmartAddressPicker extends StatefulWidget {
  const SmartAddressPicker({
    super.key,
    this.initialLabel,
    this.initialLat,
    this.initialLon,
  });

  final String? initialLabel;
  final double? initialLat;
  final double? initialLon;

  @override
  State<SmartAddressPicker> createState() => _SmartAddressPickerState();
}

class _SmartAddressPickerState extends State<SmartAddressPicker> {
  static const _kCyan = Color(0xFF4CC9F0);
  static const _kCyanDark = Color(0xFF22A6D6);
  static const _kNavy = Color(0xFF0B1B34);
  static const _kError = Color(0xFFEF4444);
  static const _kSuccess = Color(0xFF22C55E);

  final _mapCtrl = MapController();
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;

  LatLng? _target;
  String _addressLabel = '';
  bool _detecting = false;
  bool _searching = false;
  bool _reverseInProgress = false;
  String? _error;
  List<_SearchHit> _hits = [];

  static const _abidjan = LatLng(5.345317, -4.024429);

  @override
  void initState() {
    super.initState();
    if (widget.initialLat != null && widget.initialLon != null) {
      _target = LatLng(widget.initialLat!, widget.initialLon!);
      _addressLabel = widget.initialLabel ?? '';
    } else {
      // Détection auto à l'ouverture.
      WidgetsBinding.instance.addPostFrameCallback((_) => _detectCurrent());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ── GPS courant ─────────────────────────────────────────────────────────────
  Future<void> _detectCurrent() async {
    setState(() {
      _detecting = true;
      _error = null;
    });
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw 'Activez la localisation dans les paramètres du téléphone.';
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        throw 'Permission de localisation refusée.';
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      final ll = LatLng(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() => _target = ll);
      _mapCtrl.move(ll, 16.0);
      await _reverseGeocode(ll);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _target ??= _abidjan;
      });
      _mapCtrl.move(_target!, 13.0);
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  // ── Reverse geocoding via Nominatim ────────────────────────────────────────
  // Construit un libellé lisible « Quartier, Ville » plutôt qu'un display_name
  // verbeux. Aucune coordonnée brute n'est montrée à l'utilisateur.
  static String _shortPlaceLabel(Map<String, dynamic> addr) {
    String pick(List<String> keys) {
      for (final k in keys) {
        final v = (addr[k] ?? '').toString().trim();
        if (v.isNotEmpty) return v;
      }
      return '';
    }

    final quartier = pick([
      'suburb',
      'neighbourhood',
      'quarter',
      'city_district',
      'residential',
      'hamlet',
    ]);
    final ville = pick(['city', 'town', 'municipality', 'village', 'county']);
    final region = pick(['state', 'region']);
    final parts = <String>[];
    if (quartier.isNotEmpty) parts.add(quartier);
    if (ville.isNotEmpty && ville != quartier) parts.add(ville);
    if (parts.isEmpty && region.isNotEmpty) parts.add(region);
    return parts.join(', ');
  }

  Future<void> _reverseGeocode(LatLng pos) async {
    setState(() => _reverseInProgress = true);
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?format=jsonv2&addressdetails=1&accept-language=fr&zoom=16'
        '&lat=${pos.latitude}&lon=${pos.longitude}',
      );
      final res = await http.get(uri, headers: {
        'User-Agent': 'BABIFIX-App/1.0 (contact@babifix.ci)',
      });
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body) as Map<String, dynamic>;
        if (!mounted) return;
        final addr = (d['address'] as Map<String, dynamic>?) ?? const {};
        var label = _shortPlaceLabel(addr);
        if (label.isEmpty) {
          label = (d['display_name'] ?? '')
              .toString()
              .split(',')
              .take(2)
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .join(', ');
        }
        setState(() => _addressLabel = label);
      }
    } catch (_) {
      // Pas grave, l'utilisateur garde son lat/lon, pas de label.
    } finally {
      if (mounted) setState(() => _reverseInProgress = false);
    }
  }

  // ── Recherche autocomplete via Nominatim ───────────────────────────────────
  void _onSearchChanged(String q) {
    _debounce?.cancel();
    final term = q.trim();
    if (term.length < 3) {
      setState(() => _hits = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 380), () async {
      await _searchOnce(term);
    });
  }

  Future<void> _searchOnce(String term) async {
    setState(() => _searching = true);
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?format=jsonv2&addressdetails=1&limit=8&accept-language=fr'
        '&countrycodes=ci' // priorité Côte d'Ivoire
        '&q=${Uri.encodeComponent(term)}',
      );
      final res = await http.get(uri, headers: {
        'User-Agent': 'BABIFIX-App/1.0 (contact@babifix.ci)',
      });
      if (res.statusCode == 200) {
        final raw = jsonDecode(res.body) as List<dynamic>;
        final hits = raw
            .map((j) => _SearchHit.fromJson(j as Map<String, dynamic>))
            .toList();
        if (!mounted) return;
        setState(() => _hits = hits);
      }
    } catch (_) {
      // silencieux
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _selectHit(_SearchHit h) {
    setState(() {
      _target = LatLng(h.lat, h.lon);
      _addressLabel = h.label;
      _hits = [];
      _searchCtrl.text = '';
    });
    _searchFocus.unfocus();
    _mapCtrl.move(_target!, 16.0);
  }

  void _validate() {
    if (_target == null) return;
    if (_addressLabel.trim().isEmpty) {
      showBabifixToast(
        context,
        type: BabifixToastType.error,
        message: 'Adresse introuvable. Réessayez de localiser.',
      );
      return;
    }
    Navigator.of(context).pop(PickedAddress(
      label: _addressLabel,
      lat: _target!.latitude,
      lon: _target!.longitude,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Scaffold(
      backgroundColor: isLight ? const Color(0xFFF1F5F9) : _kNavy,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Adresse d\'intervention',
          style: TextStyle(
            color: isLight ? _kNavy : Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
        iconTheme: IconThemeData(color: isLight ? _kNavy : Colors.white),
      ),
      body: Stack(
        children: [
          // Carte plein écran
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapCtrl,
              options: MapOptions(
                initialCenter: _target ?? _abidjan,
                initialZoom: _target != null ? 16.0 : 12.0,
                minZoom: 4,
                maxZoom: 19,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
                onTap: (_, pos) async {
                  setState(() => _target = pos);
                  await _reverseGeocode(pos);
                },
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'ci.babifix.client',
                  maxZoom: 19,
                ),
                if (_target != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _target!,
                        width: 48,
                        height: 48,
                        child: _MarkerPin(color: _kCyan),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // Recherche en haut
          Positioned(
            top: 8,
            left: 16,
            right: 16,
            child: _buildSearchCard(isLight),
          ),

          // Bouton "Ma position" flottant
          Positioned(
            right: 16,
            bottom: 180,
            child: FloatingActionButton(
              heroTag: 'gps_locate',
              backgroundColor: Colors.white,
              foregroundColor: _kCyan,
              elevation: 4,
              onPressed: _detecting ? null : _detectCurrent,
              child: _detecting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: BabifixRingLoader.cyan(size: 28),
                    )
                  : const Icon(Icons.my_location_rounded),
            ),
          ),

          // Panneau bas : adresse + bouton valider
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _buildBottomCard(isLight),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchCard(bool isLight) {
    final bg = isLight ? Colors.white : const Color(0xFF152A45);
    final textColor = isLight ? _kNavy : Colors.white;
    final hintColor = isLight ? const Color(0xFF94A3B8) : Colors.white70;
    return Material(
      color: bg,
      elevation: 6,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(14),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(
              children: [
                Icon(Icons.search_rounded, color: hintColor, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    focusNode: _searchFocus,
                    onChanged: _onSearchChanged,
                    style: TextStyle(
                        color: textColor, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: 'Rechercher une adresse, un quartier…',
                      hintStyle: TextStyle(color: hintColor, fontSize: 13.5),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                if (_searching)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: BabifixRingLoader.cyan(size: 28),
                  )
                else if (_searchCtrl.text.isNotEmpty)
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: hintColor),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _hits = []);
                    },
                  ),
              ],
            ),
          ),
          if (_hits.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 280),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: isLight
                        ? const Color(0xFFE2E8F0)
                        : Colors.white12,
                  ),
                ),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _hits.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  thickness: 0.5,
                  color: isLight
                      ? const Color(0xFFF1F5F9)
                      : Colors.white10,
                ),
                itemBuilder: (_, i) {
                  final h = _hits[i];
                  return ListTile(
                    dense: true,
                    leading: Icon(Icons.place_outlined, color: _kCyan),
                    title: Text(
                      h.shortLabel,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      h.subLabel,
                      style: TextStyle(color: hintColor, fontSize: 11.5),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _selectHit(h),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomCard(bool isLight) {
    final bg = isLight ? Colors.white : const Color(0xFF152A45);
    final textColor = isLight ? _kNavy : Colors.white;
    final hintColor = isLight ? const Color(0xFF64748B) : Colors.white70;
    return Material(
      color: bg,
      elevation: 8,
      shadowColor: Colors.black38,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _kCyan.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.place_rounded,
                      color: _kCyan, size: 18),
                ),
                const SizedBox(width: 10),
                Text(
                  'Adresse sélectionnée',
                  style: TextStyle(
                    color: hintColor,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const Spacer(),
                if (_reverseInProgress)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: BabifixRingLoader.cyan(size: 28),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _addressLabel.isEmpty
                  ? 'Tapez sur la carte ou recherchez une adresse'
                  : _addressLabel,
              style: TextStyle(
                color: textColor,
                fontSize: 14,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (_target != null && _addressLabel.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.check_circle_rounded,
                      color: _kSuccess, size: 14),
                  const SizedBox(width: 5),
                  Text(
                    'Position localisée sur la carte',
                    style: TextStyle(color: hintColor, fontSize: 11.5),
                  ),
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _kError.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: _kError, size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                            color: _kError, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                onPressed: (_target != null && _addressLabel.isNotEmpty)
                    ? _validate
                    : null,
                icon: const Icon(Icons.check_circle_rounded, size: 18),
                label: const Text(
                  'Utiliser cette adresse',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: _kSuccess,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchHit {
  final String label;
  final String shortLabel;
  final String subLabel;
  final double lat;
  final double lon;

  _SearchHit({
    required this.label,
    required this.shortLabel,
    required this.subLabel,
    required this.lat,
    required this.lon,
  });

  factory _SearchHit.fromJson(Map<String, dynamic> j) {
    final disp = (j['display_name'] ?? '').toString();
    final parts = disp.split(',');
    final shortLabel = parts.isNotEmpty ? parts.first.trim() : disp;
    final subLabel = parts.length > 1
        ? parts.sublist(1).join(',').trim()
        : '';
    return _SearchHit(
      label: disp,
      shortLabel: shortLabel,
      subLabel: subLabel,
      lat: double.tryParse((j['lat'] ?? '0').toString()) ?? 0,
      lon: double.tryParse((j['lon'] ?? '0').toString()) ?? 0,
    );
  }
}

class _MarkerPin extends StatelessWidget {
  final Color color;
  const _MarkerPin({required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.5),
                blurRadius: 12,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(Icons.place_rounded, color: Colors.white, size: 22),
        ),
      ],
    );
  }
}
