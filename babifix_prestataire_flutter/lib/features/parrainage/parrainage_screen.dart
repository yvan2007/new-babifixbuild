import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../shared/services/babifix_user_store.dart';

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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Code copié !'), backgroundColor: Color(0xFF1565C0)),
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
          : _error != null
              ? Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                    TextButton(onPressed: _load, child: const Text('Réessayer')),
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
                              const Icon(Icons.people_alt_rounded, color: Colors.white, size: 48),
                              const SizedBox(height: 12),
                              const Text('Invitez vos amis', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              Text(
                                'Vous gagnez $_creditParrain FCFA par filleul\nVotre filleul gagne $_creditFilleul FCFA',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white70, fontSize: 14),
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
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12)],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Votre code de parrainage', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.grey)),
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
                                        style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 4,
                                          color: Color(0xFF1565C0),
                                        ),
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
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: _code.isEmpty ? null : _shareCode,
                                  icon: const Icon(Icons.share_rounded),
                                  label: const Text('Partager mon code'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF2E7D32),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
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
                              color: const Color(0xFF1565C0),
                              cardBg: cardBg,
                            )),
                            const SizedBox(width: 12),
                            Expanded(child: _StatCard(
                              icon: Icons.account_balance_wallet_rounded,
                              value: '${_creditsEarned.toStringAsFixed(0)} F',
                              label: 'Crédits gagnés',
                              color: const Color(0xFF2E7D32),
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
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12)],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Comment ça marche ?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              const SizedBox(height: 16),
                              _StepItem(step: '1', text: 'Partagez votre code unique à un ami'),
                              _StepItem(step: '2', text: 'Votre ami s\'inscrit et utilise votre code'),
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
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12)],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
          decoration: const BoxDecoration(color: Color(0xFF1565C0), shape: BoxShape.circle),
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
