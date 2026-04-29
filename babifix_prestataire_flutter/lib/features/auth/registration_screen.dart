import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, TargetPlatform, defaultTargetPlatform;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:latlong2/latlong.dart';

import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../json_utils.dart';
import '../../shared/auth_utils.dart';
import '../../shared/widgets/address_search_field.dart';

// =============================================================================
// Wizard d'inscription prestataire — 3 étapes
//   Étape 0 : Identité & Compte
//   Étape 1 : Profil Professionnel
//   Étape 2 : Documents (photo + CNI recto/verso)
// =============================================================================

// ── Design tokens ─────────────────────────────────────────────────────────────
const _kNavyDeep = Color(0xFF050D1A);
const _kNavy = Color(0xFF0A1628);
const _kCyan = Color(0xFF4CC9F0);
const _kBlue = Color(0xFF2563EB);
const _kBlueDark = Color(0xFF1D4ED8);
const _kGreen = Color(0xFF10B981);
const _kBlueDeep = Color(0xFF1E40AF);

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
  // ── Étapes ────────────────────────────────────────────────────────────────
  int _step = 0;
  static const int _kSteps = 3;

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
  String? _specialite;
  int? _categoryId;
  List<Map<String, dynamic>> _publicCategories = [];
  bool _loadingCategories = true;
  double _yearsExperience = 3;
  LatLng? _villePin;
  String _villeAddressLabel = '';

  // ── Documents étape 2 ────────────────────────────────────────────────────
  String? _profilePhotoPath;
  List<int>? _profilePhotoBytes; // pour envoi base64
  String? _cniRectoPath;
  String? _cniVersoPath;

  // ── Soumission ────────────────────────────────────────────────────────────
  bool _submitting = false;

  final ImagePicker _picker = ImagePicker();

  // ── Animation ─────────────────────────────────────────────────────────────
  late final AnimationController _stepAnim;

  @override
  void initState() {
    super.initState();
    _stepAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..forward();
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
    try {
      final url = '${babifixApiBaseUrl()}/api/public/categories/';
      debugPrint(
        'BABIFIX PRESTATAIRE REGISTRATION: Loading categories from $url',
      );
      final res = await http.get(Uri.parse(url));
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
      // Stocker le chemin et les bytes pour envoi base64
      final bytes = await x.readAsBytes();
      setState(() {
        onPicked(x.path);
        // Stocker les bytes pour envoi base64
        if (onPicked ==
            (p) {
              _profilePhotoPath = p;
            }) {
          _profilePhotoBytes = bytes;
        }
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
    super.dispose();
  }

  // ── Navigation entre étapes ───────────────────────────────────────────────
  void _nextStep() {
    if (_step == 0) {
      if (!widget.credentialLock &&
          !(_formStep0.currentState?.validate() ?? false))
        return;
    } else if (_step == 1) {
      if (!(_formStep1.currentState?.validate() ?? false)) return;
      if (_villeCtrl.text.trim().length < 3) {
        _snack('Veuillez indiquer votre ville via le champ de recherche.');
        return;
      }
    }
    setState(() {
      _step = (_step + 1).clamp(0, _kSteps - 1);
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
    if (!widget.documentsLocked) {
      if (_cniRectoPath == null || _cniRectoPath!.isEmpty) {
        _snack('Importez votre CNI recto pour continuer.');
        return;
      }
      if (_cniVersoPath == null || _cniVersoPath!.isEmpty) {
        _snack('Importez votre CNI verso pour continuer.');
        return;
      }
    }
    setState(() => _submitting = true);
    final result = await _submitRegistration();
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result.ok) {
      await widget.onAuthReady();
      if (!mounted) return;
      widget.onSubmit();
    } else {
      _snack(result.message);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1E3A5F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
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
                // Header personnalisé
                _buildHeader(),
                // Barre de progression
                _buildProgressBar(),
                // Indicateur étapes
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

  // ── Barre de progression ──────────────────────────────────────────────────
  Widget _buildProgressBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: (_step + 1) / _kSteps),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 4,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(color: Colors.white.withValues(alpha: 0.08)),
                ),
                FractionallySizedBox(
                  widthFactor: v,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [_kCyan, Color(0xFF0284C7)],
                      ),
                      borderRadius: BorderRadius.all(Radius.circular(4)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Indicateur étapes ─────────────────────────────────────────────────────
  Widget _buildStepIndicator() {
    const labels = ['Identité', 'Profil pro', 'Documents'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Row(
        children: List.generate(_kSteps * 2 - 1, (i) {
          if (i.isOdd) {
            final filled = i ~/ 2 < _step;
            return Expanded(
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: filled
                      ? const LinearGradient(
                          colors: [_kCyan, Color(0xFF0284C7)],
                        )
                      : null,
                  color: filled ? null : Colors.white.withValues(alpha: 0.1),
                ),
              ),
            );
          }
          final idx = i ~/ 2;
          final done = idx < _step;
          final active = idx == _step;
          return Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: active
                      ? const LinearGradient(
                          colors: [_kCyan, Color(0xFF0284C7)],
                        )
                      : null,
                  color: done
                      ? _kGreen
                      : active
                      ? null
                      : Colors.white.withValues(alpha: 0.08),
                  border: active
                      ? null
                      : Border.all(
                          color: done
                              ? _kGreen
                              : Colors.white.withValues(alpha: 0.15),
                          width: 1.5,
                        ),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: _kCyan.withValues(alpha: 0.45),
                            blurRadius: 12,
                          ),
                        ]
                      : done
                      ? [
                          BoxShadow(
                            color: _kGreen.withValues(alpha: 0.35),
                            blurRadius: 8,
                          ),
                        ]
                      : null,
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
                            color: active ? _kNavy : Colors.white38,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                labels[idx],
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                  color: active
                      ? _kCyan
                      : done
                      ? _kGreen
                      : Colors.white38,
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
                  primary: _kCyan,
                  outline: Colors.white.withValues(alpha: 0.12),
                  surface: const Color(0xFF0D1F3C),
                ),
                inputDecorationTheme: InputDecorationTheme(
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.07),
                  labelStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 14,
                  ),
                  floatingLabelStyle: const TextStyle(
                    color: _kCyan,
                    fontSize: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: _kCyan, width: 1.5),
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
              label: 'Suivant — Profil professionnel',
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
                          gradient: const LinearGradient(
                            colors: [_kBlue, _kBlueDark],
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_yearsExperience.round()} an${_yearsExperience.round() > 1 ? 's' : ''}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: _kBlue,
                      inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
                      thumbColor: _kBlue,
                      overlayColor: _kBlue.withValues(alpha: 0.2),
                    ),
                    child: Slider(
                      value: _yearsExperience,
                      min: 0,
                      max: 40,
                      divisions: 40,
                      label: '${_yearsExperience.round()} ans',
                      onChanged: (v) => setState(() => _yearsExperience = v),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Bio
            _DarkFormField(
              label: 'Décrivez votre activité',
              controller: _bioCtrl,
              icon: Icons.description_outlined,
              maxLines: 4,
              hint:
                  'Ex. : Plombier depuis 8 ans, spécialisé en rénovation et dépannage rapide...',
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
                        fillColor: Colors.white.withValues(alpha: 0.06),
                        labelStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                        floatingLabelStyle: const TextStyle(color: _kCyan),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.10),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.10),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: _kCyan,
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
                  if (_villePin != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          size: 14,
                          color: _kGreen,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Position enregistrée',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _kGreen,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 28),
            _DarkGradientButton(
              label: 'Suivant — Documents d\'identité',
              icon: Icons.arrow_forward_rounded,
              onPressed: _nextStep,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDarkDropdown() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: ThemeData.dark().colorScheme.copyWith(
            primary: _kCyan,
            surface: const Color(0xFF0D1F3C),
          ),
        ),
        child: DropdownButtonFormField<int>(
          value: _categoryId,
          dropdownColor: const Color(0xFF0D1F3C),
          items: [
            for (final c in _publicCategories)
              DropdownMenuItem<int>(
                value: jsonInt(c['id']),
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: ('${c['icone_url'] ?? ''}'.isNotEmpty)
                          ? SvgPicture.network(
                              '${c['icone_url']}',
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
                            ),
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

          const SizedBox(height: 28),

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
                    : const LinearGradient(colors: [_kCyan, Color(0xFF0284C7)]),
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
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
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
              'Votre dossier sera examiné par l\'équipe BABIFIX (48–72 h)',
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
      'nom': '${_prenomCtrl.text.trim()} ${_nomCtrl.text.trim()}'.trim(),
      'specialite': _specialite ?? '',
      if (_categoryId != null) 'category_id': _categoryId,
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
    Future<String?> _encodeImage(String? path) async {
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

    final portraitB64 = await _encodeImage(_profilePhotoPath);
    if (portraitB64 != null) {
      photoMap['photo_portrait_b64'] = portraitB64;
      photoMap.remove('photo_portrait_url');
    }
    final cniRectoB64 = await _encodeImage(_cniRectoPath);
    if (cniRectoB64 != null) photoMap['cni_recto_b64'] = cniRectoB64;

    final cniVersoB64 = await _encodeImage(_cniVersoPath);
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
          final t = data['token'] as String?;
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
              final t = d['token'] as String?;
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
            if (code.isNotEmpty)
              return _SubmitResult(false, _mapApiError(code));
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
    final first = t.split(',').first.trim();
    final out = first.isNotEmpty ? first : t;
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: child,
        ),
      ),
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
            color: iconColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: iconColor, size: 22),
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
                style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.white.withValues(alpha: 0.45),
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
    this.maxLines = 1,
    this.textInputAction,
    this.validator,
    this.hint,
  });
  final String label;
  final TextEditingController controller;
  final IconData? icon;
  final TextInputType? keyboardType;
  final int maxLines;
  final TextInputAction? textInputAction;
  final FormFieldValidator<String>? validator;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      validator:
          validator ??
          (v) => (v == null || v.trim().isEmpty) ? 'Champ requis' : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(
          color: Colors.white.withValues(alpha: 0.3),
          fontSize: 13,
        ),
        labelStyle: TextStyle(
          color: Colors.white.withValues(alpha: 0.5),
          fontSize: 14,
        ),
        floatingLabelStyle: const TextStyle(color: _kCyan, fontSize: 12),
        prefixIcon: icon != null
            ? Icon(icon, color: Colors.white.withValues(alpha: 0.4), size: 20)
            : null,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.07),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _kCyan, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFEF4444)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
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
        labelStyle: TextStyle(
          color: Colors.white.withValues(alpha: 0.5),
          fontSize: 14,
        ),
        floatingLabelStyle: const TextStyle(color: _kCyan, fontSize: 12),
        prefixIcon: Icon(
          Icons.lock_outline_rounded,
          color: Colors.white.withValues(alpha: 0.4),
          size: 20,
        ),
        suffixIcon: IconButton(
          onPressed: onToggle,
          icon: Icon(
            visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: Colors.white.withValues(alpha: 0.4),
            size: 20,
          ),
        ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.07),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _kCyan, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFEF4444)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
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
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
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
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_kCyan, Color(0xFF0284C7)]),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: _kCyan.withValues(alpha: 0.4),
              blurRadius: 18,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(width: 8),
            Icon(icon, color: Colors.white, size: 18),
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
          color: hasImage && !locked
              ? accentColor.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: locked
                ? Colors.white.withValues(alpha: 0.08)
                : hasImage
                ? accentColor.withValues(alpha: 0.40)
                : Colors.white.withValues(alpha: 0.10),
            width: hasImage && !locked ? 1.5 : 1,
          ),
          boxShadow: hasImage && !locked
              ? [
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.15),
                    blurRadius: 12,
                  ),
                ]
              : null,
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
                      errorBuilder: (_, __, ___) => Container(
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
