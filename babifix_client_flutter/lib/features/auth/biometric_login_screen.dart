import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/zego_call_service.dart';
import '../../user_store.dart';

class BiometricLoginScreen extends StatefulWidget {
  final VoidCallback onSuccess;
  final VoidCallback onUsePassword;

  const BiometricLoginScreen({
    super.key,
    required this.onSuccess,
    required this.onUsePassword,
  });

  @override
  State<BiometricLoginScreen> createState() => _BiometricLoginScreenState();
}

class _BiometricLoginScreenState extends State<BiometricLoginScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _fadeAnimation;

  bool _isAuthenticating = false;
  bool _showError = false;
  String _errorMessage = '';
  BiometricType? _biometricType;
  bool _biometricEnabled = false;
  bool _isLoading = true;

  static const String _biometricEnabledKey = 'biometric_enabled';

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _checkBiometricAndShow();
  }

  void _initAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: AnimationController(
          duration: const Duration(milliseconds: 400),
          vsync: this,
        )..forward(),
        curve: Curves.easeOut,
      ),
    );
  }

  Future<void> _checkBiometricAndShow() async {
    try {
      // Check if user has enabled biometric
      final prefs = await SharedPreferences.getInstance();
      _biometricEnabled = prefs.getBool(_biometricEnabledKey) ?? false;

      if (!_biometricEnabled) {
        // Biometric not enabled by user, skip
        widget.onUsePassword();
        return;
      }

      // Check if device supports biometric
      final localAuth = LocalAuthentication();
      final canCheckBiometrics = await localAuth.canCheckBiometrics;
      final isDeviceSupported = await localAuth.isDeviceSupported();

      if (!canCheckBiometrics || !isDeviceSupported) {
        widget.onUsePassword();
        return;
      }

      final biometrics = await localAuth.getAvailableBiometrics();
      if (biometrics.isEmpty) {
        widget.onUsePassword();
        return;
      }

      setState(() {
        _biometricType = biometrics.first;
        _isLoading = false;
      });

      // Auto-trigger biometric after a short delay
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        _authenticate();
      }
    } catch (e) {
      widget.onUsePassword();
    }
  }

  Future<void> _authenticate() async {
    if (_isAuthenticating) return;

    setState(() {
      _isAuthenticating = true;
      _showError = false;
    });

    HapticFeedback.lightImpact();

    final localAuth = LocalAuthentication();

    try {
      final didAuthenticate = await localAuth.authenticate(
        localizedReason: 'Authentifiez-vous pour accéder à BABIFIX',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
          useErrorDialogs: false,
          sensitiveTransaction: true,
        ),
      );

      if (didAuthenticate) {
        HapticFeedback.mediumImpact();
        final profile = await BabifixUserStore.loadProfile();
        await BabifixZegoService.init(
          userID: 'babifix_client_${profile['email']}',
          userName: profile['name'] ?? profile['email'] ?? 'Client',
        );
        widget.onSuccess();
      } else {
        _showErrorMessage('Authentification annulée');
      }
    } on PlatformException catch (e) {
      String message;
      switch (e.code) {
        case 'NotAvailable':
          message = 'Biométrie non disponible sur cet appareil';
          break;
        case 'NotEnrolled':
          message =
              'Aucune biométrie configurée.\nConfigurez Face ID ou Empreinte dans les paramètres.';
          break;
        case 'LockedOut':
          message = 'Trop de tentatives.\nRéessayez dans quelques minutes.';
          break;
        case 'PermanentlyLockedOut':
          message = 'Biométrie désactivée.\nUtilisez votre mot de passe.';
          break;
        default:
          message = 'Erreur d\'authentification';
      }
      _showErrorMessage(message);
    } finally {
      if (mounted) {
        setState(() {
          _isAuthenticating = false;
        });
      }
    }
  }

  void _showErrorMessage(String message) {
    HapticFeedback.heavyImpact();
    setState(() {
      _showError = true;
      _errorMessage = message;
    });

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showError = false;
        });
      }
    });
  }

  IconData _getBiometricIcon() {
    switch (_biometricType) {
      case BiometricType.face:
        return Icons.face;
      case BiometricType.fingerprint:
      case BiometricType.strong:
        return Icons.fingerprint;
      case BiometricType.iris:
        return Icons.remove_red_eye;
      default:
        return Icons.lock;
    }
  }

  Color _getBiometricColor() {
    switch (_biometricType) {
      case BiometricType.face:
        return const Color(0xFF0084D1);
      case BiometricType.fingerprint:
      case BiometricType.strong:
        return const Color(0xFF2E7D32);
      default:
        return const Color(0xFF1565C0);
    }
  }

  String _getBiometricLabel() {
    switch (_biometricType) {
      case BiometricType.face:
        return 'Face ID';
      case BiometricType.fingerprint:
      case BiometricType.strong:
        return 'Empreinte digitale';
      case BiometricType.iris:
        return 'Iris';
      default:
        return 'Biométrie';
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Theme.of(context).primaryColor),
              const SizedBox(height: 20),
              Text(
                'Chargement...',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    final color = _getBiometricColor();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),

                // Logo
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    Icons.home_repair_service,
                    size: 40,
                    color: color,
                  ),
                ),

                const SizedBox(height: 40),

                // Animated biometric icon
                GestureDetector(
                  onTap: _isAuthenticating ? null : _authenticate,
                  child: CustomAnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _isAuthenticating ? 1.0 : _pulseAnimation.value,
                        child: child,
                      );
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _showError
                            ? Colors.red.shade50
                            : color.withValues(alpha: 0.1),
                        border: Border.all(
                          color: _showError ? Colors.red : color,
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (_showError ? Colors.red : color).withValues(
                              alpha: 0.3,
                            ),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Center(
                        child: _isAuthenticating
                            ? SizedBox(
                                width: 50,
                                height: 50,
                                child: CircularProgressIndicator(
                                  color: color,
                                  strokeWidth: 3,
                                ),
                              )
                            : Icon(
                                _showError
                                    ? Icons.error_outline
                                    : _getBiometricIcon(),
                                size: 70,
                                color: _showError ? Colors.red : color,
                              ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 40),

                // Title
                Text(
                  _showError ? 'Oups !' : 'Bienvenue',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: _showError ? Colors.red : Colors.black87,
                  ),
                ),

                const SizedBox(height: 12),

                // Subtitle
                Text(
                  _showError
                      ? _errorMessage
                      : 'Touchez pour vous connecter avec\n${_getBiometricLabel()}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: _showError ? Colors.red.shade400 : Colors.black54,
                    height: 1.5,
                  ),
                ),

                const SizedBox(height: 24),

                // Biometric type badge
                if (!_showError && _biometricType != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_getBiometricIcon(), size: 20, color: color),
                        const SizedBox(width: 8),
                        Text(
                          _getBiometricLabel(),
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                const Spacer(),

                // Retry button on error
                if (_showError) ...[
                  ElevatedButton.icon(
                    onPressed: _authenticate,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Réessayer'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 40,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Use password button
                TextButton(
                  onPressed: widget.onUsePassword,
                  child: Text(
                    'Utiliser mon mot de passe',
                    style: TextStyle(
                      color: _showError
                          ? Colors.red.shade400
                          : Colors.grey.shade600,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CustomAnimatedBuilder extends AnimatedWidget {
  final Widget Function(BuildContext, Widget?) builder;
  final Widget? child;

  const CustomAnimatedBuilder({
    super.key,
    required Animation<double> animation,
    required this.builder,
    this.child,
  }) : super(listenable: animation);

  @override
  Widget build(BuildContext context) {
    return builder(context, child);
  }
}

// Helper to enable/disable biometric
class BiometricHelper {
  static const String _biometricEnabledKey = 'biometric_enabled';

  static Future<void> enableBiometric() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricEnabledKey, true);
  }

  static Future<void> disableBiometric() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricEnabledKey, false);
  }

  static Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_biometricEnabledKey) ?? false;
  }

  static Future<bool> isBiometricAvailable() async {
    try {
      final localAuth = LocalAuthentication();
      final canCheck = await localAuth.canCheckBiometrics;
      final isSupported = await localAuth.isDeviceSupported();
      if (!canCheck || !isSupported) return false;
      final biometrics = await localAuth.getAvailableBiometrics();
      return biometrics.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
