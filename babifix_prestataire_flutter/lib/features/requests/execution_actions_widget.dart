/// Widget d'actions cycle exécution prestataire (Phase E — P3).
///
/// - Bouton "Démarrer" : appelle ReservationApi.demarrer, gère HTTP 409
///   acompte_required avec un dialogue clair.
/// - Bouton "Photos avant" / "Photos après" → ouvre l'uploader (P8).
/// - Bouton "Terminer" : exige au moins 1 photo après.
///
/// Le widget connaît l'état escrow via [EscrowQuote] et désactive les
/// actions impossibles.
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../babifix_design_system.dart';
import '../../models/babifix_models.dart';
import '../../services/babifix_api.dart';
import '../../shared/widgets/babifix_phase_widgets.dart';

class ExecutionActionsWidget extends StatefulWidget {
  final String reservationReference;
  final String statut;
  final List<String> photosAvant;
  final List<String> photosApres;
  final VoidCallback? onChanged;

  const ExecutionActionsWidget({
    super.key,
    required this.reservationReference,
    required this.statut,
    this.photosAvant = const [],
    this.photosApres = const [],
    this.onChanged,
  });

  @override
  State<ExecutionActionsWidget> createState() =>
      _ExecutionActionsWidgetState();
}

class _ExecutionActionsWidgetState extends State<ExecutionActionsWidget> {
  EscrowQuote? _quote;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadQuote();
  }

  Future<void> _loadQuote() async {
    try {
      _quote = await EscrowApi.quote(widget.reservationReference);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _demarrer() async {
    setState(() => _busy = true);
    try {
      final r = await ReservationApi.demarrer(widget.reservationReference);
      if (r['error'] == 'acompte_required') {
        if (!mounted) return;
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            icon:
                Icon(Icons.lock_outline, color: BabifixDesign.error, size: 56),
            title: const Text('Acompte non versé'),
            content: Text(
              "Le client n'a pas encore versé l'acompte. "
              "Vous ne pouvez pas démarrer l'intervention.\n\n"
              "Montant attendu : ${(r['amount_due_online'] as num?)?.toInt() ?? 0} F CFA",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }
      _snack('Intervention démarrée');
      widget.onChanged?.call();
      await _loadQuote();
    } on BabifixApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uploadPhotos(String type) async {
    final picker = ImagePicker();
    final files = await picker.pickMultiImage(imageQuality: 70);
    if (files.isEmpty) return;
    setState(() => _busy = true);
    try {
      // B7 — Upload chaque fichier via MediaApi → renvoie une URL
      // canonique (/media/babifix_uploads/...). Stockée dans
      // photos_avant/photos_apres pour affichage classique.
      final urls = <String>[];
      for (final f in files) {
        try {
          final url = await MediaApi.uploadFile(f.path);
          if (url.isNotEmpty) urls.add(url);
        } catch (e) {
          _snack('Échec upload d\'une photo : $e');
        }
      }
      if (urls.isEmpty) {
        _snack('Aucune photo uploadée.');
        return;
      }
      await ReservationApi.uploadPhotos(
        widget.reservationReference,
        type: type,
        photos: urls,
      );
      _snack('${urls.length} photo(s) envoyée(s)');
      widget.onChanged?.call();
    } catch (e) {
      _snack('Erreur upload : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _terminer() async {
    if (widget.photosApres.isEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Aucune photo après'),
          content: const Text(
            "Vous n'avez ajouté aucune photo après intervention. "
            'Le client risque de refuser la confirmation. Continuer ?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Ajouter d\'abord'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Terminer quand même'),
            ),
          ],
        ),
      );
      if (go != true) return;
    }
    setState(() => _busy = true);
    try {
      await ReservationApi.terminer(widget.reservationReference);
      _snack('Travaux marqués terminés. Le client doit confirmer.');
      widget.onChanged?.call();
    } on BabifixApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final s = widget.statut;
    final canStart = s == 'DEVIS_ACCEPTE' && (_quote?.acompteValide ?? false);
    final canFinish = s == 'INTERVENTION_EN_COURS';
    final acompteEnAttente = s == 'DEVIS_ACCEPTE' &&
        !(_quote?.acompteValide ?? false);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_quote != null)
            EscrowStatusBadge.fromQuote(_quote!),
          if (acompteEnAttente) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.hourglass_top,
                      color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'En attente du versement de l\'acompte par le client.',
                      style: TextStyle(
                          color: Colors.orange.shade900, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (canStart)
            ElevatedButton.icon(
              onPressed: _busy ? null : _demarrer,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Démarrer l\'intervention'),
              style: ElevatedButton.styleFrom(
                backgroundColor: BabifixDesign.ciGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          if (canFinish) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        _busy ? null : () => _uploadPhotos('avant'),
                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                    label: Text('Photos avant (${widget.photosAvant.length})'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        _busy ? null : () => _uploadPhotos('apres'),
                    icon: const Icon(Icons.photo_camera, size: 18),
                    label: Text('Photos après (${widget.photosApres.length})'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _busy ? null : _terminer,
              icon: const Icon(Icons.check_circle),
              label: const Text('Marquer terminé'),
              style: ElevatedButton.styleFrom(
                backgroundColor: BabifixDesign.ciBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
          if (!canStart && !canFinish && !acompteEnAttente)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Center(
                child: Text(
                  s == 'Terminee'
                      ? 'En attente de confirmation du client.'
                      : s == 'Confirmee'
                          ? 'Travaux confirmés ✓'
                          : 'Étape : $s',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

