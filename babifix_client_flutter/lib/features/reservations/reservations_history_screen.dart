import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../user_store.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens
// ─────────────────────────────────────────────────────────────────────────────
const _kNavy     = Color(0xFF050D1A);
const _kCard     = Color(0xFF0D1B2E);
const _kBlue     = Color(0xFF2563EB);
const _kCyan     = Color(0xFF4CC9F0);
const _kGreen    = Color(0xFF10B981);
const _kAmber    = Color(0xFFF59E0B);
const _kRed      = Color(0xFFEF4444);
const _kPurple   = Color(0xFF8B5CF6);

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

  Color get statusColor {
    switch (statut) {
      case 'Terminee': return _kGreen;
      case 'Annulee':  return _kRed;
      case 'En cours': return _kAmber;
      case 'Confirmee': return _kBlue;
      default: return _kPurple;
    }
  }

  String get statusLabel {
    switch (statut) {
      case 'Terminee':  return 'Terminée';
      case 'Annulee':   return 'Annulée';
      case 'En cours':  return 'En cours';
      case 'Confirmee': return 'Confirmée';
      default: return 'En attente';
    }
  }

  IconData get statusIcon {
    switch (statut) {
      case 'Terminee':  return Icons.check_circle_rounded;
      case 'Annulee':   return Icons.cancel_rounded;
      case 'En cours':  return Icons.pending_rounded;
      case 'Confirmee': return Icons.verified_rounded;
      default: return Icons.schedule_rounded;
    }
  }
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

class _ReservationsHistoryScreenState extends State<ReservationsHistoryScreen>
    with SingleTickerProviderStateMixin {
  List<_Reservation> _all = [];
  bool _loading = true;
  String? _error;
  String _filterStatut = '';
  late final AnimationController _shimmerCtrl;

  static const _filterOptions = [
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
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _load();
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    super.dispose();
  }

  Future<String?> _token() async {
    if (widget.authToken != null && widget.authToken!.isNotEmpty) {
      return widget.authToken;
    }
    return BabifixUserStore.getApiToken();
  }

  String get _base => widget.apiBase ?? babifixApiBaseUrl();

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final token = await _token();
    if (token == null) {
      setState(() { _loading = false; _error = 'Non connecté.'; });
      return;
    }
    final uri = Uri.parse('$_base/api/client/reservations/list').replace(
      queryParameters: _filterStatut.isNotEmpty ? {'statut': _filterStatut} : null,
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
        setState(() { _all = list; _loading = false; });
      } else {
        setState(() { _loading = false; _error = 'Erreur ${res.statusCode}'; });
      }
    } catch (_) {
      setState(() { _loading = false; _error = 'Impossible de charger les réservations.'; });
    }
  }

  Future<void> _cancel(_Reservation r) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => _PremiumDialog(
        title: 'Annuler la réservation ?',
        body: 'Annuler "${r.title}" définitivement ?',
        confirmLabel: 'Annuler la réservation',
        confirmColor: _kRed,
        onConfirm: () => Navigator.pop(ctx, true),
        onCancel: () => Navigator.pop(ctx, false),
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
          _showToast('Réservation annulée.', icon: Icons.check_circle_rounded, color: _kGreen);
        }
      } else {
        final err = jsonDecode(res.body)['error'] ?? 'Erreur';
        if (mounted) _showToast('Impossible d\'annuler : $err', icon: Icons.error_rounded, color: _kRed);
      }
    } catch (_) {
      if (mounted) _showToast('Erreur réseau.', icon: Icons.wifi_off_rounded, color: _kAmber);
    }
  }

  Future<void> _openDisputeDialog(_Reservation r) async {
    final controller = TextEditingController();
    final motif = await showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: _kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _kAmber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.report_problem_rounded, color: _kAmber, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(child: Text('Signaler un problème',
                    style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800))),
              ]),
              const SizedBox(height: 6),
              Text(r.reference, style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11, fontFamily: 'monospace')),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                maxLines: 3,
                maxLength: 200,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Décrivez le problème rencontré…',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.06),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _kCyan),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Center(child: Text('Annuler', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700))),
                  ),
                )),
                const SizedBox(width: 10),
                Expanded(flex: 2, child: GestureDetector(
                  onTap: () => Navigator.pop(ctx, controller.text),
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [_kAmber, Color(0xFFD97706)]),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Center(child: Text('Signaler', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
                  ),
                )),
              ]),
            ],
          ),
        ),
      ),
    );
    if (motif == null || motif.trim().isEmpty) return;
    final token = await _token();
    try {
      final res = await http.post(
        Uri.parse('$_base/api/client/reservations/${r.reference}/dispute'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode({'motif': motif.trim()}),
      );
      if (res.statusCode == 200) {
        _load();
        if (mounted) _showToast('Litige ouvert. Notre équipe reviendra vers vous.', icon: Icons.check_circle_rounded, color: _kGreen);
      } else {
        final err = jsonDecode(res.body)['error'] ?? 'Erreur';
        if (mounted) _showToast('Impossible : $err', icon: Icons.error_rounded, color: _kRed);
      }
    } catch (_) {
      if (mounted) _showToast('Erreur réseau.', icon: Icons.wifi_off_rounded, color: _kAmber);
    }
  }

  Future<void> _downloadInvoice(_Reservation r) async {
    final token = await _token();
    final uri = Uri.parse('$_base/api/bookings/${r.id}/invoice/').replace(
      queryParameters: token != null ? {'token': token} : null,
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      _showToast('Impossible d\'ouvrir la facture.', icon: Icons.error_rounded, color: _kRed);
    }
  }

  void _showToast(String msg, {required IconData icon, required Color color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _kCard,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Row(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(msg, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
        ]),
      ),
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: _kNavy,
        colorScheme: const ColorScheme.dark(primary: _kCyan, surface: _kCard),
      ),
      child: Scaffold(
        backgroundColor: _kNavy,
        appBar: AppBar(
          backgroundColor: const Color(0xFF060E1C),
          elevation: 0,
          title: const Text('Mes réservations',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: _kCyan),
              onPressed: _load,
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(52),
            child: _PremiumFilterBar(
              options: _filterOptions,
              selected: _filterStatut,
              onChanged: (v) { setState(() => _filterStatut = v); _load(); },
            ),
          ),
        ),
        body: _body(),
      ),
    );
  }

  Widget _body() {
    if (_loading) return _ShimmerList(ctrl: _shimmerCtrl);
    if (_error != null) return _ErrorState(message: _error!, onRetry: _load);
    if (_all.isEmpty) return _EmptyState(filter: _filterStatut);
    return RefreshIndicator(
      onRefresh: _load,
      color: _kCyan,
      backgroundColor: _kCard,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        itemCount: _all.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (ctx, i) => _PremiumReservationCard(
          reservation: _all[i],
          onCancel: () => _cancel(_all[i]),
          onDispute: () => _openDisputeDialog(_all[i]),
          onRate: () => GoRouter.of(ctx).push('/reservations/${_all[i].reference}/rate').then((_) => _load()),
          onDownloadInvoice: () => _downloadInvoice(_all[i]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Barre de filtres premium
// ─────────────────────────────────────────────────────────────────────────────
class _PremiumFilterBar extends StatelessWidget {
  final List<(String, String)> options;
  final String selected;
  final void Function(String) onChanged;

  const _PremiumFilterBar({required this.options, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      color: const Color(0xFF060E1C),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final (val, label) = options[i];
          final active = selected == val;
          return GestureDetector(
            onTap: () => onChanged(val),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                gradient: active
                    ? const LinearGradient(colors: [_kCyan, Color(0xFF0284C7)])
                    : null,
                color: active ? null : Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: active ? Colors.transparent : Colors.white.withValues(alpha: 0.10),
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: active ? Colors.white : Colors.white.withValues(alpha: 0.55),
                  fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                  fontSize: 12,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Carte réservation premium
// ─────────────────────────────────────────────────────────────────────────────
class _PremiumReservationCard extends StatelessWidget {
  final _Reservation reservation;
  final VoidCallback onCancel;
  final VoidCallback onDispute;
  final VoidCallback onRate;
  final VoidCallback onDownloadInvoice;

  const _PremiumReservationCard({
    required this.reservation,
    required this.onCancel,
    required this.onDispute,
    required this.onRate,
    required this.onDownloadInvoice,
  });

  @override
  Widget build(BuildContext context) {
    final c = reservation.statusColor;
    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.25)),
        boxShadow: [BoxShadow(color: c.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(
        children: [
          // ── Stripe de statut ──────────────────────────────────────────
          Container(
            height: 4,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [c, c.withValues(alpha: 0.3)]),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ─────────────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        reservation.title,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: c.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: c.withValues(alpha: 0.4)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(reservation.statusIcon, size: 11, color: c),
                        const SizedBox(width: 4),
                        Text(reservation.statusLabel, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w800)),
                      ]),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ── Infos ───────────────────────────────────────────────
                _InfoRow(icon: Icons.person_rounded, text: reservation.prestataire, iconColor: _kCyan),
                if (reservation.addressLabel.isNotEmpty)
                  _InfoRow(icon: Icons.location_on_rounded, text: reservation.addressLabel, iconColor: _kAmber),
                _InfoRow(icon: Icons.payments_rounded,
                  text: '${reservation.montant} • ${reservation.paymentType}', iconColor: _kGreen),

                const SizedBox(height: 6),
                // ── Référence ───────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    reservation.reference,
                    style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.35), fontFamily: 'monospace'),
                  ),
                ),

                // ── Actions ─────────────────────────────────────────────
                if (_hasActions) ...[
                  const SizedBox(height: 14),
                  const Divider(color: Color(0x12FFFFFF), height: 1),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: _buildActions()),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool get _hasActions =>
      reservation.canCancel || reservation.canRate || reservation.canDispute ||
      reservation.disputeOuverte || reservation.statut == 'Terminee' || reservation.rated;

  List<Widget> _buildActions() {
    final actions = <Widget>[];

    if (reservation.canCancel)
      actions.add(_ActionBtn(label: 'Annuler', icon: Icons.cancel_rounded, color: _kRed, onTap: onCancel));

    if (reservation.canRate && !reservation.rated)
      actions.add(_ActionBtn(label: 'Donner un avis', icon: Icons.star_rounded, color: _kAmber, onTap: onRate, filled: true));

    if (reservation.rated && reservation.ratingNote != null)
      actions.add(_RatingBadge(note: reservation.ratingNote!));

    if (reservation.canDispute)
      actions.add(_ActionBtn(label: 'Signaler', icon: Icons.report_rounded, color: _kAmber, onTap: onDispute));

    if (reservation.disputeOuverte)
      actions.add(_DisputeTag());

    if (reservation.statut == 'Terminee')
      actions.add(_ActionBtn(label: 'Facture PDF', icon: Icons.download_rounded, color: _kCyan, onTap: onDownloadInvoice));

    return actions;
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool filled;

  const _ActionBtn({required this.label, required this.icon, required this.color, required this.onTap, this.filled = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: filled ? color : color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: filled ? null : Border.all(color: color.withValues(alpha: 0.40)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: filled ? Colors.white : color),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: filled ? Colors.white : color, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

class _RatingBadge extends StatelessWidget {
  final int note;
  const _RatingBadge({required this.note});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        ...List.generate(5, (i) => Icon(i < note ? Icons.star_rounded : Icons.star_outline_rounded, size: 13, color: Colors.amber)),
        const SizedBox(width: 5),
        Text('$note/5', style: const TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

class _DisputeTag extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: _kAmber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kAmber.withValues(alpha: 0.40)),
      ),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.warning_rounded, size: 14, color: _kAmber),
        SizedBox(width: 5),
        Text('Litige en cours', style: TextStyle(color: _kAmber, fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Info row
// ─────────────────────────────────────────────────────────────────────────────
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color iconColor;
  const _InfoRow({required this.icon, required this.text, required this.iconColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Icon(icon, size: 13, color: iconColor.withValues(alpha: 0.7)),
        const SizedBox(width: 6),
        Expanded(child: Text(text,
            style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.65)),
            overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shimmer skeleton loading
// ─────────────────────────────────────────────────────────────────────────────
class _ShimmerList extends StatelessWidget {
  final AnimationController ctrl;
  const _ShimmerList({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) {
        final shimmerGrad = LinearGradient(
          begin: const Alignment(-1.5, 0),
          end: const Alignment(1.5, 0),
          stops: [ctrl.value - 0.3, ctrl.value, ctrl.value + 0.3],
          colors: const [Color(0xFF0D1B2E), Color(0xFF1A2D45), Color(0xFF0D1B2E)],
        );
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          itemCount: 4,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, __) => _ShimmerCard(gradient: shimmerGrad),
        );
      },
    );
  }
}

class _ShimmerCard extends StatelessWidget {
  final LinearGradient gradient;
  const _ShimmerCard({required this.gradient});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 130,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final String filter;
  const _EmptyState({required this.filter});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 100, height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [_kBlue.withValues(alpha: 0.15), _kCyan.withValues(alpha: 0.05)]),
          ),
          child: const Icon(Icons.calendar_today_rounded, size: 48, color: _kCyan),
        ),
        const SizedBox(height: 20),
        Text(
          filter.isEmpty ? 'Aucune réservation' : 'Aucune réservation "$filter"',
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'Vos réservations apparaîtront ici.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Error state
// ─────────────────────────────────────────────────────────────────────────────
class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _kRed.withValues(alpha: 0.12),
          ),
          child: const Icon(Icons.error_outline_rounded, color: _kRed, size: 44),
        ),
        const SizedBox(height: 16),
        Text(message, style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: onRetry,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_kCyan, _kBlue]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('Réessayer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialog premium
// ─────────────────────────────────────────────────────────────────────────────
class _PremiumDialog extends StatelessWidget {
  final String title;
  final String body;
  final String confirmLabel;
  final Color confirmColor;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _PremiumDialog({
    required this.title, required this.body, required this.confirmLabel,
    required this.confirmColor, required this.onConfirm, required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _kCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Text(body, style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 14)),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: GestureDetector(
              onTap: onCancel,
              child: Container(
                height: 46,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
                child: const Center(child: Text('Non', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700))),
              ),
            )),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: GestureDetector(
              onTap: onConfirm,
              child: Container(
                height: 46,
                decoration: BoxDecoration(color: confirmColor, borderRadius: BorderRadius.circular(14)),
                child: Center(child: Text(confirmLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13), textAlign: TextAlign.center)),
              ),
            )),
          ]),
        ]),
      ),
    );
  }
}
