import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../babifix_design_system.dart';
import '../services/nominatim_geocode.dart';
import 'babifix_ring_loader.dart';

class BabifixAddressSearchField extends StatefulWidget {
  const BabifixAddressSearchField({
    super.key,
    required this.controller,
    required this.onPlaceSelected,
    this.minChars = 2,
    this.debounce = const Duration(milliseconds: 350),
  });

  final TextEditingController controller;
  final void Function(LatLng coordinates, String addressLabel) onPlaceSelected;
  final int minChars;
  final Duration debounce;

  @override
  State<BabifixAddressSearchField> createState() =>
      _BabifixAddressSearchFieldState();
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
          _emptyHint = list.isEmpty
              ? 'Aucun résultat : saisissez une commune (Cocody, Marcory, Yopougon...)'
              : null;
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
    widget.controller.selection =
        TextSelection.collapsed(offset: p.displayName.length);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fieldBg = isDark ? const Color(0xFF081220) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final hintColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final borderColor =
        isDark ? const Color(0xFF1E3250) : const Color(0xFFCBD5E1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          maxLines: 1,
          textCapitalization: TextCapitalization.sentences,
          style: TextStyle(
            color: textColor,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          onChanged: _onTextChanged,
          decoration: InputDecoration(
            hintText: 'Ex. : Cocody · Deux Plateaux, Marcory, Yopougon...',
            hintStyle: TextStyle(
              color: hintColor,
              fontSize: 13.5,
              fontWeight: FontWeight.w400,
            ),
            prefixIcon: const Icon(
              Icons.place_rounded,
              color: Color(0xFF38BDF8),
              size: 20,
            ),
            filled: true,
            fillColor: fieldBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: BabifixDesign.cyan, width: 1.8),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: BabifixRingLoader.cyan(size: 20),
                    ),
                  )
                : (widget.controller.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: hintColor,
                        ),
                        tooltip: 'Effacer',
                        onPressed: () {
                          widget.controller.clear();
                          _onTextChanged('');
                        },
                      )
                    : null),
          ),
        ),
        if (_error != null && _suggestions.isEmpty && !_loading)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text(
              _error!,
              style: const TextStyle(fontSize: 12, color: Color(0xFFF87171)),
            ),
          ),
        if (_emptyHint != null &&
            _suggestions.isEmpty &&
            !_loading &&
            _error == null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text(
              _emptyHint!,
              style: TextStyle(fontSize: 12, color: hintColor),
            ),
          ),
        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Material(
            elevation: 6,
            shadowColor: Colors.black54,
            borderRadius: BorderRadius.circular(14),
            color: isDark ? const Color(0xFF0E1A2D) : Colors.white,
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < _suggestions.length; i++) ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: borderColor.withValues(alpha: 0.6),
                        ),
                      InkWell(
                        onTap: () => _pick(_suggestions[i]),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.location_on_rounded,
                                size: 20,
                                color: Color(0xFF38BDF8),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _suggestions[i].displayName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: textColor,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.north_west_rounded,
                                size: 16,
                                color: hintColor,
                              ),
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
