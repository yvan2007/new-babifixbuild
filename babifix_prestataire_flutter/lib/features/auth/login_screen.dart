import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../babifix_api_config.dart';
import '../../shared/auth_utils.dart';
import '../../shared/widgets/babifix_page_route.dart';
import 'forgot_password_screen.dart';
import '../../shared/widgets/babifix_ring_loader.dart';
import '../../shared/widgets/babifix_snackbar.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onBack, required this.onSuccess,});

  final VoidCallback onBack;
  final VoidCallback onSuccess;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  late final AnimationController _anim;
  late final Animation<double> _fadeIn;

  static const _navyDeep = Color(0xFF060E1C);
  static const _cyan = Color(0xFF4CC9F0);
  static const _blue = Color(0xFF4CC9F0);

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeIn = CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic);
    _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final identifier = _user.text.trim();
    final pass = _pass.text;
    // L'identifiant peut être l'email OU le nom d'utilisateur (nom/prénom
    // choisi à l'inscription). Le backend cherche d'abord par email puis par
    // username : on route donc selon la présence d'un '@'.
    final isEmail = identifier.contains('@');
    setState(() => _loading = true);
    try {
      final res = await http.post(
        Uri.parse('${babifixApiBaseUrl()}/api/auth/login/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          if (isEmail) 'email': identifier else 'username': identifier,
          'password': pass,
        }),
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
        final msg = res.statusCode == 400 || res.statusCode == 401
            ? 'Identifiants incorrects. Vérifiez votre email et mot de passe.'
            : res.statusCode == 403
            ? 'Compte suspendu. Contactez l\'administrateur.'
            : 'Erreur serveur (${res.statusCode}). Réessayez.';
        _snack(msg);
      }
    } catch (_) {
      if (mounted) _snack('Impossible de contacter le serveur.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg) {
    showBabifixToast(
        context,
        type: BabifixToastType.info,
        message: msg,
      );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF4CC9F0),
          secondary: Color(0xFF4CC9F0),
          surface: Color(0xFF0A1628),
        ),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: Color(0xFF4CC9F0),
          selectionColor: Color(0x554CC9F0),
          selectionHandleColor: Color(0xFF4CC9F0),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: InputBorder.none,
        ),
      ),
      child: Scaffold(
        backgroundColor: _navyDeep,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // ── Fond gradient + orbes ──────────────────────────────────────
            Positioned.fill(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF060E1C),
                      Color(0xFF0B1B34),
                      Color(0xFF0A1628),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: -80,
              right: -60,
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [_cyan.withValues(alpha: 0.18), Colors.transparent],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -100,
              left: -80,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [_blue.withValues(alpha: 0.14), Colors.transparent],
                  ),
                ),
              ),
            ),

            // ── Contenu ────────────────────────────────────────────────────
            SafeArea(
              child: FadeTransition(
                opacity: _fadeIn,
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - 32,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                    // ── Logo + titre ─────────────────────────────────
                    Center(
                      child: Column(
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: _cyan.withValues(alpha: 0.45),
                                  blurRadius: 28,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: Image.asset(
                                'assets/images/logo_babifix.png',
                                fit: BoxFit.cover,
                                width: 80,
                                height: 80,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'BABIFIX',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 4,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Espace Prestataire',
                            style: TextStyle(
                              fontSize: 13,
                              color: _cyan.withValues(alpha: 0.85),
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),

                          const SizedBox(height: 36),

                          // ── Card glassmorphisme ───────────────────────────
                          ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                              child: Container(
                                padding: const EdgeInsets.fromLTRB(
                                  24,
                                  28,
                                  24,
                                  28,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(28),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.12),
                                    width: 1.5,
                                  ),
                                ),
                                child: Form(
                                  key: _formKey,
                                  child: Center(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                    const Text(
                                      'Connexion',
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Accédez à votre espace professionnel',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.white.withValues(
                                          alpha: 0.5,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 24),

                                    // Champ email
                                    _PremiumField(
                                      controller: _user,
                                      label: 'Email ou nom complet',
                                      icon: Icons.person_outline_rounded,
                                      inputType: TextInputType.emailAddress,
                                      textInputAction: TextInputAction.next,
                                      validator: (v) {
                                        if (v == null || v.trim().isEmpty) return 'Email ou nom requis';
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 14),

                                    // Champ mot de passe
                                    _PremiumField(
                                      controller: _pass,
                                      label: 'Mot de passe',
                                      icon: Icons.lock_outline_rounded,
                                      obscure: _obscure,
                                      onToggleObscure: () =>
                                          setState(() => _obscure = !_obscure),
                                      textInputAction: TextInputAction.done,
                                      onSubmitted: (_) => _submit(),
                                      validator: (v) {
                                        if (v == null || v.isEmpty) return 'Mot de passe requis';
                                        return null;
                                      },
                                    ),

                                    // Mot de passe oublié
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).push(
                                              babifixRoute(
                                                (_) => const ForgotPasswordScreen(),
                                              ),
                                            ),
                                        style: TextButton.styleFrom(
                                          foregroundColor: _cyan,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 8,
                                          ),
                                        ),
                                        child: const Text(
                                          'Mot de passe oublié ?',
                                          style: TextStyle(fontSize: 13),
                                        ),
                                      ),
                                    ),

                                    const SizedBox(height: 8),

                                    // Bouton connexion
                                    _PremiumButton(
                                      label: 'Se connecter',
                                      loading: _loading,
                                      onPressed: _submit,
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFF4CC9F0),
                                          Color(0xFF4CC9F0),
                                        ],
                                      ),
                                    ),
                                   ],
                                 ),
                               ),
                             ),
                            ),
                          ),
                        ),

                            const SizedBox(height: 28),

                          // ── Lien inscription ─────────────────────────────
                          Center(
                            child: RichText(
                              text: TextSpan(
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 14,
                                ),
                                children: [
                                  const TextSpan(text: 'Pas encore inscrit ? '),
                                  WidgetSpan(
                                    child: GestureDetector(
                                      onTap: widget.onBack,
                                      child: const Text(
                                        'Créer un compte',
                                        style: TextStyle(
                                          color: _cyan,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          decoration: TextDecoration.underline,
                                          decorationColor: _cyan,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
  }
}

// ─── Widgets réutilisables premium ────────────────────────────────────────────

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
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscure;
  final VoidCallback? onToggleObscure;
  final TextInputType? inputType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        keyboardType: inputType,
        textInputAction: textInputAction,
        onFieldSubmitted: onSubmitted,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator: validator,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 14,
          ),
          floatingLabelStyle: const TextStyle(
            color: Color(0xFF4CC9F0),
            fontSize: 12,
          ),
          errorStyle: const TextStyle(
            color: Color(0xFFFF8A80),
            fontSize: 11,
          ),
          prefixIcon: Icon(
            icon,
            color: Colors.white.withValues(alpha: 0.4),
            size: 20,
          ),
          suffixIcon: onToggleObscure != null
              ? IconButton(
                  onPressed: onToggleObscure,
                  icon: Icon(
                    obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: Colors.white.withValues(alpha: 0.4),
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

class _PremiumButton extends StatelessWidget {
  const _PremiumButton({
    required this.label,
    required this.loading,
    required this.onPressed,
    required this.gradient,
  });

  final String label;
  final bool loading;
  final VoidCallback onPressed;
  final Gradient gradient;

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
                  colors: [Color(0xFF475569), Color(0xFF334155)],
                )
              : gradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: loading
              ? []
              : [
                  BoxShadow(
                    color: const Color(0xFF4CC9F0).withValues(alpha: 0.4),
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
                  child: BabifixRingLoader.cyan(size: 28),
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
