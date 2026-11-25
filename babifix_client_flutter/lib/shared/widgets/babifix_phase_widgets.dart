/// Widgets BABIFIX partagés — Phase B/C/E/F.
///
/// - DevisCardWidget       : rendu Kanban d'un devis (lecture).
/// - SystemEventWidget     : rendu d'un message Kind=SYSTEM.
/// - TimelineReservationWidget : timeline 8 étapes.
/// - MoneyBreakdownWidget  : sous-total → commission → net.
/// - EscrowStatusBadge     : badge "En escrow" / "Cash main à main" / "Libéré".
library babifix_phase_widgets;

import 'dart:convert';

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
      photosPrestataire: (payload['photos_prestataire'] as List? ?? const [])
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList(),
      lignes: lignes,
      estEstimation: payload['est_estimation'] == true,
      prixMin: (payload['prix_min'] as num?)?.toDouble() ?? 0,
      prixMax: (payload['prix_max'] as num?)?.toDouble() ?? 0,
    );
    return DevisCardWidget(devis: devis, compact: compact);
  }

  const DevisCardWidget({super.key, required this.devis, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final isDark = BabifixDesign.isDark(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: BabifixDesign.surfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? BabifixDesign.borderDark
              : BabifixDesign.cyanDeep.withValues(alpha: 0.18),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.24 : 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context),
          if (devis.diagnostic.isNotEmpty) _diagnostic(context),
          if (devis.photosPrestataire.isNotEmpty) _photos(),
          ..._sections(context),
          _totals(context),
        ],
      ),
    );
  }

  Widget _photos() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.photo_library_outlined,
                  size: 14, color: Colors.grey.shade600),
              const SizedBox(width: 5),
              Text('Photos du prestataire',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade700)),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 70,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: devis.photosPrestataire.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) => ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _devisPhoto(devis.photosPrestataire[i], 70),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _devisPhoto(String src, double size) {
    final ph = Container(
      width: size,
      height: size,
      color: Colors.grey.shade200,
      child: Icon(Icons.broken_image_outlined,
          color: Colors.grey.shade400, size: 24),
    );
    final s = src.trim();
    if (s.startsWith('data:image/')) {
      try {
        return Image.memory(base64Decode(s.split(',').last),
            width: size, height: size, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => ph);
      } catch (_) {
        return ph;
      }
    }
    if (s.startsWith('http')) {
      return Image.network(s,
          width: size, height: size, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => ph);
    }
    return ph;
  }

  Widget _header(BuildContext context) {
    final isDark = BabifixDesign.isDark(context);
    final couleur = switch (devis.statut) {
      DevisStatus.accepte => isDark ? const Color(0xFF4ADE80) : BabifixDesign.emeraldForest,
      DevisStatus.refuse => BabifixDesign.error,
      DevisStatus.envoye => isDark ? BabifixDesign.cyan : BabifixDesign.cyanDeep,
      _ => BabifixDesign.textMutedOf(context),
    };
    final estim = devis.estEstimation;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: (isDark ? BabifixDesign.cyan : BabifixDesign.cyanDeep)
            .withValues(alpha: 0.09),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: Row(
        children: [
          Icon(
            estim ? Icons.assignment_outlined : Icons.receipt_long,
            size: 20,
            color: BabifixDesign.iconColor(context),
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
                    color: BabifixDesign.textPrimaryOf(context),
                  ),
                ),
                if (estim)
                  Text(
                    'Chiffrage sur mesure apres diagnostic',
                    style: TextStyle(
                      fontSize: 12,
                      color: BabifixDesign.textMutedOf(context),
                    ),
                  )
                else if (devis.dateProposee != null &&
                    devis.dateProposee!.isNotEmpty)
                  Text(
                    'Proposé pour le ${devis.dateProposee}',
                    style: TextStyle(
                      fontSize: 12,
                      color: BabifixDesign.textMutedOf(context),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: couleur.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              estim ? 'En preparation' : devis.statut.label,
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

  Widget _diagnostic(BuildContext context) {
    final isDark = BabifixDesign.isDark(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: BabifixDesign.elevatedSurfaceOf(context),
          borderRadius: BorderRadius.circular(8),
          border: isDark ? Border.all(color: BabifixDesign.borderDark) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Diagnostic',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: BabifixDesign.textMutedOf(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              devis.diagnostic,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: BabifixDesign.textPrimaryOf(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _sections(BuildContext context) {
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
      out.add(_section(context, t, ls));
    }
    return out;
  }

  Widget _section(BuildContext context, DevisLineType t, List<LigneDevis> lignes) {
    final couleur = _typeColor(t, isDark: BabifixDesign.isDark(context));
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
                  color: BabifixDesign.textPrimaryOf(context),
                  fontFeatures: BabifixDesign.tabularFigures,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ...lignes.map((l) => _ligneRow(context, l)),
          const SizedBox(height: 4),
          Divider(height: 1, color: BabifixDesign.borderOf(context)),
        ],
      ),
    );
  }

  Widget _ligneRow(BuildContext context, LigneDevis l) {
    final qStr = l.quantite == l.quantite.roundToDouble()
        ? l.quantite.toStringAsFixed(0)
        : l.quantite.toStringAsFixed(2);
    final uniteText = l.unite.isEmpty ? '' : ' ${l.unite}';
    final ink = BabifixDesign.textPrimaryOf(context);
    final muted = BabifixDesign.textMutedOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.description, style: TextStyle(fontSize: 13, color: ink)),
                if (l.marque.isNotEmpty)
                  Text(l.marque, style: TextStyle(fontSize: 11, color: muted)),
                Text(
                  '$qStr$uniteText x ${fmtMoney(l.prixUnitaire)}',
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

  Widget _totals(BuildContext context) {
    final isDark = BabifixDesign.isDark(context);
    if (devis.estEstimation) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
        child: Row(
          children: [
            Icon(
              Icons.receipt_long_rounded,
              size: 16,
              color: isDark ? BabifixDesign.cyan : BabifixDesign.cyanDeep,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Devis detaille en attente du chiffrage par l\'artisan',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: BabifixDesign.textPrimaryOf(context),
                ),
              ),
            ),
          ],
        ),
      );
    }
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
        lightCard: !isDark,
      ),
    );
  }

  static Color _typeColor(DevisLineType t, {bool isDark = false}) => switch (t) {
        DevisLineType.fourniture => isDark ? const Color(0xFFC4B5FD) : Colors.deepPurple,
        DevisLineType.mainOeuvre => isDark ? BabifixDesign.cyan : BabifixDesign.cyanDeep,
        DevisLineType.deplacement => isDark ? const Color(0xFFFDBA74) : BabifixDesign.ciOrange,
        DevisLineType.autre => isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
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
  // Par défaut "Total à payer" : correct pour un résumé de devis (ce que le
  // client paiera AU TOTAL). Sur un écran de paiement en escrow Mobile Money,
  // seul un ACOMPTE (30 %) est dû immédiatement — afficher "Total à payer"
  // en gros et en gras juste à côté du montant réellement demandé induisait
  // en erreur (« on me dit 18 % » : le client lisait la commission comme le
  // montant dû, sans réaliser que "Total à payer" = devis complet, pas
  // l'acompte). Passer un libellé différent (ex. "Total du devis") dans ce cas.
  final String totalLabel;
  final bool lightCard;

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
    this.totalLabel = 'Total à payer',
    this.lightCard = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = BabifixDesign.isDark(context);
    final useLightStyle = lightCard && !isDark;
    final bgColor = useLightStyle ? const Color(0xFFF8FAFC) : BabifixDesign.navyElevated;
    final borderColor = useLightStyle
        ? const Color(0xFFCBD5E1)
        : BabifixDesign.cyan.withValues(alpha: 0.28);
    final titleColor = useLightStyle ? const Color(0xFF0F172A) : Colors.white;
    final dividerColor = useLightStyle
        ? const Color(0xFFE2E8F0)
        : Colors.white.withValues(alpha: 0.14);
    final totalColor = useLightStyle ? BabifixDesign.emeraldForest : BabifixDesign.cyan;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long_rounded,
                  size: 15, color: totalColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Détail financier sous séquestre',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: titleColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _row(context, 'Sous-total', fmtMoney(sousTotal), bold: false, useLightStyle: useLightStyle),
          if (remise > 0)
            _row(context, 'Remise', '- ${fmtMoney(remise)}',
                color: BabifixDesign.emeraldTint, useLightStyle: useLightStyle),
          if (!compact || showProviderNet) ...[
            _row(
              context,
              'Commission BABIFIX ($commissionRate%)',
              '- ${fmtMoney(commissionMontant)}',
              color: useLightStyle ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
              useLightStyle: useLightStyle,
            ),
          ],
          Divider(height: 18, color: dividerColor),
          _row(
            context,
            totalLabel,
            fmtMoney(totalTtc),
            bold: true,
            big: true,
            color: totalColor,
            useLightStyle: useLightStyle,
          ),
          if (showProviderNet) ...[
            const SizedBox(height: 6),
            _row(
              context,
              'Vous toucherez',
              fmtMoney(netPrestataire),
              bold: true,
              color: useLightStyle ? BabifixDesign.emeraldForest : const Color(0xFF4ADE80),
              useLightStyle: useLightStyle,
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value,
      {bool bold = false, bool big = false, Color? color, required bool useLightStyle}) {
    final defaultLabelCol = useLightStyle ? const Color(0xFF475569) : const Color(0xFFCBD5E1);
    final defaultValCol = useLightStyle ? const Color(0xFF0F172A) : Colors.white;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: TextStyle(
                    fontSize: big ? 14 : 12,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                    color: color ?? defaultLabelCol,
                  ))),
          Text(value,
              style: TextStyle(
                fontSize: big ? 16 : 13,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                color: color ?? defaultValCol,
                fontFeatures: BabifixDesign.tabularFigures,
              )),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SystemEventWidget — événements système dans le chat
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
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.18)),
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
                color: BabifixDesign.textPrimaryOf(context),
              ),
            ),
          ),
          if (createdAt != null) ...[
            const SizedBox(width: 6),
            Text('· ${f.format(createdAt!.toLocal())}',
                style: TextStyle(
                    fontSize: 10.5,
                    color: BabifixDesign.textMutedOf(context))),
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
          ? 'Acompte commission à verser'
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < steps.length; i++) _row(steps[i], i == steps.length - 1),
        ],
      ),
    );
  }

  Widget _row(ReservationStep s, bool last) {
    final color = s.active
        ? BabifixDesign.ciBlue
        : (s.reached ? BabifixDesign.ciGreen : Colors.grey.shade300);
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
                  color: Colors.white,
                ),
              ),
              if (!last)
                Expanded(
                  child: Container(width: 2, color: Colors.grey.shade200),
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
                          ? Colors.grey.shade900
                          : Colors.grey.shade500,
                    ),
                  ),
                  if (s.at != null && f != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        f.format(s.at!.toLocal()),
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500),
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
