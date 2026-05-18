/// Historique des appels (C8 / P10).
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../babifix_design_system.dart';
import '../../models/babifix_models.dart';
import '../../services/babifix_api.dart';
import '../../services/call_service.dart';
import '../../shared/widgets/animated_list_item.dart';

class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({super.key});

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  List<CallRecord> _calls = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _calls = await CallsApi.history();
      _error = null;
    } on BabifixApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes appels'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _calls.isEmpty
                  ? _empty()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        itemCount: _calls.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1),
                        itemBuilder: (_, i) => AnimatedListItem(
                          index: i,
                          child: _tile(_calls[i]),
                        ),
                      ),
                    ),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.call_outlined,
                  size: 60, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                "Aucun appel pour l'instant.",
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );

  Widget _tile(CallRecord c) {
    final isOutgoing = c.callerId.toString() ==
        c.callerId.toString(); // best-effort sans current user id
    final dur = c.durationSeconds;
    final durStr = dur > 0
        ? '${(dur ~/ 60).toString().padLeft(2, '0')}:${(dur % 60).toString().padLeft(2, '0')}'
        : '—';
    final color = _statusColor(c.status);
    final f = DateFormat('dd/MM HH:mm');
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.18),
        child: Icon(_statusIcon(c.status), color: color, size: 20),
      ),
      title: Text(
        isOutgoing ? c.calleeName : c.callerName,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        [
          c.isVideo ? 'Vidéo' : 'Audio',
          if (c.reservationReference != null &&
              c.reservationReference!.isNotEmpty)
            'Réf. ${c.reservationReference}',
          'Durée $durStr',
        ].join(' · '),
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Text(
        f.format(c.startedAt.toLocal()),
        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
      ),
      onTap: c.reservationReference == null || c.reservationReference!.isEmpty
          ? null
          : () => CallService.startOutgoing(
                context: context,
                reservationReference: c.reservationReference!,
                targetName:
                    isOutgoing ? c.calleeName : c.callerName,
                isVideo: c.isVideo,
              ),
    );
  }

  Color _statusColor(CallStatus s) => switch (s) {
        CallStatus.answered ||
        CallStatus.ended =>
          BabifixDesign.ciGreen,
        CallStatus.rejected ||
        CallStatus.cancelled ||
        CallStatus.missed =>
          BabifixDesign.error,
        CallStatus.ringing => BabifixDesign.ciBlue,
      };

  IconData _statusIcon(CallStatus s) => switch (s) {
        CallStatus.answered || CallStatus.ended => Icons.call_received,
        CallStatus.rejected || CallStatus.cancelled => Icons.call_end,
        CallStatus.missed => Icons.call_missed,
        CallStatus.ringing => Icons.call_made,
      };
}
