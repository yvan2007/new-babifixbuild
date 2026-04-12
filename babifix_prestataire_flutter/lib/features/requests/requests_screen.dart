import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../babifix_api_config.dart';
import '../../shared/auth_utils.dart';
import '../../shared/widgets/payment_method_logo.dart';
import 'rate_client_screen.dart';

class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  bool loading = false;
  String? authToken;
  late List<_RequestItem> items;

  @override
  void initState() {
    super.initState();
    items = <_RequestItem>[];
    _initSession();
  }

  /// Align\u00e9 UML / API : pending, active (Confirm\u00e9e/En cours), completed (Termin\u00e9e), refused.
  static String _bucketFromApi(String raw) {
    final t = raw.trim();
    if (t == 'Annulee' || t.toLowerCase().contains('annul')) return 'refused';
    if (t == 'En attente' || t.toLowerCase().contains('attente')) return 'pending';
    if (t == 'Terminee' || t.toLowerCase().contains('termin')) return 'completed';
    return 'active';
  }

  static String _labelStatut(String apiStatus) {
    switch (apiStatus) {
      case 'Confirmee':
        return 'Confirm\u00e9e';
      case 'Terminee':
        return 'Termin\u00e9e';
      case 'Annulee':
        return 'Annul\u00e9e';
      case 'En cours':
        return 'En cours';
      default:
        return apiStatus;
    }
  }

  bool _canConfirmCash(_RequestItem it) {
    return it.paymentType == 'ESPECES' &&
        it.cashFlowStatus == 'pending_prestataire' &&
        (it.apiStatus == 'Terminee');
  }

  @override
  Widget build(BuildContext context) {
    final pending = items.where((e) => e.status == 'pending').toList();
    final active = items.where((e) => e.status == 'active').toList();
    final completed = items.where((e) => e.status == 'completed').toList();
    final refused = items.where((e) => e.status == 'refused').toList();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: widget.onBack, icon: const Icon(Icons.arrow_back)),
        title: const Text('Exigences'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (loading) const LinearProgressIndicator(),
          Text('Nouvelles demandes (${pending.length})', style: const TextStyle(fontWeight: FontWeight.w800)),
          if (pending.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.swipe_rounded, size: 14, color: Color(0xFF94A3B8)),
                const SizedBox(width: 4),
                Text(
                  'Glissez \u2192 pour accepter  \u2022  \u2190 pour refuser',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          ...pending.map((item) => _buildCard(item)),
          const SizedBox(height: 8),
          const Text('Confirm\u00e9es / en cours', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          ...active.map((item) => _buildCard(item)),
          if (completed.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Termin\u00e9es (${completed.length})', style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            ...completed.map((item) => _buildCard(item)),
          ],
          if (refused.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Annul\u00e9es (${refused.length})', style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            ...refused.map((item) => _buildCard(item)),
          ],
        ],
      ),
    );
  }

  Widget _buildCard(_RequestItem it) {
    final card = _buildCardInner(it);
    if (it.status != 'pending') return card;
    return Dismissible(
      key: ValueKey(it.reference),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        final decision = direction == DismissDirection.startToEnd ? 'accept' : 'refuse';
        await _decide(it, decision);
        return false; // list updates via setState in _decide
      },
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: const Color(0xFF22C55E),
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.centerLeft,
        child: const Row(
          children: [
            Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 28),
            SizedBox(width: 8),
            Text('Accepter', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
          ],
        ),
      ),
      secondaryBackground: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444),
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.centerRight,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('Refuser', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
            SizedBox(width: 8),
            Icon(Icons.cancel_outlined, color: Colors.white, size: 28),
          ],
        ),
      ),
      child: card,
    );
  }

  Widget _buildCardInner(_RequestItem it) {
    final tagText = _labelStatut(it.apiStatus);
    final hasClientMsg = it.clientMessage.isNotEmpty;
    final hasPhotos    = it.clientPhotos.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── En-tête client + tag ──────────────────────────────────────
          Row(
            children: [
              Expanded(child: Text(it.client, style: const TextStyle(fontWeight: FontWeight.w700))),
              _Tag(text: tagText),
            ],
          ),
          const SizedBox(height: 4),
          Text(it.service, style: const TextStyle(color: Color(0xFF4B5563))),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.schedule_rounded, size: 14, color: Color(0xFF94A3B8)),
              const SizedBox(width: 4),
              Text('${it.date}  ${it.hour}', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.location_on_outlined, size: 14, color: Color(0xFF94A3B8)),
              const SizedBox(width: 4),
              Expanded(child: Text(it.address, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)))),
            ],
          ),

          // ── Message du client ─────────────────────────────────────────
          if (hasClientMsg) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.chat_bubble_outline_rounded, size: 13, color: Color(0xFF2563EB)),
                    SizedBox(width: 5),
                    Text('Message du client', style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF2563EB),
                    )),
                  ]),
                  const SizedBox(height: 5),
                  Text(it.clientMessage, style: const TextStyle(fontSize: 13, color: Color(0xFF374151), height: 1.5)),
                ],
              ),
            ),
          ],

          // ── Photos du client ──────────────────────────────────────────
          if (hasPhotos) ...[
            const SizedBox(height: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.photo_library_outlined, size: 13, color: Color(0xFF64748B)),
                  const SizedBox(width: 5),
                  Text(
                    'Photos du problème (${it.clientPhotos.length})',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                  ),
                ]),
                const SizedBox(height: 6),
                SizedBox(
                  height: 80,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: it.clientPhotos.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (ctx, i) => ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _SafeImage(src: it.clientPhotos[i], size: 80),
                    ),
                  ),
                ),
              ],
            ),
          ],

          // ── Description (si pas de message client dédié) ──────────────
          if (!hasClientMsg && it.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(it.description, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
          ],

          // ── Paiement ──────────────────────────────────────────────────
          if (it.paymentType.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (it.paymentType == 'MOBILE_MONEY' && it.mobileMoneyOperator.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: BabifixPaymentMethodLogo(methodId: it.mobileMoneyOperator, height: 22),
                    ),
                  Expanded(
                    child: Text(
                      'Paiement : ${_paymentLabel(it.paymentType, it.mobileMoneyOperator)}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.star, size: 15, color: Color(0xFFF59E0B)),
              Text(' ${it.rating}', style: const TextStyle(fontSize: 12)),
              const Spacer(),
              Text(it.amount, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0284C7))),
            ],
          ),

          // ── Actions ───────────────────────────────────────────────────
          if (it.status == 'pending') ...[
            const SizedBox(height: 10),
            // Bouton proposer un devis (prioritaire)
            if (it.bookingId != null) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _showDevisDialog(it),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.request_quote_rounded, size: 18),
                  label: const Text('Proposer un devis', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 6),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _decide(it, 'refuse'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                      side: const BorderSide(color: Color(0xFFFCA5A5)),
                    ),
                    child: const Text('Refuser'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _decide(it, 'accept'),
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF22C55E)),
                    child: const Text('Accepter'),
                  ),
                ),
              ],
            ),
          ],
          if (it.status == 'active') ...[
            const SizedBox(height: 8),
            if (it.apiStatus == 'Confirmee')
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _postReservationStatus(it, 'En cours'),
                  icon: const Icon(Icons.play_arrow, size: 20),
                  label: const Text('D\u00e9marrer la prestation'),
                ),
              ),
            if (it.apiStatus == 'En cours')
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _postReservationStatus(it, 'Terminee'),
                  icon: const Icon(Icons.check_circle_outline, size: 20),
                  label: const Text('Terminer la prestation'),
                ),
              ),
          ],
          if (it.status == 'completed' && _canConfirmCash(it)) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: () => _confirmCashPayment(it),
                child: const Text('Confirmer r\u00e9ception des esp\u00e8ces'),
              ),
            ),
          ],
          if (it.status == 'completed') ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => RateClientScreen(
                    reservationRef: it.reference,
                    clientName: it.client,
                  ),
                ),
              ),
              icon: const Icon(Icons.star_border_rounded, size: 18),
              label: const Text('\u00c9valuer le client'),
            ),
          ],
        ],
      ),
    );
  }

  // ── Dialogue de devis ─────────────────────────────────────────────────────
  void _showDevisDialog(_RequestItem it) {
    final priceCtrl   = TextEditingController();
    final messageCtrl = TextEditingController();
    bool sending = false;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Proposer un devis', style: TextStyle(fontWeight: FontWeight.w800)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Réservation : ${it.service}',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Le client a déjà payé 1 500 FCFA de frais de visite.\nEntrez le prix total de la prestation.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.45),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: priceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Prix total (FCFA)',
                    hintText: 'Ex. : 25 000',
                    prefixIcon: const Icon(Icons.payments_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: messageCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Explication (optionnel)',
                    hintText: 'Décrivez pourquoi ce prix...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: sending ? null : () => Navigator.pop(ctx),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: sending
                  ? null
                  : () async {
                      final price = int.tryParse(priceCtrl.text.replaceAll(RegExp(r'\D'), ''));
                      if (price == null || price < 2000) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Le montant minimum d\'un devis est 2 000 FCFA.')),
                        );
                        return;
                      }
                      setS(() => sending = true);
                      try {
                        final res = await http.post(
                          Uri.parse('${babifixApiBaseUrl()}/api/bookings/${it.bookingId}/devis/'),
                          headers: {
                            'Content-Type': 'application/json',
                            'Authorization': 'Bearer $authToken',
                          },
                          body: jsonEncode({
                            'price_fcfa': price,
                            'devis_message': messageCtrl.text.trim(),
                          }),
                        );
                        if (!mounted) return;
                        Navigator.pop(ctx);
                        if (res.statusCode == 200 || res.statusCode == 201) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Devis envoyé ! Le client sera notifié.'),
                              backgroundColor: Color(0xFF2563EB),
                            ),
                          );
                          await _loadRequests();
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Erreur ${res.statusCode}')),
                          );
                        }
                      } catch (_) {
                        if (mounted) Navigator.pop(ctx);
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Impossible de contacter le serveur.')),
                        );
                      } finally {
                        setS(() => sending = false);
                      }
                    },
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
              child: sending
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Envoyer le devis'),
            ),
          ],
        ),
      ),
    );
  }

  String _paymentLabel(String code, [String mobileOp = '']) {
    switch (code) {
      case 'ESPECES':
        return 'Esp\u00e8ces';
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

  Future<void> _initSession() async {
    authToken = await readStoredApiToken();
    babifixRegisterFcm(authToken);
    await _loadRequests();
  }

  Future<void> _loadRequests() async {
    if (authToken == null) return;
    setState(() => loading = true);
    try {
      final res = await http.get(
        Uri.parse('${babifixApiBaseUrl()}/api/prestataire/requests'),
        headers: {'Authorization': 'Bearer $authToken'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final remote = (data['items'] as List<dynamic>? ?? []).map((e) {
          final raw = '${e['status']}';
          final bucket = _RequestsScreenState._bucketFromApi(raw);
          final pay = '${e['payment_type'] ?? ''}';
          final mmOp = '${e['mobile_money_operator'] ?? ''}';
          final cash = '${e['cash_flow_status'] ?? ''}';
          final photos = (e['client_photos'] as List<dynamic>? ?? [])
              .map((p) => '$p'.trim())
              .where((p) => p.isNotEmpty)
              .toList();
          return _RequestItem(
            reference: '${e['reference'] ?? e['id'] ?? ''}',
            client: '${e['client']}',
            service: '${e['service']}',
            date: '${e['date']}',
            hour: '${e['hour']}',
            amount: '${e['amount']}',
            address: '${e['address']}',
            description: '${e['description']}',
            rating: (e['rating'] as num?)?.toDouble() ?? 0,
            status: bucket,
            apiStatus: raw,
            paymentType: pay,
            mobileMoneyOperator: mmOp,
            cashFlowStatus: cash,
            clientMessage: '${e['client_message'] ?? ''}',
            clientPhotos: photos,
            bookingId: (e['id'] as num?)?.toInt(),
          );
        }).toList();
        setState(() => items = remote);
      }
    } catch (_) {
      if (mounted) setState(() => items = []);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _applyStatusFromApi(_RequestItem item, String newApiStatus) {
    item.apiStatus = newApiStatus;
    item.status = _RequestsScreenState._bucketFromApi(newApiStatus);
  }

  Future<void> _decide(_RequestItem item, String decision) async {
    if (authToken == null) return;
    try {
      final res = await http.post(
        Uri.parse('${babifixApiBaseUrl()}/api/prestataire/requests/${item.reference}/decision'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({'decision': decision}),
      );
      if (res.statusCode == 200 && mounted) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final st = '${body['status'] ?? (decision == 'accept' ? 'Confirmee' : 'Annulee')}';
        setState(() => _applyStatusFromApi(item, st));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Action impossible hors connexion API')),
        );
      }
    }
  }

  Future<void> _postReservationStatus(_RequestItem item, String newStatus) async {
    if (authToken == null) return;
    try {
      final res = await http.post(
        Uri.parse('${babifixApiBaseUrl()}/api/prestataire/requests/${item.reference}/status'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({'status': newStatus}),
      );
      if (res.statusCode == 200 && mounted) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final st = '${body['status'] ?? newStatus}';
        setState(() => _applyStatusFromApi(item, st));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Statut : ${_RequestsScreenState._labelStatut(st)}')),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur ${res.statusCode}')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible de mettre \u00e0 jour le statut')),
        );
      }
    }
  }

  Future<void> _confirmCashPayment(_RequestItem item) async {
    if (authToken == null) return;
    try {
      final res = await http.post(
        Uri.parse('${babifixApiBaseUrl()}/api/prestataire/requests/${item.reference}/cash-confirm'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
      );
      if (res.statusCode == 200 && mounted) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final cfs = '${body['cash_flow_status'] ?? 'pending_admin'}';
        setState(() => item.cashFlowStatus = cfs);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Esp\u00e8ces confirm\u00e9es \u2014 en attente validation admin')),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur ${res.statusCode}')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Confirmation impossible')),
        );
      }
    }
  }
}

class _RequestItem {
  _RequestItem({
    required this.reference,
    required this.client,
    required this.service,
    required this.date,
    required this.hour,
    required this.amount,
    required this.address,
    required this.description,
    required this.rating,
    required this.status,
    this.apiStatus = 'En attente',
    this.paymentType = '',
    this.mobileMoneyOperator = '',
    this.cashFlowStatus = '',
    this.clientMessage = '',
    this.clientPhotos = const [],
    this.bookingId,
  });

  final String reference;
  final String client;
  final String service;
  final String date;
  final String hour;
  final String amount;
  final String address;
  final String description;
  final double rating;
  /// pending | active | completed | refused
  String status;
  /// Statut brut API (En attente, Confirmee, En cours, Terminee, Annulee)
  String apiStatus;
  String paymentType;
  String mobileMoneyOperator;
  String cashFlowStatus;
  /// Message du client décrivant le problème
  final String clientMessage;
  /// Photos envoyées par le client (base64 data URI ou URL HTTP)
  final List<String> clientPhotos;
  /// ID numérique pour les endpoints devis
  final int? bookingId;
}

// ── Widget d'image sécurisé : gère base64, HTTP et fichier local ──────────────
class _SafeImage extends StatelessWidget {
  const _SafeImage({required this.src, this.size = 80});
  final String src;
  final double size;

  static Widget _placeholder(double sz) => Container(
    width: sz, height: sz,
    decoration: BoxDecoration(
      color: const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Icon(Icons.photo_outlined, color: Color(0xFFCBD5E1), size: 28),
  );

  @override
  Widget build(BuildContext context) {
    if (src.isEmpty) return _placeholder(size);

    // Cas 1 : data URI base64
    if (src.startsWith('data:image/')) {
      try {
        final bytes = base64Decode(src.split(',').last);
        return Image.memory(
          bytes,
          width: size, height: size, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(size),
        );
      } catch (_) {
        return _placeholder(size);
      }
    }

    // Cas 2 : URL réseau
    if (src.startsWith('http://') || src.startsWith('https://')) {
      return Image.network(
        src,
        width: size, height: size, fit: BoxFit.cover,
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : Container(
                width: size, height: size,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
        errorBuilder: (_, __, ___) => _placeholder(size),
      );
    }

    // Cas 3 : chemin fichier local
    try {
      final file = File(src);
      if (file.existsSync()) {
        return Image.file(
          file,
          width: size, height: size, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(size),
        );
      }
    } catch (_) {}

    return _placeholder(size);
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = text.toLowerCase();
    late Color bg;
    late Color fg;
    if (t.contains('attente')) {
      bg = const Color(0xFFFEF3C7);
      fg = const Color(0xFF92400E);
    } else if (t.contains('annul')) {
      bg = const Color(0xFFFEE2E2);
      fg = const Color(0xFF991B1B);
    } else if (t.contains('termin')) {
      bg = const Color(0xFFDCFCE7);
      fg = const Color(0xFF166534);
    } else if (t.contains('cours')) {
      bg = const Color(0xFFE0E7FF);
      fg = const Color(0xFF3730A3);
    } else if (t.contains('confirm')) {
      bg = const Color(0xFFDBEAFE);
      fg = const Color(0xFF1D4ED8);
    } else {
      bg = const Color(0xFFF3F4F6);
      fg = const Color(0xFF374151);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w600)),
    );
  }
}
