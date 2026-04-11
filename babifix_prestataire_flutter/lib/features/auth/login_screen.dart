import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../babifix_api_config.dart';
import '../../shared/auth_utils.dart';
import 'forgot_password_screen.dart';

/// Connexion API — enregistre le JWT localement (aucun compte démo imposé).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onBack, required this.onSuccess});

  final VoidCallback onBack;
  final VoidCallback onSuccess;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      final res = await http.post(
        Uri.parse('${babifixApiBaseUrl()}/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': _user.text.trim(), 'password': _pass.text}),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final tok = (data['token'] ?? data['access']) as String?;
        final refresh = data['refresh'] as String?;
        if (tok != null && tok.isNotEmpty) {
          await writeStoredApiToken(tok);
          if (refresh != null) await writeStoredRefreshToken(refresh);
          babifixRegisterFcm(tok);
          if (mounted) widget.onSuccess();
          return;
        }
      }
      if (mounted) {
        final String msg;
        if (res.statusCode == 400 || res.statusCode == 401) {
          msg = 'Identifiants incorrects. Vérifiez votre nom d\'utilisateur et mot de passe.';
        } else if (res.statusCode == 403) {
          msg = 'Compte suspendu ou non autorisé. Contactez l\'administrateur.';
        } else {
          msg = 'Connexion impossible (erreur ${res.statusCode}). Réessayez.';
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible de contacter le serveur.')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: widget.onBack, icon: const Icon(Icons.arrow_back)),
        title: const Text('Connexion'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Utilisez un compte Django avec le rôle prestataire (créé par l\'administrateur ou via l\'inscription).',
            style: TextStyle(color: Color(0xFF64748B), height: 1.4),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _user,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Nom d\'utilisateur'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pass,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Mot de passe'),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _loading ? null : _submit,
            child: _loading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Se connecter'),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.center,
            child: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
              ),
              child: const Text('Mot de passe oublié ?'),
            ),
          ),
        ],
      ),
    );
  }
}
