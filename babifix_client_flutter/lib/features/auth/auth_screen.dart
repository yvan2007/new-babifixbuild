import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../user_store.dart';
import 'biometric_login_screen.dart';
import 'email_verification_screen.dart';
import 'post_signup_onboarding.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.onAuthSuccess});

  final VoidCallback onAuthSuccess;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with TickerProviderStateMixin {
  late TabController _tab;
  late final AnimationController _anim;
  late final Animation<double> _fadeIn;

  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  final pass2Ctrl = TextEditingController();
  final nameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  String _regPhoneE164 = '';
  String _regCountry = 'CI';
  bool hidden = true;
  bool hidden2 = true;
  bool _loading = false;

  bool _showBiometricLogin = false;
  bool _isLoading = true;

  static const _blue = Color(0xFF2563EB);
  static const _blueDeep = Color(0xFF1D4ED8);
  static const _navy = Color(0xFF0B1B34);
  static const _cyan = Color(0xFF4CC9F0);

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeIn = CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic);
    _anim.forward();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() {
      if (mounted) setState(() {});
    });
    _checkBiometricLogin();
  }

  Future<void> _checkBiometricLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final biometricEnabled = prefs.getBool('biometric_enabled') ?? false;
    final isLoggedIn = await BabifixUserStore.isLoggedIn();
    if (biometricEnabled && isLoggedIn) {
      final isAvailable = await BiometricHelper.isBiometricAvailable();
      if (isAvailable && mounted) {
        setState(() {
          _showBiometricLogin = true;
          _isLoading = false;
        });
        return;
      }
    }
    if (mounted)
      setState(() {
        _showBiometricLogin = false;
        _isLoading = false;
      });
  }

  @override
  void dispose() {
    _tab.dispose();
    _anim.dispose();
    emailCtrl.dispose();
    passCtrl.dispose();
    pass2Ctrl.dispose();
    nameCtrl.dispose();
    phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _doLogin() async {
    if (_loading) return;
    setState(() => _loading = true);
    final err = await BabifixUserStore.login(
      emailCtrl.text.trim(),
      passCtrl.text,
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (err != null) {
      _snack(err);
      return;
    }
    widget.onAuthSuccess();
  }

  Future<void> _doRegister() async {
    if (_loading) return;
    if (passCtrl.text != pass2Ctrl.text) {
      _snack('Les mots de passe ne correspondent pas.');
      return;
    }
    setState(() => _loading = true);
    final err = await BabifixUserStore.register(
      email: emailCtrl.text.trim(),
      password: passCtrl.text,
      name: nameCtrl.text.trim(),
      phone: _regPhoneE164.isNotEmpty ? _regPhoneE164 : phoneCtrl.text.trim(),
      countryCode: _regCountry,
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (err != null) {
      _snack(err);
      return;
    }
    final email = emailCtrl.text.trim();
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => EmailVerificationScreen(
          email: email,
          onContinue: () {
            Navigator.of(context).pop();
            showPostSignupOnboardingIfNeeded(
              context,
              onDone: widget.onAuthSuccess,
            );
          },
        ),
      ),
    );
  }

  Future<void> _googleAuth() async {
    final err = await BabifixUserStore.tryGoogleAuth();
    if (!mounted) return;
    if (err != null) {
      _snack(err);
      return;
    }
    widget.onAuthSuccess();
  }

  Future<void> _appleAuth() async {
    final err = await BabifixUserStore.tryAppleAuth();
    if (!mounted) return;
    if (err != null) {
      _snack(err);
      return;
    }
    widget.onAuthSuccess();
  }

  void _showForgotPasswordDialog() {
    final forgotEmailCtrl = TextEditingController(text: emailCtrl.text);
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF0B1B34).withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Réinitialiser le mot de passe',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Entrez votre email pour recevoir un lien de réinitialisation.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _PremiumField(
                    controller: forgotEmailCtrl,
                    label: 'Adresse email',
                    icon: Icons.email_outlined,
                    inputType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white54,
                        ),
                        child: const Text('Annuler'),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () async {
                          final email = forgotEmailCtrl.text.trim();
                          if (email.isEmpty) return;
                          Navigator.of(ctx).pop();
                          try {
                            final res = await http.post(
                              Uri.parse(
                                '${babifixApiBaseUrl()}/api/auth/forgot-password',
                              ),
                              headers: {'Content-Type': 'application/json'},
                              body: jsonEncode({'email': email}),
                            );
                            if (!mounted) return;
                            if (res.statusCode == 200) {
                              _snack('Email de réinitialisation envoyé ✓');
                            } else {
                              _snack(
                                'Adresse email introuvable ou erreur serveur.',
                              );
                            }
                          } catch (_) {
                            if (mounted)
                              _snack('Impossible de contacter le serveur.');
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [_blue, _blueDeep],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Envoyer',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ).then((_) => forgotEmailCtrl.dispose());
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: _navy,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF060E1C),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF4CC9F0)),
        ),
      );
    }
    if (_showBiometricLogin) {
      return BiometricLoginScreen(
        onSuccess: widget.onAuthSuccess,
        onUsePassword: () => setState(() => _showBiometricLogin = false),
      );
    }

    return Theme(
      data: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF2563EB),
          secondary: Color(0xFF4CC9F0),
          surface: Color(0xFF0A1628),
        ),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: Color(0xFF4CC9F0),
          selectionColor: Color(0x554CC9F0),
          selectionHandleColor: Color(0xFF4CC9F0),
        ),
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF060E1C),
        body: Stack(
          children: [
            // ── Fond premium ───────────────────────────────────────────────
            Positioned.fill(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFF050D1A),
                      Color(0xFF0A1628),
                      Color(0xFF060E1C),
                    ],
                    stops: [0.0, 0.4, 1.0],
                  ),
                ),
              ),
            ),
            // Orbe orange en haut
            Positioned(
              top: -120,
              left: -80,
              child: Container(
                width: 340,
                height: 340,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [_blue.withValues(alpha: 0.22), Colors.transparent],
                  ),
                ),
              ),
            ),
            // Orbe cyan en bas
            Positioned(
              bottom: -100,
              right: -60,
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [_cyan.withValues(alpha: 0.14), Colors.transparent],
                  ),
                ),
              ),
            ),

            // ── Contenu ────────────────────────────────────────────────────
            SafeArea(
              child: FadeTransition(
                opacity: _fadeIn,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                  children: [
                    // ── Logo hero ─────────────────────────────────────────
                    Center(
                      child: Column(
                        children: [
                          Container(
                            width: 88,
                            height: 88,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [_blue, _blueDeep],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: _blue.withValues(alpha: 0.5),
                                  blurRadius: 32,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Text(
                                'B',
                                style: TextStyle(
                                  fontSize: 40,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  height: 1,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'BABIFIX',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Services à domicile · Côte d\'Ivoire',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.45),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // ── Card principale glassmorphisme ─────────────────────
                    ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.055),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.10),
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            children: [
                              // Onglets personnalisés
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  16,
                                  16,
                                  0,
                                ),
                                child: Container(
                                  height: 46,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: TabBar(
                                    controller: _tab,
                                    dividerColor: Colors.transparent,
                                    indicator: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [_blue, _blueDeep],
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          color: _blue.withValues(alpha: 0.4),
                                          blurRadius: 12,
                                        ),
                                      ],
                                    ),
                                    labelColor: Colors.white,
                                    unselectedLabelColor: Colors.white
                                        .withValues(alpha: 0.4),
                                    labelStyle: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                    tabs: const [
                                      Tab(text: 'Connexion'),
                                      Tab(text: 'Inscription'),
                                    ],
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  20,
                                  20,
                                  24,
                                ),
                                child: AnimatedBuilder(
                                  animation: _tab,
                                  builder: (_, __) => _tab.index == 0
                                      ? _buildLoginForm()
                                      : _buildRegisterForm(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── Séparateur ─────────────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: Divider(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'ou continuer avec',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.35),
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Divider(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // ── Boutons sociaux ────────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: _SocialButton(
                            label: 'Google',
                            iconAsset:
                                'assets/illustrations/icons/brand_google.svg',
                            onPressed: _googleAuth,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SocialButton(
                            label: 'Apple',
                            iconAsset:
                                'assets/illustrations/icons/brand_apple.svg',
                            onPressed: _appleAuth,
                          ),
                        ),
                      ],
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

  Widget _buildLoginForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PremiumField(
          controller: emailCtrl,
          label: 'Adresse email',
          icon: Icons.email_outlined,
          inputType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 14),
        _PremiumField(
          controller: passCtrl,
          label: 'Mot de passe',
          icon: Icons.lock_outline_rounded,
          obscure: hidden,
          onToggleObscure: () => setState(() => hidden = !hidden),
          onSubmitted: (_) => _doLogin(),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _showForgotPasswordDialog,
            style: TextButton.styleFrom(
              foregroundColor: _blue,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            ),
            child: const Text(
              'Mot de passe oublié ?',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ),
        const SizedBox(height: 6),
        _GradientButton(
          label: 'Se connecter',
          loading: _loading,
          onPressed: _doLogin,
        ),
      ],
    );
  }

  Widget _buildRegisterForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PremiumField(
          controller: nameCtrl,
          label: 'Nom complet',
          icon: Icons.person_outline_rounded,
          capWords: true,
        ),
        const SizedBox(height: 14),
        // Téléphone avec drapeau
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: IntlPhoneField(
            initialCountryCode: 'CI',
            style: const TextStyle(color: Colors.white, fontSize: 15),
            dropdownTextStyle: const TextStyle(color: Colors.white),
            dropdownIconPosition: IconPosition.trailing,
            dropdownIcon: Icon(
              Icons.arrow_drop_down,
              color: Colors.white.withValues(alpha: 0.4),
            ),
            decoration: InputDecoration(
              labelText: 'Téléphone',
              labelStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 14,
              ),
              floatingLabelStyle: const TextStyle(color: _blue, fontSize: 12),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onChanged: (phone) {
              _regPhoneE164 = phone.completeNumber;
              _regCountry = phone.countryISOCode;
            },
          ),
        ),
        const SizedBox(height: 14),
        _PremiumField(
          controller: emailCtrl,
          label: 'Adresse email',
          icon: Icons.email_outlined,
          inputType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 14),
        _PremiumField(
          controller: passCtrl,
          label: 'Mot de passe',
          icon: Icons.lock_outline_rounded,
          obscure: hidden,
          onToggleObscure: () => setState(() => hidden = !hidden),
        ),
        const SizedBox(height: 14),
        _PremiumField(
          controller: pass2Ctrl,
          label: 'Confirmer le mot de passe',
          icon: Icons.lock_outline_rounded,
          obscure: hidden2,
          onToggleObscure: () => setState(() => hidden2 = !hidden2),
          onSubmitted: (_) => _doRegister(),
        ),
        const SizedBox(height: 20),
        _GradientButton(
          label: 'Créer mon compte',
          loading: _loading,
          onPressed: _doRegister,
        ),
        const SizedBox(height: 12),
        Text(
          'En créant un compte, vous acceptez nos Conditions d\'utilisation et notre Politique de confidentialité.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.3),
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

// ─── Widgets communs ──────────────────────────────────────────────────────────

class _PremiumField extends StatelessWidget {
  const _PremiumField({
    required this.controller,
    required this.label,
    required this.icon,
    this.obscure = false,
    this.onToggleObscure,
    this.inputType,
    this.textInputAction,
    this.onSubmitted,
    this.capWords = false,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscure;
  final VoidCallback? onToggleObscure;
  final TextInputType? inputType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final bool capWords;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: inputType,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        textCapitalization: capWords
            ? TextCapitalization.words
            : TextCapitalization.none,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 14,
          ),
          floatingLabelStyle: const TextStyle(
            color: Color(0xFF2563EB),
            fontSize: 12,
          ),
          prefixIcon: Icon(
            icon,
            color: Colors.white.withValues(alpha: 0.35),
            size: 20,
          ),
          suffixIcon: onToggleObscure != null
              ? IconButton(
                  onPressed: onToggleObscure,
                  icon: Icon(
                    obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: Colors.white.withValues(alpha: 0.35),
                    size: 20,
                  ),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  final String label;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 54,
        decoration: BoxDecoration(
          gradient: loading
              ? const LinearGradient(
                  colors: [Color(0xFF374151), Color(0xFF1F2937)],
                )
              : const LinearGradient(
                  colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: loading
              ? []
              : [
                  BoxShadow(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.45),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
        ),
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
        ),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.label,
    required this.iconAsset,
    required this.onPressed,
  });

  final String label;
  final String iconAsset;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(iconAsset, width: 20, height: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
