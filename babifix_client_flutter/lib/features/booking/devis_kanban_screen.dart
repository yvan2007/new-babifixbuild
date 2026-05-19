/// Écran "Détail devis" (Phase A + C1).
///
/// Affichage Kanban professionnel du devis reçu :
/// - rendu via [DevisCardWidget],
/// - actions Accepter / Refuser (avec motif),
/// - timeline 8 étapes,
/// - bouton "Procéder au paiement" qui ouvre l'écran escrow C5.
import 'package:flutter/material.dart';

import '../../babifix_design_system.dart';
import '../../models/babifix_models.dart';
import '../../services/babifix_api.dart';
import '../../shared/widgets/babifix_phase_widgets.dart';
import 'escrow_quote_screen.dart';
import '../../shared/widgets/babifix_ring_loader.dart';

class DevisKanbanScreen extends StatefulWidget {
  final String reservationReference;
  final Map<String, dynamic>? reservationInfo;

  const DevisKanbanScreen({
    super.key,
    required this.reservationReference,
    this.reservationInfo,
  });

  @override
  State<DevisKanbanScreen> createState() => _DevisKanbanScreenState();
}

class _DevisKanbanScreenState extends State<DevisKanbanScreen> {
  Devis? _devis;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await DevisApi.get(widget.reservationReference);
      setState(() {
        _devis = d;
        _loading = false;
      });
    } on BabifixApiException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      await DevisApi.accept(widget.reservationReference);
      if (!mounted) return;
      // Enchaîner vers le paiement escrow.
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EscrowQuoteScreen(
            reservationReference: widget.reservationReference,
          ),
        ),
      );
      if (mounted) await _load();
    } on BabifixApiException catch (e) {
      _snack('Acceptation refusée : ${e.message}');
    } catch (e) {
      _snack('Erreur : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refuse() async {
    final controller = TextEditingController();
    final motif = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Refuser ce devis'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Motif (facultatif)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: BabifixDesign.error,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Refuser'),
          ),
        ],
      ),
    );
    if (motif == null) return;

    setState(() => _busy = true);
    try {
      await DevisApi.refuse(widget.reservationReference, motif: motif);
      if (mounted) {
        _snack('Devis refusé');
        Navigator.of(context).pop(true);
      }
    } on BabifixApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Détail du devis'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: _loading
          ? const Center(child: BabifixRingLoader.dark(size: 80))
          : _error != null
              ? _errorView()
              : _devis == null
                  ? _empty()
                  : _content(_devis!),
      bottomNavigationBar: _devis == null ? null : _actionsBar(_devis!),
    );
  }

  Widget _errorView() => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 56, color: BabifixDesign.error),
              const SizedBox(height: 12),
              Text(_error ?? '', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _load,
                child: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );

  Widget _empty() => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            "Aucun devis disponible pour cette demande pour l'instant.",
            textAlign: TextAlign.center,
          ),
        ),
      );

  Widget _content(Devis devis) {
    final stat = (widget.reservationInfo?['statut'] ?? 'DEVIS_ENVOYE').toString();
    final acompteValide = widget.reservationInfo?['acompte_valide'] == true;
    final steps = buildReservationTimeline(
      currentStatut: stat,
      acompteValide: acompteValide,
    );
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // Header rappel
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: BabifixDesign.ciBlue.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: BabifixDesign.ciBlue.withValues(alpha: 0.20)),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline,
                  color: BabifixDesign.ciBlue, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Le prestataire vous a envoyé un devis structuré. '
                  'Accepter ouvrira le paiement de l\'acompte.',
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey.shade800),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        DevisCardWidget(devis: devis),
        const SizedBox(height: 14),
        Text('Suivi de la demande',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade800)),
        const SizedBox(height: 8),
        TimelineReservationWidget(steps: steps),
        const SizedBox(height: 100),
      ],
    );
  }

  Widget _actionsBar(Devis devis) {
    final canAct = devis.statut == DevisStatus.envoye;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: canAct
            ? Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _refuse,
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Refuser'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: BabifixDesign.error,
                        side: BorderSide(color: BabifixDesign.error),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _busy ? null : _accept,
                      icon: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: BabifixRingLoader.cyan(size: 28))
                          : const Icon(Icons.check, size: 18),
                      label: const Text('Accepter & payer'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: BabifixDesign.ciBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              )
            : Center(
                child: Text(
                  'Devis ${devis.statut.label.toLowerCase()}',
                  style: TextStyle(
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600),
                ),
              ),
      ),
    );
  }
}
