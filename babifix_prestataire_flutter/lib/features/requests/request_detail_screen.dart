import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../babifix_design_system.dart';
import '../../services/call_service.dart';
import '../../services/babifix_api.dart';
import '../../shared/widgets/babifix_snackbar.dart';
import '../../shared/widgets/payment_method_logo.dart';
import '../../shared/widgets/babifix_mini_map.dart';
import '../../shared/widgets/babifix_voice_note.dart';
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
    this.addressStreet = '',
    this.addressQuartier = '',
    this.addressVille = '',
    this.addressPays = '',
    this.addressRepere = '',
    this.addressLat,
    this.addressLon,
    this.addressIsApproximate = true,
    this.distanceKm,
    this.reponsesExigences = const {},
    this.cautionPayee = false,
    this.visiteEffectuee = false,
    this.scheduledDate = '',
    this.audioProbleme = '',
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

  // Adresse structurée — affichée joliment avec une icône par champ.
  final String addressStreet;
  final String addressQuartier;
  final String addressVille;
  final String addressPays;
  final String addressRepere;
  final double? addressLat;
  final double? addressLon;
  final bool addressIsApproximate;

  /// Distance estimée (km) entre le prestataire et le lieu de la demande.
  final double? distanceKm;

  /// Réponses du client aux questions dynamiques de la catégorie (Phase 2).
  /// Format {key: {label, value, unit?}}.
  final Map<String, dynamic> reponsesExigences;

  /// Caution de visite (Phase 3).
  final bool cautionPayee;
  final bool visiteEffectuee;

  /// Date prévue (ISO yyyy-mm-dd) choisie par le client — pour bloquer le
  /// bouton « Démarrer » avant le jour J.
  final String scheduledDate;

  /// Note vocale du client décrivant le besoin (URL). Vide si absente.
  final String audioProbleme;

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
                color: const Color(0xFF0B1B34),
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
                    colors: [Color(0xFF7C3AED), Color(0xFF7C3AED)],
                  ),
                  children: [
                    _InfoRow(label: 'Type', value: service),
                    const SizedBox(height: 8),
                    if (date.isNotEmpty || hour.isNotEmpty)
                      _InfoRow(
                        label: 'Date / Heure',
                        value: '${date.isNotEmpty ? date : ''} ${hour.isNotEmpty ? 'à $hour' : ''}'.trim(),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Adresse d'intervention (affichage structuré pro) ──────
                _AddressCard(
                  street: addressStreet,
                  quartier: addressQuartier,
                  ville: addressVille,
                  pays: addressPays,
                  repere: addressRepere,
                  fallbackLabel: address,
                  lat: addressLat,
                  lon: addressLon,
                  isApproximate: addressIsApproximate,
                  distanceKm: distanceKm,
                ),
                _RequirementsAnswersCard(reponses: reponsesExigences),
                // Carte moderne : emplacement du client (pin goutte).
                if (addressLat != null && addressLon != null) ...[
                  const SizedBox(height: 12),
                  BabifixMiniMap(
                    lat: addressLat!,
                    lon: addressLon!,
                    height: 170,
                    pinColor: const Color(0xFF4CC9F0),
                    pinIcon: Icons.person_pin_circle_rounded,
                  ),
                ],
                const SizedBox(height: 16),

                // Urgency & requirements
                if (isUrgent ||
                    disponibilitesClient.isNotEmpty ||
                    scheduledDate.isNotEmpty ||
                    prixPropose != null) ...[
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
                      // Créneau/date choisi par le client (planning). Affiché même
                      // si le texte libre « disponibilités » est vide, sinon le
                      // planning du client n'apparaissait nulle part côté presta.
                      if (scheduledDate.isNotEmpty) ...[
                        _InfoRow(
                          label: 'Date souhaitée',
                          value: scheduledDate.length >= 10
                              ? scheduledDate.substring(0, 10)
                              : scheduledDate,
                          icon: Icons.event_available_rounded,
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

                // Client message / description + note vocale
                if (clientMessage.isNotEmpty || audioProbleme.isNotEmpty) ...[
                  _SectionCard(
                    icon: Icons.chat_bubble_rounded,
                    title: 'Message du client',
                    gradient: const LinearGradient(
                      colors: [Color(0xFF60A5FA), Color(0xFF4CC9F0)],
                    ),
                    children: [
                      if (clientMessage.isNotEmpty)
                        Text(
                          clientMessage,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFFCBD5E1),
                            height: 1.6,
                          ),
                        ),
                      // Note vocale enregistrée par le client (façon WhatsApp).
                      if (audioProbleme.isNotEmpty) ...[
                        if (clientMessage.isNotEmpty) const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.mic_rounded,
                                size: 16, color: Color(0xFF38BDF8)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: BabifixVoiceNotePlayer(
                                url: MediaApi.absolute(audioProbleme),
                                durationSeconds: 0,
                                isMe: false,
                              ),
                            ),
                          ],
                        ),
                      ],
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

                // Amount — masqué tant qu'aucun montant réel (évite « 0 FCFA »)
                if (amount.trim().isNotEmpty &&
                    !RegExp(r'^0+(\s|$)').hasMatch(amount.trim()))
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF122236),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0x1A38BDF8)),
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
                          amount,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF38BDF8),
                          ),
                        ),
                      ],
                    ),
                  ),
                // Caution réglée : le presta confirme la visite (détermine qui
                // garde la caution en cas d'annulation).
                if (cautionPayee && !visiteEffectuee) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _markVisitDone(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF06B6D4),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      icon: const Icon(Icons.fact_check_rounded, size: 20),
                      label: const Text('Visite effectuée',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                ] else if (visiteEffectuee) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.check_circle_rounded,
                            color: Color(0xFF16A34A), size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Visite effectuée, la caution vous est acquise.',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF166534),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                // Actions cycle exécution (démarrer/photos/terminer + escrow status)
                const SizedBox(height: 14),
                ExecutionActionsWidget(
                  reservationReference: reference,
                  statut: apiStatus,
                  scheduledDate: scheduledDate,
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
                // Visio-diagnostic + demande d'estimation/visite : uniquement
                // AVANT tout engagement de visite. Dès que la caution est réglée
                // OU la visite effectuée, ces boutons de DEMANDE disparaissent
                // (inutile de re-demander une visite déjà en cours/faite).
                if (addressIsApproximate && !cautionPayee && !visiteEffectuee) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => CallService.startOutgoing(
                        context: context,
                        reservationReference: reference,
                        targetName: client,
                        isVideo: true,
                        diagnostic: true,
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF06B6D4),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      icon: const Icon(Icons.videocam_rounded, size: 20),
                      label: const Text(
                        'Visio-diagnostic (avant devis)',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 6, left: 4, right: 4),
                    child: Text(
                      'Évaluez le chantier en vidéo avant de proposer un devis. '
                      'Le client reçoit un appel et peut décliner.',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _showEstimationDialog(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white38),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                          ),
                          icon: const Icon(Icons.query_stats_rounded, size: 18),
                          label: const Text('Estimation',
                              style: TextStyle(fontSize: 12.5)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _showVisitDialog(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white38),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                          ),
                          icon: const Icon(Icons.home_repair_service_rounded,
                              size: 18),
                          label: const Text('Visite',
                              style: TextStyle(fontSize: 12.5)),
                        ),
                      ),
                    ],
                  ),
                ],
                // Visite proposée mais caution pas encore payée → le presta peut
                // se rétracter (annuler la demande) ; la résa repart en cours.
                if (apiStatus == 'VISITE_DIAGNOSTIC' && !cautionPayee) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _cancelVisit(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFEF4444),
                        side: const BorderSide(color: Color(0x55EF4444)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                      icon: const Icon(Icons.cancel_outlined, size: 18),
                      label: const Text('Annuler la demande de visite'),
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
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white38),
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
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white38),
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

  // ── Estimation (fourchette indicative) ──────────────────────────────────
  Future<void> _showEstimationDialog(BuildContext context) async {
    final diagCtrl = TextEditingController();
    final minCtrl = TextEditingController();
    final maxCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Envoyer une estimation'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Fourchette indicative (non payable). Vous enverrez ensuite '
                  'un devis ferme.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: diagCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Diagnostic',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: minCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Min',
                        suffixText: 'FCFA',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: maxCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Max',
                        suffixText: 'FCFA',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Envoyer')),
        ],
      ),
    );
    if (ok != true) return;
    final diag = diagCtrl.text.trim();
    final min = double.tryParse(minCtrl.text.replaceAll(',', '.').trim()) ?? 0;
    final max = double.tryParse(maxCtrl.text.replaceAll(',', '.').trim()) ?? 0;
    if (!context.mounted) return;
    if (diag.isEmpty || min <= 0 || max <= 0) {
      showBabifixToast(context,
          type: BabifixToastType.info,
          message: 'Renseignez le diagnostic et la fourchette.');
      return;
    }
    try {
      await DevisApi.createEstimation(
        reference: reference,
        diagnostic: diag,
        prixMin: min,
        prixMax: max,
      );
      if (!context.mounted) return;
      showBabifixToast(context,
          type: BabifixToastType.success,
          message: 'Estimation envoyée au client.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!context.mounted) return;
      showBabifixToast(context,
          type: BabifixToastType.error, message: 'Échec : $e');
    }
  }

  // ── Demande de visite de diagnostic (caution) ───────────────────────────
  Future<void> _showVisitDialog(BuildContext context) async {
    final cautionCtrl = TextEditingController();
    final motifCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Demander une visite'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Le client règle une caution (déductible du devis) avant que '
                  'vous receviez l’adresse exacte. Montant maximum : 5 000 FCFA.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: cautionCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Montant de la caution',
                  helperText: 'Maximum 5 000 FCFA',
                  suffixText: 'FCFA',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: motifCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Motif (optionnel)',
                  hintText: 'Ex. mesures sur place nécessaires',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Demander')),
        ],
      ),
    );
    if (ok != true) return;
    final caution =
        double.tryParse(cautionCtrl.text.replaceAll(',', '.').trim()) ?? 0;
    if (!context.mounted) return;
    if (caution <= 0) {
      showBabifixToast(context,
          type: BabifixToastType.info,
          message: 'Indiquez un montant de caution.');
      return;
    }
    if (caution > 5000) {
      showBabifixToast(context,
          type: BabifixToastType.error,
          message: 'La caution ne peut pas dépasser 5 000 FCFA.');
      return;
    }
    try {
      await DevisApi.requestVisit(
        reference: reference,
        cautionMontant: caution,
        cautionMotif: motifCtrl.text.trim(),
      );
      if (!context.mounted) return;
      showBabifixToast(context,
          type: BabifixToastType.success,
          message: 'Visite proposée au client.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!context.mounted) return;
      showBabifixToast(context,
          type: BabifixToastType.error, message: 'Échec : $e');
    }
  }

  Future<void> _cancelVisit(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Annuler la visite'),
        content: const Text(
          'Annuler la demande de visite ? La réservation repart en cours : '
          'vous pourrez envoyer un devis direct.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Non')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Annuler la visite')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await DevisApi.cancelVisit(reference);
      if (!context.mounted) return;
      showBabifixToast(context,
          type: BabifixToastType.success,
          message: 'Demande de visite annulée.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!context.mounted) return;
      showBabifixToast(context,
          type: BabifixToastType.error, message: 'Échec : $e');
    }
  }

  Future<void> _markVisitDone(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmer la visite'),
        content: const Text(
          'Confirmez-vous avoir effectué la visite de diagnostic ? '
          'La caution vous sera acquise même en cas d’annulation.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirmer')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await DevisApi.visiteDone(reference);
      if (!context.mounted) return;
      showBabifixToast(context,
          type: BabifixToastType.success, message: 'Visite confirmée.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!context.mounted) return;
      showBabifixToast(context,
          type: BabifixToastType.error, message: 'Échec : $e');
    }
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
    if (s.contains('cours')) return const Color(0xFF7C3AED);
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
        color: c.withValues(alpha: 0.10),
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
        color: const Color(0xFF122236),
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
                  color: gradient.colors.first,
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
        color: const Color(0x18EF4444),
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
                  'Urgent',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFEF4444),
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

    // Décodage borné : une photo plein format (plusieurs Mo) décodée à sa taille
    // réelle sature la mémoire GPU → l'écran devenait NOIR quand l'image passait
    // à l'écran (et redevenait normal une fois sortie). On borne la résolution de
    // décodage à ~3× la taille d'affichage : net à l'écran, sans surcharge.
    final int decodePx = (size * 3).ceil();

    if (src.startsWith('data:image/')) {
      try {
        final bytes = base64Decode(src.split(',').last);
        return Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: decodePx,
          filterQuality: FilterQuality.low,
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
        cacheWidth: decodePx,
        filterQuality: FilterQuality.low,
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
          cacheWidth: decodePx,
          filterQuality: FilterQuality.low,
          errorBuilder: (_, __, ___) => _placeholder(size),
        );
      }
    } catch (_) {}

    return _placeholder(size);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _RequirementsAnswersCard — réponses du client aux questions dynamiques de la
// catégorie (Phase 2). Format {key: {label, value, unit?}}. Rien si vide.
// ─────────────────────────────────────────────────────────────────────────────
class _RequirementsAnswersCard extends StatelessWidget {
  const _RequirementsAnswersCard({required this.reponses});

  final Map<String, dynamic> reponses;

  @override
  Widget build(BuildContext context) {
    // Ne garder que les entrées ayant une valeur non vide.
    final rows = <MapEntry<String, String>>[];
    for (final v in reponses.values) {
      if (v is! Map) continue;
      final label = (v['label'] ?? '').toString().trim();
      var value = (v['value'] ?? '').toString().trim();
      final unit = (v['unit'] ?? '').toString().trim();
      if (value.isEmpty) continue;
      if (unit.isNotEmpty) value = '$value $unit';
      rows.add(MapEntry(label.isEmpty ? '—' : label, value));
    }
    if (rows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
                color: Colors.black12, blurRadius: 12, offset: Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF4F46E5),
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: const [
                  Icon(Icons.assignment_turned_in_rounded,
                      color: Colors.white, size: 20),
                  SizedBox(width: 10),
                  Text(
                    'Détails de la demande',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                children: [
                  for (int i = 0; i < rows.length; i++) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 5,
                          child: Text(
                            rows[i].key,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 6,
                          child: Text(
                            rows[i].value,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 13.5,
                              color: Color(0xFF0B1B34),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (i != rows.length - 1)
                      const Divider(height: 18, color: Color(0xFFF1F5F9)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _AddressCard — affichage pro de l'adresse d'intervention (rue / quartier /
// ville / pays / repère), chacun avec son icône colorée et un lien
// "Ouvrir dans Google Maps" en bas.
// ─────────────────────────────────────────────────────────────────────────────
class _AddressCard extends StatelessWidget {
  const _AddressCard({
    required this.street,
    required this.quartier,
    required this.ville,
    required this.pays,
    required this.repere,
    required this.fallbackLabel,
    required this.lat,
    required this.lon,
    required this.isApproximate,
    this.distanceKm,
  });

  final String street;
  final String quartier;
  final String ville;
  final String pays;
  final String repere;
  final String fallbackLabel;
  final double? lat;
  final double? lon;
  final bool isApproximate;
  final double? distanceKm;

  bool get _hasStructured =>
      street.isNotEmpty ||
      quartier.isNotEmpty ||
      ville.isNotEmpty ||
      pays.isNotEmpty ||
      repere.isNotEmpty;

  String get _formattedAddress {
    final parts = <String>[];
    if (street.isNotEmpty) parts.add(street);
    if (quartier.isNotEmpty) parts.add(quartier);
    if (ville.isNotEmpty) parts.add(ville);
    if (pays.isNotEmpty) parts.add(pays);
    return parts.isNotEmpty ? parts.join(', ') : fallbackLabel;
  }

  Future<void> _openInMaps() async {
    final query = Uri.encodeComponent(_formattedAddress);
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En‑tête : cyan si précise, orange/verrouillée si approximative
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isApproximate ? const Color(0xFFD97706) : const Color(0xFF0891B2),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(
                  isApproximate ? Icons.lock_outline_rounded : Icons.location_on_rounded,
                  color: Colors.white,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isApproximate
                        ? "Adresse approximative"
                        : "Adresse d'intervention",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                if (distanceKm != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.directions_car_rounded,
                            color: Colors.white, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          '~${distanceKm!.toStringAsFixed(distanceKm! < 10 ? 1 : 0)} km',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: isApproximate
                ? _buildApproximateBody()
                : _buildPreciseBody(),
          ),
          // Bouton Google Maps toujours visible si adresse structurée
          if (_hasStructured && !isApproximate)
            InkWell(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(16),
              ),
              onTap: _openInMaps,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: const BoxDecoration(
                  color: Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.map_rounded, size: 18, color: Color(0xFF0891B2)),
                    SizedBox(width: 8),
                    Text(
                      'Voir sur Google Maps',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0891B2),
                        fontSize: 13,
                      ),
                    ),
                    Spacer(),
                    Icon(Icons.arrow_forward_ios_rounded,
                        size: 14, color: Color(0xFF0891B2)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildApproximateBody() {
    // Quand c'est approximatif : juste la ville avec un message
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ville.isNotEmpty)
          _AddressLine(
            icon: Icons.apartment_rounded,
            color: const Color(0xFFF59E0B),
            label: 'Ville',
            value: ville,
          ),
        if (!ville.isNotEmpty && fallbackLabel.isNotEmpty)
          Text(
            fallbackLabel,
            style: const TextStyle(fontSize: 14, color: Color(0xFF334155)),
          ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
            ),
          ),
          child: const Row(
            children: [
              Icon(Icons.lock_outline_rounded, size: 14, color: Color(0xFFD97706)),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  "Adresse exacte visible après acceptation du devis",
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Color(0xFF92400E),
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPreciseBody() {
    // Adresse précise — affichage premium/grand
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Quartier en grand — le plus important
        if (quartier.isNotEmpty) ...[
          Text(
            quartier.toUpperCase(),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1E293B),
              letterSpacing: 1,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 4),
        ],
        // Rue
        if (street.isNotEmpty) ...[
          Row(
            children: [
              Icon(Icons.add_road_rounded, size: 16, color: const Color(0xFF0EA5E9)),
              const SizedBox(width: 6),
              Text(
                street,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF334155),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],
        // Ville
        if (ville.isNotEmpty) ...[
          Row(
            children: [
              Icon(Icons.apartment_rounded, size: 16, color: const Color(0xFFF59E0B)),
              const SizedBox(width: 6),
              Text(
                ville,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],
        // Point de repère
        if (repere.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFF22C55E).withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.pin_drop_rounded, size: 16, color: Color(0xFF22C55E)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'POINT DE REPÈRE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF22C55E),
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        repere,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        // Pays si présent
        if (pays.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.flag_rounded, size: 14, color: const Color(0xFFEF4444)),
              const SizedBox(width: 6),
              Text(
                pays,
                style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _AddressLine extends StatelessWidget {
  const _AddressLine({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.isHighlighted = false,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  padding: isHighlighted
                      ? const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4)
                      : null,
                  decoration: isHighlighted
                      ? BoxDecoration(
                          color: color.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: color.withValues(alpha: 0.3),
                          ),
                        )
                      : null,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 14,
                      color: const Color(0xFF1E293B),
                      fontWeight: isHighlighted
                          ? FontWeight.w700
                          : FontWeight.w600,
                    ),
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
