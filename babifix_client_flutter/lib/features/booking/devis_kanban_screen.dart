/// Écran "Détail devis" (Phase A + C1).
///
/// Affichage Kanban professionnel du devis reçu :
/// - rendu via [DevisCardWidget],
/// - actions Accepter / Refuser (avec motif),
/// - timeline 8 étapes,
/// - bouton "Procéder au paiement" qui ouvre l'écran escrow C5.
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../babifix_design_system.dart';
import '../../shared/widgets/babifix_suggestion_chips.dart';
import '../../models/babifix_models.dart';
import '../../services/babifix_api.dart';
import '../../shared/widgets/babifix_phase_widgets.dart';
import '../../user_store.dart';
import 'escrow_quote_screen.dart';
import '../../shared/widgets/babifix_ring_loader.dart';
import '../../shared/widgets/babifix_snackbar.dart';

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
  bool _acompteValide = false;
  // Détail argent réconcilié (caution, reste, commissions, net) fourni par
  // l'endpoint /detail — sert à afficher le règlement complet AVANT acceptation.
  Map<String, dynamic>? _extras;

  @override
  void initState() {
    super.initState();
    _acompteValide = widget.reservationInfo?['acompte_valide'] == true;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await DevisApi.get(widget.reservationReference);
      // Rafraîchit le statut d'acompte (sinon « Payer maintenant » réapparaît
      // après paiement, car widget.reservationInfo est figé).
      bool acompte = _acompteValide;
      try {
        final q = await EscrowApi.quote(widget.reservationReference);
        acompte = q.acompteValide;
      } catch (_) {}
      // Détail argent réconcilié (facultatif : n'empêche pas l'affichage du devis).
      Map<String, dynamic>? extras;
      try {
        final r = await BabifixUserStore.authGet(
          '/api/client/reservations/${widget.reservationReference}/detail',
        );
        if (r.statusCode == 200) {
          final body = jsonDecode(r.body) as Map<String, dynamic>;
          extras = (body['reservation'] as Map<String, dynamic>?) ?? body;
        }
      } catch (_) {}
      setState(() {
        _devis = d;
        _acompteValide = acompte;
        _extras = extras;
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
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Motif (facultatif)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              BabifixSuggestionChips(
                controller: controller,
                accent: BabifixDesign.error,
                suggestions: const [
                  'Prix trop élevé',
                  'Délai trop long',
                  'J\'ai trouvé moins cher',
                  'Détails à revoir',
                  'Je ne suis plus intéressé',
                ],
              ),
            ],
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
    showBabifixToast(
        context,
        type: BabifixToastType.info,
        message: msg,
      );
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
    final acompteValide = _acompteValide;
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
                  color: BabifixDesign.iconOnLight, size: 20),
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
        DevisCardWidget(devis: _reconciledDevisForCard(devis)),
        if (!devis.estEstimation && _extras != null) ...[
          const SizedBox(height: 14),
          _reglementCard(_extras!),
        ],
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

  /// Si la caution a déjà été réglée, la carte devis (en haut) doit refléter
  /// la MÊME commission réconciliée que _reglementCard (en dessous) — sinon
  /// les deux cartes affichent deux chiffres différents pour "Commission
  /// BABIFIX" sur le même écran. Sans caution réglée (ou sans _extras
  /// disponibles), on garde le devis tel quel (rien à réconcilier).
  Devis _reconciledDevisForCard(Devis d) {
    final ex = _extras;
    if (ex == null || ex['caution_payee'] != true) return d;
    double v(String k, double fb) => double.tryParse('${ex[k] ?? ''}') ?? fb;
    final commission = v('commission', d.commissionMontant);
    final rate = (ex['commission_rate'] is num)
        ? (ex['commission_rate'] as num).round()
        : d.commissionRate;
    final net = v('net_prestataire', d.netPrestataire);
    return d.copyWithReconciled(
      commissionRate: rate,
      commissionMontant: commission,
      netPrestataire: net,
    );
  }

  /// Détail du règlement AVANT acceptation : sous-total, caution déjà versée
  /// (mobile), reste à payer (espèces/mobile), part BABIFIX (2 commissions),
  /// part prestataire, et mention « caution non remboursable sauf litige ».
  Widget _reglementCard(Map<String, dynamic> ex) {
    double d(String k, [double fb = 0]) =>
        double.tryParse('${ex[k] ?? ''}') ?? fb;
    final sousTotal = d('sous_total');
    if (sousTotal <= 0) return const SizedBox.shrink();
    final cautionPayee = ex['caution_payee'] == true;
    final caution = cautionPayee ? d('caution_montant') : 0.0;
    final commission = d('commission', sousTotal * 0.18);
    final commissionPct = (ex['commission_rate'] is num)
        ? (ex['commission_rate'] as num).round()
        : (sousTotal > 0 ? (commission / sousTotal * 100).round() : 18);
    // Phase 5 : transport 100 % presta ; frais fixe de mise en relation en plus.
    final frais = cautionPayee ? d('frais_mise_en_relation', 500) : 0.0;
    final net = d('net_prestataire', sousTotal - commission);
    final reste = d('reste_client', sousTotal - caution);
    final totalClient = d('total_client', sousTotal + frais);

    Widget row(String label, double value,
        {Color? color, bool bold = false, bool big = false, bool neg = false}) {
      final txt = '${neg ? '− ' : ''}${fmtMoney(value.abs())}';
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(label,
                  style: TextStyle(
                      fontSize: big ? 14 : 12.5,
                      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                      color: color ?? Colors.grey.shade700)),
            ),
            Text(txt,
                style: TextStyle(
                    fontSize: big ? 18 : 13,
                    fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
                    color: color ?? BabifixDesign.navy)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(width: 3, height: 16, decoration: BoxDecoration(
                  color: BabifixDesign.cyan,
                  borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 8),
              Text('Détail du règlement',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: BabifixDesign.navy,
                      letterSpacing: 0.4)),
            ],
          ),
          const SizedBox(height: 12),
          row('Sous-total prestation', sousTotal),
          if (caution > 0) ...[
            row('Transport versé au prestataire', caution,
                color: BabifixDesign.cyan, neg: true),
            row('Reste à régler (espèces ou mobile)', reste,
                bold: true, color: BabifixDesign.navy),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, color: Color(0xFFE2E8F0)),
          ),
          row('Commission BABIFIX devis ($commissionPct %)', commission,
              color: BabifixDesign.warning),
          row('Net reversé au prestataire', net, color: BabifixDesign.success),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, color: Color(0xFFE2E8F0)),
          ),
          row('TOTAL PRESTATION', sousTotal, bold: true, big: true),
          if (frais > 0) ...[
            const SizedBox(height: 6),
            row('Frais de mise en relation (à la visite)', frais,
                color: BabifixDesign.warning),
            row('Total payé par le client', totalClient,
                bold: true, color: BabifixDesign.navy),
          ],
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              caution > 0
                  ? 'Le transport (versé par mobile) revient à 100 % au '
                      'prestataire et est déduit du devis. Les frais de mise en '
                      'relation reviennent à BABIFIX. Non remboursable, sauf '
                      'litige (après analyse).'
                  : 'Vous payez exactement le devis. La commission BABIFIX est '
                      'prélevée sur la part du prestataire, sans surplus pour vous.',
              style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                  color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionsBar(Devis devis) {
    final canAct = devis.statut == DevisStatus.envoye;
    // « Payer maintenant » seulement si le devis est accepté ET l'acompte n'a
    // pas encore été versé (sinon la page réapparaissait après paiement).
    final canPay = devis.statut == DevisStatus.accepte && !_acompteValide;
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
            : canPay
                ? ElevatedButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            setState(() => _busy = true);
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => EscrowQuoteScreen(
                                  reservationReference:
                                      widget.reservationReference,
                                ),
                              ),
                            );
                            if (mounted) {
                              setState(() => _busy = false);
                              await _load();
                            }
                          },
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: BabifixRingLoader.cyan(size: 28))
                        : const Icon(Icons.payment, size: 18),
                    label: const Text('Payer maintenant'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: BabifixDesign.ciOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  )
                : (devis.statut == DevisStatus.accepte && _acompteValide)
                    ? Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF22C55E).withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_rounded,
                                color: Color(0xFF16A34A), size: 20),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Acompte payé : en attente de l\'intervention du prestataire.',
                                style: TextStyle(
                                    color: Color(0xFF16A34A),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13),
                              ),
                            ),
                          ],
                        ),
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
