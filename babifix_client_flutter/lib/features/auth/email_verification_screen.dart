import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../user_store.dart';

/// Affiché après l'inscription pour inviter l'utilisateur à confirmer son email.
/// L'utilisateur peut renvoyer l'email de vérification ou continuer directement.
class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({
    super.key,
    required this.email,
    required this.onContinue,
  });

  final String email;
  final VoidCallback onContinue;

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  bool _sending = false;
  bool _sent = false;

  Future<void> _resendEmail() async {
    setState(() {
      _sending = true;
      _sent = false;
    });
    try {
      final token = await BabifixUserStore.getApiToken();
      await http.post(
        Uri.parse('${babifixApiBaseUrl()}/api/auth/resend-verification/'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty)
            'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'email': widget.email}),
      );
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _sending = false;
      _sent = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFF0A1628),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icône
              Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  color: BabifixDesign.cyan.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.mark_email_unread_rounded,
                  size: 56,
                  color: BabifixDesign.cyan,
                ),
              ),
              const SizedBox(height: 36),

              // Titre
              const Text(
                'Vérifiez votre email',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Corps
              Text(
                'Un email de confirmation a été envoyé à\n${widget.email}\n\n'
                'Cliquez sur le lien dans l\'email pour activer votre compte BABIFIX.',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // Feedback renvoi
              if (_sent)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: BabifixDesign.cyan.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Email renvoyé !',
                    style: TextStyle(
                      color: BabifixDesign.cyan,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

              const SizedBox(height: 36),

              // Bouton principal : continuer
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: BabifixDesign.ciOrange,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: widget.onContinue,
                  child: const Text(
                    'Continuer',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Bouton secondaire : renvoyer
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                        color: BabifixDesign.cyan.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _sending ? null : _resendEmail,
                  child: _sending
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: BabifixDesign.cyan,
                          ),
                        )
                      : Text(
                          'Renvoyer l\'email',
                          style: TextStyle(color: BabifixDesign.cyan),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
