import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../shared/auth_utils.dart';

/// Écran permettant au prestataire d'évaluer le client après prestation.
class RateClientScreen extends StatefulWidget {
  final String reservationRef;
  final String clientName;
  final String? apiBase;
  final String? authToken;

  const RateClientScreen({
    super.key,
    required this.reservationRef,
    this.clientName = 'le client',
    this.apiBase,
    this.authToken,
  });

  @override
  State<RateClientScreen> createState() => _RateClientScreenState();
}

class _RateClientScreenState extends State<RateClientScreen>
    with TickerProviderStateMixin {
  int _note = 0;
  final _commentCtrl = TextEditingController();
  bool _submitting = false;
  bool _submitted = false;
  final List<AnimationController> _starCtrl = [];
  final List<Animation<double>> _starScale = [];

  String get _base => widget.apiBase ?? babifixApiBaseUrl();

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < 5; i++) {
      final ctrl = AnimationController(
        duration: const Duration(milliseconds: 400),
        vsync: this,
      );
      _starCtrl.add(ctrl);
      _starScale.add(
        Tween<double>(begin: 1.0, end: 1.0).animate(
          CurvedAnimation(parent: ctrl, curve: Curves.elasticOut),
        ),
      );
    }
  }

  @override
  void dispose() {
    for (final c in _starCtrl) c.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  void _tapStar(int starIndex) {
    setState(() => _note = starIndex + 1);
    for (int i = 0; i <= starIndex; i++) {
      Future.delayed(Duration(milliseconds: i * 50), () {
        if (!mounted) return;
        _starCtrl[i].forward(from: 0);
      });
    }
  }

  Future<String?> _token() async {
    if (widget.authToken != null && widget.authToken!.isNotEmpty) {
      return widget.authToken;
    }
    return readStoredApiToken();
  }

  Future<void> _submit() async {
    if (_note == 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sélectionnez une note.')));
      return;
    }
    setState(() => _submitting = true);
    final token = await _token();
    try {
      final res = await http.post(
        Uri.parse(
          '$_base/api/prestataire/reservations/${widget.reservationRef}/rate-client',
        ),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'note': _note,
          'commentaire': _commentCtrl.text.trim(),
        }),
      );
      if (res.statusCode == 200) {
        setState(() {
          _submitted = true;
          _submitting = false;
        });
      } else {
        final err = jsonDecode(res.body)['error'] ?? 'Erreur';
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Impossible : $err')));
        }
        setState(() => _submitting = false);
      }
    } catch (_) {
      setState(() => _submitting = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Erreur réseau.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Évaluer le client'),
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: _submitted
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: BabifixDesign.success.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: BabifixDesign.success,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Merci !',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Votre avis a bien été enregistré.',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 28),
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: BabifixDesign.ciOrange,
                      ),
                      child: const Text('Retour'),
                    ),
                  ],
                ),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Column(
                      children: [
                        const Icon(
                          Icons.person_rounded,
                          size: 52,
                          color: BabifixDesign.ciOrange,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Comment était ${widget.clientName} ?',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        Text(
                          widget.reservationRef,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Note',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) {
                      final filled = i < _note;
                      return GestureDetector(
                        onTap: () => _tapStar(i),
                        child: AnimatedBuilder(
                          animation: _starCtrl[i],
                          builder: (_, child) {
                            final t = _starCtrl[i].value;
                            final bounce = 1.0 + 0.35 * math.sin(t * math.pi);
                            return Transform.scale(
                              scale: t > 0 ? bounce : 1.0,
                              child: child,
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(
                              filled ? Icons.star_rounded : Icons.star_border_rounded,
                              color: filled ? Colors.amber : Colors.grey,
                              size: 42,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Commentaire (optionnel)',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _commentCtrl,
                    maxLines: 3,
                    maxLength: 500,
                    decoration: InputDecoration(
                      hintText: 'Ponctualité, respect, paiement…',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          BabifixDesign.radiusMD,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: _submitting ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: BabifixDesign.ciOrange,
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Envoyer',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
