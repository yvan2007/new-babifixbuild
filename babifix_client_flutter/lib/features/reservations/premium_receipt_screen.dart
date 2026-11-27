import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:printing/printing.dart';
import '../../babifix_design_system.dart';
import '../../services/babifix_api.dart';
import '../../shared/widgets/payment_method_logo.dart';
import '../../shared/widgets/babifix_button.dart';
import '../../shared/widgets/babifix_page_route.dart';
import '../../shared/widgets/babifix_ring_loader.dart';
import '../../shared/widgets/babifix_snackbar.dart';
import '../../user_store.dart';
import '../payment/payment_screen.dart';

class PremiumReceiptScreen extends StatefulWidget {
  final String reservationReference;

  /// Quand `true`, l'écran sert de DEVIS (avant acceptation) : en-tête « DEVIS »,
  /// détail argent complet et boutons Accepter / Refuser si le devis est ENVOYE.
  /// Quand `false` (défaut), c'est un REÇU en lecture seule.
  final bool isQuote;

  const PremiumReceiptScreen({
    super.key,
    required this.reservationReference,
    this.isQuote = false,
  });

  @override
  State<PremiumReceiptScreen> createState() => _PremiumReceiptScreenState();
}

class _PremiumReceiptScreenState extends State<PremiumReceiptScreen> {
  Map<String, dynamic>? _data;
  Uint8List? _pdfBytes;
  bool _loading = true;
  String? _error;
  bool _accepting = false;
  bool _refusing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final r = await BabifixUserStore.authGet(
        '/api/client/reservations/${widget.reservationReference}/detail',
      );
      if (r.statusCode != 200) throw Exception('Erreur chargement');
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      Uint8List? pdf;
      try {
        final raw = await ReceiptApi.downloadPdf(widget.reservationReference);
        pdf = Uint8List.fromList(raw);
      } catch (_) {}
      if (mounted) setState(() { _data = body; _pdfBytes = pdf; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _sharePdf() async {
    if (_pdfBytes == null) return;
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/recu_${widget.reservationReference}.pdf');
    await f.writeAsBytes(_pdfBytes!);
    await Share.shareXFiles([XFile(f.path)], subject: 'Reçu BABIFIX : ${widget.reservationReference}');
  }

  // ─── Actions DEVIS (mode isQuote) ──────────────────────────────────────────

  /// Le devis est-il encore actionnable (accepter / refuser) ?
  bool get _devisActionnable {
    final res = (_data?['reservation'] as Map<String, dynamic>?) ?? _data ?? {};
    return widget.isQuote && '${res['devis_statut'] ?? ''}' == 'ENVOYE';
  }

  Future<void> _acceptDevis() async {
    if (_accepting) return;
    setState(() => _accepting = true);
    try {
      final resp = await BabifixUserStore.authPost(
        '/api/client/reservations/${widget.reservationReference}/devis/accept',
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final montant = (data['montant'] as num?)?.toInt() ?? 0;
        final reservationId = (data['reservation_id'] as num?)?.toInt();
        if (!mounted) return;
        final res = (_data?['reservation'] as Map<String, dynamic>?) ?? _data ?? {};
        final presta = (res['prestataire_data'] as Map<String, dynamic>?) ?? {};
        showBabifixToast(context,
            type: BabifixToastType.success,
            message: 'Devis accepté ! Redirection vers le paiement...');
        await Future.delayed(const Duration(milliseconds: 700));
        if (!mounted) return;
        if (reservationId != null && reservationId > 0) {
          Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
            builder: (_) => PaymentScreen(
              reservationId: reservationId,
              amount: montant,
              serviceTitle: 'Devis ${widget.reservationReference}',
              providerName: '${presta['nom'] ?? 'Prestataire'}',
            ),
          ));
        } else {
          _load();
        }
      } else {
        if (mounted) {
          showBabifixToast(context,
              type: BabifixToastType.error,
              message: _errBody(resp.body) ?? 'Impossible d\'accepter le devis');
        }
      }
    } catch (e) {
      if (mounted) {
        showBabifixToast(context,
            type: BabifixToastType.error, message: 'Erreur : $e');
      }
    }
    if (mounted) setState(() => _accepting = false);
  }

  Future<void> _refuseDevis() async {
    if (_refusing) return;
    final motifCtrl = TextEditingController();
    final motif = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Refuser le devis'),
        content: TextField(
          controller: motifCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Motif du refus',
            hintText: 'Pourquoi refusez-vous ce devis ?',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(
              foregroundColor: Colors.white,backgroundColor: BabifixDesign.error),
            onPressed: () => Navigator.pop(ctx, motifCtrl.text),
            child: const Text('Refuser'),
          ),
        ],
      ),
    );
    if (motif == null || motif.trim().isEmpty) return;
    setState(() => _refusing = true);
    try {
      final resp = await BabifixUserStore.authPost(
        '/api/client/reservations/${widget.reservationReference}/devis/refuse',
        body: jsonEncode({'motif': motif.trim()}),
      );
      if (mounted && resp.statusCode == 200) {
        showBabifixToast(context,
            type: BabifixToastType.error, message: 'Devis refusé');
        _load();
      } else if (mounted) {
        showBabifixToast(context,
            type: BabifixToastType.error,
            message: _errBody(resp.body) ?? 'Refus impossible');
      }
    } catch (e) {
      if (mounted) {
        showBabifixToast(context,
            type: BabifixToastType.error, message: 'Erreur : $e');
      }
    }
    if (mounted) setState(() => _refusing = false);
  }

  String? _errBody(String body) {
    try {
      final d = jsonDecode(body) as Map<String, dynamic>;
      final s = (d['detail'] ?? d['error'])?.toString();
      if (s != null && s.isNotEmpty) return s;
    } catch (_) {}
    return null;
  }

  Color _statusColor(String s) {
    final l = s.toLowerCase();
    if (l.contains('pay') || l.contains('complete') || l.contains('termine') || l.contains('valide') || l.contains('sold')) {
      return const Color(0xFF0E3B2E);
    }
    if (l.contains('attent') || l.contains('pending') || l.contains('encour') || l.contains('acompte')) {
      return const Color(0xFFB45309);
    }
    if (l.contains('annul') || l.contains('refus') || l.contains('error') || l.contains('echec')) {
      return BabifixDesign.error;
    }
    return BabifixDesign.navy;
  }

  String _statusLabel(String s) {
    final l = s.toLowerCase();
    if (l.contains('pay') || l.contains('complete') || l.contains('sold')) return 'Paye';
    if (l.contains('termine') || l.contains('valide')) return 'Valide';
    if (l.contains('attent') || l.contains('pending')) return 'En attente';
    if (l.contains('encour')) return 'En cours';
    if (l.contains('annul')) return 'Annule';
    if (l.contains('refus')) return 'Refuse';
    if (l.contains('echec')) return 'Echoue';
    return s;
  }

  IconData _statusIcon(String s) {
    final l = s.toLowerCase();
    if (l.contains('pay') || l.contains('complete') || l.contains('termine') || l.contains('valide')) return Icons.check_circle_rounded;
    if (l.contains('attent') || l.contains('pending') || l.contains('encour')) return Icons.access_time_rounded;
    if (l.contains('annul') || l.contains('refus') || l.contains('echec')) return Icons.cancel_rounded;
    return Icons.help_outline_rounded;
  }

  static const _frMonths = <int, String>{
    1: 'janvier',
    2: 'fevrier',
    3: 'mars',
    4: 'avril',
    5: 'mai',
    6: 'juin',
    7: 'juillet',
    8: 'aout',
    9: 'septembre',
    10: 'octobre',
    11: 'novembre',
    12: 'decembre',
  };

  /// Formate une date ISO en francais lisible ('21 novembre 2026').
  String _safeDate(dynamic raw) {
    final s = '${raw ?? ''}'.trim();
    final dt = DateTime.tryParse(s);
    if (dt != null) {
      final m = _frMonths[dt.month] ?? '${dt.month}';
      return '${dt.day} $m ${dt.year}';
    }
    if (s.length >= 10) return s.substring(0, 10);
    final now = DateTime.now();
    return '${now.day} ${_frMonths[now.month]} ${now.year}';
  }

  /// Extrait HH:MM d'une chaine ISO si present, sinon vide.
  String _safeTime(dynamic raw) {
    final s = '${raw ?? ''}'.trim();
    final dt = DateTime.tryParse(s);
    if (dt != null && s.contains('T')) {
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      return 'a $hh:$mm';
    }
    if (s.length >= 16) return 'a ${s.substring(11, 16)}';
    return '';
  }

  String _paymentLabel(String id) {
    switch (id) {
      case 'ESPECES': return 'Espèces';
      case 'ORANGE_MONEY': return 'Orange Money';
      case 'MTN_MOMO': return 'MTN Mobile Money';
      case 'WAVE': return 'Wave';
      case 'MOOV': return 'Moov Money';
      default: return id;
    }
  }

  Widget _paymentMethodWidget(String id, {double height = 32}) {
    if (id == 'ESPECES') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.money_rounded, size: height, color: BabifixDesign.success),
          const SizedBox(width: 8),
          Text('Espèces', style: TextStyle(fontSize: height * 0.5, fontWeight: FontWeight.w600, color: BabifixDesign.navy)),
        ],
      );
    }
    return BabifixPaymentMethodLogo(methodId: id, height: height);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      bottomNavigationBar: _devisActionnable
          ? SafeArea(top: false, bottom: true, child: _buildQuoteActions())
          : null,
      appBar: AppBar(
        title: Text(widget.isQuote ? 'Devis' : 'Reçu de paiement'),
        backgroundColor: BabifixDesign.surfaceOf(context),
        foregroundColor: BabifixDesign.textPrimaryOf(context),
        iconTheme: IconThemeData(color: BabifixDesign.textPrimaryOf(context)),
        elevation: 0,
        surfaceTintColor: BabifixDesign.surfaceOf(context),
        actions: [
          if (_pdfBytes != null)
            IconButton(icon: const Icon(Icons.share_outlined), onPressed: _sharePdf),
          if (_data != null)
            IconButton(
              icon: const Icon(Icons.print_outlined),
              onPressed: () {
                final nav = Navigator.of(context);
                ReceiptApi.downloadPdf(widget.reservationReference).then((raw) {
                  if (mounted) {
                    nav.push(babifixRoute(
                      (_) => _PdfPreviewScreen(bytes: Uint8List.fromList(raw), reference: widget.reservationReference),
                    ));
                  }
                });
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: BabifixRingLoader.dark(size: 80))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline_rounded, color: BabifixDesign.error, size: 64),
                        const SizedBox(height: 16),
                        Text(_error!, textAlign: TextAlign.center, style: BabifixDesign.bodyMedium(color: BabifixDesign.error)),
                        const SizedBox(height: 16),
                        ElevatedButton(onPressed: _load, child: const Text('Réessayer')),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  child: _buildReceipt(context),
                ),
    );
  }

  Widget _buildReceipt(BuildContext context) {
    final d = _data ?? <String, dynamic>{};
    final res = (d['reservation'] as Map<String, dynamic>?) ?? d;
    final client = (res['client_data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final presta = (res['prestataire_data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final statut = '${res['statut'] ?? d['statut'] ?? ''}';
    final payType = '${res['payment_type'] ?? d['payment_type'] ?? 'ESPECES'}';
    final ref = '${res['reference'] ?? widget.reservationReference}';
    final montant = (res['montant'] ?? 0).runtimeType == double
        ? (res['montant'] as double)
        : double.tryParse('${res['montant'] ?? 0}') ?? 0;
    // Date NÉCESSAIRE sur le reçu = la date CHOISIE au créneau (scheduled_date)
    // si elle existe ; sinon, à défaut, la date de réservation (created_at).
    final scheduledRaw = '${res['scheduled_date'] ?? ''}'.trim();
    final dateStr = scheduledRaw.isNotEmpty
        ? _safeDate(scheduledRaw)
        : _safeDate(res['created_at']);
    final timeStr = _safeTime(res['created_at']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(ref, dateStr, timeStr, statut, payType),
        const SizedBox(height: 20),
        _buildParties(client, presta),
        const SizedBox(height: 20),
        _buildReservationInfo(res, payType),
        const SizedBox(height: 20),
        _buildServicesTable(res),
        const SizedBox(height: 20),
        _buildFinancialSummary(res, montant),
        const SizedBox(height: 20),
        _buildFooter(ref),
      ],
    );
  }

  Widget _buildHeader(String ref, String date, String time, String statut, String payType) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1B34),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFB45309).withValues(alpha: 0.45), width: 1.2),
        boxShadow: [
          BoxShadow(color: BabifixDesign.navy.withValues(alpha: 0.16), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40, height: 40,
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Image.asset(
                          'assets/images/logo_babifix.png',
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Icon(
                              Icons.build_rounded,
                              color: BabifixDesign.navy,
                              size: 24),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('BABIFIX', style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w900,
                            color: Colors.white, letterSpacing: 1.2,
                          )),
                          Text('Services a domicile · Cote d\'Ivoire', style: TextStyle(
                            fontSize: 11, color: Colors.white.withValues(alpha: 0.72),
                          )),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(widget.isQuote ? 'DEVIS DETAILLE' : 'RECU DE PAIEMENT', style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w800,
                    color: Color(0xFFFDE68A), letterSpacing: 1.6,
                  )),
                  const SizedBox(height: 4),
                  Text('N° $ref', style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700,
                    color: Colors.white,
                  )),
                  const SizedBox(height: 2),
                  Text('$date $time'.trim(), style: TextStyle(
                    fontSize: 12, color: Colors.white.withValues(alpha: 0.7),
                  )),
                ],
              ),
              _StatusBadge(status: statut, color: _statusColor(statut), icon: _statusIcon(statut), label: _statusLabel(statut)),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _paymentMethodWidget(payType, height: 28),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParties(Map<String, dynamic> client, Map<String, dynamic> presta) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _PartyCard(
          title: 'Client',
          name: '${client['nom'] ?? client['username'] ?? client['name'] ?? 'N/A'}',
          email: '${client['email'] ?? ''}',
          phone: '${client['phone'] ?? client['telephone'] ?? ''}',
          icon: Icons.person_outline_rounded,
          color: BabifixDesign.cyan,
        )),
        const SizedBox(width: 12),
        Expanded(child: _PartyCard(
          title: 'Prestataire',
          name: '${presta['nom'] ?? presta['name'] ?? presta['username'] ?? 'N/A'}',
          email: '${presta['email'] ?? ''}',
          phone: '${presta['phone'] ?? presta['telephone'] ?? ''}',
          icon: Icons.engineering_outlined,
          color: BabifixDesign.success,
        )),
      ],
    );
  }

  Widget _buildReservationInfo(Map<String, dynamic> res, String payType) {
    final items = [
      ('Référence', '${res['reference'] ?? 'N/A'}', Icons.tag_rounded),
      // Date NÉCESSAIRE = celle choisie au créneau (scheduled_date) ; à défaut,
      // la date de réservation.
      (
        'Date prévue',
        ('${res['scheduled_date'] ?? ''}'.trim().isNotEmpty)
            ? _safeDate('${res['scheduled_date']}')
            : _safeDate(res['created_at']),
        Icons.event_available_rounded,
      ),
      // On garde aussi la date de réservation, à titre indicatif.
      ('Réservé le', _safeDate(res['created_at']), Icons.history_rounded),
      ('Paiement', _paymentLabel(payType), Icons.payment_rounded),
      ('Statut', _statusLabel('${res['statut'] ?? ''}'), Icons.info_outline_rounded),
    ];
    return _SectionCard(
      title: 'Réservation',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: items.map((e) => _InfoTile(label: e.$1, value: e.$2, icon: e.$3)).toList(),
      ),
    );
  }

  Widget _buildServicesTable(Map<String, dynamic> res) {
    final lignes = (res['devis'] as List?) ?? (res['lignes'] as List?) ?? [];
    if (lignes.isEmpty) {
      final title = '${res['title'] ?? 'Service'}';
      final montant = (res['montant'] ?? 0).runtimeType == double
          ? (res['montant'] as double)
          : double.tryParse('${res['montant'] ?? 0}') ?? 0;
      return _SectionCard(
        title: 'Prestations',
        child: Column(
          children: [
            _TableRow(designation: title, qte: '1', pu: montant, total: montant, isHeader: true),
          ],
        ),
      );
    }
    return _SectionCard(
      title: 'Prestations',
      child: Column(
        children: [
          _TableHeader(),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          for (var i = 0; i < lignes.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: Color(0xFFF1F5F9)),
            _TableDataRow(ligne: lignes[i] as Map<String, dynamic>, index: i),
          ],
        ],
      ),
    );
  }

  Widget _buildFinancialSummary(Map<String, dynamic> res, double montant) {
    final sousTotal = double.tryParse('${res['sous_total'] ?? ''}') ?? montant;
    final cautionPayee = res['caution_payee'] == true;
    final cautionMontant = cautionPayee
        ? (double.tryParse('${res['caution_montant'] ?? 0}') ?? 0)
        : 0.0;
    final frais = double.tryParse('${res['frais_mise_en_relation'] ?? 0}') ?? 0;
    final remiseFid = double.tryParse('${res['remise_fidelite'] ?? 0}') ?? 0;
    final montantVerse = double.tryParse('${res['montant_verse'] ?? 0}') ?? 0;
    final montantRestant = double.tryParse('${res['montant_restant'] ?? 0}') ?? 0;
    final soldeValide = res['solde_valide'] == true;
    final totalClient = double.tryParse('${res['total_client'] ?? ''}') ??
        (sousTotal + frais - remiseFid).clamp(0, double.infinity).toDouble();
    final totalPaye = soldeValide
        ? (sousTotal - remiseFid + cautionMontant).clamp(0, double.infinity).toDouble()
        : (montantVerse + cautionMontant);

    return _SectionCard(
      title: 'Resume financier',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _SummaryRow(label: 'Sous-total prestation', value: sousTotal),
          if (cautionMontant > 0) ...[
            const SizedBox(height: 6),
            _SummaryRow(
                label: 'Caution transport deduite',
                value: -cautionMontant,
                color: const Color(0xFF0E3B2E)),
          ],
          if (frais > 0) ...[
            const SizedBox(height: 6),
            _SummaryRow(
                label: 'Frais de mise en relation',
                value: frais,
                color: const Color(0xFFB45309)),
          ],
          if (remiseFid > 0) ...[
            const SizedBox(height: 6),
            _SummaryRow(
                label: 'Remise fidelite BABIFIX',
                value: -remiseFid,
                color: const Color(0xFF0E3B2E)),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, color: Color(0xFFE2E8F0)),
          ),
          if (!widget.isQuote && totalPaye > 0) ...[
            _SummaryRow(
                label: 'Deja regle',
                value: totalPaye,
                bold: true,
                color: const Color(0xFF0E3B2E)),
            if (montantRestant > 0 && !soldeValide) ...[
              const SizedBox(height: 6),
              _SummaryRow(
                  label: 'Reste a regler',
                  value: montantRestant,
                  bold: true,
                  color: const Color(0xFFC2410C)),
            ],
            const SizedBox(height: 8),
          ],
          _SummaryRow(
              label: widget.isQuote ? 'TOTAL DEVIS' : 'TOTAL PRESTATION',
              value: totalClient,
              bold: true,
              large: true,
              color: BabifixDesign.navy),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              cautionMontant > 0
                  ? 'Le transport de visite est reverse au prestataire et deduit du devis accepte.'
                  : 'Montant exact garanti sans frais caches. Paiement protege par sequestre BABIFIX.',
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: BabifixDesign.iconOnLight,
                  height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuoteActions() {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _refusing || _accepting ? null : _refuseDevis,
              style: OutlinedButton.styleFrom(
                foregroundColor: BabifixDesign.error,
                side: BorderSide(color: BabifixDesign.error.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _refusing
                  ? const SizedBox(
                      width: 18, height: 18, child: BabifixRingLoader.dark(size: 18))
                  : const Text('Refuser',
                      style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: BabifixButton(
              label: 'Accepter le devis',
              isLoading: _accepting,
              height: 48,
              onPressed: _accepting || _refusing ? null : _acceptDevis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(String ref) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('BABIFIX', style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800, color: BabifixDesign.navy,
                    )),
                    const SizedBox(height: 4),
                    Text('Services à domicile en Côte d\'Ivoire', style: TextStyle(
                      fontSize: 12, color: BabifixDesign.iconOnLight,
                    )),
                    const SizedBox(height: 10),
                    _ContactRow(icon: Icons.email_outlined, text: 'contact@babifix.ci'),
                    const SizedBox(height: 4),
                    _ContactRow(icon: Icons.phone_outlined, text: '+225 01 02 03 04 05'),
                    const SizedBox(height: 4),
                    _ContactRow(icon: Icons.language_outlined, text: 'www.babifix.ci'),
                    const SizedBox(height: 4),
                    _ContactRow(icon: Icons.location_on_outlined, text: 'Abidjan, Côte d\'Ivoire'),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: QrImageView(
                  data: 'BABIFIX:$ref',
                  version: QrVersions.auto,
                  size: 80,
                  backgroundColor: Colors.white,
                  eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: BabifixDesign.navy),
                  dataModuleStyle: QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: BabifixDesign.navy),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Document généré automatiquement par BABIFIX le ${DateTime.now().toString().substring(0, 10)}.',
            style: TextStyle(fontSize: 11, color: BabifixDesign.iconOnLight.withValues(alpha: 0.7)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─── Sous-widgets ──────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String status;
  final Color color;
  final IconData icon;
  final String label;
  const _StatusBadge({required this.status, required this.color, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700, color: color,
          )),
        ],
      ),
    );
  }
}

class _PartyCard extends StatelessWidget {
  final String title, name, email, phone;
  final IconData icon;
  final Color color;
  const _PartyCard({required this.title, required this.name, required this.email, required this.phone, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: const Color(0x080F172A), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: color, size: 16),
              ),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: BabifixDesign.iconOnLight, letterSpacing: 0.8)),
            ],
          ),
          const SizedBox(height: 8),
          Text(name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: BabifixDesign.navy)),
          if (email.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(email, style: TextStyle(fontSize: 12, color: BabifixDesign.iconOnLight), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
          if (phone.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(phone, style: TextStyle(fontSize: 12, color: BabifixDesign.iconOnLight)),
          ],
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: const Color(0x080F172A), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 3, height: 16, decoration: BoxDecoration(
                color: BabifixDesign.cyan, borderRadius: BorderRadius.circular(2),
              )),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800,
                color: BabifixDesign.navy, letterSpacing: 0.5,
              )),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const _InfoTile({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: (MediaQuery.of(context).size.width - 84) / 2,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: BabifixDesign.iconOnLight),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 11, color: BabifixDesign.iconOnLight, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: BabifixDesign.navy)),
        ],
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(
        color: BabifixDesign.navy,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const SizedBox(width: 4),
          Expanded(flex: 4, child: Text('Désignation', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white))),
          Expanded(flex: 2, child: Text('Qté', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white), textAlign: TextAlign.center)),
          Expanded(flex: 3, child: Text('Prix unit.', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white), textAlign: TextAlign.right)),
          Expanded(flex: 3, child: Text('Total', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white), textAlign: TextAlign.right)),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _TableDataRow extends StatelessWidget {
  final Map<String, dynamic> ligne;
  final int index;
  const _TableDataRow({required this.ligne, required this.index});

  @override
  Widget build(BuildContext context) {
    final designation = '${ligne['designation'] ?? ligne['description'] ?? ligne['title'] ?? 'Prestation'}';
    final qte = double.tryParse('${ligne['quantite'] ?? ligne['qte'] ?? 1}') ?? 1;
    final pu = double.tryParse('${ligne['prix_unitaire'] ?? ligne['prix'] ?? 0}') ?? 0;
    final total = double.tryParse('${ligne['total'] ?? 0}') ?? (qte * pu);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      color: index.isEven ? Colors.transparent : const Color(0xFFF8FAFC),
      child: Row(
        children: [
          const SizedBox(width: 4),
          Expanded(flex: 4, child: Text(designation, style: TextStyle(fontSize: 12, color: BabifixDesign.navy, fontWeight: FontWeight.w500))),
          Expanded(flex: 2, child: Text('${qte.toInt()}', style: TextStyle(fontSize: 12, color: BabifixDesign.iconOnLight), textAlign: TextAlign.center)),
          Expanded(flex: 3, child: Text('${pu.toStringAsFixed(0)} F', style: TextStyle(fontSize: 12, color: BabifixDesign.iconOnLight), textAlign: TextAlign.right)),
          Expanded(flex: 3, child: Text('${total.toStringAsFixed(0)} F', style: TextStyle(fontSize: 12, color: BabifixDesign.navy, fontWeight: FontWeight.w700), textAlign: TextAlign.right)),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  final String designation, qte;
  final double pu, total;
  final bool isHeader;
  const _TableRow({required this.designation, required this.qte, required this.pu, required this.total, this.isHeader = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(
        color: isHeader ? BabifixDesign.navy : Colors.transparent,
        borderRadius: isHeader ? BorderRadius.circular(8) : null,
      ),
      child: Row(
        children: [
          const SizedBox(width: 4),
          Expanded(flex: 4, child: Text(designation, style: TextStyle(
            fontSize: 12, fontWeight: isHeader ? FontWeight.w700 : FontWeight.w500,
            color: isHeader ? Colors.white : BabifixDesign.navy,
          ))),
          Expanded(flex: 2, child: Text(qte, style: TextStyle(fontSize: 12, color: isHeader ? Colors.white : BabifixDesign.iconOnLight), textAlign: TextAlign.center)),
          Expanded(flex: 3, child: Text('${pu.toStringAsFixed(0)} F', style: TextStyle(fontSize: 12, color: isHeader ? Colors.white : BabifixDesign.iconOnLight), textAlign: TextAlign.right)),
          Expanded(flex: 3, child: Text('${total.toStringAsFixed(0)} F', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: isHeader ? Colors.white : BabifixDesign.navy), textAlign: TextAlign.right)),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final double value;
  final bool bold, large;
  final Color? color;
  const _SummaryRow({required this.label, required this.value, this.bold = false, this.large = false, this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(
          fontSize: large ? 15 : 13,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
          color: color ?? BabifixDesign.iconOnLight,
        )),
        Text('${value.toStringAsFixed(0)} FCFA', style: TextStyle(
          fontSize: large ? 22 : 14,
          fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
          color: color ?? BabifixDesign.navy,
        )),
      ],
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _ContactRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: BabifixDesign.iconOnLight),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(fontSize: 12, color: BabifixDesign.iconOnLight)),
      ],
    );
  }
}

// ─── PDF Preview screen (print) ────────────────────────────────────────────

class _PdfPreviewScreen extends StatelessWidget {
  final Uint8List bytes;
  final String reference;
  const _PdfPreviewScreen({required this.bytes, required this.reference});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Imprimer le reçu'),
        backgroundColor: Colors.white,
        foregroundColor: BabifixDesign.navy,
        elevation: 0,
      ),
      body: PdfPreview(
        build: (_) async => bytes,
        canChangePageFormat: false,
        canDebug: false,
      ),
    );
  }
}
