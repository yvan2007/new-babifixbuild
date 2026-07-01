/// Visualisateur de reçu PDF (C9 / P11).
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import '../../babifix_design_system.dart';
import '../../services/babifix_api.dart';
import '../../shared/widgets/babifix_ring_loader.dart';

class ReceiptPdfScreen extends StatefulWidget {
  final String reservationReference;
  const ReceiptPdfScreen({super.key, required this.reservationReference});

  @override
  State<ReceiptPdfScreen> createState() => _ReceiptPdfScreenState();
}

class _ReceiptPdfScreenState extends State<ReceiptPdfScreen> {
  Uint8List? _bytes;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _download();
  }

  Future<void> _download() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await ReceiptApi.downloadPdf(widget.reservationReference);
      _bytes = Uint8List.fromList(raw);
    } on BabifixApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _share() async {
    if (_bytes == null) return;
    try {
      final dir = await getTemporaryDirectory();
      final f = File(
          '${dir.path}/recu_${widget.reservationReference}.pdf');
      await f.writeAsBytes(_bytes!);
      await Share.shareXFiles([XFile(f.path)],
          subject:
              'Reçu BABIFIX : ${widget.reservationReference}');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reçu'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
        actions: [
          if (_bytes != null)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              onPressed: _share,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: BabifixRingLoader.dark(size: 80))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline,
                            color: BabifixDesign.error, size: 56),
                        const SizedBox(height: 12),
                        Text(_error!,
                            textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _download,
                          child: const Text('Réessayer'),
                        ),
                      ],
                    ),
                  ),
                )
              : PdfPreview(
                  build: (_) async => _bytes!,
                  canChangePageFormat: false,
                  canDebug: false,
                  allowPrinting: true,
                  allowSharing: true,
                ),
    );
  }
}
