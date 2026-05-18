/// Écran "Confirmer travaux" (Phase F — C6).
///
/// Le client vérifie photos avant/après + résumé devis, puis confirme.
/// La confirmation déclenche EscrowService.release_funds côté backend.
import 'dart:convert' show base64Decode;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../babifix_design_system.dart';
import '../../models/babifix_models.dart';
import '../../services/babifix_api.dart';
import '../../shared/widgets/animated_check_circle.dart';
import '../../shared/widgets/babifix_phase_widgets.dart';
import '../reservations/rate_provider_screen.dart';
import '../../shared/widgets/babifix_ring_loader.dart';

class ConfirmCompletionScreen extends StatefulWidget {
  final String reservationReference;
  final List<String> photosAvant;
  final List<String> photosApres;

  const ConfirmCompletionScreen({
    super.key,
    required this.reservationReference,
    this.photosAvant = const [],
    this.photosApres = const [],
  });

  @override
  State<ConfirmCompletionScreen> createState() =>
      _ConfirmCompletionScreenState();
}

class _ConfirmCompletionScreenState extends State<ConfirmCompletionScreen> {
  EscrowQuote? _quote;
  Devis? _devis;
  bool _loading = true;
  bool _busy = false;
  bool _accept = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _quote = await EscrowApi.quote(widget.reservationReference);
      _devis = await DevisApi.get(widget.reservationReference);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _doConfirm() async {
    setState(() => _busy = true);
    try {
      final r = await EscrowApi.confirmCompletion(widget.reservationReference);
      if (!mounted) return;
      final escrow = (r['escrow'] as Map?) ?? const {};
      final released =
          (escrow['released_to_provider'] as num?)?.toDouble() ?? 0;
      _showSuccess(released, escrow);
    } on BabifixApiException catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openDispute() async {
    final motifCtl = TextEditingController();
    String prio = 'Moyenne';
    final motif = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSb) {
        return AlertDialog(
          title: const Text('Ouvrir un litige'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Décrivez le problème. Un admin examinera et tranchera "
                "(remboursement, libération, ou partage).",
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: motifCtl,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Motif (ex: travaux non conformes, ...)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: prio,
                items: const [
                  DropdownMenuItem(value: 'Basse', child: Text('Priorité basse')),
                  DropdownMenuItem(value: 'Moyenne', child: Text('Priorité moyenne')),
                  DropdownMenuItem(value: 'Haute', child: Text('Priorité haute')),
                ],
                onChanged: (v) => setSb(() => prio = v ?? 'Moyenne'),
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ],
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
              onPressed: () => Navigator.pop(ctx, motifCtl.text.trim()),
              child: const Text('Ouvrir'),
            ),
          ],
        );
      }),
    );
    if (motif == null || motif.isEmpty) return;
    setState(() => _busy = true);
    try {
      await DisputeApi.open(
        reservationReference: widget.reservationReference,
        motif: motif,
        priorite: prio,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.orange.shade700,
        content: const Text(
          "Litige ouvert. Un admin BABIFIX vous contactera.",
        ),
      ));
      Navigator.of(context).pop(false);
    } on BabifixApiException catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSuccess(double released, Map escrow) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const AnimatedCheckCircle(size: 78),
        title: const Text('Travaux confirmés'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              released > 0
                  ? 'Vous avez libéré ${fmtMoney(released)} au prestataire.'
                  : 'Le règlement cash est acté. Vous pouvez régler le solde au prestataire en main propre.',
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 12),
            Text(
              'Vous pouvez maintenant noter le prestataire et télécharger votre reçu.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context, true);
            },
            child: const Text('Plus tard'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8B5CF6),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.star_outline_rounded, size: 18),
            label: const Text('Noter le prestataire'),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context, true);
              Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => RateProviderScreen(
                    reservationReference: widget.reservationReference,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Confirmer les travaux'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: _loading
          ? const Center(child: BabifixRingLoader.dark(size: 80))
          : _body(),
    );
  }

  Widget _body() {
    final q = _quote;
    final isMobile = q != null && q.isMobile;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: BabifixDesign.ciBlue.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: BabifixDesign.ciBlue.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: BabifixDesign.ciBlue, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isMobile
                            ? "En confirmant, vous libérez ${q != null ? fmtMoney(q.netPrestataire) : ''} au prestataire. "
                                "Cette action est définitive."
                            : "En confirmant, vous validez que le règlement cash est en règle. "
                                "Aucun fonds n'est libéré (la commission est déjà encaissée).",
                        style: const TextStyle(fontSize: 13, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (widget.photosAvant.isNotEmpty)
                _photoSection('Photos avant intervention', widget.photosAvant),
              if (widget.photosApres.isNotEmpty)
                _photoSection('Photos après intervention', widget.photosApres),
              if (_devis != null) ...[
                const SizedBox(height: 8),
                Text('Rappel du devis',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade700)),
                const SizedBox(height: 6),
                DevisCardWidget(devis: _devis!, compact: true),
              ],
              const SizedBox(height: 12),
              CheckboxListTile(
                value: _accept,
                onChanged: (v) => setState(() => _accept = v ?? false),
                title: const Text(
                  'Je confirme avoir contrôlé les travaux et les accepter.',
                  style: TextStyle(fontSize: 13),
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _openDispute,
                    icon: const Icon(Icons.report_problem_outlined, size: 18),
                    label: const Text('Ouvrir un litige'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: BabifixDesign.error,
                      side: BorderSide(color: BabifixDesign.error),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: (!_accept || _busy) ? null : _doConfirm,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_circle, size: 18),
                    label: const Text('Confirmer & libérer'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: BabifixDesign.ciGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _broken() => Container(
        width: 100,
        height: 100,
        color: Colors.grey.shade300,
        child: const Icon(Icons.broken_image_outlined),
      );

  Widget _photoSection(String title, List<String> urls) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700)),
          const SizedBox(height: 6),
          SizedBox(
            height: 100,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: urls.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final u = urls[i];
                Widget child;
                if (u.startsWith('data:image')) {
                  final b64 = u.substring(u.indexOf(',') + 1);
                  Uint8List? bytes;
                  try {
                    bytes = base64Decode(b64);
                  } catch (_) {}
                  child = bytes == null
                      ? _broken()
                      : Image.memory(bytes,
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _broken());
                } else {
                  // URL relative ou absolue
                  final full = MediaApi.absolute(u);
                  child = Image.network(full,
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _broken());
                }
                return ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: child,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
