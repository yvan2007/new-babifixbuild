import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../shared/widgets/babifix_button.dart';
import '../../shared/widgets/babifix_snackbar.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final String? apiBase;
  final String? initialEmail;

  const ForgotPasswordScreen({
    super.key,
    this.apiBase,
    this.initialEmail,
  });

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final TextEditingController _emailCtrl;
  final _tokenCtrl = TextEditingController();
  final _tokenFocus = FocusNode();
  final _pwCtrl = TextEditingController();
  final _pw2Ctrl = TextEditingController();

  bool _loading = false;
  bool _resending = false;
  int _step = 1; // 1: Email, 2: Code 6 cases + Nouveau mdp, 3: Succès
  bool _obscurePw = true;
  bool _obscurePw2 = true;
  String? _error;

  String get _base => widget.apiBase ?? babifixApiBaseUrl();

  static const _navyDeep = Color(0xFF060E1C);
  static const _surfaceNavy = Color(0xFF0A1628);
  static const _borderNavy = Color(0xFF1E3250);
  static const _cyan = Color(0xFF0284C7);
  static const _cyanBright = Color(0xFF38BDF8);
  static const _orange = Color(0xFFEA580C);
  static const _successGreen = Color(0xFF10B981);

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController(text: widget.initialEmail ?? '');
    _tokenFocus.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _tokenCtrl.dispose();
    _tokenFocus.dispose();
    _pwCtrl.dispose();
    _pw2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _sendEmail({bool isResend = false}) async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Veuillez saisir une adresse email valide.');
      return;
    }
    setState(() {
      if (isResend) {
        _resending = true;
      } else {
        _loading = true;
      }
      _error = null;
    });
    try {
      final res = await http.post(
        Uri.parse('$_base/api/auth/forgot-password/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() {
          _step = 2;
          _loading = false;
          _resending = false;
        });
        showBabifixToast(
          context,
          type: BabifixToastType.success,
          message: isResend
              ? 'Un nouveau code a été envoyé à $email.'
              : 'Code de sécurité à 6 chiffres envoyé par email.',
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _tokenFocus.requestFocus();
        });
      } else {
        setState(() {
          _loading = false;
          _resending = false;
          _error = 'Adresse email introuvable ou erreur serveur.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _resending = false;
          _error = 'Erreur réseau. Vérifiez votre connexion.';
        });
      }
    }
  }

  Future<void> _resetPassword() async {
    final token = _tokenCtrl.text.trim();
    final pw = _pwCtrl.text.trim();
    final pw2 = _pw2Ctrl.text.trim();

    if (token.length != 6) {
      setState(() => _error = 'Veuillez saisir les 6 chiffres du code reçu par email.');
      return;
    }
    if (pw.isEmpty || pw2.isEmpty) {
      setState(() => _error = 'Veuillez renseigner et confirmer le nouveau mot de passe.');
      return;
    }
    if (pw != pw2) {
      setState(() => _error = 'Les deux mots de passe ne correspondent pas.');
      return;
    }
    if (pw.length < 6) {
      setState(() => _error = 'Le mot de passe doit comporter au moins 6 caractères.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await http.post(
        Uri.parse('$_base/api/auth/reset-password/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'token': token, 'new_password': pw}),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() {
          _step = 3;
          _loading = false;
        });
      } else {
        String msg = 'Code invalide ou expiré.';
        try {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final err = data['error'] ?? '';
          if (err == 'token_expired') {
            msg = 'Le code a expiré (validité 30 min). Demandez un nouveau code.';
          } else if (err == 'invalid_token') {
            msg = 'Code incorrect. Vérifiez les 6 chiffres reçus par email.';
          }
        } catch (_) {}
        setState(() {
          _loading = false;
          _error = msg;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Erreur réseau. Vérifiez votre connexion.';
        });
      }
    }
  }

  Widget _buildOtpBoxes() {
    final code = _tokenCtrl.text;
    return GestureDetector(
      onTap: () => _tokenFocus.requestFocus(),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(6, (index) {
              final hasChar = index < code.length;
              final char = hasChar ? code[index] : '';
              final isFocused = _tokenFocus.hasFocus &&
                  (index == code.length || (code.length == 6 && index == 5));

              Color borderColor = const Color(0xFF233858);
              if (_error != null && code.length == 6) {
                borderColor = const Color(0xFFEF4444);
              } else if (isFocused) {
                borderColor = _cyanBright;
              } else if (hasChar) {
                borderColor = _cyan;
              }

              return AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 44,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F1E36),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: borderColor,
                    width: isFocused ? 2.0 : 1.4,
                  ),
                ),
                child: hasChar
                    ? Text(
                        char,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      )
                    : Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: isFocused
                              ? _cyanBright
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
              height: 54,
              width: double.infinity,
              child: TextField(
                controller: _tokenCtrl,
                focusNode: _tokenFocus,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  filled: false,
                  counterText: '',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                onChanged: (_) {
                  setState(() {
                    if (_error != null) _error = null;
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navyDeep,
      appBar: AppBar(
        backgroundColor: _navyDeep,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () {
            if (_step == 2) {
              setState(() {
                _step = 1;
                _error = null;
              });
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
        title: const Text(
          'Mot de passe oublié',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_step == 1) _buildStep1Email(),
              if (_step == 2) _buildStep2Reset(),
              if (_step == 3) _buildStep3Done(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep1Email() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _surfaceNavy,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _borderNavy),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _orange.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.lock_reset_rounded, color: _orange, size: 26),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Réinitialisation du compte',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Espace Client · BABIFIX',
                      style: TextStyle(color: _cyanBright, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'Saisissez l\'adresse email associée à votre compte BABIFIX. Vous recevrez un code à 6 chiffres pour choisir un nouveau mot de passe.',
            style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 14, height: 1.45),
          ),
          const SizedBox(height: 24),
          _buildField(
            controller: _emailCtrl,
            label: 'Votre adresse email',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (!_loading) _sendEmail();
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _buildErrorBox(_error!),
          ],
          const SizedBox(height: 24),
          BabifixButton(
            label: 'Recevoir le code à 6 chiffres',
            isLoading: _loading,
            width: double.infinity,
            height: 52,
            backgroundColor: BabifixDesign.cyan,
            foregroundColor: BabifixDesign.navy,
            onPressed: _loading ? null : () => _sendEmail(),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2Reset() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _surfaceNavy,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _borderNavy),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _cyanBright.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.mark_email_read_outlined, color: _cyanBright, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Code de sécurité (6 chiffres)',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _emailCtrl.text.trim(),
                      style: const TextStyle(color: _cyanBright, fontSize: 13, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'Saisissez les 6 chiffres reçus par email :',
            style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          _buildOtpBoxes(),
          const SizedBox(height: 22),
          const Text(
            'Choisissez votre nouveau mot de passe :',
            style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          _buildField(
            controller: _pwCtrl,
            label: 'Nouveau mot de passe (min. 6 caractères)',
            icon: Icons.lock_outline_rounded,
            obscure: _obscurePw,
            onToggleObscure: () => setState(() => _obscurePw = !_obscurePw),
          ),
          const SizedBox(height: 14),
          _buildField(
            controller: _pw2Ctrl,
            label: 'Confirmer le nouveau mot de passe',
            icon: Icons.lock_outline_rounded,
            obscure: _obscurePw2,
            onToggleObscure: () => setState(() => _obscurePw2 = !_obscurePw2),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (!_loading) _resetPassword();
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            _buildErrorBox(_error!),
          ],
          const SizedBox(height: 24),
          BabifixButton(
            label: 'Enregistrer le nouveau mot de passe',
            isLoading: _loading,
            width: double.infinity,
            height: 52,
            onPressed: _loading ? null : _resetPassword,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed: _resending ? null : () => _sendEmail(isResend: true),
                icon: const Icon(Icons.refresh_rounded, size: 16, color: _cyanBright),
                label: Text(
                  _resending ? 'Renvoi...' : 'Renvoyer le code',
                  style: const TextStyle(color: _cyanBright, fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _step = 1;
                  _error = null;
                }),
                child: const Text(
                  'Changer d\'email',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStep3Done() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      decoration: BoxDecoration(
        color: _surfaceNavy,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _borderNavy),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: _successGreen.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded, color: _successGreen, size: 40),
          ),
          const SizedBox(height: 24),
          const Text(
            'Mot de passe réinitialisé !',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            'Votre mot de passe a été mis à jour. Vous pouvez maintenant vous connecter en toute sécurité.',
            style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 14, height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          BabifixButton(
            label: 'Retour à la connexion',
            width: double.infinity,
            height: 52,
            backgroundColor: BabifixDesign.cyan,
            foregroundColor: BabifixDesign.navy,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    VoidCallback? onToggleObscure,
    TextInputType keyboardType = TextInputType.text,
    TextInputAction textInputAction = TextInputAction.next,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFF0F1E36),
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13.5),
        floatingLabelStyle: const TextStyle(color: _cyanBright, fontSize: 12, fontWeight: FontWeight.w600),
        prefixIcon: Icon(icon, color: _cyanBright, size: 20),
        suffixIcon: onToggleObscure != null
            ? IconButton(
                icon: Icon(
                  obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: const Color(0xFF94A3B8),
                  size: 20,
                ),
                onPressed: onToggleObscure,
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF243B5A)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF243B5A)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _cyanBright, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      ),
    );
  }

  Widget _buildErrorBox(String msg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0x25EF4444),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x60EF4444)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              msg,
              style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
