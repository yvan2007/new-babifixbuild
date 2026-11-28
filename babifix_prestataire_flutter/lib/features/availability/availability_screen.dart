import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../shared/auth_utils.dart';
import '../../shared/widgets/babifix_ring_loader.dart';
import '../../shared/widgets/babifix_snackbar.dart';

// ─── Palette adaptative (Blanc / Clair / Bleu Sombre) ───────────────────────

class _AvailPalette {
  final bool isDark;
  final Color pageTop;
  final Color pageBottom;
  final Color cardBg;
  final Color dialogBg;
  final Color softBg;
  final Color border;
  final Color textPrimary;
  final Color textMuted;
  final Color accent;
  final Color onAccent;
  final Color danger;
  final Color unavailBgStart;
  final Color unavailBgEnd;

  const _AvailPalette({
    required this.isDark,
    required this.pageTop,
    required this.pageBottom,
    required this.cardBg,
    required this.dialogBg,
    required this.softBg,
    required this.border,
    required this.textPrimary,
    required this.textMuted,
    required this.accent,
    required this.onAccent,
    required this.danger,
    required this.unavailBgStart,
    required this.unavailBgEnd,
  });

  factory _AvailPalette.of(BuildContext context) {
    final dark = BabifixDesign.isDark(context);
    final whiteMode = BabifixDesign.isWhiteMode(context);
    return _AvailPalette(
      isDark: dark,
      pageTop: dark
          ? BabifixDesign.navy
          : (whiteMode ? BabifixDesign.bgWhite : BabifixDesign.bgLight),
      pageBottom: dark
          ? BabifixDesign.obsidian
          : (whiteMode ? BabifixDesign.bgWhite : BabifixDesign.bgSoft),
      cardBg: dark ? BabifixDesign.navySurface : BabifixDesign.bgWhite,
      dialogBg: dark ? BabifixDesign.navySurface : BabifixDesign.bgWhite,
      softBg: dark ? BabifixDesign.navyElevated : BabifixDesign.bgSoft,
      border: dark
          ? BabifixDesign.borderDark
          : BabifixDesign.borderLight,
      textPrimary: BabifixDesign.textPrimaryOf(context),
      textMuted: BabifixDesign.textMutedOf(context),
      accent: dark ? const Color(0xFFFFD700) : BabifixDesign.navy,
      onAccent: dark ? const Color(0xFF0A0E27) : Colors.white,
      danger: dark ? const Color(0xFFFF6B6B) : const Color(0xFFB91C1C),
      unavailBgStart:
          dark ? const Color(0xFF2A1A1A) : const Color(0xFFFFF5F5),
      unavailBgEnd: dark ? const Color(0xFF1A1515) : BabifixDesign.bgWhite,
    );
  }
}

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
    final pal = _AvailPalette.of(context);

    weekday = await showDialog<int>(
      context: context,
      builder: (ctx) {
        final dPal = _AvailPalette.of(ctx);
        return Dialog(
          backgroundColor: dPal.dialogBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: dPal.accent.withValues(alpha: 0.25)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Choisir le jour',
                  style: TextStyle(
                    color: dPal.textPrimary,
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
                        color: dPal.accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          _weekdays[i],
                          style: TextStyle(
                            color: dPal.accent,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    title: Text(
                      _weekdaysFull[i],
                      style: TextStyle(
                          color: dPal.textPrimary,
                          fontWeight: FontWeight.w600),
                    ),
                    onTap: () => Navigator.pop(ctx, i),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (weekday == null || !mounted) return;

    start = await _pickTimeThemed(const TimeOfDay(hour: 8, minute: 0), 'Heure de début');
    if (start == null || !mounted) return;

    end = await _pickTimeThemed(
      TimeOfDay(
        hour: start.hour == 23 ? 23 : start.hour + 1,
        minute: start.hour == 23 ? 59 : start.minute,
      ),
      'Heure de fin',
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
    // Keep reference to pal clean if needed.
    assert(pal.textPrimary != Colors.transparent);
  }

  // Sélecteur d'heure adaptatif au thème actif.
  Future<TimeOfDay?> _pickTimeThemed(TimeOfDay initial, String help) {
    final pal = _AvailPalette.of(context);
    return showTimePicker(
      context: context,
      initialTime: initial,
      helpText: help,
      builder: (context, child) {
        final base = pal.isDark ? ThemeData.dark() : ThemeData.light();
        return Theme(
          data: base.copyWith(
            timePickerTheme: TimePickerThemeData(
              backgroundColor: pal.dialogBg,
              hourMinuteTextColor: pal.textPrimary,
              hourMinuteColor: pal.accent.withValues(alpha: 0.14),
              dayPeriodTextColor: pal.textPrimary,
              dayPeriodColor: pal.accent.withValues(alpha: 0.14),
              dialHandColor: pal.accent,
              dialBackgroundColor: pal.softBg,
              entryModeIconColor: pal.accent,
              confirmButtonStyle: ButtonStyle(
                foregroundColor: WidgetStateProperty.all(pal.accent),
              ),
              cancelButtonStyle: ButtonStyle(
                foregroundColor: WidgetStateProperty.all(pal.textMuted),
              ),
            ),
            colorScheme: pal.isDark
                ? ColorScheme.dark(primary: pal.accent, surface: pal.dialogBg, onPrimary: pal.onAccent, onSurface: pal.textPrimary)
                : ColorScheme.light(primary: pal.accent, surface: pal.dialogBg, onPrimary: pal.onAccent, onSurface: pal.textPrimary),
          ),
          child: child!,
        );
      },
    );
  }

  /// Saisie RAPIDE : choisir plusieurs jours (+ presets) et UNE plage horaire,
  /// appliquée à tous les jours sélectionnés en un seul geste.
  Future<void> _addSlotsBulk() async {
    final selected = <int>{};
    TimeOfDay start = const TimeOfDay(hour: 8, minute: 0);
    TimeOfDay end = const TimeOfDay(hour: 17, minute: 0);
    String fmt(TimeOfDay t) =>
        '${t.hour.toString().padLeft(2, '0')}h${t.minute.toString().padLeft(2, '0')}';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final pal = _AvailPalette.of(ctx);
          return Dialog(
            backgroundColor: pal.dialogBg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: pal.accent.withValues(alpha: 0.25)),
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Saisie rapide',
                        style: TextStyle(
                            color: pal.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text('Choisissez les jours et une plage horaire.',
                        style: TextStyle(color: pal.textMuted, fontSize: 12.5)),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _preset('Lun - Ven', pal, () {
                          setLocal(() {
                            selected
                              ..clear()
                              ..addAll([0, 1, 2, 3, 4]);
                          });
                        }),
                        _preset('Week-end', pal, () {
                          setLocal(() {
                            selected
                              ..clear()
                              ..addAll([5, 6]);
                          });
                        }),
                        _preset('Tous', pal, () {
                          setLocal(() {
                            selected
                              ..clear()
                              ..addAll([0, 1, 2, 3, 4, 5, 6]);
                          });
                        }),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(7, (i) {
                        final sel = selected.contains(i);
                        return GestureDetector(
                          onTap: () => setLocal(() {
                            if (sel) {
                              selected.remove(i);
                            } else {
                              selected.add(i);
                            }
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 9),
                            decoration: BoxDecoration(
                              color: sel
                                  ? pal.accent.withValues(alpha: 0.16)
                                  : pal.softBg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: sel
                                    ? pal.accent
                                    : pal.border,
                                width: sel ? 1.5 : 1,
                              ),
                            ),
                            child: Text(_weekdays[i],
                                style: TextStyle(
                                    color: sel ? pal.accent : pal.textMuted,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13)),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final t = await _pickTimeThemed(start, 'Heure de début');
                              if (t != null) setLocal(() => start = t);
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: pal.textPrimary,
                              side: BorderSide(
                                  color: pal.accent.withValues(alpha: 0.4)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: Text('Début : ${fmt(start)}'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final t = await _pickTimeThemed(end, 'Heure de fin');
                              if (t != null) setLocal(() => end = t);
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: pal.textPrimary,
                              side: BorderSide(
                                  color: pal.accent.withValues(alpha: 0.4)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: Text('Fin : ${fmt(end)}'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: pal.accent,
                          foregroundColor: pal.onAccent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          textStyle:
                              const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        child: const Text('Appliquer'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    if (ok != true || !mounted) return;
    if (selected.isEmpty) {
      _showError('Sélectionnez au moins un jour.');
      return;
    }
    if (end.hour < start.hour ||
        (end.hour == start.hour && end.minute <= start.minute)) {
      _showError('L\'heure de fin doit être après l\'heure de début.');
      return;
    }

    final tok = await _token();
    int added = 0;
    for (final d in selected) {
      final slot = _Slot(weekday: d, start: start, end: end);
      try {
        final res = await http.post(
          Uri.parse('$_base/api/prestataire/availability/slots/'),
          headers: {
            'Authorization': 'Bearer $tok',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(slot.toJson()),
        );
        if (res.statusCode == 200 || res.statusCode == 201) added++;
      } catch (_) {}
    }
    if (mounted) {
      await _loadAll();
      if (added > 0 && mounted) {
        showBabifixToast(
          context,
          type: BabifixToastType.success,
          message: '$added creneau${added > 1 ? 'x' : ''} ajoute${added > 1 ? 's' : ''}.',
        );
      } else {
        _showError('Aucun creneau n\'a pu etre ajoute.');
      }
    }
  }

  Widget _preset(String label, _AvailPalette pal, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: pal.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: pal.accent.withValues(alpha: 0.3)),
        ),
        child: Text(label,
            style: TextStyle(
                color: pal.accent,
                fontSize: 12,
                fontWeight: FontWeight.w700)),
      ),
    );
  }

  Future<void> _deleteSlot(_Slot slot) async {
    if (slot.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final pal = _AvailPalette.of(ctx);
        return Dialog(
          backgroundColor: pal.dialogBg,
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
                Text(
                  'Supprimer ce créneau ?',
                  style: TextStyle(color: pal.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: TextButton.styleFrom(
                          foregroundColor: pal.textMuted,
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
                          foregroundColor: Colors.white,
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
        );
      },
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
    final outerPal = _AvailPalette.of(context);
    DateTimeRange? range = await showDateRangePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Période d\'indisponibilité',
      cancelText: 'Annuler',
      confirmText: 'Confirmer',
      saveText: 'Sauvegarder',
      builder: (context, child) {
        final base = outerPal.isDark ? ThemeData.dark() : ThemeData.light();
        return Theme(
          data: base.copyWith(
            colorScheme: outerPal.isDark
                ? ColorScheme.dark(
                    primary: outerPal.danger,
                    onPrimary: Colors.white,
                    surface: outerPal.dialogBg,
                    onSurface: outerPal.textPrimary,
                    onSurfaceVariant: outerPal.textMuted,
                  )
                : ColorScheme.light(
                    primary: outerPal.danger,
                    onPrimary: Colors.white,
                    surface: outerPal.dialogBg,
                    onSurface: outerPal.textPrimary,
                    onSurfaceVariant: outerPal.textMuted,
                  ),
            dialogTheme: DialogThemeData(backgroundColor: outerPal.dialogBg),
            datePickerTheme: DatePickerThemeData(
              backgroundColor: outerPal.dialogBg,
              headerBackgroundColor: outerPal.pageTop,
              headerForegroundColor: outerPal.textPrimary,
              surfaceTintColor: Colors.transparent,
              rangePickerBackgroundColor: outerPal.dialogBg,
              rangePickerHeaderBackgroundColor: outerPal.pageTop,
              rangePickerHeaderForegroundColor: outerPal.textPrimary,
              rangeSelectionBackgroundColor: outerPal.danger.withValues(alpha: 0.18),
              rangeSelectionOverlayColor: WidgetStateProperty.all(
                outerPal.danger.withValues(alpha: 0.14),
              ),
              dayStyle: TextStyle(color: outerPal.textPrimary, fontSize: 13),
              dayForegroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return Colors.white;
                if (states.contains(WidgetState.disabled)) {
                  return outerPal.textMuted.withValues(alpha: 0.38);
                }
                return outerPal.textPrimary;
              }),
              dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return outerPal.danger;
                return null;
              }),
              todayBorder: BorderSide(color: outerPal.accent),
              yearStyle: TextStyle(color: outerPal.textPrimary),
              yearForegroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return outerPal.danger;
                return outerPal.textPrimary;
              }),
              weekdayStyle: TextStyle(color: outerPal.accent, fontWeight: FontWeight.w700),
              dividerColor: outerPal.border,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: outerPal.textMuted),
            ),
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                backgroundColor: outerPal.danger,
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
      builder: (ctx) {
        final pal = _AvailPalette.of(ctx);
        return Dialog(
          backgroundColor: pal.dialogBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: pal.danger.withValues(alpha: 0.3)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Motif (optionnel)',
                  style: TextStyle(color: pal.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonCtrl,
                  style: TextStyle(color: pal.textPrimary),
                  maxLength: 100,
                  decoration: InputDecoration(
                    hintText: 'Congés, voyage, etc.',
                    hintStyle: TextStyle(color: pal.textMuted.withValues(alpha: 0.7)),
                    filled: true,
                    fillColor: pal.softBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: pal.border),
                    ),
                    counterStyle: TextStyle(color: pal.textMuted),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: TextButton.styleFrom(
                          foregroundColor: pal.textMuted,
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
                          backgroundColor: pal.danger,
                          foregroundColor: Colors.white,
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
        );
      },
    );
    reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    if (confirmed != true || !mounted) return;

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

  /// Indispos par DATES PRÉCISES : le presta coche plusieurs jours distincts
  /// (ex. 20, 22, 30) sur un calendrier jusqu'à 2 mois. Chaque date cochée
  /// devient une indisponibilité d'un jour.
  Future<void> _addUnavailabilityDates() async {
    final selected = <DateTime>{};
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final pal = _AvailPalette.of(ctx);
        return Dialog(
          backgroundColor: pal.dialogBg,
          insetPadding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: pal.danger.withValues(alpha: 0.3)),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 560),
            child: _MultiMonthCalendar(
              selected: selected,
              onConfirm: () => Navigator.pop(ctx, true),
              onCancel: () => Navigator.pop(ctx, false),
            ),
          ),
        );
      },
    );
    if (result != true || !mounted) return;
    if (selected.isEmpty) {
      _showError('Sélectionnez au moins une date.');
      return;
    }
    final tok = await _token();
    int added = 0;
    for (final d in selected) {
      final iso =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      try {
        final res = await http.post(
          Uri.parse('$_base/api/prestataire/availability/unavailability/'),
          headers: {
            'Authorization': 'Bearer $tok',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'date_from': iso, 'date_to': iso, 'reason': ''}),
        );
        if (res.statusCode == 200 || res.statusCode == 201) added++;
      } catch (_) {}
    }
    if (mounted) {
      await _loadAll();
      _showError('$added date${added > 1 ? 's' : ''} bloquée${added > 1 ? 's' : ''}.');
    }
  }

  Future<void> _deleteUnavailability(_Unavailability u) async {
    if (u.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final pal = _AvailPalette.of(ctx);
        return Dialog(
          backgroundColor: pal.dialogBg,
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
                Text(
                  'Supprimer cette période ?',
                  style: TextStyle(color: pal.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: TextButton.styleFrom(
                          foregroundColor: pal.textMuted,
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
                          foregroundColor: Colors.white,
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
        );
      },
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
    final pal = _AvailPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [pal.pageTop, pal.pageBottom],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          leading: Navigator.canPop(context)
              ? BackButton(color: pal.textPrimary)
              : null,
          iconTheme: IconThemeData(color: pal.textPrimary),
          foregroundColor: pal.textPrimary,
          title: Text(
            'Mes disponibilités',
            style: TextStyle(
              color: pal.textPrimary,
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
            indicatorColor: pal.accent,
            indicatorWeight: 3,
            labelColor: pal.accent,
            unselectedLabelColor: pal.textMuted,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            dividerColor: pal.border,
            tabs: const [
              Tab(icon: Icon(Icons.schedule_rounded, size: 20), text: 'Créneaux'),
              Tab(icon: Icon(Icons.event_busy_rounded, size: 20), text: 'Congés'),
            ],
          ),
        ),
        body: SafeArea(
          top: false,
          bottom: true,
          child: _loading
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
                      onBulkAdd: _addSlotsBulk,
                      onDelete: _deleteSlot,
                      onRefresh: _loadAll,
                    ),
                    _UnavailabilityTab(
                      unavailabilities: _unavailabilities,
                      onAdd: _addUnavailability,
                      onAddDates: _addUnavailabilityDates,
                      onDelete: _deleteUnavailability,
                      onRefresh: _loadAll,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ─── Onglet créneaux hebdomadaires ───────────────────────────────────────────

class _SlotsTab extends StatelessWidget {
  final List<_Slot> slots;
  final VoidCallback onAdd;
  final VoidCallback onBulkAdd;
  final void Function(_Slot) onDelete;
  final Future<void> Function() onRefresh;

  const _SlotsTab({
    required this.slots,
    required this.onAdd,
    required this.onBulkAdd,
    required this.onDelete,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final pal = _AvailPalette.of(context);
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
                  color: pal.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.info_outline_rounded, color: pal.accent, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Définissez vos créneaux de travail hebdomadaires.',
                  style: TextStyle(color: pal.textMuted, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onBulkAdd,
                  icon: const Icon(Icons.bolt_rounded, size: 20),
                  label: const Text('Saisie rapide'),
                  style: FilledButton.styleFrom(
                    backgroundColor: pal.accent,
                    foregroundColor: pal.onAccent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: pal.isDark ? 4 : 0,
                    shadowColor: pal.accent.withValues(alpha: 0.3),
                    textStyle: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Un'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: pal.accent,
                  side: BorderSide(color: pal.accent.withValues(alpha: 0.45)),
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  textStyle:
                      const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
            ],
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
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
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
                                  color: pal.accent,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  _weekdaysFull[dayIndex],
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    color: pal.textPrimary,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: pal.accent.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${daySlots.length} créneau${daySlots.length > 1 ? 'x' : ''}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: pal.accent,
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
    final pal = _AvailPalette.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: pal.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: pal.isDark ? pal.accent.withValues(alpha: 0.22) : pal.border,
          width: 1,
        ),
        boxShadow: BabifixDesign.elevationShadowSM(!pal.isDark),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: pal.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: pal.accent.withValues(alpha: 0.28),
              width: 1,
            ),
          ),
          child: Center(
            child: Text(
              _weekdays[slot.weekday],
              style: TextStyle(
                color: pal.accent,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ),
        title: Text(
          '${_fmt(slot.start)} - ${_fmt(slot.end)}',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: pal.textPrimary,
            letterSpacing: 0.5,
          ),
        ),
        subtitle: Text(
          '${slot.end.hour - slot.start.hour}h de disponibilité',
          style: TextStyle(
            fontSize: 12,
            color: pal.textMuted,
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
    final pal = _AvailPalette.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: pal.accent.withValues(alpha: 0.1),
              border: Border.all(
                color: pal.accent.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: Icon(Icons.schedule_rounded, size: 48, color: pal.accent),
          ),
          const SizedBox(height: 20),
          Text(
            'Aucun créneau défini',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: pal.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Ajoutez vos horaires de disponibilité.',
            textAlign: TextAlign.center,
            style: TextStyle(color: pal.textMuted, fontSize: 14),
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
  final VoidCallback onAddDates;
  final void Function(_Unavailability) onDelete;
  final Future<void> Function() onRefresh;

  const _UnavailabilityTab({
    required this.unavailabilities,
    required this.onAdd,
    required this.onAddDates,
    required this.onDelete,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final pal = _AvailPalette.of(context);
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
                  color: pal.danger.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.event_busy_rounded, color: pal.danger, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Bloquez des périodes où vous n\'êtes pas disponible.',
                  style: TextStyle(color: pal.textMuted, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onAddDates,
                  icon: const Icon(Icons.calendar_month_rounded, size: 20),
                  label: const Text('Dates précises'),
                  style: FilledButton.styleFrom(
                    backgroundColor: pal.danger,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: pal.isDark ? 4 : 0,
                    shadowColor: pal.danger.withValues(alpha: 0.35),
                    textStyle: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.date_range_rounded, size: 18),
                label: const Text('Période'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: pal.danger,
                  side: BorderSide(
                      color: pal.danger.withValues(alpha: 0.5)),
                  padding:
                      const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  textStyle:
                      const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
              ),
            ],
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
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
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
    final pal = _AvailPalette.of(context);
    final duration = u.dateTo.difference(u.dateFrom).inDays + 1;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            pal.unavailBgStart,
            pal.unavailBgEnd,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: pal.danger.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: BabifixDesign.elevationShadowSM(!pal.isDark),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: pal.danger.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: pal.danger.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Icon(Icons.event_busy_rounded, color: pal.danger, size: 22),
        ),
        title: Text(
          '${_fmt(u.dateFrom)} → ${_fmt(u.dateTo)}',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: pal.textPrimary,
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
                  style: TextStyle(
                    color: pal.textMuted,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: pal.danger.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$duration jour${duration > 1 ? 's' : ''}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: pal.danger,
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

// ─── Calendrier multi-sélection (jusqu'à ~2 mois) ────────────────────────────

class _MultiMonthCalendar extends StatefulWidget {
  final Set<DateTime> selected;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _MultiMonthCalendar({
    required this.selected,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  State<_MultiMonthCalendar> createState() => _MultiMonthCalendarState();
}

class _MultiMonthCalendarState extends State<_MultiMonthCalendar> {
  static const _moisFr = [
    'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin',
    'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre',
  ];
  late final DateTime _today;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _today = DateTime(n.year, n.month, n.day);
  }

  bool _isSel(DateTime d) => widget.selected
      .any((s) => s.year == d.year && s.month == d.month && s.day == d.day);

  void _toggle(DateTime d) {
    setState(() {
      final match = widget.selected
          .where((s) => s.year == d.year && s.month == d.month && s.day == d.day)
          .toList();
      if (match.isNotEmpty) {
        widget.selected.remove(match.first);
      } else {
        widget.selected.add(d);
      }
    });
  }

  List<DateTime> _months() {
    final base = DateTime(_today.year, _today.month, 1);
    return [
      base,
      DateTime(base.year, base.month + 1, 1),
      DateTime(base.year, base.month + 2, 1),
    ];
  }

  Widget _monthGrid(DateTime month, _AvailPalette pal) {
    final firstWeekday = DateTime(month.year, month.month, 1).weekday; // 1=Lun
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final cells = <Widget>[];
    for (var i = 1; i < firstWeekday; i++) {
      cells.add(const SizedBox());
    }
    for (var day = 1; day <= daysInMonth; day++) {
      final d = DateTime(month.year, month.month, day);
      final past = d.isBefore(_today);
      final sel = _isSel(d);
      cells.add(GestureDetector(
        onTap: past ? null : () => _toggle(d),
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: sel ? pal.danger : pal.softBg,
            borderRadius: BorderRadius.circular(8),
            border: sel ? null : Border.all(color: pal.border),
          ),
          alignment: Alignment.center,
          child: Text(
            '$day',
            style: TextStyle(
              color: past
                  ? pal.textMuted.withValues(alpha: 0.35)
                  : (sel ? Colors.white : pal.textPrimary),
              fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 6),
          child: Text(
            '${_moisFr[month.month - 1]} ${month.year}',
            style: TextStyle(
                color: pal.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 14),
          ),
        ),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.1,
          children: cells,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = _AvailPalette.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('Cochez les jours à bloquer',
              style: TextStyle(
                  color: pal.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: ['L', 'M', 'M', 'J', 'V', 'S', 'D']
                .map((d) => Expanded(
                      child: Center(
                        child: Text(d,
                            style: TextStyle(
                                color: pal.danger,
                                fontWeight: FontWeight.w800,
                                fontSize: 12)),
                      ),
                    ))
                .toList(),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
                children: _months().map((m) => _monthGrid(m, pal)).toList()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: widget.onCancel,
                  style: TextButton.styleFrom(foregroundColor: pal.textMuted),
                  child: const Text('Annuler'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: widget.onConfirm,
                  style: FilledButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: pal.danger,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    widget.selected.isEmpty
                        ? 'Confirmer'
                        : 'Bloquer ${widget.selected.length} date${widget.selected.length > 1 ? 's' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
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

class _EmptyStateUnavailability extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final pal = _AvailPalette.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: pal.danger.withValues(alpha: 0.1),
              border: Border.all(
                color: pal.danger.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: Icon(Icons.event_available_rounded, size: 48, color: pal.danger),
          ),
          const SizedBox(height: 20),
          Text(
            'Aucune période bloquée',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: pal.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Ajoutez vos congés ou indisponibilités ponctuelles.',
            style: TextStyle(color: pal.textMuted, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
