import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../babifix_api_config.dart';
import '../../user_store.dart';
import '../../shared/services/websocket_push_service.dart';

class DevisDetailScreen extends StatefulWidget {
  final String reservationReference;
  final VoidCallback onBack;

  const DevisDetailScreen({
    super.key,
    required this.reservationReference,
    required this.onBack,
  });

  @override
  State<DevisDetailScreen> createState() => _DevisDetailScreenState();
}

class _DevisDetailScreenState extends State<DevisDetailScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _devis;
  bool _accepting = false;
  bool _refusing = false;

  @override
  void initState() {
    super.initState();
    _loadDevis();
    _initChatWebSocket();
  }

  Future<void> _loadDevis() async {
    final token = await BabifixUserStore.getApiToken();
    if (token == null) {
      setState(() {
        _loading = false;
        _error = 'Non connecté';
      });
      return;
    }

    try {
      final uri = Uri.parse(
        '${babifixApiBaseUrl()}/api/client/reservations/${widget.reservationReference}/devis',
      );
      final resp = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() {
          _devis = data['devis'];
          _loading = false;
        });
      } else {
        setState(() {
          _loading = false;
          _error = 'Erreur: ${resp.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _acceptDevis() async {
    if (_accepting) return;
    setState(() => _accepting = true);

    final token = await BabifixUserStore.getApiToken();
    if (token == null) return;

    try {
      final uri = Uri.parse(
        '${babifixApiBaseUrl()}/api/client/reservations/${widget.reservationReference}/devis/accept',
      );
      final resp = await http.post(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (resp.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Devis accepté!')));
          _loadDevis();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Erreur: ${resp.statusCode}')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    }

    if (mounted) setState(() => _accepting = false);
  }

  Future<void> _refuseDevis() async {
    if (_refusing) return;

    final motifController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Refuser le devis'),
        content: TextField(
          controller: motifController,
          decoration: const InputDecoration(
            labelText: 'Motif du refus',
            hintText: 'Pourquoi refusez-vous ce devis?',
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, motifController.text),
            child: const Text('Refuser'),
          ),
        ],
      ),
    );

    if (result == null || result.isEmpty) return;

    setState(() => _refusing = true);

    final token = await BabifixUserStore.getApiToken();
    if (token == null) return;

    try {
      final uri = Uri.parse(
        '${babifixApiBaseUrl()}/api/client/reservations/${widget.reservationReference}/devis/refuse',
      );
      final resp = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'motif': result}),
      );

      if (resp.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Devis refusé')));
          _loadDevis();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    }

    if (mounted) setState(() => _refusing = false);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: widget.onBack,
          ),
          title: const Text('Devis'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Détails'),
              Tab(icon: Icon(Icons.chat_bubble_outline), text: 'Chat'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(child: Text(_error!))
            : _devis == null
            ? const Center(child: Text('Aucun devis disponible'))
            : TabBarView(children: [_buildDevisContent(), _buildChatSection()]),
      ),
    );
  }

  Widget _buildDevisContent() {
    final devis = _devis!;
    final lignes = (devis['lignes'] as List?) ?? [];
    final statut = devis['statut'] as String? ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatutBanner(statut),
          const SizedBox(height: 16),
          _buildPrestataireInfo(devis),
          const SizedBox(height: 16),
          _buildDiagnostic(devis),
          const SizedBox(height: 16),
          _buildDateInfo(devis),
          const SizedBox(height: 16),
          _buildLignes(lignes),
          const SizedBox(height: 16),
          _buildTotal(devis),
          if (statut == 'ENVOYE') ...[
            const SizedBox(height: 24),
            _buildActionButtons(),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildStatutBanner(String statut) {
    Color bgColor;
    Color textColor;
    String label;

    switch (statut) {
      case 'ACCEPTE':
        bgColor = Colors.green.withValues(alpha: 0.2);
        textColor = Colors.green;
        label = 'Devis accepté';
        break;
      case 'REFUSE':
        bgColor = Colors.red.withValues(alpha: 0.2);
        textColor = Colors.red;
        label = 'Devis refusé';
        break;
      case 'ENVOYE':
        bgColor = Colors.blue.withValues(alpha: 0.2);
        textColor = Colors.blue;
        label = 'En attente de votre décision';
        break;
      default:
        bgColor = Colors.grey.withValues(alpha: 0.2);
        textColor = Colors.grey;
        label = statut;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildPrestataireInfo(Map<String, dynamic> devis) {
    final prestataire = (devis['prestataire'] as Map<String, dynamic>?) ?? {};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Prestataire',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(prestataire['nom'] ?? 'Inconnu'),
            Text(prestataire['specialite'] ?? ''),
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnostic(Map<String, dynamic> devis) {
    final diagnostic = devis['diagnostic'] as String? ?? '';
    if (diagnostic.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Diagnostic',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(diagnostic),
          ],
        ),
      ),
    );
  }

  Widget _buildDateInfo(Map<String, dynamic> devis) {
    final dateProposee = devis['date_proposee'] as String?;
    final heureDebut = devis['heure_debut'] as String?;
    final heureFin = devis['heure_fin'] as String?;

    if (dateProposee == null && heureDebut == null)
      return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Date proposée',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(dateProposee ?? 'Non définie'),
            if (heureDebut != null) Text('De $heureDebut à $heureFin'),
          ],
        ),
      ),
    );
  }

  Widget _buildLignes(List<dynamic> lignes) {
    if (lignes.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Détails du devis',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 8),
            ...lignes.map(
              (l) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${l['description']} (x${l['quantite']})',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    Text(
                      '${l['total'].toStringAsFixed(0)} francs CFA',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotal(Map<String, dynamic> devis) {
    final sousTotal = (devis['sous_total'] as num?) ?? 0;
    final commission = (devis['commission_montant'] as num?) ?? 0;
    final total = (devis['total_ttc'] as num?) ?? 0;
    final commissionRate = (devis['commission_rate'] as num?) ?? 0;

    return Card(
      color: const Color(0xFF0A1628),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Sous-total',
                  style: TextStyle(color: Colors.white70),
                ),
                Text(
                  '${sousTotal.toStringAsFixed(0)} francs CFA',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Commission ($commissionRate%)',
                  style: const TextStyle(color: Colors.white70),
                ),
                Text(
                  '${commission.toStringAsFixed(0)} francs CFA',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
            const Divider(color: Colors.white30),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                Text(
                  '${total.toStringAsFixed(0)} francs CFA',
                  style: const TextStyle(
                    color: Color(0xFF4CC9F0),
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _refusing ? null : _refuseDevis,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
            ),
            child: Text(_refusing ? '...' : 'Refuser'),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: FilledButton(
            onPressed: _accepting ? null : _acceptDevis,
            child: Text(_accepting ? '...' : 'Accepter le devis'),
          ),
        ),
      ],
    );
  }

  // Chat Section
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  StreamSubscription? _wsSubscription;
  String? _chatToken;

  Future<void> _initChatWebSocket() async {
    _chatToken = await BabifixUserStore.getApiToken();
    _loadMessages();
    _wsSubscription = WebSocketPushService.instance.chatStream.listen(
      _onNewMessage,
    );
    WebSocketPushService.instance.connect();
  }

  void _onNewMessage(Map<String, dynamic> data) {
    final ref = data['reference']?.toString() ?? '';
    if (ref == widget.reservationReference && mounted) {
      setState(() {
        _messages.insert(0, data);
      });
      _scrollToBottom();
    }
  }

  Future<void> _loadMessages() async {
    if (_chatToken == null) return;
    try {
      final uri = Uri.parse(
        '${babifixApiBaseUrl()}/api/messages/${widget.reservationReference}',
      );
      final resp = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $_chatToken'},
      );
      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(resp.body);
        setState(() {
          _messages = List<Map<String, dynamic>>.from(data['messages'] ?? []);
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('Chat load error: $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty || _chatToken == null) return;

    try {
      final uri = Uri.parse('${babifixApiBaseUrl()}/api/messages/send');
      final resp = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $_chatToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'reservation_reference': widget.reservationReference,
          'message': text,
        }),
      );
      if (resp.statusCode == 200 && mounted) {
        _chatController.clear();
        _loadMessages();
      }
    } catch (e) {
      debugPrint('Chat send error: $e');
    }
  }

  Widget _buildChatSection() {
    return Column(
      children: [
        Expanded(
          child: _messages.isEmpty
              ? const Center(
                  child: Text(
                    'Aucun message.\nCommencez la conversation !',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  controller: _chatScrollController,
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final msg = _messages[index];
                    final isMe = msg['sender_type'] == 'client';
                    return Align(
                      alignment: isMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isMe
                              ? Theme.of(context).primaryColor
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          msg['message'] ?? '',
                          style: TextStyle(
                            color: isMe ? Colors.white : Colors.black,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chatController,
                  decoration: const InputDecoration(
                    hintText: 'Envoyer un message...',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.send),
                color: Theme.of(context).primaryColor,
                onPressed: _sendMessage,
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _chatController.dispose();
    _chatScrollController.dispose();
    _wsSubscription?.cancel();
    super.dispose();
  }
}
