import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../babifix_api_config.dart';
import '../../user_store.dart';
import '../../shared/widgets/babifix_ring_loader.dart';

class MyDisputesScreen extends StatefulWidget {
  const MyDisputesScreen({super.key});

  @override
  State<MyDisputesScreen> createState() => _MyDisputesScreenState();
}

class _MyDisputesScreenState extends State<MyDisputesScreen> {
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
      final token = await BabifixUserStore.getApiToken();
      final res = await http.get(
        Uri.parse('${babifixApiBaseUrl()}/api/client/disputes/'),
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
          color: _kSuccess,
          icon: Icons.payments_rounded,
          label: 'Remboursé'
        );
      case 'Liberer paiement':
        return (
          color: _kAmber,
          icon: Icons.gavel_rounded,
          label: 'Décision contre vous'
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
    return Scaffold(
      backgroundColor: const Color(0xFF050D1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Mes litiges',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
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
            child: const Icon(Icons.verified_rounded,
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
            'Vos interventions se passent bien.\nContinuez comme ça !',
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
    final hasPrestaResp = d['has_presta_response'] == true;
    final photosCount = (d['photos_client_count'] ?? 0) as int;
    final decisionNote = (d['decision_note'] ?? '').toString();

    return Container(
      decoration: BoxDecoration(
        color: _kNavy,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isOpen
              ? decStyle.color.withValues(alpha: 0.45)
              : Colors.white.withValues(alpha: 0.08),
          width: isOpen ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header : décision badge + priorité
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
          ),
          // Body
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                  (d['reservation_title'] ?? 'N/A').toString(),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 12.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                // Motif
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
                // Métriques
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _chip(
                      Icons.tag_rounded,
                      d['reference']?.toString() ?? '',
                      _kCyan,
                    ),
                    if (montant > 0)
                      _chip(
                        Icons.shield_rounded,
                        '${montant.toStringAsFixed(0)} F bloqués',
                        _kAmber,
                      ),
                    if (photosCount > 0)
                      _chip(
                        Icons.image_rounded,
                        '$photosCount photo${photosCount > 1 ? "s" : ""}',
                        _kCyan,
                      ),
                    if (hasPrestaResp)
                      _chip(
                        Icons.reply_rounded,
                        'Réponse presta',
                        _kSuccess,
                      ),
                  ],
                ),
                // Note décision si fermé
                if (!isOpen && decisionNote.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: decStyle.color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: decStyle.color.withValues(alpha: 0.30),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Note de l\'admin',
                          style: TextStyle(
                            color: decStyle.color,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          decisionNote,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
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
