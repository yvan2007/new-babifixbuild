import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../babifix_design_system.dart';
import '../../services/call_service.dart';
import '../../shared/widgets/payment_method_logo.dart';
import '../call/call_history_screen.dart';
import 'client_journal_viewer.dart';
import 'execution_actions_widget.dart';
import '../../shared/widgets/babifix_ring_loader.dart';

class RequestDetailScreen extends StatelessWidget {
  const RequestDetailScreen({
    super.key,
    required this.reference,
    required this.client,
    required this.service,
    required this.date,
    required this.hour,
    required this.amount,
    required this.address,
    required this.description,
    required this.apiStatus,
    required this.paymentType,
    required this.mobileMoneyOperator,
    required this.rating,
    required this.clientMessage,
    required this.clientPhotos,
    required this.disponibilitesClient,
    required this.isUrgent,
    required this.prixPropose,
  });

  final String reference;
  final String client;
  final String service;
  final String date;
  final String hour;
  final String amount;
  final String address;
  final String description;
  final String apiStatus;
  final String paymentType;
  final String mobileMoneyOperator;
  final double rating;
  final String clientMessage;
  final List<String> clientPhotos;
  final String disponibilitesClient;
  final bool isUrgent;
  final double? prixPropose;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BabifixDesign.navy,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            backgroundColor: BabifixDesign.navy,
            elevation: 0,
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back, color: Colors.white),
            ),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
              title: Text(
                reference,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0A1628), Color(0xFF152238)],
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Status badge
                _StatusBadge(status: apiStatus),
                const SizedBox(height: 20),

                // Client info
                _SectionCard(
                  icon: Icons.person_rounded,
                  title: 'Client',
                  gradient: const LinearGradient(
                    colors: [Color(0xFF38BDF8), Color(0xFF0EA5E9)],
                  ),
                  children: [
                    _InfoRow(label: 'Nom', value: client),
                    const SizedBox(height: 8),
                    _InfoRow(
                      label: 'Note',
                      value: '⭐ ${rating.toStringAsFixed(1)}',
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Service info
                _SectionCard(
                  icon: Icons.build_rounded,
                  title: 'Service',
                  gradient: const LinearGradient(
                    colors: [Color(0xFFA78BFA), Color(0xFF8B5CF6)],
                  ),
                  children: [
                    _InfoRow(label: 'Type', value: service),
                    const SizedBox(height: 8),
                    if (date.isNotEmpty || hour.isNotEmpty)
                      _InfoRow(
                        label: 'Date / Heure',
                        value: '${date.isNotEmpty ? date : ''} ${hour.isNotEmpty ? 'à $hour' : ''}'.trim(),
                      ),
                    const SizedBox(height: 8),
                    _InfoRow(label: 'Adresse', value: address),
                  ],
                ),
                const SizedBox(height: 16),

                // Urgency & requirements
                if (isUrgent || disponibilitesClient.isNotEmpty || prixPropose != null) ...[
                  _SectionCard(
                    icon: isUrgent ? Icons.flash_on_rounded : Icons.tune_rounded,
                    title: 'Exigences du client',
                    gradient: LinearGradient(
                      colors: isUrgent
                          ? const [Color(0xFFF87171), Color(0xFFEF4444)]
                          : const [Color(0xFF818CF8), Color(0xFF6366F1)],
                    ),
                    children: [
                      if (isUrgent) ...[
                        _UrgencyBadge(),
                        const SizedBox(height: 12),
                      ],
                      if (disponibilitesClient.isNotEmpty) ...[
                        _InfoRow(
                          label: 'Disponibilités',
                          value: disponibilitesClient,
                          icon: Icons.schedule_rounded,
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (prixPropose != null && prixPropose! > 0)
                        _InfoRow(
                          label: 'Budget proposé',
                          value: '${prixPropose!.toStringAsFixed(0)} FCFA',
                          icon: Icons.monetization_on_rounded,
                          valueColor: const Color(0xFFF59E0B),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // Client message / description
                if (clientMessage.isNotEmpty) ...[
                  _SectionCard(
                    icon: Icons.chat_bubble_rounded,
                    title: 'Message du client',
                    gradient: const LinearGradient(
                      colors: [Color(0xFF60A5FA), Color(0xFF4CC9F0)],
                    ),
                    children: [
                      Text(
                        clientMessage,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFFCBD5E1),
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // Photos
                if (clientPhotos.isNotEmpty) ...[
                  _SectionCard(
                    icon: Icons.photo_library_rounded,
                    title: 'Photos du client',
                    subtitle: '${clientPhotos.length} photo(s)',
                    gradient: const LinearGradient(
                      colors: [Color(0xFF22C55E), Color(0xFF22C55E)],
                    ),
                    children: [
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: clientPhotos.length,
                        itemBuilder: (ctx, i) => ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: GestureDetector(
                            onTap: () => _showPhotoFullscreen(context, clientPhotos[i]),
                            child: _SafeImage(src: clientPhotos[i], size: 100),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // Payment info
                if (paymentType.isNotEmpty) ...[
                  _SectionCard(
                    icon: Icons.payment_rounded,
                    title: 'Paiement',
                    gradient: const LinearGradient(
                      colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                    ),
                    children: [
                      Row(
                        children: [
                          if (paymentType == 'MOBILE_MONEY' && mobileMoneyOperator.isNotEmpty) ...[
                            BabifixPaymentMethodLogo(
                              methodId: mobileMoneyOperator,
                              height: 28,
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: _InfoRow(
                              label: 'Mode',
                              value: _paymentLabel(paymentType, mobileMoneyOperator),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // Amount
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF152A45), Color(0xFF1A3355)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Montant estimé',
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                      Text(
                        amount.isEmpty ? 'À définir' : amount,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF38BDF8),
                        ),
                      ),
                    ],
                  ),
                ),
                // Actions cycle exécution (démarrer/photos/terminer + escrow status)
                const SizedBox(height: 14),
                ExecutionActionsWidget(
                  reservationReference: reference,
                  statut: apiStatus,
                ),
                // Bouton "Voir le journal client" — utile dès que la
                // prestation est terminée pour comparer ce que le presta a
                // déclaré et ce que le client en dit.
                if (apiStatus == 'Terminee' ||
                    apiStatus == 'Confirmee' ||
                    apiStatus.toLowerCase().contains('confirm')) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => ClientJournalViewer(
                            reservationReference: reference,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.menu_book_outlined),
                      label: const Text('Voir le journal du client'),
                    ),
                  ),
                ],
                // Appel direct au client + raccourci historique
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => CallService.startOutgoing(
                          context: context,
                          reservationReference: reference,
                          targetName: client,
                          isVideo: false,
                        ),
                        icon: const Icon(Icons.call, size: 18),
                        label: const Text('Appeler le client'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => const CallHistoryScreen(),
                          ),
                        ),
                        icon: const Icon(Icons.history, size: 18),
                        label: const Text('Mes appels'),
                      ),
                    ),
                  ],
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  void _showPhotoFullscreen(BuildContext context, String src) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            InteractiveViewer(
              child: _SafeImage(src: src, size: 400),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _paymentLabel(String code, [String mobileOp = '']) {
    switch (code) {
      case 'ESPECES':
        return 'Espèces';
      case 'MOBILE_MONEY':
        final op = _mobileMoneyOpLabel(mobileOp);
        return op.isEmpty ? 'Mobile Money' : 'Mobile Money ($op)';
      case 'CARTE':
        return 'Carte';
      default:
        return code;
    }
  }

  String _mobileMoneyOpLabel(String op) {
    switch (op) {
      case 'ORANGE_MONEY':
        return 'Orange Money';
      case 'MTN_MOMO':
        return 'MTN MoMo';
      case 'WAVE':
        return 'Wave';
      case 'MOOV':
        return 'Moov';
      default:
        return '';
    }
  }
}

// ── Status Badge ──────────────────────────────────────────────────────────────
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  Color _color() {
    final s = status.toLowerCase();
    if (s.contains('attente') || s.contains('demande')) return const Color(0xFFF59E0B);
    if (s.contains('devis')) return const Color(0xFF60A5FA);
    if (s.contains('cours')) return const Color(0xFFA78BFA);
    if (s.contains('termin')) return const Color(0xFF22C55E);
    if (s.contains('annul')) return const Color(0xFFF87171);
    if (s.contains('confirm')) return const Color(0xFF22C55E);
    return const Color(0xFF94A3B8);
  }

  String _label() {
    final s = status;
    if (s == 'DEMANDE_ENVOYEE') return 'Nouvelle demande';
    if (s == 'DEVIS_EN_COURS') return 'Devis à préparer';
    if (s == 'DEVIS_ENVOYE') return 'Devis envoyé';
    if (s == 'DEVIS_ACCEPTE') return 'Devis accepté';
    if (s == 'INTERVENTION_EN_COURS') return 'Intervention en cours';
    if (s == 'En attente') return 'En attente';
    if (s == 'Confirmee') return 'Confirmée';
    if (s == 'En cours') return 'En cours';
    if (s == 'Terminee') return 'Terminée';
    if (s == 'Annulee') return 'Annulée';
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final c = _color();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            c.withValues(alpha: 0.15),
            c.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 8)],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _label(),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: c,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section Card ──────────────────────────────────────────────────────────────
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.gradient,
    required this.children,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Gradient gradient;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF152A45), Color(0xFF1A3355)],
        ),
        borderRadius: BorderRadius.circular(16),
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
                  gradient: gradient,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(color: Color(0x1AFFFFFF), height: 24),
          ...children,
        ],
      ),
    );
  }
}

// ── Info Row ──────────────────────────────────────────────────────────────────
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.icon,
    this.valueColor,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: const Color(0xFF64748B)),
          const SizedBox(width: 8),
        ],
        Text(
          '$label : ',
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF94A3B8),
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: valueColor ?? const Color(0xFFE2E8F0),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Urgency Badge ─────────────────────────────────────────────────────────────
class _UrgencyBadge extends StatelessWidget {
  const _UrgencyBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0x20EF4444), Color(0x10EF4444)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.flash_on_rounded, size: 18, color: Color(0xFFEF4444)),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'URGENT',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFEF4444),
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  'Intervention rapide demandée',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Safe Image ────────────────────────────────────────────────────────────────
class _SafeImage extends StatelessWidget {
  const _SafeImage({required this.src, this.size = 100});
  final String src;
  final double size;

  static Widget _placeholder(double sz) => Container(
    width: sz,
    height: sz,
    decoration: BoxDecoration(
      color: const Color(0xFF152A45),
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Icon(Icons.photo_outlined, color: Color(0xFF64748B), size: 24),
  );

  @override
  Widget build(BuildContext context) {
    if (src.isEmpty) return _placeholder(size);

    if (src.startsWith('data:image/')) {
      try {
        final bytes = base64Decode(src.split(',').last);
        return Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(size),
        );
      } catch (_) {
        return _placeholder(size);
      }
    }

    if (src.startsWith('http://') || src.startsWith('https://')) {
      return Image.network(
        src,
        width: size,
        height: size,
        fit: BoxFit.cover,
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: const Color(0xFF152A45),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: BabifixRingLoader.cyan(size: 28),
                ),
              ),
        errorBuilder: (_, __, ___) => _placeholder(size),
      );
    }

    try {
      final file = File(src);
      if (file.existsSync()) {
        return Image.file(
          file,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(size),
        );
      }
    } catch (_) {}

    return _placeholder(size);
  }
}
