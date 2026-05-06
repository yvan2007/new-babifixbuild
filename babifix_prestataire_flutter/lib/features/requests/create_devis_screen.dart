import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../shared/auth_utils.dart';

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

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _loadCommissionRate();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _diagnosticCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
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
    setState(() => _lignes.removeAt(index));
  }

  double get _sousTotal => _lignes.fold(0, (sum, l) => sum + l.total);
  double get _commission => _sousTotal * _commissionRate;
  double get _total => _sousTotal + _commission;

  Future<void> _submit() async {
    if (_diagnosticCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez entrer un diagnostic')),
      );
      return;
    }
    if (_lignes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ajoutez au moins une ligne de devis')),
      );
      return;
    }

    setState(() => _submitting = true);

    final token = await readStoredApiToken();
    if (token == null) {
      setState(() => _submitting = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Non connecté')));
      }
      return;
    }

    try {
      final uri = Uri.parse(
        '${babifixApiBaseUrl()}/api/prestataire/requests/${widget.reservationReference}/devis',
      );

      final payload = {
        'diagnostic': _diagnosticCtrl.text.trim(),
        if (_dateProposee != null)
          'date_proposee': _dateProposee!.toIso8601String().split('T')[0],
        if (_heureDebut != null) 'heure_debut': _heureDebut!.format(context),
        if (_heureFin != null) 'heure_fin': _heureFin!.format(context),
        'validite_jours': _validiteJours,
        'note_prestataire': _noteCtrl.text.trim(),
        'lignes': _lignes
            .map(
              (l) => {
                'type_ligne': l.type,
                'description': l.description,
                'quantite': l.quantite,
                'prix_unitaire': l.prixUnitaire,
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Devis envoyé avec succès!')),
          );
          widget.onDevisCreated();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Erreur: ${resp.statusCode}')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur: $e')));
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
          'Créer un devis',
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
                _buildDateTimeSection(),
                const SizedBox(height: 20),
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
              const Text(
                'Demande de devis',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _infoRow(Icons.person_outline, 'Client', client),
          if (title.isNotEmpty) _infoRow(Icons.build_outlined, 'Service', title),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 8),
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
            hint: 'Décrivez votre diagnostic et les travaux à effectuer...',
            maxLines: 4,
          ),
          const SizedBox(height: 16),
          const Text(
            'Note complémentaire',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 8),
          _PremiumTextField(
            controller: _noteCtrl,
            hint: 'Informations complémentaires pour le client...',
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
                      : 'Heure début',
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
                      colors: [BabifixDesign.cyan, Color(0xFF2563EB)],
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
                  _popupItem('MAIN_OEUVRE', 'Main d\'œuvre', Icons.engineering),
                  _popupItem('DEPLACEMENT', 'Déplacement', Icons.directions_car),
                  _popupItem('AUTRE', 'Autre', Icons.more_horiz),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
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
                    DropdownMenuItem(value: 'MAIN_OEUVRE', child: Text('Main d\'œuvre')),
                    DropdownMenuItem(value: 'DEPLACEMENT', child: Text('Déplacement')),
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
            onChanged: (v) => ligne.description = v,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _PremiumTextField(
                  hint: 'Qté',
                  keyboardType: TextInputType.number,
                  onChanged: (v) => ligne.quantite = int.tryParse(v) ?? 1,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PremiumTextField(
                  hint: 'Prix unitaire',
                  keyboardType: TextInputType.number,
                  suffix: 'FCFA',
                  onChanged: (v) => ligne.prixUnitaire = double.tryParse(v) ?? 0,
                ),
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
      title: 'Validité du devis',
      icon: Icons.timer_outlined,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Durée de validité',
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
                'Sous-total',
                style: TextStyle(fontSize: 14, color: Color(0xFF94A3B8)),
              ),
              Text(
                '${_sousTotal.toStringAsFixed(0)} FCFA',
                style: const TextStyle(fontSize: 14, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Commission (${(_commissionRate * 100).toInt()}%)',
                style: const TextStyle(fontSize: 14, color: Color(0xFF94A3B8)),
              ),
              Text(
                '${_commission.toStringAsFixed(0)} FCFA',
                style: const TextStyle(fontSize: 14, color: Color(0xFFB4C2D9)),
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
                'Total client',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              Text(
                '${_total.toStringAsFixed(0)} FCFA',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: BabifixDesign.cyan,
                ),
              ),
            ],
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
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
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
  final int maxLines;
  final TextInputType? keyboardType;
  final String? suffix;
  final ValueChanged<String>? onChanged;

  const _PremiumTextField({
    this.controller,
    this.hint,
    this.maxLines = 1,
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
  String description;
  int quantite;
  double prixUnitaire;

  _LigneDevis({
    this.type = 'FOURNITURE',
    this.description = '',
    this.quantite = 1,
    this.prixUnitaire = 0,
  });

  double get total => quantite * prixUnitaire;
}
