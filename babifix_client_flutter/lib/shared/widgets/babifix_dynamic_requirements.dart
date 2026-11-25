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
///     "key":   "surface_m2",        // requis : cle de la reponse
///     "label": "Surface (m²)",      // requis : libelle affiche
///     "type":  "number",            // text | number | select | bool
///     "choices": ["A","B"],         // pour select
///     "required": true,              // optionnel (défaut false)
///     "unit": "m²",                 // optionnel (suffixe)
///     "hint": "Ex. 25"               // optionnel (placeholder)
///   }
/// ─────────────────────────────────────────────────────────────────────────
class BabifixDynamicRequirements extends StatefulWidget {
  const BabifixDynamicRequirements({
    super.key,
    required this.template,
    required this.answers,
    required this.onChanged,
    this.profil = '',
    this.demandeType = '',
  });

  /// Liste de questions (voir en-tête). Peut être vide.
  final List<Map<String, dynamic>> template;

  /// Profil de devis de la catégorie (STANDARD/SURFACE/FORFAIT/DIAGNOSTIC).
  /// Pour SURFACE, un assistant de calcul de m² s'affiche.
  final String profil;

  /// Type de demande courant (panne/maintenance/renovation…). Sert à filtrer
  /// les questions déclarant une liste `types` : elles ne s'affichent que si
  /// le type courant y figure. Une question sans `types` s'affiche toujours.
  final String demandeType;

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

  // Assistant de surface (profil SURFACE).
  final _lenCtrl = TextEditingController();
  final _widCtrl = TextEditingController();
  final _heightCtrl = TextEditingController(text: '2.8');
  String _calcMode = 'sol'; // 'sol' (L×l) | 'murs' (2·(L+l)·H)

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _lenCtrl.dispose();
    _widCtrl.dispose();
    _heightCtrl.dispose();
    super.dispose();
  }

  /// Clé cible pour l'assistant de surface : `surface_m2` en priorité, sinon
  /// le premier champ numérique dont l'unité contient « m² ».
  String? get _surfaceTargetKey {
    for (final q in widget.template) {
      if ((q['key'] ?? '').toString() == 'surface_m2') return 'surface_m2';
    }
    for (final q in widget.template) {
      final unit = (q['unit'] ?? '').toString().toLowerCase();
      final type = (q['type'] ?? '').toString().toLowerCase();
      if (type == 'number' && unit.contains('m²')) {
        return (q['key'] ?? '').toString();
      }
    }
    return null;
  }

  double? _num(TextEditingController c) {
    final t = c.text.replaceAll(',', '.').trim();
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  double? get _computedSurface {
    final l = _num(_lenCtrl);
    final w = _num(_widCtrl);
    if (l == null || w == null || l <= 0 || w <= 0) return null;
    if (_calcMode == 'murs') {
      final h = _num(_heightCtrl) ?? 2.8;
      return 2 * (l + w) * h;
    }
    return l * w;
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

  /// Reporte une surface calculée/preset dans le champ cible + son contrôleur.
  void _applySurface(double value) {
    final key = _surfaceTargetKey;
    if (key == null || key.isEmpty) return;
    final rounded = value >= 100 ? value.round().toString() : value.toStringAsFixed(1);
    _controllerFor(key).text = rounded;
    setState(() => _set(key, rounded));
  }

  String _typeOf(Map<String, dynamic> q) =>
      (q['type'] ?? 'text').toString().toLowerCase();

  @override
  Widget build(BuildContext context) {
    final valid = widget.template
        .where((q) => (q['key'] ?? '').toString().isNotEmpty)
        .where((q) => babifixQuestionMatchesType(q, widget.demandeType))
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
        if (widget.profil.toUpperCase() == 'SURFACE' &&
            _surfaceTargetKey != null) ...[
          _buildSurfaceAssistant(),
          const SizedBox(height: 16),
        ],
        for (final q in valid) ...[
          _buildQuestion(q),
          const SizedBox(height: 14),
        ],
      ],
    );
  }

  // Presets de surface au sol (m²) — repères logement Côte d'Ivoire.
  static const List<(String, double)> _surfacePresets = [
    ('Studio', 20),
    ('2 pièces', 45),
    ('3 pièces', 70),
    ('4 pièces +', 95),
    ('Villa', 140),
  ];

  Widget _buildSurfaceAssistant() {
    final computed = _computedSurface;
    final isDark = BabifixDesign.isDark(context);
    final ink = BabifixDesign.textPrimaryOf(context);
    final muted = BabifixDesign.textMutedOf(context);
    final accent = isDark ? BabifixDesign.cyan : BabifixDesign.cyanDeep;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isDark ? 0.12 : 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.34)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.square_foot_rounded, size: 18, color: accent),
              const SizedBox(width: 6),
              Text(
                'Aide au calcul de la surface',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Pas besoin d\'être exact, une mesure approximative suffit pour le devis.',
            style: TextStyle(fontSize: 11.5, color: muted),
          ),
          const SizedBox(height: 10),
          // Presets rapides.
          Text(
            'Reperes rapides',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: muted,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in _surfacePresets)
                ActionChip(
                  label: Text('${p.$1} · ~${p.$2.round()} m²'),
                  onPressed: () => _applySurface(p.$2),
                  backgroundColor: BabifixDesign.surfaceOf(context),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: ink,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: BabifixDesign.borderOf(context)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Calculateur dimensions.
          Row(
            children: [
              Text(
                'Calculer',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: muted,
                ),
              ),
              const SizedBox(width: 10),
              _modeChip('Sol', 'sol'),
              const SizedBox(width: 6),
              _modeChip('Murs', 'murs'),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _dimField(_lenCtrl, 'Longueur', 'm')),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text('×', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
              Expanded(child: _dimField(_widCtrl, 'Largeur', 'm')),
              if (_calcMode == 'murs') ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child:
                      Text('×', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
                Expanded(child: _dimField(_heightCtrl, 'Hauteur', 'm')),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  computed == null
                      ? (_calcMode == 'murs'
                          ? 'Surface des murs : 2 × (L + l) × H'
                          : 'Surface au sol : L × l')
                      : '≈ ${computed >= 100 ? computed.round() : computed.toStringAsFixed(1)} m²',
                  style: TextStyle(
                    fontSize: computed == null ? 11.5 : 15,
                    fontWeight:
                        computed == null ? FontWeight.w500 : FontWeight.w800,
                    color: computed == null ? muted : ink,
                  ),
                ),
              ),
              FilledButton(
                onPressed: computed == null
                    ? null
                    : () => _applySurface(computed),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: isDark ? BabifixDesign.navy : Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Reporter',
                    style: TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _modeChip(String label, String value) {
    final sel = _calcMode == value;
    final isDark = BabifixDesign.isDark(context);
    final accent = isDark ? BabifixDesign.cyan : BabifixDesign.cyanDeep;
    return GestureDetector(
      onTap: () => setState(() => _calcMode = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: sel ? accent : BabifixDesign.surfaceOf(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: sel ? accent : BabifixDesign.borderOf(context),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: sel
                ? (isDark ? BabifixDesign.navy : Colors.white)
                : BabifixDesign.textMutedOf(context),
          ),
        ),
      ),
    );
  }

  Widget _dimField(TextEditingController c, String hint, String unit) {
    return TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      onChanged: (_) => setState(() {}),
      decoration: _decoration(hint, unit),
    );
  }

  Widget _buildQuestion(Map<String, dynamic> q) {
    final key = q['key'].toString();
    final label = (q['label'] ?? key).toString();
    final required = q['required'] == true;
    final unit = (q['unit'] ?? '').toString();
    final hint = (q['hint'] ?? '').toString();
    final type = _typeOf(q);

    final ink = BabifixDesign.textPrimaryOf(context);
    final labelWidget = RichText(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: ink,
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
        final isDark = BabifixDesign.isDark(context);
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
                    selectedColor: isDark
                        ? const Color(0xFF0E3B2E)
                        : const Color(0xFFE6F4EF),
                    labelStyle: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: current == c
                          ? (isDark ? Colors.white : const Color(0xFF0E3B2E))
                          : (isDark
                              ? const Color(0xFFCBD5E1)
                              : const Color(0xFF334155)),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: current == c
                            ? const Color(0xFF0E3B2E)
                            : (isDark
                                ? const Color(0xFF334155)
                                : const Color(0xFFCBD5E1)),
                      ),
                    ),
                    backgroundColor: isDark
                        ? const Color(0xFF0F1F38)
                        : Colors.white,
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

    final currentText = (widget.answers[key] ?? '').toString().trim();
    const unknownText = "Je ne sais pas (l'artisan verifiera)";
    final isUnknownSelected = currentText == unknownText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        labelWidget,
        const SizedBox(height: 6),
        field,
        if (!required && (type == 'number' || type == 'text')) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                final ctl = _controllerFor(key);
                setState(() {
                  if (isUnknownSelected) {
                    ctl.clear();
                    _set(key, '');
                  } else {
                    ctl.text = type == 'number' ? '' : unknownText;
                    _set(key, unknownText);
                  }
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isUnknownSelected
                      ? const Color(0xFF0E3B2E).withValues(alpha: 0.14)
                      : BabifixDesign.elevatedSurfaceOf(context),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isUnknownSelected
                        ? const Color(0xFF0E3B2E)
                        : BabifixDesign.borderOf(context),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isUnknownSelected
                          ? Icons.check_circle_rounded
                          : Icons.help_outline_rounded,
                      size: 14,
                      color: isUnknownSelected
                          ? const Color(0xFF0E3B2E)
                          : BabifixDesign.textMutedOf(context),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      "Je ne sais pas · L'artisan verifiera",
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: isUnknownSelected
                            ? const Color(0xFF0E3B2E)
                            : BabifixDesign.textMutedOf(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  InputDecoration _decoration(String hint, String unit) {
    final isDark = BabifixDesign.isDark(context);
    final fill = BabifixDesign.elevatedSurfaceOf(context);
    final border = BabifixDesign.borderOf(context);
    final muted = BabifixDesign.textMutedOf(context);
    final accent = isDark ? BabifixDesign.cyan : BabifixDesign.cyanDeep;
    return InputDecoration(
      hintText: hint.isEmpty ? null : hint,
      hintStyle: TextStyle(color: muted),
      suffixText: unit.isEmpty ? null : unit,
      suffixStyle: TextStyle(color: muted, fontWeight: FontWeight.w600),
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      filled: true,
      fillColor: fill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: accent, width: 1.5),
      ),
    );
  }
}

/// Une question s'applique au type de demande courant si elle ne déclare pas
/// de liste `types`, ou si [demandeType] y figure. Liste vide/absente = toujours.
bool babifixQuestionMatchesType(Map<String, dynamic> q, String demandeType) {
  final raw = q['types'];
  if (raw is! List || raw.isEmpty) return true;
  if (demandeType.isEmpty) return true; // type non précisé → on n'exclut rien
  return raw.map((e) => e.toString().toLowerCase()).contains(
        demandeType.toLowerCase(),
      );
}

/// Vérifie que toutes les questions `required` du template (applicables au
/// type courant) ont une réponse non vide dans [answers]. Renvoie la liste des
/// libellés manquants.
List<String> babifixMissingRequirements(
  List<Map<String, dynamic>> template,
  Map<String, dynamic> answers, {
  String demandeType = '',
}) {
  final missing = <String>[];
  for (final q in template) {
    if (q['required'] != true) continue;
    if (!babifixQuestionMatchesType(q, demandeType)) continue;
    final key = (q['key'] ?? '').toString();
    if (key.isEmpty) continue;
    final v = answers[key];
    final empty = v == null || (v is String && v.trim().isEmpty);
    if (empty) missing.add((q['label'] ?? key).toString());
  }
  return missing;
}
