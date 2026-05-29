import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../shared/geo_utils.dart';
import '../../shared/services/nominatim_geocode.dart';
import '../../shared/widgets/babifix_osm_map.dart';

/// Résultat retourné par le picker d'adresse.
class PickedAddress {
  const PickedAddress({
    required this.label,
    required this.latitude,
    required this.longitude,
  });
  final String label;
  final double latitude;
  final double longitude;
}

/// Écran plein écran « Adresse d'intervention » : carte OSM interactive,
/// recherche d'adresse, reverse-géocode automatique du pin, bouton « Utiliser
/// cette adresse ». Retourne un [PickedAddress] via Navigator.pop.
class AddressMapPickerScreen extends StatefulWidget {
  const AddressMapPickerScreen({
    super.key,
    this.initial,
    this.initialAddress,
  });

  /// Point de départ (sinon Abidjan).
  final LatLng? initial;

  /// Adresse pré-saisie (affichée dans la barre de recherche).
  final String? initialAddress;

  @override
  State<AddressMapPickerScreen> createState() => _AddressMapPickerScreenState();
}

class _AddressMapPickerScreenState extends State<AddressMapPickerScreen> {
  late LatLng _pin;
  late final TextEditingController _searchCtrl;
  Timer? _searchDebounce;
  Timer? _reverseDebounce;
  List<NominatimPlace> _suggestions = [];
  bool _searching = false;
  bool _resolving = false;
  bool _locatingMe = false; // auto-localisation à l'ouverture
  String _resolvedAddress = '';

  @override
  void initState() {
    super.initState();
    _pin = widget.initial ?? BabifixOsmLocationPicker.defaultCenter;
    _searchCtrl = TextEditingController(text: widget.initialAddress ?? '');
    // Si aucune position de départ fournie, on auto-localise sur le GPS.
    if (widget.initial == null) {
      _autoLocate();
    } else {
      _scheduleReverse();
    }
  }

  Future<void> _autoLocate() async {
    setState(() => _locatingMe = true);
    try {
      // Demande la permission si nécessaire.
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) setState(() => _locatingMe = false);
        _scheduleReverse(); // on garde Abidjan par défaut
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      // Garde-fou : si la position est hors Côte d'Ivoire (cas typique d'un
      // émulateur qui renvoie Mountain View), on retombe sur Abidjan.
      final LatLng target = isInCotedIvoire(pos.latitude, pos.longitude)
          ? LatLng(pos.latitude, pos.longitude)
          : const LatLng(kAbidjanLat, kAbidjanLon);
      setState(() {
        _pin = target;
        _locatingMe = false;
      });
      _scheduleReverse();
    } catch (_) {
      if (mounted) setState(() => _locatingMe = false);
      _scheduleReverse();
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _reverseDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onPinMoved(LatLng p) {
    setState(() {
      _pin = p;
      _resolvedAddress = '';
      _suggestions = [];
    });
    _scheduleReverse();
  }

  void _scheduleReverse() {
    _reverseDebounce?.cancel();
    _reverseDebounce = Timer(const Duration(milliseconds: 400), _doReverse);
  }

  Future<void> _doReverse() async {
    // Reverse geocoding non implémenté (nominatim_geocode n'expose que nominatimSearch).
    // Branche-toi ici quand tu ajouteras une fonction `nominatimReverse(lat, lon)`.
    if (!mounted) return;
    setState(() {
      _resolving = false;
      _resolvedAddress = '${_pin.latitude.toStringAsFixed(5)}, ${_pin.longitude.toStringAsFixed(5)}';
    });
  }

  void _onSearchChanged(String q) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      if (q.trim().length < 3) {
        if (mounted) setState(() => _suggestions = []);
        return;
      }
      setState(() => _searching = true);
      final results = await nominatimSearch(q);
      if (!mounted) return;
      setState(() {
        _searching = false;
        _suggestions = results;
      });
    });
  }

  void _selectSuggestion(NominatimPlace p) {
    setState(() {
      _pin = LatLng(p.latitude, p.longitude);
      _resolvedAddress = p.displayName;
      _suggestions = [];
      _searchCtrl.text = p.displayName;
    });
  }

  void _confirm() {
    if (_resolvedAddress.isEmpty) return;
    Navigator.of(context).pop(
      PickedAddress(
        label: _resolvedAddress,
        latitude: _pin.latitude,
        longitude: _pin.longitude,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF050D1A) : const Color(0xFFF0F6FF);
    final cardBg = isDark ? const Color(0xFF0A1628) : Colors.white;
    final text = isDark ? Colors.white : const Color(0xFF0F172A);
    final sub = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final brand = const Color(0xFF4CC9F0);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        foregroundColor: text,
        title: const Text(
          "Adresse d'intervention",
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Retour',
        ),
      ),
      body: Stack(
        children: [
          // ── Carte plein écran ─────────────────────────────────────────────
          Positioned.fill(
            bottom: 180, // place pour le panneau bas
            top: 70,     // place pour la barre de recherche
            child: BabifixOsmLocationPicker(
              marker: _pin,
              onMarkerMoved: _onPinMoved,
              height: double.infinity,
            ),
          ),

          // ── Overlay « auto-localisation en cours » (pro, animé) ──────────
          if (_locatingMe)
            Positioned(
              top: 70,
              left: 12,
              right: 12,
              child: IgnorePointer(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 300),
                  builder: (_, t, child) => Opacity(opacity: t, child: child),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: brand.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Row(
                      children: [
                        SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Localisation en cours…',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // ── Barre de recherche + suggestions ──────────────────────────────
          Positioned(
            top: 8,
            left: 12,
            right: 12,
            child: AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: Column(
                children: [
                  Material(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(14),
                    elevation: 4,
                    shadowColor: Colors.black26,
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: _onSearchChanged,
                      style: TextStyle(color: text),
                      decoration: InputDecoration(
                        hintText: 'Rechercher une adresse (Cocody, Bassam…)',
                        hintStyle: TextStyle(color: sub),
                        prefixIcon: _searching
                            ? const Padding(
                                padding: EdgeInsets.all(14),
                                child: SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : Icon(Icons.search_rounded, color: brand),
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _suggestions = []);
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14,
                        ),
                      ),
                    ),
                  ),
                  if (_suggestions.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const ClampingScrollPhysics(),
                        padding: EdgeInsets.zero,
                        itemCount: _suggestions.length.clamp(0, 6),
                        separatorBuilder: (_, __) => Divider(
                          height: 1, color: sub.withValues(alpha: 0.15),
                        ),
                        itemBuilder: (_, i) {
                          final p = _suggestions[i];
                          return ListTile(
                            dense: true,
                            leading: Icon(Icons.place_rounded, color: brand, size: 20),
                            title: Text(
                              p.displayName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: text, fontSize: 13),
                            ),
                            onTap: () => _selectSuggestion(p),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ── Panneau bas : adresse résolue + bouton confirmer ─────────────
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: EdgeInsets.fromLTRB(
                16, 16, 16, MediaQuery.paddingOf(context).bottom + 16,
              ),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 20,
                    offset: const Offset(0, -6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.place_rounded, color: brand, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Adresse sélectionnée',
                        style: TextStyle(
                          color: brand, fontWeight: FontWeight.w800, fontSize: 12,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: _resolving
                        ? Row(
                            key: const ValueKey('loading'),
                            children: [
                              const SizedBox(
                                width: 14, height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Recherche de l\'adresse…',
                                style: TextStyle(color: sub, fontSize: 13),
                              ),
                            ],
                          )
                        : Text(
                            key: ValueKey(_resolvedAddress),
                            _resolvedAddress.isEmpty
                                ? 'Touchez la carte ou recherchez une adresse'
                                : _resolvedAddress,
                            style: TextStyle(
                              color: text,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              height: 1.35,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: (_resolvedAddress.isNotEmpty && !_resolving)
                          ? _confirm
                          : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: brand,
                        disabledBackgroundColor: brand.withValues(alpha: 0.35),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.check_circle_rounded, color: Colors.white),
                      label: const Text(
                        'Utiliser cette adresse',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
