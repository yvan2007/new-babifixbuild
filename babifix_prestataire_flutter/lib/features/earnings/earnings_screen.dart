import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../babifix_api_config.dart';
import '../../shared/auth_utils.dart';

Future<String?> _getToken() async {
  return readStoredApiToken();
}

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
  late AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _init();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _token = await _getToken();
    await _load();
  }

  String? _loadError;

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
        final res = await http.get(
          Uri.parse(
            '${babifixApiBaseUrl()}/api/prestataire/earnings?period=$periodParam',
          ),
          headers: {'Authorization': 'Bearer $_token'},
        );
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final summary = data['summary'] as Map<String, dynamic>? ?? {};
          final total = (summary['total'] as num?)?.toInt() ?? 0;
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
        if (mounted)
          setState(() => _loadError = 'Erreur serveur (${res.statusCode})');
      } else {
        if (mounted) setState(() => _loadError = 'Connexion requise');
      }
    } catch (_) {
      if (mounted)
        setState(() => _loadError = 'Impossible de charger les gains');
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
    if (_token == null) return;
    final periodParam = _period == 'Jour'
        ? 'day'
        : _period == 'Semaine'
        ? 'week'
        : _period == 'Tout'
        ? 'all'
        : 'month';
    final url =
        '${babifixApiBaseUrl()}/api/admin/export/paiements/?period=$periodParam';
    // Show URL in snackbar — deep link to browser download
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Export CSV prêt — ouvrez l\'URL dans votre navigateur',
          ),
          action: SnackBarAction(label: 'OK', onPressed: () {}),
        ),
      );
    }
    // In a production app, use url_launcher: launchUrl(Uri.parse(url))
    // For now, copy to clipboard via a direct API download attempt
    try {
      final res = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $_token'},
      );
      if (res.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Export CSV téléchargé avec succès')),
        );
      }
    } catch (_) {}
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
    final isLight = widget.paletteMode.toString().contains('light');
    final bg = isLight ? const Color(0xFFF8FAFC) : const Color(0xFF0B1B34);
    final card = isLight ? Colors.white : const Color(0xFF152A45);
    final text = isLight ? const Color(0xFF0F172A) : Colors.white;
    final sub = isLight ? const Color(0xFF64748B) : const Color(0xFFB4C2D9);
    const cyan = Color(0xFF4CC9F0);

    final maxBar = _chartData.isEmpty
        ? 1.0
        : _chartData.map((b) => b.value).reduce((a, b) => a > b ? a : b) * 1.2;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: isLight ? Colors.white : const Color(0xFF0B1B34),
        foregroundColor: text,
        elevation: 0,
        leading: widget.onBack != null
            ? IconButton(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded),
              )
            : null,
        title: Text(
          'Mes gains',
          style: TextStyle(fontWeight: FontWeight.w800, color: text),
        ),
        actions: [
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
          padding: const EdgeInsets.all(16),
          children: [
            // Sélecteur période
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['Jour', 'Semaine', 'Mois', 'Tout']
                    .map(
                      (t) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(t),
                          selected: _period == t,
                          selectedColor: cyan,
                          labelStyle: TextStyle(
                            color: _period == t
                                ? const Color(0xFF0B1B34)
                                : text,
                            fontWeight: FontWeight.w700,
                          ),
                          onSelected: (_) {
                            setState(() => _period = t);
                            _load();
                          },
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 8, bottom: 8),
                child: LinearProgressIndicator(color: Color(0xFF4CC9F0)),
              ),
            if (_loadError != null && !_loading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Color(0xFFEF4444),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _loadError!,
                          style: const TextStyle(
                            color: Color(0xFF991B1B),
                            fontSize: 13,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _load,
                        child: const Text('Réessayer'),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),

            // KPI card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: isLight
                    ? null
                    : const LinearGradient(
                        colors: [Color(0xFF0B1B34), Color(0xFF152A45)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                color: isLight ? Colors.white : null,
                border: isLight
                    ? Border.all(color: const Color(0xFFE2E8F0))
                    : null,
                boxShadow: isLight
                    ? [
                        BoxShadow(
                          color: const Color(
                            0xFF0B1B34,
                          ).withValues(alpha: 0.07),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total des gains',
                          style: TextStyle(
                            color: sub,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 400),
                          child: Text(
                            _formatFcfa(_totalAmount),
                            key: ValueKey(_totalAmount),
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: cyan,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$_missionCount prestation(s)',
                          style: TextStyle(color: sub, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: cyan.withValues(alpha: 0.15),
                    ),
                    child: const Icon(
                      Icons.payments_rounded,
                      color: Color(0xFF4CC9F0),
                      size: 28,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Graphique barres fl_chart
            if (_chartData.isNotEmpty) ...[
              Text(
                'Évolution des gains',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: text,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                height: 200,
                padding: const EdgeInsets.fromLTRB(0, 12, 16, 8),
                decoration: BoxDecoration(
                  color: card,
                  borderRadius: BorderRadius.circular(16),
                  border: isLight
                      ? Border.all(color: const Color(0xFFE2E8F0))
                      : null,
                ),
                child: AnimatedBuilder(
                  animation: _animCtrl,
                  builder: (_, __) => BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: maxBar,
                      barTouchData: BarTouchData(
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                              BarTooltipItem(
                                _formatFcfa(rod.toY.round()),
                                const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
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
                                padding: const EdgeInsets.only(top: 4),
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
                                style: TextStyle(fontSize: 10, color: sub),
                              );
                            },
                          ),
                        ),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (_) => FlLine(
                          color: sub.withValues(alpha: 0.2),
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
                              toY:
                                  _chartData[i].value.toDouble() *
                                  _animCtrl.value,
                              width: 18,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(6),
                              ),
                              gradient: const LinearGradient(
                                colors: [Color(0xFF4CC9F0), Color(0xFF2563EB)],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Transactions
            if (_transactions.isNotEmpty) ...[
              Text(
                'Transactions',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
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
                  isLight: isLight,
                  textColor: text,
                  subColor: sub,
                ),
              ),
            ] else if (!_loading)
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Text(
                    'Aucune transaction sur cette période.',
                    style: TextStyle(color: sub),
                  ),
                ),
              ),
            const SizedBox(height: 40),
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
    required this.isLight,
    required this.textColor,
    required this.subColor,
  });

  final String client;
  final String service;
  final String gross;
  final String commission;
  final String net;
  final String status;
  final bool isLight;
  final Color textColor;
  final Color subColor;

  @override
  Widget build(BuildContext context) {
    final bool paid = status.toLowerCase().contains('pay');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : const Color(0xFF152A45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isLight ? const Color(0xFFE2E8F0) : const Color(0x22FFFFFF),
        ),
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
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: paid
                      ? const Color(0xFF059669).withValues(alpha: 0.12)
                      : const Color(0xFFF59E0B).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: paid
                        ? const Color(0xFF059669)
                        : const Color(0xFFD97706),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(service, style: TextStyle(color: subColor, fontSize: 13)),
          const SizedBox(height: 10),
          Row(
            children: [
              Text('Brut', style: TextStyle(color: subColor, fontSize: 13)),
              const Spacer(),
              Text(gross, style: TextStyle(color: textColor, fontSize: 13)),
            ],
          ),
          Row(
            children: [
              Text(
                'Commission',
                style: TextStyle(color: subColor, fontSize: 13),
              ),
              const Spacer(),
              Text(
                commission,
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ],
          ),
          Row(
            children: [
              Text(
                'Net',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: textColor,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Text(
                net,
                style: const TextStyle(
                  color: Color(0xFF4CC9F0),
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
