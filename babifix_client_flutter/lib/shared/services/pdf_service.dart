import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

class PdfService {
  static Future<File> generateDevisPdf(Map<String, dynamic> devis) async {
    final pdf = pw.Document();

    final prestataire = (devis['prestataire'] as Map<String, dynamic>?) ?? {};
    final lignes = (devis['lignes'] as List?) ?? [];
    final diagnostic = devis['diagnostic'] as String? ?? '';
    final dateProposee = devis['date_proposee'] as String? ?? 'Non précisée';
    final sousTotal = (devis['sous_total'] as num?) ?? 0;
    final commission = (devis['commission_montant'] as num?) ?? 0;
    final total = (devis['total_ttc'] as num?) ?? 0;
    final statut = devis['statut'] as String? ?? '';

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              pw.SizedBox(height: 20),
              _buildPrestataireInfo(prestataire),
              pw.SizedBox(height: 20),
              _buildDiagnostic(diagnostic),
              pw.SizedBox(height: 20),
              _buildDateInfo(dateProposee),
              pw.SizedBox(height: 20),
              _buildLignesTable(lignes),
              pw.SizedBox(height: 20),
              _buildTotalSection(sousTotal, commission, total),
              pw.SizedBox(height: 20),
              _buildFooter(statut),
            ],
          );
        },
      ),
    );

    final output = await getTemporaryDirectory();
    final file = File(
      '${output.path}/devis_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  static pw.Widget _buildHeader() {
    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue600,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
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
                'Votre partenaire de confiance',
                style: const pw.TextStyle(fontSize: 12, color: PdfColors.white),
              ),
            ],
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
    );
  }

  static pw.Widget _buildPrestataireInfo(Map<String, dynamic> prestataire) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(15),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Prestataire',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue600,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            '${prestataire['nom'] ?? ''} ${prestataire['prenom'] ?? ''}',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text('${prestataire['telephone'] ?? ''}'),
          pw.Text('${prestataire['email'] ?? ''}'),
        ],
      ),
    );
  }

  static pw.Widget _buildDiagnostic(String diagnostic) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(15),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(8),
      ),
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
    );
  }

  static pw.Widget _buildDateInfo(String dateProposee) {
    return pw.Row(
      children: [
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Date proposée',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(dateProposee),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildLignesTable(List lignes) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _tableHeader('Description'),
            _tableHeader('Quantité'),
            _tableHeader('Prix unitaire'),
            _tableHeader('Total'),
          ],
        ),
        ...lignes.map(
          (ligne) => pw.TableRow(
            children: [
              _tableCell('${ligne['description'] ?? ''}'),
              _tableCell('${ligne['quantite'] ?? 1}'),
              _tableCell('${_formatMontant(ligne['prix_unitaire'])}'),
              _tableCell('${_formatMontant(ligne['montant'])}'),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _tableHeader(String text) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(text, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
    );
  }

  static pw.Widget _tableCell(String text) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(text),
    );
  }

  static pw.Widget _buildTotalSection(
    num sousTotal,
    num commission,
    num total,
  ) {
    return pw.Container(
      alignment: pw.Alignment.centerRight,
      child: pw.Container(
        width: 200,
        padding: const pw.EdgeInsets.all(15),
        decoration: pw.BoxDecoration(
          color: PdfColors.blue50,
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Column(
          children: [
            _totalRow('Sous-total', sousTotal),
            pw.Divider(),
            _totalRow('Commission (18%)', commission),
            pw.Divider(),
            _totalRow('Total TTC', total, isBold: true),
          ],
        ),
      ),
    );
  }

  static pw.Widget _totalRow(String label, num value, {bool isBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
          pw.Text(
            '${_formatMontant(value)} FCFA',
            style: pw.TextStyle(
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildFooter(String statut) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(15),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            'Conditions',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 5),
          pw.Text('• Devis valable 7 jours'),
          pw.Text('• Prix TTC, commission incluse'),
          pw.Text('• Paiement après intervention'),
          pw.SizedBox(height: 10),
          pw.Text(
            'Statut: ${_getStatutLabel(statut)}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
  }

  static String _formatMontant(dynamic value) {
    if (value == null) return '0';
    final num v = value is String ? num.tryParse(value) ?? 0 : value;
    return v
        .toStringAsFixed(0)
        .replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]} ',
        );
  }

  static String _getStatutLabel(String statut) {
    switch (statut) {
      case 'DEVIS_ENVOYE':
        return 'En attente de validation';
      case 'DEVIS_ACCEPTE':
        return 'Accepté';
      case 'DEVIS_REFUSE':
        return 'Refusé';
      default:
        return statut;
    }
  }

  static Future<void> printDevis(Map<String, dynamic> devis) async {
    final file = await generateDevisPdf(devis);
    await Printing.layoutPdf(onLayout: (format) => file.readAsBytes());
  }

  static Future<void> shareDevisPdf(Map<String, dynamic> devis) async {
    final file = await generateDevisPdf(devis);
    await Printing.sharePdf(
      bytes: await file.readAsBytes(),
      filename: 'devis_babifix.pdf',
    );
  }
}
