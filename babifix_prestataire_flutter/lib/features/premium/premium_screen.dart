import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../babifix_design_system.dart';
import '../../shared/error_utils.dart';
import '../../shared/services/babifix_remote_config.dart';
import '../../shared/services/babifix_user_store.dart';
import '../../shared/widgets/babifix_button.dart';
import '../../shared/widgets/babifix_skeleton.dart';
import '../../shared/widgets/babifix_snackbar.dart';
import '../../shared/widgets/payment_method_logo.dart';
import '../wallet/babifix_wallet_card.dart';

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  bool _loading = true;
  bool _subscribing = false;
  String? _error;

  bool _isPremium = false;
  String _currentTier = 'standard';
  int _daysRemaining = 0;
  double _commissionEffective = 18;
  bool _trialAvailable = true;
  bool _isAnnual = false; // toggle Mensuel ↔ Annuel
  double _simCaFcfa = 150000;
  Map<String, dynamic>? _calcData;

  List<Map<String, dynamic>> _tiers = [];

  static const _tierColors = {
    'standard': Color(0xFF64748B),
    'silver': Color(0xFFC0C0C0),
    'gold': Color(0xFFF59E0B),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final [statusResp, tiersResp] = await Future.wait<http.Response>([
        BabifixUserStore.authGet('/api/prestataire/premium/subscribe/'),
        BabifixUserStore.authGet('/api/prestataire/premium/tiers/'),
      ]);

      if (statusResp.statusCode == 200) {
        final d = jsonDecode(statusResp.body);
        setState(() {
          _isPremium = d['is_premium'] ?? false;
          _currentTier = d['tier'] ?? 'standard';
          _daysRemaining = d['days_remaining'] ?? 0;
          _commissionEffective = (d['commission_effective'] ?? 18).toDouble();
          _trialAvailable = d['trial_available'] ?? true;
          _isAnnual = d['is_annual'] ?? false;
        });
      }
      if (tiersResp.statusCode == 200) {
        final d = jsonDecode(tiersResp.body);
        setState(() { _tiers = List<Map<String, dynamic>>.from(d['tiers'] ?? []); });
      }
      await _loadCalculator(_simCaFcfa.round());
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      setState(() { _loading = false; });
    }
  }

  Future<void> _loadCalculator(int caFcfa) async {
    try {
      final resp = await BabifixUserStore.authGet(
        '/api/prestataire/premium/calculator/?ca=$caFcfa',
      );
      if (resp.statusCode == 200 && mounted) {
        setState(() {
          _calcData = jsonDecode(resp.body) as Map<String, dynamic>;
        });
      }
    } catch (_) {}
  }

  Future<void> _subscribe(String tier, {required String billingPeriod}) async {
    setState(() { _subscribing = true; });
    try {
      final resp = await BabifixUserStore.authPost(
        '/api/prestataire/premium/subscribe/',
        body: jsonEncode({'tier': tier, 'billing_period': billingPeriod}),
      );
      final data = jsonDecode(resp.body);
      if (resp.statusCode == 200 && data['ok'] == true) {
        if (!mounted) return;
        await _showPremiumActivatedAnimation(
          tier,
          trial: billingPeriod == 'trial',
        );
        await _load();
      } else if (resp.statusCode == 402) {
        if (!mounted) return;
        _showInsufficientFundsDialog(data);
      } else if (resp.statusCode == 403 && data['error'] == 'trial_already_used') {
        if (!mounted) return;
        showBabifixToast(
        context,
        type: BabifixToastType.warning,
        message: data['message']?.toString() ?? 'Essai déjà utilisé',
      );
      } else {
        if (!mounted) return;
        showBabifixToast(
        context,
        type: BabifixToastType.error,
        message: data['error']?.toString() ?? 'Erreur',
      );
      }
    } catch (e) {
      if (!mounted) return;
      showBabifixToast(
        context,
        type: BabifixToastType.error,
        message: userFriendlyError(e),
      );
    } finally {
      if (mounted) setState(() { _subscribing = false; });
    }
  }

  /// Animation premium « pro » jouée à l'activation d'un abonnement : médaille
  /// dorée qui apparaît avec un halo, étincelles, et message de bienvenue.
  /// Fluide (scale + fade) et auto-fermée.
  Future<void> _showPremiumActivatedAnimation(String tier, {bool trial = false}) async {
    if (!mounted) return;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'premium',
      barrierColor: Colors.black.withValues(alpha: 0.62),
      transitionDuration: const Duration(milliseconds: 420),
      pageBuilder: (_, __, ___) =>
          _PremiumActivatedOverlay(tier: tier, trial: trial),
      transitionBuilder: (_, anim, __, child) {
        final c = Curves.easeOutBack.transform(anim.value.clamp(0.0, 1.0));
        return Opacity(
          opacity: anim.value.clamp(0.0, 1.0),
          child: Transform.scale(scale: 0.8 + 0.2 * c, child: child),
        );
      },
    );
  }

  void _showInsufficientFundsDialog(Map data) {
    final price = (data['price'] ?? 0).toDouble();
    final solde = (data['solde_actuel'] ?? 0).toDouble();
    final tier = (data['tier'] ?? '').toString();
    final billingPeriod = (data['billing_period'] ?? 'monthly').toString();
    final diff = (price - solde).clamp(0, double.infinity);

    String? selectedOperator;
    final operators = const [
      {'code': 'ORANGE_MONEY', 'label': 'Orange Money', 'color': Color(0xFFFF6600)},
      {'code': 'MTN_MOMO', 'label': 'MTN Money', 'color': Color(0xFFFFCC00)},
      {'code': 'MOOV', 'label': 'Moov Money', 'color': Color(0xFF0050AA)},
      {'code': 'WAVE', 'label': 'Wave', 'color': Color(0xFF1DCCFB)},
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          backgroundColor: BabifixDesign.surfaceOf(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: BabifixDesign.borderOf(context)),
          ),
          title: Text(
            'Solde insuffisant',
            style: TextStyle(
              color: BabifixDesign.textPrimaryOf(context),
              fontWeight: FontWeight.w800,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Prix de l'abonnement : ${price.toStringAsFixed(0)} FCFA\n"
                  "Votre solde : ${solde.toStringAsFixed(0)} FCFA\n"
                  "Reste à régler : ${diff.toStringAsFixed(0)} FCFA",
                  style: TextStyle(
                    color: BabifixDesign.textMutedOf(context),
                    height: 1.5,
                    fontFeatures: BabifixDesign.tabularFigures,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Choisissez un service Mobile Money :',
                  style: TextStyle(
                    color: BabifixDesign.textPrimaryOf(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: operators.map((op) {
                    final code = op['code'] as String;
                    final sel = selectedOperator == code;
                    final isDarkBg = Theme.of(context).brightness == Brightness.dark;
                    return InkWell(
                      onTap: () => setStateDialog(() => selectedOperator = code),
                      borderRadius: BorderRadius.circular(14),
                      child: AnimatedContainer(
                        duration: BabifixDesign.durationFast,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: sel
                              ? BabifixDesign.ciOrange.withValues(alpha: 0.14)
                              : BabifixDesign.elevatedSurfaceOf(context),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: sel
                                ? BabifixDesign.ciOrange
                                : BabifixDesign.borderOf(context),
                            width: sel ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            BabifixPaymentMethodBadge(
                              methodId: code,
                              size: 28,
                              selected: sel,
                              onDarkSurface: isDarkBg,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              op['label'] as String,
                              style: TextStyle(
                                color: sel
                                    ? BabifixDesign.textPrimaryOf(context)
                                    : BabifixDesign.textMutedOf(context),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Annuler',
                style: TextStyle(color: BabifixDesign.textMutedOf(context)),
              ),
            ),
            BabifixButton(
              label: 'Payer ${price.toStringAsFixed(0)} F',
              icon: Icons.phone_iphone_rounded,
              height: 44,
              width: 170,
              onPressed: selectedOperator == null
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      _payPremiumViaMobileMoney(
                        tier: tier,
                        billingPeriod: billingPeriod,
                        operator: selectedOperator!,
                      );
                    },
            ),
          ],
        ),
      ),
    );
  }

  /// Payer l'abonnement premium via Mobile Money (GeniusPay) : endpoint dédié.
  /// En simulation, l'abonnement est activé immédiatement (réponse ok:true).
  /// En paiement réel, une page de checkout s'ouvre ; le webhook GeniusPay
  /// activera l'abonnement à la confirmation.
  Future<void> _payPremiumViaMobileMoney({
    required String tier,
    required String billingPeriod,
    required String operator,
  }) async {
    setState(() { _subscribing = true; });
    try {
      final resp = await BabifixUserStore.authPost(
        '/api/prestataire/premium/pay/',
        body: jsonEncode({
          'tier': tier,
          'billing_period': billingPeriod,
          'mobile_money_operator': operator,
        }),
      );
      if (resp.statusCode >= 400) {
        if (mounted) {
          showBabifixToast(
            context,
            type: BabifixToastType.error,
            message: 'Échec initialisation paiement : ${resp.statusCode}',
          );
        }
        return;
      }
      final j = jsonDecode(resp.body);
      // Activation immédiate (simulation / sandbox / auto-validation).
      if (j['ok'] == true) {
        if (!mounted) return;
        await _showPremiumActivatedAnimation(tier);
        await _load();
        return;
      }
      // Paiement réel : ouvrir la page de checkout. Le webhook activera ensuite.
      final url = (j['checkout_url'] ?? j['payment_url'] ?? '').toString();
      if (url.isEmpty) {
        if (mounted) {
          showBabifixToast(
            context,
            type: BabifixToastType.warning,
            message: 'Paiement initié. Vérifiez votre téléphone, puis actualisez.',
          );
        }
        return;
      }
      final ok = await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        showBabifixToast(
          context,
          type: BabifixToastType.error,
          message: "Impossible d'ouvrir la page de paiement.",
        );
      }
    } catch (e) {
      if (mounted) {
        showBabifixToast(
          context,
          type: BabifixToastType.error,
          message: userFriendlyError(e),
        );
      }
    } finally {
      if (mounted) setState(() { _subscribing = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BabifixDesign.navy,
      appBar: AppBar(
        title: const Text(
          'BABIFIX Premium',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const BabifixSkeletonScope(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  children: [
                    BabifixSkeletonCard(),
                    SizedBox(height: 14),
                    BabifixSkeletonCard(),
                  ],
                ),
              ),
            )
          : _error != null
          ? _buildError()
          : RefreshIndicator(
              onRefresh: _load,
              color: BabifixDesign.cyan,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_isPremium) _buildCurrentStatus(),
                    if (!_isPremium) _buildCommissionInfo(),
                    const SizedBox(height: 8),
                    const Text(
                      'Choisissez votre formule',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Plus de visibilité, moins de commission, plus de chantiers.',
                      style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                    ),
                    const SizedBox(height: 18),
                    _buildBillingToggle(),
                    const SizedBox(height: 18),
                    ..._tiers.map((tier) => _buildTierCard(tier)),
                    const SizedBox(height: 16),
                    _buildProfitabilityCalculator(),
                    const SizedBox(height: 16),
                    _buildComparisonTable(),
                    const SizedBox(height: 16),
                    if (_trialAvailable && !_isPremium) _buildTrialBanner(),
                    const SizedBox(height: 20),
                    _buildPaymentNote(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: BabifixDesign.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline, size: 48, color: BabifixDesign.error),
            ),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Erreur inconnue',
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            BabifixButton(
              label: 'Réessayer',
              width: 180,
              onPressed: _load,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentStatus() {
    final color = _tierColors[_currentTier] ?? BabifixDesign.cyanDeep;
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: BabifixDesign.navy,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 1.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.workspace_premium_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Premium ${_currentTier.toUpperCase()}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$_daysRemaining jours restants',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Commission : ${_commissionEffective.toStringAsFixed(0)}%',
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _subscribing ? null : _cancelSubscription,
              icon: const Icon(Icons.cancel_outlined,
                  size: 18, color: Colors.white),
              label: const Text(
                'Résilier mon abonnement',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.white.withValues(alpha: 0.6)),
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelSubscription() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF152A45),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Résilier l\'abonnement ?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Vous repasserez en formule Standard : commission de base '
          '(${BabifixRemoteConfig.instance.current.commissionBasePct} %), '
          '3 devis actifs et perte du badge. Cette action est immediate.',
          style: const TextStyle(color: Color(0xFFB4C2D9), height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler',
                style: TextStyle(color: Color(0xFFB4C2D9))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: BabifixDesign.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Résilier'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() { _subscribing = true; });
    try {
      final resp = await BabifixUserStore.authPost(
        '/api/prestataire/premium/subscribe/',
        body: jsonEncode({'tier': 'standard'}),
      );
      final data = jsonDecode(resp.body);
      if (resp.statusCode == 200 && data['ok'] == true) {
        if (!mounted) return;
        showBabifixToast(
          context,
          type: BabifixToastType.info,
          message: 'Abonnement résilié : retour en Standard.',
        );
        await _load();
      } else {
        if (!mounted) return;
        showBabifixToast(
          context,
          type: BabifixToastType.error,
          message: data['error']?.toString() ?? 'Erreur',
        );
      }
    } catch (e) {
      if (!mounted) return;
      showBabifixToast(
        context,
        type: BabifixToastType.error,
        message: userFriendlyError(e),
      );
    } finally {
      if (mounted) setState(() { _subscribing = false; });
    }
  }

  Widget _buildCommissionInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: BabifixDesign.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BabifixDesign.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: BabifixDesign.warning.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.info_outline_rounded,
              color: BabifixDesign.warning,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Commission actuelle : ${_commissionEffective.toStringAsFixed(0)}%\nPassez Premium pour réduire votre commission et personnaliser votre carte Wallet.',
              style: TextStyle(
                fontSize: 13,
                color: BabifixDesign.textPrimaryOf(context),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBillingToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: BabifixDesign.surfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BabifixDesign.borderOf(context)),
      ),
      child: Row(
        children: [
          Expanded(child: _toggleButton('Mensuel', false)),
          Expanded(child: _toggleButton('Annuel · 2 mois offerts', true)),
        ],
      ),
    );
  }

  Widget _toggleButton(String label, bool annual) {
    final sel = _isAnnual == annual;
    return GestureDetector(
      onTap: () => setState(() => _isAnnual = annual),
      child: AnimatedContainer(
        duration: BabifixDesign.durationFast,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: sel ? BabifixDesign.ciOrange : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: sel ? Colors.white : BabifixDesign.textMutedOf(context),
            fontWeight: FontWeight.w800,
            fontSize: 13.5,
          ),
        ),
      ),
    );
  }

  Widget _buildTierCard(Map<String, dynamic> tier) {
    final tierId = tier['id']?.toString() ?? '';
    final isStandard = tierId == 'standard';
    final isActive = _isPremium
        ? _currentTier == tierId
        : isStandard; // tier actuel par défaut = standard
    final isPopular = tier['popular'] == true;
    final color = _tierColors[tierId] ?? BabifixDesign.cyan;

    final priceMonthly = (tier['price'] ?? 0).toInt();
    final priceAnnual = (tier['price_annual'] ?? priceMonthly * 12).toInt();
    final savingsPct = (tier['annual_savings_pct'] ?? 0).toInt();
    final displayPrice = _isAnnual ? priceAnnual : priceMonthly;
    final period = isStandard ? '' : (_isAnnual ? '/ an' : '/ mois');

    final trialAvailable = tier['trial_available'] == true && _trialAvailable;

    final walletTier = tierId == 'gold'
        ? BabifixWalletTier.gold
        : tierId == 'silver'
            ? BabifixWalletTier.silver
            : BabifixWalletTier.standard;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          margin: EdgeInsets.only(bottom: 16, top: isPopular ? 12 : 0),
          decoration: BoxDecoration(
            color: BabifixDesign.surfaceOf(context),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isActive || isPopular ? color : BabifixDesign.borderOf(context),
              width: isActive || isPopular ? 1.8 : 1,
            ),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        tierId == 'gold'
                            ? Icons.star_rounded
                            : tierId == 'silver'
                                ? Icons.star_half_rounded
                                : Icons.verified_user_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tier['name']?.toString() ?? '',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              color: BabifixDesign.textPrimaryOf(context),
                            ),
                          ),
                          if (isStandard)
                            Text(
                              'Gratuit pour tous les prestataires vérifiés',
                              style: TextStyle(
                                color: BabifixDesign.textMutedOf(context),
                                fontSize: 12,
                              ),
                            )
                          else
                            Row(
                              children: [
                                Text(
                                  '$displayPrice FCFA',
                                  style: TextStyle(
                                    color: BabifixDesign.textPrimaryOf(context),
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    fontFeatures: BabifixDesign.tabularFigures,
                                  ),
                                ),
                                Text(
                                  ' $period',
                                  style: TextStyle(
                                    color: BabifixDesign.textMutedOf(context),
                                    fontSize: 12,
                                  ),
                                ),
                                if (_isAnnual && savingsPct > 0) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: BabifixDesign.success
                                          .withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '-$savingsPct%',
                                      style: const TextStyle(
                                        color: BabifixDesign.success,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        fontFeatures: BabifixDesign.tabularFigures,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                        ],
                      ),
                    ),
                    if (isActive)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'ACTIF',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Aperçu de votre carte Wallet',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: BabifixDesign.textMutedOf(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    BabifixWalletCard(
                      compactPreview: true,
                      tier: walletTier,
                      soldeFcfa: 0,
                      prestataireName:
                          'EDITION ${(tier['name'] ?? tierId).toString().toUpperCase()}',
                      maskedCardNumber: '**** **** **** 2250',
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    ...((tier['features'] as List?) ?? []).map(
                      (f) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.check_circle_rounded, color: color, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                f.toString(),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: BabifixDesign.textPrimaryOf(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (!isActive && !isStandard) ...[
                      const SizedBox(height: 14),
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: BabifixDesign.elevatedSurfaceOf(context),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: BabifixDesign.borderOf(context)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.account_balance_wallet_rounded,
                                size: 16, color: BabifixDesign.cyanDeep),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Déduit de votre solde Wallet BABIFIX (ou Mobile Money)',
                                style: TextStyle(
                                  color: BabifixDesign.textMutedOf(context),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      BabifixButton(
                        label: _isAnnual
                            ? 'Souscrire ${tier['name']} (Annuel)'
                            : 'Souscrire ${tier['name']}',
                        loadingLabel: 'Activation...',
                        isLoading: _subscribing,
                        backgroundColor: BabifixDesign.ciOrange,
                        onPressed: _subscribing
                            ? null
                            : () => _subscribe(
                                  tierId,
                                  billingPeriod: _isAnnual ? 'annual' : 'monthly',
                                ),
                      ),
                      if (trialAvailable) ...[
                        const SizedBox(height: 10),
                        BabifixButton(
                          label: 'Essai gratuit 7 jours',
                          variant: BabifixButtonVariant.outlined,
                          icon: Icons.bolt_rounded,
                          height: 44,
                          onPressed: _subscribing
                              ? null
                              : () => _subscribe(tierId, billingPeriod: 'trial'),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (isPopular)
          Positioned(
            top: -2,
            left: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.5),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.local_fire_department_rounded,
                      color: Colors.white, size: 14),
                  SizedBox(width: 4),
                  Text(
                    'LE PLUS POPULAIRE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildComparisonTable() {
    if (_tiers.length < 2) return const SizedBox.shrink();

    Widget header(String label, Color? color) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color ?? BabifixDesign.textPrimaryOf(context),
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
              ),
            ),
          ),
        );

    Widget cell(String text, {bool bold = false}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: BabifixDesign.textPrimaryOf(context),
                fontSize: 12,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                fontFeatures: BabifixDesign.tabularFigures,
              ),
            ),
          ),
        );

    Widget row(String label, List<String> values) => Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: BabifixDesign.borderOf(context))),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: 11, horizontal: 12),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: BabifixDesign.textMutedOf(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              for (final v in values) cell(v),
            ],
          ),
        );

    final basePct = BabifixRemoteConfig.instance.current.commissionBasePct;
    final floorPct = BabifixRemoteConfig.instance.current.commissionFloorPct;
    String commissionFor(Map<String, dynamic> t) {
      final eff = (t['commission_effective_pct'] as num?)?.toInt();
      if (eff != null) return '$eff %';
      final red = (t['commission_reduction'] as num?)?.toInt() ?? 0;
      final computed = (basePct - red).clamp(floorPct, 50);
      return '$computed %';
    }
    String quota(int q) => q == -1 ? 'Illimites' : '$q';
    String visibility(int pct) => pct == 0 ? 'Standard' : '+$pct %';

    return Container(
      decoration: BoxDecoration(
        color: BabifixDesign.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BabifixDesign.borderOf(context)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  flex: 1,
                  child: Text(
                    'Comparaison',
                    style: TextStyle(
                      color: BabifixDesign.textPrimaryOf(context),
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
                for (final t in _tiers)
                  header(
                    (t['name'] ?? '').toString(),
                    _tierColors[t['id']] ?? BabifixDesign.textPrimaryOf(context),
                  ),
              ],
            ),
          ),
          row('Commission',
              _tiers.map((t) => commissionFor(t)).toList()),
          row('Visibilité',
              _tiers.map((t) => visibility((t['visibility_boost_pct'] ?? 0) as int)).toList()),
          row('Devis actifs',
              _tiers.map((t) => quota((t['max_active_devis'] ?? 3) as int)).toList()),
          row(
            'Badge profil',
            _tiers.map((t) {
              final b = (t['badge'] ?? '').toString().trim();
              if (b.isNotEmpty) return b;
              final id = t['id']?.toString() ?? '';
              if (id == 'silver') return 'Pro vérifié';
              if (id == 'gold') return 'Top';
              return 'Standard';
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildProfitabilityCalculator() {
    final comp = _calcData?['comparison'] as Map<String, dynamic>?;
    final silverMap = comp?['silver'] as Map<String, dynamic>?;
    final goldMap = comp?['gold'] as Map<String, dynamic>?;
    final silverGain = (silverMap?['net_gain_vs_standard'] as num?)?.toInt() ?? 0;
    final goldGain = (goldMap?['net_gain_vs_standard'] as num?)?.toInt() ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BabifixDesign.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BabifixDesign.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calculate_rounded, color: Color(0xFFB45309), size: 20),
              const SizedBox(width: 8),
              Text(
                'Simulateur de rentabilite mensuelle',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: BabifixDesign.textPrimaryOf(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Chiffre d\'affaires estime : ${(_simCaFcfa / 1000).round()} 000 FCFA / mois',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: BabifixDesign.textMutedOf(context),
            ),
          ),
          Slider(
            value: _simCaFcfa,
            min: 50000,
            max: 600000,
            divisions: 11,
            activeColor: const Color(0xFFB45309),
            onChanged: (v) => setState(() => _simCaFcfa = v),
            onChangeEnd: (v) => _loadCalculator(v.round()),
          ),
          if (silverMap != null && goldMap != null)
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0E3B2E).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Silver', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                        Text(
                          '${silverGain >= 0 ? '+' : ''}$silverGain FCFA net',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 13.5,
                            color: silverGain >= 0 ? const Color(0xFF047857) : const Color(0xFFC2410C),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFB45309).withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Gold', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                        Text(
                          '${goldGain >= 0 ? '+' : ''}$goldGain FCFA net',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 13.5,
                            color: goldGain >= 0 ? const Color(0xFF047857) : const Color(0xFFC2410C),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildTrialBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BabifixDesign.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BabifixDesign.cyanDeep.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.bolt_rounded, color: BabifixDesign.cyanDeep, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Essai gratuit 7 jours',
                  style: TextStyle(
                    color: BabifixDesign.textPrimaryOf(context),
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Testez Argent ou Or gratuitement. Aucun débit, sans engagement.',
                  style: TextStyle(
                    color: BabifixDesign.textMutedOf(context),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentNote() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BabifixDesign.surfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BabifixDesign.borderOf(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lightbulb_outline_rounded,
            color: BabifixDesign.textMutedOf(context),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Le montant est déduit de votre wallet BABIFIX. Si votre solde est insuffisant, vous pourrez payer via Mobile Money.',
              style: TextStyle(
                fontSize: 12,
                color: BabifixDesign.textMutedOf(context),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Overlay d'activation premium : médaille dorée avec halo pulsant, étincelles
/// qui jaillissent, et message de bienvenue. Se ferme tout seul après ~2,4 s.
class _PremiumActivatedOverlay extends StatefulWidget {
  const _PremiumActivatedOverlay({required this.tier, this.trial = false});
  final String tier;
  final bool trial;

  @override
  State<_PremiumActivatedOverlay> createState() =>
      _PremiumActivatedOverlayState();
}

class _PremiumActivatedOverlayState extends State<_PremiumActivatedOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();
  late final AnimationController _halo = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);
  Timer? _auto;

  static const _gold = Color(0xFFF5B301);

  @override
  void initState() {
    super.initState();
    _auto = Timer(const Duration(milliseconds: 2400), () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    _auto?.cancel();
    _intro.dispose();
    _halo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tierLabel = widget.tier.toUpperCase();
    return GestureDetector(
      onTap: () => Navigator.of(context).maybePop(),
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Container(
          width: 300,
          padding: const EdgeInsets.fromLTRB(24, 30, 24, 26),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF14233D), Color(0xFF0B1B34)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _gold.withValues(alpha: 0.5), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: _gold.withValues(alpha: 0.25),
                blurRadius: 40,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Médaille + halo pulsant + étincelles.
              SizedBox(
                width: 130,
                height: 130,
                child: AnimatedBuilder(
                  animation: Listenable.merge([_intro, _halo]),
                  builder: (_, __) {
                    final pop = Curves.easeOutBack
                        .transform(_intro.value.clamp(0.0, 1.0));
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        // Halo
                        Container(
                          width: 96 + 18 * _halo.value,
                          height: 96 + 18 * _halo.value,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(colors: [
                              _gold.withValues(alpha: 0.35 * (1 - _halo.value)),
                              _gold.withValues(alpha: 0.0),
                            ]),
                          ),
                        ),
                        // Étincelles
                        ...List.generate(8, (i) {
                          final ang = (i / 8) * 2 * math.pi;
                          final d = 40 + 22 * pop;
                          return Transform.translate(
                            offset: Offset(
                                math.cos(ang) * d, math.sin(ang) * d),
                            child: Opacity(
                              opacity: (pop).clamp(0.0, 1.0) *
                                  (0.5 + 0.5 * _halo.value),
                              child: Icon(Icons.star_rounded,
                                  size: 12 + 4 * (i.isEven ? 1 : 0),
                                  color: _gold),
                            ),
                          );
                        }),
                        // Médaille
                        Transform.scale(
                          scale: 0.5 + 0.5 * pop,
                          child: Container(
                            width: 78,
                            height: 78,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFFFFD66B), _gold],
                              ),
                            ),
                            child: const Icon(Icons.workspace_premium_rounded,
                                color: Colors.white, size: 44),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
              Text(
                widget.trial
                    ? 'Essai Premium activé 🎉'
                    : 'Bienvenue en Premium 🎉',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 19,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.trial
                    ? 'Essai gratuit 7 jours · formule $tierLabel'
                    : 'Abonnement $tierLabel actif · commission réduite',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _gold,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Continuer',
                    style: TextStyle(
                        color: Colors.white70, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
