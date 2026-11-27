import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../services/babifix_api.dart';
import '../chat/chat_room_screen.dart';
import '../../shared/geo_utils.dart';
import '../../shared/services/nominatim_geocode.dart';
import '../../shared/services/smart_gps.dart';
import '../../shared/widgets/address_search_field.dart';
import '../../shared/widgets/babifix_button.dart';
import '../../shared/widgets/babifix_dynamic_requirements.dart';
import '../../shared/widgets/babifix_osm_map.dart';
import '../../shared/widgets/babifix_page_route.dart';
import '../../shared/widgets/babifix_ring_loader.dart';
import '../../shared/widgets/babifix_sheet.dart';
import '../../shared/widgets/babifix_snackbar.dart';
import '../../shared/widgets/babifix_suggestion_chips.dart';
import '../../shared/widgets/babifix_voice_note.dart';
import '../../shared/widgets/gps_location_card.dart';
import '../../shared/widgets/payment_method_logo.dart';
import '../../user_store.dart';
import '../auth/auth_screen.dart';

/// Palette adaptative (clair sobre par defaut ou sombre selon le theme actif).
class _BookingPalette {
  const _BookingPalette({
    required this.isLight,
    required this.pageBg,
    required this.cardBg,
    required this.softBg,
    required this.border,
    required this.textPrimary,
    required this.textMuted,
    required this.accent,
    required this.accentSoft,
    required this.accentOnFill,
    required this.success,
    required this.danger,
  });

  final bool isLight;
  final Color pageBg;
  final Color cardBg;
  final Color softBg;
  final Color border;
  final Color textPrimary;
  final Color textMuted;
  final Color accent;
  final Color accentSoft;
  final Color accentOnFill;
  final Color success;
  final Color danger;

  factory _BookingPalette.of(BuildContext context) {
    final light = Theme.of(context).brightness == Brightness.light;
    final whiteMode = BabifixDesign.isWhiteMode(context);
    return _BookingPalette(
      isLight: light,
      pageBg: light
          ? (whiteMode ? BabifixDesign.bgWhite : BabifixDesign.bgLight)
          : BabifixDesign.obsidian,
      cardBg: light ? BabifixDesign.bgWhite : BabifixDesign.navySurface,
      softBg: light ? BabifixDesign.bgSoft : BabifixDesign.navyElevated,
      border: light ? BabifixDesign.borderLight : BabifixDesign.borderDark,
      textPrimary: light ? BabifixDesign.textStrongLight : BabifixDesign.textStrongDark,
      textMuted: light ? BabifixDesign.textMutedLight : BabifixDesign.textMutedDark,
      accent: light ? BabifixDesign.cyanDeep : BabifixDesign.cyan,
      accentSoft: light
          ? const Color(0xFFE0F2FE)
          : BabifixDesign.cyan.withValues(alpha: 0.14),
      accentOnFill: light ? Colors.white : BabifixDesign.navy,
      success: light ? BabifixDesign.emeraldForest : const Color(0xFF4ADE80),
      danger: light ? const Color(0xFFB91C1C) : const Color(0xFFFCA5A5),
    );
  }
}

/// Flow de reservation en 4 etapes :
/// 0 -> Besoin  1 -> Adresse  2 -> Disponibilite & paiement  3 -> Confirmation
class BookingFlowScreen extends StatefulWidget {
  const BookingFlowScreen({
    super.key,
    required this.serviceTitle,
    required this.servicePrice,
    this.providerName,
    this.providerPhoto,
    this.providerRating,
    this.providerSpecialite,
    this.providerId,
    this.onConfirm,
  });

  final String serviceTitle;
  final int servicePrice;
  final String? providerName;
  final String? providerPhoto;
  final double? providerRating;
  final String? providerSpecialite;
  final int? providerId;
  final Future<Map<String, dynamic>?> Function(Map<String, dynamic> data)?
      onConfirm;

  @override
  State<BookingFlowScreen> createState() => _BookingFlowScreenState();
}

class _BookingFlowScreenState extends State<BookingFlowScreen> {
  int _step = 0;

  final _problemeCtrl = TextEditingController();
  String _audioProblemeUrl = '';
  bool _audioUploading = false;
  String _videoProblemeUrl = '';
  bool _videoUploading = false;
  String _demandeType = '';

  static const List<(String, String, IconData)> _demandeTypes = [
    ('panne', 'Panne / reparation', Icons.build_rounded),
    ('maintenance', 'Maintenance', Icons.handyman_rounded),
    ('renovation', 'Renovation', Icons.format_paint_rounded),
    ('installation', 'Installation', Icons.add_home_work_rounded),
    ('conseil', 'Devis / conseil', Icons.request_quote_rounded),
    ('autre', 'Autre besoin', Icons.more_horiz_rounded),
  ];

  final _addressCtrl = TextEditingController();
  final _repereCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  bool _submitting = false;
  String _paymentType = 'ESPECES';
  bool _isUrgent = false;
  Map<String, dynamic>? _sosPreview;
  int _alertedSosCount = 0;
  String _disponibilites = '';
  bool _checkingAvailability = false;
  bool? _providerAvailable;
  String _availabilityMessage = '';
  DateTime? _selectedDate;
  List<Map<String, dynamic>> _availableCreneaux = [];
  String _reservationReference = '';

  List<Map<String, dynamic>> _exigTemplate = [];
  String _exigProfil = 'STANDARD';
  final Map<String, dynamic> _reponsesExigences = {};

  LatLng _mapPin = BabifixOsmLocationPicker.defaultCenter;
  bool _mapPinFromUser = false;
  bool _gpsAutoTried = false;
  GpsLocationState _gpsState = GpsLocationState.idle;
  List<Uint8List> _photos = [];
  List<Map<String, dynamic>> _savedAddresses = [];
  dynamic _selectedSavedAddressId;

  static const _steps = ['Besoin', 'Adresse', 'Creneau', 'Envoye'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryAutoLocate());
    _loadSavedAddresses();
    _loadRequirements();
    _loadSosPreview();
  }

  Future<void> _loadSosPreview() async {
    try {
      final token = await BabifixUserStore.getApiToken();
      if (token == null || token.isEmpty) return;
      final uri = Uri.parse(
        '${babifixApiBaseUrl()}/api/client/sos/preview/?title=${Uri.encodeComponent(widget.serviceTitle)}',
      );
      final resp = await http.get(uri, headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200 && mounted) {
        final j = jsonDecode(resp.body) as Map<String, dynamic>;
        setState(() => _sosPreview = j);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _problemeCtrl.dispose();
    _addressCtrl.dispose();
    _repereCtrl.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _onVoiceRecorded(String path, int durationSeconds) async {
    setState(() => _audioUploading = true);
    try {
      final url = await MediaApi.uploadFile(path);
      if (mounted) {
        setState(() {
          _audioProblemeUrl = url;
          _audioUploading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _audioUploading = false);
        showBabifixToast(
          context,
          type: BabifixToastType.error,
          message: 'Envoi de la note vocale echoue.',
        );
      }
    }
  }

  Future<void> _pickVideo(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final XFile? video = await picker.pickVideo(
        source: source,
        maxDuration: const Duration(seconds: 30),
      );
      if (video == null) return;
      setState(() => _videoUploading = true);
      final url = await MediaApi.uploadFile(video.path);
      if (mounted) {
        setState(() {
          _videoProblemeUrl = url;
          _videoUploading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _videoUploading = false);
        showBabifixToast(
          context,
          type: BabifixToastType.error,
          message: 'Envoi de la video echoue.',
        );
      }
    }
  }

  Map<String, dynamic> _buildReponsesExigences() {
    if (_exigTemplate.isEmpty || _reponsesExigences.isEmpty) return {};
    final out = <String, dynamic>{};
    for (final q in _exigTemplate) {
      final key = (q['key'] ?? '').toString();
      if (key.isEmpty) continue;
      final v = _reponsesExigences[key];
      final empty = v == null || (v is String && v.trim().isEmpty);
      if (empty) continue;
      final unit = (q['unit'] ?? '').toString();
      out[key] = {
        'label': (q['label'] ?? key).toString(),
        'value': v,
        if (unit.isNotEmpty) 'unit': unit,
      };
    }
    return out;
  }

  Future<void> _loadRequirements() async {
    final pid = widget.providerId;
    if (pid == null) return;
    try {
      final r = await BabifixUserStore.authGet('/api/providers/$pid/requirements/');
      if (r.statusCode == 200 && mounted) {
        final d = jsonDecode(r.body) as Map<String, dynamic>;
        final tpl = (d['template_exigences'] as List?) ?? const [];
        setState(() {
          _exigProfil = (d['profil_devis'] ?? 'STANDARD').toString();
          _exigTemplate = tpl
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _loadSavedAddresses() async {
    try {
      final r = await BabifixUserStore.authGet('/api/client/addresses');
      if (r.statusCode == 200 && mounted) {
        final d = jsonDecode(r.body) as Map<String, dynamic>;
        setState(() {
          _savedAddresses = List<Map<String, dynamic>>.from(d['addresses'] ?? []);
        });
      }
    } catch (_) {}
  }

  void _applySavedAddress(Map<String, dynamic> a) {
    final lat = (a['latitude'] as num?)?.toDouble();
    final lon = (a['longitude'] as num?)?.toDouble();
    if (lat == null || lon == null) return;
    setState(() {
      _selectedSavedAddressId = a['id'] ?? '${a['label'] ?? ''}:${lat}_$lon';
      _mapPin = LatLng(lat, lon);
      _mapPinFromUser = true;
      _addressCtrl.text = '${a['address_label'] ?? a['label'] ?? ''}'.trim();
      _repereCtrl.text = '${a['address_repere'] ?? ''}'.trim();
    });
    showBabifixToast(
      context,
      type: BabifixToastType.success,
      message: 'Localite « ${a['label']} » selectionnee.',
    );
  }

  Future<void> _saveCurrentLocation() async {
    final pal = _BookingPalette.of(context);
    final labelCtrl = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: pal.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: pal.accentSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.bookmark_add_rounded, color: pal.accent, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Enregistrer ce lieu',
                style: TextStyle(
                  color: pal.textPrimary,
                  fontSize: 16.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: labelCtrl,
              autofocus: true,
              style: TextStyle(color: pal.textPrimary),
              decoration: InputDecoration(
                hintText: 'Maison, Bureau, Chez maman...',
                hintStyle: TextStyle(color: pal.textMuted),
                filled: true,
                fillColor: pal.softBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: pal.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: pal.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: pal.accent, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in ['Maison', 'Bureau', 'Chez maman'])
                  ActionChip(
                    label: Text(s, style: const TextStyle(fontSize: 12.5)),
                    backgroundColor: pal.softBg,
                    side: BorderSide(color: pal.border),
                    labelStyle: TextStyle(color: pal.textPrimary),
                    onPressed: () => labelCtrl.text = s,
                  ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Annuler', style: TextStyle(color: pal.textMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: BabifixDesign.ciOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, labelCtrl.text.trim()),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (label == null || label.isEmpty) return;
    try {
      final r = await BabifixUserStore.authPost(
        '/api/client/addresses',
        body: jsonEncode({
          'label': label,
          'latitude': _mapPin.latitude,
          'longitude': _mapPin.longitude,
          'address_label': _addressCtrl.text.trim(),
          'address_repere': _repereCtrl.text.trim(),
          'is_default': _savedAddresses.isEmpty,
        }),
      );
      if (r.statusCode == 201) {
        await _loadSavedAddresses();
        if (mounted) {
          showBabifixToast(
            context,
            type: BabifixToastType.success,
            message: 'Lieu « $label » enregistre.',
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _tryAutoLocate({bool forceRefresh = false}) async {
    if (_gpsAutoTried && !forceRefresh) return;
    _gpsAutoTried = true;
    if (!mounted) return;
    setState(() => _gpsState = GpsLocationState.resolving);
    try {
      final gps = await acquireSmartGps(forceFresh: forceRefresh);
      if (!mounted) return;
      if (gps.hasHardError) {
        setState(() => _gpsState = GpsLocationState.denied);
        if (forceRefresh && gps.friendlyMessage != null) {
          showBabifixToast(
            context,
            type: BabifixToastType.info,
            message: gps.friendlyMessage!,
          );
        }
        return;
      }
      LatLng safePin;
      if (gps.ok && gps.inCoteIvoire) {
        safePin = gps.position!;
      } else {
        final saved = await BabifixUserStore.loadAddressCoords();
        safePin = saved != null
            ? LatLng(saved.lat, saved.lng)
            : const LatLng(kAbidjanLat, kAbidjanLon);
        if (!mounted) return;
      }
      setState(() {
        _mapPin = safePin;
        _mapPinFromUser = true;
        _gpsState = GpsLocationState.detected;
      });
      await _reverseGeocodeShort(
        safePin,
        overwrite: forceRefresh || _addressCtrl.text.trim().isEmpty,
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _gpsState = _gpsState == GpsLocationState.detected
              ? _gpsState
              : GpsLocationState.denied;
        });
      }
    }
  }

  void _goTo(int step) => setState(() => _step = step);

  int _revGeoSeq = 0;

  String _shortPlaceLabel(Map<String, dynamic> addr) {
    String pick(List<String> keys) {
      for (final k in keys) {
        final v = (addr[k] ?? '').toString().trim();
        if (v.isNotEmpty) return v;
      }
      return '';
    }

    final house = pick(['house_number']);
    final road = pick(['road', 'street', 'pedestrian', 'footway', 'path']);
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
    if (road.isNotEmpty) {
      parts.add(house.isNotEmpty ? '$house $road' : road);
    }
    if (quartier.isNotEmpty && !parts.contains(quartier)) parts.add(quartier);
    if (ville.isNotEmpty && !parts.contains(ville)) parts.add(ville);
    if (parts.isEmpty && region.isNotEmpty) parts.add(region);
    return parts.join(', ');
  }

  Future<void> _reverseGeocodeShort(LatLng p, {bool overwrite = true}) async {
    final seq = ++_revGeoSeq;
    String label = '';
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?lat=${p.latitude}&lon=${p.longitude}'
        '&format=json&addressdetails=1&accept-language=fr&zoom=16',
      );
      final r = await http
          .get(url, headers: {'User-Agent': 'BABIFIX/1.0 client'})
          .timeout(const Duration(seconds: 5));
      if (!mounted || seq != _revGeoSeq) return;
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final addr = (j['address'] as Map<String, dynamic>?) ?? const {};
        label = _shortPlaceLabel(addr);
        if (label.isEmpty) {
          label = (j['display_name'] ?? '')
              .toString()
              .split(',')
              .take(2)
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .join(', ');
        }
      }
    } catch (_) {}
    if (!mounted || seq != _revGeoSeq) return;
    if (label.isEmpty) {
      label = resolveNearestCivCommune(p.latitude, p.longitude).displayName;
    }
    if (label.isNotEmpty && (overwrite || _addressCtrl.text.trim().isEmpty)) {
      setState(() => _addressCtrl.text = label);
    }
  }

  Future<void> _checkProviderAvailability(DateTime date) async {
    if (widget.providerId == null) return;

    setState(() {
      _selectedDate = date;
      _checkingAvailability = true;
      _providerAvailable = null;
      _availabilityMessage = '';
    });

    try {
      final uri = Uri.parse(
        '${babifixApiBaseUrl()}/api/client/check-provider-availability'
        '?provider_id=${widget.providerId}'
        '&date=${date.toIso8601String().split('T')[0]}',
      );
      final token = await BabifixUserStore.getApiToken();
      final resp = await http
          .get(uri, headers: token != null ? {'Authorization': 'Bearer $token'} : null)
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(resp.body);
        setState(() {
          _providerAvailable = data['available'] as bool?;
          if (data['available'] == true) {
            if (data['busy_that_day'] == true) {
              final sugg = (data['suggested_dates'] as List?)
                      ?.map((e) => '$e')
                      .toList() ??
                  const [];
              final notice = (data['notice'] as String?) ??
                  'Ce prestataire a deja une intervention ce jour-la.';
              _availabilityMessage = sugg.isNotEmpty
                  ? '$notice\nJours libres : ${sugg.join(' · ')}'
                  : notice;
            } else {
              _availabilityMessage = 'Prestataire disponible sur cette date.';
            }
            _availableCreneaux = (data['creneaux'] as List?)
                    ?.map((c) => c as Map<String, dynamic>)
                    .toList() ??
                [];
          } else {
            _availabilityMessage = data['message'] as String? ?? 'Indisponible';
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _providerAvailable = null;
          _availabilityMessage = '';
        });
      }
    }

    if (mounted) setState(() => _checkingAvailability = false);
  }

  Future<bool> _precheckDuplicates() async {
    try {
      final token = await BabifixUserStore.getApiToken();
      if (token == null || token.isEmpty) return true;
      final uri = Uri.parse(
        '${babifixApiBaseUrl()}/api/client/reservations/check-duplicate',
      ).replace(
        queryParameters: {
          if (widget.providerId != null) 'provider_id': '${widget.providerId}',
          'title': widget.serviceTitle,
        },
      );
      final resp = await http
          .get(uri, headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) return true;
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      final dupProvider = j['duplicate_provider'] as Map<String, dynamic>?;
      final dupCategory = j['duplicate_category'] as Map<String, dynamic>?;
      if (!mounted) return false;
      if (dupProvider != null) {
        await _showDuplicateProviderDialog(dupProvider);
        return false;
      }
      if (dupCategory != null) {
        final proceed = await _showDuplicateCategoryDialog(dupCategory);
        return proceed == true;
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  Future<void> _showDuplicateProviderDialog(Map<String, dynamic> info) {
    final ref = (info['reference'] ?? '').toString();
    final presta = (info['prestataire'] ?? 'ce prestataire').toString();
    return showDialog<void>(
      context: context,
      builder: (ctx) => _DuplicateDialog(
        accent: const Color(0xFFEF4444),
        icon: Icons.block_rounded,
        title: 'Prestation deja en cours',
        message:
            'Vous avez deja une prestation en cours avec $presta'
            '${ref.isNotEmpty ? ' (ref. $ref)' : ''}.\n\n'
            'Terminez cette prestation avant d\'en reserver une nouvelle avec le meme prestataire.',
        primaryLabel: "J'ai compris",
        onPrimary: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  Future<bool?> _showDuplicateCategoryDialog(Map<String, dynamic> info) {
    final cat = (info['category'] ?? '').toString();
    final presta = (info['prestataire'] ?? 'un autre prestataire').toString();
    final ref = (info['reference'] ?? '').toString();
    return showDialog<bool>(
      context: context,
      builder: (ctx) => _DuplicateDialog(
        accent: const Color(0xFFF59E0B),
        icon: Icons.warning_amber_rounded,
        title: 'Prestation similaire en cours',
        message:
            'Vous avez deja une prestation '
            '${cat.isNotEmpty ? '« $cat »' : 'de cette categorie'} en cours '
            'avec $presta${ref.isNotEmpty ? ' (ref. $ref)' : ''}.\n\n'
            'Voulez-vous tout de meme continuer ?',
        secondaryLabel: 'Annuler',
        onSecondary: () => Navigator.of(ctx).pop(false),
        primaryLabel: 'Continuer quand meme',
        onPrimary: () => Navigator.of(ctx).pop(true),
      ),
    );
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_mapPinFromUser) {
      showBabifixToast(
        context,
        type: BabifixToastType.info,
        message: 'Epinglez votre position exacte sur la carte avant de reserver.',
      );
      _goTo(1);
      return;
    }
    setState(() => _submitting = true);
    final canProceed = await _precheckDuplicates();
    if (!canProceed) {
      if (mounted) setState(() => _submitting = false);
      return;
    }
    final isSosEligible = _sosPreview?['eligible'] == true;
    final useSosMode = _isUrgent && isSosEligible;
    final data = <String, dynamic>{
      'title': widget.serviceTitle,
      'description_probleme': _problemeCtrl.text.trim(),
      if (_demandeType.isNotEmpty) 'demande_type': _demandeType,
      'address_label': _addressCtrl.text.trim(),
      'address_repere': _repereCtrl.text.trim(),
      'client_message': _msgCtrl.text.trim(),
      'disponibilites_client': _disponibilites,
      if (_selectedDate != null)
        'scheduled_date': _selectedDate!.toIso8601String().split('T')[0],
      'is_urgent': _isUrgent,
      if (useSosMode) 'sos_mode': true,
      'payment_type': _paymentType,
      if (!useSosMode && widget.providerId != null) 'provider_id': widget.providerId,
      if (!useSosMode && widget.providerName != null) 'prestataire_name': widget.providerName,
    };
    if (_mapPinFromUser) {
      data['latitude'] = _mapPin.latitude;
      data['longitude'] = _mapPin.longitude;
    }
    if (_photos.isNotEmpty) {
      data['photo_attachments'] = _photos
          .map((b) => 'data:image/jpeg;base64,${base64Encode(b)}')
          .toList();
    }
    if (_audioProblemeUrl.isNotEmpty) {
      data['audio_probleme'] = _audioProblemeUrl;
    }
    if (_videoProblemeUrl.isNotEmpty) {
      data['video_probleme'] = _videoProblemeUrl;
    }
    final reponses = _buildReponsesExigences();
    if (reponses.isNotEmpty) {
      data['reponses_exigences'] = reponses;
    }

    var authTok = await BabifixUserStore.getApiToken();
    if ((authTok == null || authTok.isEmpty) && mounted) {
      bool loggedIn = false;
      await Navigator.of(context).push<void>(
        babifixRoute(
          (_) => AuthScreen(
            onAuthSuccess: () {
              loggedIn = true;
              Navigator.of(context).maybePop();
            },
          ),
        ),
      );
      if (loggedIn) authTok = await BabifixUserStore.getApiToken();
      if (authTok == null || authTok.isEmpty) {
        if (mounted) {
          setState(() => _submitting = false);
          showBabifixToast(
            context,
            type: BabifixToastType.error,
            title: 'Reservation',
            message: 'Connectez-vous pour finaliser votre reservation.',
          );
        }
        return;
      }
    }

    if (!mounted) return;
    showBabifixToast(
      context,
      type: BabifixToastType.info,
      title: 'Reservation',
      message: 'Envoi de votre demande au prestataire...',
      duration: const Duration(seconds: 2),
    );

    bool ok = false;
    String? reference;
    String? errorMsg;
    if (widget.onConfirm != null) {
      final result = await widget.onConfirm!(data);
      if (result != null) {
        ok = result['ok'] == true;
        reference = result['reference'] as String?;
        errorMsg = result['error'] as String?;
      }
    } else {
      try {
        final token = await BabifixUserStore.getApiToken();
        if (token == null || token.isEmpty) {
          errorMsg = 'Connectez-vous pour reserver';
        } else {
          final resp = await http.post(
            Uri.parse('${babifixApiBaseUrl()}/api/client/reservations'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({...data, 'use_devis': true}),
          );
          if (resp.statusCode == 201) {
            final j = jsonDecode(resp.body) as Map<String, dynamic>;
            ok = j['ok'] == true || j['reference'] != null;
            reference = j['reference'] as String?;
            _alertedSosCount = (j['alerted_providers_count'] as num?)?.toInt() ?? 0;
          } else {
            try {
              final body = jsonDecode(resp.body) as Map<String, dynamic>;
              errorMsg = (body['message'] ?? body['error'] ?? 'Erreur ${resp.statusCode}')
                  .toString();
            } catch (_) {
              errorMsg = 'Erreur ${resp.statusCode}';
            }
          }
        }
      } catch (e) {
        errorMsg = 'Erreur reseau : $e';
      }
    }
    if (!mounted) return;
    setState(() {
      _submitting = false;
      if (reference != null) _reservationReference = reference;
    });
    if (ok) {
      showBabifixToast(
        context,
        type: BabifixToastType.success,
        title: 'Demande envoyee',
        message: reference != null && reference.isNotEmpty
            ? 'Votre demande a bien ete transmise (ref. $reference).'
            : 'Votre demande a bien ete transmise au prestataire.',
      );
      _goTo(3);
    } else {
      showBabifixToast(
        context,
        type: BabifixToastType.error,
        title: 'Reservation impossible',
        message: errorMsg ?? 'Une erreur est survenue. Reessayez.',
        duration: const Duration(seconds: 4),
      );
    }
  }

  Widget _buildCurrentStep(BuildContext context) {
    switch (_step) {
      case 0:
        return _StepProbleme(
          problemeCtrl: _problemeCtrl,
          demandeType: _demandeType,
          demandeTypes: _demandeTypes,
          onDemandeTypeChanged: (t) => setState(() => _demandeType = t),
          photos: _photos,
          onPhotosChanged: (p) => setState(() => _photos = p),
          audioUrl: _audioProblemeUrl,
          audioUploading: _audioUploading,
          onVoiceRecorded: _onVoiceRecorded,
          onAudioRemoved: () => setState(() => _audioProblemeUrl = ''),
          videoUrl: _videoProblemeUrl,
          videoUploading: _videoUploading,
          onPickVideo: _pickVideo,
          onVideoRemoved: () => setState(() => _videoProblemeUrl = ''),
          exigencesTemplate: _exigTemplate,
          exigencesProfil: _exigProfil,
          reponsesExigences: _reponsesExigences,
          onExigencesChanged: (m) => setState(() {
            _reponsesExigences
              ..clear()
              ..addAll(m);
          }),
          onNext: () {
            if (_demandeType.isEmpty) {
              showBabifixToast(
                context,
                type: BabifixToastType.info,
                message: 'Choisissez le type de demande.',
              );
              return;
            }
            if (_problemeCtrl.text.trim().isEmpty) {
              showBabifixToast(
                context,
                type: BabifixToastType.info,
                message: 'Decrivez votre besoin en quelques mots.',
              );
              return;
            }
            final missing = babifixMissingRequirements(
              _exigTemplate,
              _reponsesExigences,
              demandeType: _demandeType,
            );
            if (missing.isNotEmpty) {
              showBabifixToast(
                context,
                type: BabifixToastType.info,
                message: 'Completez : ${missing.join(', ')}.',
              );
              return;
            }
            _goTo(1);
          },
          providerName: widget.providerName,
          providerPhoto: widget.providerPhoto,
          providerSpecialite: widget.providerSpecialite,
          providerRating: widget.providerRating,
        );
      case 1:
        return _StepAddress(
          addressCtrl: _addressCtrl,
          repereCtrl: _repereCtrl,
          msgCtrl: _msgCtrl,
          mapPin: _mapPin,
          gpsState: _gpsState,
          onGpsRefresh: () {
            setState(() => _selectedSavedAddressId = null);
            _tryAutoLocate(forceRefresh: true);
          },
          savedAddresses: _savedAddresses,
          selectedSavedAddressId: _selectedSavedAddressId,
          onPickSaved: _applySavedAddress,
          onUseCurrent: () {
            setState(() => _selectedSavedAddressId = null);
            _tryAutoLocate(forceRefresh: true);
          },
          onSaveCurrent: _saveCurrentLocation,
          onMapPinChanged: (p) => setState(() {
            _selectedSavedAddressId = null;
            _mapPin = p;
            _mapPinFromUser = true;
            _gpsState = GpsLocationState.detected;
          }),
          onMapTap: (p) {
            setState(() {
              _selectedSavedAddressId = null;
              _mapPin = p;
              _mapPinFromUser = true;
              _gpsState = GpsLocationState.detected;
            });
            _reverseGeocodeShort(p, overwrite: true);
          },
          onNext: () {
            if (!_mapPinFromUser) {
              showBabifixToast(
                context,
                type: BabifixToastType.info,
                message:
                    'Epinglez votre position exacte sur la carte (ou « Ma position »).',
              );
              return;
            }
            if (_addressCtrl.text.trim().isEmpty) {
              _addressCtrl.text = 'Position selectionnee sur la carte';
              _reverseGeocodeShort(_mapPin, overwrite: true);
            }
            _goTo(2);
          },
          onBack: () => _goTo(0),
        );
      case 2:
        return _StepDisponibilite(
          disponibilites: _disponibilites,
          onDisponibilitesChanged: (v) => setState(() => _disponibilites = v),
          isUrgent: _isUrgent,
          onUrgentChanged: (v) => setState(() => _isUrgent = v),
          sosPreview: _sosPreview,
          paymentType: _paymentType,
          onPaymentTypeChanged: (v) => setState(() => _paymentType = v),
          onConfirm: _submit,
          onBack: () => _goTo(1),
          submitting: _submitting,
          providerId: widget.providerId,
          checkingAvailability: _checkingAvailability,
          providerAvailable: _providerAvailable,
          availabilityMessage: _availabilityMessage,
          availableCreneaux: _availableCreneaux,
          onCreneauSelected: (v) => setState(() => _disponibilites = v),
          onCheckAvailability: _checkProviderAvailability,
        );
      default:
        return _StepDone(
          serviceTitle: widget.serviceTitle,
          reference: _reservationReference.isNotEmpty ? _reservationReference : null,
          providerName: (_isUrgent && _sosPreview?['eligible'] == true) ? null : widget.providerName,
          sosMode: _isUrgent && _sosPreview?['eligible'] == true,
          sosFeeFcfa: (_sosPreview?['fee_fcfa'] as num?)?.toInt() ?? 1500,
          alertedCount: _alertedSosCount,
          onClose: () => Navigator.of(context).pop(),
          onOpenChat: widget.providerId != null
              ? () {
                  final nav = Navigator.of(context);
                  nav.pushReplacement(
                    babifixRoute(
                      (_) => ChatRoomScreen(
                        name: widget.providerName ?? 'Prestataire',
                        peerUserId: widget.providerId,
                        apiBase: babifixApiBaseUrl(),
                      ),
                    ),
                  );
                }
              : null,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = _BookingPalette.of(context);

    return PopScope(
      canPop: _step == 3,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_step == 0) {
          final hasData = _problemeCtrl.text.isNotEmpty || _photos.isNotEmpty;
          if (hasData) {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: pal.cardBg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                title: Text(
                  'Quitter la demande ?',
                  style: TextStyle(color: pal.textPrimary, fontWeight: FontWeight.w800),
                ),
                content: Text(
                  'Les informations saisies seront perdues.',
                  style: TextStyle(color: pal.textMuted),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text('Annuler', style: TextStyle(color: pal.textMuted)),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: pal.danger,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Quitter'),
                  ),
                ],
              ),
            );
            if (confirm == true && context.mounted) {
              Navigator.of(context).pop();
            }
          } else {
            Navigator.of(context).pop();
          }
          return;
        }
        if (_step > 0 && _step < 3) {
          _goTo(_step - 1);
        }
      },
      child: Scaffold(
        backgroundColor: pal.pageBg,
        appBar: AppBar(
          backgroundColor: pal.cardBg,
          foregroundColor: pal.textPrimary,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: Icon(
              _step > 0 && _step < 3
                  ? Icons.arrow_back_rounded
                  : Icons.close_rounded,
              color: pal.textPrimary,
            ),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nouvelle demande',
                style: TextStyle(
                  color: pal.textPrimary,
                  fontSize: 16.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                (widget.providerSpecialite ?? widget.serviceTitle).trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: pal.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(54),
            child: Container(
              decoration: BoxDecoration(
                color: pal.cardBg,
                border: Border(bottom: BorderSide(color: pal.border)),
              ),
              child: _StepIndicator(steps: _steps, current: _step),
            ),
          ),
        ),
        body: SizedBox.expand(
          child: AnimatedSwitcher(
            duration: BabifixDesign.durationFast,
            child: SizedBox.expand(
              key: ValueKey(_step),
              child: _buildCurrentStep(context),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Indicateur d'etapes lisible (1 a 4) ──────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.steps, required this.current});

  final List<String> steps;
  final int current;

  @override
  Widget build(BuildContext context) {
    final pal = _BookingPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              for (int i = 0; i < steps.length; i++) ...[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 240),
                        height: 4,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(99),
                          color: i < current
                              ? pal.success
                              : (i == current
                                  ? BabifixDesign.ciOrange
                                  : pal.border),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${i + 1}. ${steps[i]}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight:
                              i == current ? FontWeight.w800 : FontWeight.w600,
                          color: i == current
                              ? pal.textPrimary
                              : (i < current ? pal.success : pal.textMuted),
                        ),
                      ),
                    ],
                  ),
                ),
                if (i < steps.length - 1) const SizedBox(width: 6),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ── Composants communs de structure & barre d'actions basse ─────────────────

class _StepSectionCard extends StatelessWidget {
  const _StepSectionCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final pal = _BookingPalette.of(context);
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: pal.cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: pal.border),
        boxShadow: BabifixDesign.elevationShadowSM(pal.isLight),
      ),
      child: child,
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final pal = _BookingPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: pal.accentSoft,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: pal.accent, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: pal.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  color: pal.textMuted,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StickyFooterBar extends StatelessWidget {
  const _StickyFooterBar({
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.loading = false,
  });

  final String primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final pal = _BookingPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: pal.cardBg,
        border: Border(top: BorderSide(color: pal.border)),
        boxShadow: BabifixDesign.elevationShadowSM(pal.isLight),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Row(
          children: [
            if (secondaryLabel != null && onSecondary != null) ...[
              Expanded(
                flex: 1,
                child: BabifixButton(
                  label: secondaryLabel!,
                  variant: BabifixButtonVariant.outlined,
                  backgroundColor: pal.cardBg,
                  foregroundColor: pal.textPrimary,
                  height: 50,
                  onPressed: loading ? null : onSecondary,
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              flex: 2,
              child: BabifixButton(
                label: primaryLabel,
                variant: BabifixButtonVariant.primary,
                height: 50,
                isLoading: loading,
                onPressed: loading ? null : onPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Step 0 : Votre besoin ───────────────────────────────────────────────────

List<String> babifixCategorySuggestions(String? specialite) {
  final s = (specialite ?? '').toLowerCase();
  bool has(List<String> kws) => kws.any((k) => s.contains(k));
  if (has(['plomb', 'fuite', 'sanitaire', 'eau'])) {
    return [
      "Fuite d'eau",
      'Robinet qui goutte',
      'WC bouche',
      'Chauffe-eau en panne',
      'Installation sanitaire',
    ];
  }
  if (has(['elect', 'courant'])) {
    return [
      'Panne de courant',
      'Prise defectueuse',
      'Court-circuit',
      'Installation de prise',
      'Tableau electrique',
    ];
  }
  if (has(['menage', 'nettoy', 'propret'])) {
    return [
      'Menage complet',
      'Nettoyage apres travaux',
      'Vitres',
      'Repassage',
      'Entretien regulier',
    ];
  }
  if (has(['menuis', 'parquet', 'meuble', 'bois'])) {
    return [
      'Meuble a reparer',
      'Porte qui coince',
      'Pose de parquet',
      'Etagere a monter',
      'Sur-mesure',
    ];
  }
  if (has(['demenag', 'manuten', 'transport'])) {
    return [
      'Demenagement appartement',
      'Cartons',
      'Meubles lourds',
      'Besoin camion',
      'Etage sans ascenseur',
    ];
  }
  if (has(['peint', 'enduit'])) {
    return [
      "Peinture d'une piece",
      'Tout le logement',
      'Reprise de fissures',
      'Plafond',
      'Exterieur',
    ];
  }
  if (has(['clim', 'froid', 'refrig'])) {
    return [
      'Clim ne refroidit plus',
      'Installation de clim',
      'Entretien / recharge',
      'Bruit anormal',
      'Fuite d eau',
    ];
  }
  if (has(['jardin', 'espace vert', 'gazon', 'tonte', 'elagage'])) {
    return [
      'Tonte de pelouse',
      'Taille de haie',
      'Debroussaillage',
      'Elagage',
      'Entretien regulier',
    ];
  }
  if (has(['coiff', 'beaut', 'esthet', 'maquill'])) {
    return ['A domicile', 'Coupe', 'Coiffure evenement', 'Soins'];
  }
  if (has(['mecan', 'auto', 'voiture', 'garage'])) {
    return ['Panne moteur', 'Vidange', 'Freins', 'Batterie', 'Diagnostic'];
  }
  if (has(['electromenager', 'frigo', 'machine'])) {
    return [
      'Appareil en panne',
      'Ne s allume plus',
      'Bruit anormal',
      'Diagnostic',
      'Piece a changer',
    ];
  }
  return [
    'Ne fonctionne plus',
    'Reparation rapide',
    'Installation',
    'Entretien',
    'Diagnostic',
  ];
}

class _StepProbleme extends StatelessWidget {
  const _StepProbleme({
    required this.problemeCtrl,
    required this.demandeType,
    required this.demandeTypes,
    required this.onDemandeTypeChanged,
    required this.photos,
    required this.onPhotosChanged,
    required this.audioUrl,
    required this.audioUploading,
    required this.onVoiceRecorded,
    required this.onAudioRemoved,
    required this.videoUrl,
    required this.videoUploading,
    required this.onPickVideo,
    required this.onVideoRemoved,
    required this.exigencesTemplate,
    required this.exigencesProfil,
    required this.reponsesExigences,
    required this.onExigencesChanged,
    required this.onNext,
    this.providerName,
    this.providerPhoto,
    this.providerSpecialite,
    this.providerRating,
  });

  final TextEditingController problemeCtrl;
  final String demandeType;
  final List<(String, String, IconData)> demandeTypes;
  final ValueChanged<String> onDemandeTypeChanged;
  final List<Uint8List> photos;
  final ValueChanged<List<Uint8List>> onPhotosChanged;
  final String audioUrl;
  final bool audioUploading;
  final void Function(String path, int durationSeconds) onVoiceRecorded;
  final VoidCallback onAudioRemoved;
  final String videoUrl;
  final bool videoUploading;
  final Future<void> Function(ImageSource source) onPickVideo;
  final VoidCallback onVideoRemoved;
  final List<Map<String, dynamic>> exigencesTemplate;
  final String exigencesProfil;
  final Map<String, dynamic> reponsesExigences;
  final ValueChanged<Map<String, dynamic>> onExigencesChanged;
  final VoidCallback onNext;
  final String? providerName;
  final String? providerPhoto;
  final String? providerSpecialite;
  final double? providerRating;

  @override
  Widget build(BuildContext context) {
    final pal = _BookingPalette.of(context);
    final resolvedPhoto = babifixResolveMediaUrl(providerPhoto ?? '');

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (providerName != null && providerName!.trim().isNotEmpty) ...[
                  _StepSectionCard(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: resolvedPhoto.startsWith('http')
                                ? Image.network(
                                    resolvedPhoto,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        _initialsAvatar(pal, providerName!),
                                  )
                                : _initialsAvatar(pal, providerName!),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                providerName!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: pal.textPrimary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14.5,
                                ),
                              ),
                              if (providerSpecialite != null &&
                                  providerSpecialite!.trim().isNotEmpty)
                                Text(
                                  providerSpecialite!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: pal.textMuted,
                                    fontSize: 12.5,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (providerRating != null && providerRating! > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  color: Color(0xFFD97706),
                                  size: 15,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  providerRating!.toStringAsFixed(1),
                                  style: const TextStyle(
                                    color: Color(0xFF92400E),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                const _StepHeader(
                  icon: Icons.build_circle_outlined,
                  title: 'Quel est votre besoin ?',
                  subtitle:
                      'Precisez votre demande pour obtenir un devis adapte.',
                ),
                const SizedBox(height: 18),

                // ── 1. Nature de l'intervention (grille 2 colonnes) ──
                _StepSectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Type d\'intervention',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: pal.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final itemW = (constraints.maxWidth - 8) / 2;
                          return Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: demandeTypes.map((t) {
                              final selected = demandeType == t.$1;
                              return InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () =>
                                    onDemandeTypeChanged(selected ? '' : t.$1),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 160),
                                  width: itemW,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 11,
                                  ),
                                  decoration: BoxDecoration(
                                    color: selected ? pal.accentSoft : pal.softBg,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: selected ? pal.accent : pal.border,
                                      width: selected ? 1.6 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        t.$3,
                                        size: 17,
                                        color: selected
                                            ? pal.accent
                                            : pal.textMuted,
                                      ),
                                      const SizedBox(width: 7),
                                      Expanded(
                                        child: Text(
                                          t.$2,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: selected
                                                ? FontWeight.w800
                                                : FontWeight.w600,
                                            color: selected
                                                ? pal.textPrimary
                                                : pal.textMuted,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // ── 2. Description et mots-cles ──
                _StepSectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Description du besoin',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: pal.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: problemeCtrl,
                        minLines: 3,
                        maxLines: 5,
                        style: TextStyle(
                          color: pal.textPrimary,
                          fontSize: 14.5,
                          height: 1.4,
                        ),
                        decoration: InputDecoration(
                          hintText:
                              'Expliquez ce que vous constatez (ex : fuite sous evier, climatiseur a recharger...)',
                          hintStyle: TextStyle(
                            color: pal.textMuted.withValues(alpha: 0.75),
                            fontSize: 13.5,
                          ),
                          filled: true,
                          fillColor: pal.softBg,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: pal.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: pal.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: pal.accent, width: 1.6),
                          ),
                          contentPadding: const EdgeInsets.all(14),
                        ),
                      ),
                      const SizedBox(height: 12),
                      BabifixSuggestionChips(
                        controller: problemeCtrl,
                        accent: pal.accent,
                        title: 'Precisions rapides',
                        suggestions: babifixCategorySuggestions(providerSpecialite),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // ── 3. Pieces jointes optionnelles ──
                _StepSectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Pieces jointes',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: pal.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '(optionnel)',
                            style: TextStyle(fontSize: 12, color: pal.textMuted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _AttachTile(
                              icon: Icons.add_a_photo_outlined,
                              label: photos.isEmpty
                                  ? 'Photos'
                                  : '${photos.length} photo(s)',
                              active: photos.isNotEmpty,
                              onTap: () async {
                                final picked = await _showImagePicker(context);
                                if (picked != null && picked.isNotEmpty) {
                                  onPhotosChanged([...photos, ...picked]);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _AttachTile(
                              icon: Icons.mic_none_rounded,
                              label: audioUrl.isEmpty ? 'Audio' : 'Audio ajoute',
                              active: audioUrl.isNotEmpty,
                              loading: audioUploading,
                              customChild: !audioUploading && audioUrl.isEmpty
                                  ? Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          height: 30,
                                          child: BabifixVoiceRecorderButton(
                                            color: pal.accent,
                                            onRecorded: onVoiceRecorded,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Note vocale',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: pal.textMuted,
                                          ),
                                        ),
                                      ],
                                    )
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _AttachTile(
                              icon: Icons.videocam_outlined,
                              label: videoUrl.isEmpty ? 'Video' : 'Video ajoutee',
                              active: videoUrl.isNotEmpty,
                              loading: videoUploading,
                              onTap: videoUploading || videoUrl.isNotEmpty
                                  ? null
                                  : () => _pickVideoSource(context, onPickVideo),
                            ),
                          ),
                        ],
                      ),
                      if (photos.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 64,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: photos.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 8),
                            itemBuilder: (_, idx) => Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.memory(
                                    photos[idx],
                                    width: 64,
                                    height: 64,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  top: 3,
                                  right: 3,
                                  child: GestureDetector(
                                    onTap: () {
                                      final next = [...photos]..removeAt(idx);
                                      onPhotosChanged(next);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: const BoxDecoration(
                                        color: Colors.black87,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.close_rounded,
                                        size: 13,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (audioUrl.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: pal.softBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: pal.border),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: BabifixVoiceNotePlayer(
                                  url: MediaApi.absolute(audioUrl),
                                  durationSeconds: 0,
                                  isMe: true,
                                ),
                              ),
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: onAudioRemoved,
                                icon: Icon(
                                  Icons.delete_outline,
                                  color: pal.danger,
                                  size: 20,
                                ),
                                tooltip: 'Supprimer la note vocale',
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (videoUrl.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: pal.softBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: pal.border),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.videocam_rounded,
                                  color: pal.success, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Video jointe',
                                  style: TextStyle(
                                    color: pal.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () => launchUrl(
                                  Uri.parse(MediaApi.absolute(videoUrl)),
                                  mode: LaunchMode.externalApplication,
                                ),
                                child: const Text('Voir'),
                              ),
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: onVideoRemoved,
                                icon: Icon(
                                  Icons.delete_outline,
                                  color: pal.danger,
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                if (exigencesTemplate.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _StepSectionCard(
                    child: BabifixDynamicRequirements(
                      template: exigencesTemplate,
                      profil: exigencesProfil,
                      demandeType: demandeType,
                      answers: reponsesExigences,
                      onChanged: onExigencesChanged,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        _StickyFooterBar(
          primaryLabel: 'Continuer vers l\'adresse',
          onPrimary: onNext,
        ),
      ],
    );
  }

  Widget _initialsAvatar(_BookingPalette pal, String name) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : 'B';
    return DecoratedBox(
      decoration: BoxDecoration(color: pal.accentSoft),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: pal.accent,
            fontWeight: FontWeight.w900,
            fontSize: 17,
          ),
        ),
      ),
    );
  }

  Future<List<Uint8List>?> _showImagePicker(BuildContext context) async {
    final pal = _BookingPalette.of(context);
    return showBabifixModalSheet<List<Uint8List>>(
      context: context,
      backgroundColor: pal.cardBg,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.camera_alt_rounded, color: pal.accent),
              title: Text(
                'Prendre une photo',
                style: TextStyle(color: pal.textPrimary, fontWeight: FontWeight.w600),
              ),
              onTap: () async {
                final img = await _pickImageFromCamera();
                if (ctx.mounted) Navigator.pop(ctx, img != null ? [img] : null);
              },
            ),
            ListTile(
              leading: Icon(Icons.photo_library_rounded, color: pal.accent),
              title: Text(
                'Choisir dans la galerie',
                style: TextStyle(color: pal.textPrimary, fontWeight: FontWeight.w600),
              ),
              onTap: () async {
                final imgs = await _pickImagesFromGallery();
                if (ctx.mounted) Navigator.pop(ctx, imgs);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<Uint8List?> _pickImageFromCamera() async {
    try {
      final picker = ImagePicker();
      final XFile? img = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (img == null) return null;
      return await img.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  Future<List<Uint8List>?> _pickImagesFromGallery() async {
    try {
      final picker = ImagePicker();
      final List<XFile> imgs = await picker.pickMultiImage(imageQuality: 85);
      if (imgs.isEmpty) return null;
      final bytes = <Uint8List>[];
      for (final img in imgs) {
        bytes.add(await img.readAsBytes());
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }
}

Future<void> _pickVideoSource(
  BuildContext context,
  Future<void> Function(ImageSource source) onPickVideo,
) {
  final pal = _BookingPalette.of(context);
  return showBabifixModalSheet<void>(
    context: context,
    backgroundColor: pal.cardBg,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(Icons.videocam_rounded, color: pal.accent),
            title: Text(
              'Filmer le probleme',
              style: TextStyle(color: pal.textPrimary, fontWeight: FontWeight.w600),
            ),
            onTap: () {
              Navigator.pop(ctx);
              onPickVideo(ImageSource.camera);
            },
          ),
          ListTile(
            leading: Icon(Icons.video_library_rounded, color: pal.accent),
            title: Text(
              'Choisir une video',
              style: TextStyle(color: pal.textPrimary, fontWeight: FontWeight.w600),
            ),
            onTap: () {
              Navigator.pop(ctx);
              onPickVideo(ImageSource.gallery);
            },
          ),
        ],
      ),
    ),
  );
}

class _AttachTile extends StatelessWidget {
  const _AttachTile({
    required this.icon,
    required this.label,
    this.onTap,
    this.active = false,
    this.loading = false,
    this.customChild,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  final bool loading;
  final Widget? customChild;

  @override
  Widget build(BuildContext context) {
    final pal = _BookingPalette.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        constraints: const BoxConstraints(minHeight: 82),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: active ? pal.success.withValues(alpha: 0.1) : pal.softBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? pal.success : pal.border,
            width: active ? 1.4 : 1,
          ),
        ),
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: BabifixRingLoader.cyan(size: 20),
                )
              : customChild ??
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        active ? Icons.check_circle_rounded : icon,
                        color: active ? pal.success : pal.accent,
                        size: 22,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: active ? pal.success : pal.textPrimary,
                        ),
                      ),
                    ],
                  ),
        ),
      ),
    );
  }
}

// ── Step 1 : Adresse & localisation ──────────────────────────────────────────

class _StepAddress extends StatefulWidget {
  const _StepAddress({
    required this.addressCtrl,
    required this.repereCtrl,
    required this.msgCtrl,
    required this.mapPin,
    required this.onMapPinChanged,
    required this.onMapTap,
    required this.onNext,
    required this.onBack,
    required this.gpsState,
    required this.onGpsRefresh,
    required this.savedAddresses,
    this.selectedSavedAddressId,
    required this.onPickSaved,
    required this.onUseCurrent,
    required this.onSaveCurrent,
  });

  final List<Map<String, dynamic>> savedAddresses;
  final dynamic selectedSavedAddressId;
  final ValueChanged<Map<String, dynamic>> onPickSaved;
  final VoidCallback onUseCurrent;
  final VoidCallback onSaveCurrent;
  final TextEditingController addressCtrl;
  final TextEditingController repereCtrl;
  final TextEditingController msgCtrl;
  final LatLng mapPin;
  final ValueChanged<LatLng> onMapPinChanged;
  final ValueChanged<LatLng> onMapTap;
  final VoidCallback onNext;
  final VoidCallback onBack;
  final GpsLocationState gpsState;
  final VoidCallback onGpsRefresh;

  @override
  State<_StepAddress> createState() => _StepAddressState();
}

class _StepAddressState extends State<_StepAddress> {
  bool _showDetails = false;

  IconData _iconForLabel(String label) {
    final l = label.toLowerCase();
    if (l.contains('maison') || l.contains('domicile') || l.contains('chez')) {
      return Icons.home_rounded;
    }
    if (l.contains('bureau') || l.contains('travail')) {
      return Icons.work_rounded;
    }
    return Icons.place_rounded;
  }

  Widget _sourceChip(
    _BookingPalette pal, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool highlight = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 96,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: highlight ? pal.accentSoft : pal.cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: highlight ? pal.accent : pal.border,
            width: highlight ? 1.8 : 1,
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Center(
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: highlight ? pal.accent : pal.softBg,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      size: 16,
                      color: highlight ? pal.accentOnFill : pal.accent,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.15,
                    fontWeight: highlight ? FontWeight.w800 : FontWeight.w600,
                    color: pal.textPrimary,
                  ),
                ),
              ],
            ),
            if (highlight)
              Positioned(
                top: -4,
                right: -2,
                child: Icon(
                  Icons.check_circle_rounded,
                  size: 15,
                  color: pal.accent,
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = _BookingPalette.of(context);
    final hasSavedSelected = widget.selectedSavedAddressId != null;
    final chips = <Widget>[
      _sourceChip(
        pal,
        icon: Icons.my_location_rounded,
        label: 'Ma position',
        onTap: widget.onUseCurrent,
        highlight: !hasSavedSelected,
      ),
      ...widget.savedAddresses.map(
        (a) {
          final key = a['id'] ?? '${a['label'] ?? ''}:${a['latitude']}_${a['longitude']}';
          final isSel = hasSavedSelected && widget.selectedSavedAddressId == key;
          return _sourceChip(
            pal,
            icon: _iconForLabel('${a['label'] ?? ''}'),
            label: '${a['label'] ?? 'Adresse'}',
            onTap: () => widget.onPickSaved(a),
            highlight: isSel,
          );
        },
      ),
      _sourceChip(
        pal,
        icon: Icons.bookmark_add_outlined,
        label: 'Enregistrer',
        onTap: widget.onSaveCurrent,
      ),
    ];

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _StepHeader(
                  icon: Icons.location_on_rounded,
                  title: 'Lieu d\'intervention',
                  subtitle:
                      'Confirmez votre position exacte pour guider l\'artisan.',
                ),
                const SizedBox(height: 16),

                // ── Raccourcis adresse ──
                SizedBox(
                  height: 98,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: chips.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, i) => chips[i],
                  ),
                ),
                const SizedBox(height: 14),

                // ── Recherche adresse + GPS + repere ──
                _StepSectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Adresse et point de repere',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: pal.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      GpsLocationCard(
                        state: widget.gpsState,
                        addressText: widget.addressCtrl.text,
                        onRefresh: widget.onGpsRefresh,
                      ),
                      const SizedBox(height: 10),
                      BabifixAddressSearchField(
                        controller: widget.addressCtrl,
                        onPlaceSelected: (latLng, label) {
                          if (label.trim().isNotEmpty) {
                            widget.addressCtrl.text = label.trim();
                          }
                          widget.onMapPinChanged(latLng);
                        },
                      ),
                      const SizedBox(height: 10),
                      _RepereTextField(controller: widget.repereCtrl),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // ── Carte interactive ──
                _StepSectionCard(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.map_rounded, color: pal.accent, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            'Ajustez le marqueur si besoin',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5,
                              color: pal.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: BabifixOsmLocationPicker(
                          marker: widget.mapPin,
                          onMarkerMoved: widget.onMapTap,
                          height: 220,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // ── Instructions d'acces optionnelles ──
                _StepSectionCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        onTap: () =>
                            setState(() => _showDetails = !_showDetails),
                        child: Row(
                          children: [
                            Icon(
                              _showDetails
                                  ? Icons.expand_less_rounded
                                  : Icons.add_circle_outline_rounded,
                              color: pal.accent,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _showDetails
                                    ? 'Masquer les precisions d\'acces'
                                    : 'Ajouter des precisions d\'acces (optionnel)',
                                style: TextStyle(
                                  color: pal.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_showDetails) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: widget.msgCtrl,
                          maxLines: 3,
                          style: TextStyle(color: pal.textPrimary, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Batiment, etage, code portail, acces...',
                            hintStyle: TextStyle(color: pal.textMuted),
                            filled: true,
                            fillColor: pal.softBg,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: pal.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: pal.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: pal.accent, width: 1.5),
                            ),
                            contentPadding: const EdgeInsets.all(12),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        _StickyFooterBar(
          secondaryLabel: 'Retour',
          onSecondary: widget.onBack,
          primaryLabel: 'Choisir le creneau',
          onPrimary: widget.onNext,
        ),
      ],
    );
  }
}

// ── Step 2 : Disponibilite & paiement ────────────────────────────────────────

class _StepDisponibilite extends StatelessWidget {
  const _StepDisponibilite({
    required this.disponibilites,
    required this.onDisponibilitesChanged,
    required this.isUrgent,
    required this.onUrgentChanged,
    this.sosPreview,
    required this.paymentType,
    required this.onPaymentTypeChanged,
    required this.onConfirm,
    required this.onBack,
    required this.submitting,
    this.providerId,
    this.checkingAvailability,
    this.providerAvailable,
    this.availabilityMessage,
    this.availableCreneaux = const [],
    this.onCreneauSelected,
    this.onCheckAvailability,
  });

  final String disponibilites;
  final ValueChanged<String> onDisponibilitesChanged;
  final bool isUrgent;
  final ValueChanged<bool> onUrgentChanged;
  final Map<String, dynamic>? sosPreview;
  final String paymentType;
  final ValueChanged<String> onPaymentTypeChanged;
  final Future<void> Function() onConfirm;
  final VoidCallback onBack;
  final bool submitting;
  final int? providerId;
  final bool? checkingAvailability;
  final bool? providerAvailable;
  final String? availabilityMessage;
  final List<Map<String, dynamic>> availableCreneaux;
  final ValueChanged<String>? onCreneauSelected;
  final Future<void> Function(DateTime)? onCheckAvailability;

  @override
  Widget build(BuildContext context) {
    final pal = _BookingPalette.of(context);
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _StepHeader(
                  icon: Icons.schedule_rounded,
                  title: 'Creneau et reglement',
                  subtitle:
                      'Indiquez vos disponibilites et le mode de paiement souhaite.',
                ),
                const SizedBox(height: 16),

                if (providerId != null) ...[
                  _StepSectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _AvailabilityCalendar(
                          providerId: providerId!,
                          selectedLabel: disponibilites,
                          onPick: onDisponibilitesChanged,
                          onDateSelected: onCheckAvailability,
                        ),
                        if (checkingAvailability == true) ...[
                          const SizedBox(height: 10),
                          const Center(child: BabifixRingLoader.cyan(size: 22)),
                        ],
                        if (availabilityMessage != null &&
                            availabilityMessage!.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: (providerAvailable == true
                                      ? pal.success
                                      : providerAvailable == false
                                          ? pal.danger
                                          : pal.accent)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: (providerAvailable == true
                                        ? pal.success
                                        : providerAvailable == false
                                            ? pal.danger
                                            : pal.accent)
                                    .withValues(alpha: 0.35),
                              ),
                            ),
                            child: Text(
                              availabilityMessage!,
                              style: TextStyle(
                                color: providerAvailable == true
                                    ? pal.success
                                    : providerAvailable == false
                                        ? pal.danger
                                        : pal.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                if (availableCreneaux.isNotEmpty) ...[
                  _StepSectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Creneaux disponibles',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: pal.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final c in availableCreneaux)
                              _CreneauChip(
                                label: c['label'] as String? ?? 'Creneau',
                                timeRange: c['time_range'] as String? ?? '',
                                selected: disponibilites == c['id'].toString(),
                                onTap: () => onCreneauSelected?.call(
                                  c['id'].toString(),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // ── Mode de paiement ──
                _StepSectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mode de paiement apres devis',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: pal.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _PaymentOption(
                              icon: Icons.payments_rounded,
                              label: 'Especes',
                              subtitle: 'Sur place',
                              selected: paymentType == 'ESPECES',
                              onTap: () => onPaymentTypeChanged('ESPECES'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _PaymentOption(
                              icon: Icons.phone_android_rounded,
                              label: 'Mobile Money',
                              subtitle: 'Wave, Orange, MTN',
                              selected: paymentType == 'MOBILE_MONEY',
                              onTap: () => onPaymentTypeChanged('MOBILE_MONEY'),
                            ),
                          ),
                        ],
                      ),
                      if (paymentType == 'MOBILE_MONEY') ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: const [
                            BabifixPaymentMethodLogo(methodId: 'WAVE', height: 22),
                            BabifixPaymentMethodLogo(methodId: 'ORANGE_MONEY', height: 22),
                            BabifixPaymentMethodLogo(methodId: 'MTN_MOMO', height: 22),
                            BabifixPaymentMethodLogo(methodId: 'MOOV_MONEY', height: 22),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Vous choisirez l\'operateur au moment du reglement, apres reception du devis.',
                          style: TextStyle(
                            fontSize: 12,
                            color: pal.textMuted,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // ── BABIFIX SOS 24/7 (uniquement pour categories eligibles) ──
                if (sosPreview?['eligible'] == true) ...[
                  const SizedBox(height: 14),
                  _Sos247Card(
                    active: isUrgent,
                    sosPreview: sosPreview!,
                    onChanged: onUrgentChanged,
                  ),
                ],
              ],
            ),
          ),
        ),
        _StickyFooterBar(
          secondaryLabel: 'Retour',
          onSecondary: onBack,
          primaryLabel: (isUrgent && sosPreview?['eligible'] == true)
              ? 'Lancer le Radar SOS'
              : 'Envoyer la demande',
          loading: submitting,
          onPrimary: onConfirm,
        ),
      ],
    );
  }
}

class _CreneauChip extends StatelessWidget {
  const _CreneauChip({
    required this.label,
    required this.timeRange,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String timeRange;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pal = _BookingPalette.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? pal.accentSoft : pal.softBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? pal.accent : pal.border,
            width: selected ? 1.8 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.access_time_rounded,
                  size: 16,
                  color: selected ? pal.accent : pal.textMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected ? pal.accent : pal.textPrimary,
                  ),
                ),
              ],
            ),
            if (timeRange.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                timeRange,
                style: TextStyle(fontSize: 11.5, color: pal.textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PaymentOption extends StatelessWidget {
  const _PaymentOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pal = _BookingPalette.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? pal.accentSoft : pal.softBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? pal.accent : pal.border,
            width: selected ? 1.8 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: selected ? pal.accent : pal.textMuted,
              size: 24,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: pal.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(fontSize: 11, color: pal.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Carte SOS 24/7 (eligibilite, tarif serveur & guide encadre) ──────────────

class _Sos247Card extends StatelessWidget {
  const _Sos247Card({
    required this.active,
    required this.sosPreview,
    required this.onChanged,
  });

  final bool active;
  final Map<String, dynamic> sosPreview;
  final ValueChanged<bool> onChanged;

  void _showGuide(BuildContext context) {
    final dayFee = sosPreview['day_fee_fcfa'] ?? 1500;
    final nightFee = sosPreview['night_fee_fcfa'] ?? 2500;
    showBabifixModalSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.emergency_share_rounded, color: Color(0xFFC2410C), size: 22),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Comment fonctionne BABIFIX SOS 24/7 ?',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '1. Alerte sectorielle immediate : tous les artisans disponibles de votre metier dans un rayon de ${sosPreview['radius_km'] ?? 7} km recoivent votre demande en meme temps.\n\n'
                '2. Forfait express encadre :\n'
                '   • Journee (06h-20h) : $dayFee FCFA\n'
                '   • Nuit (20h-06h) & Dimanche : $nightFee FCFA\n\n'
                '3. 100 % deductible : si vous validez le devis etabli sur place par l\'artisan, ce forfait est integralement deduit du montant final. Aucune facturation sans votre accord.',
                style: const TextStyle(fontSize: 13.5, height: 1.45),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0B1B34)),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Compris'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = _BookingPalette.of(context);
    final isNight = sosPreview['is_night'] == true;
    final fee = sosPreview['fee_fcfa'] ?? (isNight ? 2500 : 1500);
    final sched = '${sosPreview['schedule_label'] ?? (isNight ? 'Astreinte Nuit / Dimanche' : 'Journee Express')}';
    const sosTerra = Color(0xFFC2410C);

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => onChanged(!active),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: active ? sosTerra.withValues(alpha: 0.08) : pal.cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: active ? sosTerra : pal.border,
            width: active ? 1.8 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: (active ? sosTerra : pal.accent).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.emergency_share_rounded,
                    color: active ? sosTerra : pal.accent,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'BABIFIX SOS 24/7',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14.5,
                              color: active ? sosTerra : pal.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: (isNight ? const Color(0xFF0B1B34) : const Color(0xFFB45309))
                                  .withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '$fee FCFA',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: isNight ? const Color(0xFF0B1B34) : const Color(0xFFB45309),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sched,
                        style: TextStyle(fontSize: 11.5, color: pal.textMuted),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: active,
                  onChanged: onChanged,
                  activeThumbColor: sosTerra,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Diffuse immediatement a tous les artisans du secteur (${sosPreview['radius_km'] ?? 7} km). Forfait deplacement $fee FCFA 100 % deductible du devis.',
              style: TextStyle(fontSize: 12, color: pal.textMuted, height: 1.35),
            ),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => _showGuide(context),
              child: const Text(
                'Voir le fonctionnement et tarif encadre',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: sosTerra,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Step 3 : Confirmation (avec Radar SOS Live si sosMode == true) ────────────

class _StepDone extends StatefulWidget {
  const _StepDone({
    required this.serviceTitle,
    required this.onClose,
    this.reference,
    this.providerName,
    this.sosMode = false,
    this.sosFeeFcfa = 1500,
    this.alertedCount = 0,
    this.onOpenChat,
  });

  final String serviceTitle;
  final VoidCallback onClose;
  final String? reference;
  final String? providerName;
  final bool sosMode;
  final int sosFeeFcfa;
  final int alertedCount;
  final VoidCallback? onOpenChat;

  @override
  State<_StepDone> createState() => _StepDoneState();
}

class _StepDoneState extends State<_StepDone> with SingleTickerProviderStateMixin {
  AnimationController? _radarCtrl;
  Timer? _pollTimer;
  String? _claimedProviderName;
  int? _claimedProviderId;

  @override
  void initState() {
    super.initState();
    _claimedProviderName = widget.providerName;
    if (widget.sosMode && widget.reference != null && _claimedProviderName == null) {
      _radarCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1600),
      )..repeat();
      _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _pollSosStatus());
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _radarCtrl?.dispose();
    super.dispose();
  }

  Future<void> _pollSosStatus() async {
    if (widget.reference == null) return;
    try {
      final token = await BabifixUserStore.getApiToken();
      if (token == null || token.isEmpty) return;
      final resp = await http.get(
        Uri.parse('${babifixApiBaseUrl()}/api/client/reservations/${widget.reference}/detail'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200 && mounted) {
        final d = jsonDecode(resp.body) as Map<String, dynamic>;
        final pd = d['prestataire_data'] as Map<String, dynamic>?;
        final pname = '${pd?['nom'] ?? d['prestataire'] ?? ''}'.trim();
        final pid = d['assigned_provider_id'] as int?;
        if (pname.isNotEmpty && pname != 'A affecter') {
          _pollTimer?.cancel();
          _radarCtrl?.stop();
          setState(() {
            _claimedProviderName = pname;
            _claimedProviderId = pid;
          });
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final pal = _BookingPalette.of(context);
    final isWaitingSos = widget.sosMode && _claimedProviderName == null;
    const sosTerra = Color(0xFFC2410C);

    return SafeArea(
      top: false,
      bottom: true,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _StepSectionCard(
          padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isWaitingSos && _radarCtrl != null)
                SizedBox(
                  width: 112,
                  height: 112,
                  child: AnimatedBuilder(
                    animation: _radarCtrl!,
                    builder: (_, __) {
                      final t = _radarCtrl!.value;
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 48 + t * 62,
                            height: 48 + t * 62,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: sosTerra.withValues(alpha: (1 - t) * 0.7),
                                width: 2.2,
                              ),
                              color: sosTerra.withValues(alpha: (1 - t) * 0.14),
                            ),
                          ),
                          Container(
                            width: 58,
                            height: 58,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: sosTerra,
                            ),
                            child: const Icon(
                              Icons.radar_rounded,
                              size: 32,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                )
              else
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: pal.success.withValues(alpha: 0.14),
                  ),
                  child: Icon(
                    Icons.check_circle_rounded,
                    size: 52,
                    color: pal.success,
                  ),
                ),
              const SizedBox(height: 22),
              Text(
                isWaitingSos
                    ? 'Radar SOS actif...'
                    : (_claimedProviderName != null && widget.sosMode)
                        ? 'Artisan SOS trouve !'
                        : 'Demande envoyee',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                  color: pal.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isWaitingSos
                    ? 'Alerte envoyee dans votre secteur (${widget.alertedCount > 0 ? '${widget.alertedCount} artisan(s) notifies' : 'recherche en cours'}). Le premier artisan qui accepte prend votre mission (${widget.sosFeeFcfa} FCFA deductible).'
                    : (_claimedProviderName != null && widget.sosMode)
                        ? '$_claimedProviderName a pris votre urgence « ${widget.serviceTitle} » en charge.'
                        : 'Votre demande pour « ${widget.serviceTitle} » a ete transmise. Le prestataire va preparer votre devis sur mesure.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: pal.textMuted,
                  height: 1.45,
                  fontSize: 14,
                ),
              ),
              if (widget.reference != null) ...[
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: pal.softBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: pal.border),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Reference de suivi',
                        style: TextStyle(fontSize: 12, color: pal.textMuted),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.reference!,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: pal.accent,
                          fontFeatures: BabifixDesign.tabularFigures,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_claimedProviderName != null && (widget.onOpenChat != null || _claimedProviderId != null)) ...[
                const SizedBox(height: 16),
                BabifixButton(
                  label: 'Discuter avec $_claimedProviderName',
                  icon: Icons.chat_bubble_outline_rounded,
                  variant: BabifixButtonVariant.outlined,
                  backgroundColor: pal.cardBg,
                  foregroundColor: pal.textPrimary,
                  width: double.infinity,
                  height: 48,
                  onPressed: widget.onOpenChat ?? () {
                    Navigator.of(context).pushReplacement(
                      babifixRoute(
                        (_) => ChatRoomScreen(
                          name: _claimedProviderName ?? 'Artisan',
                          peerUserId: _claimedProviderId,
                          apiBase: babifixApiBaseUrl(),
                        ),
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 16),
              BabifixButton(
                label: 'Retour a l\'accueil',
                variant: BabifixButtonVariant.primary,
                width: double.infinity,
                height: 50,
                onPressed: widget.onClose,
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _DuplicateDialog extends StatelessWidget {
  const _DuplicateDialog({
    required this.accent,
    required this.icon,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final Color accent;
  final IconData icon;
  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final pal = _BookingPalette.of(context);
    return Dialog(
      backgroundColor: pal.cardBg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 60,
              height: 60,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: accent, size: 30),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: pal.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: pal.textMuted,
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: onPrimary,
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                primaryLabel,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (secondaryLabel != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: onSecondary,
                child: Text(
                  secondaryLabel!,
                  style: TextStyle(
                    color: pal.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RepereTextField extends StatelessWidget {
  const _RepereTextField({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final pal = _BookingPalette.of(context);
    return TextField(
      controller: controller,
      maxLength: 200,
      maxLines: 2,
      minLines: 1,
      style: TextStyle(color: pal.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        isDense: true,
        counterText: '',
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        filled: true,
        fillColor: pal.success.withValues(alpha: 0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: pal.success.withValues(alpha: 0.35)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: pal.success.withValues(alpha: 0.35)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: pal.success, width: 1.5),
        ),
        prefixIcon: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: pal.success.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.pin_drop_rounded, size: 18, color: pal.success),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        labelText: 'Point de repere (optionnel)',
        labelStyle: TextStyle(
          color: pal.success,
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
        ),
        hintText: 'ex : en face de la pharmacie Saint-Joseph',
        hintStyle: TextStyle(
          color: pal.textMuted,
          fontSize: 12.5,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

class _AvailabilityCalendar extends StatefulWidget {
  const _AvailabilityCalendar({
    required this.providerId,
    required this.selectedLabel,
    required this.onPick,
    this.onDateSelected,
  });

  final int providerId;
  final String selectedLabel;
  final ValueChanged<String> onPick;
  final ValueChanged<DateTime>? onDateSelected;

  @override
  State<_AvailabilityCalendar> createState() => _AvailabilityCalendarState();
}

class _AvailabilityCalendarState extends State<_AvailabilityCalendar> {
  static const _wd = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

  bool _loading = true;
  bool _hasAvailability = false;
  bool _error = false;
  List<Map<String, dynamic>> _days = [];
  int _selectedDayIndex = -1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final resp = await http.get(
        Uri.parse(
          '${babifixApiBaseUrl()}/api/public/providers/${widget.providerId}/availability/',
        ),
      );
      if (resp.statusCode == 200) {
        final j = jsonDecode(resp.body) as Map<String, dynamic>;
        final days = ((j['days'] as List?) ?? const []).cast<Map<String, dynamic>>();
        if (mounted) {
          setState(() {
            _hasAvailability = j['has_availability'] == true;
            _days = days.take(14).toList();
            _loading = false;
          });
        }
      } else if (mounted) {
        setState(() {
          _error = true;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = true;
          _loading = false;
        });
      }
    }
  }

  String _seg(String iso, int i) {
    final p = iso.split('-');
    return p.length == 3 ? p[i] : '';
  }

  void _pickSlot(Map<String, dynamic> day, Map<String, dynamic> slot) {
    final iso = '${day['date']}';
    final wd = (day['weekday'] as num?)?.toInt() ?? 0;
    final label =
        '${_wd[wd]} ${_seg(iso, 2)}/${_seg(iso, 1)} · ${slot['start']}-${slot['end']}';
    widget.onPick(label);
  }

  @override
  Widget build(BuildContext context) {
    final pal = _BookingPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.event_available_rounded, color: pal.accent, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Disponibilites du prestataire',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: pal.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: BabifixRingLoader.cyan(size: 28)),
          )
        else if (_error || !_hasAvailability)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: pal.softBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: pal.border),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, color: pal.accent, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _error
                        ? 'Disponibilites indisponibles pour le moment.'
                        : 'Ce prestataire n\'a pas encore publie de creneaux fixes.',
                    style: TextStyle(
                      color: pal.textMuted,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          )
        else ...[
          SizedBox(
            height: 98,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _days.length,
              itemBuilder: (_, i) => _dayChip(pal, i),
            ),
          ),
          _buildSlots(pal),
        ],
      ],
    );
  }

  Widget _dayChip(_BookingPalette pal, int index) {
    final day = _days[index];
    final available = day['available'] == true;
    final blocked = day['blocked'] == true;
    final selected = index == _selectedDayIndex;
    final iso = '${day['date']}';
    final wd = (day['weekday'] as num?)?.toInt() ?? 0;

    return GestureDetector(
      onTap: available
          ? () {
              final newIndex = selected ? -1 : index;
              setState(() => _selectedDayIndex = newIndex);
              if (newIndex >= 0) {
                final d = DateTime.tryParse('${day['date']}');
                if (d != null) widget.onDateSelected?.call(d);
              }
            }
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 62,
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: selected
              ? (pal.isLight ? BabifixDesign.navy : BabifixDesign.cyan)
              : (available ? pal.softBg : pal.pageBg),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? (pal.isLight ? BabifixDesign.navy : BabifixDesign.cyan)
                : (available
                    ? pal.success.withValues(alpha: 0.5)
                    : pal.border),
            width: available && !selected ? 1.3 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _wd[wd],
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: selected
                    ? (pal.isLight ? Colors.white70 : BabifixDesign.navy)
                    : (available ? pal.textMuted : pal.textMuted.withValues(alpha: 0.45)),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _seg(iso, 2),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                fontFeatures: BabifixDesign.tabularFigures,
                color: selected
                    ? (pal.isLight ? Colors.white : BabifixDesign.navy)
                    : (available
                        ? pal.textPrimary
                        : pal.textMuted.withValues(alpha: 0.45)),
              ),
            ),
            const SizedBox(height: 5),
            if (blocked)
              Icon(Icons.lock_rounded, size: 13, color: pal.danger)
            else if (available)
              Icon(
                Icons.check_circle_rounded,
                size: 13,
                color: selected ? Colors.white : pal.success,
              )
            else
              Icon(
                Icons.cancel_rounded,
                size: 13,
                color: pal.textMuted.withValues(alpha: 0.35),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlots(_BookingPalette pal) {
    if (_selectedDayIndex < 0 || _selectedDayIndex >= _days.length) {
      return const SizedBox.shrink();
    }
    final day = _days[_selectedDayIndex];
    final slots =
        ((day['slots'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final iso = '${day['date']}';
    final wd = (day['weekday'] as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Creneaux du ${_wd[wd]} ${_seg(iso, 2)}/${_seg(iso, 1)}',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: pal.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in slots)
                _slotChip(
                  pal,
                  day,
                  s,
                  '${_wd[wd]} ${_seg(iso, 2)}/${_seg(iso, 1)} · ${s['start']}-${s['end']}',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _slotChip(
    _BookingPalette pal,
    Map<String, dynamic> day,
    Map<String, dynamic> slot,
    String label,
  ) {
    final selected = widget.selectedLabel == label;
    return InkWell(
      onTap: () => _pickSlot(day, slot),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? BabifixDesign.navy : pal.softBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? BabifixDesign.navy : pal.border,
            width: selected ? 1.8 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.schedule_rounded,
              size: 15,
              color: selected ? Colors.white : pal.accent,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '${slot['start']} - ${slot['end']}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  fontFeatures: BabifixDesign.tabularFigures,
                  color: selected ? Colors.white : pal.textPrimary,
                ),
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 6),
              const Icon(Icons.check_rounded, size: 15, color: Colors.white),
            ],
          ],
        ),
      ),
    );
  }
}
