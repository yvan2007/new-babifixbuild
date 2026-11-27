import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../babifix_design_system.dart';
import '../../models/babifix_models.dart';
import '../../services/babifix_api.dart';
import '../../shared/services/babifix_user_store.dart';
import '../premium/premium_screen.dart';
import '../../shared/widgets/babifix_button.dart';
import '../../shared/widgets/babifix_phase_widgets.dart';
import '../../shared/widgets/babifix_sheet.dart';
import '../../shared/widgets/babifix_snackbar.dart';

class DevisKanbanEditorScreen extends StatefulWidget {
  final String reservationReference;
  final int? categoryId;
  final String reservationTitle;
  final String clientName;
  final String clientProblem;
  final List<String> clientPhotos;
  final Map<String, dynamic> reponsesExigences;

  const DevisKanbanEditorScreen({
    super.key,
    required this.reservationReference,
    this.categoryId,
    this.reservationTitle = '',
    this.clientName = '',
    this.clientProblem = '',
    this.clientPhotos = const [],
    this.reponsesExigences = const {},
  });

  @override
  State<DevisKanbanEditorScreen> createState() =>
      _DevisKanbanEditorScreenState();
}

class _DevisKanbanEditorScreenState extends State<DevisKanbanEditorScreen> {
  final _diagnosticCtl = TextEditingController();
  final _noteCtl = TextEditingController();
  final _validiteCtl = TextEditingController(text: '7');
  DateTime? _dateProposee;
  TimeOfDay? _heureDebut;
  TimeOfDay? _heureFin;

  final List<LigneDevis> _lignes = [];
  List<CatalogueItem> _catalogue = [];
  List<Map<String, dynamic>> _smartItems = [];
  List<Map<String, dynamic>> _quickTemplates = [];
  Map<String, dynamic> _uiProfile = const {};
  int _plafondFcfa = 100000;
  String _artisanTier = 'palier_1_proximite';
  Map<String, dynamic>? _meritProgress;
  String _profilDevis = 'STANDARD';
  String _categoryNom = '';
  List<String> _recommendedUnits = const [];
  bool _sending = false;
  final List<String> _diagPhotos = [];
  final ImagePicker _picker = ImagePicker();
  bool _attemptedSend = false;
  double _remise = 0;

  bool get _showFournitures => _uiProfile['show_fournitures'] != false;
  bool get _showDiagPhotos => _uiProfile['show_diag_photos'] != false;
  String get _diagnosticSectionTitle =>
      '${_uiProfile['diagnostic_label'] ?? 'Diagnostic & planification'}';
  String get _mainOeuvreLabel {
    final labels = _uiProfile['line_labels'];
    if (labels is Map && '${labels['MAIN_OEUVRE'] ?? ''}'.trim().isNotEmpty) {
      return '${labels['MAIN_OEUVRE']}'.trim();
    }
    return "Main-d'oeuvre";
  }

  String get _fournitureLabel {
    final labels = _uiProfile['line_labels'];
    if (labels is Map && '${labels['FOURNITURE'] ?? ''}'.trim().isNotEmpty) {
      return '${labels['FOURNITURE']}'.trim();
    }
    return 'Fourniture';
  }

  String get _emptyLinesHint {
    final h = '${_uiProfile['empty_hint'] ?? ''}'.trim();
    if (h.isNotEmpty) return h;
    return _showFournitures
        ? "Fournitures, main-d'oeuvre, deplacement..."
        : 'Choisissez un modele rapide ci-dessus ou ajoutez une prestation.';
  }

  double get _sousTotal => _lignes.fold<double>(0, (s, l) => s + l.total);
  double get _baseTotal {
    final b = _sousTotal - _remise;
    return b < 0 ? 0 : b;
  }

  // Taux de commission EFFECTIF du presta (réduction premium incluse), chargé
  // depuis le serveur. 18 par défaut tant que non chargé.
  int _commissionRate = 18;
  double get _commission => _baseTotal * _commissionRate / 100;
  double get _net => _baseTotal - _commission;

  Future<void> _addDiagPhoto() async {
    if (_diagPhotos.length >= 6) {
      _snack('6 photos maximum.');
      return;
    }
    try {
      final x = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 1280,
      );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      final uri = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      if (mounted) setState(() => _diagPhotos.add(uri));
    } catch (_) {
      _snack("Impossible d'ajouter la photo.");
    }
  }

  @override
  void initState() {
    super.initState();
    _loadCatalogue();
    _loadDraft();
    _loadCommissionRate();
    _loadSmartAssist();
  }

  Future<void> _loadSmartAssist() async {
    try {
      final problemText = [
        widget.reservationTitle,
        widget.clientProblem,
        _diagnosticCtl.text,
      ].where((s) => s.trim().isNotEmpty).join(' ');
      final params = <String, String>{};
      if (problemText.isNotEmpty) params['description'] = problemText;
      if (widget.categoryId != null) {
        params['category_id'] = '${widget.categoryId}';
      }
      final uri = Uri(
        path: '/api/prestataire/smart/devis-assist/',
        queryParameters: params.isEmpty ? null : params,
      );
      final resp = await BabifixUserStore.authGet(uri.toString());
      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(resp.body);
        if (data is Map<String, dynamic>) {
          final bench = data['benchmark'];
          final benchMap =
              bench is Map ? Map<String, dynamic>.from(bench) : null;
          final rawItems = benchMap?['suggested_items'] ?? data['suggested_items'];
          final unitsRaw = data['recommended_units'];
          final uiProf = data['devis_ui_profile'];
          final rawTemplates = data['quick_templates'];
          final rawMerit = data['merit_progress'];
          setState(() {
            _profilDevis = '${data['profil_devis'] ?? 'STANDARD'}'.toUpperCase();
            _categoryNom = '${data['category_nom'] ?? ''}'.trim();
            if (uiProf is Map) {
              _uiProfile = Map<String, dynamic>.from(uiProf);
            }
            if (rawTemplates is List) {
              _quickTemplates = rawTemplates
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList();
            }
            final plaf = (data['plafond_intervention_fcfa'] as num?)?.toInt();
            if (plaf != null && plaf > 0) _plafondFcfa = plaf;
            final tier = '${data['artisan_tier'] ?? ''}'.trim();
            if (tier.isNotEmpty) _artisanTier = tier;
            if (rawMerit is Map) {
              _meritProgress = Map<String, dynamic>.from(rawMerit);
            }
            if (unitsRaw is List) {
              _recommendedUnits = unitsRaw
                  .map((e) => '$e'.trim())
                  .where((e) => e.isNotEmpty)
                  .toList();
            }
            if (rawItems is List) {
              _smartItems = rawItems
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList();
            }
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _loadCommissionRate() async {
    final rate = await ProviderApi.effectiveCommissionRate();
    if (mounted) setState(() => _commissionRate = rate);
  }

  TimeOfDay? _parseTime(String? s) {
    if (s == null || s.isEmpty) return null;
    final parts = s.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  Future<void> _loadDraft() async {
    try {
      final d = await DevisApi.getDraft(widget.reservationReference);
      if (d == null || !mounted) return;
      setState(() {
        _diagnosticCtl.text = (d['diagnostic'] ?? '').toString();
        _noteCtl.text = (d['note_prestataire'] ?? '').toString();
        _validiteCtl.text = '${d['validite_jours'] ?? 7}';
        _remise = (d['remise'] as num?)?.toDouble() ?? 0;
        final dp = d['date_proposee']?.toString();
        if (dp != null && dp.isNotEmpty) _dateProposee = DateTime.tryParse(dp);
        _heureDebut = _parseTime(d['heure_debut']?.toString());
        _heureFin = _parseTime(d['heure_fin']?.toString());
        _diagPhotos
          ..clear()
          ..addAll((d['photos_prestataire'] as List? ?? const [])
              .map((e) => e.toString())
              .where((e) => e.isNotEmpty));
        _lignes
          ..clear()
          ..addAll((d['lignes'] as List? ?? const [])
              .whereType<Map>()
              .map((m) {
            final q = (m['quantite'] as num?)?.toDouble() ?? 1;
            final p = (m['prix_unitaire'] as num?)?.toDouble() ?? 0;
            return LigneDevis(
              typeLigne:
                  DevisLineType.fromCode((m['type_ligne'] ?? 'AUTRE').toString()),
              description: (m['description'] ?? '').toString(),
              quantite: q,
              prixUnitaire: p,
              unite: (m['unite'] ?? '').toString(),
              marque: (m['marque'] ?? '').toString(),
              total: q * p,
            );
          }));
      });
      if (mounted) _snack('Brouillon restauré.');
    } catch (_) {}
  }

  Future<void> _saveDraft() async {
    if (_lignes.isEmpty && _diagnosticCtl.text.trim().isEmpty) {
      _snack('Rien à enregistrer pour le moment.');
      return;
    }
    setState(() => _sending = true);
    try {
      String? dp;
      if (_dateProposee != null) {
        dp = '${_dateProposee!.year}-${_dateProposee!.month.toString().padLeft(2, '0')}-${_dateProposee!.day.toString().padLeft(2, '0')}';
      }
      String? toIso(TimeOfDay? t) => t == null
          ? null
          : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      await DevisApi.create(
        reference: widget.reservationReference,
        diagnostic: _diagnosticCtl.text.trim(),
        dateProposee: dp,
        heureDebut: toIso(_heureDebut),
        heureFin: toIso(_heureFin),
        validiteJours: int.tryParse(_validiteCtl.text.trim()) ?? 7,
        notePrestataire: _noteCtl.text.trim(),
        photosPrestataire: _diagPhotos,
        remise: _remise,
        draft: true,
        lignes: _lignes,
      );
      if (!mounted) return;
      showBabifixToast(
        context,
        type: BabifixToastType.success,
        message: 'Brouillon enregistré.',
      );
    } on BabifixApiException catch (e) {
      if (e.code == 'devis_quota_reached' && mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Quota de devis atteint'),
            content: Text(e.message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Fermer'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB45309)),
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const PremiumScreen()),
                  );
                },
                child: const Text('Passer Pro / Gold'),
              ),
            ],
          ),
        );
      } else if (e.code == 'detail_required_high_amount' && mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Detail recommande pour ce montant'),
            content: Text(
              '${e.message}\n\nAjoutez au moins une 2e ligne (ou une note explicative de 15 caracteres minimum) pour rassurer le client.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Fermer'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0E3B2E),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  _addEmptyLine(
                    _showFournitures
                        ? DevisLineType.fourniture
                        : DevisLineType.mainOeuvre,
                  );
                },
                child: const Text('Ajouter une ligne'),
              ),
            ],
          ),
        );
      } else {
        _snack(e.message);
      }
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _diagnosticCtl.dispose();
    _noteCtl.dispose();
    _validiteCtl.dispose();
    super.dispose();
  }

  Future<void> _loadCatalogue() async {
    final cid = widget.categoryId;
    if (cid == null) return;
    try {
      _catalogue = await CatalogueApi.forCategory(cid);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  String get _defaultLineUnit {
    if (_recommendedUnits.isNotEmpty) return _recommendedUnits.first;
    if (_profilDevis == 'SURFACE') return 'm²';
    if (_profilDevis == 'FORFAIT') return 'forfait';
    return 'u';
  }

  String get _diagnosticHint {
    final profHint = '${_uiProfile['diagnostic_hint'] ?? ''}'.trim();
    if (profHint.isNotEmpty) return profHint;
    switch (_profilDevis) {
      case 'SURFACE':
        return 'Surface mesuree (m²), etat du support, preparation requise...';
      case 'DIAGNOSTIC':
        return 'Panne relevee sur appareil/installation, pieces et tests requis...';
      case 'FORFAIT':
        return 'Perimetre exact de la prestation, horaires, consignes et engagement...';
      default:
        return 'Analyse du probleme observe sur place';
    }
  }

  void _applyQuickTemplate(Map<String, dynamic> tpl) {
    final diag = '${tpl['diagnostic'] ?? ''}'.trim();
    final linesRaw = tpl['lignes'];
    final nextLines = <LigneDevis>[];
    if (linesRaw is List) {
      for (final raw in linesRaw) {
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        final q = (m['quantite'] as num?)?.toDouble() ?? 1.0;
        final p = (m['prix_unitaire'] as num?)?.toDouble() ?? 0.0;
        nextLines.add(
          LigneDevis(
            typeLigne: DevisLineType.fromCode(
              '${m['type_ligne'] ?? 'MAIN_OEUVRE'}',
            ),
            description: '${m['description'] ?? ''}'.trim(),
            quantite: q,
            prixUnitaire: p,
            unite: '${m['unite'] ?? _defaultLineUnit}'.trim(),
            total: q * p,
          ),
        );
      }
    }
    setState(() {
      if (diag.isNotEmpty) _diagnosticCtl.text = diag;
      if (nextLines.isNotEmpty) {
        _lignes
          ..clear()
          ..addAll(nextLines);
      }
    });
    showBabifixToast(
      context,
      type: BabifixToastType.success,
      message:
          'Modele "${tpl['title'] ?? 'Rapide'}" applique. Ajustez les montants si besoin.',
    );
  }

  void _addEmptyLine(DevisLineType t) {
    final unit = (t == DevisLineType.mainOeuvre && _profilDevis == 'FORFAIT')
        ? 'forfait'
        : _defaultLineUnit;
    setState(() {
      _lignes.add(LigneDevis(
        typeLigne: t,
        description: '',
        quantite: 1,
        prixUnitaire: 0,
        unite: unit,
        total: 0,
      ));
    });
  }

  void _removeLine(LigneDevis l) {
    setState(() => _lignes.remove(l));
  }

  Future<void> _openCatalogue([DevisLineType? section]) async {
    if (_catalogue.isEmpty) {
      showBabifixToast(
        context,
        type: BabifixToastType.info,
        message: 'Catalogue vide pour votre catégorie.',
      );
      return;
    }
    final filtered = section == null
        ? _catalogue
        : _catalogue.where((c) => c.typeLigne == section).toList();
    final searchCtl = TextEditingController();
    final picked = await showBabifixModalSheet<CatalogueItem>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scroll) {
          return StatefulBuilder(builder: (ctx, setSb) {
            final q = searchCtl.text.toLowerCase().trim();
            final list = filtered
                .where((c) =>
                    q.isEmpty ||
                    c.nom.toLowerCase().contains(q) ||
                    c.marque.toLowerCase().contains(q))
                .toList();
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    section == null
                        ? 'Catalogue'
                        : 'Catalogue · ${section.label}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: searchCtl,
                    onChanged: (_) => setSb(() {}),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Rechercher…',
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: list.isEmpty
                      ? Center(
                          child: Text(
                              q.isEmpty
                                  ? 'Aucun item dans cette section.'
                                  : 'Aucun résultat pour "$q".',
                              style: TextStyle(
                                  color: Colors.grey.shade600)),
                        )
                      : ListView.separated(
                          controller: scroll,
                          itemCount: list.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final c = list[i];
                            return ListTile(
                              leading: const Icon(Icons.add_circle_outline,
                                  color: Colors.deepPurple),
                              title: Text(c.nom),
                              subtitle: Text([
                                if (c.marque.isNotEmpty) c.marque,
                                '${fmtMoney(c.prixUnitaireIndicatif)} / ${c.unite}',
                              ].join(' · ')),
                              onTap: () => Navigator.pop(ctx, c),
                            );
                          },
                        ),
                ),
              ],
            );
          });
        },
      ),
    );
    if (picked != null) {
      setState(() {
        _lignes.add(LigneDevis(
          typeLigne: picked.typeLigne,
          description: picked.nom,
          quantite: 1,
          prixUnitaire: picked.prixUnitaireIndicatif,
          unite: picked.unite,
          marque: picked.marque,
          catalogueItemId: picked.id,
          total: picked.prixUnitaireIndicatif,
        ));
      });
    }
  }

  void _openPreview() {
    final preview = Devis(
      reference: 'APERÇU',
      diagnostic: _diagnosticCtl.text.trim(),
      dateProposee: _dateProposee == null
          ? null
          : '${_dateProposee!.year}-${_dateProposee!.month.toString().padLeft(2, '0')}-${_dateProposee!.day.toString().padLeft(2, '0')}',
      heureDebut: _heureDebut?.format(context),
      heureFin: _heureFin?.format(context),
      sousTotal: _sousTotal,
      remise: _remise,
      commissionRate: _commissionRate,
      commissionMontant: _commission,
      totalTtc: _baseTotal,
      netPrestataire: _net,
      notePrestataire: _noteCtl.text.trim(),
      validiteJours: int.tryParse(_validiteCtl.text.trim()) ?? 7,
      statut: DevisStatus.brouillon,
      lignes: _lignes,
    );
    showBabifixModalSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scroll) => SingleChildScrollView(
          controller: scroll,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 8),
              Text('Aperçu du devis',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: BabifixDesign.ciBlue)),
              Text(
                'Voici ce que le client verra exactement.',
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
              DevisCardWidget(devis: preview),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.edit),
                label: const Text('Modifier'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _ligneIncomplete(LigneDevis l) =>
      l.description.trim().isEmpty || l.prixUnitaire <= 0;

  Future<void> _send() async {
    if (_diagnosticCtl.text.trim().isEmpty) {
      _snack('Le diagnostic est obligatoire.');
      return;
    }
    if (_lignes.isEmpty) {
      _snack('Ajoutez au moins une ligne de devis.');
      return;
    }
    if (_lignes.any(_ligneIncomplete)) {
      setState(() => _attemptedSend = true);
      _snack('Complétez les lignes en rouge (désignation et prix).');
      return;
    }
    if (_sousTotal <= 0) {
      _snack('Le total doit être supérieur à 0.');
      return;
    }
    setState(() => _sending = true);
    try {
      String? dp;
      if (_dateProposee != null) {
        dp = '${_dateProposee!.year}-${_dateProposee!.month.toString().padLeft(2, '0')}-${_dateProposee!.day.toString().padLeft(2, '0')}';
      }
      String? toIso(TimeOfDay? t) =>
          t == null ? null : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      await DevisApi.create(
        reference: widget.reservationReference,
        diagnostic: _diagnosticCtl.text.trim(),
        dateProposee: dp,
        heureDebut: toIso(_heureDebut),
        heureFin: toIso(_heureFin),
        validiteJours: int.tryParse(_validiteCtl.text.trim()) ?? 7,
        notePrestataire: _noteCtl.text.trim(),
        photosPrestataire: _diagPhotos,
        remise: _remise,
        lignes: _lignes,
      );
      if (!mounted) return;
      showBabifixToast(
        context,
        type: BabifixToastType.success,
        message: 'Devis envoyé au client.',
      );
      Navigator.of(context).pop(true);
    } on BabifixApiException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _snack(String s) {
    if (!mounted) return;
    showBabifixToast(
        context,
        type: BabifixToastType.info,
        message: s,
      );
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final lightBase = ThemeData.light(useMaterial3: true);
    return Theme(
      data: lightBase.copyWith(
        colorScheme: lightBase.colorScheme.copyWith(
          primary: BabifixDesign.cyan,
          secondary: BabifixDesign.ciOrange,
          surface: Colors.white,
          onSurface: BabifixDesign.navy,
        ),
      ),
      child: Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.request_quote_rounded, color: BabifixDesign.navy, size: 18),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Nouveau devis',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  Text('Établir un devis professionnel',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w400)),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: BabifixDesign.navy,
        elevation: 0,
        surfaceTintColor: Colors.white,
        actions: [
          TextButton.icon(
            onPressed: _sending ? null : _saveDraft,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('Brouillon'),
            style: TextButton.styleFrom(
              foregroundColor: BabifixDesign.cyan,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              children: [
                _clientRequestCard(),
                if (_quickTemplates.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _quickTemplatesCard(),
                ],
                const SizedBox(height: 14),
                _topInfosCard(),
                if (_showDiagPhotos) ...[
                  const SizedBox(height: 14),
                  _diagPhotosCard(),
                ],
                const SizedBox(height: 14),
                _lignesCard(),
                const SizedBox(height: 14),
                _devisCoherenceBanner(),
                _escrowNote(),
                const SizedBox(height: 100),
              ],
            ),
          ),
          SafeArea(top: false, bottom: true, child: _bottomBar()),
        ],
      ),
    ),
    );
  }

  // ─── Client Request Card ─────────────────────────────────────────────────

  Widget _clientRequestCard() {
    final hasProblem = widget.clientProblem.trim().isNotEmpty;
    final hasPhotos = widget.clientPhotos.isNotEmpty;
    final hasName = widget.clientName.trim().isNotEmpty;
    final hasExigences = widget.reponsesExigences.isNotEmpty;
    final hasMeta = _categoryNom.isNotEmpty || _recommendedUnits.isNotEmpty;
    if (!hasProblem && !hasPhotos && !hasName && !hasExigences && !hasMeta) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: const Border(left: BorderSide(color: BabifixDesign.cyan, width: 3)),
        boxShadow: [
          BoxShadow(color: const Color(0x080F172A), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: BabifixDesign.cyan.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.person_outline_rounded, size: 20, color: BabifixDesign.cyan),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Demande du client',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: BabifixDesign.navy)),
                    if (hasName)
                      Text(widget.clientName,
                          style: TextStyle(fontSize: 12, color: BabifixDesign.iconOnLight)),
                  ],
                ),
              ),
              if (widget.reservationTitle.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: BabifixDesign.navy,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(widget.reservationTitle,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white)),
                  ),
                ),
            ],
          ),
          if (hasProblem) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.chat_bubble_outline_rounded, size: 16, color: BabifixDesign.iconOnLight),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(widget.clientProblem,
                        style: const TextStyle(fontSize: 13, height: 1.5, color: BabifixDesign.navy)),
                  ),
                ],
              ),
            ),
          ],
          if (hasPhotos) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 76,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.clientPhotos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => _openPhoto(widget.clientPhotos[i]),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: _ClientPhoto(src: widget.clientPhotos[i], size: 76),
                  ),
                ),
              ),
            ),
          ],
          if (hasExigences || hasMeta) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F9FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBAE6FD)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.assignment_turned_in_rounded,
                          size: 15, color: Color(0xFF0369A1)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _categoryNom.isNotEmpty
                              ? 'Fiche metier : $_categoryNom ($_profilDevis)'
                              : 'Cahier des charges client ($_profilDevis)',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0369A1),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_recommendedUnits.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Unites recommandees : ${_recommendedUnits.join(', ')}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF0C4A6E)),
                    ),
                  ],
                  if (hasExigences) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final entry in widget.reponsesExigences.entries)
                          Builder(builder: (_) {
                            final v = entry.value;
                            String label = entry.key;
                            String valText = '$v';
                            if (v is Map) {
                              label = '${v['label'] ?? entry.key}';
                              final unit = '${v['unit'] ?? ''}'.trim();
                              final rawVal = v['value'];
                              valText = rawVal is bool
                                  ? (rawVal ? 'Oui' : 'Non')
                                  : '$rawVal${unit.isNotEmpty ? ' $unit' : ''}';
                            }
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFBAE6FD)),
                              ),
                              child: Text(
                                '$label : $valText',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: BabifixDesign.navy,
                                ),
                              ),
                            );
                          }),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openPhoto(String src) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Center(
                child: _ClientPhoto(src: src, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Modeles prets en 1 clic ─────────────────────────────────────────────

  Widget _quickTemplatesCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: const Border(
          left: BorderSide(color: Color(0xFF0E3B2E), width: 3),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080F172A),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF0E3B2E).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.flash_on_rounded,
                  size: 16,
                  color: Color(0xFF0E3B2E),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Modeles prets en 1 clic (${_categoryNom.isNotEmpty ? _categoryNom : 'Votre metier'})',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: BabifixDesign.navy,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Touchez un modele pour pre-remplir automatiquement le devis. Vous modifiez ensuite les montants librement.',
            style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 76,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _quickTemplates.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final tpl = _quickTemplates[i];
                final title = '${tpl['title'] ?? 'Modele'}';
                final subtitle = '${tpl['subtitle'] ?? ''}'.trim();
                return InkWell(
                  onTap: () => _applyQuickTemplate(tpl),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 215,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF0E3B2E).withValues(alpha: 0.25),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0E3B2E),
                          ),
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF334155),
                              height: 1.25,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ─── Diagnostic & Scheduling Card ────────────────────────────────────────

  Widget _topInfosCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: const Border(left: BorderSide(color: BabifixDesign.navy, width: 3)),
        boxShadow: [
          BoxShadow(color: const Color(0x080F172A), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: BabifixDesign.navy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _showFournitures ? Icons.biotech_rounded : Icons.event_note_rounded,
                  size: 18,
                  color: BabifixDesign.navy,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _diagnosticSectionTitle,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: BabifixDesign.navy,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _diagnosticCtl,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: '$_diagnosticSectionTitle *',
              hintText: _diagnosticHint,
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            ),
          ),
          // Date proposée / Début / Fin retirés : la planification se fait via
          // le créneau choisi par le client, pas dans le devis.
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: BabifixDesign.warning.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.verified_outlined, size: 16, color: BabifixDesign.warning),
              ),
              const SizedBox(width: 10),
              const Text('Valable', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: BabifixDesign.navy)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: DropdownButton<int>(
                  value: int.tryParse(_validiteCtl.text.trim()) ?? 7,
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  style: const TextStyle(fontSize: 12.5, color: BabifixDesign.navy, fontWeight: FontWeight.w600),
                  items: const [3, 7, 14, 30]
                      .map((d) => DropdownMenuItem(
                            value: d,
                            child: Text('$d jours', style: const TextStyle(fontSize: 12.5)),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _validiteCtl.text = '${v ?? 7}'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteCtl,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Note pour le client (optionnel)',
              hintText: 'Conditions, garantie, précisions…',
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Diagnostic Photos Card ──────────────────────────────────────────────

  Widget _diagPhotosCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: const Border(left: BorderSide(color: BabifixDesign.warning, width: 3)),
        boxShadow: [
          BoxShadow(color: const Color(0x080F172A), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: BabifixDesign.warning.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.add_a_photo_outlined, size: 18, color: BabifixDesign.warning),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Photos du diagnostic',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: BabifixDesign.navy)),
                    Text('${_diagPhotos.length}/6 · Justifiez votre devis avec des photos',
                        style: TextStyle(fontSize: 11, color: BabifixDesign.iconOnLight)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 76,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                ..._diagPhotos.asMap().entries.map((e) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Stack(
                        children: [
                          GestureDetector(
                            onTap: () => _openPhoto(e.value),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: _ClientPhoto(src: e.value, size: 76),
                            ),
                          ),
                          Positioned(
                            top: 2,
                            right: 2,
                            child: GestureDetector(
                              onTap: () => setState(() => _diagPhotos.removeAt(e.key)),
                              child: Container(
                                decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle),
                                padding: const EdgeInsets.all(2),
                                child: const Icon(Icons.close,
                                    size: 14, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )),
                if (_diagPhotos.length < 6)
                  GestureDetector(
                    onTap: _addDiagPhoto,
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: const Icon(Icons.add_rounded,
                          color: BabifixDesign.iconOnLight, size: 28),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Line Items Card ─────────────────────────────────────────────────────

  Widget _lignesCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: const Border(left: BorderSide(color: BabifixDesign.cyan, width: 3)),
        boxShadow: [
          BoxShadow(color: const Color(0x080F172A), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: BabifixDesign.cyan.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.receipt_long_rounded, size: 18, color: BabifixDesign.cyan),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Détail du devis',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: BabifixDesign.navy)),
              ),
              if (_catalogue.isNotEmpty)
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: BabifixDesign.cyan.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: TextButton.icon(
                    onPressed: () => _openCatalogue(),
                    icon: const Icon(Icons.library_books, size: 16),
                    label: const Text('Catalogue', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: BabifixDesign.cyan,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    ),
                  ),
                ),
            ],
          ),
          if (_catalogue.isNotEmpty || _smartItems.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildQuickSuggestionsBar(),
          ],
          const SizedBox(height: 14),
          if (_lignes.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 32),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  Icon(Icons.receipt_long_outlined, size: 48, color: const Color(0xFFCBD5E1)),
                  const SizedBox(height: 8),
                  Text('Ajoutez les lignes de votre devis',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: BabifixDesign.iconOnLight)),
                  const SizedBox(height: 4),
                  Text(_emptyLinesHint,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: BabifixDesign.iconOnLight.withValues(alpha: 0.7))),
                ],
              ),
            )
          else
            ...List.generate(_lignes.length, (i) {
              final l = _lignes[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _DevisLineEditor(
                  ligne: l,
                  highlightError: _attemptedSend && _ligneIncomplete(l),
                  recommendedUnits: _recommendedUnits,
                  onChange: (nl) {
                    setState(() {
                      final idx = _lignes.indexOf(l);
                      if (idx >= 0) _lignes[idx] = nl;
                    });
                  },
                  onRemove: () => _removeLine(l),
                ),
              );
            }),
          const SizedBox(height: 14),
          Text('Ajouter une ligne',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: BabifixDesign.iconOnLight)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_showFournitures)
                _addTypeChip(DevisLineType.fourniture, _fournitureLabel, Icons.inventory_2_rounded),
              _addTypeChip(DevisLineType.mainOeuvre, _mainOeuvreLabel, Icons.engineering_rounded),
              _addTypeChip(DevisLineType.autre, 'Autre', Icons.add_circle_outline_rounded),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: BabifixDesign.success.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.local_offer_rounded, size: 16, color: BabifixDesign.success),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Remise',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: BabifixDesign.navy)),
                ),
                SizedBox(
                  width: 140,
                  child: TextField(
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    // Saisie numérique uniquement : on bloque toute lettre/texte
                    // dans les champs de montant (chiffres + séparateur décimal).
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    textAlign: TextAlign.end,
                    decoration: InputDecoration(
                      hintText: '0',
                      suffixText: 'FCFA',
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                    onChanged: (v) => setState(() =>
                        _remise = double.tryParse(v.replaceAll(',', '.')) ?? 0),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _addTypeChip(DevisLineType type, String label, IconData icon) {
    return Material(
      color: BabifixDesign.cyan.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _addEmptyLine(type),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: BabifixDesign.cyan.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: BabifixDesign.cyan),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: BabifixDesign.cyan)),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Suggestions Rapides 1-Clic ──────────────────────────────────────────

  Widget _buildQuickSuggestionsBar() {
    final previewItems = _catalogue.length > 8 ? _catalogue.sublist(0, 8) : _catalogue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_smartItems.isNotEmpty) ...[
          Row(
            children: [
              const Icon(Icons.bolt_rounded, size: 15, color: BabifixDesign.ciOrange),
              const SizedBox(width: 4),
              Text(
                'Kits recommandes pour ce diagnostic :',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: BabifixDesign.navy.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _smartItems.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) {
                final it = _smartItems[i];
                final nom = (it['nom'] ?? '').toString();
                final prix = (it['prix'] as num?)?.toDouble() ?? 0;
                final typeCode = (it['type_ligne'] ?? 'FOURNITURE').toString();
                final unite = (it['unite'] ?? '').toString();
                return InkWell(
                  onTap: () {
                    setState(() {
                      _lignes.add(LigneDevis(
                        typeLigne: DevisLineType.fromCode(typeCode),
                        description: nom,
                        quantite: 1,
                        prixUnitaire: prix,
                        unite: unite,
                        total: prix,
                      ));
                    });
                    showBabifixToast(
                      context,
                      type: BabifixToastType.success,
                      message: '$nom ajoute.',
                    );
                  },
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFFED7AA)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add_circle_outline, size: 13, color: BabifixDesign.ciOrange),
                        const SizedBox(width: 5),
                        Text(
                          '$nom (${fmtMoney(prix)})',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: BabifixDesign.navy,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (previewItems.isNotEmpty) const SizedBox(height: 10),
        ],
        if (previewItems.isNotEmpty) ...[
          Row(
            children: [
              const Icon(Icons.inventory_2_outlined, size: 15, color: BabifixDesign.cyan),
              const SizedBox(width: 4),
              Text(
                'Catalogue rapide (1-clic) :',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: BabifixDesign.navy.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: previewItems.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) {
                final it = previewItems[i];
                final isFourniture = it.typeLigne == DevisLineType.fourniture;
                return InkWell(
                  onTap: () {
                    setState(() {
                      _lignes.add(LigneDevis(
                        typeLigne: it.typeLigne,
                        description: it.nom,
                        quantite: 1,
                        prixUnitaire: it.prixUnitaireIndicatif,
                        unite: it.unite,
                        marque: it.marque,
                        catalogueItemId: it.id,
                        total: it.prixUnitaireIndicatif,
                      ));
                    });
                    showBabifixToast(
                      context,
                      type: BabifixToastType.success,
                      message: '${it.nom} ajoute.',
                    );
                  },
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isFourniture
                          ? const Color(0xFFEFF6FF)
                          : const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isFourniture
                            ? const Color(0xFFBFDBFE)
                            : const Color(0xFFBBF7D0),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isFourniture
                              ? Icons.add_circle_outline
                              : Icons.check_circle_outline,
                          size: 13,
                          color: isFourniture
                              ? const Color(0xFF1D4ED8)
                              : const Color(0xFF15803D),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '${it.nom} (${fmtMoney(it.prixUnitaireIndicatif)})',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isFourniture
                                ? const Color(0xFF1E40AF)
                                : const Color(0xFF166534),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  // ─── Escrow Security Note ────────────────────────────────────────────────

  Widget _devisCoherenceBanner() {
    String? msg;
    var isWarn = false;
    final hasZeroLine = _lignes.any((l) => l.prixUnitaire <= 0);
    final hasFourniture = _lignes.any((l) => l.typeLigne == DevisLineType.fourniture);
    final hasMo = _lignes.any((l) => l.typeLigne == DevisLineType.mainOeuvre);
    final exceedsCeiling = _baseTotal > _plafondFcfa && _plafondFcfa > 0;

    if (_lignes.isNotEmpty && hasZeroLine) {
      msg = 'Une ligne du devis a un prix unitaire a 0 FCFA.';
      isWarn = true;
    } else if (exceedsCeiling) {
      final completed = (_meritProgress?['completed_missions'] as num?)?.toInt() ?? 0;
      final needed = (_meritProgress?['target_missions'] as num?)?.toInt() ?? 10;
      final tierLabel = _artisanTier == 'palier_2_maitre'
          ? 'Niveau 2'
          : (_artisanTier == 'palier_3_entreprise' ? 'Niveau 3' : 'Niveau 1');
      msg = 'Montant superieur a ${fmtMoney(_plafondFcfa.toDouble())} ($tierLabel) : '
          'le client paiera par Mobile Money securise. '
          'Niveau 2 gratuit des $needed missions ($completed/$needed).';
      isWarn = false;
    } else if (_showFournitures && hasFourniture && !hasMo) {
      msg = 'Vous avez ajoute des fournitures sans ligne de main-d\'oeuvre.';
    }

    if (msg == null) return const SizedBox.shrink();
    final accent = isWarn
        ? BabifixDesign.ciOrange
        : (exceedsCeiling ? const Color(0xFF0E3B2E) : BabifixDesign.cyan);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withValues(alpha: 0.28)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isWarn
                  ? Icons.warning_amber_rounded
                  : (exceedsCeiling
                      ? Icons.verified_user_outlined
                      : Icons.tips_and_updates_outlined),
              size: 18,
              color: accent,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                msg,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  color: BabifixDesign.navy,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _escrowNote() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BabifixDesign.success.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BabifixDesign.success.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: BabifixDesign.success.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.shield_rounded, size: 16, color: BabifixDesign.success),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Paiement sécurisé',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: BabifixDesign.navy)),
                const SizedBox(height: 4),
                Text(
                  'Des que le client accepte, son paiement est garde en securite par BABIFIX. '
                  'Vous etes paye automatiquement a la fin du travail.',
                  style: TextStyle(fontSize: 12, height: 1.4, color: BabifixDesign.iconOnLight),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Bottom Bar ──────────────────────────────────────────────────────────

  Widget _bottomBar() {
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 50;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isKeyboardOpen)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              color: Colors.white,
              child: MoneyBreakdownWidget(
                sousTotal: _sousTotal,
                remise: _remise,
                commissionRate: _commissionRate,
                commissionMontant: _commission,
                totalTtc: _baseTotal,
                netPrestataire: _net,
                compact: true,
                showProviderNet: true,
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: const Color(0xFFF8FAFC),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Net artisan :',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: BabifixDesign.navy)),
                  Text('${_net.toStringAsFixed(0)} FCFA',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF16A34A))),
                ],
              ),
            ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: const Color(0x0A0F172A),
                blurRadius: 12,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _sending ? null : _openPreview,
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('Aperçu'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: BabifixDesign.textPrimaryOf(context),
                    side: BorderSide(color: BabifixDesign.borderOf(context)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: BabifixButton(
                  label: 'Envoyer au client',
                  loadingLabel: 'Envoi...',
                  icon: Icons.send_rounded,
                  height: 48,
                  borderRadius: 14,
                  isLoading: _sending,
                  onPressed: _sending ? null : _send,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  }
}

// ─── Line Editor ────────────────────────────────────────────────────────────

class _DevisLineEditor extends StatefulWidget {
  final LigneDevis ligne;
  final ValueChanged<LigneDevis> onChange;
  final VoidCallback onRemove;
  final bool highlightError;
  final List<String> recommendedUnits;

  const _DevisLineEditor({
    required this.ligne,
    required this.onChange,
    required this.onRemove,
    this.highlightError = false,
    this.recommendedUnits = const [],
  });

  @override
  State<_DevisLineEditor> createState() => _DevisLineEditorState();
}

class _DevisLineEditorState extends State<_DevisLineEditor> {
  late TextEditingController _desc;
  late TextEditingController _qty;
  late TextEditingController _prix;
  late DevisLineType _type;

  static const Map<DevisLineType, IconData> _typeIcons = {
    DevisLineType.fourniture: Icons.inventory_2_rounded,
    DevisLineType.mainOeuvre: Icons.engineering_rounded,
    DevisLineType.deplacement: Icons.directions_car_rounded,
    DevisLineType.autre: Icons.more_horiz_rounded,
  };

  static const List<DevisLineType> _selectableTypes = [
    DevisLineType.fourniture,
    DevisLineType.mainOeuvre,
    // Déplacement retiré des choix : compris dans la main-d'œuvre.
    DevisLineType.autre,
  ];

  String _typeLabel(DevisLineType t) {
    switch (t) {
      case DevisLineType.fourniture:
        return 'Fourniture';
      case DevisLineType.mainOeuvre:
        return 'Main-d\'œuvre';
      case DevisLineType.deplacement:
        // Ancien type (devis existants) : on l'affiche comme main-d'œuvre.
        return 'Main-d\'œuvre';
      case DevisLineType.autre:
        return 'Autre';
    }
  }

  @override
  void initState() {
    super.initState();
    _desc = TextEditingController(text: widget.ligne.description);
    _qty = TextEditingController(
        text: widget.ligne.quantite == widget.ligne.quantite.roundToDouble()
            ? widget.ligne.quantite.toStringAsFixed(0)
            : widget.ligne.quantite.toStringAsFixed(2));
    _prix = TextEditingController(
        text: widget.ligne.prixUnitaire > 0
            ? widget.ligne.prixUnitaire.toStringAsFixed(0)
            : '');
    _type = widget.ligne.typeLigne;
  }

  @override
  void dispose() {
    _desc.dispose();
    _qty.dispose();
    _prix.dispose();
    super.dispose();
  }

  void _emit() {
    // Main-d'œuvre : pas de champ description (on sait déjà ce que c'est) → on
    // met un libellé par défaut pour que le devis/reçu reste lisible.
    final desc = (_type == DevisLineType.mainOeuvre && _desc.text.trim().isEmpty)
        ? 'Main-d\'œuvre'
        : _desc.text;
    // Main-d'œuvre : quantité forcée à 1 (le prix saisi EST le total de la
    // ligne) ; sinon Qté × Prix unitaire.
    final qte = _type == DevisLineType.mainOeuvre
        ? 1.0
        : (double.tryParse(_qty.text.replaceAll(',', '.')) ?? 1);
    widget.onChange(widget.ligne.copyWith(
      typeLigne: _type,
      description: desc,
      quantite: qte,
      prixUnitaire: double.tryParse(_prix.text.replaceAll(',', '.')) ?? 0,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.ligne.total;
    final isLabour = _type == DevisLineType.mainOeuvre;
    return Container(
      decoration: BoxDecoration(
        color: widget.highlightError
            ? BabifixDesign.error.withValues(alpha: 0.04)
            : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: widget.highlightError
              ? BabifixDesign.error
              : const Color(0xFFE2E8F0),
          width: widget.highlightError ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0x040F172A),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Type badge + delete
            Row(
              children: [
                PopupMenuButton<DevisLineType>(
                  tooltip: 'Changer le type',
                  onSelected: (t) {
                    setState(() => _type = t);
                    _emit();
                  },
                  itemBuilder: (_) => [
                    for (final t in _selectableTypes)
                      PopupMenuItem<DevisLineType>(
                        value: t,
                        child: Row(
                          children: [
                            Icon(_typeIcons[t], size: 18, color: BabifixDesign.iconOnLight),
                            const SizedBox(width: 10),
                            Text(_typeLabel(t)),
                          ],
                        ),
                      ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: BabifixDesign.cyan.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: BabifixDesign.cyan.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_typeIcons[_type] ?? Icons.more_horiz, color: BabifixDesign.cyan, size: 16),
                        const SizedBox(width: 6),
                        Text(_typeLabel(_type),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: BabifixDesign.cyan)),
                        const Icon(Icons.arrow_drop_down, color: BabifixDesign.cyan, size: 18),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                Container(
                  decoration: BoxDecoration(
                    color: BabifixDesign.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    color: BabifixDesign.error,
                    onPressed: widget.onRemove,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Description — masquée pour la main-d'œuvre (on sait déjà ce que c'est).
            if (!isLabour) ...[
            TextField(
              controller: _desc,
              onChanged: (_) => _emit(),
              decoration: InputDecoration(
                hintText: _type == DevisLineType.mainOeuvre
                    ? 'Prestation (ex : Pose, réparation…)'
                    : _type == DevisLineType.fourniture
                        ? 'Fourniture (ex : Robinet, câble…)'
                        : _type == DevisLineType.deplacement
                            ? 'Déplacement (ex : Transport, livraison…)'
                            : 'Désignation',
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 12),
            ],
            // Qté × Price
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Main-d'œuvre = un SEUL prix (pas Heures × Taux) : on masque la
                // quantité et le « × ».
                if (!isLabour) ...[
                  SizedBox(
                    width: 80,
                    child: TextField(
                      controller: _qty,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      onChanged: (_) => _emit(),
                      decoration: InputDecoration(
                        labelText: 'Qté',
                        labelStyle: const TextStyle(fontSize: 12),
                        isDense: true,
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('×', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 18, fontWeight: FontWeight.w300)),
                  ),
                ],
                Expanded(
                  child: TextField(
                    controller: _prix,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: BabifixDesign.navy,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    // Saisie numérique uniquement : on bloque toute lettre/texte
                    // dans les champs de montant (chiffres + séparateur décimal).
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    onChanged: (_) => _emit(),
                    decoration: InputDecoration(
                      labelText: isLabour ? 'Prix (main-d\'œuvre)' : 'Prix unitaire',
                      labelStyle: const TextStyle(fontSize: 12),
                      suffixText: 'FCFA',
                      suffixStyle: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Subtotal
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: BabifixDesign.cyan.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('= ${fmtMoney(total)}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: BabifixDesign.cyan)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Photo widget ───────────────────────────────────────────────────────────

class _ClientPhoto extends StatelessWidget {
  const _ClientPhoto({required this.src, this.size, this.fit = BoxFit.cover});
  final String src;
  final double? size;
  final BoxFit fit;

  Widget _placeholder() => Container(
        width: size,
        height: size,
        color: Colors.grey.shade200,
        child: Icon(Icons.broken_image_outlined,
            color: Colors.grey.shade400, size: 28),
      );

  @override
  Widget build(BuildContext context) {
    final s = src.trim();
    if (s.isEmpty) return _placeholder();
    if (s.startsWith('data:image/')) {
      try {
        final bytes = base64Decode(s.split(',').last);
        return Image.memory(bytes,
            width: size, height: size, fit: fit,
            errorBuilder: (_, __, ___) => _placeholder());
      } catch (_) {
        return _placeholder();
      }
    }
    if (s.startsWith('http://') || s.startsWith('https://')) {
      return Image.network(s,
          width: size, height: size, fit: fit,
          errorBuilder: (_, __, ___) => _placeholder());
    }
    try {
      final f = File(s);
      if (f.existsSync()) {
        return Image.file(f,
            width: size, height: size, fit: fit,
            errorBuilder: (_, __, ___) => _placeholder());
      }
    } catch (_) {}
    return _placeholder();
  }
}
