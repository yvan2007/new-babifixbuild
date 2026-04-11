import 'dart:convert';

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

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  final pass2Ctrl = TextEditingController();
  final nameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  String _regPhoneE164 = '';
  String _regCountry = 'CI';
  bool hidden = true;
  bool hidden2 = true;

  bool _showBiometricLogin = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() {
      if (mounted) setState(() {});
    });
    _checkBiometricLogin();
  }

  Future<void> _checkBiometricLogin() async {
    // Check if biometric is enabled and user is logged in
    final prefs = await SharedPreferences.getInstance();
    final biometricEnabled = prefs.getBool('biometric_enabled') ?? false;
    final isLoggedIn = await BabifixUserStore.isLoggedIn();

    if (biometricEnabled && isLoggedIn) {
      // Check if biometric is available on device
      final isAvailable = await BiometricHelper.isBiometricAvailable();
      if (isAvailable && mounted) {
        setState(() {
          _showBiometricLogin = true;
          _isLoading = false;
        });
        return;
      }
    }

    if (mounted) {
      setState(() {
        _showBiometricLogin = false;
        _isLoading = false;
      });
    }
  }

  void _onBiometricSuccess() {
    widget.onAuthSuccess();
  }

  void _onBiometricUsePassword() {
    setState(() {
      _showBiometricLogin = false;
    });
  }

  void _enableBiometricAndContinue() async {
    await BiometricHelper.enableBiometric();
    widget.onAuthSuccess();
  }

  @override
  void dispose() {
    _tab.dispose();
    emailCtrl.dispose();
    passCtrl.dispose();
    pass2Ctrl.dispose();
    nameCtrl.dispose();
    phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _doLogin() async {
    final err = await BabifixUserStore.login(emailCtrl.text, passCtrl.text);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    widget.onAuthSuccess();
  }

  Future<void> _doRegister() async {
    if (passCtrl.text != pass2Ctrl.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Les mots de passe ne correspondent pas.'),
        ),
      );
      return;
    }
    final err = await BabifixUserStore.register(
      email: emailCtrl.text.trim(),
      password: passCtrl.text,
      name: nameCtrl.text.trim(),
      phone: _regPhoneE164.isNotEmpty ? _regPhoneE164 : phoneCtrl.text.trim(),
      countryCode: _regCountry,
    );
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    // Afficher l'écran de vérification d'email, puis l'onboarding
    if (mounted) {
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
  }

  Future<void> _googleAuth() async {
    final err = await BabifixUserStore.tryGoogleAuth();
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    widget.onAuthSuccess();
  }

  Future<void> _appleAuth() async {
    final err = await BabifixUserStore.tryAppleAuth();
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    widget.onAuthSuccess();
  }

  void _showForgotPasswordDialog() {
    final forgotEmailCtrl = TextEditingController(text: emailCtrl.text);
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Réinitialiser le mot de passe'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Entrez votre adresse email pour recevoir un lien de réinitialisation.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: forgotEmailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () async {
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Email de réinitialisation envoyé ✓'),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Adresse email introuvable ou erreur serveur.'),
                      ),
                    );
                  }
                } catch (_) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Impossible de contacter le serveur.'),
                    ),
                  );
                }
              },
              child: const Text('Envoyer'),
            ),
          ],
        );
      },
    ).then((_) => forgotEmailCtrl.dispose());
  }

  Widget _svgPrefix(String asset) => Padding(
    padding: const EdgeInsets.only(left: 14, right: 4),
    child: SvgPicture.asset(asset, width: 22, height: 22),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isLight = theme.brightness == Brightness.light;
    final titleColor = cs.onSurface;
    final muted = cs.onSurfaceVariant;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Compte BABIFIX'),
        backgroundColor: Colors.transparent,
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isLight
                ? const [
                    Color(0xFFF6F8FC),
                    Color(0xFFEFF6FF),
                    Color(0xFFE0F2FE),
                  ]
                : [
                    BabifixDesign.navy,
                    const Color(0xFF0E2844),
                    BabifixDesign.navy,
                  ],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              Text(
                'Bienvenue sur BABIFIX',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: titleColor,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Connectez-vous ou creez un compte pour reserver et suivre vos prestations.',
                style: TextStyle(color: muted, fontSize: 15, height: 1.4),
              ),
              const SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                  color: isLight
                      ? Colors.white.withValues(alpha: 0.85)
                      : cs.surface.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: BabifixDesign.cyan.withValues(alpha: 0.35),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isLight ? 0.06 : 0.25,
                      ),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    TabBar(
                      controller: _tab,
                      indicatorColor: BabifixDesign.cyan,
                      labelColor: titleColor,
                      unselectedLabelColor: muted,
                      tabs: const [
                        Tab(text: 'Connexion'),
                        Tab(text: 'Creer un compte'),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                      child: AnimatedBuilder(
                        animation: _tab,
                        builder: (context, child) => _tab.index == 0
                            ? _buildLoginForm(muted, titleColor)
                            : _buildRegisterForm(muted, titleColor),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Ou continuer avec',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, fontSize: 13),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _googleAuth,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SvgPicture.asset(
                            'assets/illustrations/icons/brand_google.svg',
                            width: 22,
                            height: 22,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Google',
                            style: TextStyle(
                              color: titleColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _appleAuth,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SvgPicture.asset(
                            'assets/illustrations/icons/brand_apple.svg',
                            width: 20,
                            height: 22,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Apple',
                            style: TextStyle(
                              color: titleColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm(Color muted, Color titleColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: emailCtrl,
          keyboardType: TextInputType.emailAddress,
          style: TextStyle(color: titleColor),
          decoration: InputDecoration(
            labelText: 'Email',
            prefixIcon: _svgPrefix('assets/illustrations/icons/icon_mail.svg'),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: passCtrl,
          obscureText: hidden,
          style: TextStyle(color: titleColor),
          decoration: InputDecoration(
            labelText: 'Mot de passe',
            prefixIcon: _svgPrefix('assets/illustrations/icons/icon_lock.svg'),
            suffixIcon: IconButton(
              onPressed: () => setState(() => hidden = !hidden),
              icon: Icon(
                hidden
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
                color: muted,
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _showForgotPasswordDialog,
            child: const Text('Mot de passe oublie ?'),
          ),
        ),
        const SizedBox(height: 6),
        FilledButton(onPressed: _doLogin, child: const Text('Se connecter')),
      ],
    );
  }

  Widget _buildRegisterForm(Color muted, Color titleColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: nameCtrl,
          textCapitalization: TextCapitalization.words,
          style: TextStyle(color: titleColor),
          decoration: InputDecoration(
            labelText: 'Nom complet',
            prefixIcon: _svgPrefix('assets/illustrations/icons/icon_user.svg'),
          ),
        ),
        const SizedBox(height: 12),
        IntlPhoneField(
          initialCountryCode: 'CI',
          style: TextStyle(color: titleColor),
          dropdownTextStyle: TextStyle(color: titleColor),
          decoration: InputDecoration(
            labelText: 'Telephone',
            prefixIcon: _svgPrefix('assets/illustrations/icons/icon_phone.svg'),
          ),
          onChanged: (phone) {
            _regPhoneE164 = phone.completeNumber;
            _regCountry = phone.countryISOCode;
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: emailCtrl,
          keyboardType: TextInputType.emailAddress,
          style: TextStyle(color: titleColor),
          decoration: InputDecoration(
            labelText: 'Email',
            prefixIcon: _svgPrefix('assets/illustrations/icons/icon_mail.svg'),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: passCtrl,
          obscureText: hidden,
          style: TextStyle(color: titleColor),
          decoration: InputDecoration(
            labelText: 'Mot de passe',
            prefixIcon: _svgPrefix('assets/illustrations/icons/icon_lock.svg'),
            suffixIcon: IconButton(
              onPressed: () => setState(() => hidden = !hidden),
              icon: Icon(
                hidden
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
                color: muted,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: pass2Ctrl,
          obscureText: hidden2,
          style: TextStyle(color: titleColor),
          decoration: InputDecoration(
            labelText: 'Confirmer le mot de passe',
            prefixIcon: _svgPrefix('assets/illustrations/icons/icon_lock.svg'),
            suffixIcon: IconButton(
              onPressed: () => setState(() => hidden2 = !hidden2),
              icon: Icon(
                hidden2
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
                color: muted,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _doRegister,
          child: const Text('Creer mon compte'),
        ),
      ],
    );
  }
}
