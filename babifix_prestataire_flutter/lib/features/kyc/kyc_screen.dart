import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../babifix_api_config.dart';
import '../../shared/auth_utils.dart';
import '../../shared/app_palette_mode.dart';
import '../../shared/widgets/babifix_ring_loader.dart';
import '../../shared/widgets/babifix_snackbar.dart';

// Constantes
const _kMaxImgBytes = 3 * 1024 * 1024; // 3 MB
const _kSteps = [
  'Profil',
  'Identite',
  'Photos',
  'Accord',
  'Envoi',
];

const _kCommunesAbidjan = [
  'Cocody',
  'Yopougon',
  'Abobo',
  'Marcory',
  'Koumassi',
  'Port-Bouët',
  'Treichville',
  'Adjamé',
  'Plateau',
  'Attécoubé',
  'Bingerville',
  'Songon',
  'Autre commune'
];

class KYCScreen extends StatefulWidget {
  const KYCScreen({
    super.key,
    required this.onBack,
    required this.paletteMode,
  });

  final VoidCallback onBack;
  final AppPaletteMode paletteMode;

  @override
  State<KYCScreen> createState() => _KYCScreenState();
}

class _KYCScreenState extends State<KYCScreen> {
  int _step = 0; // 0=Palier & Commune, 1=Infos CNI, 2=Photos CNI, 3=Supervision/Docs, 4=Récap, 5=Done

  // Étape 0 : Paliers & Communes
  String _selectedTier = 'palier_1_proximite'; // palier_1_proximite, palier_2_maitre, palier_3_entreprise
  String _commune = 'Cocody';

  // Etape 1 : Piece d'identite
  final _cniCtrl = TextEditingController();
  final _mrzCtrl = TextEditingController();
  final _expiryCtrl = TextEditingController();
  DateTime? _expiryDate;
  String? _cniError;
  String? _expiryError;

  // Donnees serveur Smart KYC & progression merite
  int? _autoCheckScore;
  List<String> _autoCheckHints = const [];
  Map<String, dynamic>? _meritProgress;

  // Étape 2 : Photos CNI & Selfie
  Uint8List? _rectoBytes;
  Uint8List? _versoBytes;
  Uint8List? _selfieBytes;

  // Étape 3 : Documents spécifiques (selon palier + régime métier sensible)
  // Palier 1 : WhatsApp entretien
  bool _whatsappRequested = false;
  bool _requestingSupervisor = false;
  // Régime SENSIBLE_CASIER (nounous, aide domicile, chauffeurs)
  String _regimeKyc = 'STANDARD_TERRAIN';
  String _categoryNom = '';
  bool get _isSensible => _regimeKyc == 'SENSIBLE_CASIER';
  Uint8List? _casierBytes;
  Uint8List? _certificatMedBytes;
  final _refNomCtrl = TextEditingController();
  final _refTelCtrl = TextEditingController();
  // Palier 2 : CNMCI
  final _cnmciCtrl = TextEditingController();
  Uint8List? _cnmciCardBytes;
  // Palier 3 : RCCM & Fiscalité
  final _rccmCtrl = TextEditingController();
  final _ccCtrl = TextEditingController();
  Uint8List? _rccmDocBytes;

  bool _loading = false;
  String? _statusKyc;
  String? _rejectReason;
  bool _loadingStatus = true;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _cniCtrl.dispose();
    _mrzCtrl.dispose();
    _expiryCtrl.dispose();
    _cnmciCtrl.dispose();
    _rccmCtrl.dispose();
    _ccCtrl.dispose();
    _refNomCtrl.dispose();
    _refTelCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    setState(() => _loadingStatus = true);
    try {
      final t = await readStoredApiToken();
      if (t == null) return;
      final res = await http.get(
        Uri.parse('${babifixApiBaseUrl()}/api/prestataire/kyc/status/'),
        headers: {'Authorization': 'Bearer $t'},
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _statusKyc = d['status'] as String?;
          _rejectReason = d['rejection_reason'] as String?;
          _regimeKyc = '${d['regime_kyc'] ?? 'STANDARD_TERRAIN'}';
          _categoryNom = '${d['category_nom'] ?? ''}';
          if (_isSensible) {
            _whatsappRequested = true;
          }
          final rNom = '${d['reference_contact_nom'] ?? ''}'.trim();
          final rTel = '${d['reference_contact_tel'] ?? ''}'.trim();
          if (rNom.isNotEmpty) _refNomCtrl.text = rNom;
          if (rTel.isNotEmpty) _refTelCtrl.text = rTel;
          if (d['artisan_tier'] != null && d['artisan_tier'].toString().isNotEmpty) {
            _selectedTier = d['artisan_tier'].toString();
          }
          if (d['commune_rattachement'] != null && d['commune_rattachement'].toString().isNotEmpty) {
            _commune = d['commune_rattachement'].toString();
          }
          if (d['kyc_cni_mrz'] != null && d['kyc_cni_mrz'].toString().trim().isNotEmpty) {
            _mrzCtrl.text = d['kyc_cni_mrz'].toString().trim();
          }
          final rawScore = d['auto_check_score'];
          if (rawScore is num) _autoCheckScore = rawScore.toInt();
          final rawAuto = d['auto_check_result'];
          if (rawAuto is Map && rawAuto['hints'] is List) {
            _autoCheckHints = (rawAuto['hints'] as List)
                .map((e) => '$e'.trim())
                .where((e) => e.isNotEmpty)
                .toList();
          }
          if (d['merit_progress'] is Map) {
            _meritProgress = Map<String, dynamic>.from(d['merit_progress'] as Map);
          }
        });
      }
    } catch (_) {}
    setState(() => _loadingStatus = false);
  }

  Future<void> _pickImage(ImageSource source, void Function(Uint8List) onPick) async {
    final picker = ImagePicker();
    final xf = await picker.pickImage(
      source: source,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 85,
    );
    if (xf == null) return;
    final bytes = await xf.readAsBytes();
    if (bytes.length > _kMaxImgBytes) {
      if (mounted) {
        showBabifixToast(
          context,
          type: BabifixToastType.error,
          message: 'Image trop lourde (max 3 MB). Réduisez la résolution.',
        );
      }
      return;
    }
    onPick(bytes);
  }

  Future<void> _launchSupervisorWhatsApp() async {
    setState(() => _requestingSupervisor = true);
    try {
      final t = await readStoredApiToken();
      String phoneSuperviseur = '2250700000000';
      String message = 'Bonjour Superviseur Babifix ($_commune), je souhaite passer mon micro-entretien visio de 5 minutes pour valider mes outils et mon profil.';

      if (t != null) {
        final res = await http.post(
          Uri.parse('${babifixApiBaseUrl()}/api/prestataire/supervisor/request-call/'),
          headers: {
            'Authorization': 'Bearer $t',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'commune': _commune}),
        );
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data['whatsapp_url'] != null) {
            final uri = Uri.parse(data['whatsapp_url']);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
              setState(() => _whatsappRequested = true);
              return;
            }
          }
        }
      }

      // Repli direct WhatsApp
      final fallbackUri = Uri.parse('https://wa.me/$phoneSuperviseur?text=${Uri.encodeComponent(message)}');
      if (await canLaunchUrl(fallbackUri)) {
        await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
        setState(() => _whatsappRequested = true);
      } else {
        if (mounted) {
          showBabifixToast(
            context,
            type: BabifixToastType.info,
            message: 'WhatsApp non détecté. Contactez le superviseur au +$phoneSuperviseur',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showBabifixToast(
          context,
          type: BabifixToastType.error,
          message: 'Erreur lors de l\'appel superviseur : $e',
        );
      }
    } finally {
      if (mounted) setState(() => _requestingSupervisor = false);
    }
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      final t = await readStoredApiToken();
      if (t == null) throw Exception('Non authentifié');

      String toB64(Uint8List b) => 'data:image/jpeg;base64,${base64Encode(b)}';

      final payload = <String, dynamic>{
        'artisan_tier': _selectedTier,
        'commune_rattachement': _commune,
        'whatsapp_interview_requested': _isSensible ? true : _whatsappRequested,
        'cni_number': _cniCtrl.text.trim(),
        if (_mrzCtrl.text.trim().isNotEmpty) 'cni_mrz': _mrzCtrl.text.trim(),
        'cni_expiry': _expiryDate != null
            ? '${_expiryDate!.year}-${_expiryDate!.month.toString().padLeft(2, '0')}-${_expiryDate!.day.toString().padLeft(2, '0')}'
            : '',
        'cni_recto_b64': toB64(_rectoBytes!),
        'cni_verso_b64': toB64(_versoBytes!),
        'selfie_b64': toB64(_selfieBytes!),
      };

      if (_casierBytes != null) {
        payload['casier_judiciaire_b64'] = toB64(_casierBytes!);
      }
      if (_certificatMedBytes != null) {
        payload['certificat_medical_b64'] = toB64(_certificatMedBytes!);
      }
      if (_refNomCtrl.text.trim().isNotEmpty) {
        payload['reference_contact_nom'] = _refNomCtrl.text.trim();
      }
      if (_refTelCtrl.text.trim().isNotEmpty) {
        payload['reference_contact_tel'] = _refTelCtrl.text.trim();
      }

      if (_selectedTier == 'palier_2_maitre') {
        payload['cnmci_number'] = _cnmciCtrl.text.trim();
        if (_cnmciCardBytes != null) {
          payload['cnmci_card_b64'] = toB64(_cnmciCardBytes!);
        }
      } else if (_selectedTier == 'palier_3_entreprise') {
        payload['rccm_number'] = _rccmCtrl.text.trim();
        payload['compte_contribuable'] = _ccCtrl.text.trim();
        if (_rccmDocBytes != null) {
          payload['rccm_document_b64'] = toB64(_rccmDocBytes!);
        }
      }

      final res = await http.post(
        Uri.parse('${babifixApiBaseUrl()}/api/prestataire/kyc/submit/'),
        headers: {
          'Authorization': 'Bearer $t',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 30));

      if (res.statusCode == 200 || res.statusCode == 201) {
        int? score;
        List<String> hints = const [];
        try {
          final body = jsonDecode(res.body);
          if (body is Map<String, dynamic>) {
            final sc = body['auto_check_score'];
            if (sc is num) score = sc.toInt();
            final auto = body['auto_check_result'];
            if (auto is Map && auto['hints'] is List) {
              hints = (auto['hints'] as List)
                  .map((e) => '$e'.trim())
                  .where((e) => e.isNotEmpty)
                  .toList();
            }
          }
        } catch (_) {}
        setState(() {
          if (score != null) _autoCheckScore = score;
          _autoCheckHints = hints;
          _statusKyc = 'pending';
          _step = 5;
        });
      } else {
        final err = jsonDecode(res.body) as Map<String, dynamic>;
        final fields = err['fields'] as Map? ?? {};
        final rawHints = err['hints'] is List
            ? (err['hints'] as List)
                .map((e) => '$e'.trim())
                .where((e) => e.isNotEmpty)
                .toList()
            : const <String>[];
        final sc = err['auto_check_score'];
        if (sc is num && mounted) {
          setState(() {
            _autoCheckScore = sc.toInt();
            _autoCheckHints = rawHints;
          });
        }
        final msg = fields.values.isNotEmpty
            ? fields.values.first.toString()
            : (err['detail'] ?? err['message'] ?? 'Erreur serveur (${res.statusCode})').toString();
        if (mounted) {
          if (err['error'] == 'kyc_auto_rejected' && rawHints.isNotEmpty) {
            await showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Verification automatique : corrections requises'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(msg, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      for (final h in rawHints)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('· $h', style: const TextStyle(fontSize: 13)),
                        ),
                    ],
                  ),
                ),
                actions: [
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0E3B2E)),
                    onPressed: () {
                      Navigator.pop(ctx);
                      setState(() => _step = 2);
                    },
                    child: const Text('Corriger mes photos'),
                  ),
                ],
              ),
            );
          } else {
            showBabifixToast(context, type: BabifixToastType.error, message: msg);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        showBabifixToast(context, type: BabifixToastType.error, message: 'Erreur réseau : $e');
      }
    }
    setState(() => _loading = false);
  }

  bool get _isLight => widget.paletteMode != AppPaletteMode.blue;

  Color get _bg => _isLight ? const Color(0xFFF6F8FC) : const Color(0xFF0B1B34);
  Color get _card => _isLight ? Colors.white : const Color(0xFF14243C);
  Color get _text => _isLight ? const Color(0xFF0F172A) : Colors.white;
  Color get _muted => _isLight ? const Color(0xFF64748B) : const Color(0xFFB4C2D9);
  Color get _border => _isLight ? const Color(0xFFE2E8F0) : Colors.white.withValues(alpha: 0.10);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1B34),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () {
            if (_step > 0 && _step < 5) {
              setState(() => _step--);
            } else {
              widget.onBack();
            }
          },
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Verifier mon compte',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
            Text('Gratuit · 2 minutes',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF93C5FD))),
          ],
        ),
      ),
      body: _loadingStatus
          ? const Center(child: BabifixRingLoader.cyan(size: 80))
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_statusKyc == 'approved') return _buildApproved();
    if (_statusKyc == 'rejected') return _buildRejected();
    if (_statusKyc == 'pending' || _statusKyc == 'under_review') return _buildPending();
    if (_step == 5) return _buildDone();

    return Column(
      children: [
        _buildStepper(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: _buildStepContent(),
          ),
        ),
      ],
    );
  }

  Widget _buildStepper() {
    final activeStep = _step.clamp(0, _kSteps.length - 1);
    return Container(
      color: const Color(0xFF0B1B34),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(_kSteps.length, (i) {
          final done = i < activeStep;
          final active = i == activeStep;
          final leftLineColor = i <= activeStep
              ? const Color(0xFF22C55E)
              : Colors.white.withValues(alpha: 0.16);
          final rightLineColor = done
              ? const Color(0xFF22C55E)
              : Colors.white.withValues(alpha: 0.16);
          return Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 2,
                        color: i == 0 ? Colors.transparent : leftLineColor,
                      ),
                    ),
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: done
                            ? const Color(0xFF22C55E)
                            : active
                                ? const Color(0xFFFF6B00)
                                : Colors.white.withValues(alpha: 0.15),
                      ),
                      child: Center(
                        child: done
                            ? const Icon(Icons.check, size: 14, color: Colors.white)
                            : Text(
                                '${i + 1}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: active ? Colors.white : Colors.white54,
                                ),
                              ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        height: 2,
                        color: i == _kSteps.length - 1
                            ? Colors.transparent
                            : rightLineColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _kSteps[i],
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 9.5,
                        color: active ? Colors.white : Colors.white54,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case 0:
        return _buildStep0TierAndCommune();
      case 1:
        return _buildStep1CniInfo();
      case 2:
        return _buildStep2PhotosCni();
      case 3:
        return _buildStep3SupervisionAndDocs();
      case 4:
        return _buildStep4Recap();
      default:
        return const SizedBox.shrink();
    }
  }

  // Étape 0 : Choix du Palier & Commune de rattachement
  Widget _buildStep0TierAndCommune() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildNoticeAdaptive(),
        if (_meritProgress != null) ...[
          const SizedBox(height: 14),
          _buildMeritProgressCard(),
        ],
        const SizedBox(height: 20),
        _sectionTitle('1. Votre commune d\'intervention principale'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _commune,
              isExpanded: true,
              dropdownColor: _card,
              style: TextStyle(color: _text, fontWeight: FontWeight.w600, fontSize: 14),
              items: _kCommunesAbidjan.map((c) {
                return DropdownMenuItem(value: c, child: Text(c));
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _commune = val);
              },
            ),
          ),
        ),
        const SizedBox(height: 24),
        _sectionTitle('2. Choisissez votre niveau d\'artisan'),
        const SizedBox(height: 12),

        // Palier 1
        _buildTierOptionCard(
          id: 'palier_1_proximite',
          badgeText: 'NIVEAU 1 · INDEPENDANT',
          badgeColor: const Color(0xFFFF6B00),
          title: 'Artisan independant',
          subtitle: 'Sans papier d\'entreprise',
          description: 'Pour les artisans avec experience. Juste votre CNI et un appel rapide WhatsApp de 5 min.',
          plafond: 'Missions jusqu\'a 100 000 FCFA',
          icon: Icons.handyman_rounded,
        ),
        const SizedBox(height: 14),

        // Palier 2
        _buildTierOptionCard(
          id: 'palier_2_maitre',
          badgeText: 'NIVEAU 2 · CONFIRME',
          badgeColor: const Color(0xFF4CC9F0),
          title: 'Artisan certifie',
          subtitle: 'Carte metier ou diplome',
          description: 'Pour les artisans ayant une carte professionnelle ou un diplome de metier.',
          plafond: 'Missions jusqu\'a 500 000 FCFA',
          icon: Icons.military_tech_rounded,
        ),
        const SizedBox(height: 14),

        // Palier 3
        _buildTierOptionCard(
          id: 'palier_3_entreprise',
          badgeText: 'NIVEAU 3 · ENTREPRISE',
          badgeColor: const Color(0xFF22C55E),
          title: 'Entreprise declaree',
          subtitle: 'Avec papiers officiels (RCCM)',
          description: 'Pour les entreprises pouvant faire des factures et prendre de gros chantiers.',
          plafond: 'Gros chantiers sans limite',
          icon: Icons.business_rounded,
        ),
        const SizedBox(height: 28),

        _nextButton(
          label: 'Continuer : Pièce d\'identité',
          icon: Icons.arrow_forward_rounded,
          enabled: true,
          onTap: () => setState(() => _step = 1),
        ),
      ],
    );
  }

  Widget _buildTierOptionCard({
    required String id,
    required String badgeText,
    required Color badgeColor,
    required String title,
    required String subtitle,
    required String description,
    required String plafond,
    required IconData icon,
  }) {
    final isSelected = _selectedTier == id;
    return GestureDetector(
      onTap: () => setState(() => _selectedTier = id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? badgeColor.withValues(alpha: 0.08) : _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? badgeColor : _border,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: badgeColor.withValues(alpha: 0.20),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  )
                ]
              : [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: badgeColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          badgeText,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: badgeColor,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _text,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? badgeColor : _muted.withValues(alpha: 0.4),
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? Center(
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: badgeColor,
                            ),
                          ),
                        )
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: badgeColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: TextStyle(
                fontSize: 12,
                color: _muted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _bg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified_outlined, size: 14, color: badgeColor),
                  const SizedBox(width: 6),
                  Text(
                    plafond,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _text,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMeritProgressCard() {
    final m = _meritProgress;
    if (m == null) return const SizedBox.shrink();
    final completed = (m['completed_missions'] as num?)?.toInt() ?? 0;
    final target = (m['target_missions'] as num?)?.toInt() ?? 10;
    final rating = (m['rating'] as num?)?.toDouble() ?? 0.0;
    final ratio = target > 0 ? (completed / target).clamp(0.0, 1.0) : 0.0;
    final eligible = m['eligible_for_tier2'] == true;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _isLight ? const Color(0xFFECFDF5) : const Color(0xFF0E3B2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF10B981).withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium_rounded, color: Color(0xFF10B981), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  eligible
                      ? 'Bravo : Niveau 2 (500 000 FCFA) debloque !'
                      : 'Niveau 2 gratuit des $target missions reussies',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: _isLight ? const Color(0xFF0E3B2E) : Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 7,
              backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.2),
              valueColor: const AlwaysStoppedAnimation(Color(0xFF10B981)),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$completed / $target missions · Note ${rating.toStringAsFixed(1)}/5',
            style: TextStyle(
              fontSize: 11.5,
              color: _isLight ? const Color(0xFF065F46) : const Color(0xFFD1FAE5),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoticeAdaptive() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFC2410C).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFC2410C).withValues(alpha: 0.28)),
      ),
      child: const Row(
        children: [
          Icon(Icons.verified_user_rounded, color: Color(0xFFC2410C), size: 22),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '100 % gratuit : confirmez votre identite pour recevoir vos missions en toute confiance.',
              style: TextStyle(fontSize: 12.5, color: Color(0xFFC2410C), fontWeight: FontWeight.w600, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  // Étape 1 : Infos CNI
  Widget _buildStep1CniInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SecurityBanner(isLight: _isLight),
        const SizedBox(height: 24),
        _sectionTitle('Informations de la pièce d\'identité'),
        const SizedBox(height: 12),
        _PremiumField(
          label: 'Numéro de CNI ou Passeport',
          controller: _cniCtrl,
          hint: 'Ex : CI 0123456789',
          error: _cniError,
          icon: Icons.numbers_rounded,
          isLight: _isLight,
          card: _card,
          text: _text,
          muted: _muted,
          border: _border,
        ),
        const SizedBox(height: 16),
        _DateField(
          label: 'Date d\'expiration',
          value: _expiryDate,
          error: _expiryError,
          isLight: _isLight,
          card: _card,
          text: _text,
          muted: _muted,
          border: _border,
          onPick: (d) => setState(() {
            _expiryDate = d;
            _expiryCtrl.text =
                '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
            _expiryError = null;
          }),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              title: Text(
                'Code au dos de la CNI (facultatif)',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _muted),
              ),
              subtitle: Text(
                'Permet une validation encore plus rapide',
                style: TextStyle(fontSize: 11, color: _muted.withValues(alpha: 0.8)),
              ),
              children: [
                TextFormField(
                  controller: _mrzCtrl,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.characters,
                  style: TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Recopiez les 3 lignes en bas au dos de la CNI',
                    hintStyle: TextStyle(color: _muted.withValues(alpha: 0.55)),
                    filled: true,
                    fillColor: _bg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _border),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() => _step = 0),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _border),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text('Précédent', style: TextStyle(color: _muted)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: _nextButton(
                label: 'Suivant : Photos CNI',
                icon: Icons.arrow_forward_rounded,
                enabled: true,
                onTap: () {
                  bool ok = true;
                  if (_cniCtrl.text.trim().length < 5) {
                    setState(() => _cniError = 'Numéro trop court (min 5 caractères)');
                    ok = false;
                  } else {
                    setState(() => _cniError = null);
                  }
                  if (_expiryDate == null) {
                    setState(() => _expiryError = 'Date d\'expiration requise');
                    ok = false;
                  } else if (_expiryDate!.isBefore(DateTime.now())) {
                    setState(() => _expiryError = 'Cette pièce est expirée');
                    ok = false;
                  } else {
                    setState(() => _expiryError = null);
                  }
                  if (ok) setState(() => _step = 2);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Étape 2 : Photos CNI (Recto, Verso, Selfie)
  Widget _buildStep2PhotosCni() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Photos de votre pièce & Selfie'),
        const SizedBox(height: 8),
        Text(
          'Ces photos prouvent votre identité et protègent la communauté des clients Babifix.',
          style: TextStyle(fontSize: 12, color: _muted),
        ),
        const SizedBox(height: 18),

        _buildPhotoItemCard(
          label: 'CNI Recto',
          hint: 'Face avant avec votre photo et nom',
          bytes: _rectoBytes,
          onPick: (b) => setState(() => _rectoBytes = b),
        ),
        const SizedBox(height: 14),

        _buildPhotoItemCard(
          label: 'CNI Verso',
          hint: 'Face arrière de votre pièce',
          bytes: _versoBytes,
          onPick: (b) => setState(() => _versoBytes = b),
        ),
        const SizedBox(height: 14),

        _buildPhotoItemCard(
          label: 'Selfie tenant votre pièce',
          hint: 'Votre visage et votre pièce visibles ensemble',
          bytes: _selfieBytes,
          onPick: (b) => setState(() => _selfieBytes = b),
          isSelfie: true,
        ),
        const SizedBox(height: 28),

        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() => _step = 1),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _border),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text('Précédent', style: TextStyle(color: _muted)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: _nextButton(
                label: 'Suivant : Validation',
                icon: Icons.arrow_forward_rounded,
                enabled: _rectoBytes != null && _versoBytes != null && _selfieBytes != null,
                onTap: () => setState(() => _step = 3),
              ),
            ),
          ],
        ),
      ],
    );
  }

  bool get _sensibleDocsComplete =>
      !_isSensible ||
      (_casierBytes != null &&
          _refNomCtrl.text.trim().length >= 2 &&
          _refTelCtrl.text.trim().length >= 8);

  // Étape 3 : Spécifique au Palier + contrôle régime métier sensible
  Widget _buildStep3SupervisionAndDocs() {
    final tierSection = _selectedTier == 'palier_1_proximite'
        ? _buildPalier1SupervisorSection()
        : (_selectedTier == 'palier_2_maitre'
            ? _buildPalier2CnmciSection()
            : _buildPalier3EnterpriseSection());

    if (!_isSensible) return tierSection;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSensibleSafetyBlock(),
        const SizedBox(height: 22),
        tierSection,
      ],
    );
  }

  Widget _buildSensibleSafetyBlock() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isLight ? const Color(0xFFF0FDFA) : const Color(0xFF0C2A2E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF14B8A6).withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF14B8A6).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.policy_rounded, color: Color(0xFF0F766E), size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _categoryNom.isNotEmpty
                          ? 'Metier sensible : $_categoryNom'
                          : 'Metier sensible : verification renforcee',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: _text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Casier judiciaire + 1 contact de reference + entretien visio obligatoires. Donne le badge "Casier verifie" aux familles.',
                      style: TextStyle(fontSize: 11.5, color: _muted, height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildPhotoItemCard(
            label: 'Extrait de Casier Judiciaire (Bulletin N° 3) *',
            hint: 'Document recent (< 3 mois), photo claire ou capture nette',
            bytes: _casierBytes,
            onPick: (b) => setState(() => _casierBytes = b),
          ),
          const SizedBox(height: 12),
          _buildPhotoItemCard(
            label: 'Certificat medical d\'aptitude (optionnel)',
            hint: 'Recommande pour garde d\'enfants et aide aux seniors',
            bytes: _certificatMedBytes,
            onPick: (b) => setState(() => _certificatMedBytes = b),
          ),
          const SizedBox(height: 14),
          _PremiumField(
            label: 'Personne de reference / Ancien employeur *',
            controller: _refNomCtrl,
            hint: 'Ex : Mme Kouame Nathalie',
            icon: Icons.person_search_rounded,
            isLight: _isLight,
            card: _card,
            text: _text,
            muted: _muted,
            border: _border,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          _PremiumField(
            label: 'Telephone du contact de reference *',
            controller: _refTelCtrl,
            hint: 'Ex : +225 07 XX XX XX XX',
            icon: Icons.phone_in_talk_rounded,
            isLight: _isLight,
            card: _card,
            text: _text,
            muted: _muted,
            border: _border,
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  Widget _buildPalier1SupervisorSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Validation de vos compétences · Palier 1'),
        const SizedBox(height: 8),
        Text(
          'Pas besoin de diplôme : votre admission se fait lors d\'un micro-entretien vidéo WhatsApp de 5 minutes avec le superviseur officiel de votre zone.',
          style: TextStyle(fontSize: 13, color: _muted, height: 1.4),
        ),
        const SizedBox(height: 20),

        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0F2642), Color(0xFF133256)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.4)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF22C55E).withValues(alpha: 0.15),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E).withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.support_agent_rounded, color: Color(0xFF22C55E), size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Superviseur Babifix · Zone $_commune',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Row(
                          children: [
                            Icon(Icons.circle, color: Color(0xFF22C55E), size: 8),
                            SizedBox(width: 6),
                            Text(
                              'En service pour entretien vidéo',
                              style: TextStyle(color: Color(0xFF4CC9F0), fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: Colors.white12),
              const SizedBox(height: 12),
              const Text(
                'Les 3 consignes pour réussir vos 5 minutes :',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
              ),
              const SizedBox(height: 8),
              _buildSupervisorBullet('1. Ayez vos principaux outils de travail sous la main'),
              _buildSupervisorBullet('2. Gardez votre pièce d\'identité physique avec vous'),
              _buildSupervisorBullet('3. Placez-vous dans un endroit bien éclairé et calme'),
              const SizedBox(height: 20),

              // Bouton WhatsApp officiel
              SizedBox(
                width: double.infinity,
                height: 54,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF25D366), Color(0xFF128C7E)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF25D366).withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: _requestingSupervisor ? null : _launchSupervisorWhatsApp,
                      child: Center(
                        child: _requestingSupervisor
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: BabifixRingLoader.mono(color: Colors.white, size: 22),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.video_call_rounded, color: Colors.white, size: 24),
                                  const SizedBox(width: 10),
                                  Text(
                                    _whatsappRequested
                                        ? 'Entretien WhatsApp lancé ✓ (Relancer)'
                                        : 'Lancer mon entretien WhatsApp (5 min)',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),

        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() => _step = 2),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _border),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text('Précédent', style: TextStyle(color: _muted)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: _nextButton(
                label: 'Suivant : Récapitulatif',
                icon: Icons.arrow_forward_rounded,
                enabled: _sensibleDocsComplete,
                onTap: () => setState(() => _step = 4),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPalier2CnmciSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Justificatifs Chambre des Métiers · Palier 2'),
        const SizedBox(height: 8),
        Text(
          'Renseignez votre immatriculation CNMCI pour débloquer le badge Maître Artisan et les interventions jusqu\'à 500 000 FCFA.',
          style: TextStyle(fontSize: 12, color: _muted),
        ),
        const SizedBox(height: 20),

        _PremiumField(
          label: 'Numéro d\'immatriculation CNMCI',
          controller: _cnmciCtrl,
          hint: 'Ex : CNMCI-ABJ-12345',
          icon: Icons.badge_outlined,
          isLight: _isLight,
          card: _card,
          text: _text,
          muted: _muted,
          border: _border,
        ),
        const SizedBox(height: 18),

        _buildPhotoItemCard(
          label: 'Photo de votre carte CNMCI ou diplôme',
          hint: 'Photo nette de votre carte professionnelle',
          bytes: _cnmciCardBytes,
          onPick: (b) => setState(() => _cnmciCardBytes = b),
        ),
        const SizedBox(height: 28),

        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() => _step = 2),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _border),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text('Précédent', style: TextStyle(color: _muted)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: _nextButton(
                label: 'Suivant : Récapitulatif',
                icon: Icons.arrow_forward_rounded,
                enabled: (_cnmciCtrl.text.isNotEmpty || _cnmciCardBytes != null) &&
                    _sensibleDocsComplete,
                onTap: () => setState(() => _step = 4),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPalier3EnterpriseSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Documents Entreprise BTP / PME · Palier 3'),
        const SizedBox(height: 8),
        Text(
          'Permet à votre entreprise d\'être sélectionnée pour les missions corporate B2B, syndics et devis d\'envergure.',
          style: TextStyle(fontSize: 12, color: _muted),
        ),
        const SizedBox(height: 20),

        _PremiumField(
          label: 'Numéro RCCM de l\'entreprise',
          controller: _rccmCtrl,
          hint: 'Ex : CI-ABJ-2024-B-12345',
          icon: Icons.business_outlined,
          isLight: _isLight,
          card: _card,
          text: _text,
          muted: _muted,
          border: _border,
        ),
        const SizedBox(height: 14),

        _PremiumField(
          label: 'Numéro Compte Contribuable (DGI)',
          controller: _ccCtrl,
          hint: 'Ex : 2101234 A',
          icon: Icons.receipt_long_rounded,
          isLight: _isLight,
          card: _card,
          text: _text,
          muted: _muted,
          border: _border,
        ),
        const SizedBox(height: 18),

        _buildPhotoItemCard(
          label: 'Document RCCM ou DFE scanné',
          hint: 'Photo ou scan de votre extrait de registre',
          bytes: _rccmDocBytes,
          onPick: (b) => setState(() => _rccmDocBytes = b),
        ),
        const SizedBox(height: 28),

        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() => _step = 2),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _border),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text('Précédent', style: TextStyle(color: _muted)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: _nextButton(
                label: 'Suivant : Récapitulatif',
                icon: Icons.arrow_forward_rounded,
                enabled: (_rccmCtrl.text.isNotEmpty || _rccmDocBytes != null) &&
                    _sensibleDocsComplete,
                onTap: () => setState(() => _step = 4),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSupervisorBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF22C55E), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 12, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoItemCard({
    required String label,
    required String hint,
    required Uint8List? bytes,
    required void Function(Uint8List) onPick,
    bool isSelfie = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: _bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border),
            ),
            child: bytes != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(bytes, fit: BoxFit.cover),
                  )
                : Icon(
                    isSelfie ? Icons.face_rounded : Icons.camera_alt_outlined,
                    color: _muted,
                    size: 28,
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: _text)),
                const SizedBox(height: 3),
                Text(hint, style: TextStyle(fontSize: 11, color: _muted)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _pickImage(ImageSource.camera, onPick),
                      icon: const Icon(Icons.camera_alt_rounded, size: 14),
                      label: const Text('Prendre photo', style: TextStyle(fontSize: 11)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0B1B34),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => _pickImage(ImageSource.gallery, onPick),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: _border),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Text('Galerie', style: TextStyle(fontSize: 11, color: _muted)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Étape 4 : Récapitulatif
  Widget _buildStep4Recap() {
    String tierLabel = 'Palier 1 · De Proximité (Expérience terrain)';
    Color tierColor = const Color(0xFFFF6B00);
    if (_selectedTier == 'palier_2_maitre') {
      tierLabel = 'Palier 2 · Maître Artisan (CNMCI)';
      tierColor = const Color(0xFF4CC9F0);
    } else if (_selectedTier == 'palier_3_entreprise') {
      tierLabel = 'Palier 3 · Entreprise BTP / PME';
      tierColor = const Color(0xFF22C55E);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Récapitulatif de votre dossier'),
        const SizedBox(height: 12),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow('Niveau sollicité', tierLabel, highlightColor: tierColor),
              _infoRow('Commune de rattachement', _commune),
              _infoRow('Pièce d\'identité N°', _cniCtrl.text),
              if (_expiryDate != null)
                _infoRow('Expiration pièce', '${_expiryDate!.day}/${_expiryDate!.month}/${_expiryDate!.year}'),
              if (_isSensible) ...[
                _infoRow('Regime metier', 'Sensible · Casier + visio obligatoires',
                    highlightColor: const Color(0xFF14B8A6)),
                _infoRow('Contact de reference', '${_refNomCtrl.text.trim()} (${_refTelCtrl.text.trim()})'),
                _infoRow('Casier judiciaire', _casierBytes != null ? 'Joint au dossier' : 'Manquant'),
                if (_certificatMedBytes != null)
                  _infoRow('Certificat medical', 'Joint au dossier'),
              ],
              if (_selectedTier == 'palier_1_proximite' || _isSensible)
                _infoRow('Micro-visio superviseur', _whatsappRequested ? 'Demandée via WhatsApp ✓' : 'À passer sous 24h'),
              if (_selectedTier == 'palier_2_maitre' && _cnmciCtrl.text.isNotEmpty)
                _infoRow('Numéro CNMCI', _cnmciCtrl.text),
              if (_selectedTier == 'palier_3_entreprise') ...[
                if (_rccmCtrl.text.isNotEmpty) _infoRow('Numéro RCCM', _rccmCtrl.text),
                if (_ccCtrl.text.isNotEmpty) _infoRow('Compte Contribuable', _ccCtrl.text),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),

        _sectionTitle('Pièces jointes prêtes'),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _thumbCard('CNI Recto', _rectoBytes)),
            const SizedBox(width: 8),
            Expanded(child: _thumbCard('CNI Verso', _versoBytes)),
            const SizedBox(width: 8),
            Expanded(child: _thumbCard('Selfie', _selfieBytes)),
          ],
        ),
        const SizedBox(height: 24),

        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() => _step = 3),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _border),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text('Précédent', style: TextStyle(color: _muted)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 52,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF6B00), Color(0xFFE87722)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF6B00).withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: _loading ? null : _submit,
                      child: Center(
                        child: _loading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: BabifixRingLoader.mono(color: Colors.white, size: 22),
                              )
                            : const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.send_rounded, color: Colors.white, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'Soumettre mon dossier',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _scoreSummaryText() {
    final parts = <String>[];
    if (_autoCheckScore != null) {
      parts.add('Score d\'analyse optique & anti-fraude : $_autoCheckScore / 100.');
    }
    if (_autoCheckHints.isNotEmpty) {
      parts.add('Points notes : ${_autoCheckHints.take(3).join(' · ')}.');
    }
    if (_meritProgress != null) {
      final c = (_meritProgress!['completed_missions'] as num?)?.toInt() ?? 0;
      final t = (_meritProgress!['target_missions'] as num?)?.toInt() ?? 10;
      parts.add('Progression Niveau 2 gratuit : $c/$t missions reussies.');
    }
    return parts.isEmpty ? '' : '\n\n${parts.join('\n')}';
  }

  Widget _buildDone() => _StatusCard(
        icon: Icons.check_circle_rounded,
        color: const Color(0xFF0E3B2E),
        title: 'Dossier transmis !',
        body: 'Votre dossier a ete analyse automatiquement et envoye avec succes.\n'
            'Votre superviseur de zone ($_commune) finalise la validation.${_scoreSummaryText()}',
        onBack: widget.onBack,
      );

  Widget _buildPending() => _StatusCard(
        icon: Icons.hourglass_top_rounded,
        color: const Color(0xFFC2410C),
        title: _statusKyc == 'under_review' ? 'En cours d\'examen' : 'En attente de verification',
        body: (_statusKyc == 'under_review'
                ? 'Notre superviseur de zone examine actuellement vos documents et votre outillage.'
                : 'Votre dossier est bien recu. La validation intervient rapidement.') +
            _scoreSummaryText(),
        onBack: widget.onBack,
      );

  Widget _buildRejected() => _StatusCard(
        icon: Icons.error_outline_rounded,
        color: const Color(0xFFDC2626),
        title: 'Dossier non valide',
        body: (_rejectReason != null && _rejectReason!.isNotEmpty
                ? 'Motif : $_rejectReason\n\nVous pouvez corriger vos pieces et soumettre a nouveau votre dossier.'
                : 'Votre dossier necessite des corrections. Verifiez la lisibilite de vos pieces ou contactez votre superviseur.') +
            _scoreSummaryText(),
        onBack: () => setState(() {
          _statusKyc = null;
          _step = 0;
        }),
      );

  Widget _buildApproved() => _StatusCard(
        icon: Icons.verified_rounded,
        color: const Color(0xFF0E3B2E),
        title: 'Statut Verifie actif',
        body: 'Felicitations ! Votre profil est verifie et pret a recevoir des missions remunerees sur Babifix.'
            '${_scoreSummaryText()}',
        onBack: widget.onBack,
      );

  Widget _sectionTitle(String t) => Text(
        t,
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _text),
      );

  Widget _infoRow(String label, String value, {Color? highlightColor}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$label : ', style: TextStyle(fontSize: 13, color: _muted, fontWeight: FontWeight.w600)),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  color: highlightColor ?? _text,
                  fontWeight: highlightColor != null ? FontWeight.w800 : FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _thumbCard(String label, Uint8List? bytes) => Container(
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _border),
        ),
        child: Column(
          children: [
            if (bytes != null)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                child: Image.memory(bytes, height: 70, width: double.infinity, fit: BoxFit.cover),
              )
            else
              Container(
                height: 70,
                decoration: BoxDecoration(
                  color: _muted.withValues(alpha: 0.1),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                ),
                child: const Center(child: Icon(Icons.image_outlined, color: Colors.grey)),
              ),
            Padding(
              padding: const EdgeInsets.all(6),
              child: Text(
                label,
                style: TextStyle(fontSize: 10, color: _muted, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );

  Widget _nextButton({
    required String label,
    required IconData icon,
    required bool enabled,
    VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 52,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: enabled ? const Color(0xFF0E3B2E) : _muted.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: enabled ? onTap : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: enabled ? Colors.white : _muted,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(icon, size: 16, color: enabled ? Colors.white : _muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Composants de style & champs
class _SecurityBanner extends StatelessWidget {
  const _SecurityBanner({required this.isLight});
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF4CC9F0).withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF4CC9F0).withValues(alpha: 0.25)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_rounded, color: Color(0xFF4CC9F0), size: 20),
              SizedBox(width: 8),
              Text(
                'Vérification sécurisée et confidentielle',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF4CC9F0)),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            'Vos pièces d\'identité sont chiffrées selon la réglementation ivoirienne de protection des données (Loi n° 2013-450) et traitées exclusivement par l\'équipe d\'accréditation.',
            style: TextStyle(fontSize: 11, color: Color(0xFF64748B), height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    required this.onBack,
  });
  final IconData icon;
  final Color color;
  final String title, body;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 40),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              body,
              style: const TextStyle(fontSize: 14, color: Color(0xFF64748B), height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Retour au profil'),
              style: FilledButton.styleFrom(backgroundColor: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _PremiumField extends StatelessWidget {
  const _PremiumField({
    required this.label,
    required this.controller,
    required this.hint,
    required this.icon,
    required this.isLight,
    required this.card,
    required this.text,
    required this.muted,
    required this.border,
    this.error,
    this.onChanged,
  });
  final String label, hint;
  final TextEditingController controller;
  final IconData icon;
  final bool isLight;
  final Color card, text, muted, border;
  final String? error;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: muted)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          onChanged: onChanged,
          style: TextStyle(color: text, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: muted.withValues(alpha: 0.6)),
            prefixIcon: Icon(icon, color: const Color(0xFF4CC9F0), size: 20),
            filled: true,
            fillColor: card,
            errorText: error,
            errorStyle: const TextStyle(color: Color(0xFFFF8A80), fontSize: 11),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF4CC9F0), width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onPick,
    required this.isLight,
    required this.card,
    required this.text,
    required this.muted,
    required this.border,
    this.error,
  });
  final String label;
  final DateTime? value;
  final void Function(DateTime) onPick;
  final bool isLight;
  final Color card, text, muted, border;
  final String? error;

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: muted)),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: value ?? DateTime.now().add(const Duration(days: 365)),
              firstDate: DateTime.now(),
              lastDate: DateTime(2040),
            );
            if (d != null) onPick(d);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: error != null ? const Color(0xFFFF8A80) : border),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_rounded, color: Color(0xFF4CC9F0), size: 20),
                const SizedBox(width: 10),
                Text(
                  value != null ? _fmt(value!) : 'Sélectionner la date',
                  style: TextStyle(
                    color: value != null ? text : muted.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(error!, style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 11)),
          ),
      ],
    );
  }
}
