import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../babifix_api_config.dart';
import '../../shared/auth_utils.dart';
import '../../shared/widgets/babifix_ring_loader.dart';
import '../../shared/widgets/babifix_snackbar.dart';

// ─── Premium Colors ────────────────────────────────────────────────────────

const _premiumGold = Color(0xFFFFD700);
const _deepNavy = Color(0xFF0A0E27);
const _charcoal = Color(0xFF1A1F3A);
const _darkSurface = Color(0xFF0D1117);
const _cardBg = Color(0xFF151B30);

// ─── Modèle local ────────────────────────────────────────────────────────────

class _Slot {
  final int? id;
  final int weekday;
  final TimeOfDay start;
  final TimeOfDay end;

  const _Slot({this.id, required this.weekday, required this.start, required this.end});

  factory _Slot.fromJson(Map<String, dynamic> j) {
    TimeOfDay parseTime(String s) {
      final parts = s.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }

    return _Slot(
      id: j['id'] as int?,
      weekday: (j['jour_semaine'] ?? j['weekday']) as int,
      start: parseTime((j['heure_debut'] ?? j['start_time']) as String),
      end: parseTime((j['heure_fin'] ?? j['end_time']) as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'jour_semaine': weekday,
        'heure_debut': '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}:00',
        'heure_fin': '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}:00',
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
        dateFrom: DateTime.parse(
          (j['date_debut'] ?? j['date_from']) as String,
        ),
        dateTo: DateTime.parse(
          (j['date_fin'] ?? j['date_to']) as String,
        ),
        reason: (j['motif'] ?? j['reason']) as String? ?? '',
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

      final slotsResJson = jsonDecode(slotsRes.body);
      final slotsData = slotsResJson is List
          ? slotsResJson
          : (slotsResJson as Map<String, dynamic>)['slots'] as List? ?? [];
      final slots = slotsData
          .map((e) => _Slot.fromJson(e as Map<String, dynamic>))
          .toList();

      final unavResJson = jsonDecode(unavRes.body);
      final unavData = unavResJson is List
          ? unavResJson
          : (unavResJson as Map<String, dynamic>)['periods'] as List? ?? [];
      final unavs = unavData
          .map((e) => _Unavailability.fromJson(e as Map<String, dynamic>))
          .toList();

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

  void _showError(String message) {
    if (!mounted) return;
    showBabifixToast(
        context,
        type: BabifixToastType.info,
        message: message,
      );
  }

  Future<void> _addSlot() async {
    int? weekday;
    TimeOfDay? start;
    TimeOfDay? end;

    weekday = await showDialog<int>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: _charcoal,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: _premiumGold.withValues(alpha: 0.3)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Choisir le jour',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              ...List.generate(
                7,
                (i) => ListTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          _premiumGold.withValues(alpha: 0.2),
                          _premiumGold.withValues(alpha: 0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        _weekdays[i],
                        style: const TextStyle(
                          color: _premiumGold,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  title: Text(
                    _weekdaysFull[i],
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  onTap: () => Navigator.pop(ctx, i),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (weekday == null || !mounted) return;

    start = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 8, minute: 0),
      helpText: 'Heure de début',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            timePickerTheme: TimePickerThemeData(
              backgroundColor: _charcoal,
              hourMinuteTextColor: Colors.white,
              hourMinuteColor: _premiumGold.withValues(alpha: 0.2),
              dayPeriodTextColor: Colors.white,
              dayPeriodColor: _premiumGold.withValues(alpha: 0.2),
              dialHandColor: _premiumGold,
              dialBackgroundColor: _cardBg,
              entryModeIconColor: _premiumGold,
              confirmButtonStyle: ButtonStyle(
                foregroundColor: WidgetStateProperty.all(_premiumGold),
              ),
              cancelButtonStyle: ButtonStyle(
                foregroundColor: WidgetStateProperty.all(Colors.white70),
              ),
            ),
            colorScheme: const ColorScheme.dark(
              primary: _premiumGold,
              surface: _charcoal,
            ),
          ),
          child: child!,
        );
      },
    );
    if (start == null || !mounted) return;

    end = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: start.hour + 1, minute: start.minute),
      helpText: 'Heure de fin',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            timePickerTheme: TimePickerThemeData(
              backgroundColor: _charcoal,
              hourMinuteTextColor: Colors.white,
              hourMinuteColor: _premiumGold.withValues(alpha: 0.2),
              dayPeriodTextColor: Colors.white,
              dayPeriodColor: _premiumGold.withValues(alpha: 0.2),
              dialHandColor: _premiumGold,
              dialBackgroundColor: _cardBg,
              entryModeIconColor: _premiumGold,
              confirmButtonStyle: ButtonStyle(
                foregroundColor: WidgetStateProperty.all(_premiumGold),
              ),
              cancelButtonStyle: ButtonStyle(
                foregroundColor: WidgetStateProperty.all(Colors.white70),
              ),
            ),
            colorScheme: const ColorScheme.dark(
              primary: _premiumGold,
              surface: _charcoal,
            ),
          ),
          child: child!,
        );
      },
    );
    if (end == null || !mounted) return;

    if (end.hour < start.hour ||
        (end.hour == start.hour && end.minute <= start.minute)) {
      _showError('L\'heure de fin doit être après l\'heure de début.');
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
        _showError('Erreur lors de l\'ajout du créneau (${res.statusCode}).');
      }
    } catch (_) {
      if (mounted) {
        _showError('Erreur réseau.');
      }
    }
  }

  Future<void> _deleteSlot(_Slot slot) async {
    if (slot.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: _charcoal,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.red.withValues(alpha: 0.3)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 30),
              ),
              const SizedBox(height: 16),
              const Text(
                'Supprimer ce créneau ?',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white70,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Annuler'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Supprimer'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true) return;
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
      cancelText: 'Annuler',
      confirmText: 'Confirmer',
      saveText: 'Sauvegarder',
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFFFF6B6B),
              onPrimary: Colors.white,
              surface: _charcoal,
              onSurface: Colors.white,
              onSurfaceVariant: Colors.white70,
            ),
            dialogTheme: const DialogThemeData(backgroundColor: _charcoal),
            datePickerTheme: DatePickerThemeData(
              backgroundColor: _charcoal,
              headerBackgroundColor: _deepNavy,
              headerForegroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              rangePickerBackgroundColor: _charcoal,
              rangePickerHeaderBackgroundColor: _deepNavy,
              rangePickerHeaderForegroundColor: Colors.white,
              rangeSelectionBackgroundColor: const Color(0xFFFF6B6B).withValues(alpha: 0.2),
              rangeSelectionOverlayColor: WidgetStateProperty.all(
                const Color(0xFFFF6B6B).withValues(alpha: 0.15),
              ),
              dayStyle: const TextStyle(color: Colors.white, fontSize: 13),
              dayForegroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return Colors.white;
                if (states.contains(WidgetState.disabled)) return Colors.white24;
                return Colors.white;
              }),
              dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return const Color(0xFFFF6B6B);
                return null;
              }),
              todayBorder: BorderSide(color: _premiumGold),
              yearStyle: const TextStyle(color: Colors.white),
              yearForegroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return const Color(0xFFFF6B6B);
                return Colors.white;
              }),
              weekdayStyle: const TextStyle(color: _premiumGold, fontWeight: FontWeight.w700),
              dividerColor: _premiumGold.withValues(alpha: 0.2),
              inputDecorationTheme: const InputDecorationTheme(
                filled: true,
                fillColor: _cardBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                  borderSide: BorderSide(color: _premiumGold, width: 1),
                ),
                labelStyle: TextStyle(color: Colors.white70),
                hintStyle: TextStyle(color: Colors.white38),
              ),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
            ),
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B6B),
                foregroundColor: Colors.white,
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (range == null || !mounted) return;

    String reason = '';
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: _charcoal,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: const Color(0xFFFF6B6B).withValues(alpha: 0.3)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Motif (optionnel)',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                style: const TextStyle(color: Colors.white),
                maxLength: 100,
                decoration: InputDecoration(
                  hintText: 'Congés, voyage, etc.',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.06),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  counterStyle: const TextStyle(color: Colors.white54),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white70,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Annuler'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6B6B),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Confirmer'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
        _showError('Erreur lors de l\'ajout du congé (${res.statusCode}).');
      }
    } catch (_) {
      if (mounted) {
        _showError('Erreur réseau.');
      }
    }
  }

  Future<void> _deleteUnavailability(_Unavailability u) async {
    if (u.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: _charcoal,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.red.withValues(alpha: 0.3)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 30),
              ),
              const SizedBox(height: 16),
              const Text(
                'Supprimer cette période ?',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white70,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Annuler'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Supprimer'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true) return;
    final tok = await _token();
    try {
      await http.delete(
        Uri.parse('$_base/api/prestataire/availability/unavailability/${u.id}/'),
        headers: {'Authorization': 'Bearer $tok'},
      );
      _loadAll();
    } catch (_) {}
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_deepNavy, _darkSurface, _deepNavy],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text(
            'Mes disponibilités',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 20,
              letterSpacing: 0.3,
            ),
          ),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          bottom: TabBar(
            controller: _tab,
            indicatorColor: _premiumGold,
            indicatorWeight: 3,
            labelColor: _premiumGold,
            unselectedLabelColor: Colors.white54,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            dividerColor: Colors.white.withValues(alpha: 0.1),
            tabs: const [
              Tab(icon: Icon(Icons.schedule_rounded, size: 20), text: 'Créneaux'),
              Tab(icon: Icon(Icons.event_busy_rounded, size: 20), text: 'Congés'),
            ],
          ),
        ),
        body: _loading
            ? Center(
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: BabifixRingLoader.cyan(size: 28),
                ),
              )
            : TabBarView(
                controller: _tab,
                children: [
                  _SlotsTab(
                    slots: _slots,
                    onAdd: _addSlot,
                    onDelete: _deleteSlot,
                    onRefresh: _loadAll,
                  ),
                  _UnavailabilityTab(
                    unavailabilities: _unavailabilities,
                    onAdd: _addUnavailability,
                    onDelete: _deleteUnavailability,
                    onRefresh: _loadAll,
                  ),
                ],
              ),
      ),
    );
  }
}

// ─── Onglet créneaux hebdomadaires ───────────────────────────────────────────

class _SlotsTab extends StatelessWidget {
  final List<_Slot> slots;
  final VoidCallback onAdd;
  final void Function(_Slot) onDelete;
  final Future<void> Function() onRefresh;

  const _SlotsTab({
    required this.slots,
    required this.onAdd,
    required this.onDelete,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final grouped = <int, List<_Slot>>{};
    for (final s in slots) {
      grouped.putIfAbsent(s.weekday, () => []).add(s);
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _premiumGold.withValues(alpha: 0.2),
                      _premiumGold.withValues(alpha: 0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.info_outline_rounded, color: _premiumGold, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Définissez vos créneaux de travail hebdomadaires.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Ajouter un créneau'),
              style: FilledButton.styleFrom(
                backgroundColor: _premiumGold,
                foregroundColor: _deepNavy,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 4,
                shadowColor: _premiumGold.withValues(alpha: 0.4),
                textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: RefreshIndicator(
            onRefresh: onRefresh,
            color: const Color(0xFF4CC9F0),
            child: slots.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [_EmptyStateSlots()],
                )
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  itemCount: 7,
                  itemBuilder: (_, dayIndex) {
                    final daySlots = grouped[dayIndex] ?? [];
                    if (daySlots.isEmpty) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 16, bottom: 8),
                          child: Row(
                            children: [
                              Container(
                                width: 4,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: _premiumGold,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _weekdaysFull[dayIndex],
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: Colors.white,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _premiumGold.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${daySlots.length} créneau${daySlots.length > 1 ? 'x' : ''}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: _premiumGold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        ...daySlots.map(
                          (s) => _SlotCard(slot: s, onDelete: () => onDelete(s)),
                        ),
                      ],
                    );
                  },
                ),
          ),
        ),
      ],
    );
  }
}

class _SlotCard extends StatelessWidget {
  final _Slot slot;
  final VoidCallback onDelete;

  const _SlotCard({required this.slot, required this.onDelete});

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}h${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _cardBg,
            _cardBg.withValues(alpha: 0.7),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _premiumGold.withValues(alpha: 0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: _premiumGold.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _premiumGold.withValues(alpha: 0.2),
                _premiumGold.withValues(alpha: 0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _premiumGold.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Center(
            child: Text(
              _weekdays[slot.weekday],
              style: const TextStyle(
                color: _premiumGold,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ),
        title: Text(
          '${_fmt(slot.start)} – ${_fmt(slot.end)}',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: Colors.white,
            letterSpacing: 0.5,
          ),
        ),
        subtitle: Text(
          '${slot.end.hour - slot.start.hour}h de disponibilité',
          style: const TextStyle(
            fontSize: 12,
            color: Colors.white54,
          ),
        ),
        trailing: IconButton(
          icon: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.red.withValues(alpha: 0.3),
              ),
            ),
            child: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 18),
          ),
          onPressed: onDelete,
        ),
      ),
    );
  }
}

class _EmptyStateSlots extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _premiumGold.withValues(alpha: 0.1),
              border: Border.all(
                color: _premiumGold.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: const Icon(Icons.schedule_rounded, size: 48, color: _premiumGold),
          ),
          const SizedBox(height: 20),
          const Text(
            'Aucun créneau défini',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Ajoutez vos horaires de disponibilité.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14),
          ),
        ],
      ),
    );
  }
}

// ─── Onglet congés / indisponibilités ────────────────────────────────────────

class _UnavailabilityTab extends StatelessWidget {
  final List<_Unavailability> unavailabilities;
  final VoidCallback onAdd;
  final void Function(_Unavailability) onDelete;
  final Future<void> Function() onRefresh;

  const _UnavailabilityTab({
    required this.unavailabilities,
    required this.onAdd,
    required this.onDelete,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B6B).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.event_busy_rounded, color: Color(0xFFFF6B6B), size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Bloquez des périodes où vous n\'êtes pas disponible.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Bloquer une période'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B6B),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 4,
                shadowColor: const Color(0xFFFF6B6B).withValues(alpha: 0.4),
                textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: RefreshIndicator(
            onRefresh: onRefresh,
            color: const Color(0xFF4CC9F0),
            child: unavailabilities.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [_EmptyStateUnavailability()],
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  itemCount: unavailabilities.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final u = unavailabilities[i];
                    return _UnavailabilityCard(u: u, onDelete: () => onDelete(u));
                  },
                ),
          ),
        ),
      ],
    );
  }
}

class _UnavailabilityCard extends StatelessWidget {
  final _Unavailability u;
  final VoidCallback onDelete;

  const _UnavailabilityCard({required this.u, required this.onDelete});

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final duration = u.dateTo.difference(u.dateFrom).inDays + 1;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF2A1A1A),
            const Color(0xFF1A1515),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFF6B6B).withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF6B6B).withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFFFF6B6B).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFFFF6B6B).withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: const Icon(Icons.event_busy_rounded, color: Color(0xFFFF6B6B), size: 22),
        ),
        title: Text(
          '${_fmt(u.dateFrom)} → ${_fmt(u.dateTo)}',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: Colors.white,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (u.reason.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  u.reason,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B6B).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$duration jour${duration > 1 ? 's' : ''}',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFFF6B6B),
                ),
              ),
            ),
          ],
        ),
        trailing: IconButton(
          icon: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.red.withValues(alpha: 0.3),
              ),
            ),
            child: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 18),
          ),
          onPressed: onDelete,
        ),
      ),
    );
  }
}

class _EmptyStateUnavailability extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFF6B6B).withValues(alpha: 0.1),
              border: Border.all(
                color: const Color(0xFFFF6B6B).withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: const Icon(Icons.event_available_rounded, size: 48, color: Color(0xFFFF6B6B)),
          ),
          const SizedBox(height: 20),
          const Text(
            'Aucune période bloquée',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Ajoutez vos congés ou indisponibilités ponctuelles.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
