import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:lottie/lottie.dart';
import '../../babifix_api_config.dart';
import '../../user_store.dart';
import '../../shared/services/websocket_push_service.dart';
import '../../shared/services/lottie_service.dart';
import '../../shared/services/confetti_toast_service.dart';
import '../../shared/services/haptic_service.dart';

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
        _error = 'Non connecté';
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
        setState(() {
          _loading = false;
          _error = 'Erreur: ${resp.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
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
        if (mounted) {
          HapticService.success();
          ConfettiService.showSuccess(context, 'Devis accepté!');
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Devis accepté!')));
          _loadDevis();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Erreur: ${resp.statusCode}')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur: $e')));
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
        title: const Text('Refuser le devis'),
        content: TextField(
          controller: motifController,
          decoration: const InputDecoration(
            labelText: 'Motif du refus',
            hintText: 'Pourquoi refusez-vous ce devis?',
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, motifController.text),
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Devis refusé')));
          _loadDevis();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur: $e')));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur PDF: $e')));
      }
    }
  }

  pw.Widget _buildPdfContent() {
    final devis = _devis!;
    final prestataire = (devis['prestataire'] as Map<String, dynamic>?) ?? {};
    final lignes = (devis['lignes'] as List?) ?? [];
    final diagnostic = devis['diagnostic'] as String? ?? '';
    final dateProposee = devis['date_proposee'] as String? ?? 'Non précisée';
    final sousTotal = (devis['sous_total'] as num?) ?? 0;
    final commission = (devis['commission_montant'] as num?) ?? 0;
    final total = (devis['total_ttc'] as num?) ?? 0;

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
                    'Qté',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Text(
                    'Prix',
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
                    child: pw.Text('${ligne['quantite'] ?? 1}'),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text('${ligne['montant'] ?? 0}'),
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
            child: pw.Column(
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Sous-total'),
                    pw.Text('${_formatMontant(sousTotal)}'),
                  ],
                ),
                pw.Divider(),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Commission (18%)'),
                    pw.Text('${_formatMontant(commission)}'),
                  ],
                ),
                pw.Divider(),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Total TTC',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text(
                      '${_formatMontant(total)}',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        pw.SizedBox(height: 20),
        pw.Text('Date proposée: $dateProposee'),
        pw.SizedBox(height: 10),
        pw.Text(
          'Conditions: Devis valable 7 jours, Prix TTC, Commission incluse',
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
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: widget.onBack,
          ),
          title: const Text('Devis'),
          actions: [
            IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              tooltip: 'Exporter en PDF',
              onPressed: _devis != null ? _exportPdf : null,
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Détails'),
              Tab(icon: Icon(Icons.chat_bubble_outline), text: 'Chat'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(child: Text(_error!))
            : _devis == null
            ? const Center(child: Text('Aucun devis disponible'))
            : TabBarView(children: [_buildDevisContent(), _buildChatSection()]),
      ),
    );
  }

  Widget _buildDevisContent() {
    final devis = _devis!;
    final lignes = (devis['lignes'] as List?) ?? [];
    final statut = devis['statut'] as String? ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatutBanner(statut),
          const SizedBox(height: 16),
          _buildPrestataireInfo(devis),
          const SizedBox(height: 16),
          _buildDiagnostic(devis),
          const SizedBox(height: 16),
          _buildDateInfo(devis),
          const SizedBox(height: 16),
          _buildLignes(lignes),
          const SizedBox(height: 16),
          _buildTotal(devis),
          if (statut == 'ENVOYE') ...[
            const SizedBox(height: 24),
            _buildActionButtons(),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildStatutBanner(String statut) {
    Color bgColor;
    Color textColor;
    String label;

    switch (statut) {
      case 'ACCEPTE':
        bgColor = Colors.green.withValues(alpha: 0.2);
        textColor = Colors.green;
        label = 'Devis accepté';
        break;
      case 'REFUSE':
        bgColor = Colors.red.withValues(alpha: 0.2);
        textColor = Colors.red;
        label = 'Devis refusé';
        break;
      case 'ENVOYE':
        bgColor = Colors.blue.withValues(alpha: 0.2);
        textColor = Colors.blue;
        label = 'En attente de votre décision';
        break;
      default:
        bgColor = Colors.grey.withValues(alpha: 0.2);
        textColor = Colors.grey;
        label = statut;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildPrestataireInfo(Map<String, dynamic> devis) {
    final prestataire = (devis['prestataire'] as Map<String, dynamic>?) ?? {};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Prestataire',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(prestataire['nom'] ?? 'Inconnu'),
            Text(prestataire['specialite'] ?? ''),
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnostic(Map<String, dynamic> devis) {
    final diagnostic = devis['diagnostic'] as String? ?? '';
    if (diagnostic.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Diagnostic',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(diagnostic),
          ],
        ),
      ),
    );
  }

  Widget _buildDateInfo(Map<String, dynamic> devis) {
    final dateProposee = devis['date_proposee'] as String?;
    final heureDebut = devis['heure_debut'] as String?;
    final heureFin = devis['heure_fin'] as String?;

    if (dateProposee == null && heureDebut == null)
      return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Date proposée',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(dateProposee ?? 'Non définie'),
            if (heureDebut != null) Text('De $heureDebut à $heureFin'),
          ],
        ),
      ),
    );
  }

  Widget _buildLignes(List<dynamic> lignes) {
    if (lignes.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Détails du devis',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 8),
            ...lignes.map(
              (l) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${l['description']} (x${l['quantite']})',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    Text(
                      '${l['total'].toStringAsFixed(0)} francs CFA',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotal(Map<String, dynamic> devis) {
    final sousTotal = (devis['sous_total'] as num?) ?? 0;
    final commission = (devis['commission_montant'] as num?) ?? 0;
    final total = (devis['total_ttc'] as num?) ?? 0;
    final commissionRate = (devis['commission_rate'] as num?) ?? 0;

    return Card(
      color: const Color(0xFF0A1628),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Sous-total',
                  style: TextStyle(color: Colors.white70),
                ),
                Text(
                  '${sousTotal.toStringAsFixed(0)} francs CFA',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Commission ($commissionRate%)',
                  style: const TextStyle(color: Colors.white70),
                ),
                Text(
                  '${commission.toStringAsFixed(0)} francs CFA',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
            const Divider(color: Colors.white30),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                Text(
                  '${total.toStringAsFixed(0)} francs CFA',
                  style: const TextStyle(
                    color: Color(0xFF4CC9F0),
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ],
        ),
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
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
            ),
            child: Text(_refusing ? '...' : 'Refuser'),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: FilledButton(
            onPressed: _accepting ? null : _acceptDevis,
            child: Text(_accepting ? '...' : 'Accepter le devis'),
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
              ? const Center(
                  child: Text(
                    'Aucun message.\nCommencez la conversation !',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
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
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isMe
                              ? Theme.of(context).primaryColor
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          msg['message'] ?? '',
                          style: TextStyle(
                            color: isMe ? Colors.white : Colors.black,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chatController,
                  decoration: const InputDecoration(
                    hintText: 'Envoyer un message...',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.send),
                color: Theme.of(context).primaryColor,
                onPressed: _sendMessage,
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
