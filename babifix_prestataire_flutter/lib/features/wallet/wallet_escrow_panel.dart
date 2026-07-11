/// Panneau Wallet — distingue Escrow / Disponible / Cash (Phase F — P2).
///
/// À insérer dans l'écran wallet existant (en haut), via :
///   WalletEscrowPanel(...)
///
/// Il charge la liste des réservations actives + leur quote escrow pour
/// estimer le montant en attente de libération.
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../babifix_design_system.dart';
import '../../models/babifix_models.dart';
import '../../services/babifix_api.dart';
import '../../shared/services/babifix_user_store.dart';
import '../../shared/widgets/animated_money.dart';
import '../../shared/widgets/babifix_phase_widgets.dart';
import 'escrow_payments_screen.dart';
import '../../shared/widgets/babifix_ring_loader.dart';

class WalletEscrowPanel extends StatefulWidget {
  final double soldeDisponibleFcfa;
  final bool hidden;
  const WalletEscrowPanel({
    super.key,
    required this.soldeDisponibleFcfa,
    this.hidden = false,
  });

  @override
  State<WalletEscrowPanel> createState() => _WalletEscrowPanelState();
}

class _WalletEscrowPanelState extends State<WalletEscrowPanel> {
  bool _loading = true;
  double _escrowPending = 0; // Net à toucher quand le client confirmera
  double _cashAttendu = 0; // Cash à recevoir en main propre
  int _countActifs = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // Liste des demandes actives du presta
      // « En attente client » = travaux terminés, en attente de confirmation/
      // solde du client : l'argent est toujours en escrow et DOIT apparaître ici
      // (sinon le montant en escrow retombe à 0 dès que le presta termine).
      final r = await BabifixUserStore.authGet(
        '/api/prestataire/requests/?statut_in=DEVIS_ACCEPTE,INTERVENTION_EN_COURS,En attente client,Terminee',
      );
      if (r.statusCode >= 400) {
        setState(() => _loading = false);
        return;
      }
      final j = jsonDecode(r.body);
      // L'endpoint renvoie la liste sous la clé « items » (et non « requests ») :
      // lire la mauvaise clé donnait une liste vide → escrow toujours à 0.
      final list = (j['items'] as List? ?? j['requests'] as List? ?? const []);
      double escrow = 0;
      double cash = 0;
      int n = 0;
      for (final raw in list) {
        if (raw is! Map) continue;
        final ref = raw['reference']?.toString();
        if (ref == null || ref.isEmpty) continue;
        try {
          final q = await EscrowApi.quote(ref);
          if (q.fundsReleasedAt != null) continue;
          if (q.isMobile && q.acompteValide) {
            // VRAI montant bloqué en escrow = ce que le client a RÉELLEMENT
            // versé (acompte seul, ou acompte + solde). C'est le montant
            // littéralement détenu en séquestre. Repli sur le net si l'info
            // n'est pas dispo (ancien backend non redéployé).
            escrow += q.montantVerse > 0 ? q.montantVerse : q.netPrestataire;
          }
          if (q.isCash && q.acompteValide) {
            cash += q.cashRemainderDueToProvider;
          }
          n++;
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _escrowPending = escrow;
        _cashAttendu = cash;
        _countActifs = n;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : const Color(0xFF0F172A);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BabifixDesign.ciBlue.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BabifixDesign.ciBlue.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_wallet, color: onSurface),
              const SizedBox(width: 8),
              Text('Vos revenus',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800, color: onSurface)),
              const Spacer(),
              if (_loading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: BabifixRingLoader.cyan(size: 28),
                )
              else
                IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh, size: 18),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _tile(
                  label: 'Disponible',
                  value: fmtMoney(widget.soldeDisponibleFcfa),
                  color: BabifixDesign.ciGreen,
                  icon: Icons.check_circle,
                  helper: 'retirable maintenant',
                  masked: widget.hidden,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _tile(
                  label: 'Bloqué en escrow',
                  value: fmtMoney(_escrowPending),
                  color: BabifixDesign.ciBlue,
                  icon: Icons.lock_outline,
                  helper: 'versé (net) à la confirmation',
                  masked: widget.hidden,
                ),
              ),
            ],
          ),
          if (_cashAttendu > 0) ...[
            const SizedBox(height: 8),
            _tile(
              label: 'Cash attendu (main à main)',
              value: fmtMoney(_cashAttendu),
              color: Colors.orange.shade700,
              icon: Icons.payments_outlined,
              helper: 'à percevoir directement du client',
              wide: true,
              masked: widget.hidden,
            ),
          ],
          if (_countActifs > 0) ...[
            const SizedBox(height: 8),
            Text(
              '$_countActifs chantier${_countActifs > 1 ? 's' : ''} en cours.',
              style:
                  TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
          const SizedBox(height: 10),
          // Bouton « Voir le détail » → écran liste des escrows par résa
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => const PrestataireEscrowPaymentsScreen(),
                ),
              ),
              icon: Icon(Icons.list_alt, size: 18, color: BabifixDesign.iconOnLight),
              label: Text(
                'Voir mes paiements en attente',
                style: TextStyle(
                  color: BabifixDesign.ciBlue,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                    color: BabifixDesign.ciBlue.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Extrait la partie numérique d'une chaîne "12 345 F CFA" pour le tween.
  double _parseMoney(String s) {
    final digits = RegExp(r'[\d]+').allMatches(s).map((m) => m.group(0)!).join();
    return double.tryParse(digits) ?? 0;
  }

  Widget _tile({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
    required String helper,
    bool wide = false,
    bool masked = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        color: color,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Tween animé : si la valeur arrive à "12 345 F CFA", on affiche un
          // compteur qui grimpe en 650 ms — bien plus satisfaisant visuellement.
          masked
              ? Text(
                  '•••• F CFA',
                  style: TextStyle(
                      fontSize: wide ? 18 : 17,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                      color: const Color(0xFF0B1B34)),
                )
              : AnimatedMoney(
                  value: _parseMoney(value),
                  // Couleur vive (accent du tile) + plus grande → bien lisible.
                  style: TextStyle(
                      fontSize: wide ? 18 : 17,
                      fontWeight: FontWeight.w900,
                      color: color),
                ),
          const SizedBox(height: 2),
          Text(helper,
              style: TextStyle(
                  fontSize: 10, color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}
