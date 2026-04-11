import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../user_store.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Modèle local
// ─────────────────────────────────────────────────────────────────────────────
class _Reservation {
  final int id;
  final String reference;
  final String title;
  final String prestataire;
  final String montant;
  final String statut;
  final String paymentType;
  final String addressLabel;
  final bool canCancel;
  final bool canRate;
  final bool canDispute;
  final bool rated;
  final int? ratingNote;
  final bool disputeOuverte;

  const _Reservation({
    required this.id,
    required this.reference,
    required this.title,
    required this.prestataire,
    required this.montant,
    required this.statut,
    required this.paymentType,
    required this.addressLabel,
    required this.canCancel,
    required this.canRate,
    required this.canDispute,
    required this.rated,
    this.ratingNote,
    required this.disputeOuverte,
  });

  factory _Reservation.fromJson(Map<String, dynamic> j) => _Reservation(
    id: j['id'] as int? ?? 0,
    reference: j['reference'] as String? ?? '',
    title: j['title'] as String? ?? '',
    prestataire: j['prestataire'] as String? ?? '',
    montant: j['montant'] as String? ?? '',
    statut: j['statut'] as String? ?? '',
    paymentType: j['payment_type'] as String? ?? '',
    addressLabel: j['address_label'] as String? ?? '',
    canCancel: j['can_cancel'] as bool? ?? false,
    canRate: j['can_rate'] as bool? ?? false,
    canDispute: j['can_dispute'] as bool? ?? false,
    rated: j['rated'] as bool? ?? false,
    ratingNote: j['rating_note'] as int?,
    disputeOuverte: j['dispute_ouverte'] as bool? ?? false,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Écran principal
// ─────────────────────────────────────────────────────────────────────────────
class ReservationsHistoryScreen extends StatefulWidget {
  final String? apiBase;
  final String? authToken;

  const ReservationsHistoryScreen({super.key, this.apiBase, this.authToken});

  @override
  State<ReservationsHistoryScreen> createState() =>
      _ReservationsHistoryScreenState();
}

class _ReservationsHistoryScreenState extends State<ReservationsHistoryScreen> {
  List<_Reservation> _all = [];
  bool _loading = true;
  String? _error;
  String _filterStatut = '';

  final _filterOptions = const [
    ('', 'Toutes'),
    ('En attente', 'En attente'),
    ('Confirmee', 'Confirmées'),
    ('En cours', 'En cours'),
    ('Terminee', 'Terminées'),
    ('Annulee', 'Annulées'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<String?> _token() async {
    if (widget.authToken != null && widget.authToken!.isNotEmpty) {
      return widget.authToken;
    }
    return BabifixUserStore.getApiToken();
  }

  String get _base => widget.apiBase ?? babifixApiBaseUrl();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final token = await _token();
    if (token == null) {
      setState(() {
        _loading = false;
        _error = 'Non connecté.';
      });
      return;
    }
    final uri = Uri.parse('$_base/api/client/reservations/list').replace(
      queryParameters: _filterStatut.isNotEmpty
          ? {'statut': _filterStatut}
          : null,
    );
    try {
      final res = await http
          .get(uri, headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final list = (data['reservations'] as List? ?? [])
            .map((e) => _Reservation.fromJson(e as Map<String, dynamic>))
            .toList();
        setState(() {
          _all = list;
          _loading = false;
        });
      } else {
        setState(() {
          _loading = false;
          _error = 'Erreur ${res.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Impossible de charger les réservations.';
      });
    }
  }

  Future<void> _cancel(_Reservation r) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Annuler la réservation ?'),
        content: Text('Annuler "${r.title}" définitivement ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Non'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: BabifixDesign.error),
            child: const Text('Annuler'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final token = await _token();
    try {
      final res = await http.post(
        Uri.parse('$_base/api/client/reservations/${r.reference}/cancel'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        _load();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Réservation annulée.')));
        }
      } else {
        final err = jsonDecode(res.body)['error'] ?? 'Erreur';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Impossible d\'annuler : $err')),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Erreur réseau.')));
      }
    }
  }

  Future<void> _openDisputeDialog(_Reservation r) async {
    final controller = TextEditingController();
    final motif = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Signaler un problème'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Réservation : ${r.reference}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              maxLength: 200,
              decoration: const InputDecoration(
                hintText: 'Décrivez le problème rencontré…',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Signaler'),
          ),
        ],
      ),
    );
    if (motif == null || motif.trim().isEmpty) return;
    final token = await _token();
    try {
      final res = await http.post(
        Uri.parse('$_base/api/client/reservations/${r.reference}/dispute'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'motif': motif.trim()}),
      );
      if (res.statusCode == 200) {
        _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Litige ouvert. Notre équipe reviendra vers vous.'),
            ),
          );
        }
      } else {
        final err = jsonDecode(res.body)['error'] ?? 'Erreur';
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Impossible : $err')));
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Erreur réseau.')));
      }
    }
  }

  Future<void> _downloadInvoice(_Reservation r) async {
    final token = await _token();
    final invoiceUrl = '$_base/api/bookings/${r.id}/invoice/';
    final uri = Uri.parse(
      invoiceUrl,
    ).replace(queryParameters: token != null ? {'token': token} : null);
    // Build the URL with Authorization as query param for direct browser access
    // The backend accepts either header or query token
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d\'ouvrir la facture.')),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Mes réservations'),
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          _FilterBar(
            options: _filterOptions,
            selected: _filterStatut,
            onChanged: (v) {
              setState(() => _filterStatut = v);
              _load();
            },
          ),
          Expanded(child: _body(cs)),
        ],
      ),
    );
  }

  Widget _body(ColorScheme cs) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: BabifixDesign.error,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(_error!),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      );
    }
    if (_all.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_today_rounded,
              size: 64,
              color: cs.outline.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            const Text(
              'Aucune réservation',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Vos réservations apparaîtront ici.',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(BabifixDesign.spaceLG),
        itemCount: _all.length,
        separatorBuilder: (_, __) =>
            const SizedBox(height: BabifixDesign.spaceSM),
        itemBuilder: (ctx, i) => _ReservationCard(
          reservation: _all[i],
          onCancel: () => _cancel(_all[i]),
          onDispute: () => _openDisputeDialog(_all[i]),
          onRate: () => GoRouter.of(ctx)
              .push('/reservations/${_all[i].reference}/rate')
              .then((_) => _load()),
          onDownloadInvoice: () => _downloadInvoice(_all[i]),
          apiBase: _base,
          authToken: widget.authToken,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget barre de filtres
// ─────────────────────────────────────────────────────────────────────────────
class _FilterBar extends StatelessWidget {
  final List<(String, String)> options;
  final String selected;
  final void Function(String) onChanged;

  const _FilterBar({
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final (val, label) = options[i];
          final active = selected == val;
          return FilterChip(
            label: Text(label),
            selected: active,
            onSelected: (_) => onChanged(val),
            selectedColor: BabifixDesign.ciOrange.withValues(alpha: 0.15),
            checkmarkColor: BabifixDesign.ciOrange,
            labelStyle: TextStyle(
              color: active
                  ? BabifixDesign.ciOrange
                  : cs.onSurface.withValues(alpha: 0.7),
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              fontSize: 12,
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget carte réservation
// ─────────────────────────────────────────────────────────────────────────────
class _ReservationCard extends StatelessWidget {
  final _Reservation reservation;
  final VoidCallback onCancel;
  final VoidCallback onDispute;
  final VoidCallback onRate;
  final VoidCallback onDownloadInvoice;
  final String apiBase;
  final String? authToken;

  const _ReservationCard({
    required this.reservation,
    required this.onCancel,
    required this.onDispute,
    required this.onRate,
    required this.onDownloadInvoice,
    required this.apiBase,
    this.authToken,
  });

  Color _statutColor() {
    switch (reservation.statut) {
      case 'Terminee':
        return BabifixDesign.success;
      case 'Annulee':
        return BabifixDesign.error;
      case 'En cours':
        return BabifixDesign.ciOrange;
      case 'Confirmee':
        return BabifixDesign.ciBlue;
      default:
        return BabifixDesign.warning;
    }
  }

  String _statutLabel() {
    switch (reservation.statut) {
      case 'Terminee':
        return 'Terminée';
      case 'Annulee':
        return 'Annulée';
      case 'En cours':
        return 'En cours';
      case 'Confirmee':
        return 'Confirmée';
      default:
        return 'En attente';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final statColor = _statutColor();
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BabifixDesign.radiusMD),
        side: BorderSide(color: cs.outlineVariant, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(BabifixDesign.spaceMD),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Text(
                    reservation.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(
                      BabifixDesign.radiusPill,
                    ),
                  ),
                  child: Text(
                    _statutLabel(),
                    style: TextStyle(
                      color: statColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // ── Infos ───────────────────────────────────────────────────
            _InfoRow(icon: Icons.person_rounded, text: reservation.prestataire),
            if (reservation.addressLabel.isNotEmpty)
              _InfoRow(
                icon: Icons.location_on_rounded,
                text: reservation.addressLabel,
              ),
            _InfoRow(
              icon: Icons.payments_rounded,
              text: '${reservation.montant} • ${reservation.paymentType}',
            ),
            const SizedBox(height: 4),
            Text(
              reservation.reference,
              style: TextStyle(
                fontSize: 11,
                color: cs.outline,
                fontFamily: 'monospace',
              ),
            ),
            // ── Actions ─────────────────────────────────────────────────
            if (reservation.canCancel ||
                reservation.canRate ||
                reservation.canDispute ||
                reservation.disputeOuverte ||
                reservation.statut == 'Terminee')
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (reservation.canCancel)
                      OutlinedButton.icon(
                        onPressed: onCancel,
                        icon: const Icon(Icons.cancel_outlined, size: 16),
                        label: const Text('Annuler'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: BabifixDesign.error,
                          side: const BorderSide(color: BabifixDesign.error),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                        ),
                      ),
                    if (reservation.canRate && !reservation.rated)
                      FilledButton.icon(
                        onPressed: onRate,
                        icon: const Icon(Icons.star_rounded, size: 16),
                        label: const Text('Donner un avis'),
                        style: FilledButton.styleFrom(
                          backgroundColor: BabifixDesign.ciOrange,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                        ),
                      ),
                    if (reservation.rated && reservation.ratingNote != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            color: Colors.amber,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${reservation.ratingNote}/5',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    if (reservation.canDispute)
                      OutlinedButton.icon(
                        onPressed: onDispute,
                        icon: const Icon(Icons.report_outlined, size: 16),
                        label: const Text('Signaler'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: BabifixDesign.warning,
                          side: const BorderSide(color: BabifixDesign.warning),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                        ),
                      ),
                    if (reservation.disputeOuverte)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: BabifixDesign.warning.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(
                            BabifixDesign.radiusPill,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.warning_rounded,
                              size: 14,
                              color: BabifixDesign.warning,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Litige en cours',
                              style: TextStyle(
                                fontSize: 11,
                                color: BabifixDesign.warning,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (reservation.statut == 'Terminee')
                      OutlinedButton.icon(
                        onPressed: onDownloadInvoice,
                        icon: const Icon(Icons.download_rounded, size: 16),
                        label: const Text('Facture PDF'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: BabifixDesign.ciBlue,
                          side: const BorderSide(color: BabifixDesign.ciBlue),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Icon(icon, size: 13, color: cs.outline),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.75),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
