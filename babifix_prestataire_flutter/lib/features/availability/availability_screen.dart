import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../shared/auth_utils.dart';

// ─── Modèle local ────────────────────────────────────────────────────────────

class _Slot {
  final int? id;
  final int weekday;
  final TimeOfDay start;
  final TimeOfDay end;

  const _Slot({this.id, required this.weekday, required this.start, required this.end});

  factory _Slot.fromJson(Map<String, dynamic> j) {
    TimeOfDay _parseTime(String s) {
      final parts = s.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }

    return _Slot(
      id: j['id'] as int?,
      weekday: j['weekday'] as int,
      start: _parseTime(j['start_time'] as String),
      end: _parseTime(j['end_time'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'weekday': weekday,
        'start_time': '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}:00',
        'end_time': '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}:00',
      };
}

class _Unavailability {
  final int? id;
  final DateTime dateFrom;
  final DateTime dateTo;
  final String reason;

  const _Unavailability({
    this.id,
    required this.dateFrom,
    required this.dateTo,
    this.reason = '',
  });

  factory _Unavailability.fromJson(Map<String, dynamic> j) => _Unavailability(
        id: j['id'] as int?,
        dateFrom: DateTime.parse(j['date_from'] as String),
        dateTo: DateTime.parse(j['date_to'] as String),
        reason: j['reason'] as String? ?? '',
      );
}

// ─── Constantes ──────────────────────────────────────────────────────────────

const _weekdays = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
const _weekdaysFull = [
  'Lundi',
  'Mardi',
  'Mercredi',
  'Jeudi',
  'Vendredi',
  'Samedi',
  'Dimanche',
];

// ─── Écran principal ─────────────────────────────────────────────────────────

class AvailabilityScreen extends StatefulWidget {
  const AvailabilityScreen({super.key});

  @override
  State<AvailabilityScreen> createState() => _AvailabilityScreenState();
}

class _AvailabilityScreenState extends State<AvailabilityScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  List<_Slot> _slots = [];
  List<_Unavailability> _unavailabilities = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<String?> _token() => readStoredApiToken();
  String get _base => babifixApiBaseUrl();

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final tok = await _token();
    if (tok == null) {
      setState(() => _loading = false);
      return;
    }
    final headers = {'Authorization': 'Bearer $tok'};
    try {
      final slotsRes = await http.get(
        Uri.parse('$_base/api/prestataire/availability/slots/'),
        headers: headers,
      );
      final unavRes = await http.get(
        Uri.parse('$_base/api/prestataire/availability/unavailability/'),
        headers: headers,
      );

      final slots = slotsRes.statusCode == 200
          ? (jsonDecode(slotsRes.body) as List)
              .map((e) => _Slot.fromJson(e as Map<String, dynamic>))
              .toList()
          : <_Slot>[];

      final unavs = unavRes.statusCode == 200
          ? (jsonDecode(unavRes.body) as List)
              .map((e) => _Unavailability.fromJson(e as Map<String, dynamic>))
              .toList()
          : <_Unavailability>[];

      if (mounted) {
        setState(() {
          _slots = slots;
          _unavailabilities = unavs;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addSlot() async {
    int? weekday;
    TimeOfDay? start;
    TimeOfDay? end;

    // Sélection du jour
    weekday = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Choisir le jour'),
        children: List.generate(
          7,
          (i) => SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, i),
            child: Text(_weekdaysFull[i]),
          ),
        ),
      ),
    );
    if (weekday == null || !mounted) return;

    // Sélection de l'heure de début
    start = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 8, minute: 0),
      helpText: 'Heure de début',
    );
    if (start == null || !mounted) return;

    // Sélection de l'heure de fin
    end = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: start.hour + 1, minute: start.minute),
      helpText: 'Heure de fin',
    );
    if (end == null || !mounted) return;

    if (end.hour < start.hour ||
        (end.hour == start.hour && end.minute <= start.minute)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('L\'heure de fin doit être après l\'heure de début.')),
      );
      return;
    }

    final slot = _Slot(weekday: weekday, start: start, end: end);
    final tok = await _token();
    try {
      final res = await http.post(
        Uri.parse('$_base/api/prestataire/availability/slots/'),
        headers: {
          'Authorization': 'Bearer $tok',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(slot.toJson()),
      );
      if (res.statusCode == 201 || res.statusCode == 200) {
        _loadAll();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : ${res.body}')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur réseau.')),
        );
      }
    }
  }

  Future<void> _deleteSlot(_Slot slot) async {
    if (slot.id == null) return;
    final tok = await _token();
    try {
      await http.delete(
        Uri.parse('$_base/api/prestataire/availability/slots/${slot.id}/'),
        headers: {'Authorization': 'Bearer $tok'},
      );
      _loadAll();
    } catch (_) {}
  }

  Future<void> _addUnavailability() async {
    final now = DateTime.now();
    DateTimeRange? range = await showDateRangePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Période d\'indisponibilité',
    );
    if (range == null || !mounted) return;

    String reason = '';
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Motif (optionnel)'),
        content: TextField(
          controller: reasonCtrl,
          decoration:
              const InputDecoration(hintText: 'Congés, voyage, etc.'),
          maxLength: 100,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirmer')),
        ],
      ),
    );
    reasonCtrl.dispose();
    if (confirmed != true || !mounted) return;
    reason = reasonCtrl.text.trim();

    final tok = await _token();
    final payload = {
      'date_from': range.start.toIso8601String().substring(0, 10),
      'date_to': range.end.toIso8601String().substring(0, 10),
      'reason': reason,
    };
    try {
      final res = await http.post(
        Uri.parse('$_base/api/prestataire/availability/unavailability/'),
        headers: {
          'Authorization': 'Bearer $tok',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );
      if (res.statusCode == 201 || res.statusCode == 200) {
        _loadAll();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : ${res.body}')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur réseau.')),
        );
      }
    }
  }

  Future<void> _deleteUnavailability(_Unavailability u) async {
    if (u.id == null) return;
    final tok = await _token();
    try {
      await http.delete(
        Uri.parse(
            '$_base/api/prestataire/availability/unavailability/${u.id}/'),
        headers: {'Authorization': 'Bearer $tok'},
      );
      _loadAll();
    } catch (_) {}
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Mes disponibilités'),
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        bottom: TabBar(
          controller: _tab,
          indicatorColor: BabifixDesign.cyan,
          labelColor: BabifixDesign.cyan,
          unselectedLabelColor: cs.onSurfaceVariant,
          tabs: const [
            Tab(icon: Icon(Icons.schedule_rounded), text: 'Créneaux'),
            Tab(icon: Icon(Icons.event_busy_rounded), text: 'Congés'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tab,
              children: [
                _SlotsTab(
                  slots: _slots,
                  onAdd: _addSlot,
                  onDelete: _deleteSlot,
                ),
                _UnavailabilityTab(
                  unavailabilities: _unavailabilities,
                  onAdd: _addUnavailability,
                  onDelete: _deleteUnavailability,
                ),
              ],
            ),
    );
  }
}

// ─── Onglet créneaux hebdomadaires ───────────────────────────────────────────

class _SlotsTab extends StatelessWidget {
  final List<_Slot> slots;
  final VoidCallback onAdd;
  final void Function(_Slot) onDelete;

  const _SlotsTab(
      {required this.slots, required this.onAdd, required this.onDelete});

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}h${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Group by weekday
    final grouped = <int, List<_Slot>>{};
    for (final s in slots) {
      grouped.putIfAbsent(s.weekday, () => []).add(s);
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Définissez vos créneaux de travail hebdomadaires.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
              ),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Ajouter'),
                style: FilledButton.styleFrom(
                    backgroundColor: BabifixDesign.cyan),
              ),
            ],
          ),
        ),
        Expanded(
          child: slots.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.schedule_rounded,
                          size: 64,
                          color: cs.outline.withValues(alpha: 0.35)),
                      const SizedBox(height: 16),
                      const Text('Aucun créneau défini',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text('Ajoutez vos horaires de disponibilité.',
                          style: TextStyle(color: cs.onSurfaceVariant)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: 7,
                  itemBuilder: (_, dayIndex) {
                    final daySlots = grouped[dayIndex] ?? [];
                    if (daySlots.isEmpty) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 12, bottom: 6),
                          child: Text(
                            _weekdaysFull[dayIndex],
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14),
                          ),
                        ),
                        ...daySlots.map(
                          (s) => Card(
                            elevation: 0,
                            margin: const EdgeInsets.only(bottom: 6),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(BabifixDesign.radiusMD),
                              side: BorderSide(
                                  color: cs.outlineVariant, width: 1),
                            ),
                            child: ListTile(
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: BabifixDesign.cyan
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: Text(
                                    _weekdays[s.weekday],
                                    style: TextStyle(
                                      color: BabifixDesign.cyan,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ),
                              title: Text(
                                '${_fmt(s.start)} – ${_fmt(s.end)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline_rounded,
                                    color: Colors.red),
                                onPressed: () => onDelete(s),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ─── Onglet congés / indisponibilités ────────────────────────────────────────

class _UnavailabilityTab extends StatelessWidget {
  final List<_Unavailability> unavailabilities;
  final VoidCallback onAdd;
  final void Function(_Unavailability) onDelete;

  const _UnavailabilityTab({
    required this.unavailabilities,
    required this.onAdd,
    required this.onDelete,
  });

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Bloquez des périodes où vous n\'êtes pas disponible.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
              ),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Bloquer'),
                style: FilledButton.styleFrom(
                    backgroundColor: BabifixDesign.ciOrange),
              ),
            ],
          ),
        ),
        Expanded(
          child: unavailabilities.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event_available_rounded,
                          size: 64,
                          color: cs.outline.withValues(alpha: 0.35)),
                      const SizedBox(height: 16),
                      const Text('Aucune période bloquée',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text(
                          'Ajoutez vos congés ou indisponibilités ponctuelles.',
                          style: TextStyle(color: cs.onSurfaceVariant),
                          textAlign: TextAlign.center),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: unavailabilities.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final u = unavailabilities[i];
                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(BabifixDesign.radiusMD),
                        side:
                            BorderSide(color: cs.outlineVariant, width: 1),
                      ),
                      child: ListTile(
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: BabifixDesign.ciOrange
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.event_busy_rounded,
                              color: BabifixDesign.ciOrange, size: 22),
                        ),
                        title: Text(
                          '${_fmt(u.dateFrom)} → ${_fmt(u.dateTo)}',
                          style:
                              const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: u.reason.isNotEmpty
                            ? Text(u.reason,
                                style: TextStyle(
                                    color: cs.onSurfaceVariant,
                                    fontSize: 12))
                            : null,
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: Colors.red),
                          onPressed: () => onDelete(u),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
