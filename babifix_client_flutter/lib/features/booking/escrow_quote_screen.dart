/// Écran "Quote escrow" (Phase F — C5).
///
/// Avant de lancer le checkout GeniusPay, on affiche au client :
/// - sa stratégie (CASH commission 18% vs MOBILE 100%),
/// - le montant à verser en ligne maintenant,
/// - ce qui restera dû en cash main à main (le cas échéant),
/// - la garantie "fonds bloqués jusqu'à confirmation".
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';

import '../../babifix_design_system.dart';
import '../../babifix_api_config.dart';
import '../../models/babifix_models.dart';
import '../../services/babifix_api.dart';
import '../../shared/widgets/babifix_phase_widgets.dart';
import '../../user_store.dart';
import '../../shared/widgets/babifix_ring_loader.dart';
import '../../shared/widgets/babifix_snackbar.dart';
import '../../shared/error_utils.dart';

class EscrowQuoteScreen extends StatefulWidget {
  final String reservationReference;
  const EscrowQuoteScreen({super.key, required this.reservationReference});

  @override
  State<EscrowQuoteScreen> createState() => _EscrowQuoteScreenState();
}

class _EscrowQuoteScreenState extends State<EscrowQuoteScreen> {
  EscrowQuote? _quote;
  bool _loading = true;
  bool _starting = false;
  String? _error;
  final _phoneCtl = TextEditingController();
  String _operator = 'ORANGE_MONEY';

  @override
  void initState() {
    super.initState();
    _load();
    _prefillPhone();
  }

  Future<void> _prefillPhone() async {
    try {
      final profile = await BabifixUserStore.loadProfile();
      final phone = profile['phone'] ?? '';
      if (phone.isNotEmpty && mounted) {
        _phoneCtl.text = phone;
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _phoneCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _quote = await EscrowApi.quote(widget.reservationReference);
    } on BabifixApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _startPayment() async {
    final q = _quote;
    if (q == null) return;
    if (q.reservationId == null) {
      _snack('Réservation introuvable.');
      return;
    }
    setState(() => _starting = true);
    try {
      final r = await BabifixUserStore.authPost(
        '/api/paiements/geniuspay/initiate/',
        body: jsonEncode({
          'reservation': q.reservationId,
          'montant': q.amountDueOnline.toInt(),
          'customer_name': 'Client BABIFIX',
          'phone': _phoneCtl.text.trim(),
          'payment_method': _operator,
        }),
      );
      if (r.statusCode >= 400) {
        _snack(apiErrorMessage(r.body) ?? userFriendlyError(null, r.statusCode));
        return;
      }
      final j = jsonDecode(r.body);
      final url =
          (j['checkout_url'] ?? j['payment_url'] ?? '').toString();
      if (url.isEmpty) {
        // Mode simulation : on considère le paiement OK et on revient.
        _snack('Paiement simulé. Le prestataire est notifié.');
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      final ok = await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication);
      if (!ok) _snack("Impossible d'ouvrir la page de paiement");
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _snack(String s) {
    if (!mounted) return;
    showBabifixToast(
        context,
        type: BabifixToastType.info,
        message: s,
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Paiement de l\'acompte'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: _loading
          ? const Center(child: BabifixRingLoader.dark(size: 80))
          : _error != null
              ? _errorView()
              : _content(_quote!),
    );
  }

  Widget _errorView() => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  color: BabifixDesign.error, size: 48),
              const SizedBox(height: 10),
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

  Widget _content(EscrowQuote q) {
    final isCash = q.isCash;
    final color = isCash ? Colors.orange.shade700 : BabifixDesign.ciBlue;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: color.withValues(alpha: 0.30)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                            isCash
                                ? Icons.handshake
                                : Icons.lock_outline,
                            color: color,
                            size: 26),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            isCash
                                ? 'Paiement cash en main propre'
                                : 'Paiement Mobile Money — fonds bloqués',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: color),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isCash
                          ? "Vous versez maintenant uniquement la commission "
                              "de la plateforme (${q.commissionMontant.toInt()} F CFA). "
                              "Le reste (${q.cashRemainderDueToProvider.toInt()} F CFA) "
                              "sera payé en cash directement au prestataire à la fin du chantier."
                          : "Vous versez 100% du devis maintenant. "
                              "L'argent reste sécurisé chez BABIFIX. "
                              "Le prestataire ne reçoit sa part qu'après votre confirmation des travaux.",
                      style: const TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // Bloc montants
              MoneyBreakdownWidget(
                sousTotal: q.totalDevis,
                commissionRate: 18,
                commissionMontant: q.commissionMontant,
                totalTtc: q.totalDevis,
                netPrestataire: q.netPrestataire,
              ),
              const SizedBox(height: 14),
              // Bloc "à payer maintenant"
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: BabifixDesign.ciGreen.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: BabifixDesign.ciGreen.withValues(alpha: 0.30)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.payment,
                        color: BabifixDesign.ciGreen, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'À payer maintenant en Mobile Money',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            fmtMoney(q.amountDueOnline),
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: BabifixDesign.ciGreen),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (isCash) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.payments_outlined,
                          size: 18, color: Colors.grey.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Reste à payer en cash au prestataire : '
                          '${fmtMoney(q.cashRemainderDueToProvider)}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              if (q.acompteValide)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: BabifixDesign.ciGreen.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color:
                            BabifixDesign.ciGreen.withValues(alpha: 0.30)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle,
                          color: BabifixDesign.ciGreen),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Acompte déjà versé — le prestataire peut démarrer.',
                          style: TextStyle(
                              color: BabifixDesign.ciGreen,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
              if (!q.acompteValide) ...[
                Text(
                  'Méthode Mobile Money',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade700),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: _operator,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'ORANGE_MONEY', child: Text('Orange Money')),
                    DropdownMenuItem(
                        value: 'MTN_MOMO', child: Text('MTN Mobile Money')),
                    DropdownMenuItem(value: 'WAVE', child: Text('Wave')),
                    DropdownMenuItem(value: 'MOOV', child: Text('Moov Money')),
                  ],
                  onChanged: (v) => setState(() => _operator = v ?? 'ORANGE_MONEY'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _phoneCtl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Téléphone Mobile Money',
                    hintText: '+225 07 00 00 00 00',
                    prefixIcon: const Icon(Icons.phone_iphone),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Text(
                'Opérateurs supportés : Orange Money · MTN MoMo · Wave · Moov',
                style:
                    TextStyle(fontSize: 11, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: q.acompteValide || _starting ? null : _startPayment,
                icon: _starting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: BabifixRingLoader.cyan(size: 28))
                    : const Icon(Icons.phone_iphone),
                label: Text(
                  q.acompteValide
                      ? 'Déjà payé'
                      : 'Payer ${fmtMoney(q.amountDueOnline)}',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: BabifixDesign.ciGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// Évite warning d'import non utilisé
// ignore: unused_element
void _keepApiConfigImport() => babifixApiBaseUrl();
