import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../babifix_design_system.dart';
import '../services/nominatim_geocode.dart';

class BabifixAddressSearchField extends StatefulWidget {
  const BabifixAddressSearchField({
    super.key,
    required this.controller,
    required this.onPlaceSelected,
    this.minChars = 3,
    this.debounce = const Duration(milliseconds: 450),
  });

  final TextEditingController controller;
  final void Function(LatLng coordinates, String addressLabel) onPlaceSelected;
  final int minChars;
  final Duration debounce;

  @override
  State<BabifixAddressSearchField> createState() => _BabifixAddressSearchFieldState();
}

class _BabifixAddressSearchFieldState extends State<BabifixAddressSearchField> {
  Timer? _debounce;
  List<NominatimPlace> _suggestions = [];
  bool _loading = false;
  String? _error;
  String? _emptyHint;
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged(String value) {
    _debounce?.cancel();
    final t = value.trim();
    if (t.length < widget.minChars) {
      setState(() {
        _suggestions = [];
        _loading = false;
        _error = null;
        _emptyHint = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _emptyHint = null;
    });
    _debounce = Timer(widget.debounce, () async {
      try {
        final list = await nominatimSearch(t);
        if (!mounted) return;
        setState(() {
          _suggestions = list;
          _loading = false;
          _error = null;
          _emptyHint = list.isEmpty ? 'Aucun résultat — précisez ville ou quartier' : null;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _suggestions = [];
          _loading = false;
          _error = 'Recherche indisponible';
          _emptyHint = null;
        });
      }
    });
  }

  void _pick(NominatimPlace p) {
    widget.controller.text = p.displayName;
    widget.controller.selection = TextSelection.collapsed(offset: p.displayName.length);
    widget.onPlaceSelected(LatLng(p.latitude, p.longitude), p.displayName);
    setState(() {
      _suggestions = [];
      _loading = false;
      _error = null;
      _emptyHint = null;
    });
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          onChanged: _onTextChanged,
          decoration: InputDecoration(
            hintText: 'Rechercher ville, commune, quartier…',
            prefixIcon: Icon(Icons.place_outlined, color: BabifixDesign.cyan),
            filled: true,
            fillColor: cs.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: theme.dividerColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: theme.dividerColor.withValues(alpha: 0.6)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: BabifixDesign.cyan, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
        ),
        if (_error != null && _suggestions.isEmpty && !_loading)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text(
              _error!,
              style: TextStyle(fontSize: 12, color: cs.error.withValues(alpha: 0.9)),
            ),
          ),
        if (_emptyHint != null && _suggestions.isEmpty && !_loading && _error == null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text(
              _emptyHint!,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Material(
            elevation: 6,
            shadowColor: Colors.black38,
            borderRadius: BorderRadius.circular(16),
            color: cs.surface,
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < _suggestions.length; i++) ...[
                      if (i > 0)
                        Divider(height: 1, thickness: 1, color: theme.dividerColor.withValues(alpha: 0.5)),
                      InkWell(
                        onTap: () => _pick(_suggestions[i]),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.place_rounded, size: 22, color: BabifixDesign.cyan),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _suggestions[i].displayName,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13, height: 1.3),
                                ),
                              ),
                              Icon(Icons.north_west_rounded, size: 18, color: cs.onSurfaceVariant),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
