import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../babifix_design_system.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// Formulaire d'exigences DYNAMIQUE (Phase 2 — devis intelligent).
///
/// Rend une liste de questions décrites par la catégorie
/// (`Category.template_exigences`, renvoyée par
/// `GET /api/providers/<id>/requirements/`) et remonte les réponses via
/// [onChanged]. Si le template est vide, le widget ne rend RIEN → l'écran
/// garde son formulaire habituel (rétrocompatible).
///
/// Chaque question est un map JSON :
///   {
///     "key":   "surface_m2",         // requis — clé de la réponse
///     "label": "Surface (m²)",       // requis — libellé affiché
///     "type":  "number",             // text | number | select | bool
///     "choices": ["A","B"],          // pour select
///     "required": true,               // optionnel (défaut false)
///     "unit": "m²",                  // optionnel (suffixe)
///     "hint": "Ex. 25"               // optionnel (placeholder)
///   }
/// ─────────────────────────────────────────────────────────────────────────
class BabifixDynamicRequirements extends StatefulWidget {
  const BabifixDynamicRequirements({
    super.key,
    required this.template,
    required this.answers,
    required this.onChanged,
  });

  /// Liste de questions (voir en-tête). Peut être vide.
  final List<Map<String, dynamic>> template;

  /// Réponses courantes (persistées par le parent pour survivre aux rebuilds).
  final Map<String, dynamic> answers;

  /// Appelé à chaque modification avec la map complète des réponses.
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  State<BabifixDynamicRequirements> createState() =>
      _BabifixDynamicRequirementsState();
}

class _BabifixDynamicRequirementsState
    extends State<BabifixDynamicRequirements> {
  final Map<String, TextEditingController> _controllers = {};

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String key) {
    return _controllers.putIfAbsent(
      key,
      () => TextEditingController(text: '${widget.answers[key] ?? ''}'),
    );
  }

  void _set(String key, dynamic value) {
    widget.answers[key] = value;
    widget.onChanged(Map<String, dynamic>.from(widget.answers));
  }

  String _typeOf(Map<String, dynamic> q) =>
      (q['type'] ?? 'text').toString().toLowerCase();

  @override
  Widget build(BuildContext context) {
    final valid = widget.template
        .where((q) => (q['key'] ?? '').toString().isNotEmpty)
        .toList();
    if (valid.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.assignment_outlined,
                size: 18, color: BabifixDesign.cyan),
            SizedBox(width: 6),
            Text(
              'Précisez votre besoin',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: BabifixDesign.navy,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Ces détails aident le prestataire à chiffrer plus juste.',
          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 12),
        for (final q in valid) ...[
          _buildQuestion(q),
          const SizedBox(height: 14),
        ],
      ],
    );
  }

  Widget _buildQuestion(Map<String, dynamic> q) {
    final key = q['key'].toString();
    final label = (q['label'] ?? key).toString();
    final required = q['required'] == true;
    final unit = (q['unit'] ?? '').toString();
    final hint = (q['hint'] ?? '').toString();
    final type = _typeOf(q);

    final labelWidget = RichText(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: BabifixDesign.navy,
        ),
        children: required
            ? const [
                TextSpan(
                  text: ' *',
                  style: TextStyle(color: Color(0xFFEF4444)),
                ),
              ]
            : const [],
      ),
    );

    Widget field;
    switch (type) {
      case 'bool':
        final v = widget.answers[key] == true;
        field = Row(
          children: [
            Expanded(child: labelWidget),
            Switch(
              value: v,
              activeThumbColor: BabifixDesign.cyan,
              onChanged: (nv) => setState(() => _set(key, nv)),
            ),
          ],
        );
        return field;
      case 'select':
        final choices = (q['choices'] as List?)
                ?.map((e) => e.toString())
                .where((e) => e.isNotEmpty)
                .toList() ??
            const <String>[];
        final current = widget.answers[key]?.toString();
        field = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            labelWidget,
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in choices)
                  ChoiceChip(
                    label: Text(c),
                    selected: current == c,
                    onSelected: (_) => setState(() => _set(key, c)),
                    selectedColor: BabifixDesign.cyan.withValues(alpha: 0.18),
                    labelStyle: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: current == c
                          ? BabifixDesign.navy
                          : const Color(0xFF475569),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: current == c
                            ? BabifixDesign.cyan
                            : const Color(0xFFCBD5E1),
                      ),
                    ),
                    backgroundColor: Colors.white,
                  ),
              ],
            ),
          ],
        );
        return field;
      case 'number':
        field = TextField(
          controller: _controllerFor(key),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          onChanged: (v) => _set(key, v.replaceAll(',', '.').trim()),
          decoration: _decoration(hint, unit),
        );
        break;
      default: // text
        field = TextField(
          controller: _controllerFor(key),
          textCapitalization: TextCapitalization.sentences,
          onChanged: (v) => _set(key, v.trim()),
          decoration: _decoration(hint, unit),
        );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        labelWidget,
        const SizedBox(height: 6),
        field,
      ],
    );
  }

  InputDecoration _decoration(String hint, String unit) => InputDecoration(
        hintText: hint.isEmpty ? null : hint,
        suffixText: unit.isEmpty ? null : unit,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: BabifixDesign.cyan, width: 1.5),
        ),
      );
}

/// Vérifie que toutes les questions `required` du template ont une réponse
/// non vide dans [answers]. Renvoie la liste des libellés manquants.
List<String> babifixMissingRequirements(
  List<Map<String, dynamic>> template,
  Map<String, dynamic> answers,
) {
  final missing = <String>[];
  for (final q in template) {
    if (q['required'] != true) continue;
    final key = (q['key'] ?? '').toString();
    if (key.isEmpty) continue;
    final v = answers[key];
    final empty = v == null || (v is String && v.trim().isEmpty);
    if (empty) missing.add((q['label'] ?? key).toString());
  }
  return missing;
}
