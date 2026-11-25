import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../user_store.dart';
import '../../shared/widgets/babifix_button.dart';
import '../../shared/widgets/babifix_ring_loader.dart';

/// Écran de confirmation OTP par Email (6 cases distinctes haute lisibilité WCAG AAA).
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
  final _codeCtrl = TextEditingController();
  final _focusNode = FocusNode();
  bool _verifying = false;
  bool _sending = false;
  bool _sent = false;
  String? _errorMessage;
  bool _verifiedSuccess = false;
  bool _didFinish = false;

  void _triggerContinueOnce() {
    if (_didFinish) return;
    _didFinish = true;
    widget.onContinue();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _verifyOtp() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      setState(() {
        _errorMessage = 'Veuillez saisir les 6 chiffres du code reçu par email.';
      });
      return;
    }

    setState(() {
      _verifying = true;
      _errorMessage = null;
    });

    try {
      final response = await http.post(
        Uri.parse('${babifixApiBaseUrl()}/api/auth/verify-email-otp/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': widget.email,
          'otp': code,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['ok'] == true) {
        setState(() {
          _verifiedSuccess = true;
          _verifying = false;
        });
        await Future.delayed(const Duration(milliseconds: 650));
        if (mounted) _triggerContinueOnce();
      } else {
        setState(() {
          _errorMessage = data['message'] ??
              'Code invalide ou expiré. Vérifiez votre boîte mail.';
          _verifying = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Erreur réseau. Vérifiez votre connexion internet.';
        _verifying = false;
      });
    }
  }

  Future<void> _resendEmail() async {
    setState(() {
      _sending = true;
      _sent = false;
      _errorMessage = null;
    });
    try {
      final token = await BabifixUserStore.getApiToken();
      await http.post(
        Uri.parse('${babifixApiBaseUrl()}/api/auth/resend-email-otp/'),
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

  Widget _buildOtpBoxes() {
    final code = _codeCtrl.text;
    return GestureDetector(
      onTap: () => _focusNode.requestFocus(),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(6, (index) {
              final hasChar = index < code.length;
              final char = hasChar ? code[index] : '';
              final isFocused = _focusNode.hasFocus &&
                  (index == code.length || (code.length == 6 && index == 5));

              Color borderColor = const Color(0xFF233858);
              if (_verifiedSuccess) {
                borderColor = const Color(0xFF10B981);
              } else if (_errorMessage != null) {
                borderColor = const Color(0xFFEF4444);
              } else if (isFocused) {
                borderColor = const Color(0xFF38BDF8);
              } else if (hasChar) {
                borderColor = const Color(0xFF0284C7);
              }

              return AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 48,
                height: 60,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F1E36),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: borderColor,
                    width: (isFocused || _verifiedSuccess) ? 2.0 : 1.4,
                  ),
                  boxShadow: isFocused
                      ? [
                          BoxShadow(
                            color: const Color(0xFF38BDF8).withValues(alpha: 0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: hasChar
                    ? Text(
                        char,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      )
                    : Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isFocused
                              ? const Color(0xFF38BDF8)
                              : const Color(0xFF334155),
                          shape: BoxShape.circle,
                        ),
                      ),
              );
            }),
          ),
          // Champ de saisie invisible qui capte le clavier et le presse-papiers
          Opacity(
            opacity: 0.0,
            child: SizedBox(
              height: 60,
              width: double.infinity,
              child: TextField(
                controller: _codeCtrl,
                focusNode: _focusNode,
                keyboardType: TextInputType.number,
                maxLength: 6,
                autofocus: true,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  filled: false,
                  counterText: '',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                onChanged: (val) {
                  setState(() {
                    if (_errorMessage != null) _errorMessage = null;
                  });
                  if (val.length == 6) {
                    _verifyOtp();
                  }
                },
                onSubmitted: (_) => _verifyOtp(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _triggerContinueOnce();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A1628),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            tooltip: 'Continuer',
            onPressed: _triggerContinueOnce,
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: BabifixDesign.ciOrange.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: BabifixDesign.ciOrange.withValues(alpha: 0.35),
                      width: 1.8,
                    ),
                  ),
                  child: const Icon(
                    Icons.mark_email_unread_rounded,
                    size: 40,
                    color: BabifixDesign.ciOrange,
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'Vérification par Email',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Saisissez le code de sécurité à 6 chiffres envoyé à :',
                  style: TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontSize: 14,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F1E36),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF1E3250)),
                  ),
                  child: Text(
                    widget.email,
                    style: const TextStyle(
                      color: Color(0xFF38BDF8),
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 28),

                // 6 cases OTP distinctes à fort contraste
                _buildOtpBoxes(),

                const SizedBox(height: 14),

                if (_errorMessage != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            color: Color(0xFFF87171), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Color(0xFFFCA5A5),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                if (_verifiedSuccess)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF10B981).withValues(alpha: 0.4),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_rounded,
                            color: Color(0xFF34D399), size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Email vérifié avec succès !',
                          style: TextStyle(
                            color: Color(0xFF6EE7B7),
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),

                if (_sent)
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.35),
                      ),
                    ),
                    child: const Text(
                      'Un nouveau code vient d\'être envoyé dans votre boîte mail.',
                      style: TextStyle(
                        color: Color(0xFF7DD3FC),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                const SizedBox(height: 16),

                // Bouton principal : Valider le code (texte blanc pur WCAG AAA)
                BabifixButton(
                  label: 'Valider le code',
                  isLoading: _verifying,
                  width: double.infinity,
                  height: 52,
                  onPressed: _verifying || _verifiedSuccess ? null : _verifyOtp,
                ),
                const SizedBox(height: 12),

                // Bouton secondaire : renvoyer un code
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF38BDF8),
                      side: const BorderSide(
                        color: Color(0xFF1E3250),
                        width: 1.4,
                      ),
                      backgroundColor: const Color(0xFF0F1E36),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _sending ? null : _resendEmail,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: BabifixRingLoader.cyan(size: 18),
                          )
                        : const Icon(
                            Icons.refresh_rounded,
                            size: 18,
                            color: Color(0xFF38BDF8),
                          ),
                    label: const Text(
                      'Renvoyer un nouveau code',
                      style: TextStyle(
                        color: Color(0xFF38BDF8),
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Option passer (continuer vers l'application)
                TextButton.icon(
                  onPressed: _triggerContinueOnce,
                  icon: const Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    color: Color(0xFF94A3B8),
                  ),
                  label: const Text(
                    'Vérifier plus tard · Accéder à mon espace',
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
