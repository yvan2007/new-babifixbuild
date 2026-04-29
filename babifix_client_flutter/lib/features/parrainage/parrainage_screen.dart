import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../user_store.dart';

class ClientParrainageScreen extends StatefulWidget {
  const ClientParrainageScreen({super.key});

  @override
  State<ClientParrainageScreen> createState() => _ClientParrainageScreenState();
}

class _ClientParrainageScreenState extends State<ClientParrainageScreen> {
  bool _loading = true;
  bool _applying = false;
  String? _error;
  String _code = '';
  int _filleuls = 0;
  double _creditsEarned = 0;
  int _creditParrain = 2000;
  int _creditFilleul = 1000;

  final _codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
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
      }
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      setState(() { _loading = false; });
    }
  }

  Future<void> _applyCode() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) return;
    setState(() { _applying = true; });
    try {
      final resp = await BabifixUserStore.authPost(
        '/api/auth/referral/',
        body: jsonEncode({'code': code}),
      );
      final data = jsonDecode(resp.body);
      if (resp.statusCode == 200 && data['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🎁 Code appliqué ! Votre bonus sera crédité à votre 1ère réservation.'), backgroundColor: Color(0xFF2E7D32)),
        );
        _codeController.clear();
        await _load();
      } else {
        final err = data['error'] ?? 'Erreur';
        final msg = {
          'invalid_code': 'Code invalide',
          'self_referral_not_allowed': 'Vous ne pouvez pas utiliser votre propre code',
          'code_already_used': 'Vous avez déjà utilisé un code de parrainage',
        }[err] ?? err;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() { _applying = false; });
    }
  }

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: _code));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Code copié !'), backgroundColor: Color(0xFF1565C0)),
    );
  }

  void _shareCode() {
    Share.share(
      '🏠 Rejoins BABIFIX et bénéficie de $_creditFilleul FCFA sur ta 1ère réservation !\n'
      'Utilise mon code : $_code\n'
      'Télécharge l\'app : https://babifix.ci/app',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0D1B2A) : const Color(0xFFF0F4FF);
    final cardBg = isDark ? const Color(0xFF1A2740) : Colors.white;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('Parrainage'),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.card_giftcard_rounded, color: Colors.white, size: 48),
                          const SizedBox(height: 12),
                          const Text('Invitez vos amis', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text(
                            'Vous gagnez $_creditParrain FCFA par ami invité\nVotre ami gagne $_creditFilleul FCFA',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Mon code
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12)],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Mon code à partager', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.grey)),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1565C0).withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFF1565C0).withOpacity(0.3)),
                                  ),
                                  child: Text(
                                    _code.isEmpty ? '—' : _code,
                                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 4, color: Color(0xFF1565C0)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              IconButton.filled(
                                onPressed: _code.isEmpty ? null : _copyCode,
                                icon: const Icon(Icons.copy_rounded),
                                style: IconButton.styleFrom(backgroundColor: const Color(0xFF1565C0), foregroundColor: Colors.white),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _code.isEmpty ? null : _shareCode,
                              icon: const Icon(Icons.share_rounded),
                              label: const Text('Partager'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF1565C0),
                                side: const BorderSide(color: Color(0xFF1565C0)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Appliquer un code reçu
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12)],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Utiliser un code ami', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.grey)),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _codeController,
                                  textCapitalization: TextCapitalization.characters,
                                  decoration: InputDecoration(
                                    hintText: 'Code de parrainage',
                                    filled: true,
                                    fillColor: isDark ? const Color(0xFF243050) : const Color(0xFFF5F7FF),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              FilledButton(
                                onPressed: _applying ? null : _applyCode,
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF2E7D32),
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: _applying
                                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                    : const Text('Appliquer'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Stats
                    Row(
                      children: [
                        Expanded(child: _MiniStat(icon: Icons.people_rounded, value: '$_filleuls', label: 'Amis invités', color: const Color(0xFF1565C0), cardBg: cardBg)),
                        const SizedBox(width: 12),
                        Expanded(child: _MiniStat(icon: Icons.savings_rounded, value: '${_creditsEarned.toStringAsFixed(0)} F', label: 'Crédits gagnés', color: const Color(0xFF2E7D32), cardBg: cardBg)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final Color cardBg;
  const _MiniStat({required this.icon, required this.value, required this.label, required this.color, required this.cardBg});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: cardBg,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12)],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    ),
  );
}
