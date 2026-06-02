import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../user_store.dart';
import '../../shared/error_utils.dart';
import '../../shared/services/websocket_push_service.dart';
import '../../shared/services/confetti_toast_service.dart';
import '../../shared/services/haptic_service.dart';
import '../payment/payment_screen.dart';
import '../../shared/widgets/babifix_ring_loader.dart';
import '../../shared/widgets/babifix_snackbar.dart';

class DevisDetailScreen extends StatefulWidget {
  final String reservationReference;
  final VoidCallback onBack;

  const DevisDetailScreen({
    super.key,
    required this.reservationReference,
    required this.onBack,
  });

  @override
  State<DevisDetailScreen> createState() => _DevisDetailScreenState();
}

class _DevisDetailScreenState extends State<DevisDetailScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _devis;
  bool _accepting = false;
  bool _refusing = false;

  @override
  void initState() {
    super.initState();
    _loadDevis();
    _initChatWebSocket();
  }

  Future<void> _loadDevis() async {
    final token = await BabifixUserStore.getApiToken();
    if (token == null) {
      setState(() {
        _loading = false;
        _error = 'Non connecte';
      });
      return;
    }

    try {
      final uri = Uri.parse(
        '${babifixApiBaseUrl()}/api/client/reservations/${widget.reservationReference}/devis',
      );
      final resp = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() {
          _devis = data['devis'];
          _loading = false;
        });
      } else {
        final body = _tryParseErrorBody(resp.body);
        setState(() {
          _loading = false;
          _error = body ?? userFriendlyError(null, resp.statusCode);
        });
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = userFriendlyError(e);
      });
    }
  }

  String? _tryParseErrorBody(String body) {
    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
      final detail = data['detail'] as String?;
      if (detail != null && detail.isNotEmpty) return detail;
    } catch (_) {}
    return null;
  }

  Future<void> _acceptDevis() async {
    if (_accepting) return;
    setState(() => _accepting = true);

    final token = await BabifixUserStore.getApiToken();
    if (token == null) return;

    try {
      final uri = Uri.parse(
        '${babifixApiBaseUrl()}/api/client/reservations/${widget.reservationReference}/devis/accept',
      );
      final resp = await http.post(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final montant = (data['montant'] as num?)?.toInt() ?? 0;

        if (mounted) {
          HapticService.success();
          ConfettiService.showSuccess(context, 'Devis accepte!');
          showBabifixToast(
        context,
        type: BabifixToastType.success,
        message: 'Devis accepte! Redirection vers le paiement...',
      );

          await Future.delayed(const Duration(milliseconds: 800));

          if (mounted) {
            final reservationId = (data['reservation_id'] as num?)?.toInt();
            if (reservationId != null && reservationId > 0) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute<void>(
                  builder: (_) => PaymentScreen(
                    reservationId: reservationId,
                    amount: montant,
                    serviceTitle: 'Devis ${widget.reservationReference}',
                    providerName: _devis?['prestataire']?['nom'] ?? 'Prestataire',
                  ),
                ),
              );
            } else {
              _loadDevis();
            }
          }
        }
      } else {
        if (mounted) {
          final body = _tryParseErrorBody(resp.body);
          showBabifixToast(
        context,
        type: BabifixToastType.error,
        message: body ?? userFriendlyError(null, resp.statusCode),
      );
        }
      }
    } catch (e) {
      if (mounted) {
        showBabifixToast(
        context,
        type: BabifixToastType.error,
        message: userFriendlyError(e),
      );
      }
    }

    if (mounted) setState(() => _accepting = false);
  }

  Future<void> _refuseDevis() async {
    if (_refusing) return;

    final motifController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF152A45),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Refuser le devis',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: TextField(
          controller: motifController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Motif du refus',
            labelStyle: TextStyle(color: Color(0xFF94A3B8)),
            hintText: 'Pourquoi refusez-vous ce devis?',
            hintStyle: TextStyle(color: Color(0xFF64748B)),
            filled: true,
            fillColor: Color(0xFF0F1D32),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
              borderSide: BorderSide.none,
            ),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, motifController.text),
            style: FilledButton.styleFrom(
              backgroundColor: BabifixDesign.error,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Refuser'),
          ),
        ],
      ),
    );

    if (result == null || result.isEmpty) return;

    setState(() => _refusing = true);

    final token = await BabifixUserStore.getApiToken();
    if (token == null) return;

    try {
      final uri = Uri.parse(
        '${babifixApiBaseUrl()}/api/client/reservations/${widget.reservationReference}/devis/refuse',
      );
      final resp = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'motif': result}),
      );

      if (resp.statusCode == 200) {
        if (mounted) {
          showBabifixToast(
        context,
        type: BabifixToastType.error,
        message: 'Devis refuse',
      );
          _loadDevis();
        }
      }
    } catch (e) {
      if (mounted) {
        showBabifixToast(
        context,
        type: BabifixToastType.error,
        message: userFriendlyError(e),
      );
      }
    }

    if (mounted) setState(() => _refusing = false);
  }

  Future<void> _exportPdf() async {
    if (_devis == null) return;
    try {
      await Printing.layoutPdf(
        onLayout: (format) async {
          final pdf = pw.Document();
          pdf.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              build: (context) => _buildPdfContent(),
            ),
          );
          return pdf.save();
        },
      );
    } catch (e) {
      if (mounted) {
        showBabifixToast(
        context,
        type: BabifixToastType.error,
        message: 'Erreur PDF: $e',
      );
      }
    }
  }

  pw.Widget _buildPdfContent() {
    final devis = _devis!;
    final prestataire = (devis['prestataire'] as Map<String, dynamic>?) ?? {};
    final lignes = (devis['lignes'] as List?) ?? [];
    final diagnostic = devis['diagnostic'] as String? ?? '';
    final dateProposee = devis['date_proposee'] as String? ?? 'Non precisee';
    final total = (devis['total_ttc'] as num?) ??
        (devis['sous_total'] as num?) ??
        0;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.all(20),
          decoration: pw.BoxDecoration(color: PdfColors.blue600),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'BABIFIX',
                style: pw.TextStyle(
                  fontSize: 28,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
              pw.Text(
                'DEVIS',
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 20),
        pw.Container(
          padding: const pw.EdgeInsets.all(15),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Prestataire',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                '${prestataire['nom'] ?? ''} ${prestataire['prenom'] ?? ''}',
              ),
              pw.Text('${prestataire['telephone'] ?? ''}'),
            ],
          ),
        ),
        pw.SizedBox(height: 20),
        if (diagnostic.isNotEmpty) ...[
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(15),
            decoration: pw.BoxDecoration(color: PdfColors.grey100),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Diagnostic',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 5),
                pw.Text(diagnostic),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
        ],
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300),
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Text(
                    'Description',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Text(
                    'Qte',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Text(
                    'Total',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ),
              ],
            ),
            ...lignes.map(
              (ligne) => pw.TableRow(
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text('${ligne['description'] ?? ''}'),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text(
                      '${ligne['quantite'] ?? 1}'
                      '${(ligne['unite'] ?? '').toString().isNotEmpty ? ' ${ligne['unite']}' : ''}',
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text(
                        _formatMontant((ligne['total'] as num?) ?? 0)),
                  ),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 20),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Container(
            width: 200,
            padding: const pw.EdgeInsets.all(15),
            decoration: pw.BoxDecoration(color: PdfColors.blue50),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Total a payer',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  _formatMontant(total),
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
        pw.SizedBox(height: 20),
        pw.Text('Date proposee: $dateProposee'),
        pw.SizedBox(height: 10),
        pw.Text(
          'Conditions: Devis valable 7 jours. Prix TTC, tout compris.',
        ),
      ],
    );
  }

  String _formatMontant(num value) =>
      value
          .toStringAsFixed(0)
          .replaceAllMapped(
            RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
            (m) => '${m[1]} ',
          ) +
      ' FCFA';

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: BabifixDesign.navy,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: widget.onBack,
          ),
          title: const Text(
            'Devis',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
              tooltip: 'Exporter en PDF',
              onPressed: _devis != null ? _exportPdf : null,
            ),
          ],
          bottom: const TabBar(
            dividerColor: Color(0x1AFFFFFF),
            indicatorColor: BabifixDesign.cyan,
            labelColor: BabifixDesign.cyan,
            unselectedLabelColor: Color(0xFF94A3B8),
            tabs: [
              Tab(text: 'Details'),
              Tab(icon: Icon(Icons.chat_bubble_outline), text: 'Chat'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: BabifixRingLoader.cyan(size: 28))
            : _error != null
            ? _buildError()
            : _devis == null
            ? const Center(
                child: Text(
                  'Aucun devis disponible',
                  style: TextStyle(color: Color(0xFF94A3B8)),
                ),
              )
            : TabBarView(children: [_buildDevisContent(), _buildChatSection()]),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: BabifixDesign.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline, size: 48, color: BabifixDesign.error),
            ),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Erreur inconnue',
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _loadDevis,
              style: FilledButton.styleFrom(
                backgroundColor: BabifixDesign.cyan,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Reessayer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDevisContent() {
    final devis = _devis!;
    final lignes = (devis['lignes'] as List?) ?? [];
    final statut = devis['statut'] as String? ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatutBanner(statut),
          const SizedBox(height: 20),
          _buildPrestataireInfo(devis),
          const SizedBox(height: 16),
          _buildDiagnostic(devis),
          _buildDateInfo(devis),
          const SizedBox(height: 16),
          _buildLignes(lignes),
          const SizedBox(height: 16),
          _buildTotal(devis),
          if (statut == 'ENVOYE') ...[
            const SizedBox(height: 28),
            _buildActionButtons(),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildStatutBanner(String statut) {
    late Color bgColor;
    late Color fgColor;
    late IconData icon;
    String label;

    switch (statut) {
      case 'ACCEPTE':
        bgColor = BabifixDesign.success.withValues(alpha: 0.12);
        fgColor = BabifixDesign.success;
        icon = Icons.check_circle_rounded;
        label = 'Devis accepte';
        break;
      case 'REFUSE':
        bgColor = BabifixDesign.error.withValues(alpha: 0.12);
        fgColor = BabifixDesign.error;
        icon = Icons.cancel_rounded;
        label = 'Devis refuse';
        break;
      case 'ENVOYE':
        bgColor = BabifixDesign.cyan.withValues(alpha: 0.12);
        fgColor = BabifixDesign.cyan;
        icon = Icons.hourglass_empty_rounded;
        label = 'En attente de votre decision';
        break;
      default:
        bgColor = const Color(0x1AFFFFFF);
        fgColor = const Color(0xFF94A3B8);
        icon = Icons.info_outline;
        label = statut;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: fgColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: fgColor, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: fgColor,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrestataireInfo(Map<String, dynamic> devis) {
    final prestataire = (devis['prestataire'] as Map<String, dynamic>?) ?? {};
    return _SectionCard(
      icon: Icons.person_outline_rounded,
      title: 'Prestataire',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            prestataire['nom'] ?? 'Inconnu',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          if (prestataire['specialite'] != null && prestataire['specialite'].toString().isNotEmpty)
            Text(
              prestataire['specialite'],
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            ),
        ],
      ),
    );
  }

  Widget _buildDiagnostic(Map<String, dynamic> devis) {
    final diagnostic = devis['diagnostic'] as String? ?? '';
    if (diagnostic.isEmpty) return const SizedBox.shrink();

    return _SectionCard(
      icon: Icons.medical_services_outlined,
      title: 'Diagnostic',
      child: Text(
        diagnostic,
        style: const TextStyle(
          color: Color(0xFFCBD5E1),
          fontSize: 14,
          height: 1.5,
        ),
      ),
    );
  }

  Widget _buildDateInfo(Map<String, dynamic> devis) {
    final dateProposee = devis['date_proposee'] as String?;
    final heureDebut = devis['heure_debut'] as String?;
    final heureFin = devis['heure_fin'] as String?;

    if (dateProposee == null && heureDebut == null) return const SizedBox.shrink();

    return _SectionCard(
      icon: Icons.calendar_today_outlined,
      title: 'Date proposee',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dateProposee ?? 'Non definie',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
          ),
          if (heureDebut != null) ...[
            const SizedBox(height: 4),
            Text(
              'De $heureDebut a $heureFin',
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLignes(List<dynamic> lignes) {
    if (lignes.isEmpty) return const SizedBox.shrink();

    final typeColors = {
      'FOURNITURE': BabifixDesign.cyan,
      'MAIN_OEUVRE': BabifixDesign.ciOrange,
      'DEPLACEMENT': const Color(0xFF8B5CF6),
      'AUTRE': const Color(0xFF64748B),
    };

    final typeLabels = {
      'FOURNITURE': 'Fourniture',
      'MAIN_OEUVRE': "Main d'oeuvre",
      'DEPLACEMENT': 'Deplacement',
      'AUTRE': 'Autre',
    };

    return _SectionCard(
      icon: Icons.format_list_bulleted,
      title: 'Details du devis',
      child: Column(
        children: [
          ...lignes.asMap().entries.map((entry) {
            final i = entry.key;
            final l = entry.value;
            final lineColor = typeColors[l['type_ligne']] ?? typeColors['AUTRE']!;
            final lineLabel = typeLabels[l['type_ligne']] ?? l['type_ligne'];
            final qte = l['quantite'];
            final qStr = (qte is num && qte == qte.roundToDouble())
                ? qte.toInt().toString()
                : '$qte';
            final unite = (l['unite'] ?? '').toString();
            final marque = (l['marque'] ?? '').toString();

            return Container(
              margin: EdgeInsets.only(bottom: i < lignes.length - 1 ? 16 : 0),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0F1D32),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: lineColor.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 40,
                    decoration: BoxDecoration(
                      color: lineColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${l['description']}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: lineColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                lineLabel,
                                style: TextStyle(
                                  color: lineColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                '$qStr${unite.isNotEmpty ? ' $unite' : ''} × ${_formatMontant(l['prix_unitaire'])}'
                                '${marque.isNotEmpty ? ' · $marque' : ''}',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Color(0xFF94A3B8), fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${_formatMontant(l['total'])}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: lineColor,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildTotal(Map<String, dynamic> devis) {
    // Le client paie le total TTC (= somme des lignes). La commission BABIFIX
    // est prélevée côté prestataire : on ne l'affiche PAS au client pour ne
    // pas laisser croire qu'elle s'ajoute à ce qu'il doit régler.
    final total = (devis['total_ttc'] as num?) ??
        (devis['sous_total'] as num?) ??
        0;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0A1628), Color(0xFF152A45)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x22FFFFFF)),
        boxShadow: BabifixDesign.cyanGlowShadow(opacity: 0.08),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'Total à payer',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              Text(
                '${total.toStringAsFixed(0)} FCFA',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: BabifixDesign.cyan,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Montant TTC, tout compris. Réglé via paiement sécurisé (escrow) à la prestation.',
            style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B), height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _refusing ? null : _refuseDevis,
            style: OutlinedButton.styleFrom(
              foregroundColor: BabifixDesign.error,
              side: BorderSide(color: BabifixDesign.error.withValues(alpha: 0.3)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _refusing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: BabifixRingLoader.cyan(size: 28),
                  )
                : const Text('Refuser', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: FilledButton(
            onPressed: _accepting ? null : _acceptDevis,
            style: FilledButton.styleFrom(
              backgroundColor: BabifixDesign.ciOrange,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _accepting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: BabifixRingLoader.cyan(size: 28),
                  )
                : const Text(
                    'Accepter le devis',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
          ),
        ),
      ],
    );
  }

  // Chat Section
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  StreamSubscription? _wsSubscription;
  String? _chatToken;

  Future<void> _initChatWebSocket() async {
    _chatToken = await BabifixUserStore.getApiToken();
    _loadMessages();
    _wsSubscription = WebSocketPushService.instance.chatStream.listen(
      _onNewMessage,
    );
    WebSocketPushService.instance.connect();
  }

  void _onNewMessage(Map<String, dynamic> data) {
    final ref = data['reference']?.toString() ?? '';
    if (ref == widget.reservationReference && mounted) {
      setState(() {
        _messages.insert(0, data);
      });
      _scrollToBottom();
    }
  }

  Future<void> _loadMessages() async {
    if (_chatToken == null) return;
    try {
      final uri = Uri.parse(
        '${babifixApiBaseUrl()}/api/messages/${widget.reservationReference}',
      );
      final resp = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $_chatToken'},
      );
      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(resp.body);
        setState(() {
          _messages = List<Map<String, dynamic>>.from(data['messages'] ?? []);
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('Chat load error: $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty || _chatToken == null) return;

    try {
      final uri = Uri.parse('${babifixApiBaseUrl()}/api/messages/send');
      final resp = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $_chatToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'reservation_reference': widget.reservationReference,
          'message': text,
        }),
      );
      if (resp.statusCode == 200 && mounted) {
        _chatController.clear();
        _loadMessages();
      }
    } catch (e) {
      debugPrint('Chat send error: $e');
    }
  }

  Widget _buildChatSection() {
    return Column(
      children: [
        Expanded(
          child: _messages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: BabifixDesign.cyan.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 40,
                          color: BabifixDesign.iconOnDark,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Aucun message.\nCommencez la conversation !',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _chatScrollController,
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final msg = _messages[index];
                    final isMe = msg['sender_type'] == 'client';
                    return Align(
                      alignment: isMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.75,
                        ),
                        decoration: BoxDecoration(
                          color: isMe
                              ? BabifixDesign.ciOrange
                              : const Color(0xFF152A45),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          msg['message'] ?? '',
                          style: TextStyle(
                            color: isMe ? Colors.white : const Color(0xFFCBD5E1),
                            fontSize: 14,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF152A45),
            border: Border(
              top: BorderSide(color: const Color(0x1AFFFFFF)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chatController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Envoyer un message...',
                    hintStyle: const TextStyle(color: Color(0xFF64748B)),
                    filled: true,
                    fillColor: const Color(0xFF0F1D32),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  color: BabifixDesign.ciOrange,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                  onPressed: _sendMessage,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _chatController.dispose();
    _chatScrollController.dispose();
    _wsSubscription?.cancel();
    super.dispose();
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF152A45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: BabifixDesign.cyan.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: BabifixDesign.iconOnDark),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
