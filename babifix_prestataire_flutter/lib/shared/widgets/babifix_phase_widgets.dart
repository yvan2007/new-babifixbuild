/// Widgets BABIFIX partagés — Phase B/C/E/F.
///
/// - DevisCardWidget       : rendu Kanban d'un devis (lecture).
/// - SystemEventWidget     : rendu d'un message Kind=SYSTEM.
/// - TimelineReservationWidget : timeline 8 étapes.
/// - MoneyBreakdownWidget  : sous-total → commission → net.
/// - EscrowStatusBadge     : badge "En escrow" / "Cash main à main" / "Libéré".
library babifix_phase_widgets;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../babifix_design_system.dart';
import '../../models/babifix_models.dart';

// ---------------------------------------------------------------------------
// Format monétaire FCFA
// ---------------------------------------------------------------------------
String fmtMoney(num v) {
  final f = NumberFormat.decimalPattern('fr_FR');
  return '${f.format(v.round())} F CFA';
}

// ---------------------------------------------------------------------------
// DevisCardWidget — rendu Kanban pro
// ---------------------------------------------------------------------------
class DevisCardWidget extends StatelessWidget {
  final Devis devis;
  final bool compact;

  /// Construit depuis un payload_json (Message.kind == DEVIS_CARD).
  factory DevisCardWidget.fromPayload(Map<String, dynamic> payload,
      {bool compact = true}) {
    final lignes = (payload['lignes'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => LigneDevis.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    final devis = Devis(
      id: payload['devis_id'] as int?,
      reference: (payload['devis_reference'] ?? '').toString(),
      diagnostic: (payload['diagnostic'] ?? '').toString(),
      dateProposee: payload['date_proposee']?.toString(),
      heureDebut: payload['heure_debut']?.toString(),
      heureFin: payload['heure_fin']?.toString(),
      sousTotal: (payload['sous_total'] as num?)?.toDouble() ?? 0,
      commissionRate: (payload['commission_rate'] as num?)?.toInt() ?? 18,
      commissionMontant: (payload['commission_montant'] as num?)?.toDouble() ?? 0,
      totalTtc: (payload['total_ttc'] as num?)?.toDouble() ?? 0,
      netPrestataire: (payload['net_prestataire'] as num?)?.toDouble() ?? 0,
      notePrestataire: (payload['note_prestataire'] ?? '').toString(),
      validiteJours: (payload['validite_jours'] as num?)?.toInt() ?? 7,
      statut: DevisStatus.fromCode((payload['statut'] ?? 'BROUILLON').toString()),
      lignes: lignes,
    );
    return DevisCardWidget(devis: devis, compact: compact);
  }

  const DevisCardWidget({super.key, required this.devis, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final isDark = BabifixDesign.isDark(context);
    final surface = BabifixDesign.surfaceOf(context);
    final elevated = BabifixDesign.elevatedSurfaceOf(context);
    final border = BabifixDesign.borderOf(context);
    final ink = BabifixDesign.textPrimaryOf(context);
    final muted = BabifixDesign.textMutedOf(context);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? border
              : BabifixDesign.ciBlue.withValues(alpha: 0.16),
        ),
        boxShadow: isDark
            ? const <BoxShadow>[]
            : [
                BoxShadow(
                  color: BabifixDesign.navy.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(isDark: isDark, ink: ink, muted: muted),
          if (devis.diagnostic.isNotEmpty)
            _diagnostic(
              elevated: elevated,
              border: border,
              ink: ink,
              muted: muted,
            ),
          ..._sections(isDark: isDark, ink: ink, muted: muted, border: border),
          _totals(),
          _footer(ink: ink, muted: muted),
        ],
      ),
    );
  }

  Widget _footer({required Color ink, required Color muted}) {
    final hasNote = devis.notePrestataire.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasNote) ...[
            Row(
              children: [
                Icon(Icons.sticky_note_2_outlined, size: 14, color: muted),
                const SizedBox(width: 5),
                Text(
                  'Note du prestataire',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: muted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              devis.notePrestataire,
              style: TextStyle(fontSize: 12.5, height: 1.35, color: ink),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Icon(Icons.schedule, size: 13, color: muted),
              const SizedBox(width: 5),
              Text(
                'Devis valable ${devis.validiteJours} jours',
                style: TextStyle(fontSize: 11.5, color: muted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _header({
    required bool isDark,
    required Color ink,
    required Color muted,
  }) {
    final couleur = switch (devis.statut) {
      DevisStatus.accepte =>
        isDark ? const Color(0xFF4ADE80) : BabifixDesign.emeraldForest,
      DevisStatus.refuse =>
        isDark ? const Color(0xFFFCA5A5) : BabifixDesign.error,
      DevisStatus.envoye => isDark ? BabifixDesign.cyan : BabifixDesign.ciBlue,
      _ => muted,
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: isDark
            ? BabifixDesign.navyElevated
            : BabifixDesign.ciBlue.withValues(alpha: 0.06),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.receipt_long,
            size: 20,
            color: isDark ? BabifixDesign.cyan : BabifixDesign.iconOnLight,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Devis ${devis.reference}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
                if (devis.dateProposee != null && devis.dateProposee!.isNotEmpty)
                  Text(
                    'Proposé pour le ${devis.dateProposee}',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: couleur.withValues(alpha: isDark ? 0.18 : 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              devis.statut.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: couleur,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _diagnostic({
    required Color elevated,
    required Color border,
    required Color ink,
    required Color muted,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: elevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Diagnostic',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: muted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              devis.diagnostic,
              style: TextStyle(fontSize: 13, height: 1.35, color: ink),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _sections({
    required bool isDark,
    required Color ink,
    required Color muted,
    required Color border,
  }) {
    final types = [
      DevisLineType.fourniture,
      DevisLineType.mainOeuvre,
      DevisLineType.deplacement,
      DevisLineType.autre,
    ];
    final out = <Widget>[];
    for (final t in types) {
      final ls = devis.lignesByType(t);
      if (ls.isEmpty) continue;
      out.add(
        _section(t, ls, isDark: isDark, ink: ink, muted: muted, border: border),
      );
    }
    return out;
  }

  Widget _section(
    DevisLineType t,
    List<LigneDevis> lignes, {
    required bool isDark,
    required Color ink,
    required Color muted,
    required Color border,
  }) {
    final couleur = _typeColor(t, isDark: isDark, muted: muted);
    final icon = _typeIcon(t);
    final st = devis.sousTotalByType(t);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: couleur),
              const SizedBox(width: 6),
              Text(
                t.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: couleur,
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              Text(
                fmtMoney(st),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: ink,
                  fontFeatures: BabifixDesign.tabularFigures,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ...lignes.map((l) => _ligneRow(l, ink: ink, muted: muted)),
          const SizedBox(height: 4),
          Divider(height: 1, color: border),
        ],
      ),
    );
  }

  Widget _ligneRow(
    LigneDevis l, {
    required Color ink,
    required Color muted,
  }) {
    final qStr = l.quantite == l.quantite.roundToDouble()
        ? l.quantite.toStringAsFixed(0)
        : l.quantite.toStringAsFixed(2);
    final uniteText = l.unite.isEmpty ? '' : ' ${l.unite}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.description,
                  style: TextStyle(fontSize: 13, color: ink),
                ),
                if (l.marque.isNotEmpty)
                  Text(
                    l.marque,
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                Text(
                  '$qStr$uniteText × ${fmtMoney(l.prixUnitaire)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: muted,
                    fontFeatures: BabifixDesign.tabularFigures,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            fmtMoney(l.total),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: ink,
              fontFeatures: BabifixDesign.tabularFigures,
            ),
          ),
        ],
      ),
    );
  }

  Widget _totals() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      child: MoneyBreakdownWidget(
        sousTotal: devis.sousTotal,
        remise: devis.remise,
        commissionRate: devis.commissionRate,
        commissionMontant: devis.commissionMontant,
        totalTtc: devis.totalTtc,
        netPrestataire: devis.netPrestataire,
        compact: compact,
      ),
    );
  }

  static Color _typeColor(
    DevisLineType t, {
    required bool isDark,
    required Color muted,
  }) =>
      switch (t) {
        DevisLineType.fourniture =>
          isDark ? const Color(0xFFC084FC) : Colors.deepPurple,
        DevisLineType.mainOeuvre =>
          isDark ? BabifixDesign.cyan : BabifixDesign.ciBlue,
        DevisLineType.deplacement =>
          isDark ? BabifixDesign.ciOrangeBright : BabifixDesign.ciOrange,
        DevisLineType.autre => muted,
      };

  static IconData _typeIcon(DevisLineType t) => switch (t) {
        DevisLineType.fourniture => Icons.build_circle_outlined,
        DevisLineType.mainOeuvre => Icons.handyman_outlined,
        DevisLineType.deplacement => Icons.directions_car_outlined,
        DevisLineType.autre => Icons.more_horiz,
      };
}

// ---------------------------------------------------------------------------
// MoneyBreakdownWidget
// ---------------------------------------------------------------------------
class MoneyBreakdownWidget extends StatelessWidget {
  final double sousTotal;
  final double remise;
  final int commissionRate;
  final double commissionMontant;
  final double totalTtc;
  final double netPrestataire;
  final bool compact;
  final bool showProviderNet;

  const MoneyBreakdownWidget({
    super.key,
    required this.sousTotal,
    this.remise = 0,
    required this.commissionRate,
    required this.commissionMontant,
    required this.totalTtc,
    required this.netPrestataire,
    this.compact = false,
    this.showProviderNet = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = BabifixDesign.isDark(context);
    final ink = BabifixDesign.textPrimaryOf(context);
    final muted = BabifixDesign.textMutedOf(context);
    final accent = isDark ? BabifixDesign.cyan : BabifixDesign.emeraldForest;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? BabifixDesign.navyElevated : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? BabifixDesign.borderDark : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row(context, 'Sous-total', fmtMoney(sousTotal), bold: false, ink: ink, muted: muted),
          if (remise > 0)
            _row(context, 'Remise', '- ${fmtMoney(remise)}',
                color: isDark ? const Color(0xFF4ADE80) : BabifixDesign.emeraldTint, ink: ink, muted: muted),
          if (!compact || showProviderNet) ...[
            _row(
              context,
              'Commission BABIFIX ($commissionRate%)',
              '- ${fmtMoney(commissionMontant)}',
              color: muted,
              ink: ink,
              muted: muted,
            ),
          ],
          Divider(height: 14, color: BabifixDesign.borderOf(context)),
          _row(
            context,
            'Total à payer',
            fmtMoney(totalTtc),
            bold: true,
            big: true,
            color: accent,
            ink: ink,
            muted: muted,
          ),
          if (showProviderNet) ...[
            const SizedBox(height: 6),
            _row(
              context,
              'Vous toucherez',
              fmtMoney(netPrestataire),
              bold: true,
              color: isDark ? const Color(0xFF4ADE80) : BabifixDesign.emeraldForest,
              ink: ink,
              muted: muted,
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value,
      {bool bold = false, bool big = false, Color? color, required Color ink, required Color muted}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: TextStyle(
                    fontSize: big ? 14 : 12,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                    color: color ?? muted,
                  ))),
          Text(value,
              style: TextStyle(
                fontSize: big ? 16 : 13,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                color: color ?? ink,
                fontFeatures: BabifixDesign.tabularFigures,
              )),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SystemEventWidget : événements système dans le chat
// ---------------------------------------------------------------------------
class SystemEventWidget extends StatelessWidget {
  final String body;
  final String? eventType;
  final DateTime? createdAt;

  const SystemEventWidget(
      {super.key, required this.body, this.eventType, this.createdAt});

  factory SystemEventWidget.fromMessage(ChatMessage m) {
    final t = (m.payloadJson?['event_type'] ?? '').toString();
    return SystemEventWidget(
      body: m.body,
      eventType: t,
      createdAt: m.createdAt,
    );
  }

  @override
  Widget build(BuildContext context) {
    final icon = _icon(eventType ?? '');
    final color = _color(eventType ?? '');
    final f = DateFormat('HH:mm');
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              body.replaceAll(' \u2014 ', ' · ').replaceAll(' \u2013 ', ' · '),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: BabifixDesign.textPrimaryOf(context)),
            ),
          ),
          if (createdAt != null) ...[
            const SizedBox(width: 6),
            Text('· ${f.format(createdAt!.toLocal())}',
                style: TextStyle(
                    fontSize: 10.5, color: BabifixDesign.textMutedOf(context))),
          ],
        ],
      ),
    );
  }

  IconData _icon(String t) {
    if (t.contains('start')) return Icons.play_circle_fill;
    if (t.contains('finish')) return Icons.check_circle_outline;
    if (t.contains('payment') || t.contains('escrow')) {
      return Icons.account_balance_wallet;
    }
    if (t.contains('confirm')) return Icons.verified;
    if (t.contains('release') || t.contains('funds')) {
      return Icons.payments_outlined;
    }
    if (t.contains('call')) return Icons.phone;
    return Icons.info_outline;
  }

  Color _color(String t) {
    if (t.contains('finish') || t.contains('confirm') || t.contains('release')) {
      return BabifixDesign.ciGreen;
    }
    if (t.contains('payment')) return BabifixDesign.ciBlue;
    if (t.contains('reject') || t.contains('cancel')) {
      return BabifixDesign.error;
    }
    return Colors.grey.shade600;
  }
}

// ---------------------------------------------------------------------------
// EscrowStatusBadge
// ---------------------------------------------------------------------------
class EscrowStatusBadge extends StatelessWidget {
  final EscrowStrategy strategy;
  final bool acompteValide;
  final bool fundsReleased;

  const EscrowStatusBadge({
    super.key,
    required this.strategy,
    required this.acompteValide,
    required this.fundsReleased,
  });

  factory EscrowStatusBadge.fromQuote(EscrowQuote q) {
    return EscrowStatusBadge(
      strategy: q.strategy,
      acompteValide: q.acompteValide,
      fundsReleased: q.fundsReleasedAt != null,
    );
  }

  @override
  Widget build(BuildContext context) {
    late String label;
    late Color color;
    late IconData icon;

    if (fundsReleased) {
      label = 'Fonds libérés';
      color = BabifixDesign.ciGreen;
      icon = Icons.task_alt;
    } else if (!acompteValide) {
      label = strategy == EscrowStrategy.cashCommissionOnly
          ? 'Commission à régler pour démarrer'
          : 'Paiement initial requis';
      color = Colors.orange.shade700;
      icon = Icons.hourglass_top;
    } else if (strategy == EscrowStrategy.cashCommissionOnly) {
      label = 'Commission encaissée · solde cash à régler';
      color = BabifixDesign.ciBlue;
      icon = Icons.handshake;
    } else {
      label = 'Fonds bloqués en escrow';
      color = BabifixDesign.ciBlue;
      icon = Icons.lock_outline;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: color),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// TimelineReservationWidget
// ---------------------------------------------------------------------------
class TimelineReservationWidget extends StatelessWidget {
  final List<ReservationStep> steps;
  const TimelineReservationWidget({super.key, required this.steps});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BabifixDesign.surfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BabifixDesign.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < steps.length; i++)
            _row(context, steps[i], i == steps.length - 1),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, ReservationStep s, bool last) {
    final isDark = BabifixDesign.isDark(context);
    final color = s.active
        ? (isDark ? BabifixDesign.cyan : BabifixDesign.cyanDeep)
        : (s.reached ? BabifixDesign.success : BabifixDesign.borderOf(context));
    final f = s.at != null ? DateFormat('dd/MM HH:mm') : null;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  s.reached ? Icons.check : Icons.circle,
                  size: 12,
                  color: (s.active && isDark) ? BabifixDesign.navy : Colors.white,
                ),
              ),
              if (!last)
                Expanded(
                  child: Container(width: 2, color: BabifixDesign.borderOf(context)),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: s.active
                          ? FontWeight.w800
                          : (s.reached ? FontWeight.w600 : FontWeight.w400),
                      color: s.reached
                          ? BabifixDesign.textPrimaryOf(context)
                          : BabifixDesign.textMutedOf(context),
                    ),
                  ),
                  if (s.at != null && f != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        f.format(s.at!.toLocal()),
                        style: TextStyle(
                            fontSize: 11, color: BabifixDesign.textMutedOf(context)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
