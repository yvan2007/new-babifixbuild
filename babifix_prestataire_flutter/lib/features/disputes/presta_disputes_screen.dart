import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../babifix_api_config.dart';
import '../../shared/auth_utils.dart';
import 'presta_dispute_respond_screen.dart';
import '../../shared/widgets/babifix_ring_loader.dart';

/// Liste des litiges du prestataire avec accès à la réponse / suivi.
class PrestaDisputesScreen extends StatefulWidget {
  const PrestaDisputesScreen({super.key});

  @override
  State<PrestaDisputesScreen> createState() => _PrestaDisputesScreenState();
}

class _PrestaDisputesScreenState extends State<PrestaDisputesScreen> {
  static const _kNavy = Color(0xFF0B1B34);
  static const _kCyan = Color(0xFF4CC9F0);
  static const _kAmber = Color(0xFFF59E0B);
  static const _kError = Color(0xFFEF4444);
  static const _kSuccess = Color(0xFF22C55E);

  List<Map<String, dynamic>> _disputes = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = await readStoredApiToken();
      final res = await http.get(
        Uri.parse('${babifixApiBaseUrl()}/api/prestataire/disputes/'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _disputes = List<Map<String, dynamic>>.from(d['disputes'] ?? []);
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Erreur ${res.statusCode}';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Erreur réseau : $e';
        _loading = false;
      });
    }
  }

  ({Color color, IconData icon, String label}) _decisionStyle(String dec) {
    switch (dec) {
      case 'Rembourser client':
        return (
          color: _kError,
          icon: Icons.payments_rounded,
          label: 'Remboursement client'
        );
      case 'Liberer paiement':
        return (
          color: _kSuccess,
          icon: Icons.check_circle_rounded,
          label: 'Décision en votre faveur'
        );
      case 'Partage partiel':
        return (
          color: _kCyan,
          icon: Icons.balance_rounded,
          label: 'Partage partiel'
        );
      case 'En cours':
      default:
        return (
          color: _kAmber,
          icon: Icons.hourglass_top_rounded,
          label: 'En cours d\'examen'
        );
    }
  }

  Color _priorityColor(String p) {
    switch (p) {
      case 'Haute':
        return _kError;
      case 'Basse':
        return _kSuccess;
      default:
        return _kAmber;
    }
  }

  @override
  Widget build(BuildContext context) {
    final openCount =
        _disputes.where((d) => d['is_open'] == true).length;
    return Scaffold(
      backgroundColor: const Color(0xFF050D1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            const Text(
              'Litiges',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
            ),
            if (openCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _kError,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$openCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white70, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: _kCyan,
        backgroundColor: _kNavy,
        child: _loading
            ? const Center(child: BabifixRingLoader.cyan(size: 28))
            : _error != null
                ? _buildError()
                : _disputes.isEmpty
                    ? _buildEmpty()
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                        itemCount: _disputes.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 12),
                        itemBuilder: (_, i) => _buildCard(_disputes[i]),
                      ),
      ),
    );
  }

  Widget _buildEmpty() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        Center(
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: _kSuccess.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.thumb_up_alt_rounded,
                color: _kSuccess, size: 42),
          ),
        ),
        const SizedBox(height: 20),
        const Center(
          child: Text(
            'Aucun litige',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Center(
          child: Text(
            'Vos clients sont satisfaits.\nContinuez votre travail de qualité !',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: _kError, size: 48),
            const SizedBox(height: 14),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _load,
              style: FilledButton.styleFrom(
                backgroundColor: _kCyan,
                foregroundColor: _kNavy,
              ),
              child: const Text('Réessayer',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> d) {
    final isOpen = d['is_open'] == true;
    final decStyle = _decisionStyle(d['decision']?.toString() ?? '');
    final priority = (d['priorite'] ?? 'Moyenne').toString();
    final priorityColor = _priorityColor(priority);
    final montant = (d['montant_concerne'] ?? 0).toDouble();
    final hasResponded = d['has_presta_response'] == true;
    final clientPhotos = (d['photos_client_count'] ?? 0) as int;
    final reference = (d['reference'] ?? '').toString();

    return Material(
      color: _kNavy,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: !isOpen
            ? null
            : () async {
                final ok = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => PrestaDisputeRespondScreen(
                      disputeRef: reference,
                      categorieLabel:
                          (d['categorie_label'] ?? 'Litige').toString(),
                      motif: (d['motif'] ?? '').toString(),
                      clientName: (d['client_name'] ?? 'N/A').toString(),
                      reservationTitle:
                          (d['reservation_title'] ?? '').toString(),
                      priorite: priority,
                      photosClientCount: clientPhotos,
                      hasAlreadyResponded: hasResponded,
                    ),
                  ),
                );
                if (ok == true) _load();
              },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isOpen
                  ? decStyle.color.withValues(alpha: 0.45)
                  : Colors.white.withValues(alpha: 0.08),
              width: isOpen ? 1.5 : 1,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: decStyle.color.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(decStyle.icon, color: decStyle.color, size: 13),
                        const SizedBox(width: 5),
                        Text(
                          decStyle.label,
                          style: TextStyle(
                            color: decStyle.color,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: priorityColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    priority,
                    style: TextStyle(
                      color: priorityColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                (d['categorie_label'] ?? 'Litige').toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Client : ${d['client_name'] ?? 'N/A'}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                (d['motif'] ?? '').toString(),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 13,
                  height: 1.45,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _chip(Icons.tag_rounded, reference, _kCyan),
                  if (montant > 0)
                    _chip(Icons.shield_rounded,
                        '${montant.toStringAsFixed(0)} F bloqués', _kAmber),
                  if (clientPhotos > 0)
                    _chip(Icons.image_rounded,
                        '$clientPhotos photo${clientPhotos > 1 ? "s" : ""}',
                        _kCyan),
                  if (hasResponded)
                    _chip(Icons.check_circle_rounded, 'Vous avez répondu',
                        _kSuccess)
                  else if (isOpen)
                    _chip(Icons.priority_high_rounded, 'À répondre', _kError),
                ],
              ),
              if (isOpen) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 38,
                        decoration: BoxDecoration(
                          color: _kCyan,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            hasResponded
                                ? 'Compléter ma réponse'
                                : 'Apporter ma version',
                            style: const TextStyle(
                              color: Color(0xFF0B1B34),
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
