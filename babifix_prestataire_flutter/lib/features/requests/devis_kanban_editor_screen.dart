/// Éditeur de devis Kanban — Phase B (P1) + picker catalogue (P6) + aperçu (P7).
///
/// 4 onglets : Fourniture · Main d'œuvre · Déplacement · Autre.
/// Pour chaque ligne : description / quantité (décimale) / unité / prix unitaire / marque.
/// Bouton "Catalogue" pour insérer une ligne préremplie depuis CatalogueItem.
/// Total live en bas : sous-total → commission 18% → "Vous toucherez X".
/// Bouton "Aperçu" → modal client-like ; "Envoyer" → POST API.
import 'package:flutter/material.dart';

import '../../babifix_design_system.dart';
import '../../models/babifix_models.dart';
import '../../services/babifix_api.dart';
import '../../shared/widgets/animated_list_item.dart';
import '../../shared/widgets/babifix_phase_widgets.dart';
import '../../shared/widgets/babifix_ring_loader.dart';

class DevisKanbanEditorScreen extends StatefulWidget {
  final String reservationReference;
  final int? categoryId; // optionnel : si null, le bouton "Catalogue" est désactivé
  final String reservationTitle;

  const DevisKanbanEditorScreen({
    super.key,
    required this.reservationReference,
    this.categoryId,
    this.reservationTitle = '',
  });

  @override
  State<DevisKanbanEditorScreen> createState() =>
      _DevisKanbanEditorScreenState();
}

class _DevisKanbanEditorScreenState extends State<DevisKanbanEditorScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _diagnosticCtl = TextEditingController();
  final _noteCtl = TextEditingController();
  final _validiteCtl = TextEditingController(text: '7');
  DateTime? _dateProposee;
  TimeOfDay? _heureDebut;
  TimeOfDay? _heureFin;

  final List<LigneDevis> _lignes = [];
  List<CatalogueItem> _catalogue = [];
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _loadCatalogue();
  }

  @override
  void dispose() {
    _tabs.dispose();
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

  // ---------------------------------------------------------------------------
  // Calculs
  // ---------------------------------------------------------------------------
  double get _sousTotal => _lignes.fold<double>(0, (s, l) => s + l.total);
  int get _commissionRate => 18;
  double get _commission => _sousTotal * _commissionRate / 100;
  double get _net => _sousTotal - _commission;

  List<LigneDevis> _lignesOf(DevisLineType t) =>
      _lignes.where((l) => l.typeLigne == t).toList();

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

  Future<void> _openCatalogue(DevisLineType section) async {
    if (_catalogue.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Catalogue vide pour votre catégorie.'),
      ));
      return;
    }
    final filtered =
        _catalogue.where((c) => c.typeLigne == section).toList();
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
                    'Catalogue · ${section.label}',
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
      commissionRate: _commissionRate,
      commissionMontant: _commission,
      totalTtc: _sousTotal,
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

  Future<void> _send() async {
    if (_diagnosticCtl.text.trim().isEmpty) {
      _snack('Le diagnostic est obligatoire.');
      return;
    }
    if (_lignes.isEmpty || _sousTotal <= 0) {
      _snack('Ajoutez au moins une ligne de devis.');
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
        lignes: _lignes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: BabifixDesign.ciGreen,
          content: const Text('Devis envoyé au client.')));
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(s)));
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final sections = [
      DevisLineType.fourniture,
      DevisLineType.mainOeuvre,
      DevisLineType.deplacement,
      DevisLineType.autre,
    ];
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Rédiger un devis'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: BabifixDesign.ciBlue,
          unselectedLabelColor: Colors.grey.shade600,
          indicatorColor: BabifixDesign.ciBlue,
          tabs: [
            for (final t in sections)
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(t.label),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('${_lignesOf(t).length}',
                          style: const TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      body: Column(
        children: [
          _topInfos(),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [for (final t in sections) _sectionView(t)],
            ),
          ),
          _bottomTotals(),
        ],
      ),
      bottomNavigationBar: _actions(),
    );
  }

  Widget _topInfos() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _diagnosticCtl,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Diagnostic *',
              hintText: 'Analyse du problème observé',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _pickerTile(
                  icon: Icons.event,
                  label: _dateProposee == null
                      ? 'Date proposée'
                      : '${_dateProposee!.day}/${_dateProposee!.month}/${_dateProposee!.year}',
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      firstDate: DateTime.now(),
                      lastDate:
                          DateTime.now().add(const Duration(days: 365)),
                      initialDate: DateTime.now(),
                    );
                    if (d != null) setState(() => _dateProposee = d);
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _pickerTile(
                  icon: Icons.schedule,
                  label: _heureDebut == null
                      ? 'Début'
                      : _heureDebut!.format(context),
                  onTap: () async {
                    final t = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now());
                    if (t != null) setState(() => _heureDebut = t);
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _pickerTile(
                  icon: Icons.schedule_outlined,
                  label: _heureFin == null
                      ? 'Fin'
                      : _heureFin!.format(context),
                  onTap: () async {
                    final t = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now());
                    if (t != null) setState(() => _heureFin = t);
                  },
                ),
              ),
            ],
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
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.grey.shade700),
            const SizedBox(width: 6),
            Expanded(
              child: Text(label,
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionView(DevisLineType section) {
    final lignes = _lignesOf(section);
    return Column(
      children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _openCatalogue(section),
                  icon: const Icon(Icons.library_books, size: 18),
                  label: const Text('Catalogue'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple.shade50,
                      foregroundColor: Colors.deepPurple),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _addEmptyLine(section),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Ligne libre'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: lignes.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inbox_outlined,
                            size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 8),
                        Text(
                          'Aucune ligne ${section.label.toLowerCase()} pour l\'instant.',
                          style: TextStyle(color: Colors.grey.shade600),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(14),
                  itemCount: lignes.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final l = lignes[i];
                    return AnimatedListItem(
                      index: i,
                      child: _DevisLineEditor(
                        ligne: l,
                        onChange: (nl) {
                          setState(() {
                            final idx = _lignes.indexOf(l);
                            if (idx >= 0) _lignes[idx] = nl;
                          });
                        },
                        onRemove: () => _removeLine(l),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _bottomTotals() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      color: Colors.white,
      // AnimatedSize → grow/shrink fluide quand on ajoute/retire des
      // lignes, AnimatedSwitcher → fade entre les valeurs.
      child: AnimatedSize(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim, child: child,
          ),
          child: KeyedSubtree(
            // une clé qui change quand le sous-total change → trigger fade
            key: ValueKey('${_sousTotal.toStringAsFixed(0)}_$_commissionRate'),
            child: MoneyBreakdownWidget(
              sousTotal: _sousTotal,
              commissionRate: _commissionRate,
              commissionMontant: _commission,
              totalTtc: _sousTotal,
              netPrestataire: _net,
              compact: true,
              showProviderNet: true,
            ),
          ),
        ),
      ),
    );
  }

  Widget _actions() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _sending ? null : _openPreview,
                icon: const Icon(Icons.visibility, size: 18),
                label: const Text('Aperçu'),
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: BabifixRingLoader.cyan(size: 28))
                    : const Icon(Icons.send, size: 18),
                label: const Text('Envoyer au client'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: BabifixDesign.ciBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Composant : éditeur d'une ligne
// ---------------------------------------------------------------------------
class _DevisLineEditor extends StatefulWidget {
  final LigneDevis ligne;
  final ValueChanged<LigneDevis> onChange;
  final VoidCallback onRemove;

  const _DevisLineEditor({
    required this.ligne,
    required this.onChange,
    required this.onRemove,
  });

  @override
  State<_DevisLineEditor> createState() => _DevisLineEditorState();
}

class _DevisLineEditorState extends State<_DevisLineEditor> {
  late TextEditingController _desc;
  late TextEditingController _qty;
  late TextEditingController _prix;
  late TextEditingController _marque;
  late String _unite;

  static const _unitChoices = [
    'u', 'm', 'm²', 'm³', 'ml', 'kg', 'h', 'jour', 'forfait',
  ];

  @override
  void initState() {
    super.initState();
    _desc = TextEditingController(text: widget.ligne.description);
    _qty = TextEditingController(
        text: widget.ligne.quantite == widget.ligne.quantite.roundToDouble()
            ? widget.ligne.quantite.toStringAsFixed(0)
            : widget.ligne.quantite.toStringAsFixed(2));
    _prix = TextEditingController(
        text: widget.ligne.prixUnitaire.toStringAsFixed(0));
    _marque = TextEditingController(text: widget.ligne.marque);
    _unite = widget.ligne.unite.isEmpty ? 'u' : widget.ligne.unite;
  }

  void _emit() {
    widget.onChange(widget.ligne.copyWith(
      description: _desc.text,
      quantite: double.tryParse(_qty.text.replaceAll(',', '.')) ?? 1,
      prixUnitaire: double.tryParse(_prix.text.replaceAll(',', '.')) ?? 0,
      unite: _unite,
      marque: _marque.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.ligne.total;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _desc,
                  onChanged: (_) => _emit(),
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                icon:
                    Icon(Icons.delete_outline, color: BabifixDesign.error),
                onPressed: widget.onRemove,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 70,
                child: TextField(
                  controller: _qty,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  onChanged: (_) => _emit(),
                  decoration: const InputDecoration(
                    labelText: 'Qté',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 90,
                child: DropdownButtonFormField<String>(
                  initialValue:
                      _unitChoices.contains(_unite) ? _unite : 'u',
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Unité',
                    isDense: true,
                  ),
                  items: _unitChoices
                      .map((u) => DropdownMenuItem(
                            value: u,
                            child: Text(u),
                          ))
                      .toList(),
                  onChanged: (v) {
                    setState(() => _unite = v ?? 'u');
                    _emit();
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _prix,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => _emit(),
                  decoration: const InputDecoration(
                    labelText: 'PU FCFA',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _marque,
                  onChanged: (_) => _emit(),
                  decoration: const InputDecoration(
                    labelText: 'Marque / référence (opt.)',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                fmtMoney(total),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: BabifixDesign.ciBlue,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
