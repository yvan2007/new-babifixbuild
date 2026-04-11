import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';

/// Flux complet reset mot de passe en 2 étapes :
///  1. Saisir l'email → POST /api/auth/forgot-password
///  2. Saisir le token reçu par email + nouveau mot de passe → POST /api/auth/reset-password
class ForgotPasswordScreen extends StatefulWidget {
  final String? apiBase;

  const ForgotPasswordScreen({super.key, this.apiBase});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  final _pw2Ctrl = TextEditingController();

  bool _loading = false;
  bool _emailSent = false;
  bool _done = false;
  String? _error;

  String get _base => widget.apiBase ?? babifixApiBaseUrl();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _tokenCtrl.dispose();
    _pwCtrl.dispose();
    _pw2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _sendEmail() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Veuillez saisir votre email.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await http.post(
        Uri.parse('$_base/api/auth/forgot-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );
      setState(() {
        _emailSent = true;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _loading = false;
        _error = 'Erreur réseau. Vérifiez votre connexion.';
      });
    }
  }

  Future<void> _resetPassword() async {
    final token = _tokenCtrl.text.trim();
    final pw = _pwCtrl.text.trim();
    final pw2 = _pw2Ctrl.text.trim();
    if (token.isEmpty || pw.isEmpty) {
      setState(() => _error = 'Token et nouveau mot de passe requis.');
      return;
    }
    if (pw != pw2) {
      setState(() => _error = 'Les mots de passe ne correspondent pas.');
      return;
    }
    if (pw.length < 6) {
      setState(() => _error = 'Le mot de passe doit contenir au moins 6 caractères.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http.post(
        Uri.parse('$_base/api/auth/reset-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'token': token, 'new_password': pw}),
      );
      if (res.statusCode == 200) {
        setState(() {
          _done = true;
          _loading = false;
        });
      } else {
        final errMsg = jsonDecode(res.body)['error'] ?? 'Erreur';
        setState(() {
          _loading = false;
          _error = errMsg == 'invalid_token'
              ? 'Code invalide.'
              : errMsg == 'token_expired'
                  ? 'Code expiré. Recommencez.'
                  : errMsg;
        });
      }
    } catch (_) {
      setState(() {
        _loading = false;
        _error = 'Erreur réseau.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Mot de passe oublié'),
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: _done
            ? _doneView()
            : _emailSent
                ? _resetView(cs)
                : _emailView(cs),
      ),
    );
  }

  Widget _doneView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 40),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: BabifixDesign.success.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded,
                color: BabifixDesign.success, size: 40),
          ),
          const SizedBox(height: 20),
          const Text('Mot de passe réinitialisé !',
              style:
                  TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          const Text('Vous pouvez maintenant vous connecter avec votre nouveau mot de passe.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: () =>
                Navigator.popUntil(context, (r) => r.isFirst),
            style: FilledButton.styleFrom(
                backgroundColor: BabifixDesign.ciOrange),
            child: const Text('Se connecter'),
          ),
        ],
      ),
    );
  }

  Widget _emailView(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Icon(Icons.lock_reset_rounded,
            size: 48, color: BabifixDesign.ciOrange),
        const SizedBox(height: 16),
        const Text('Réinitialiser le mot de passe',
            style:
                TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text(
          'Saisissez l\'email de votre compte. Vous recevrez un code de réinitialisation.',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 28),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: 'Email',
            prefixIcon: const Icon(Icons.email_outlined),
            border: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(BabifixDesign.radiusMD)),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!,
              style: const TextStyle(
                  color: BabifixDesign.error, fontSize: 13)),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: _loading ? null : _sendEmail,
            style: FilledButton.styleFrom(
              backgroundColor: BabifixDesign.ciOrange,
              shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(BabifixDesign.radiusMD)),
            ),
            child: _loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Envoyer le code',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  Widget _resetView(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: BabifixDesign.ciGreen.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(BabifixDesign.radiusMD),
            border:
                Border.all(color: BabifixDesign.ciGreen.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.mail_rounded,
                  color: BabifixDesign.ciGreen),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Un code a été envoyé à ${_emailCtrl.text.trim()}. Vérifiez votre boîte mail.',
                  style: const TextStyle(
                      color: BabifixDesign.ciGreen, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text('Code reçu par email',
            style:
                TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 8),
        TextField(
          controller: _tokenCtrl,
          decoration: InputDecoration(
            labelText: 'Code de réinitialisation',
            prefixIcon: const Icon(Icons.vpn_key_rounded),
            border: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(BabifixDesign.radiusMD)),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _pwCtrl,
          obscureText: true,
          decoration: InputDecoration(
            labelText: 'Nouveau mot de passe',
            prefixIcon: const Icon(Icons.lock_outlined),
            border: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(BabifixDesign.radiusMD)),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pw2Ctrl,
          obscureText: true,
          decoration: InputDecoration(
            labelText: 'Confirmer le mot de passe',
            prefixIcon: const Icon(Icons.lock_outlined),
            border: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(BabifixDesign.radiusMD)),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!,
              style: const TextStyle(
                  color: BabifixDesign.error, fontSize: 13)),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: _loading ? null : _resetPassword,
            style: FilledButton.styleFrom(
              backgroundColor: BabifixDesign.ciOrange,
              shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(BabifixDesign.radiusMD)),
            ),
            child: _loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Réinitialiser',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: () => setState(() => _emailSent = false),
            child: const Text('Utiliser un autre email'),
          ),
        ),
      ],
    );
  }
}
