import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../shared/auth_utils.dart';
import '../../shared/services/nominatim_geocode.dart';
import '../../shared/services/smart_gps.dart';
import '../../shared/widgets/babifix_button.dart';
import '../../shared/widgets/babifix_mini_map.dart';
import '../../shared/widgets/babifix_page_route.dart';
import '../../shared/widgets/babifix_ring_loader.dart';
import '../../shared/widgets/babifix_snackbar.dart';
import '../../shared/widgets/smart_address_picker.dart';

class EditProfilePrestataireScreen extends StatefulWidget {
  final String? apiBase;
  final String? authToken;

  const EditProfilePrestataireScreen({super.key, this.apiBase, this.authToken});

  @override
  State<EditProfilePrestataireScreen> createState() =>
      _EditProfilePrestataireScreenState();
}

class _EditProfilePrestataireScreenState
    extends State<EditProfilePrestataireScreen> {
  final _nomCtrl = TextEditingController();
  final _specialiteCtrl = TextEditingController();
  final _villeCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _tarifCtrl = TextEditingController();
  final _expCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _savedOk = false;
  String? _error;
  String? _success;
  String _statut = '';
  String _categoryNom = '';
  String _cniRectoUrl = '';
  String _cniVersoUrl = '';
  String _portraitUrl = '';   // URL portrait actuel (serveur)
  String? _portraitB64;       // nouvelle photo choisie (data:image base64)

  // Localisation : le prestataire la partage explicitement (consentement) et
  // peut la modifier à tout moment depuis son profil.
  double? _lat;
  double? _lon;
  bool _locating = false;

  String get _base => widget.apiBase ?? babifixApiBaseUrl();

  Future<String?> _token() async {
    if (widget.authToken != null && widget.authToken!.isNotEmpty) return widget.authToken;
    return readStoredApiToken();
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nomCtrl.dispose();
    _specialiteCtrl.dispose();
    _villeCtrl.dispose();
    _bioCtrl.dispose();
    _tarifCtrl.dispose();
    _expCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final token = await _token();
    if (token == null) { setState(() => _loading = false); return; }
    try {
      final res = await http
          .get(Uri.parse('$_base/api/prestataire/profile'), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body) as Map<String, dynamic>;
        _nomCtrl.text = d['nom'] as String? ?? '';
        _specialiteCtrl.text = d['specialite'] as String? ?? '';
        _villeCtrl.text = d['ville'] as String? ?? '';
        _bioCtrl.text = d['bio'] as String? ?? '';
        _tarifCtrl.text = d['tarif_horaire'] != null ? '${d['tarif_horaire']}' : '';
        _expCtrl.text = d['years_experience'] != null ? '${d['years_experience']}' : '0';
        setState(() {
          _statut = d['statut'] as String? ?? '';
          _categoryNom = (d['category_nom'] ?? d['category'] ?? '').toString().trim();
          _cniRectoUrl = d['cni_recto_url'] as String? ?? '';
          _cniVersoUrl = d['cni_verso_url'] as String? ?? '';
          _portraitUrl = d['photo_portrait_url'] as String? ?? '';
          _lat = (d['latitude'] as num?)?.toDouble();
          _lon = (d['longitude'] as num?)?.toDouble();
          _loading = false;
        });
      } else { setState(() => _loading = false); }
    } catch (_) { setState(() => _loading = false); }
  }

  /// Applique une position choisie (GPS, tap carte ou selecteur plein ecran),
  /// met a jour automatiquement la carte ET le champ « Zone & commune »,
  /// puis enregistre immediatement cote serveur.
  Future<void> _applyAndPersistLocation(
    double lat,
    double lon, {
    String? knownLabel,
    bool showSuccessToast = true,
  }) async {
    String ville = (knownLabel ?? '').trim();
    if (ville.isEmpty) {
      try {
        final place = await nominatimReverse(lat, lon);
        ville = (place?.displayName ?? '').trim();
      } catch (_) {}
    }
    if (ville.isEmpty) {
      ville = resolveNearestCivCommune(lat, lon).displayName;
    }
    if (mounted) {
      setState(() {
        _lat = lat;
        _lon = lon;
        _villeCtrl.text = ville;
      });
    }
    final token = await _token();
    if (token == null) return;
    try {
      final res = await http.post(
        Uri.parse('$_base/api/prestataire/location/update'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'latitude': lat,
          'longitude': lon,
          'explicit_city': true,
          'ville': ville,
        }),
      ).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (res.statusCode == 200) {
        if (showSuccessToast) {
          showBabifixToast(
            context,
            type: BabifixToastType.success,
            message: 'Position mise a jour : $ville',
          );
        }
      } else {
        showBabifixToast(
          context,
          type: BabifixToastType.error,
          message: 'Echec de l\'enregistrement (${res.statusCode}).',
        );
      }
    } catch (_) {
      if (mounted) {
        showBabifixToast(
          context,
          type: BabifixToastType.warning,
          message: 'Position selectionnee localement. Cliquez sur Sauvegarder.',
        );
      }
    }
  }

  /// Ouvre la carte interactive plein ecran (identique a l'app Client).
  Future<void> _openFullMapPicker() async {
    final picked = await Navigator.of(context).push<PickedProLocation>(
      babifixRoute(
        (_) => SmartProAddressPicker(
          initialLat: _lat,
          initialLon: _lon,
          initialLabel: _villeCtrl.text.trim().isEmpty
              ? null
              : _villeCtrl.text.trim(),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _locating = true);
    try {
      await _applyAndPersistLocation(
        picked.lat,
        picked.lon,
        knownLabel: picked.label,
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// Partage de la position GPS avec mise a jour automatique du champ Zone/Commune.
  Future<void> _shareMyLocation() async {
    if (_locating) return;
    setState(() { _locating = true; });
    try {
      final gps = await acquireSmartGps(forceFresh: true);
      if (!mounted) return;
      if (gps.permissionDeniedForever) {
        showBabifixToast(
          context,
          type: BabifixToastType.warning,
          message: gps.friendlyMessage ?? 'Autorisation bloquee. Activez-la dans les reglages.',
        );
        await Geolocator.openAppSettings();
        return;
      }
      if (gps.hasHardError) {
        showBabifixToast(
          context,
          type: BabifixToastType.warning,
          message: gps.friendlyMessage ?? 'Activez la localisation sur votre telephone.',
        );
        return;
      }
      final lat = gps.position?.latitude ?? kCivAbidjanLat;
      final lon = gps.position?.longitude ?? kCivAbidjanLon;
      await _applyAndPersistLocation(lat, lon);
    } catch (_) {
      if (mounted) {
        showBabifixToast(
          context,
          type: BabifixToastType.info,
          message: 'Touchez la carte ou choisissez votre commune ci-dessus.',
        );
      }
    } finally {
      if (mounted) setState(() { _locating = false; });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    HapticFeedback.selectionClick();
    setState(() {
      _saving = true;
      _savedOk = false;
      _error = null;
      _success = null;
    });
    var token = await _token();
    if (token == null || token.isEmpty) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Session expiree. Reconnectez-vous.';
        });
        showBabifixToast(
          context,
          type: BabifixToastType.error,
          message: 'Session expiree. Reconnectez-vous.',
        );
      }
      return;
    }
    final payload = <String, dynamic>{
      'nom': _nomCtrl.text.trim(),
      'specialite': _specialiteCtrl.text.trim(),
      'ville': _villeCtrl.text.trim(),
      'bio': _bioCtrl.text.trim(),
      if (_lat != null) 'latitude': _lat,
      if (_lon != null) 'longitude': _lon,
    };
    if (_expCtrl.text.trim().isNotEmpty) {
      payload['years_experience'] = int.tryParse(_expCtrl.text.trim());
    }
    if (_portraitB64 != null && _portraitB64!.isNotEmpty) {
      payload['photo_portrait_b64'] = _portraitB64;
    }
    try {
      Future<http.StreamedResponse> sendPatch(String tok) async {
        final req = http.Request('PATCH', Uri.parse('$_base/api/prestataire/profile'));
        req.headers['Authorization'] = 'Bearer $tok';
        req.headers['Content-Type'] = 'application/json';
        req.body = jsonEncode(payload);
        return req.send().timeout(const Duration(seconds: 18));
      }

      var streamedRes = await sendPatch(token);
      if (streamedRes.statusCode == 401) {
        final fresh = await babifixRefreshAccessToken();
        if (fresh != null && fresh.isNotEmpty) {
          token = fresh;
          streamedRes = await sendPatch(fresh);
        }
      }
      final body = await streamedRes.stream.bytesToString();
      if (!mounted) return;
      if (streamedRes.statusCode == 200) {
        HapticFeedback.mediumImpact();
        setState(() {
          _saving = false;
          _savedOk = true;
          _success = 'Profil mis a jour avec succes.';
        });
        showBabifixToast(
          context,
          type: BabifixToastType.success,
          message: 'Profil enregistre avec succes !',
        );
        await Future.delayed(const Duration(milliseconds: 550));
        if (mounted) Navigator.of(context).pop(true);
      } else {
        String errMsg = 'Impossible d\'enregistrer (HTTP ${streamedRes.statusCode}).';
        try {
          final parsed = jsonDecode(body);
          if (parsed is Map) {
            errMsg = (parsed['message'] ?? parsed['error'] ?? errMsg).toString();
          }
        } catch (_) {}
        setState(() {
          _saving = false;
          _error = errMsg;
        });
        showBabifixToast(
          context,
          type: BabifixToastType.error,
          message: errMsg,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Erreur reseau. Verifiez votre connexion.';
        });
        showBabifixToast(
          context,
          type: BabifixToastType.error,
          message: 'Erreur reseau. Verifiez votre connexion.',
        );
      }
    }
  }

  Future<void> _pickPortrait() async {
    try {
      final picker = ImagePicker();
      final x = await picker.pickImage(
          source: ImageSource.gallery, imageQuality: 70, maxWidth: 800);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      if (bytes.lengthInBytes > 3 * 1024 * 1024) {
        if (mounted) setState(() => _error = 'Photo trop lourde (3 Mo max).');
        return;
      }
      final ext = x.path.split('.').last.toLowerCase();
      final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
      setState(() {
        _portraitB64 = 'data:$mime;base64,${base64Encode(bytes)}';
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Impossible de charger la photo.');
    }
  }

  Widget _buildPortraitPicker() {
    ImageProvider? provider;
    if (_portraitB64 != null && _portraitB64!.isNotEmpty) {
      try {
        provider = MemoryImage(base64Decode(_portraitB64!.split(',').last));
      } catch (_) {}
    } else if (_portraitUrl.isNotEmpty) {
      final url = _portraitUrl.startsWith('http')
          ? _portraitUrl
          : '$_base$_portraitUrl';
      provider = NetworkImage(url);
    }
    return Center(
      child: Column(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 48,
                backgroundColor: const Color(0xFF152138),
                backgroundImage: provider,
                child: provider == null
                    ? Text(
                        _nomCtrl.text.isNotEmpty
                            ? _nomCtrl.text.characters.first.toUpperCase()
                            : 'P',
                        style: const TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            color: Colors.white),
                      )
                    : null,
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: GestureDetector(
                  onTap: _pickPortrait,
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: const BoxDecoration(
                      color: BabifixDesign.cyan,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.photo_camera_rounded,
                        size: 18, color: BabifixDesign.navy),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _pickPortrait,
            icon: const Icon(Icons.edit_rounded, size: 16),
            label: const Text('Modifier la photo de profil'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Scaffold(
      backgroundColor: isLight
          ? Theme.of(context).scaffoldBackgroundColor
          : BabifixDesign.navy,
      body: _loading
          ? const Center(child: BabifixRingLoader.cyan(size: 28))
          : CustomScrollView(slivers: [
              _buildAppBar(),
              SliverToBoxAdapter(child: _buildBody()),
            ]),
      bottomSheet: _buildSaveBar(),
    );
  }

  Widget _buildAppBar() {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final fg = isLight ? const Color(0xFF0B1B34) : Colors.white;
    final bg = isLight ? Colors.white : BabifixDesign.navy;
    final subColor = isLight ? const Color(0xFF64748B) : Colors.white70;
    return SliverAppBar(
      pinned: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_rounded, color: fg),
        onPressed: () => Navigator.pop(context),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Modifier mon profil',
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w800,
              fontSize: 17,
              letterSpacing: -0.3,
            ),
          ),
          if (_nomCtrl.text.trim().isNotEmpty)
            Text(
              _nomCtrl.text.trim(),
              style: TextStyle(
                color: subColor,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Divider(
          height: 1,
          color: isLight ? const Color(0xFFE2E8F0) : const Color(0xFF1E3A63),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final isWhite =
        Theme.of(context).scaffoldBackgroundColor == const Color(0xFFFFFFFF);
    return Container(
      decoration: BoxDecoration(
        color: isWhite
            ? Colors.white
            : (isLight ? const Color(0xFFF1F5F9) : null),
        gradient: isLight
            ? null
            : const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0B1B34), Color(0xFF081428)],
              ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_statut.isNotEmpty) _StatutBadgePremium(statut: _statut),
          if (_success != null) _AlertPremium(message: _success!, color: BabifixDesign.success, icon: Icons.check_circle_rounded),
          if (_error != null) _AlertPremium(message: _error!, color: BabifixDesign.error, icon: Icons.error_rounded),
          const SizedBox(height: 16),

          // Photo de profil (portrait) — visible par les clients
          _buildPortraitPicker(),
          const SizedBox(height: 16),

          // Informations personnelles
          _SectionCardPremium(
            icon: Icons.person_rounded,
            title: 'Informations personnelles',
            subtitle: 'Votre identite et localisation',
            color: BabifixDesign.cyan,
            child: Column(
              children: [
                _PremiumField(controller: _nomCtrl, label: "Nom complet ou raison sociale", icon: Icons.badge_rounded),
                const SizedBox(height: 12),
                if (_categoryNom.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: isLight
                          ? const Color(0xFFF0F9FF)
                          : const Color(0xFF0F2544),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF4CC9F0).withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.verified_rounded,
                          size: 18,
                          color: Color(0xFF0284C7),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Catégorie principale rattachée',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: isLight
                                      ? const Color(0xFF0369A1)
                                      : const Color(0xFF7DD3FC),
                                ),
                              ),
                              Text(
                                _categoryNom,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                  color: isLight
                                      ? const Color(0xFF0B1B34)
                                      : Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                _PremiumField(
                  controller: _specialiteCtrl,
                  label: "Précision / Savoir-faire",
                  icon: Icons.work_rounded,
                  hint: _categoryNom.isNotEmpty
                      ? "Précisez votre spécialité en $_categoryNom"
                      : "Ex: Recherche de fuite, installation...",
                ),
                const SizedBox(height: 12),
                _PremiumField(controller: _villeCtrl, label: "Zone & commune d'intervention", icon: Icons.location_on_rounded, hint: "Ex: Cocody, Abidjan"),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Localisation (partage avec consentement)
          _SectionCardPremium(
            icon: Icons.my_location_rounded,
            title: 'Ma position sur la carte',
            subtitle: 'Touchez la carte ou ouvrez-la pour choisir votre zone',
            color: BabifixDesign.ciGreen,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    BabifixMiniMap(
                      lat: _lat ?? kCivAbidjanLat,
                      lon: _lon ?? kCivAbidjanLon,
                      height: 195,
                      pinColor: BabifixDesign.ciGreen,
                      pinIcon: Icons.location_on_rounded,
                      zoom: 14.5,
                      interactive: true,
                      onTap: (LatLng p) async {
                        if (_locating) return;
                        setState(() => _locating = true);
                        try {
                          await _applyAndPersistLocation(
                            p.latitude,
                            p.longitude,
                          );
                        } finally {
                          if (mounted) setState(() => _locating = false);
                        }
                      },
                    ),
                    Positioned(
                      right: 10,
                      top: 10,
                      child: Material(
                        color: Colors.white,
                        elevation: 3,
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: _locating ? null : _openFullMapPicker,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.open_in_full_rounded,
                                  size: 14,
                                  color: Color(0xFF0B1B34),
                                ),
                                SizedBox(width: 5),
                                Text(
                                  'Agrandir',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF0B1B34),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: (_lat != null && _lon != null
                            ? BabifixDesign.ciGreen
                            : BabifixDesign.ciOrange)
                        .withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _lat != null && _lon != null
                            ? Icons.check_circle_rounded
                            : Icons.place_outlined,
                        size: 18,
                        color: _lat != null && _lon != null
                            ? BabifixDesign.ciGreen
                            : BabifixDesign.ciOrange,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _lat != null && _lon != null
                              ? (_villeCtrl.text.trim().isNotEmpty
                                  ? 'Zone active : ${_villeCtrl.text.trim()}'
                                  : 'Position partagee sur la carte.')
                              : 'Touchez la carte ou choisissez votre position ci-dessous.',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                            color: isLight ? const Color(0xFF0F172A) : Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _locating ? null : _openFullMapPicker,
                        icon: const Icon(Icons.map_rounded, size: 17),
                        label: const Text(
                          'Choisir sur carte',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: BabifixDesign.ciGreen,
                          side: const BorderSide(color: BabifixDesign.ciGreen, width: 1.3),
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _locating ? null : _shareMyLocation,
                        icon: _locating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: BabifixRingLoader.cyan(size: 16),
                              )
                            : const Icon(Icons.my_location_rounded, size: 17),
                        label: const Text(
                          'Me localiser',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: BabifixDesign.ciGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Chaque choix sur la carte met a jour automatiquement votre commune dans le formulaire.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8), height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // A propos
          _SectionCardPremium(
            icon: Icons.description_rounded,
            title: 'À propos de vous',
            subtitle: 'Décrivez votre expérience et vos garanties',
            color: BabifixDesign.ciOrange,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Assistant de présentation intelligent',
                        style: TextStyle(
                          color: isLight ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        final yrs = int.tryParse(_expCtrl.text.trim()) ?? 3;
                        final spec = _specialiteCtrl.text.trim().isNotEmpty
                            ? _specialiteCtrl.text.trim()
                            : 'dépannage et installation';
                        final vil = _villeCtrl.text.trim().isNotEmpty
                            ? _villeCtrl.text.trim()
                            : 'ma ville';
                        final expText = yrs > 0 ? "$yrs ans d'expérience" : "une solide expérience terrain";
                        setState(() {
                          _bioCtrl.text =
                              "Spécialiste en $spec avec $expText. "
                              "J'interviens rapidement à $vil et ses environs pour tous vos travaux d'installation, diagnostic et réparation. "
                              "Devis transparent, matériel professionnel et travail soigné garanti.";
                        });
                      },
                      icon: const Icon(Icons.auto_awesome_rounded, size: 15, color: Color(0xFF38BDF8)),
                      label: const Text(
                        'Rédiger auto',
                        style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _PremiumTextField(
                  controller: _bioCtrl,
                  label: 'Biographie / Description',
                  hint: 'Décrivez votre expérience, vos compétences...',
                  maxLines: 4,
                  maxLength: 500,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Expérience (le tarif horaire est supprimé : chaque devis a
          // son propre prix calculé sur place selon la prestation).
          _SectionCardPremium(
            icon: Icons.star_rounded,
            title: 'Expérience',
            subtitle: 'Vos années dans le métier',
            color: BabifixDesign.ciGreen,
            child: _PremiumField(
              controller: _expCtrl,
              label: "Années d'expérience",
              icon: Icons.star_rounded,
              keyboardType: TextInputType.number,
            ),
          ),
          const SizedBox(height: 16),

          // Documents d'identite
          _SectionCardPremium(
            icon: Icons.credit_card_rounded,
            title: 'Piece d\'identite',
            subtitle: 'CNI ou Passeport - Recto / Verso',
            color: const Color(0xFF7C3AED),
            child: Row(
              children: [
                Expanded(child: _CniUploaderPremium(label: 'Recto', currentUrl: _cniRectoUrl,
                    uploadEndpoint: '$_base/api/prestataire/upload/cni-recto/', authToken: widget.authToken,
                    onUploaded: (url) => setState(() => _cniRectoUrl = url))),
                const SizedBox(width: 12),
                Expanded(child: _CniUploaderPremium(label: 'Verso', currentUrl: _cniVersoUrl,
                    uploadEndpoint: '$_base/api/prestataire/upload/cni-verso/', authToken: widget.authToken,
                    onUploaded: (url) => setState(() => _cniVersoUrl = url))),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Portfolio
          _SectionCardPremium(
            icon: Icons.photo_library_rounded,
            title: 'Galerie de realisations',
            subtitle: 'Photos de vos travaux',
            color: const Color(0xFF22C55E),
            child: _PortfolioEditorPremium(apiBase: _base, authToken: widget.authToken),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveBar() {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      decoration: BoxDecoration(
        color: isLight ? Colors.white : BabifixDesign.navy,
        border: Border(
          top: BorderSide(
            color: BabifixDesign.borderOf(context),
          ),
        ),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewPaddingOf(context).bottom + 8,
        left: 16, right: 16, top: 12,
      ),
      child: BabifixButton(
        label: _savedOk ? 'Enregistre !' : 'Sauvegarder les modifications',
        loadingLabel: 'Enregistrement...',
        icon: _savedOk ? Icons.check_circle_rounded : Icons.save_rounded,
        isLoading: _saving,
        onPressed: _saving ? null : _save,
      ),
    );
  }
}

// ─── Premium Section Card ─────────────────────────────────────────────────────

class _SectionCardPremium extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Widget child;

  const _SectionCardPremium({
    required this.icon, required this.title, required this.subtitle,
    required this.color, required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: isLight ? Colors.white : null,
        gradient: isLight
            ? null
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0F1D33), Color(0xFF0B1525)],
              ),
        border: Border.all(color: color.withValues(alpha: isLight ? 0.32 : 0.15)),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [color.withValues(alpha: 0.2), color.withValues(alpha: 0.08)]),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: isLight ? const Color(0xFF0F172A) : Colors.white)),
                    Text(subtitle, style: TextStyle(fontSize: 11, color: isLight ? const Color(0xFF64748B) : Colors.white.withValues(alpha: 0.45))),
                  ],
                )),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

// ─── Premium Field ────────────────────────────────────────────────────────────

class _PremiumField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType keyboardType;
  final String? hint;

  const _PremiumField({
    required this.controller, required this.label, required this.icon,
    this.keyboardType = TextInputType.text, this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: TextStyle(color: isLight ? const Color(0xFF0F172A) : Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        alignLabelWithHint: true,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: isLight ? const Color(0xFF475569) : Colors.white.withValues(alpha: 0.4), fontSize: 12),
        prefixIcon: Icon(icon, size: 18, color: BabifixDesign.cyan.withValues(alpha: 0.85)),
        filled: true,
        fillColor: isLight ? const Color(0xFFF8FAFC) : const Color(0xFF0A1220),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isLight ? const Color(0xFFCBD5E1) : Colors.white.withValues(alpha: 0.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isLight ? const Color(0xFFCBD5E1) : Colors.white.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: BabifixDesign.cyan, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}

// ─── Premium TextField (multi-line) ───────────────────────────────────────────

class _PremiumTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLines;
  final int? maxLength;

  const _PremiumTextField({
    required this.controller, required this.label, required this.hint,
    this.maxLines = 1, this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return TextField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      style: TextStyle(color: isLight ? const Color(0xFF0F172A) : Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        alignLabelWithHint: true,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: isLight ? const Color(0xFF475569) : Colors.white.withValues(alpha: 0.4), fontSize: 12),
        hintStyle: TextStyle(color: isLight ? const Color(0xFF94A3B8) : Colors.white.withValues(alpha: 0.25), fontSize: 12),
        filled: true,
        fillColor: isLight ? const Color(0xFFF8FAFC) : const Color(0xFF0A1220),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isLight ? const Color(0xFFCBD5E1) : Colors.white.withValues(alpha: 0.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isLight ? const Color(0xFFCBD5E1) : Colors.white.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: BabifixDesign.ciOrange, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        counterStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11),
      ),
    );
  }
}

// ─── Statut Badge Premium ─────────────────────────────────────────────────────

class _StatutBadgePremium extends StatelessWidget {
  final String statut;
  const _StatutBadgePremium({required this.statut});

  @override
  Widget build(BuildContext context) {
    Color color; String label;
    switch (statut) {
      case 'Valide': color = BabifixDesign.success; label = 'Compte valide'; break;
      case 'En attente': color = BabifixDesign.warning; label = 'En attente de validation'; break;
      case 'Refuse': color = BabifixDesign.error; label = 'Dossier refuse'; break;
      default: color = Colors.grey; label = statut;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(colors: [color.withValues(alpha: 0.15), color.withValues(alpha: 0.05)]),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.verified_rounded, color: color, size: 16),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
      ]),
    );
  }
}

// ─── Alert Premium ────────────────────────────────────────────────────────────

class _AlertPremium extends StatelessWidget {
  final String message;
  final Color color;
  final IconData icon;
  const _AlertPremium({required this.message, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(colors: [color.withValues(alpha: 0.1), color.withValues(alpha: 0.03)]),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

// ─── CNI Uploader Premium ─────────────────────────────────────────────────────

class _CniUploaderPremium extends StatefulWidget {
  final String label;
  final String currentUrl;
  final String uploadEndpoint;
  final String? authToken;
  final void Function(String url) onUploaded;

  const _CniUploaderPremium({
    required this.label, required this.currentUrl,
    required this.uploadEndpoint, required this.onUploaded, this.authToken,
  });

  @override
  State<_CniUploaderPremium> createState() => _CniUploaderPremiumState();
}

class _CniUploaderPremiumState extends State<_CniUploaderPremium> {
  bool _uploading = false;
  late String _url;

  @override
  void initState() { super.initState(); _url = widget.currentUrl; }

  Future<String?> _token() async {
    if (widget.authToken != null && widget.authToken!.isNotEmpty) return widget.authToken;
    return readStoredApiToken();
  }

  Future<void> _pick() async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 1800);
    if (xfile == null) return;
    setState(() => _uploading = true);
    final token = await _token();
    try {
      final req = http.MultipartRequest('POST', Uri.parse(widget.uploadEndpoint));
      req.headers['Authorization'] = 'Bearer $token';
      req.files.add(await http.MultipartFile.fromPath('file', xfile.path));
      final streamed = await req.send().timeout(const Duration(seconds: 30));
      final body = await streamed.stream.bytesToString();
      if (streamed.statusCode == 200) {
        final data = jsonDecode(body) as Map<String, dynamic>;
        final url = data['url'] as String? ?? '';
        setState(() => _url = url);
        widget.onUploaded(url);
        if (mounted) showBabifixToast(
        context,
        type: BabifixToastType.info,
        message: '${widget.label} uploade',
      );
      } else {
        final err = (jsonDecode(body) as Map<String, dynamic>)['error'] ?? 'Erreur upload';
        if (mounted) showBabifixToast(
        context,
        type: BabifixToastType.info,
        message: err.toString(),
      );
      }
    } catch (_) {
      if (mounted) showBabifixToast(
        context,
        type: BabifixToastType.error,
        message: 'Erreur reseau',
      );
    } finally { if (mounted) setState(() => _uploading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final hasDoc = _url.isNotEmpty;
    return GestureDetector(
      onTap: _uploading ? null : _pick,
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: (!hasDoc && isLight) ? const Color(0xFFF8FAFC) : null,
          gradient: hasDoc
              ? LinearGradient(colors: [const Color(0xFF1A3A6E).withValues(alpha: 0.3), const Color(0xFF0B1B34).withValues(alpha: 0.2)])
              : (isLight ? null : const LinearGradient(colors: [Color(0xFF0A1220), Color(0xFF081018)])),
          border: Border.all(
            color: hasDoc
                ? BabifixDesign.ciOrange.withValues(alpha: 0.4)
                : (isLight ? const Color(0xFFCBD5E1) : Colors.white.withValues(alpha: 0.08)),
            width: hasDoc ? 1.5 : 1,
          ),
        ),
        child: _uploading
            ? const Center(child: BabifixRingLoader.cyan(size: 28))
            : hasDoc
                ? Stack(children: [
                    ClipRRect(borderRadius: BorderRadius.circular(15), child: Image.network(_url,
                        width: double.infinity, height: double.infinity, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_rounded, color: Colors.grey)))),
                    Positioned(bottom: 0, left: 0, right: 0, child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                        gradient: LinearGradient(colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)]),
                      ),
                      child: Text(widget.label, textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                    )),
                    Positioned(top: 8, right: 8, child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(color: BabifixDesign.cyan, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.edit_rounded, color: Colors.white, size: 13),
                    )),
                  ])
                : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(shape: BoxShape.circle,
                        gradient: LinearGradient(colors: [BabifixDesign.cyan.withValues(alpha: 0.15), BabifixDesign.cyan.withValues(alpha: 0.05)]),
                      ),
                      child: Icon(Icons.credit_card_rounded, color: isLight ? BabifixDesign.cyan : BabifixDesign.iconOnDark, size: 20),
                    ),
                    const SizedBox(height: 8),
                    Text(widget.label, textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: isLight ? const Color(0xFF0F172A) : Colors.white, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text('Appuyer pour ajouter',
                        style: TextStyle(fontSize: 10, color: isLight ? const Color(0xFF64748B) : Colors.white.withValues(alpha: 0.35))),
                  ]),
      ),
    );
  }
}

// ─── Portfolio Editor Premium ─────────────────────────────────────────────────

class _PortfolioEditorPremium extends StatefulWidget {
  final String apiBase;
  final String? authToken;
  const _PortfolioEditorPremium({required this.apiBase, this.authToken});

  @override
  State<_PortfolioEditorPremium> createState() => _PortfolioEditorPremiumState();
}

class _PortfolioEditorPremiumState extends State<_PortfolioEditorPremium> {
  List<Map<String, dynamic>> _photos = [];
  bool _loading = true;
  bool _uploading = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<String?> _token() async {
    if (widget.authToken != null && widget.authToken!.isNotEmpty) return widget.authToken;
    return readStoredApiToken();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final token = await _token();
    if (token == null) { setState(() => _loading = false); return; }
    try {
      final res = await http.get(Uri.parse('${widget.apiBase}/api/prestataire/portfolio'),
          headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() { _photos = ((data['photos'] as List?) ?? []).cast<Map<String, dynamic>>().toList(); _loading = false; });
      } else { setState(() => _loading = false); }
    } catch (_) { setState(() => _loading = false); }
  }

  Widget _buildPhoto(String src, double size) {
    final ph = Container(width: size, height: size, color: const Color(0xFF0A1220),
        child: const Icon(Icons.photo_outlined, color: Colors.grey, size: 24));
    if (src.isEmpty) return ph;
    if (src.startsWith('data:image/')) {
      try { final bytes = base64Decode(src.split(',').last); return Image.memory(bytes, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, __, ___) => ph); }
      catch (_) { return ph; }
    }
    if (src.startsWith('http://') || src.startsWith('https://')) return Image.network(src, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, __, ___) => ph);
    try { final f = File(src); if (f.existsSync()) return Image.file(f, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, __, ___) => ph); } catch (_) {}
    return ph;
  }

  Future<void> _addPhoto() async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 60, maxWidth: 1024);
    if (xfile == null) return;
    final bytes = await xfile.readAsBytes();
    final ext = xfile.path.split('.').last.toLowerCase();
    final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
    final b64 = 'data:$mime;base64,${base64Encode(bytes)}';
    setState(() => _uploading = true);
    final token = await _token();
    try {
      final res = await http.post(Uri.parse('${widget.apiBase}/api/prestataire/portfolio'),
          headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
          body: jsonEncode({'photo': b64, 'caption': ''}));
      if (res.statusCode == 200) { _load(); }
      else {
        final err = jsonDecode(res.body)['error'] ?? 'Erreur';
        if (mounted) showBabifixToast(
        context,
        type: BabifixToastType.error,
        message: 'Impossible d\'ajouter : $err',
      );
      }
    } catch (_) {
      if (mounted) showBabifixToast(
        context,
        type: BabifixToastType.error,
        message: 'Erreur reseau',
      );
    }
    setState(() => _uploading = false);
  }

  Future<void> _deletePhoto(int idx) async {
    final token = await _token();
    try {
      final req = http.Request('DELETE', Uri.parse('${widget.apiBase}/api/prestataire/portfolio/$idx'));
      req.headers['Authorization'] = 'Bearer $token';
      final streamedRes = await req.send().timeout(const Duration(seconds: 10));
      if (streamedRes.statusCode == 200) _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: BabifixRingLoader.cyan(size: 28));
    return Wrap(spacing: 10, runSpacing: 10, children: [
      ..._photos.asMap().entries.map((entry) {
        final i = entry.key;
        final src = entry.value['photo'] as String? ?? '';
        return Stack(children: [
          ClipRRect(borderRadius: BorderRadius.circular(12), child: _buildPhoto(src, 85)),
          Positioned(top: 4, right: 4, child: GestureDetector(onTap: () => _deletePhoto(i),
              child: Container(width: 22, height: 22, decoration: const BoxDecoration(color: BabifixDesign.error, shape: BoxShape.circle),
                  child: const Icon(Icons.close_rounded, size: 12, color: Colors.white)))),
        ]);
      }),
      if (_photos.length < 12)
        GestureDetector(onTap: _uploading ? null : _addPhoto,
            child: Container(width: 85, height: 85,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(colors: [const Color(0xFF0A1220), const Color(0xFF081018)]),
                  border: Border.all(color: BabifixDesign.cyan.withValues(alpha: 0.2), style: BorderStyle.solid, width: 1.5),
                ),
                child: _uploading
                    ? const Center(child: BabifixRingLoader.cyan(size: 28))
                    : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Container(width: 32, height: 32, decoration: BoxDecoration(shape: BoxShape.circle,
                            gradient: LinearGradient(colors: [BabifixDesign.cyan.withValues(alpha: 0.15), BabifixDesign.cyan.withValues(alpha: 0.05)])),
                            child: Icon(Icons.add_photo_alternate_rounded, color: BabifixDesign.iconOnDark, size: 18)),
                        const SizedBox(height: 4),
                        const Text('Ajouter', style: TextStyle(fontSize: 10, color: BabifixDesign.cyan, fontWeight: FontWeight.w600)),
                      ]))),
    ]);
  }
}
