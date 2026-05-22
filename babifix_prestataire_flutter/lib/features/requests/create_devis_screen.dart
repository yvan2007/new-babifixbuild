import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../shared/auth_utils.dart';
import '../../shared/widgets/babifix_ring_loader.dart';
import '../../shared/widgets/babifix_snackbar.dart';

class CreateDevisScreen extends StatefulWidget {
  final String reservationReference;
  final Map<String, dynamic> reservationDetails;
  final VoidCallback onBack;
  final VoidCallback onDevisCreated;

  const CreateDevisScreen({
    super.key,
    required this.reservationReference,
    required this.reservationDetails,
    required this.onBack,
    required this.onDevisCreated,
  });

  @override
  State<CreateDevisScreen> createState() => _CreateDevisScreenState();
}

class _CreateDevisScreenState extends State<CreateDevisScreen>
    with SingleTickerProviderStateMixin {
  final _diagnosticCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  DateTime? _dateProposee;
  TimeOfDay? _heureDebut;
  TimeOfDay? _heureFin;
  int _validiteJours = 7;
  bool _submitting = false;
  late AnimationController _animCtrl;

  final List<_LigneDevis> _lignes = [];
  double _commissionRate = 0.18;
  bool get _isUrgent => widget.reservationDetails['is_urgent'] == true;

  // Catalogue de fournitures spécifique à la catégorie du prestataire.
  int? _categoryId;
  String _categoryNom = '';
  List<Map<String, dynamic>> _catalogue = [];

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _loadCommissionRate();
    _loadCatalogue();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _diagnosticCtrl.dispose();
    _noteCtrl.dispose();
    for (final l in _lignes) {
      l.dispose();
    }
    super.dispose();
  }

  /// Récupère la catégorie du prestataire puis son catalogue de fournitures
  /// (matériaux + main d'œuvre + déplacement) propre à son métier.
  Future<void> _loadCatalogue() async {
    final token = await readStoredApiToken();
    if (token == null) return;
    try {
      // 1) Catégorie du prestataire
      int? catId = _categoryId;
      final me = await http.get(
        Uri.parse('${babifixApiBaseUrl()}/api/prestataire/me'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (me.statusCode == 200) {
        final data = jsonDecode(me.body) as Map<String, dynamic>;
        final prov = data['provider'] as Map<String, dynamic>?;
        if (prov != null) {
          catId = (prov['category_id'] as num?)?.toInt();
          _categoryNom = (prov['category_nom'] ?? '').toString();
        }
      }
      if (catId == null) return;
      // 2) Catalogue de la catégorie
      final cat = await http.get(
        Uri.parse('${babifixApiBaseUrl()}/api/categories/$catId/catalogue'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (cat.statusCode == 200) {
        final data = jsonDecode(cat.body) as Map<String, dynamic>;
        final items = (data['items'] as List?) ?? [];
        if (mounted) {
          setState(() {
            _categoryId = catId;
            _catalogue =
                items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          });
        }
      }
    } catch (_) {
      // silencieux : la saisie manuelle reste toujours possible
    }
  }

  void _addCatalogueLigne(Map<String, dynamic> item) {
    final marque = (item['marque'] ?? '').toString();
    final nom = (item['nom'] ?? '').toString();
    setState(() {
      _lignes.add(_LigneDevis(
        type: (item['type_ligne'] ?? 'FOURNITURE').toString(),
        description: marque.isNotEmpty ? '$nom ($marque)' : nom,
        quantite: 1,
        prixUnitaire:
            (item['prix_unitaire_indicatif'] as num?)?.toDouble() ?? 0,
        unite: (item['unite'] ?? '').toString(),
        marque: marque,
        catalogueItemId: (item['id'] as num?)?.toInt(),
      ));
    });
  }

  Future<void> _loadCommissionRate() async {
    final token = await readStoredApiToken();
    if (token == null) return;
    try {
      final res = await http.get(
        Uri.parse('${babifixApiBaseUrl()}/api/prestataire/wallet/'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final rate = (data['commission_rate'] as num?)?.toDouble();
        if (rate != null && rate > 0) {
          setState(() => _commissionRate = rate / 100);
        }
      }
    } catch (_) {}
  }

  void _addLigne(String type) {
    setState(() => _lignes.add(_LigneDevis(type: type)));
  }

  void _removeLigne(int index) {
    setState(() {
      _lignes[index].dispose();
      _lignes.removeAt(index);
    });
  }

  double get _sousTotal => _lignes.fold(0, (sum, l) => sum + l.total);
  double get _commission => _sousTotal * _commissionRate;
  // Règle BABIFIX : le client paie le sous-total ; la commission est DÉDUITE
  // du prestataire (jamais ajoutée au client). Net presta = sous-total − comm.
  double get _netPrestataire => _sousTotal - _commission;

  Future<void> _submit() async {
    if (_diagnosticCtrl.text.trim().isEmpty) {
      showBabifixToast(
        context,
        type: BabifixToastType.warning,
        message: 'Veuillez entrer un diagnostic',
      );
      return;
    }
    if (_lignes.isEmpty) {
      showBabifixToast(
        context,
        type: BabifixToastType.warning,
        message: 'Ajoutez au moins une ligne de devis',
      );
      return;
    }
    if (!_isUrgent && _dateProposee == null) {
      showBabifixToast(
        context,
        type: BabifixToastType.warning,
        message: 'Veuillez choisir une date pour l\'intervention',
      );
      return;
    }

    setState(() => _submitting = true);

    final token = await readStoredApiToken();
    if (token == null) {
      setState(() => _submitting = false);
      if (mounted) {
        showBabifixToast(
        context,
        type: BabifixToastType.info,
        message: 'Non connecte',
      );
      }
      return;
    }

    try {
      final uri = Uri.parse(
        '${babifixApiBaseUrl()}/api/prestataire/requests/${widget.reservationReference}/devis',
      );

      final payload = {
        'diagnostic': _diagnosticCtrl.text.trim(),
        'is_urgent': _isUrgent,
        if (!_isUrgent && _dateProposee != null)
          'date_proposee': _dateProposee!.toIso8601String().split('T')[0],
        if (!_isUrgent && _heureDebut != null) 'heure_debut': _heureDebut!.format(context),
        if (!_isUrgent && _heureFin != null) 'heure_fin': _heureFin!.format(context),
        'validite_jours': _validiteJours,
        'note_prestataire': _noteCtrl.text.trim(),
        'lignes': _lignes
            .map(
              (l) => {
                'type_ligne': l.type,
                'description': l.description,
                'quantite': l.quantite,
                'prix_unitaire': l.prixUnitaire,
                if (l.uniteCtrl.text.trim().isNotEmpty)
                  'unite': l.uniteCtrl.text.trim(),
                if (l.marque.isNotEmpty) 'marque': l.marque,
                if (l.catalogueItemId != null)
                  'catalogue_item_id': l.catalogueItemId,
              },
            )
            .toList(),
      };

      final resp = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );

      if (resp.statusCode == 200) {
        if (mounted) {
          showBabifixToast(
        context,
        type: BabifixToastType.success,
        message: 'Devis envoye avec succes!',
      );
          widget.onDevisCreated();
        }
      } else if (resp.statusCode == 403) {
        // Quota d'abonnement atteint : message clair + invite upgrade
        String message = 'Erreur 403';
        try {
          final d = jsonDecode(resp.body) as Map<String, dynamic>;
          if (d['error'] == 'active_devis_quota_reached') {
            message = (d['message'] as String?) ??
                'Limite de devis actifs atteinte pour votre abonnement.';
          }
        } catch (_) {}
        if (mounted) {
          showBabifixToast(
        context,
        type: BabifixToastType.info,
        message: message,
        duration: const Duration(seconds: 5),
      );
        }
      } else {
        if (mounted) {
          showBabifixToast(
        context,
        type: BabifixToastType.error,
        message: 'Erreur: ${resp.statusCode}',
      );
        }
      }
    } catch (e) {
      if (mounted) {
        showBabifixToast(
        context,
        type: BabifixToastType.error,
        message: 'Erreur: $e',
      );
      }
    }

    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BabifixDesign.navy,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: widget.onBack,
        ),
        title: const Text(
          'Creer un devis',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
      ),
      body: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.05),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut)),
        child: FadeTransition(
          opacity: _animCtrl,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildReservationInfo(),
                const SizedBox(height: 20),
                _buildDiagnosticSection(),
                const SizedBox(height: 20),
                if (!_isUrgent) _buildDateTimeSection(),
                if (!_isUrgent) const SizedBox(height: 20),
                _buildLignesSection(),
                const SizedBox(height: 20),
                _buildValiditeSection(),
                const SizedBox(height: 28),
                _buildTotalSection(),
                const SizedBox(height: 28),
                _buildSubmitButton(),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReservationInfo() {
    final client = widget.reservationDetails['client'] ?? 'Client';
    final title = widget.reservationDetails['title'] ?? '';
    final description = widget.reservationDetails['description_probleme'] ?? '';
    final address = widget.reservationDetails['address'] ?? '';
    final paymentType = widget.reservationDetails['payment_type'] ?? '';
    final mmOperator = widget.reservationDetails['mobile_money_operator'] ?? '';
    final disponibilites = widget.reservationDetails['disponibilites'] ?? '';
    final isUrgent = widget.reservationDetails['is_urgent'] == true;
    final prixPropose = widget.reservationDetails['prix_propose'] as double?;
    final date = widget.reservationDetails['date'] ?? '';
    final hour = widget.reservationDetails['hour'] ?? '';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF152A45), Color(0xFF1A3355)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: BabifixDesign.cyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.assignment_outlined,
                  color: BabifixDesign.cyan,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Demande de $client',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isUrgent)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.flash_on_rounded, size: 12, color: Color(0xFFEF4444)),
                      SizedBox(width: 3),
                      Text(
                        'URGENT',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFEF4444),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _infoRow(Icons.person_outline, 'Client', client),
          if (title.isNotEmpty) _infoRow(Icons.build_outlined, 'Service', title),
          if (address.isNotEmpty) _infoRow(Icons.location_on_outlined, 'Adresse', address),
          if (date.isNotEmpty || hour.isNotEmpty)
            _infoRow(Icons.calendar_today_outlined, 'Date/Heure', '$date $hour'.trim()),
          if (disponibilites.isNotEmpty) _infoRow(Icons.schedule_outlined, 'Dispo', disponibilites),
          if (paymentType.isNotEmpty)
            _infoRow(
              Icons.payment_outlined,
              'Paiement',
              mmOperator.isNotEmpty ? '$paymentType ($mmOperator)' : paymentType,
            ),
          if (prixPropose != null && prixPropose > 0) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.monetization_on_outlined, size: 18, color: Color(0xFFF59E0B)),
                  const SizedBox(width: 8),
                  const Text(
                    'Budget proposé :',
                    style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${prixPropose.toStringAsFixed(0)} FCFA',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFF59E0B),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (description.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Description du problème',
              style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0x11FFFFFF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                description,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFFB4C2D9),
                  height: 1.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF94A3B8)),
          const SizedBox(width: 8),
          Text(
            '$label : ',
            style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosticSection() {
    return _SectionCard(
      title: 'Diagnostic',
      icon: Icons.medical_services_outlined,
      child: Column(
        children: [
          _PremiumTextField(
            controller: _diagnosticCtrl,
            hint: 'Decrivez votre diagnostic et les travaux a effectuer...',
            maxLines: 4,
          ),
          const SizedBox(height: 16),
          const Text(
            'Note complementaire',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 8),
          _PremiumTextField(
            controller: _noteCtrl,
            hint: 'Informations complementaires pour le client...',
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildDateTimeSection() {
    return _SectionCard(
      title: 'Date et heure',
      icon: Icons.calendar_today_outlined,
      child: Column(
        children: [
          _DateButton(
            icon: Icons.calendar_today,
            label: _dateProposee != null
                ? '${_dateProposee!.day}/${_dateProposee!.month}/${_dateProposee!.year}'
                : 'Choisir une date',
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: DateTime.now().add(const Duration(days: 1)),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 90)),
                builder: (context, child) {
                  return Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: const ColorScheme.dark(
                        primary: BabifixDesign.cyan,
                        onPrimary: Colors.white,
                        surface: Color(0xFF152A45),
                        onSurface: Colors.white,
                      ),
                    ),
                    child: child!,
                  );
                },
              );
              if (d != null) setState(() => _dateProposee = d);
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _DateButton(
                  icon: Icons.schedule,
                  label: _heureDebut != null
                      ? _heureDebut!.format(context)
                      : 'Heure debut',
                  onTap: () async {
                    final t = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.now(),
                      builder: (context, child) {
                        return Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: const ColorScheme.dark(
                              primary: BabifixDesign.cyan,
                              onPrimary: Colors.white,
                              surface: Color(0xFF152A45),
                              onSurface: Colors.white,
                            ),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (t != null) setState(() => _heureDebut = t);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DateButton(
                  icon: Icons.schedule,
                  label: _heureFin != null
                      ? _heureFin!.format(context)
                      : 'Heure fin',
                  onTap: () async {
                    final t = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.now(),
                      builder: (context, child) {
                        return Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: const ColorScheme.dark(
                              primary: BabifixDesign.cyan,
                              onPrimary: Colors.white,
                              surface: Color(0xFF152A45),
                              onSurface: Colors.white,
                            ),
                          ),
                          child: child!,
                        );
                      },
                    );
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

  Widget _buildLignesSection() {
    return _SectionCard(
      title: 'Lignes de devis',
      icon: Icons.format_list_bulleted,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_lignes.length} ligne${_lignes.length > 1 ? 's' : ''}',
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF94A3B8),
                ),
              ),
              PopupMenuButton<String>(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [BabifixDesign.cyan, Color(0xFF4CC9F0)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 18, color: Colors.white),
                      SizedBox(width: 4),
                      Text(
                        'Ajouter',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                color: const Color(0xFF152A45),
                onSelected: _addLigne,
                itemBuilder: (_) => [
                  _popupItem('FOURNITURE', 'Fourniture', Icons.inventory_2),
                  _popupItem('MAIN_OEUVRE', 'Main d\'oeuvre', Icons.engineering),
                  _popupItem('DEPLACEMENT', 'Deplacement', Icons.directions_car),
                  _popupItem('AUTRE', 'Autre', Icons.more_horiz),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_catalogue.isNotEmpty) ...[
            _buildCatalogueButton(),
            const SizedBox(height: 12),
          ],
          if (_lignes.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: const Column(
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 40,
                    color: Color(0xFF4B5563),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Ajoutez des lignes pour composer votre devis',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                  ),
                ],
              ),
            )
          else
            ..._lignes.asMap().entries.map(
                  (e) => _buildLigneItem(e.key, e.value),
                ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _popupItem(String value, String label, IconData icon) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18, color: BabifixDesign.cyan),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }

  Widget _buildCatalogueButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openCataloguePicker,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: BabifixDesign.cyan.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: BabifixDesign.cyan.withValues(alpha: 0.40)),
          ),
          child: Row(
            children: [
              const Icon(Icons.inventory_2_outlined,
                  color: BabifixDesign.cyan, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Catalogue ${_categoryNom.isNotEmpty ? _categoryNom : "métier"}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    Text(
                      '${_catalogue.length} fournitures & prestations types',
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: BabifixDesign.cyan),
            ],
          ),
        ),
      ),
    );
  }

  void _openCataloguePicker() {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final it in _catalogue) {
      final t = (it['type_ligne'] ?? 'AUTRE').toString();
      groups.putIfAbsent(t, () => []).add(it);
    }
    const labels = {
      'FOURNITURE': 'Fournitures',
      'MAIN_OEUVRE': "Main d'œuvre",
      'DEPLACEMENT': 'Déplacement',
      'AUTRE': 'Autre',
    };
    const order = ['FOURNITURE', 'MAIN_OEUVRE', 'DEPLACEMENT', 'AUTRE'];
    final orderedKeys = [
      ...order.where(groups.containsKey),
      ...groups.keys.where((k) => !order.contains(k)),
    ];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0B1B34),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        maxChildSize: 0.92,
        minChildSize: 0.4,
        builder: (_, scrollCtrl) => Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF334155),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2_outlined,
                      color: BabifixDesign.cyan, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Catalogue ${_categoryNom.isNotEmpty ? _categoryNom : "métier"}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(sheetCtx).pop(),
                    icon: const Icon(Icons.close, color: Color(0xFF94A3B8)),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 0, 18, 8),
              child: Text(
                'Touchez un élément pour l\'ajouter au devis (vous pourrez ajuster quantité et prix).',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                children: [
                  for (final key in orderedKeys) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                      child: Text(
                        (labels[key] ?? key).toUpperCase(),
                        style: const TextStyle(
                          color: BabifixDesign.cyan,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    ...groups[key]!.map((it) => _catalogueTile(sheetCtx, it)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _catalogueTile(BuildContext sheetCtx, Map<String, dynamic> it) {
    final nom = (it['nom'] ?? '').toString();
    final marque = (it['marque'] ?? '').toString();
    final unite = (it['unite'] ?? '').toString();
    final prix = (it['prix_unitaire_indicatif'] as num?)?.toDouble() ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: const Color(0xFF0F1D32),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            _addCatalogueLigne(it);
            Navigator.of(sheetCtx).pop();
            showBabifixToast(
              context,
              type: BabifixToastType.success,
              message: 'Ajouté : $nom',
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nom,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                        ),
                      ),
                      if (marque.isNotEmpty || unite.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            [
                              if (marque.isNotEmpty) marque,
                              if (unite.isNotEmpty) 'unité : $unite',
                            ].join('  •  '),
                            style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${prix.toStringAsFixed(0)} F',
                      style: const TextStyle(
                        color: BabifixDesign.cyan,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'indicatif',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 10),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                const Icon(Icons.add_circle, color: BabifixDesign.cyan, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLigneItem(int index, _LigneDevis ligne) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1D32),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: ligne.type,
                  decoration: const InputDecoration(
                    labelText: 'Type',
                    labelStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                    filled: true,
                    fillColor: Color(0xFF152A45),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    isDense: true,
                  ),
                  dropdownColor: const Color(0xFF152A45),
                  items: const [
                    DropdownMenuItem(value: 'FOURNITURE', child: Text('Fourniture')),
                    DropdownMenuItem(value: 'MAIN_OEUVRE', child: Text('Main d\'oeuvre')),
                    DropdownMenuItem(value: 'DEPLACEMENT', child: Text('Deplacement')),
                    DropdownMenuItem(value: 'AUTRE', child: Text('Autre')),
                  ],
                  onChanged: (v) => setState(() => ligne.type = v!),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _removeLigne(index),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: BabifixDesign.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.delete_outline,
                    color: BabifixDesign.error,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _PremiumTextField(
            hint: 'Description',
            controller: ligne.descCtrl,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          if (ligne.type == 'MAIN_OEUVRE')
            Row(
              children: [
                Expanded(
                  child: _PremiumTextField(
                    hint: 'Nb heures',
                    controller: ligne.qteCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _PremiumTextField(
                    hint: 'Taux horaire',
                    controller: ligne.prixCtrl,
                    keyboardType: TextInputType.number,
                    suffix: 'FCFA',
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            )
          else if (ligne.type == 'DEPLACEMENT')
            _PremiumTextField(
              hint: 'Frais de déplacement',
              controller: ligne.prixCtrl,
              keyboardType: TextInputType.number,
              suffix: 'FCFA',
              onChanged: (_) => setState(() {}),
            )
          else
            Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _PremiumTextField(
                        hint: 'Qté',
                        controller: ligne.qteCtrl,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: _PremiumTextField(
                        hint: 'Unité (u, m², kg…)',
                        controller: ligne.uniteCtrl,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _PremiumTextField(
                  hint: 'Prix unitaire',
                  controller: ligne.prixCtrl,
                  keyboardType: TextInputType.number,
                  suffix: 'FCFA',
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
            decoration: BoxDecoration(
              color: BabifixDesign.cyan.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Sous-total',
                  style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                ),
                Text(
                  '${ligne.total.toStringAsFixed(0)} FCFA',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: BabifixDesign.cyan,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValiditeSection() {
    return _SectionCard(
      title: 'Validite du devis',
      icon: Icons.timer_outlined,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Duree de validite',
            style: TextStyle(fontSize: 14, color: Color(0xFFB4C2D9)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF152A45),
              borderRadius: BorderRadius.circular(10),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _validiteJours,
                dropdownColor: const Color(0xFF152A45),
                items: [3, 5, 7, 10, 14, 30]
                    .map(
                      (v) => DropdownMenuItem(
                        value: v,
                        child: Text(
                          '$v jours',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _validiteJours = v!),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0A1628), Color(0xFF152A45)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x22FFFFFF)),
        boxShadow: BabifixDesign.cyanGlowShadow(opacity: 0.1),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total facturé au client',
                style: TextStyle(fontSize: 14, color: Color(0xFF94A3B8)),
              ),
              Text(
                '${_sousTotal.toStringAsFixed(0)} FCFA',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Commission BABIFIX (${(_commissionRate * 100).toInt()}%)',
                style: const TextStyle(fontSize: 14, color: Color(0xFF94A3B8)),
              ),
              Text(
                '− ${_commission.toStringAsFixed(0)} FCFA',
                style: const TextStyle(fontSize: 14, color: Color(0xFFF59E0B)),
              ),
            ],
          ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 14),
            height: 1,
            color: const Color(0x22FFFFFF),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Vous recevez (net)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              Text(
                '${_netPrestataire.toStringAsFixed(0)} FCFA',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: BabifixDesign.cyan,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Le client paie le total facturé. La commission BABIFIX est déduite de votre part.',
              style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: FilledButton(
        onPressed: _submitting ? null : _submit,
        style: FilledButton.styleFrom(
          backgroundColor: BabifixDesign.ciOrange,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: _submitting
            ? const SizedBox(
                width: 22,
                height: 22,
                child: BabifixRingLoader.cyan(size: 28),
              )
            : const Text(
                'Envoyer le devis',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF152A45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: BabifixDesign.cyan.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: BabifixDesign.cyan),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _PremiumTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? hint;
  final int? maxLines;
  final TextInputType? keyboardType;
  final String? suffix;
  final ValueChanged<String>? onChanged;

  const _PremiumTextField({
    this.controller,
    this.hint,
    this.maxLines,
    this.keyboardType,
    this.suffix,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
        filled: true,
        fillColor: const Color(0xFF0F1D32),
        suffixText: suffix,
        suffixStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _DateButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F1D32),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x1AFFFFFF)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: BabifixDesign.cyan),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: label.contains('Choisir') || label.contains('Heure')
                        ? const Color(0xFF64748B)
                        : Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LigneDevis {
  String type;
  String unite;
  String marque;
  int? catalogueItemId;
  final TextEditingController descCtrl;
  final TextEditingController qteCtrl;
  final TextEditingController prixCtrl;
  final TextEditingController uniteCtrl;

  _LigneDevis({
    this.type = 'FOURNITURE',
    String description = '',
    double quantite = 1,
    double prixUnitaire = 0,
    this.unite = '',
    this.marque = '',
    this.catalogueItemId,
  })  : descCtrl = TextEditingController(text: description),
        qteCtrl =
            TextEditingController(text: quantite > 0 ? _fmtNum(quantite) : ''),
        prixCtrl = TextEditingController(
            text: prixUnitaire > 0 ? prixUnitaire.toStringAsFixed(0) : ''),
        uniteCtrl = TextEditingController(text: unite);

  static String _fmtNum(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  String get description => descCtrl.text.trim();
  double get quantite =>
      double.tryParse(qteCtrl.text.trim().replaceAll(',', '.')) ?? 1;
  double get prixUnitaire =>
      double.tryParse(prixCtrl.text.trim().replaceAll(',', '.')) ?? 0;
  double get total => quantite * prixUnitaire;

  void dispose() {
    descCtrl.dispose();
    qteCtrl.dispose();
    prixCtrl.dispose();
    uniteCtrl.dispose();
  }
}
