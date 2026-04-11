import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
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
    // Use preloaded categories if available, otherwise load from API
    if (widget.preloadedCategories != null &&
        widget.preloadedCategories!.isNotEmpty) {
      _publicCategories = widget.preloadedCategories!;
      _loadingCategories = false;
    } else {
      _loadPublicCategories();
    }
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
      final res = await http.get(
        Uri.parse('${babifixApiBaseUrl()}/api/public/categories/'),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final rows = (data['categories'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        if (!mounted) return;
        setState(() {
          _publicCategories = rows;
          _loadingCategories = false;
        });
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingCategories = false);
  }

  Future<void> _pickImage({
    required ImageSource source,
    required void Function(String path) onPicked,
  }) async {
    final x = await _picker.pickImage(
      source: source,
      imageQuality: 88,
      maxWidth: 1600,
    );
    if (x == null || !mounted) return;
    setState(() => onPicked(x.path));
  }

  void _showImageSourceSheet(void Function(String path) onPicked) {
    showModalBottomSheet<void>(
      context: context,
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
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded),
                title: const Text('Choisir depuis la galerie'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(source: ImageSource.gallery, onPicked: onPicked);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded),
                title: const Text('Prendre une photo'),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Veuillez indiquer votre ville via le champ de recherche.',
            ),
          ),
        );
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
    // Validation documents
    if (!widget.documentsLocked) {
      if (_cniRectoPath == null || _cniRectoPath!.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Importez votre CNI recto pour continuer.'),
          ),
        );
        return;
      }
      if (_cniVersoPath == null || _cniVersoPath!.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Importez votre CNI verso pour continuer.'),
          ),
        );
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
    }
  }

  // =========================================================================
  // BUILD
  // =========================================================================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isLight = theme.brightness == Brightness.light;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(
            _step == 0 ? Icons.close_rounded : Icons.arrow_back_rounded,
          ),
          onPressed: _prevStep,
        ),
        title: const Text(
          'Inscription prestataire',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(6),
          child: _buildStepProgressBar(isLight),
        ),
      ),
      body: AnimatedBuilder(
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
        child: Column(
          children: [
            // ── Indicateur étapes ────────────────────────────────────────
            _buildStepIndicator(cs, isLight),

            // ── Contenu étape ────────────────────────────────────────────
            Expanded(
              child: _step == 0
                  ? _buildStep0(cs, isLight)
                  : _step == 1
                  ? _buildStep1(cs, isLight)
                  : _buildStep2(cs, isLight),
            ),
          ],
        ),
      ),
    );
  }

  // ── Barre de progression colorée ─────────────────────────────────────────
  Widget _buildStepProgressBar(bool isLight) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: (_step + 1) / _kSteps),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => LinearProgressIndicator(
        value: v,
        backgroundColor: isLight
            ? const Color(0xFFE2E8F0)
            : const Color(0xFF374151),
        valueColor: AlwaysStoppedAnimation<Color>(BabifixDesign.cyan),
        minHeight: 4,
      ),
    );
  }

  // ── Indicateur étapes (puces numérotées) ─────────────────────────────────
  Widget _buildStepIndicator(ColorScheme cs, bool isLight) {
    const labels = ['Identité', 'Profil pro', 'Documents'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Row(
        children: List.generate(_kSteps * 2 - 1, (i) {
          if (i.isOdd) {
            return Expanded(
              child: Container(
                height: 1.5,
                color: i ~/ 2 < _step
                    ? BabifixDesign.cyan
                    : isLight
                    ? const Color(0xFFE2E8F0)
                    : const Color(0xFF374151),
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
                  color: done
                      ? BabifixDesign.ciGreen
                      : active
                      ? BabifixDesign.cyan
                      : isLight
                      ? const Color(0xFFE2E8F0)
                      : const Color(0xFF374151),
                ),
                child: Center(
                  child: done
                      ? const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 18,
                        )
                      : Text(
                          '${idx + 1}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: active
                                ? BabifixDesign.navy
                                : isLight
                                ? const Color(0xFF64748B)
                                : Colors.white54,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                labels[idx],
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                  color: active
                      ? BabifixDesign.cyan
                      : cs.onSurface.withValues(alpha: 0.5),
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
  Widget _buildStep0(ColorScheme cs, bool isLight) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Form(
        key: _formStep0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              icon: Icons.person_outline_rounded,
              title: 'Vos informations',
              subtitle: 'Ces données apparaîtront sur votre profil public.',
              iconColor: BabifixDesign.cyan,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _WizardField(
                    label: 'Prénom',
                    controller: _prenomCtrl,
                    icon: Icons.badge_outlined,
                    textInputAction: TextInputAction.next,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _WizardField(
                    label: 'Nom',
                    controller: _nomCtrl,
                    icon: Icons.badge_outlined,
                    textInputAction: TextInputAction.next,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: IntlPhoneField(
                initialCountryCode: 'CI',
                decoration: InputDecoration(
                  labelText: 'Téléphone Mobile Money',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  filled: true,
                  fillColor: isLight
                      ? const Color(0xFFF8FAFC)
                      : cs.surfaceContainerHighest.withValues(alpha: 0.4),
                ),
                onChanged: (phone) => _phoneE164 = phone.completeNumber,
              ),
            ),
            if (!widget.credentialLock) ...[
              _SectionHeader(
                icon: Icons.lock_outline_rounded,
                title: 'Sécurité du compte',
                subtitle:
                    'Choisissez un mot de passe robuste (min. 8 caractères).',
                iconColor: const Color(0xFF7C3AED),
              ),
              const SizedBox(height: 12),
              _WizardField(
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
              _WizardFieldPassword(
                label: 'Mot de passe',
                controller: _passCtrl,
                visible: _passVisible,
                onToggle: () => setState(() => _passVisible = !_passVisible),
                validator: (v) {
                  if (v == null || v.length < 8) {
                    return 'Au moins 8 caractères';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              _WizardFieldPassword(
                label: 'Confirmer le mot de passe',
                controller: _pass2Ctrl,
                visible: _pass2Visible,
                onToggle: () => setState(() => _pass2Visible = !_pass2Visible),
                validator: (v) => v != _passCtrl.text
                    ? 'Les mots de passe ne correspondent pas'
                    : null,
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: BabifixDesign.ciBlue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: BabifixDesign.ciBlue.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: BabifixDesign.ciBlue,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Votre e-mail et mot de passe sont conservés. '
                        'Modifiez uniquement les informations demandées lors du refus.',
                        style: TextStyle(
                          color: BabifixDesign.ciBlue,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 28),
            _WizardNextButton(
              label: 'Suivant — Profil professionnel',
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
  Widget _buildStep1(ColorScheme cs, bool isLight) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Form(
        key: _formStep1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              icon: Icons.work_outline_rounded,
              title: 'Votre métier',
              subtitle: 'Renseignez votre domaine et zone d\'intervention.',
              iconColor: BabifixDesign.ciOrange,
            ),
            const SizedBox(height: 16),

            // Catégorie / Spécialité
            if (_loadingCategories)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(minHeight: 2),
              )
            else
              DropdownButtonFormField<int>(
                value: _categoryId,
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
                                    ),
                                  )
                                : const Icon(Icons.category_outlined, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${c['nom'] ?? ''}',
                              overflow: TextOverflow.ellipsis,
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
                decoration: InputDecoration(
                  labelText: 'Spécialité (catégorie BABIFIX)',
                  prefixIcon: const Icon(Icons.category_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  filled: true,
                  fillColor: isLight
                      ? const Color(0xFFF8FAFC)
                      : cs.surfaceContainerHighest.withValues(alpha: 0.4),
                ),
              ),

            const SizedBox(height: 16),

            // Années d'expérience
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isLight
                    ? const Color(0xFFF8FAFC)
                    : cs.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.timeline_rounded,
                        color: BabifixDesign.ciOrange,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Années d\'expérience',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: BabifixDesign.ciOrange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_yearsExperience.round()} an${_yearsExperience.round() > 1 ? 's' : ''}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: BabifixDesign.ciOrange,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: _yearsExperience,
                    min: 0,
                    max: 40,
                    divisions: 40,
                    activeColor: BabifixDesign.ciOrange,
                    label: '${_yearsExperience.round()} ans',
                    onChanged: (v) => setState(() => _yearsExperience = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Description/Bio
            _WizardField(
              label: 'Décrivez votre activité',
              controller: _bioCtrl,
              icon: Icons.description_outlined,
              maxLines: 4,
              hint:
                  'Ex. : Plombier depuis 8 ans, spécialisé en rénovation et dépannage rapide...',
            ),
            const SizedBox(height: 16),

            // Ville d'intervention
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isLight
                    ? const Color(0xFFF8FAFC)
                    : cs.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.location_city_rounded,
                        color: BabifixDesign.cyan,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ville & zone d\'intervention',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface,
                              ),
                            ),
                            Text(
                              'Entrez votre commune (Abidjan, Bouaké…)',
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  BabifixAddressSearchField(
                    controller: _villeCtrl,
                    onPlaceSelected: (LatLng ll, String label) => setState(() {
                      _villePin = ll;
                      _villeAddressLabel = label;
                    }),
                  ),
                  if (_villePin != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          size: 16,
                          color: BabifixDesign.ciGreen,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Position enregistrée',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: BabifixDesign.ciGreen,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 28),
            _WizardNextButton(
              label: 'Suivant — Documents d\'identité',
              onPressed: _nextStep,
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // ÉTAPE 2 : Documents
  // =========================================================================
  Widget _buildStep2(ColorScheme cs, bool isLight) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.verified_user_outlined,
            title: 'Vérification d\'identité',
            subtitle:
                'Requis pour obtenir le badge Vérifié BABIFIX. Vos documents sont transmis à l\'admin de manière confidentielle.',
            iconColor: const Color(0xFF7C3AED),
          ),
          const SizedBox(height: 20),

          // ── Photo de profil ────────────────────────────────────────────
          _DocPickerCard(
            title: 'Photo de profil',
            subtitle: 'Votre visage, fond neutre. Visible par les clients.',
            icon: Icons.face_rounded,
            iconColor: BabifixDesign.ciBlue,
            imagePath: _profilePhotoPath,
            locked: widget.documentsLocked,
            onPick: widget.documentsLocked
                ? null
                : () => _showImageSourceSheet(
                    (p) => setState(() => _profilePhotoPath = p),
                  ),
          ),
          const SizedBox(height: 14),

          // ── CNI Recto ─────────────────────────────────────────────────
          _DocPickerCard(
            title: 'CNI Recto',
            subtitle: 'Face avant de votre carte nationale d\'identité.',
            icon: Icons.credit_card_rounded,
            iconColor: BabifixDesign.ciOrange,
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

          // ── CNI Verso ─────────────────────────────────────────────────
          _DocPickerCard(
            title: 'CNI Verso',
            subtitle: 'Face arrière de votre carte nationale d\'identité.',
            icon: Icons.credit_card_outlined,
            iconColor: BabifixDesign.ciGreen,
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

          // ── Note légale ────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isLight
                  ? const Color(0xFFF8FAFC)
                  : cs.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.shield_outlined,
                  color: cs.onSurfaceVariant,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Vos données sont protégées conformément à la loi ivoirienne n°2013-450 '
                    '(ARTCI). Aucun document n\'est partagé avec un tiers sans votre consentement.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: cs.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // ── Bouton soumettre ───────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _submitting ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: BabifixDesign.cyan,
                foregroundColor: BabifixDesign.navy,
                minimumSize: const Size(double.infinity, 58),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                elevation: 3,
                shadowColor: BabifixDesign.cyan.withValues(alpha: 0.35),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Color(0xFF0B1B34),
                      ),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.send_rounded, size: 20),
                        SizedBox(width: 10),
                        Text(
                          'Soumettre ma demande',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Votre dossier sera examiné par l\'équipe BABIFIX (48–72 h)',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                color: cs.onSurfaceVariant,
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
    final username = email.isNotEmpty
        ? email
        : 'prest_${DateTime.now().millisecondsSinceEpoch}';
    final password = _passCtrl.text;
    final phone = _phoneE164.trim();
    final villeText = _villeCtrl.text.trim();
    final compactCity = _compactCity(villeText);
    final addrLabel = _villeAddressLabel.isNotEmpty
        ? _villeAddressLabel.trim()
        : villeText;

    final body = jsonEncode({
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
      if (_profilePhotoPath != null && _profilePhotoPath!.trim().isNotEmpty)
        'photo_portrait_url': _profilePhotoPath!.trim(),
      'years_experience': _yearsExperience.round(),
      'bio': _bioCtrl.text.trim(),
      'phone_e164': phone,
      'email': email,
    });

    try {
      Future<String?> obtainJwt() async {
        if (widget.credentialLock) {
          final t = await readStoredApiToken();
          if (t != null && t.isNotEmpty) return t;
          return null;
        }
        var res = await http.post(
          Uri.parse('$base/api/auth/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'username': username,
            'password': password,
            'role': 'prestataire',
            'phone_e164': phone,
            'country_code': 'CI',
          }),
        );
        if (res.statusCode == 201) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final t = data['token'] as String?;
          if (t != null && t.isNotEmpty) return t;
        }
        if (res.statusCode == 400) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          if (data['error'] == 'username_exists') {
            final loginRes = await http.post(
              Uri.parse('$base/api/auth/login'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'username': username, 'password': password}),
            );
            if (loginRes.statusCode == 200) {
              final d = jsonDecode(loginRes.body) as Map<String, dynamic>;
              final t = d['token'] as String?;
              if (t != null && t.isNotEmpty) return t;
            }
            return null;
          }
        }
        return null;
      }

      final jwt = await obtainJwt();
      if (jwt == null || jwt.isEmpty) {
        return const _SubmitResult(
          false,
          'Compte : impossible de créer ou connecter ce profil. Vérifiez l\'e-mail ou le mot de passe.',
        );
      }
      await writeStoredApiToken(jwt);

      final response = await http.post(
        Uri.parse('$base/api/prestataire/register'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwt',
        },
        body: body,
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
// Widgets helpers du wizard
// =============================================================================

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
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
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
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
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12.5,
                  color: cs.onSurfaceVariant,
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

class _WizardField extends StatelessWidget {
  const _WizardField({
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
    final isLight = Theme.of(context).brightness == Brightness.light;
    final cs = Theme.of(context).colorScheme;
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      validator:
          validator ??
          (v) => (v == null || v.trim().isEmpty) ? 'Champ requis' : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: icon != null ? Icon(icon, size: 20) : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        filled: true,
        fillColor: isLight
            ? const Color(0xFFF8FAFC)
            : cs.surfaceContainerHighest.withValues(alpha: 0.4),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
    );
  }
}

class _WizardFieldPassword extends StatelessWidget {
  const _WizardFieldPassword({
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
    final isLight = Theme.of(context).brightness == Brightness.light;
    final cs = Theme.of(context).colorScheme;
    return TextFormField(
      controller: controller,
      obscureText: !visible,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
        suffixIcon: IconButton(
          onPressed: onToggle,
          icon: Icon(
            visible ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            size: 20,
          ),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        filled: true,
        fillColor: isLight
            ? const Color(0xFFF8FAFC)
            : cs.surfaceContainerHighest.withValues(alpha: 0.4),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
    );
  }
}

class _WizardNextButton extends StatelessWidget {
  const _WizardNextButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.arrow_forward_rounded, size: 20),
        label: Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: BabifixDesign.cyan,
          foregroundColor: BabifixDesign.navy,
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          elevation: 2,
          shadowColor: BabifixDesign.cyan.withValues(alpha: 0.3),
        ),
      ),
    );
  }
}

// ── Carte de document avec picker et preview ─────────────────────────────────
class _DocPickerCard extends StatelessWidget {
  const _DocPickerCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    this.imagePath,
    this.locked = false,
    this.lockMessage,
    this.onPick,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final String? imagePath;
  final bool locked;
  final String? lockMessage;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final hasImage = imagePath != null && imagePath!.isNotEmpty;

    // Preview image
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
          color: locked
              ? (isLight
                    ? const Color(0xFFF1F5F9)
                    : cs.surfaceContainerHighest.withValues(alpha: 0.3))
              : hasImage
              ? iconColor.withValues(alpha: 0.07)
              : (isLight
                    ? const Color(0xFFF8FAFC)
                    : cs.surfaceContainerHighest.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: locked
                ? cs.outlineVariant
                : hasImage
                ? iconColor.withValues(alpha: 0.45)
                : cs.outlineVariant,
            width: hasImage && !locked ? 2 : 1,
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
                    )
                  : Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: iconColor, size: 32),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (locked)
                    Row(
                      children: [
                        Icon(
                          Icons.lock_rounded,
                          size: 13,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          lockMessage ?? 'Verrouillé',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    )
                  else if (hasImage)
                    Row(
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          size: 14,
                          color: iconColor,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Document ajouté · Appuyez pour modifier',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: iconColor,
                          ),
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Icon(
                          Icons.upload_file_rounded,
                          size: 14,
                          color: iconColor,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Appuyez pour importer',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: iconColor,
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
                color: cs.onSurface.withValues(alpha: 0.3),
              ),
          ],
        ),
      ),
    );
  }
}
