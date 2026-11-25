import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../shared/widgets/babifix_button.dart';
import '../../shared/widgets/babifix_ring_loader.dart';
import '../../shared/widgets/babifix_snackbar.dart';

const _kNavyDeep = BabifixDesign.navy;
const _kCyan = BabifixDesign.cyanDeep;
const _kOrange = BabifixDesign.ciOrange;

/// Écran de confirmation OTP par Email pour l'application Prestataire (6 cases distinctes WCAG AAA).
class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({
    super.key,
    required this.email,
    required this.onContinue,
    this.onBack,
  });

  final String email;
  final VoidCallback onContinue;
  final VoidCallback? onBack;

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
          _errorMessage = data['message'] ?? 'Code invalide ou expiré.';
          _verifying = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Erreur réseau : vérifiez votre connexion.';
        _verifying = false;
      });
    }
  }

  Future<void> _resendOtp() async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _errorMessage = null;
    });

    try {
      final response = await http.post(
        Uri.parse('${babifixApiBaseUrl()}/api/auth/resend-email-otp/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': widget.email}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['ok'] == true) {
        setState(() {
          _sending = false;
          _sent = true;
        });
        if (mounted) {
          showBabifixToast(
            context,
            type: BabifixToastType.success,
            message: 'Un nouveau code vous a été envoyé par email.',
          );
        }
      } else {
        setState(() {
          _sending = false;
          _errorMessage = data['message'] ?? 'Impossible de renvoyer le code.';
        });
      }
    } catch (e) {
      setState(() {
        _sending = false;
        _errorMessage = 'Erreur réseau lors de la demande.';
      });
    }
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
                borderColor = _kCyan;
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
          if (widget.onBack != null) {
            widget.onBack!();
          } else {
            _triggerContinueOnce();
          }
        }
      },
      child: Scaffold(
        backgroundColor: _kNavyDeep,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            tooltip: 'Continuer',
            onPressed: widget.onBack ?? _triggerContinueOnce,
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: _kOrange.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _kOrange.withValues(alpha: 0.35),
                      width: 1.8,
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.mark_email_unread_rounded,
                      size: 38,
                      color: _kOrange,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'Vérification par Email',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Saisissez le code de sécurité à 6 chiffres envoyé à :',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontSize: 14,
                    height: 1.4,
                  ),
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
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF38BDF8),
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // 6 cases OTP distinctes à fort contraste
                _buildOtpBoxes(),

                if (_errorMessage != null) ...[
                  const SizedBox(height: 14),
                  Container(
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
                            size: 18, color: Color(0xFFF87171)),
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
                ],

                if (_verifiedSuccess) ...[
                  const SizedBox(height: 14),
                  Container(
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
                            size: 18, color: Color(0xFF34D399)),
                        SizedBox(width: 8),
                        Text(
                          'Compte validé avec succès !',
                          style: TextStyle(
                            color: Color(0xFF6EE7B7),
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Bouton valider (texte blanc pur WCAG AAA)
                BabifixButton(
                  label: 'Valider le code',
                  loadingLabel: 'Vérification...',
                  isLoading: _verifying,
                  onPressed: _verifying || _verifiedSuccess ? null : _verifyOtp,
                ),

                const SizedBox(height: 12),

                // Bouton renvoi de code
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
                    onPressed: _sending ? null : _resendOtp,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: BabifixRingLoader.mono(
                              size: 18,
                              color: _kCyan,
                            ),
                          )
                        : const Icon(
                            Icons.refresh_rounded,
                            size: 18,
                            color: Color(0xFF38BDF8),
                          ),
                    label: Text(
                      _sent
                          ? 'Code renvoyé · Renvoyer à nouveau'
                          : 'Renvoyer un nouveau code',
                      style: const TextStyle(
                        color: Color(0xFF38BDF8),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // Bouton passer vers le dossier prestataire
                TextButton.icon(
                  onPressed: _triggerContinueOnce,
                  icon: const Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    color: Color(0xFF94A3B8),
                  ),
                  label: const Text(
                    'Vérifier plus tard · Accéder à mon dossier',
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F1E36),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF1E3250)),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 18,
                        color: Color(0xFF94A3B8),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Le code est valable 15 minutes. Pensez à vérifier vos courriers indésirables (spams).',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
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
