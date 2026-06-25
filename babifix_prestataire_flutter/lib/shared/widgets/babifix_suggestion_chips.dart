import 'package:flutter/material.dart';

/// Chips de suggestion : des « bulles » de texte pré-écrites qu'on tape pour
/// les insérer (ou retirer) dans un champ texte. Pratique pour aider à remplir
/// un commentaire, une description, un motif… sans tout taper soi-même.
///
/// Tap = ajoute la phrase au champ (et surligne la bulle) ; re-tap = la retire.
class BabifixSuggestionChips extends StatefulWidget {
  const BabifixSuggestionChips({
    super.key,
    required this.controller,
    required this.suggestions,
    this.accent = const Color(0xFF4CC9F0),
    this.separator = ', ',
    this.title,
    this.onChanged,
  });

  final TextEditingController controller;
  final List<String> suggestions;
  final Color accent;

  /// Appelé après chaque ajout/retrait (utile pour rafraîchir un bouton parent
  /// dont l'état dépend du texte, ex. « envoyer » actif si ≥ N caractères).
  final VoidCallback? onChanged;

  /// Séparateur inséré entre deux suggestions (ex. ', ' ou '. ').
  final String separator;

  /// Petit libellé optionnel au-dessus des bulles (ex. « Suggestions »).
  final String? title;

  @override
  State<BabifixSuggestionChips> createState() => _BabifixSuggestionChipsState();
}

class _BabifixSuggestionChipsState extends State<BabifixSuggestionChips> {
  bool _has(String s) {
    final t = widget.controller.text.toLowerCase();
    return t.contains(s.toLowerCase());
  }

  void _toggle(String s) {
    var text = widget.controller.text;
    if (_has(s)) {
      // Retire la phrase + un éventuel séparateur adjacent.
      final patterns = [
        '${widget.separator}$s',
        '$s${widget.separator}',
        s,
      ];
      for (final p in patterns) {
        final idx = text.toLowerCase().indexOf(p.toLowerCase());
        if (idx != -1) {
          text = text.replaceRange(idx, idx + p.length, '');
          break;
        }
      }
    } else {
      final base = text.trimRight();
      text = base.isEmpty ? s : '$base${widget.separator}$s';
    }
    widget.controller.text = text.trimLeft();
    widget.controller.selection = TextSelection.fromPosition(
      TextPosition(offset: widget.controller.text.length),
    );
    widget.onChanged?.call();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.title != null) ...[
          Text(
            widget.title!,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: widget.accent,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: widget.suggestions.map((s) {
            final sel = _has(s);
            return GestureDetector(
              onTap: () => _toggle(s),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: sel
                      ? widget.accent.withValues(alpha: 0.16)
                      : widget.accent.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: widget.accent
                        .withValues(alpha: sel ? 0.8 : 0.25),
                    width: sel ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      sel ? Icons.check_rounded : Icons.add_rounded,
                      size: 14,
                      color: widget.accent,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      s,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: sel ? FontWeight.w700 : FontWeight.w600,
                        color: widget.accent,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
