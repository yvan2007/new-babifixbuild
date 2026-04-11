import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../babifix_api_config.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  bool _sent = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) return;
    setState(() => _loading = true);
    try {
      final res = await http.post(
        Uri.parse('${babifixApiBaseUrl()}/api/auth/forgot-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() => _sent = true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email introuvable ou erreur serveur')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible de contacter le serveur')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mot de passe oublié')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _sent ? _buildSuccess() : _buildForm(),
      ),
    );
  }

  Widget _buildSuccess() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.mark_email_read_outlined, size: 64, color: Color(0xFF10B981)),
        const SizedBox(height: 20),
        const Text(
          'Email envoyé !',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          'Un lien de réinitialisation a été envoyé à ${_emailCtrl.text.trim()}.\nVérifiez votre boîte mail (et les spams).',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF64748B), height: 1.5),
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Retour à la connexion'),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        const Text(
          'Entrez votre adresse email de compte prestataire pour recevoir un lien de réinitialisation.',
          style: TextStyle(color: Color(0xFF64748B), height: 1.5),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            if (!_loading) _submit();
          },
          decoration: const InputDecoration(
            labelText: 'Adresse email',
            prefixIcon: Icon(Icons.email_outlined),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Envoyer le lien'),
        ),
      ],
    );
  }
}
