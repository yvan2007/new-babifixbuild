import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../babifix_api_config.dart';
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

class _CreateDevisScreenState extends State<CreateDevisScreen> {
  final _diagnosticCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  DateTime? _dateProposee;
  TimeOfDay? _heureDebut;
  TimeOfDay? _heureFin;
  int _validiteJours = 7;
  bool _submitting = false;

  final List<_LigneDevis> _lignes = [];

  @override
  void dispose() {
    _diagnosticCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _addLigne(String type) {
    setState(() {
      _lignes.add(_LigneDevis(type: type));
    });
  }

  void _removeLigne(int index) {
    setState(() {
      _lignes.removeAt(index);
    });
  }

  double get _sousTotal => _lignes.fold(0, (sum, l) => sum + l.total);

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
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
        title: const Text('Créer un devis'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildReservationInfo(),
            const SizedBox(height: 16),
            _buildDiagnosticSection(),
            const SizedBox(height: 16),
            _buildDateTimeSection(),
            const SizedBox(height: 16),
            _buildLignesSection(),
            const SizedBox(height: 16),
            _buildValiditeSection(),
            const SizedBox(height: 24),
            _buildTotalSection(),
            const SizedBox(height: 24),
            _buildSubmitButton(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildReservationInfo() {
    final client = widget.reservationDetails['client'] ?? 'Client';
    final title = widget.reservationDetails['title'] ?? '';
    final description = widget.reservationDetails['description_probleme'] ?? '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Demande de devis',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text('Client: $client', style: const TextStyle(fontSize: 14)),
            if (title.isNotEmpty)
              Text('Service: $title', style: const TextStyle(fontSize: 14)),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Problème: $description',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosticSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Diagnostic',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _diagnosticCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText:
                    'Décrivez votre diagnostic et les travaux à effectuer...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Note (optionnel)',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'Informations complémentaires pour le client...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateTimeSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Date et heure proposées',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today),
                    label: Text(
                      _dateProposee != null
                          ? '${_dateProposee!.day}/${_dateProposee!.month}/${_dateProposee!.year}'
                          : 'Choisir une date',
                    ),
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now().add(
                          const Duration(days: 1),
                        ),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 90)),
                      );
                      if (d != null) setState(() => _dateProposee = d);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.schedule),
                    label: Text(
                      _heureDebut != null
                          ? _heureDebut!.format(context)
                          : 'Heure début',
                    ),
                    onPressed: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                      );
                      if (t != null) setState(() => _heureDebut = t);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.schedule),
                    label: Text(
                      _heureFin != null
                          ? _heureFin!.format(context)
                          : 'Heure fin',
                    ),
                    onPressed: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                      );
                      if (t != null) setState(() => _heureFin = t);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLignesSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Lignes de devis',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                PopupMenuButton<String>(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '+ Ajouter',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  onSelected: _addLigne,
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'FOURNITURE',
                      child: Text('Fourniture'),
                    ),
                    const PopupMenuItem(
                      value: 'MAIN_OEUVRE',
                      child: Text('Main d\'œuvre'),
                    ),
                    const PopupMenuItem(
                      value: 'DEPLACEMENT',
                      child: Text('Déplacement'),
                    ),
                    const PopupMenuItem(value: 'AUTRE', child: Text('Autre')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_lignes.isEmpty)
              const Text(
                'Aucune ligne ajoutée',
                style: TextStyle(color: Colors.grey),
              )
            else
              ..._lignes.asMap().entries.map(
                (e) => _buildLigneItem(e.key, e.value),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLigneItem(int index, _LigneDevis ligne) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: ligne.type,
                  decoration: const InputDecoration(
                    labelText: 'Type',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'FOURNITURE',
                      child: Text('Fourniture'),
                    ),
                    DropdownMenuItem(
                      value: 'MAIN_OEUVRE',
                      child: Text('Main d\'œuvre'),
                    ),
                    DropdownMenuItem(
                      value: 'DEPLACEMENT',
                      child: Text('Déplacement'),
                    ),
                    DropdownMenuItem(value: 'AUTRE', child: Text('Autre')),
                  ],
                  onChanged: (v) => setState(() => ligne.type = v!),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => _removeLigne(index),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Description',
              isDense: true,
            ),
            onChanged: (v) => ligne.description = v,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'Quantité',
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => ligne.quantite = int.tryParse(v) ?? 1,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'Prix unitaire (FCA)',
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (v) =>
                      ligne.prixUnitaire = double.tryParse(v) ?? 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                'Total: ${ligne.total.toStringAsFixed(0)} FCA',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildValiditeSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Validité du devis (jours)',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            DropdownButton<int>(
              value: _validiteJours,
              items: [3, 5, 7, 10, 14, 30]
                  .map(
                    (v) => DropdownMenuItem(value: v, child: Text('$v jours')),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _validiteJours = v!),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalSection() {
    final commission = _sousTotal * 0.1;
    final total = _sousTotal + commission;

    return Card(
      color: const Color(0xFF0A1628),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Sous-total',
                  style: TextStyle(color: Colors.white70),
                ),
                Text(
                  '${_sousTotal.toStringAsFixed(0)} FCA',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Commission (10%)',
                  style: TextStyle(color: Colors.white70),
                ),
                Text(
                  '${commission.toStringAsFixed(0)} FCA',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
            const Divider(color: Colors.white30),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                Text(
                  '${total.toStringAsFixed(0)} FCA',
                  style: const TextStyle(
                    color: Color(0xFF4CC9F0),
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: _submitting ? null : _submit,
        child: _submitting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text('Envoyer le devis'),
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
