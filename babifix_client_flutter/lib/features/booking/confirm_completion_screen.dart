/// Écran "Confirmer travaux" (Phase F : C6).
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
import 'escrow_quote_screen.dart';
import '../../shared/widgets/babifix_ring_loader.dart';
import '../../shared/widgets/babifix_snackbar.dart';

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
      // ORDRE MÉTIER (Mobile Money) : on confirme les travaux D'ABORD, puis on
      // paie le solde 70 %. Si le backend signale qu'un solde reste dû, on
      // enchaîne directement sur l'écran de paiement du solde.
      if (r['solde_du'] == true) {
        await _routeToSoldePayment();
        return;
      }
      final escrow = (r['escrow'] as Map?) ?? const {};
      final released =
          (escrow['released_to_provider'] as num?)?.toDouble() ?? 0;
      _showSuccess(released, escrow);
    } on BabifixApiException catch (e) {
      showBabifixToast(
        context,
        type: BabifixToastType.info,
        message: e.message,
      );
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
      showBabifixToast(
        context,
        type: BabifixToastType.warning,
        message: "Litige ouvert. Un admin BABIFIX vous contactera.",
      );
      Navigator.of(context).pop(false);
    } on BabifixApiException catch (e) {
      showBabifixToast(
        context,
        type: BabifixToastType.info,
        message: e.message,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Travaux confirmés mais solde Mobile Money encore dû → on informe puis on
  /// ouvre l'écran de paiement du solde (qui libère ensuite les fonds).
  Future<void> _routeToSoldePayment() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(
            color: Color(0x1A22C55E),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.verified_rounded,
              size: 40, color: Color(0xFF22C55E)),
        ),
        title: const Text('Travaux confirmés ✓',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19)),
        content: const Text(
          'Dernière étape : réglez le solde pour finaliser. '
          'Le prestataire sera payé une fois le solde reçu.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13.5, height: 1.4),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => Navigator.pop(ctx),
              icon: const Icon(Icons.payments_rounded, size: 18),
              label: const Text('Payer le solde'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF22C55E),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ),
        ],
      ),
    );
    if (!mounted) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            EscrowQuoteScreen(reservationReference: widget.reservationReference),
      ),
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  void _showSuccess(double released, Map escrow) {
    const navy = Color(0xFF0B1B34);
    const green = Color(0xFF22C55E);
    const purple = Color(0xFF7C3AED);
    final msg = released > 0
        ? 'Vous avez libéré ${fmtMoney(released)} au prestataire.'
        : 'Réglez maintenant le prestataire en espèces, puis revenez confirmer '
            'le paiement (glisser) pour finaliser.';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pastille verte + check animé (taille maîtrisée)
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: green.withValues(alpha: 0.12),
                ),
                alignment: Alignment.center,
                child: const AnimatedCheckCircle(size: 56),
              ),
              const SizedBox(height: 18),
              const Text(
                'Travaux confirmés',
                style: TextStyle(
                    fontSize: 21, fontWeight: FontWeight.w900, color: navy),
              ),
              const SizedBox(height: 10),
              Text(
                msg,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 14, height: 1.45, color: Color(0xFF475569)),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.receipt_long_rounded, size: 16, color: navy),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Vous pouvez noter le prestataire et télécharger votre reçu.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.pop(context, true);
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        foregroundColor: const Color(0xFF64748B),
                      ),
                      child: const Text('Plus tard',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: purple,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13)),
                      ),
                      icon: const Icon(Icons.star_rounded, size: 18),
                      label: const Text('Noter',
                          style: TextStyle(fontWeight: FontWeight.w800)),
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
                  ),
                ],
              ),
            ],
          ),
        ),
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
    // Solde Mobile Money encore dû → la confirmation précède le paiement.
    final soldeDu = isMobile && q.amountDueOnline > 0;
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
                        color: BabifixDesign.iconOnLight, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        soldeDu
                            ? "En confirmant, vous validez que les travaux sont bien faits. "
                                "Vous réglerez ensuite le solde de ${fmtMoney(q.amountDueOnline)} pour finaliser."
                            : isMobile
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
              if (q != null) _paymentRecap(q),
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
                            child: BabifixRingLoader.cyan(size: 28))
                        : const Icon(Icons.check_circle, size: 18),
                    label: Text(soldeDu ? 'Confirmer les travaux' : 'Confirmer & libérer'),
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

  /// Récapitulatif clair du règlement : montre ce qui a DÉJÀ été réglé et ce
  /// qu'il reste — pour éviter de croire que le total est reprélevé à la fin.
  Widget _paymentRecap(EscrowQuote q) {
    final acompteDejaRegle = (q.totalDevis - q.cashRemainderDueToProvider);
    final lines = <Widget>[
      _recapLine('Total du devis', fmtMoney(q.totalDevis), bold: true),
    ];
    if (q.isCash) {
      lines.addAll([
        _recapLine(
          'Acompte déjà réglé en ligne (commission)',
          '${fmtMoney(acompteDejaRegle)}  ✓',
          color: BabifixDesign.ciGreen,
        ),
        _recapLine(
          'Reste à régler en espèces au prestataire',
          fmtMoney(q.cashRemainderDueToProvider),
          color: BabifixDesign.ciBlue,
          bold: true,
        ),
      ]);
    } else {
      lines.addAll([
        _recapLine('Commission plateforme (déjà retenue)',
            fmtMoney(q.commissionMontant)),
        _recapLine('Versé au prestataire maintenant',
            fmtMoney(q.netPrestataire),
            color: BabifixDesign.ciGreen, bold: true),
      ]);
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Récapitulatif du règlement',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade800)),
          const SizedBox(height: 10),
          ...lines,
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.verified_user_outlined,
                  size: 16, color: BabifixDesign.ciGreen),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  q.isCash
                      ? "Aucun nouveau montant ne sera prélevé en ligne. Le total reste ${fmtMoney(q.totalDevis)}."
                      : "Le total payé en ligne reste ${fmtMoney(q.totalDevis)} : rien n'est facturé deux fois.",
                  style: TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      color: Colors.grey.shade600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _recapLine(String label, String value,
      {Color? color, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
          ),
          const SizedBox(width: 10),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  color: color ?? Colors.black87)),
        ],
      ),
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
