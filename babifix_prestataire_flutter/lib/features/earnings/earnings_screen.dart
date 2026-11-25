import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../shared/auth_utils.dart';
import '../../shared/services/haptics_service.dart';
import '../../shared/widgets/babifix_page_route.dart';
import '../../shared/widgets/babifix_skeleton.dart';
import '../../shared/widgets/babifix_snackbar.dart';
import 'payment_history_screen.dart';

class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key, required this.paletteMode, this.onBack});

  final dynamic paletteMode;
  final VoidCallback? onBack;

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen>
    with SingleTickerProviderStateMixin {
  String _period = 'Mois';
  bool _loading = false;
  String? _token;
  int _totalAmount = 0;
  int _missionCount = 0;
  List<Map<String, String>> _transactions = [];
  List<_BarData> _chartData = [];
  late final AnimationController _animCtrl;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _init();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _token = await readStoredApiToken();
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    _animCtrl.reset();
    try {
      final periodParam = _period == 'Jour'
          ? 'day'
          : _period == 'Semaine'
              ? 'week'
              : _period == 'Tout'
                  ? 'all'
                  : 'month';
      if (_token != null) {
        final res = await babifixAuthGet(
          '${babifixApiBaseUrl()}/api/prestataire/earnings?period=$periodParam',
        );
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final summary = data['summary'] as Map<String, dynamic>? ?? {};
          final total = (summary['net'] as num?)?.toInt() ?? 0;
          final count = (summary['count'] as num?)?.toInt() ?? 0;
          final txns = _parseTransactions(data['transactions']);
          final chart = _parseChart(data['chart'] as List? ?? []);
          if (mounted) {
            setState(() {
              _totalAmount = total;
              _missionCount = count;
              _transactions = txns;
              _chartData = chart;
              _loading = false;
            });
            _animCtrl.forward();
          }
          return;
        }
        if (mounted) setState(() => _loadError = 'Erreur serveur (${res.statusCode})');
      } else {
        if (mounted) setState(() => _loadError = 'Connexion requise');
      }
    } catch (_) {
      if (mounted) setState(() => _loadError = 'Impossible de charger les gains');
    }
    if (mounted) {
      setState(() {
        _totalAmount = 0;
        _missionCount = 0;
        _transactions = [];
        _chartData = [];
        _loading = false;
      });
    }
  }

  List<Map<String, String>> _parseTransactions(dynamic raw) {
    if (raw is! List) return [];
    return raw
        .map(
          (e) => {
            'client': '${e['client']}',
            'service': '${e['service']}',
            'gross': '${e['gross']}',
            'commission': '${e['commission']}',
            'net': '${e['net']}',
            'status': '${e['status']}',
          },
        )
        .toList();
  }

  List<_BarData> _parseChart(List raw) {
    if (raw.isEmpty) return [];
    return raw
        .map(
          (e) => _BarData(
            label: e['label'] as String? ?? '',
            value: (e['value'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList();
  }

  Future<void> _exportCsv() async {
    final buf = StringBuffer()
      ..writeln('Periode;Total Net FCFA;Missions')
      ..writeln('$_period;$_totalAmount;$_missionCount')
      ..writeln()
      ..writeln('Date;Client;Service;Montant');
    for (final tx in _transactions) {
      final date = (tx['date'] ?? '').replaceAll(';', ',');
      final client = (tx['client'] ?? '').replaceAll(';', ',');
      final service = (tx['service'] ?? '').replaceAll(';', ',');
      final amount = (tx['amount'] ?? '').replaceAll(';', ',');
      buf.writeln('$date;$client;$service;$amount');
    }
    final csv = buf.toString();
    await Clipboard.setData(ClipboardData(text: csv));
    try {
      await Share.share(csv, subject: 'Releve Revenus BABIFIX ($_period)');
    } catch (_) {
      if (mounted) {
        showBabifixToast(
          context,
          type: BabifixToastType.success,
          message: 'Releve CSV copie dans le presse-papiers.',
        );
      }
    }
  }

  String _formatFcfa(int v) {
    if (v >= 1000000) {
      return '${(v / 1000000).toStringAsFixed(1)} M FCFA';
    }
    if (v >= 1000) {
      final k = v ~/ 1000;
      final r = v % 1000;
      return r == 0 ? '$k 000 FCFA' : '$v FCFA';
    }
    return '$v FCFA';
  }

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final surface = BabifixDesign.surfaceOf(context);
    final border = BabifixDesign.borderOf(context);
    final text = BabifixDesign.textPrimaryOf(context);
    final sub = BabifixDesign.textMutedOf(context);
    final isDark = BabifixDesign.isDark(context);
    final accent = isDark ? BabifixDesign.cyan : BabifixDesign.ciOrange;

    final maxBar = _chartData.isEmpty
        ? 1.0
        : _chartData.map((b) => b.value).reduce((a, b) => a > b ? a : b) * 1.2;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: widget.onBack != null
            ? IconButton(
                onPressed: widget.onBack,
                icon: Icon(Icons.arrow_back_ios_new_rounded, color: text, size: 20),
              )
            : null,
        title: Text(
          'Mes gains',
          style: TextStyle(fontWeight: FontWeight.w800, color: text),
        ),
        actions: [
          IconButton(
            tooltip: 'Historique des paiements',
            onPressed: () => Navigator.of(context).push(
              babifixRoute(
                (_) => PaymentHistoryScreen(paletteMode: widget.paletteMode),
              ),
            ),
            icon: Icon(Icons.history_rounded, color: text),
          ),
          IconButton(
            tooltip: 'Exporter CSV',
            onPressed: _loading ? null : _exportCsv,
            icon: Icon(Icons.download_rounded, color: text),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            // Barre de periode segmentee
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: border),
              ),
              child: Row(
                children: ['Jour', 'Semaine', 'Mois', 'Tout'].map((t) {
                  final sel = _period == t;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                        HapticsService.selection();
                        setState(() => _period = t);
                        _load();
                      },
                      child: AnimatedContainer(
                        duration: BabifixDesign.durationFast,
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        decoration: BoxDecoration(
                          color: sel ? accent : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          t,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                            color: sel
                                ? (isDark ? BabifixDesign.navy : Colors.white)
                                : sub,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 14),
            if (_loading)
              BabifixSkeletonScope(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const BabifixSkeletonBox(height: 108, borderRadius: 20),
                    const SizedBox(height: 16),
                    const BabifixSkeletonBox(height: 196, borderRadius: 18),
                    const SizedBox(height: 16),
                    ...List.generate(3, (_) => const BabifixSkeletonCard(lines: 2)),
                  ],
                ),
              )
            else ...[
              if (_loadError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: BabifixDesign.error.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: BabifixDesign.error.withValues(alpha: 0.30),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: BabifixDesign.error,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _loadError!,
                            style: TextStyle(color: text, fontSize: 13),
                          ),
                        ),
                        TextButton(onPressed: _load, child: const Text('Reessayer')),
                      ],
                    ),
                  ),
                ),

              // Carte KPI principale
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TOTAL DES GAINS NETS',
                            style: TextStyle(
                              color: sub,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.9,
                            ),
                          ),
                          const SizedBox(height: 6),
                          AnimatedSwitcher(
                            duration: BabifixDesign.durationStandard,
                            child: Text(
                              _formatFcfa(_totalAmount),
                              key: ValueKey(_totalAmount),
                              style: BabifixDesign.amountStyle(
                                color: accent,
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$_missionCount prestation${_missionCount > 1 ? 's' : ''}',
                            style: TextStyle(
                              color: sub,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: accent.withValues(alpha: 0.14),
                      ),
                      child: Icon(Icons.payments_rounded, color: accent, size: 28),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              if (_chartData.isEmpty && _loadError == null)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: border),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accent.withValues(alpha: 0.12),
                        ),
                        child: Icon(Icons.bar_chart_rounded, size: 30, color: accent),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Aucune donnee sur cette periode',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: text,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Vos gains apparaitront ici apres vos premieres missions.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: sub),
                      ),
                    ],
                  ),
                ),

              if (_chartData.isNotEmpty) ...[
                Text(
                  'Evolution des gains',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15.5,
                    color: text,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  height: 204,
                  padding: const EdgeInsets.fromLTRB(4, 16, 16, 10),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: border),
                  ),
                  child: AnimatedBuilder(
                    animation: _animCtrl,
                    builder: (_, __) => BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: maxBar,
                        barTouchData: BarTouchData(
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipColor: (_) => BabifixDesign.navy,
                            getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                                BarTooltipItem(
                              _formatFcfa(rod.toY.round()),
                              const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                fontFeatures: BabifixDesign.tabularFigures,
                              ),
                            ),
                          ),
                        ),
                        titlesData: FlTitlesData(
                          show: true,
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (v, _) {
                                final i = v.toInt();
                                if (i < 0 || i >= _chartData.length) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    _chartData[i].label,
                                    style: TextStyle(fontSize: 11, color: sub),
                                  ),
                                );
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 44,
                              getTitlesWidget: (v, _) {
                                if (v == 0) return const SizedBox.shrink();
                                return Text(
                                  v >= 1000
                                      ? '${(v / 1000).round()}K'
                                      : v.round().toString(),
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: sub,
                                    fontFeatures: BabifixDesign.tabularFigures,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          getDrawingHorizontalLine: (_) => FlLine(
                            color: sub.withValues(alpha: 0.16),
                            strokeWidth: 1,
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        barGroups: List.generate(
                          _chartData.length,
                          (i) => BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: _chartData[i].value.toDouble() * _animCtrl.value,
                                width: 18,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(6),
                                ),
                                color: accent,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
              ],

              if (_transactions.isNotEmpty) ...[
                Text(
                  'Detail des transactions',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15.5,
                    color: text,
                  ),
                ),
                const SizedBox(height: 10),
                ..._transactions.map(
                  (t) => _TxnCard(
                    client: t['client'] ?? '',
                    service: t['service'] ?? '',
                    gross: t['gross'] ?? '',
                    commission: t['commission'] ?? '',
                    net: t['net'] ?? '',
                    status: t['status'] ?? '',
                    textColor: text,
                    subColor: sub,
                    accent: accent,
                  ),
                ),
              ] else ...[
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      'Aucune transaction sur cette periode.',
                      style: TextStyle(color: sub),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _BarData {
  const _BarData({required this.label, required this.value});
  final String label;
  final int value;
}

class _TxnCard extends StatelessWidget {
  const _TxnCard({
    required this.client,
    required this.service,
    required this.gross,
    required this.commission,
    required this.net,
    required this.status,
    required this.textColor,
    required this.subColor,
    required this.accent,
  });

  final String client;
  final String service;
  final String gross;
  final String commission;
  final String net;
  final String status;
  final Color textColor;
  final Color subColor;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final bool paid = status.toLowerCase().contains('pay');
    final surface = BabifixDesign.surfaceOf(context);
    final border = BabifixDesign.borderOf(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  client,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                    color: textColor,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (paid ? BabifixDesign.success : BabifixDesign.warning)
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: paid ? BabifixDesign.success : BabifixDesign.warning,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(service, style: TextStyle(color: subColor, fontSize: 13)),
          const SizedBox(height: 10),
          Divider(height: 1, color: border),
          const SizedBox(height: 8),
          _BreakdownRow(label: 'Brut', value: gross, labelColor: subColor, valueColor: textColor),
          const SizedBox(height: 3),
          _BreakdownRow(
            label: 'Commission',
            value: commission,
            labelColor: subColor,
            valueColor: BabifixDesign.error,
          ),
          const SizedBox(height: 3),
          _BreakdownRow(
            label: 'Net percu',
            value: net,
            labelColor: textColor,
            valueColor: accent,
            bold: true,
          ),
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.label,
    required this.value,
    required this.labelColor,
    required this.valueColor,
    this.bold = false,
  });

  final String label;
  final String value;
  final Color labelColor;
  final Color valueColor;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            color: labelColor,
            fontSize: 12.5,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            fontSize: 13,
            fontFeatures: BabifixDesign.tabularFigures,
          ),
        ),
      ],
    );
  }
}
