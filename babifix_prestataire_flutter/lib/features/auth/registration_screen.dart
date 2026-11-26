import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, TargetPlatform, defaultTargetPlatform;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

import '../../babifix_api_config.dart';
import '../../json_utils.dart';
import '../../shared/auth_utils.dart';
import '../../shared/services/nominatim_geocode.dart';
import '../../shared/services/smart_gps.dart';
import '../../shared/widgets/address_search_field.dart';
import '../../shared/widgets/babifix_mini_map.dart';
import '../../shared/widgets/babifix_page_route.dart';
import '../../shared/widgets/babifix_ring_loader.dart';
import '../../shared/widgets/babifix_snackbar.dart';
import '../../shared/widgets/smart_address_picker.dart';
import 'email_verification_screen.dart';

// =============================================================================
// Wizard d'inscription prestataire — 3 étapes
//   Étape 0 : Identité & Compte
//   Étape 1 : Profil Professionnel
//   Étape 2 : Documents (photo + CNI recto/verso)
// =============================================================================

// ── Design tokens ─────────────────────────────────────────────────────────────
const _kNavyDeep = Color(0xFF08101E);
const _kNavy = Color(0xFF0B1626);
const _kCyan = Color(0xFF0284C7);
const _kBlue = Color(0xFF0284C7);
const _kGreen = Color(0xFF059669);
const _kBlueDeep = Color(0xFF0284C7);

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({
    super.key,
    required this.onBack,
    required this.onSubmit,
    required this.onAuthReady,
    this.credentialLock = false,
    this.documentsLocked = false,
    this.initialProvider,
    this.preloadedCategories,
  });

  final VoidCallback onBack;
  final VoidCallback onSubmit;
  final Future<void> Function() onAuthReady;

  /// Après un refus : compte déjà créé — ne pas redemander e-mail/mot de passe.
  final bool credentialLock;

  /// Documents vérifiés : photo et CNI verrouillés.
  final bool documentsLocked;

  final Map<String, dynamic>? initialProvider;

  /// Catégories pré-chargées depuis le main (pour éviter double appel API)
  final List<Map<String, dynamic>>? preloadedCategories;

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen>
    with SingleTickerProviderStateMixin {
  // ── Etapes ────────────────────────────────────────────────────────────────
  int _step = 0;
  static const int _kSteps = 3;
  bool _expressMode = false;
  int get _totalSteps => _expressMode ? 2 : _kSteps;

  // ── Clés de formulaire par étape ─────────────────────────────────────────
  final _formStep0 = GlobalKey<FormState>();
  final _formStep1 = GlobalKey<FormState>();

  // ── Controllers étape 0 ───────────────────────────────────────────────────
  final _prenomCtrl = TextEditingController();
  final _nomCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();
  bool _passVisible = false;
  bool _pass2Visible = false;
  String _phoneE164 = '';

  // ── Controllers étape 1 ───────────────────────────────────────────────────
  final _villeCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _metierProposeCtrl = TextEditingController();
  String? _specialite;
  int? _categoryId;
  String _metierPropose = '';
  final Map<String, dynamic> _specAnswers = {};
  List<Map<String, dynamic>> _publicCategories = [];
  bool _loadingCategories = true;
  double _yearsExperience = 3;
  LatLng? _villePin;
  String _villeAddressLabel = '';
  bool _locating = false;

  Map<String, dynamic>? get _selectedCategory {
    if (_categoryId == null) return null;
    for (final c in _publicCategories) {
      if (jsonInt(c['id']) == _categoryId) return c;
    }
    return null;
  }

  bool get _isSensibleCategory =>
      (_selectedCategory?['regime_kyc'] ?? '').toString() == 'SENSIBLE_CASIER';

  List<Map<String, dynamic>> get _registrationQuestions {
    final raw = _selectedCategory?['registration_questions'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((e) => (e['key'] ?? '').toString().isNotEmpty)
          .toList();
    }
    return const [];
  }

  static String _normalizeRegSearch(String input) {
    var s = input.toLowerCase().trim();
    const pairs = {
      'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a',
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'î': 'i', 'ï': 'i', 'ì': 'i', 'í': 'i',
      'ô': 'o', 'ö': 'o', 'ò': 'o', 'ó': 'o',
      'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u',
      'ç': 'c', 'ñ': 'n',
    };
    pairs.forEach((k, v) => s = s.replaceAll(k, v));
    return s;
  }

  Future<void> _applyRegistrationPin(LatLng pin, {String? knownLabel}) async {
    final immediate = (knownLabel ?? '').trim().isNotEmpty
        ? knownLabel!.trim()
        : resolveNearestCivCommune(pin.latitude, pin.longitude).displayName;
    if (mounted) {
      setState(() {
        _villePin = pin;
        _villeCtrl.text = immediate;
        _villeAddressLabel = immediate;
      });
    }
    if ((knownLabel ?? '').trim().isEmpty) {
      try {
        final place = await nominatimReverse(pin.latitude, pin.longitude);
        final label = (place?.displayName ?? '').trim();
        if (label.isNotEmpty && mounted) {
          setState(() {
            _villeCtrl.text = label;
            _villeAddressLabel = label;
          });
        }
      } catch (_) {}
    }
  }

  Future<void> _openRegistrationMapPicker() async {
    final picked = await Navigator.of(context).push<PickedProLocation>(
      babifixRoute(
        (_) => SmartProAddressPicker(
          initialLat: _villePin?.latitude,
          initialLon: _villePin?.longitude,
          initialLabel: _villeCtrl.text.trim().isEmpty
              ? null
              : _villeCtrl.text.trim(),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await _applyRegistrationPin(
      LatLng(picked.lat, picked.lon),
      knownLabel: picked.label,
    );
  }

  /// « Me localiser » : recupere la position GPS et remplit la commune
  /// automatiquement (reverse geocoding + repli propre sans erreur).
  Future<void> _locateMe() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final gps = await acquireSmartGps(forceFresh: true);
      if (!mounted) return;
      if (gps.permissionDeniedForever) {
        _snack(gps.friendlyMessage ?? 'Acces position bloque. Activez-le dans les reglages.');
        await Geolocator.openAppSettings();
        return;
      }
      if (gps.hasHardError) {
        _snack(gps.friendlyMessage ?? 'Activez la localisation sur votre telephone.');
        return;
      }
      final pin = gps.position ?? const LatLng(kCivAbidjanLat, kCivAbidjanLon);
      await _applyRegistrationPin(pin);
      if (mounted) {
        _snack('Commune definie : ${_villeCtrl.text}');
      }
    } catch (_) {
      await _applyRegistrationPin(const LatLng(kCivAbidjanLat, kCivAbidjanLon));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  String _resolvedMetierLabel() {
    if (_specialite != null && _specialite!.trim().isNotEmpty) {
      return _specialite!.trim();
    }
    if (_categoryId != null && _publicCategories.isNotEmpty) {
      final match = _publicCategories.firstWhere(
        (c) => jsonInt(c['id']) == _categoryId,
        orElse: () => <String, dynamic>{},
      );
      final nom = '${match['nom'] ?? ''}'.trim();
      if (nom.isNotEmpty) return nom;
    }
    return 'dépannage et travaux techniques';
  }

  String _resolvedZoneLabel() {
    final v = _villeCtrl.text.trim();
    if (v.isNotEmpty && v.toLowerCase() != 'abidjan') return v;
    if (_villeAddressLabel.trim().isNotEmpty) return _villeAddressLabel.trim();
    return 'Cocody, Marcory, Plateau et dans tout Abidjan';
  }

  void _syncBioExperienceYears(int years) {
    final cur = _bioCtrl.text;
    if (cur.isEmpty) return;
    final label = years <= 1 ? '1 an' : '$years ans';
    final updated = cur
        .replaceAll(RegExp(r"(\d+|X)\s+ans?\s+d'exp[ée]rience"), "$label d'expérience")
        .replaceAll("J'ai X ans", "Fort de $label");
    if (updated != cur) {
      _bioCtrl.value = TextEditingValue(
        text: updated,
        selection: TextSelection.collapsed(offset: updated.length),
      );
    }
  }

  void _generateFullSmartBio() {
    final yrs = _yearsExperience.round();
    final expPhrase = yrs <= 0
        ? 'Artisan qualifié et rigoureux'
        : (yrs == 1
            ? "Fort d'un an d'expérience terrain"
            : "Fort de $yrs ans d'expérience terrain");
    final metier = _resolvedMetierLabel();
    final zone = _resolvedZoneLabel();
    final fullBio =
        "$expPhrase, je suis spécialisé en $metier (diagnostic précis, installation, entretien et dépannage rapide). "
        "J'interviens rapidement à $zone avec mon outillage professionnel complet. "
        "Devis clair avant travaux, ponctualité et prestation garantie aux normes Babifix.";
    _bioCtrl.value = TextEditingValue(
      text: fullBio,
      selection: TextSelection.collapsed(offset: fullBio.length),
    );
    setState(() {});
  }

  void _appendSmartBioSnippet(String snippet) {
    var cur = _bioCtrl.text.trim();
    // Nettoie tout ancien texte placeholder éventuel ("J'ai X ans...", "Mes spécialités : .")
    cur = cur
        .replaceAll("J'ai X ans d'expérience.", '')
        .replaceAll("Mes spécialités : .", '')
        .replaceAll("J'interviens à Abidjan (préciser communes).", '')
        .trim();
    if (cur.contains(snippet.trim())) return;
    final sep = (cur.isEmpty || cur.endsWith('.')) ? (cur.isEmpty ? '' : ' ') : '. ';
    final newText = '$cur$sep${snippet.trim()}';
    _bioCtrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
    setState(() {});
  }

  Widget _smartBioChip({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    bool isAccent = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isAccent ? const Color(0xFF0284C7) : const Color(0xFF0E1A2D),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isAccent ? const Color(0xFF38BDF8) : const Color(0xFF1E3250),
              width: isAccent ? 1.4 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isAccent ? Colors.white : const Color(0xFF38BDF8),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isAccent ? FontWeight.w800 : FontWeight.w600,
                  color: isAccent ? Colors.white : const Color(0xFFE2E8F0),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Documents étape 2 ────────────────────────────────────────────────────
  String? _profilePhotoPath;
  String? _cniRectoPath;
  String? _cniVersoPath;

  // ── Soumission ────────────────────────────────────────────────────────────
  bool _submitting = false;
  // Consentement obligatoire (CGU + politique de confidentialité) avant l'envoi.
  bool _acceptedTerms = false;
  static const String _cguUrl = 'https://babifix.ci/cgu/';
  static const String _privacyUrl = 'https://babifix.ci/confidentialite/';
  final TapGestureRecognizer _cguTap = TapGestureRecognizer();
  final TapGestureRecognizer _privacyTap = TapGestureRecognizer();

  Future<void> _openLegal(String url) async {
    try {
      final ok = await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication);
      if (!ok) _snack('Impossible d\'ouvrir la page.');
    } catch (_) {
      _snack('Impossible d\'ouvrir la page.');
    }
  }

  final ImagePicker _picker = ImagePicker();

  // ── Animation ─────────────────────────────────────────────────────────────
  late final AnimationController _stepAnim;

  @override
  void initState() {
    super.initState();
    _expressMode = !widget.credentialLock && !widget.documentsLocked;
    _stepAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..forward();
    _cguTap.onTap = () => _openLegal(_cguUrl);
    _privacyTap.onTap = () => _openLegal(_privacyUrl);
    _hydrateInitialProvider();
    // Toujours vérifier/charger les catégories — même si preloadedCategories est non-vide,
    // les catégories pré-chargées sont parfois arrivées après initState de main.dart.
    if (widget.preloadedCategories != null &&
        widget.preloadedCategories!.isNotEmpty &&
        (_publicCategories.isEmpty)) {
      _publicCategories = widget.preloadedCategories!;
      _loadingCategories = false;
    }
    // Charger les catégories depuis l'API (fallback si preloadedCategories vide ou timing)
    _loadPublicCategories();
  }

  void _hydrateInitialProvider() {
    final p = widget.initialProvider;
    if (p == null) return;
    final nom = '${p['nom'] ?? ''}'.trim();
    final parts = nom.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isNotEmpty) {
      _prenomCtrl.text = parts.first;
      if (parts.length > 1) _nomCtrl.text = parts.sublist(1).join(' ');
    }
    _villeCtrl.text = '${p['ville'] ?? ''}'.trim();
    _bioCtrl.text = '${p['bio'] ?? ''}'.trim();
    _specialite = '${p['specialite'] ?? ''}'.trim();
    _categoryId = jsonInt(p['category_id']);
    final exp = jsonDouble(p['years_experience']);
    if (exp > 0) _yearsExperience = exp.clamp(0, 40);
    final photo = '${p['photo_url'] ?? ''}'.trim();
    if (photo.isNotEmpty) _profilePhotoPath = photo;
    if (widget.documentsLocked) {
      _cniRectoPath = 'locked';
      _cniVersoPath = 'locked';
    }
  }

  Future<void> _loadPublicCategories() async {
    if (mounted) setState(() => _loadingCategories = true);
    try {
      // ?all=1 → le prestataire voit TOUTES les catégories (même vides) pour
      // choisir son métier. Le client, lui, ne voit que les catégories remplies.
      final url = '${babifixApiBaseUrl()}/api/public/categories/?all=1';
      debugPrint(
        'BABIFIX PRESTATAIRE REGISTRATION: Loading categories from $url',
      );
      // Timeout : sur cold start serveur, sans borne, la liste reste vide.
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 25));
      debugPrint(
        'BABIFIX PRESTATAIRE REGISTRATION: Response status ${res.statusCode}',
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final rows = (data['categories'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        debugPrint(
          'BABIFIX PRESTATAIRE REGISTRATION: Loaded ${rows.length} categories',
        );
        if (!mounted) return;
        setState(() {
          _publicCategories = rows;
          _loadingCategories = false;
        });
        return;
      }
    } catch (e) {
      debugPrint(
        'BABIFIX PRESTATAIRE REGISTRATION: Error loading categories: $e',
      );
    }
    debugPrint(
      'BABIFIX PRESTATAIRE REGISTRATION: Using ${_publicCategories.length} categories (from preloaded)',
    );
    if (mounted) setState(() => _loadingCategories = false);
  }

  Future<void> _pickImage({
    required ImageSource source,
    required void Function(String path) onPicked,
  }) async {
    if (source == ImageSource.camera && kIsWeb) {
      debugPrint('Camera not supported on web');
      return;
    }
    try {
      final x = await _picker.pickImage(
        source: source,
        imageQuality: 88,
        maxWidth: 1600,
      );
      if (x == null || !mounted) return;
      setState(() {
        onPicked(x.path);
      });
    } catch (e) {
      debugPrint('Image picker error: $e');
    }
  }

  void _showImageSourceSheet(void Function(String path) onPicked) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _kNavy,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded, color: _kCyan),
                title: const Text(
                  'Choisir depuis la galerie',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(source: ImageSource.gallery, onPicked: onPicked);
                },
              ),
              if (defaultTargetPlatform == TargetPlatform.android ||
                  defaultTargetPlatform == TargetPlatform.iOS)
                ListTile(
                  leading: const Icon(Icons.camera_alt_rounded, color: _kCyan),
                  title: const Text(
                    'Prendre une photo',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickImage(source: ImageSource.camera, onPicked: onPicked);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _stepAnim.dispose();
    _prenomCtrl.dispose();
    _nomCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _pass2Ctrl.dispose();
    _villeCtrl.dispose();
    _bioCtrl.dispose();
    _metierProposeCtrl.dispose();
    _cguTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  // ── Navigation entre étapes ───────────────────────────────────────────────
  bool _validateStep1() {
    if (!(_formStep1.currentState?.validate() ?? false)) return false;
    if (_categoryId == null &&
        _metierPropose.trim().isEmpty &&
        (_specialite ?? '').trim().isEmpty) {
      _snack('Choisissez votre metier ou proposez un nouveau metier.');
      return false;
    }
    if (!_expressMode) {
      for (final q in _registrationQuestions) {
        if (q['required'] == true) {
          final k = '${q['key'] ?? ''}';
          final v = _specAnswers[k];
          final empty = v == null || (v is String && v.trim().isEmpty);
          if (empty) {
            _snack('Precisez : ${q['label'] ?? k}');
            return false;
          }
        }
      }
    }
    if (_villeCtrl.text.trim().length < 3) {
      _snack('Veuillez indiquer votre ville ou commune.');
      return false;
    }
    return true;
  }

  void _nextStep() {
    if (_step == 0) {
      if (!widget.credentialLock &&
          !(_formStep0.currentState?.validate() ?? false)) {
        return;
      }
    } else if (_step == 1) {
      if (!_validateStep1()) return;
      if (_expressMode) {
        _submit();
        return;
      }
    }
    setState(() {
      _step = (_step + 1).clamp(0, _totalSteps - 1);
      _stepAnim.forward(from: 0);
    });
  }

  void _prevStep() {
    if (_step == 0) {
      widget.onBack();
    } else {
      setState(() {
        _step--;
        _stepAnim.forward(from: 0);
      });
    }
  }

  Future<void> _submit() async {
    if (!_expressMode && !widget.documentsLocked) {
      if (_cniRectoPath == null || _cniRectoPath!.isEmpty) {
        _snack('Importez votre CNI recto pour continuer.');
        return;
      }
      if (_cniVersoPath == null || _cniVersoPath!.isEmpty) {
        _snack('Importez votre CNI verso pour continuer.');
        return;
      }
    }
    // Consentement obligatoire.
    if (!_acceptedTerms) {
      _snack('Veuillez accepter les Conditions d\'utilisation et la Politique de confidentialite pour continuer.');
      return;
    }
    setState(() => _submitting = true);
    final result = await _submitRegistration();
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result.ok) {
      await widget.onAuthReady();
      if (!mounted) return;
      if (_expressMode) {
        showBabifixToast(
          context,
          type: BabifixToastType.success,
          message:
              'Inscription enregistree ! Votre dossier est en attente de validation par notre equipe.',
        );
        widget.onSubmit();
        return;
      }
      final registeredEmail = _emailCtrl.text.trim();
      if (registeredEmail.isNotEmpty) {
        // Redirection vers la saisie du code OTP 6 chiffres envoye par email
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EmailVerificationScreen(
              email: registeredEmail,
              onContinue: () {
                Navigator.of(context).pop();
                widget.onSubmit();
              },
            ),
          ),
        );
      } else {
        widget.onSubmit();
      }
    } else {
      _snack(result.message);
    }
  }

  void _snack(String msg) {
    showBabifixToast(
        context,
        type: BabifixToastType.info,
        message: msg,
      );
  }

  // =========================================================================
  // BUILD
  // =========================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kNavyDeep,
      body: Stack(
        children: [
          // ── Fond gradient ──────────────────────────────────────────────
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF060E1C),
                    Color(0xFF0B1B34),
                    Color(0xFF0A1628),
                  ],
                ),
              ),
            ),
          ),
          // Orbes décoratifs
          Positioned(
            top: -60,
            right: -50,
            child: _Orbe(color: _kCyan, size: 220, alpha: 0.13),
          ),
          Positioned(
            bottom: -80,
            left: -60,
            child: _Orbe(color: _kBlue, size: 260, alpha: 0.09),
          ),

          // ── Contenu ────────────────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                // Header personnalise
                _buildHeader(),
                if (!widget.credentialLock && !widget.documentsLocked)
                  _buildModeToggle(),
                // Barre de progression
                _buildProgressBar(),
                // Indicateur etapes
                _buildStepIndicator(),
                // Contenu de l'étape courant
                Expanded(
                  child: AnimatedBuilder(
                    animation: _stepAnim,
                    builder: (_, child) => FadeTransition(
                      opacity: _stepAnim,
                      child: SlideTransition(
                        position:
                            Tween<Offset>(
                              begin: const Offset(0.04, 0),
                              end: Offset.zero,
                            ).animate(
                              CurvedAnimation(
                                parent: _stepAnim,
                                curve: Curves.easeOutCubic,
                              ),
                            ),
                        child: child,
                      ),
                    ),
                    child: _step == 0
                        ? _buildStep0()
                        : _step == 1
                        ? _buildStep1()
                        : _buildStep2(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── En-tête personnalisé ──────────────────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: _prevStep,
            icon: Icon(
              _step == 0
                  ? Icons.close_rounded
                  : Icons.arrow_back_ios_new_rounded,
              color: Colors.white70,
              size: 20,
            ),
          ),
          const SizedBox(width: 4),
          const Text(
            'BABIFIX',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: _kCyan,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            '· Inscription Prestataire',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white38,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  // ── Selecteur Express (60 s) vs Complet ───────────────────────────────────
  Widget _buildModeToggle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 2),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFF0E1A2D),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF1E3250)),
        ),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() {
                  _expressMode = true;
                  if (_step > 1) _step = 1;
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: _expressMode
                        ? const Color(0xFF0E3B2E)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Express (60 s · sans CNI)',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: _expressMode ? Colors.white : Colors.white60,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _expressMode = false),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: !_expressMode
                        ? const Color(0xFF0284C7)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Complet (avec CNI)',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: !_expressMode ? Colors.white : Colors.white60,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Barre de progression ──────────────────────────────────────────────────
  Widget _buildProgressBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: (_step + 1) / _totalSteps),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: SizedBox(
            height: 3,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(color: const Color(0xFF1E293B)),
                ),
                FractionallySizedBox(
                  widthFactor: v,
                  child: Container(
                    color: _expressMode
                        ? const Color(0xFF10B981)
                        : const Color(0xFF0284C7),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Indicateur etapes ─────────────────────────────────────────────────────
  Widget _buildStepIndicator() {
    final labels = _expressMode
        ? const ['Identite', 'Metier & Zone']
        : const ['Identite', 'Profil pro', 'Documents'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 10),
      child: Row(
        children: List.generate(_totalSteps * 2 - 1, (i) {
          if (i.isOdd) {
            final filled = i ~/ 2 < _step;
            return Expanded(
              child: Container(
                height: 2,
                color: filled
                    ? const Color(0xFFE87722)
                    : const Color(0xFF1E293B),
              ),
            );
          }
          final idx = i ~/ 2;
          final done = idx < _step;
          final active = idx == _step;
          return Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done
                      ? const Color(0xFF16A34A)
                      : active
                          ? const Color(0xFFE87722)
                          : const Color(0xFF0E1A2D),
                  border: Border.all(
                    color: done
                        ? const Color(0xFF22C55E)
                        : active
                            ? const Color(0xFFFB923C)
                            : const Color(0xFF1E3250),
                    width: active ? 2 : 1.2,
                  ),
                ),
                child: Center(
                  child: done
                      ? const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 16,
                        )
                      : Text(
                          '${idx + 1}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: active ? Colors.white : const Color(0xFF64748B),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                labels[idx],
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active
                      ? Colors.white
                      : done
                          ? const Color(0xFF4ADE80)
                          : const Color(0xFF64748B),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  // =========================================================================
  // ÉTAPE 0 : Identité & Compte
  // =========================================================================
  Widget _buildStep0() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      child: Form(
        key: _formStep0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DarkSectionHeader(
              icon: Icons.person_outline_rounded,
              title: 'Vos informations',
              subtitle: 'Ces données apparaîtront sur votre profil public.',
              iconColor: _kCyan,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _DarkFormField(
                    label: 'Prénom',
                    controller: _prenomCtrl,
                    icon: Icons.badge_outlined,
                    textInputAction: TextInputAction.next,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DarkFormField(
                    label: 'Nom',
                    controller: _nomCtrl,
                    icon: Icons.badge_outlined,
                    textInputAction: TextInputAction.next,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Champ téléphone avec style sombre
            Theme(
              data: ThemeData.dark().copyWith(
                colorScheme: ThemeData.dark().colorScheme.copyWith(
                  primary: const Color(0xFF0284C7),
                  outline: const Color(0xFF1E3250),
                  surface: const Color(0xFF0E1A2D),
                ),
                inputDecorationTheme: InputDecorationTheme(
                  filled: true,
                  fillColor: const Color(0xFF081220),
                  labelStyle: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 14,
                  ),
                  floatingLabelStyle: const TextStyle(
                    color: Color(0xFF38BDF8),
                    fontSize: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: Color(0xFF1E3250),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: Color(0xFF1E3250),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFF0284C7), width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: IntlPhoneField(
                  initialCountryCode: 'CI',
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  dropdownTextStyle: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Téléphone Mobile Money',
                  ),
                  onChanged: (phone) => _phoneE164 = phone.completeNumber,
                ),
              ),
            ),

            if (!widget.credentialLock) ...[
              _DarkSectionHeader(
                icon: Icons.lock_outline_rounded,
                title: 'Sécurité du compte',
                subtitle:
                    'Choisissez un mot de passe robuste (min. 8 caractères).',
                iconColor: _kBlueDeep,
              ),
              const SizedBox(height: 12),
              _DarkFormField(
                label: 'Adresse e-mail',
                controller: _emailCtrl,
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Requis';
                  if (!v.contains('@')) return 'E-mail invalide';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              _DarkFormFieldPassword(
                label: 'Mot de passe',
                controller: _passCtrl,
                visible: _passVisible,
                onToggle: () => setState(() => _passVisible = !_passVisible),
                validator: (v) => (v == null || v.length < 8)
                    ? 'Au moins 8 caractères'
                    : null,
              ),
              const SizedBox(height: 12),
              _DarkFormFieldPassword(
                label: 'Confirmer le mot de passe',
                controller: _pass2Ctrl,
                visible: _pass2Visible,
                onToggle: () => setState(() => _pass2Visible = !_pass2Visible),
                validator: (v) => v != _passCtrl.text
                    ? 'Les mots de passe ne correspondent pas'
                    : null,
              ),
            ] else ...[
              _DarkInfoBox(
                icon: Icons.info_outline_rounded,
                color: _kCyan,
                text:
                    'Votre e-mail et mot de passe sont conservés. '
                    'Modifiez uniquement les informations demandées lors du refus.',
              ),
            ],

            const SizedBox(height: 28),
            _DarkGradientButton(
              label: 'Suivant : Profil professionnel',
              icon: Icons.arrow_forward_rounded,
              onPressed: _nextStep,
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // ÉTAPE 1 : Profil Professionnel
  // =========================================================================
  Widget _buildStep1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      child: Form(
        key: _formStep1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DarkSectionHeader(
              icon: Icons.work_outline_rounded,
              title: 'Votre métier',
              subtitle: 'Renseignez votre domaine et zone d\'intervention.',
              iconColor: _kBlue,
            ),
            const SizedBox(height: 16),

            // Catégorie / Spécialité
            if (_loadingCategories)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: const LinearProgressIndicator(
                    minHeight: 2,
                    color: _kCyan,
                    backgroundColor: Colors.white12,
                  ),
                ),
              )
            else if (_publicCategories.isEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off_rounded,
                        color: Colors.white54, size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Spécialités non chargées (connexion lente).',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _loadPublicCategories,
                      icon: const Icon(Icons.refresh_rounded, size: 18, color: _kCyan),
                      label: const Text('Actualiser',
                          style: TextStyle(color: _kCyan, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              )
            else
              _buildDarkDropdown(),

            const SizedBox(height: 16),

            // Années d'expérience
            _DarkCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _kBlue.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.timeline_rounded,
                          color: _kBlue,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Années d\'expérience',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_yearsExperience.round()} an${_yearsExperience.round() > 1 ? 's' : ''}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: const Color(0xFF0284C7),
                      inactiveTrackColor: const Color(0xFF1E293B),
                      thumbColor: const Color(0xFF38BDF8),
                      overlayColor: const Color(0xFF0284C7).withValues(alpha: 0.15),
                    ),
                    child: Slider(
                      value: _yearsExperience,
                      min: 0,
                      max: 40,
                      divisions: 40,
                      label: '${_yearsExperience.round()} ans',
                      onChanged: (v) {
                        setState(() {
                          _yearsExperience = v;
                          _syncBioExperienceYears(v.round());
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Bio professionnelle encadrée proprement (sans label coupé)
            _DarkCard(
              child: Column(
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
                        child: const Icon(
                          Icons.description_outlined,
                          color: _kCyan,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Décrivez votre activité',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              'Visible par les clients sur votre profil',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _generateFullSmartBio,
                        style: TextButton.styleFrom(
                          backgroundColor: const Color(0xFF0284C7).withValues(alpha: 0.18),
                          foregroundColor: const Color(0xFF38BDF8),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: const BorderSide(color: Color(0xFF0284C7)),
                          ),
                        ),
                        icon: const Icon(Icons.auto_awesome_rounded, size: 14, color: Color(0xFF38BDF8)),
                        label: const Text(
                          'Rédiger auto',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF38BDF8),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _bioCtrl,
                    maxLines: 4,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      height: 1.4,
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Veuillez décrire votre activité (ou appuyez sur Rédiger auto)' : null,
                    decoration: InputDecoration(
                      hintText:
                          'Appuyez sur « Rédiger auto » ou sur les boutons intelligents ci-dessous pour générer votre présentation professionnelle...',
                      hintStyle: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 13,
                        height: 1.35,
                      ),
                      filled: true,
                      fillColor: const Color(0xFF081220),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF1E3250)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF1E3250)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF38BDF8), width: 1.5),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFEF4444)),
                      ),
                      contentPadding: const EdgeInsets.all(14),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    child: Row(
                      children: [
                        _smartBioChip(
                          label: 'Bio complète (${_yearsExperience.round()} ans)',
                          icon: Icons.auto_awesome_rounded,
                          isAccent: true,
                          onTap: _generateFullSmartBio,
                        ),
                        const SizedBox(width: 8),
                        _smartBioChip(
                          label: '+ Expérience (${_yearsExperience.round()} ans)',
                          icon: Icons.workspace_premium_rounded,
                          onTap: () {
                            final yrs = _yearsExperience.round();
                            final expTxt = yrs <= 1
                                ? "Fort d'un an d'expérience terrain en ${_resolvedMetierLabel()}, j'assure des interventions fiables et soignées."
                                : "Fort de $yrs ans d'expérience terrain en ${_resolvedMetierLabel()}, j'assure des interventions fiables et soignées.";
                            _appendSmartBioSnippet(expTxt);
                          },
                        ),
                        const SizedBox(width: 8),
                        _smartBioChip(
                          label: '+ Spécialités',
                          icon: Icons.build_circle_outlined,
                          onTap: () {
                            _appendSmartBioSnippet(
                              "Spécialisé en ${_resolvedMetierLabel()} : diagnostic précis, installation, maintenance et dépannage rapide.",
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        _smartBioChip(
                          label: '+ Zone (${_villeCtrl.text.trim().isNotEmpty ? _villeCtrl.text.trim().split(',').first : 'Abidjan'})',
                          icon: Icons.place_outlined,
                          onTap: () {
                            _appendSmartBioSnippet(
                              "J'interviens rapidement à ${_resolvedZoneLabel()} et dans les communes voisines.",
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        _smartBioChip(
                          label: '+ Garanties',
                          icon: Icons.verified_user_outlined,
                          onTap: () {
                            _appendSmartBioSnippet(
                              "Devis détaillé gratuit avant travaux, ponctualité et travail garanti aux normes Babifix.",
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        _smartBioChip(
                          label: '+ Équipement Pro',
                          icon: Icons.handyman_outlined,
                          onTap: () {
                            _appendSmartBioSnippet(
                              "Équipé de mon outillage professionnel complet et d'appareils de contrôle certifiés.",
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Ville
            _DarkCard(
              child: Column(
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
                        child: const Icon(
                          Icons.location_city_rounded,
                          color: _kCyan,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Ville & zone d\'intervention',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              'Entrez votre commune (Abidjan, Bouaké…)',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Theme(
                    data: ThemeData.dark().copyWith(
                      colorScheme: ThemeData.dark().colorScheme.copyWith(
                        primary: _kCyan,
                      ),
                      inputDecorationTheme: InputDecorationTheme(
                        filled: true,
                        fillColor: const Color(0xFF081220),
                        labelStyle: const TextStyle(
                          color: Color(0xFF94A3B8),
                        ),
                        floatingLabelStyle: const TextStyle(color: Color(0xFF38BDF8)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFF1E3250),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFF1E3250),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFF0284C7),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                    child: BabifixAddressSearchField(
                      controller: _villeCtrl,
                      onPlaceSelected: (LatLng ll, String label) =>
                          setState(() {
                            _villePin = ll;
                            _villeAddressLabel = label;
                          }),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _locating ? null : _openRegistrationMapPicker,
                          icon: const Icon(Icons.map_rounded,
                              size: 17, color: Color(0xFF10B981)),
                          label: const Text(
                            'Choisir sur carte',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Color(0xFF10B981),
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFF10B981), width: 1.2),
                            backgroundColor: const Color(0xFF081220),
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _locating ? null : _locateMe,
                          icon: _locating
                              ? const SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Color(0xFF38BDF8)),
                                )
                              : const Icon(Icons.my_location_rounded,
                                  size: 17, color: Color(0xFF38BDF8)),
                          label: Text(
                            _locating ? 'Localisation...' : 'Me localiser',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF38BDF8),
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFF0284C7), width: 1.2),
                            backgroundColor: const Color(0xFF081220),
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Ou choisissez votre commune en 1 clic :',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final c in kCivCommunesReference.take(10))
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ActionChip(
                              backgroundColor: _villeCtrl.text.contains(c.displayName.split('·').first.trim())
                                  ? const Color(0xFF0284C7)
                                  : const Color(0xFF081220),
                              side: BorderSide(
                                color: _villeCtrl.text.contains(c.displayName.split('·').first.trim())
                                    ? const Color(0xFF38BDF8)
                                    : const Color(0xFF1E3250),
                              ),
                              avatar: Icon(
                                Icons.location_on_rounded,
                                size: 14,
                                color: _villeCtrl.text.contains(c.displayName.split('·').first.trim())
                                    ? Colors.white
                                    : const Color(0xFF38BDF8),
                              ),
                              label: Text(
                                c.displayName.replaceAll(', Abidjan', ''),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: _villeCtrl.text.contains(c.displayName.split('·').first.trim())
                                      ? Colors.white
                                      : const Color(0xFFE2E8F0),
                                ),
                              ),
                              onPressed: () {
                                setState(() {
                                  _villeCtrl.text = c.displayName;
                                  _villeAddressLabel = c.displayName;
                                  _villePin = LatLng(c.latitude, c.longitude);
                                });
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  BabifixMiniMap(
                    lat: _villePin?.latitude ?? kCivAbidjanLat,
                    lon: _villePin?.longitude ?? kCivAbidjanLon,
                    height: 170,
                    pinColor: _kGreen,
                    pinIcon: Icons.home_work_rounded,
                    onTap: (p) => _applyRegistrationPin(p),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        _villePin != null
                            ? Icons.check_circle_rounded
                            : Icons.touch_app_rounded,
                        size: 14,
                        color: _villePin != null ? _kGreen : const Color(0xFF94A3B8),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _villePin != null
                              ? 'Position definie : ${_villeCtrl.text.trim()}'
                              : 'Touchez la carte pour placer votre repere',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: _villePin != null
                                ? _kGreen
                                : const Color(0xFF94A3B8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            if (_expressMode) ...[
              const SizedBox(height: 18),
              _DarkInfoBox(
                icon: Icons.bolt_rounded,
                color: const Color(0xFF10B981),
                text:
                    'Inscription rapide : accedez tout de suite a votre espace Pro. '
                    'Vous pourrez ajouter votre CNI plus tard avant votre premiere mission.',
              ),
              const SizedBox(height: 14),
              InkWell(
                onTap: () => setState(() => _acceptedTerms = !_acceptedTerms),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: _acceptedTerms,
                          onChanged: (v) =>
                              setState(() => _acceptedTerms = v ?? false),
                          activeColor: const Color(0xFF10B981),
                          checkColor: const Color(0xFF0B1B34),
                          side: const BorderSide(color: Colors.white38, width: 1.5),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text.rich(
                            TextSpan(
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white70,
                                height: 1.45,
                              ),
                              children: [
                                const TextSpan(text: 'J\'accepte les '),
                                TextSpan(
                                  text: 'Conditions d\'utilisation',
                                  recognizer: _cguTap,
                                  style: const TextStyle(
                                    color: _kCyan,
                                    fontWeight: FontWeight.w700,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                                const TextSpan(text: ' et la '),
                                TextSpan(
                                  text: 'Politique de confidentialite',
                                  recognizer: _privacyTap,
                                  style: const TextStyle(
                                    color: _kCyan,
                                    fontWeight: FontWeight.w700,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                                const TextSpan(text: ' de BABIFIX.'),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _DarkGradientButton(
                label: _submitting
                    ? 'Creation de votre espace Pro...'
                    : 'Creer mon compte Express (60 s)',
                icon: Icons.check_circle_outline_rounded,
                onPressed: _submitting ? () {} : _nextStep,
              ),
            ] else ...[
              const SizedBox(height: 28),
              _DarkGradientButton(
                label: 'Suivant : Documents d\'identite',
                icon: Icons.arrow_forward_rounded,
                onPressed: _nextStep,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDarkDropdown() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF081220),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E3250)),
      ),
      child: Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: ThemeData.dark().colorScheme.copyWith(
            primary: const Color(0xFF0284C7),
            surface: const Color(0xFF0E1A2D),
          ),
        ),
        child: DropdownButtonFormField<int>(
          key: ValueKey(_categoryId),
          initialValue: _categoryId,
          dropdownColor: const Color(0xFF0E1A2D),
          items: [
            for (final c in _publicCategories)
              DropdownMenuItem<int>(
                value: jsonInt(c['id']),
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: ('${c['icone_slug'] ?? ''}'.trim().isNotEmpty)
                          ? SvgPicture.asset(
                              'assets/category-icons/${'${c['icone_slug'] ?? ''}'.trim()}.svg',
                              fit: BoxFit.contain,
                              placeholderBuilder: (_) => const Icon(
                                Icons.category_outlined,
                                size: 20,
                                color: Colors.white54,
                              ),
                            )
                          : (('${c['icone_url'] ?? ''}'.isNotEmpty)
                              ? SvgPicture.network(
                                  babifixResolveMediaUrl('${c['icone_url']}'),
                                  fit: BoxFit.contain,
                                  placeholderBuilder: (_) => const Icon(
                                    Icons.category_outlined,
                                    size: 20,
                                    color: Colors.white54,
                                  ),
                                )
                              : const Icon(
                                  Icons.category_outlined,
                                  size: 20,
                                  color: Colors.white54,
                                )),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${c['nom'] ?? ''}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          onChanged: (value) {
            setState(() {
              _categoryId = value;
              for (final c in _publicCategories) {
                if (jsonInt(c['id']) == value) {
                  _specialite = '${c['nom'] ?? ''}'.trim();
                  break;
                }
              }
            });
          },
          validator: (v) => v == null ? 'Choisissez une catégorie' : null,
          isExpanded: true,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          iconEnabledColor: Colors.white38,
          decoration: InputDecoration(
            labelText: 'Spécialité (catégorie BABIFIX)',
            labelStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 14,
            ),
            floatingLabelStyle: const TextStyle(color: _kCyan, fontSize: 12),
            prefixIcon: const Icon(
              Icons.category_rounded,
              color: Colors.white38,
              size: 20,
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // ÉTAPE 2 : Documents
  // =========================================================================
  Widget _buildStep2() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DarkSectionHeader(
            icon: Icons.verified_user_outlined,
            title: 'Vérification d\'identité',
            subtitle:
                'Requis pour le badge Vérifié BABIFIX. Documents transmis à l\'admin de manière confidentielle.',
            iconColor: _kBlueDeep,
          ),
          const SizedBox(height: 20),

          _DarkDocPickerCard(
            title: 'Photo de profil',
            subtitle: 'Votre visage, fond neutre. Visible par les clients.',
            icon: Icons.face_rounded,
            accentColor: _kCyan,
            imagePath: _profilePhotoPath,
            locked: widget.documentsLocked,
            onPick: widget.documentsLocked
                ? null
                : () => _showImageSourceSheet(
                    (p) => setState(() => _profilePhotoPath = p),
                  ),
          ),
          const SizedBox(height: 14),

          _DarkDocPickerCard(
            title: 'CNI Recto',
            subtitle: 'Face avant de votre carte nationale d\'identité.',
            icon: Icons.credit_card_rounded,
            accentColor: _kBlue,
            imagePath: _cniRectoPath == 'locked' ? null : _cniRectoPath,
            locked: widget.documentsLocked,
            lockMessage: 'CNI vérifiée et verrouillée',
            onPick: widget.documentsLocked
                ? null
                : () => _showImageSourceSheet(
                    (p) => setState(() => _cniRectoPath = p),
                  ),
          ),
          const SizedBox(height: 14),

          _DarkDocPickerCard(
            title: 'CNI Verso',
            subtitle: 'Face arrière de votre carte nationale d\'identité.',
            icon: Icons.credit_card_outlined,
            accentColor: _kGreen,
            imagePath: _cniVersoPath == 'locked' ? null : _cniVersoPath,
            locked: widget.documentsLocked,
            lockMessage: 'CNI vérifiée et verrouillée',
            onPick: widget.documentsLocked
                ? null
                : () => _showImageSourceSheet(
                    (p) => setState(() => _cniVersoPath = p),
                  ),
          ),

          const SizedBox(height: 20),

          // Note légale
          _DarkInfoBox(
            icon: Icons.shield_outlined,
            color: Colors.white38,
            text:
                'Vos données sont protégées conformément à la loi ivoirienne n°2013-450 '
                '(ARTCI). Aucun document n\'est partagé avec un tiers sans votre consentement.',
          ),

          const SizedBox(height: 18),

          // Consentement obligatoire (case à cocher + liens cliquables).
          InkWell(
            onTap: () => setState(() => _acceptedTerms = !_acceptedTerms),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: _acceptedTerms,
                      onChanged: (v) =>
                          setState(() => _acceptedTerms = v ?? false),
                      activeColor: _kCyan,
                      checkColor: const Color(0xFF0B1B34),
                      side: const BorderSide(color: Colors.white38, width: 1.5),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text.rich(
                        TextSpan(
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                            height: 1.45,
                          ),
                          children: [
                            const TextSpan(text: 'J\'accepte les '),
                            TextSpan(
                              text: 'Conditions d\'utilisation',
                              recognizer: _cguTap,
                              style: const TextStyle(
                                color: _kCyan,
                                fontWeight: FontWeight.w700,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                            const TextSpan(text: ' et la '),
                            TextSpan(
                              text: 'Politique de confidentialité',
                              recognizer: _privacyTap,
                              style: const TextStyle(
                                color: _kCyan,
                                fontWeight: FontWeight.w700,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                            const TextSpan(text: ' de BABIFIX.'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 18),

          // Bouton soumettre
          GestureDetector(
            onTap: _submitting ? null : _submit,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 58,
              decoration: BoxDecoration(
                gradient: _submitting
                    ? const LinearGradient(
                        colors: [Color(0xFF475569), Color(0xFF334155)],
                      )
                    : const LinearGradient(colors: [_kCyan, Color(0xFF4CC9F0)]),
                borderRadius: BorderRadius.circular(18),
                boxShadow: _submitting
                    ? []
                    : [
                        BoxShadow(
                          color: _kCyan.withValues(alpha: 0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
              ),
              child: Center(
                child: _submitting
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: BabifixRingLoader.cyan(size: 28),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.send_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Soumettre ma demande',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              'Votre dossier sera examiné par l\'équipe BABIFIX (48 - 72 h)',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                color: Colors.white.withValues(alpha: 0.35),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // API — soumission
  // =========================================================================
  Future<_SubmitResult> _submitRegistration() async {
    final base = babifixApiBaseUrl();
    final email = _emailCtrl.text.trim();
    // Username = prefix de l'email (sans @domaine), pas l'email entier
    final username = email.isNotEmpty && email.contains('@')
        ? email.split('@').first
        : (email.isNotEmpty
              ? email
              : 'prest_${DateTime.now().millisecondsSinceEpoch}');
    final password = _passCtrl.text;
    final phone = _phoneE164.trim();
    final villeText = _villeCtrl.text.trim();
    final compactCity = _compactCity(villeText);
    final addrLabel = _villeAddressLabel.isNotEmpty
        ? _villeAddressLabel.trim()
        : villeText;

    var body = jsonEncode({
      'mode': _expressMode ? 'express' : 'full',
      'nom': '${_prenomCtrl.text.trim()} ${_nomCtrl.text.trim()}'.trim(),
      'specialite': _metierPropose.trim().isNotEmpty
          ? _metierPropose.trim()
          : (_specialite ?? ''),
      if (_categoryId != null && _metierPropose.trim().isEmpty)
        'category_id': _categoryId,
      if (_metierPropose.trim().isNotEmpty)
        'metier_propose': _metierPropose.trim(),
      if (_specAnswers.isNotEmpty) 'spec_answers': _specAnswers,
      'ville': compactCity,
      'service_city': compactCity,
      'service_address_label': addrLabel.length > 500
          ? addrLabel.substring(0, 500)
          : addrLabel,
      if (_villePin != null) 'service_latitude': _villePin!.latitude,
      if (_villePin != null) 'service_longitude': _villePin!.longitude,
      'years_experience': _yearsExperience.round(),
      'bio': _bioCtrl.text.trim(),
      'phone_e164': phone,
      'email': email,
    });

    // Encode et attache toutes les images en base64
    Future<String?> encodeImage(String? path) async {
      if (path == null || path.isEmpty || path == 'locked') return null;
      try {
        final bytes = await File(path).readAsBytes();
        final ext = path.split('.').last.toLowerCase();
        final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
        return 'data:$mime;base64,${base64Encode(bytes)}';
      } catch (_) {
        return null;
      }
    }

    final photoMap = jsonDecode(body) as Map<String, dynamic>;

    final portraitB64 = await encodeImage(_profilePhotoPath);
    if (portraitB64 != null) {
      photoMap['photo_portrait_b64'] = portraitB64;
      photoMap.remove('photo_portrait_url');
    }
    final cniRectoB64 = await encodeImage(_cniRectoPath);
    if (cniRectoB64 != null) photoMap['cni_recto_b64'] = cniRectoB64;

    final cniVersoB64 = await encodeImage(_cniVersoPath);
    if (cniVersoB64 != null) photoMap['cni_verso_b64'] = cniVersoB64;

    body = jsonEncode(photoMap);

    try {
      Future<String?> obtainJwt() async {
        debugPrint(
          'BABIFIX REG: Starting obtainJwt, credentialLock=${widget.credentialLock}',
        );
        if (widget.credentialLock) {
          final t = await readStoredApiToken();
          debugPrint(
            'BABIFIX REG: credentialLock=true, stored token: ${t != null ? "exists" : "null"}',
          );
          if (t != null && t.isNotEmpty) return t;
          return null;
        }
        debugPrint(
          'BABIFIX REG: Calling /api/auth/register with username=$username, email=$email',
        );
        var res = await http.post(
          Uri.parse('$base/api/auth/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'username': username,
            'email': email,
            'password': password,
            'role': 'prestataire',
            'phone_e164': phone,
            'country_code': 'CI',
          }),
        );
        debugPrint(
          'BABIFIX REG: /api/auth/register status=${res.statusCode}, body=${res.body.substring(0, res.body.length.clamp(0, 200))}',
        );
        if (res.statusCode == 201) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final t = (data['token'] ?? data['access']) as String?;
          final r = data['refresh'] as String?;
          if (r != null && r.isNotEmpty) await writeStoredRefreshToken(r);
          debugPrint(
            'BABIFIX REG: token from register: ${t != null ? "exists (${t.length} chars)" : "null"}',
          );
          if (t != null && t.isNotEmpty) return t;
        }
        if (res.statusCode == 400) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          debugPrint('BABIFIX REG: 400 response: $data');
          if (data['error'] == 'username_exists') {
            debugPrint('BABIFIX REG: username exists, attempting login');
            final loginRes = await http.post(
              Uri.parse('$base/api/auth/login'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'username': username, 'password': password}),
            );
            debugPrint('BABIFIX REG: login status=${loginRes.statusCode}');
            if (loginRes.statusCode == 200) {
              final d = jsonDecode(loginRes.body) as Map<String, dynamic>;
              final t = (d['token'] ?? d['access']) as String?;
              final r = d['refresh'] as String?;
              if (r != null && r.isNotEmpty) await writeStoredRefreshToken(r);
              debugPrint(
                'BABIFIX REG: login token: ${t != null ? "exists" : "null"}',
              );
              if (t != null && t.isNotEmpty) return t;
            }
          }
        }
        return null;
      }

      final jwt = await obtainJwt();
      debugPrint(
        'BABIFIX REG: JWT obtained: ${jwt != null ? "yes (${jwt.length} chars)" : "NULL"}',
      );
      if (jwt == null || jwt.isEmpty) {
        return const _SubmitResult(
          false,
          'Compte : impossible de créer ou connecter ce profil. Vérifiez l\'e-mail ou le mot de passe.',
        );
      }
      await writeStoredApiToken(jwt);

      debugPrint('BABIFIX REG: Calling /api/prestataire/register');
      final response = await http.post(
        Uri.parse('$base/api/prestataire/register'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwt',
        },
        body: body,
      );
      debugPrint(
        'BABIFIX REG: /api/prestataire/register status=${response.statusCode}, body=${response.body}',
      );
      final ok =
          response.statusCode >= 200 &&
          response.statusCode < 300 &&
          response.body.isNotEmpty;
      if (!ok) {
        if (response.body.isNotEmpty) {
          try {
            final err = jsonDecode(response.body) as Map<String, dynamic>;
            final code = '${err['error'] ?? ''}'.trim();
            if (code.isNotEmpty) {
              return _SubmitResult(false, _mapApiError(code));
            }
          } catch (_) {}
        }
        return _SubmitResult(
          false,
          'Dossier : erreur serveur (${response.statusCode}).',
        );
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        return const _SubmitResult(false, 'Réponse API inattendue.');
      }
      babifixRegisterFcm(jwt);
      return const _SubmitResult(true, '');
    } catch (e) {
      return _SubmitResult(false, 'Réseau : ${e.toString()}');
    }
  }

  String _compactCity(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return t;
    final parts = t.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return t;
    final country = parts.length > 1 ? parts.last : '';
    if (country == 'Côte d\'Ivoire' || country == "Cote d'Ivoire") {
      parts.removeLast();
    }
    final out = parts.take(2).join(', ');
    return out.length > 80 ? out.substring(0, 80) : out;
  }
}

String _mapApiError(String code) {
  switch (code) {
    case 'invalid_json':
      return 'Données invalides.';
    case 'nom_specialite_required':
      return 'Nom et spécialité requis.';
    case 'missing_token':
    case 'invalid_token':
      return 'Session expirée. Réessayez.';
    default:
      return 'Erreur : $code';
  }
}

class _SubmitResult {
  const _SubmitResult(this.ok, this.message);
  final bool ok;
  final String message;
}

// =============================================================================
// Widgets premium dark
// =============================================================================

class _Orbe extends StatelessWidget {
  const _Orbe({required this.color, required this.size, required this.alpha});
  final Color color;
  final double size;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: alpha),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}

class _DarkCard extends StatelessWidget {
  const _DarkCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1A2D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E3250)),
      ),
      child: child,
    );
  }
}

class _DarkSectionHeader extends StatelessWidget {
  const _DarkSectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.iconColor,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF0E1A2D),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF1E3250)),
          ),
          child: Icon(icon, color: const Color(0xFF38BDF8), size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF94A3B8),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DarkFormField extends StatelessWidget {
  const _DarkFormField({
    required this.label,
    required this.controller,
    this.icon,
    this.keyboardType,
    this.textInputAction,
    this.validator,
  });
  final String label;
  final TextEditingController controller;
  final IconData? icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      validator:
          validator ??
          (v) => (v == null || v.trim().isEmpty) ? 'Champ requis' : null,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: Color(0xFF94A3B8),
          fontSize: 14,
        ),
        floatingLabelStyle: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12),
        prefixIcon: icon != null
            ? Icon(icon, color: const Color(0xFF64748B), size: 20)
            : null,
        filled: true,
        fillColor: const Color(0xFF081220),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF1E3250)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF1E3250)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF0284C7), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFEF4444)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
        ),
        errorStyle: const TextStyle(color: Color(0xFFFC8181)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
    );
  }
}

class _DarkFormFieldPassword extends StatelessWidget {
  const _DarkFormFieldPassword({
    required this.label,
    required this.controller,
    required this.visible,
    required this.onToggle,
    this.validator,
  });
  final String label;
  final TextEditingController controller;
  final bool visible;
  final VoidCallback onToggle;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: !visible,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: Color(0xFF94A3B8),
          fontSize: 14,
        ),
        floatingLabelStyle: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12),
        prefixIcon: const Icon(
          Icons.lock_outline_rounded,
          color: Color(0xFF64748B),
          size: 20,
        ),
        suffixIcon: IconButton(
          onPressed: onToggle,
          icon: Icon(
            visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: const Color(0xFF64748B),
            size: 20,
          ),
        ),
        filled: true,
        fillColor: const Color(0xFF081220),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF1E3250)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF1E3250)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF0284C7), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFEF4444)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
        ),
        errorStyle: const TextStyle(color: Color(0xFFFC8181)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
    );
  }
}

class _DarkInfoBox extends StatelessWidget {
  const _DarkInfoBox({
    required this.icon,
    required this.color,
    required this.text,
  });
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1A2D),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E3250)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF38BDF8), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DarkGradientButton extends StatelessWidget {
  const _DarkGradientButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFE87722),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label),
            const SizedBox(width: 8),
            Icon(icon, size: 18),
          ],
        ),
      ),
    );
  }
}

class _DarkDocPickerCard extends StatelessWidget {
  const _DarkDocPickerCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    this.imagePath,
    this.locked = false,
    this.lockMessage,
    this.onPick,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final String? imagePath;
  final bool locked;
  final String? lockMessage;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    final hasImage = imagePath != null && imagePath!.isNotEmpty;

    ImageProvider? preview;
    if (hasImage) {
      final p = imagePath!;
      if (p.startsWith('http://') || p.startsWith('https://')) {
        preview = NetworkImage(p);
      } else {
        preview = FileImage(File(p));
      }
    }

    return GestureDetector(
      onTap: locked ? null : onPick,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0E1A2D),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: locked
                ? const Color(0xFF1B2E47)
                : hasImage
                ? const Color(0xFF0284C7)
                : const Color(0xFF1E3250),
            width: hasImage && !locked ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Preview ou icône
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: hasImage && preview != null
                  ? Image(
                      image: preview,
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        width: 72,
                        height: 72,
                        color: accentColor.withValues(alpha: 0.10),
                        child: Icon(icon, color: accentColor, size: 30),
                      ),
                    )
                  : Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: accentColor, size: 30),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.45),
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (locked)
                    Row(
                      children: [
                        Icon(
                          Icons.lock_rounded,
                          size: 12,
                          color: Colors.white38,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          lockMessage ?? 'Verrouillé',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white38,
                          ),
                        ),
                      ],
                    )
                  else if (hasImage)
                    Row(
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          size: 13,
                          color: accentColor,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Ajouté · Appuyez pour modifier',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: accentColor,
                          ),
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Icon(
                          Icons.upload_file_rounded,
                          size: 13,
                          color: accentColor,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Appuyez pour importer',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: accentColor,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            if (!locked)
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.25),
              ),
          ],
        ),
      ),
    );
  }
}

class _CategoryPickerSheet extends StatefulWidget {
  const _CategoryPickerSheet({
    required this.categories,
    required this.selectedCategoryId,
    required this.initialProposed,
    required this.normalize,
    required this.onErrorSnack,
    required this.onSelectCategory,
    required this.onProposeMetier,
  });

  final List<Map<String, dynamic>> categories;
  final int? selectedCategoryId;
  final String initialProposed;
  final String Function(String) normalize;
  final void Function(String) onErrorSnack;
  final void Function(int cid, String nom) onSelectCategory;
  final void Function(String proposed) onProposeMetier;

  @override
  State<_CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<_CategoryPickerSheet> {
  late final TextEditingController _searchCtrl = TextEditingController();
  late final TextEditingController _proposeCtrl = TextEditingController(
    text: widget.initialProposed,
  );

  @override
  void dispose() {
    _searchCtrl.dispose();
    _proposeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.normalize(_searchCtrl.text);
    final filtered = widget.categories.where((c) {
      if (q.isEmpty) return true;
      final kw = c['search_keywords'] is List
          ? (c['search_keywords'] as List).join(' ')
          : '${c['search_keywords'] ?? ''}';
      final hay = widget.normalize('${c['nom'] ?? ''} ${c['groupe'] ?? ''} $kw');
      return hay.contains(q);
    }).toList();

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final c in filtered) {
      final g = '${c['groupe'] ?? 'Autres metiers'}'.trim();
      grouped.putIfAbsent(g.isEmpty ? 'Autres metiers' : g, () => []).add(c);
    }

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final maxH = MediaQuery.of(context).size.height * 0.88;

    return SafeArea(
      top: false,
      child: SizedBox(
        height: maxH,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, bottomInset + 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Choisir votre metier BABIFIX',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      FocusManager.instance.primaryFocus?.unfocus();
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.close_rounded, color: Colors.white60),
                  ),
                ],
              ),
              TextField(
                controller: _searchCtrl,
                autofocus: false,
                style: const TextStyle(color: Colors.white),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Rechercher un metier (plombier, nounou, froid...)',
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 13.5),
                  prefixIcon: const Icon(Icons.search_rounded, color: _kCyan),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() {});
                          },
                          icon: const Icon(
                            Icons.clear_rounded,
                            color: Colors.white54,
                            size: 18,
                          ),
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFF081220),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFF1E3250)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFF1E3250)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _kCyan),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  children: [
                    for (final entry in grouped.entries) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 6),
                        child: Text(
                          entry.key.toUpperCase(),
                          style: const TextStyle(
                            color: Color(0xFF38BDF8),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                      for (final c in entry.value)
                        Builder(
                          builder: (_) {
                            final cid = jsonInt(c['id']);
                            final selected =
                                widget.initialProposed.trim().isEmpty &&
                                widget.selectedCategoryId == cid;
                            final iconSlug = '${c['icone_slug'] ?? ''}'.trim();
                            final iconUrl = babifixResolveMediaUrl(
                              '${c['icone_url'] ?? ''}',
                            );
                            final isSens =
                                '${c['regime_kyc'] ?? ''}' == 'SENSIBLE_CASIER';
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: selected
                                    ? _kCyan.withValues(alpha: 0.16)
                                    : const Color(0xFF0E1A2D),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: selected ? _kCyan : const Color(0xFF1E3250),
                                ),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: ListTile(
                                  dense: true,
                                  leading: SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: iconSlug.isNotEmpty
                                        ? SvgPicture.asset(
                                            'assets/category-icons/$iconSlug.svg',
                                            fit: BoxFit.contain,
                                            placeholderBuilder: (_) => const Icon(
                                              Icons.build_circle_outlined,
                                              color: _kCyan,
                                            ),
                                          )
                                        : (iconUrl.isNotEmpty
                                            ? SvgPicture.network(
                                                iconUrl,
                                                fit: BoxFit.contain,
                                                placeholderBuilder: (_) =>
                                                    const Icon(
                                                  Icons.build_circle_outlined,
                                                  color: _kCyan,
                                                ),
                                              )
                                            : const Icon(
                                                Icons.build_circle_outlined,
                                                color: _kCyan,
                                              )),
                                  ),
                                  title: Text(
                                    '${c['nom'] ?? ''}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                  subtitle: isSens
                                      ? const Text(
                                          'Metier sensible : casier + reference au KYC',
                                          style: TextStyle(
                                            color: Color(0xFF5EEAD4),
                                            fontSize: 11,
                                          ),
                                        )
                                      : null,
                                  trailing: selected
                                      ? const Icon(Icons.check_circle_rounded, color: _kCyan)
                                      : const Icon(
                                          Icons.chevron_right_rounded,
                                          color: Colors.white30,
                                        ),
                                  onTap: () {
                                    FocusManager.instance.primaryFocus?.unfocus();
                                    widget.onSelectCategory(
                                      cid,
                                      '${c['nom'] ?? ''}'.trim(),
                                    );
                                    Navigator.pop(context);
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF17223B),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0x55F59E0B)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.add_business_rounded,
                                color: Color(0xFFFBBF24),
                                size: 18,
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Votre metier n\'est pas encore dans la liste ?',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Proposez votre metier : votre dossier est pre-enregistre des maintenant et l\'equipe Babifix cree la categorie.',
                            style: TextStyle(
                              color: Color(0xFFCBD5E1),
                              fontSize: 11.5,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _proposeCtrl,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: _searchCtrl.text.trim().isNotEmpty
                                  ? 'Ex : ${_searchCtrl.text.trim()}'
                                  : 'Nom de votre metier exact (ex : Pisciniste)',
                              hintStyle: const TextStyle(
                                color: Colors.white38,
                                fontSize: 13,
                              ),
                              filled: true,
                              fillColor: const Color(0xFF081220),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFF334155)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                final proposed = _proposeCtrl.text.trim().isNotEmpty
                                    ? _proposeCtrl.text.trim()
                                    : _searchCtrl.text.trim();
                                if (proposed.length < 3) {
                                  widget.onErrorSnack(
                                    'Indiquez au moins 3 caracteres pour votre metier.',
                                  );
                                  return;
                                }
                                FocusManager.instance.primaryFocus?.unfocus();
                                widget.onProposeMetier(proposed);
                                Navigator.pop(context);
                              },
                              icon: const Icon(Icons.check_rounded, size: 18),
                              label: const Text('Proposer ce metier (Option A)'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFF59E0B),
                                foregroundColor: const Color(0xFF0F172A),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
