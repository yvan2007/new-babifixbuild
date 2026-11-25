/// SmartAddressPicker (Prestataire) : selecteur interactif de zone et position.
/// Carte plein ecran + recherche + communes rapides + bouton GPS propre.
/// Retourne un PickedProLocation(label, lat, lon) via Navigator.pop.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/nominatim_geocode.dart';
import '../services/smart_gps.dart';
import 'babifix_ring_loader.dart';

class PickedProLocation {
  const PickedProLocation({
    required this.label,
    required this.lat,
    required this.lon,
  });

  final String label;
  final double lat;
  final double lon;
}

class SmartProAddressPicker extends StatefulWidget {
  const SmartProAddressPicker({
    super.key,
    this.initialLat,
    this.initialLon,
    this.initialLabel,
    this.title = 'Ma position sur la carte',
    this.confirmLabel = 'Utiliser cette position',
  });

  final double? initialLat;
  final double? initialLon;
  final String? initialLabel;
  final String title;
  final String confirmLabel;

  @override
  State<SmartProAddressPicker> createState() => _SmartProAddressPickerState();
}

class _SmartProAddressPickerState extends State<SmartProAddressPicker> {
  static const _kNavy = Color(0xFF0A1628);
  static const _kCyan = Color(0xFF0284C7);
  static const _kSuccess = Color(0xFF10B981);
  static const _kWarn = Color(0xFFD97706);

  static const _abidjan = LatLng(kCivAbidjanLat, kCivAbidjanLon);

  static const List<NominatimPlace> _kQuickChips = [
    NominatimPlace(latitude: 5.3600, longitude: -3.9870, displayName: 'Cocody · Deux Plateaux, Abidjan'),
    NominatimPlace(latitude: 5.3735, longitude: -3.9580, displayName: 'Riviera · Cocody, Abidjan'),
    NominatimPlace(latitude: 5.3980, longitude: -3.9885, displayName: 'Angre · Cocody, Abidjan'),
    NominatimPlace(latitude: 5.3260, longitude: -4.0205, displayName: 'Plateau · Centre, Abidjan'),
    NominatimPlace(latitude: 5.3035, longitude: -3.9825, displayName: 'Marcory · Zone 4, Abidjan'),
    NominatimPlace(latitude: 5.3010, longitude: -4.0080, displayName: 'Treichville, Abidjan'),
    NominatimPlace(latitude: 5.2970, longitude: -3.9550, displayName: 'Koumassi, Abidjan'),
    NominatimPlace(latitude: 5.3480, longitude: -4.0790, displayName: 'Yopougon, Abidjan'),
    NominatimPlace(latitude: 5.4190, longitude: -4.0190, displayName: 'Abobo, Abidjan'),
    NominatimPlace(latitude: 5.3560, longitude: -3.8880, displayName: 'Bingerville, Grand Abidjan'),
    NominatimPlace(latitude: 5.2110, longitude: -3.7380, displayName: 'Grand-Bassam'),
  ];

  static String _chipShortLabel(NominatimPlace c) {
    final left = c.displayName.split('·').first.trim();
    return left.split(',').first.trim();
  }

  final MapController _mapCtrl = MapController();
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  late LatLng _target;
  String _addressLabel = '';
  bool _detecting = false;
  bool _reverseInProgress = false;
  bool _searching = false;
  String? _notice;
  List<NominatimPlace> _hits = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    if (widget.initialLat != null && widget.initialLon != null) {
      _target = LatLng(widget.initialLat!, widget.initialLon!);
      _addressLabel = (widget.initialLabel ?? '').trim();
      if (_addressLabel.isEmpty) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _reverseGeocode(_target));
      }
    } else {
      _target = _abidjan;
      _addressLabel = resolveNearestCivCommune(
        _abidjan.latitude,
        _abidjan.longitude,
      ).displayName;
      WidgetsBinding.instance.addPostFrameCallback((_) => _detectCurrent());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _mapCtrl.dispose();
    super.dispose();
  }

  void _safeMove(LatLng pos, double zoom) {
    try {
      _mapCtrl.move(pos, zoom);
    } catch (_) {}
  }

  Future<void> _detectCurrent({bool userTriggered = false}) async {
    if (_detecting) return;
    setState(() {
      _detecting = true;
      _notice = null;
    });
    try {
      final gps = await acquireSmartGps(forceFresh: userTriggered);
      if (!mounted) return;
      if (gps.hasHardError) {
        setState(() => _notice = gps.friendlyMessage);
        return;
      }
      final ll = gps.position ?? _abidjan;
      setState(() {
        _target = ll;
        _notice = null;
      });
      _safeMove(ll, gps.inCoteIvoire ? 16.0 : 14.5);
      await _reverseGeocode(ll);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  Future<void> _reverseGeocode(LatLng pos) async {
    setState(() => _reverseInProgress = true);
    try {
      final place = await nominatimReverse(pos.latitude, pos.longitude);
      final label = (place?.displayName ?? '').trim();
      if (!mounted) return;
      setState(() {
        _addressLabel = label.isNotEmpty
            ? label
            : resolveNearestCivCommune(pos.latitude, pos.longitude).displayName;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _addressLabel =
            resolveNearestCivCommune(pos.latitude, pos.longitude).displayName;
      });
    } finally {
      if (mounted) setState(() => _reverseInProgress = false);
    }
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    final term = q.trim();
    if (term.length < 2) {
      setState(() => _hits = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 280), () async {
      setState(() => _searching = true);
      try {
        final results = await nominatimSearch(term);
        if (mounted) setState(() => _hits = results);
      } catch (_) {
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  void _selectPlace(NominatimPlace p, {double zoom = 15.0}) {
    final pos = LatLng(p.latitude, p.longitude);
    setState(() {
      _target = pos;
      _addressLabel = p.displayName;
      _hits = [];
      _notice = null;
      _searchCtrl.clear();
    });
    _searchFocus.unfocus();
    _safeMove(pos, zoom);
  }

  void _validate() {
    final label = _addressLabel.trim().isNotEmpty
        ? _addressLabel.trim()
        : resolveNearestCivCommune(_target.latitude, _target.longitude)
            .displayName;
    Navigator.of(context).pop(PickedProLocation(
      label: label,
      lat: _target.latitude,
      lon: _target.longitude,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Scaffold(
      backgroundColor: isLight ? const Color(0xFFF1F5F9) : _kNavy,
      appBar: AppBar(
        backgroundColor: isLight ? Colors.white : _kNavy,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle:
            isLight ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
        title: Text(
          widget.title,
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
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapCtrl,
              options: MapOptions(
                initialCenter: _target,
                initialZoom: 15.0,
                minZoom: 5,
                maxZoom: 19,
                backgroundColor:
                    isLight ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
                onTap: (_, pos) async {
                  setState(() {
                    _target = pos;
                    _notice = null;
                    _hits = [];
                  });
                  _searchFocus.unfocus();
                  await _reverseGeocode(pos);
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: !isLight
                      ? 'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}'
                      : 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}',
                  retinaMode: false,
                  userAgentPackageName: 'ci.babifix.prestataire',
                  maxZoom: 19,
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _target,
                      width: 48,
                      height: 48,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _kSuccess,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: _kSuccess.withValues(alpha: 0.45),
                              blurRadius: 12,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.location_on_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Recherche en haut
          Positioned(
            top: 10,
            left: 14,
            right: 14,
            child: _buildSearchCard(isLight),
          ),

          // Bouton GPS + panneau bas alignes proprement
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: FloatingActionButton.small(
                      heroTag: 'gps_locate_pro',
                      backgroundColor: Colors.white,
                      foregroundColor: _kSuccess,
                      elevation: 5,
                      onPressed: _detecting
                          ? null
                          : () => _detectCurrent(userTriggered: true),
                      child: _detecting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: BabifixRingLoader.cyan(size: 18),
                            )
                          : const Icon(Icons.my_location_rounded, size: 20),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildBottomCard(isLight),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchCard(bool isLight) {
    final bg = isLight ? Colors.white : const Color(0xFF152A45);
    final textColor = isLight ? _kNavy : Colors.white;
    final hintColor = isLight ? const Color(0xFF64748B) : Colors.white70;
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
                      color: textColor,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Rechercher votre commune ou quartier...',
                      hintStyle: TextStyle(color: hintColor, fontSize: 13.5),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                ),
                if (_searching)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: BabifixRingLoader.cyan(size: 18),
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
              constraints: const BoxConstraints(maxHeight: 240),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: isLight ? const Color(0xFFE2E8F0) : Colors.white12,
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
                  color: isLight ? const Color(0xFFF1F5F9) : Colors.white10,
                ),
                itemBuilder: (_, i) {
                  final h = _hits[i];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.place_outlined, color: _kCyan),
                    title: Text(
                      h.displayName,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _selectPlace(h, zoom: 15.5),
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
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: _kSuccess.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.place_rounded,
                      color: _kSuccess, size: 17),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Zone & position choisies',
                        style: TextStyle(
                          color: hintColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        _addressLabel.isEmpty
                            ? 'Touchez la carte ou choisissez une commune'
                            : _addressLabel,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 14,
                          height: 1.3,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (_reverseInProgress)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: BabifixRingLoader.cyan(size: 16),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _kQuickChips.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final c = _kQuickChips[i];
                  final short = _chipShortLabel(c);
                  final addrLow = _addressLabel.toLowerCase();
                  final shortLow = short.toLowerCase();
                  final active = shortLow == 'plateau'
                      ? (addrLow.contains('plateau') && !addrLow.contains('plateaux'))
                      : addrLow.contains(shortLow);
                  return GestureDetector(
                    onTap: () => _selectPlace(c, zoom: 15.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: active
                            ? _kSuccess
                            : (isLight
                                ? const Color(0xFFF1F5F9)
                                : const Color(0xFF0E1D33)),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: active
                              ? _kSuccess
                              : (isLight
                                  ? const Color(0xFFCBD5E1)
                                  : Colors.white24),
                        ),
                      ),
                      child: Text(
                        short,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: active ? Colors.white : textColor,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_notice != null) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: _kWarn.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        color: _kWarn, size: 15),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _notice!,
                        style: const TextStyle(
                          color: _kWarn,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _validate,
                icon: const Icon(Icons.check_circle_rounded, size: 18),
                label: Text(
                  widget.confirmLabel,
                  style: const TextStyle(
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
