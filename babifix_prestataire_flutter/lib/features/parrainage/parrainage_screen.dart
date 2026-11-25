import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../babifix_design_system.dart';
import '../../shared/services/babifix_user_store.dart';
import '../../shared/widgets/babifix_button.dart';
import '../../shared/widgets/babifix_ring_loader.dart';
import '../../shared/widgets/babifix_snackbar.dart';

class ParrainageScreen extends StatefulWidget {
  const ParrainageScreen({super.key});

  @override
  State<ParrainageScreen> createState() => _ParrainageScreenState();
}

class _ParrainageScreenState extends State<ParrainageScreen> {
  bool _loading = true;
  String? _error;
  String _code = '';
  int _filleuls = 0;
  double _creditsEarned = 0;
  int _creditParrain = 2000;
  int _creditFilleul = 1000;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final resp = await BabifixUserStore.authGet('/api/auth/referral/');
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() {
          _code = data['code'] ?? '';
          _filleuls = data['filleuls'] ?? 0;
          _creditsEarned = (data['credits_earned'] ?? 0).toDouble();
          _creditParrain = data['credit_parrain'] ?? 2000;
          _creditFilleul = data['credit_filleul'] ?? 1000;
        });
      } else {
        setState(() { _error = 'Erreur chargement'; });
      }
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      setState(() { _loading = false; });
    }
  }

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: _code));
    showBabifixToast(
        context,
        type: BabifixToastType.success,
        message: 'Code copié !',
      );
  }

  void _shareCode() {
    Share.share(
      '🔧 Rejoins BABIFIX et gagne ${_creditFilleul.toStringAsFixed(0)} FCFA sur ta 1ère réservation !\n'
      'Utilise mon code : $_code\n'
      'Télécharge l\'app : https://babifix.ci/app',
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final cardBg = BabifixDesign.surfaceOf(context);
    final borderCol = BabifixDesign.borderOf(context);
    final textPrimary = BabifixDesign.textPrimaryOf(context);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text(
          'Parrainage',
          style: TextStyle(color: textPrimary, fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: textPrimary,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: BabifixRingLoader.cyan(size: 36))
          : _error != null
              ? Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_error!, style: const TextStyle(color: BabifixDesign.error)),
                    const SizedBox(height: 12),
                    BabifixButton(label: 'Réessayer', width: 160, onPressed: _load),
                  ],
                ))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header architectural matte
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: BabifixDesign.navy,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: BabifixDesign.borderDark),
                          ),
                          child: Column(
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: BabifixDesign.ciOrange.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Icon(Icons.people_alt_rounded, color: BabifixDesign.ciOrange, size: 30),
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                'Invitez vos confrères',
                                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Vous gagnez $_creditParrain FCFA par filleul\nVotre filleul gagne $_creditFilleul FCFA',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: BabifixDesign.textMutedDark,
                                  fontSize: 13.5,
                                  height: 1.45,
                                  fontFeatures: BabifixDesign.tabularFigures,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Code
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: borderCol),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Votre code de parrainage',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                  color: BabifixDesign.textMutedOf(context),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                      decoration: BoxDecoration(
                                        color: BabifixDesign.cyanDeep.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: BabifixDesign.cyanDeep.withValues(alpha: 0.30)),
                                      ),
                                      child: Text(
                                        _code.isEmpty ? 'N/A' : _code,
                                        style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 4,
                                          color: BabifixDesign.cyanDeep,
                                          fontFeatures: BabifixDesign.tabularFigures,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  IconButton.filled(
                                    onPressed: _code.isEmpty ? null : _copyCode,
                                    icon: const Icon(Icons.copy_rounded),
                                    style: IconButton.styleFrom(
                                      backgroundColor: BabifixDesign.navy,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              BabifixButton(
                                label: 'Partager mon code',
                                icon: Icons.share_rounded,
                                onPressed: _code.isEmpty ? null : _shareCode,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Stats
                        Row(
                          children: [
                            Expanded(child: _StatCard(
                              icon: Icons.group_add_rounded,
                              value: '$_filleuls',
                              label: 'Filleuls',
                              color: BabifixDesign.cyanDeep,
                              cardBg: cardBg,
                            )),
                            const SizedBox(width: 12),
                            Expanded(child: _StatCard(
                              icon: Icons.account_balance_wallet_rounded,
                              value: '${_creditsEarned.toStringAsFixed(0)} F',
                              label: 'Crédits gagnés',
                              color: BabifixDesign.success,
                              cardBg: cardBg,
                            )),
                          ],
                        ),
                        const SizedBox(height: 20),
                        // Comment ça marche
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: borderCol),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Comment ça marche ?',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                  color: textPrimary,
                                ),
                              ),
                              const SizedBox(height: 16),
                              const _StepItem(step: '1', text: 'Partagez votre code unique à un ami'),
                              const _StepItem(step: '2', text: 'Votre ami s\'inscrit et utilise votre code'),
                              _StepItem(step: '3', text: 'À sa 1ère réservation, vous recevez $_creditParrain FCFA'),
                              _StepItem(step: '4', text: 'Votre ami reçoit $_creditFilleul FCFA de bienvenue'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final Color cardBg;
  const _StatCard({required this.icon, required this.value, required this.label, required this.color, required this.cardBg});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: cardBg,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: BabifixDesign.borderOf(context)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 26),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: color,
            fontFeatures: BabifixDesign.tabularFigures,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 12, color: BabifixDesign.textMutedOf(context))),
      ],
    ),
  );
}

class _StepItem extends StatelessWidget {
  final String step;
  final String text;
  const _StepItem({required this.step, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28, height: 28,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: BabifixDesign.navy, shape: BoxShape.circle),
          child: Text(step, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(text, style: const TextStyle(fontSize: 14)),
        )),
      ],
    ),
  );
}
