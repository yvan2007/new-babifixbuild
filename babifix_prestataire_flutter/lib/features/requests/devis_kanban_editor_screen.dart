import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../babifix_design_system.dart';
import '../../models/babifix_models.dart';
import '../../services/babifix_api.dart';
import '../../shared/widgets/babifix_phase_widgets.dart';
import '../../shared/widgets/babifix_ring_loader.dart';
import '../../shared/widgets/babifix_snackbar.dart';

class DevisKanbanEditorScreen extends StatefulWidget {
  final String reservationReference;
  final int? categoryId;
  final String reservationTitle;
  final String clientName;
  final String clientProblem;
  final List<String> clientPhotos;

  const DevisKanbanEditorScreen({
    super.key,
    required this.reservationReference,
    this.categoryId,
    this.reservationTitle = '',
    this.clientName = '',
    this.clientProblem = '',
    this.clientPhotos = const [],
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
  bool _sending = false;
  final List<String> _diagPhotos = [];
  final ImagePicker _picker = ImagePicker();
  bool _attemptedSend = false;
  double _remise = 0;

  double get _sousTotal => _lignes.fold<double>(0, (s, l) => s + l.total);
  double get _baseTotal {
    final b = _sousTotal - _remise;
    return b < 0 ? 0 : b;
  }

  int get _commissionRate => 18;
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
      _snack(e.message);
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

  void _addEmptyLine(DevisLineType t) {
    setState(() {
      _lignes.add(LigneDevis(
        typeLigne: t,
        description: '',
        quantite: 1,
        prixUnitaire: 0,
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
    final picked = await showModalBottomSheet<CatalogueItem>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(24))),
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
    return Scaffold(
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
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Nouveau devis',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                Text('Établir un devis professionnel',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w400)),
              ],
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
                const SizedBox(height: 14),
                _topInfosCard(),
                const SizedBox(height: 14),
                _diagPhotosCard(),
                const SizedBox(height: 14),
                _lignesCard(),
                const SizedBox(height: 14),
                _escrowNote(),
                const SizedBox(height: 100),
              ],
            ),
          ),
          _bottomBar(),
        ],
      ),
    );
  }

  // ─── Client Request Card ─────────────────────────────────────────────────

  Widget _clientRequestCard() {
    final hasProblem = widget.clientProblem.trim().isNotEmpty;
    final hasPhotos = widget.clientPhotos.isNotEmpty;
    final hasName = widget.clientName.trim().isNotEmpty;
    if (!hasProblem && !hasPhotos && !hasName) return const SizedBox.shrink();

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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: BabifixDesign.navy,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(widget.reservationTitle,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white)),
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
                child: const Icon(Icons.biotech_rounded, size: 18, color: BabifixDesign.navy),
              ),
              const SizedBox(width: 10),
              const Text('Diagnostic & planification',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: BabifixDesign.navy)),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _diagnosticCtl,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Diagnostic *',
              hintText: 'Analyse du problème observé sur place',
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
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _pickerTile(
                  icon: Icons.event_rounded,
                  label: _dateProposee == null
                      ? 'Date proposée'
                      : '${_dateProposee!.day}/${_dateProposee!.month}/${_dateProposee!.year}',
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      initialDate: DateTime.now(),
                    );
                    if (d != null) setState(() => _dateProposee = d);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _pickerTile(
                  icon: Icons.schedule_rounded,
                  label: _heureDebut == null ? 'Début' : _heureDebut!.format(context),
                  onTap: () async {
                    final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                    if (t != null) setState(() => _heureDebut = t);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _pickerTile(
                  icon: Icons.schedule_outlined,
                  label: _heureFin == null ? 'Fin' : _heureFin!.format(context),
                  onTap: () async {
                    final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                    if (t != null) setState(() => _heureFin = t);
                  },
                ),
              ),
            ],
          ),
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

  Widget _pickerTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: BabifixDesign.iconOnLight),
            const SizedBox(width: 6),
            Expanded(
              child: Text(label,
                  style: const TextStyle(fontSize: 12, color: BabifixDesign.navy, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
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
                  Text('Fournitures, main-d\'œuvre, déplacement…',
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
              _addTypeChip(DevisLineType.fourniture, 'Fourniture', Icons.inventory_2_rounded),
              _addTypeChip(DevisLineType.mainOeuvre, 'Main-d\'œuvre', Icons.engineering_rounded),
              _addTypeChip(DevisLineType.deplacement, 'Déplacement', Icons.directions_car_rounded),
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

  // ─── Escrow Security Note ────────────────────────────────────────────────

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
                  'Après acceptation, le client verse un acompte bloqué en séquestre. '
                  'Tu es payé automatiquement à la fin de la mission — pas de risque d\'impayé.',
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
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
                    foregroundColor: BabifixDesign.navy,
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: BabifixRingLoader.cyan(size: 28))
                      : const Icon(Icons.send_rounded, size: 18),
                  label: const Text('Envoyer au client'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: BabifixDesign.navy,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: BabifixDesign.navy.withValues(alpha: 0.5),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Line Editor ────────────────────────────────────────────────────────────

class _DevisLineEditor extends StatefulWidget {
  final LigneDevis ligne;
  final ValueChanged<LigneDevis> onChange;
  final VoidCallback onRemove;
  final bool highlightError;

  const _DevisLineEditor({
    required this.ligne,
    required this.onChange,
    required this.onRemove,
    this.highlightError = false,
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
    DevisLineType.deplacement,
    DevisLineType.autre,
  ];

  String _typeLabel(DevisLineType t) {
    switch (t) {
      case DevisLineType.fourniture:
        return 'Fourniture';
      case DevisLineType.mainOeuvre:
        return 'Main-d\'œuvre & déplacement';
      case DevisLineType.deplacement:
        return 'Déplacement';
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
    widget.onChange(widget.ligne.copyWith(
      typeLigne: _type,
      description: _desc.text,
      quantite: double.tryParse(_qty.text.replaceAll(',', '.')) ?? 1,
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
            // Description
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
            // Qté × Price
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _qty,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => _emit(),
                    decoration: InputDecoration(
                      labelText: isLabour ? 'Heures' : 'Qté',
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
                Expanded(
                  child: TextField(
                    controller: _prix,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => _emit(),
                    decoration: InputDecoration(
                      labelText: isLabour ? 'Taux horaire' : 'Prix unitaire',
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
