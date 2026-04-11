import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

class BiometricAuthWidget extends StatefulWidget {
  final VoidCallback? onSuccess;
  final Function(String)? onError;
  final String title;
  final String subtitle;
  final bool showSkipButton;
  final VoidCallback? onSkip;

  const BiometricAuthWidget({
    super.key,
    this.onSuccess,
    this.onError,
    this.title = 'Connexion biométrique',
    this.subtitle = 'Touchez le bouton pour vous authentifier',
    this.showSkipButton = true,
    this.onSkip,
  });

  @override
  State<BiometricAuthWidget> createState() => _BiometricAuthWidgetState();
}

class _BiometricAuthWidgetState extends State<BiometricAuthWidget>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _scaleController;
  late AnimationController _fadeController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  bool _isAuthenticating = false;
  bool _showError = false;
  String _errorMessage = '';
  BiometricType? _biometricType;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _checkBiometrics();
  }

  void _initAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));

    _fadeController.forward();
  }

  Future<void> _checkBiometrics() async {
    final localAuth = LocalAuthentication();
    try {
      final isAvailable = await localAuth.canCheckBiometrics;
      final isDeviceSupported = await localAuth.isDeviceSupported();

      if (isAvailable && isDeviceSupported) {
        final biometrics = await localAuth.getAvailableBiometrics();
        if (biometrics.isNotEmpty) {
          setState(() {
            _biometricType = biometrics.first;
          });
        }
      }
    } catch (e) {
      debugPrint('Error checking biometrics: $e');
    }
  }

  Future<void> _authenticate() async {
    if (_isAuthenticating) return;

    setState(() {
      _isAuthenticating = true;
      _showError = false;
    });

    _scaleController.forward().then((_) => _scaleController.reverse());

    final localAuth = LocalAuthentication();

    try {
      final didAuthenticate = await localAuth.authenticate(
        localizedReason: widget.subtitle,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
          useErrorDialogs: true,
          sensitiveTransaction: true,
        ),
      );

      if (didAuthenticate) {
        _onSuccess();
      } else {
        _onError('Authentification annulée');
      }
    } on PlatformException catch (e) {
      String message;
      switch (e.code) {
        case 'NotAvailable':
          message = 'Biométrie non disponible';
          break;
        case 'NotEnrolled':
          message = 'Aucune biométrie configurée';
          break;
        case 'LockedOut':
          message = 'Trop de tentatives, réessayez plus tard';
          break;
        case 'PermanentlyLockedOut':
          message = 'Biométrie désactivée, utilisez votre mot de passe';
          break;
        default:
          message = 'Erreur d\'authentification';
      }
      _onError(message);
    } finally {
      if (mounted) {
        setState(() {
          _isAuthenticating = false;
        });
      }
    }
  }

  void _onSuccess() {
    HapticFeedback.mediumImpact();
    widget.onSuccess?.call();
  }

  void _onError(String message) {
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

    widget.onError?.call(message);
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
        return 'Empreinte';
      case BiometricType.iris:
        return 'Iris';
      default:
        return 'Biométrie';
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scaleController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _getBiometricColor();

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),

            // Biometric icon with pulse animation
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _isAuthenticating ? 1.0 : _pulseAnimation.value,
                  child: child,
                );
              },
              child: GestureDetector(
                onTap: _isAuthenticating ? null : _authenticate,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        color.withValues(alpha: 0.2),
                        color.withValues(alpha: 0.1),
                      ],
                    ),
                    border: Border.all(
                      color: _isAuthenticating
                          ? color
                          : color.withValues(alpha: 0.5),
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.3),
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
                        : AnimatedBuilder(
                            animation: _scaleAnimation,
                            builder: (context, child) {
                              return Transform.scale(
                                scale: _scaleAnimation.value,
                                child: child,
                              );
                            },
                            child: Icon(
                              _getBiometricIcon(),
                              size: 70,
                              color: color,
                            ),
                          ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 40),

            // Title
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: _showError ? 22 : 26,
                fontWeight: FontWeight.bold,
                color: _showError ? Colors.red : Colors.black87,
              ),
              child: Text(_showError ? 'Erreur' : widget.title),
            ),

            const SizedBox(height: 12),

            // Subtitle or error message
            Text(
              _showError ? _errorMessage : widget.subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: _showError ? Colors.red.shade400 : Colors.black54,
                height: 1.4,
              ),
            ),

            const SizedBox(height: 16),

            // Biometric type badge
            if (_biometricType != null && !_showError)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_getBiometricIcon(), size: 18, color: color),
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
            if (_showError)
              ElevatedButton.icon(
                onPressed: _authenticate,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),

            // Skip button
            if (widget.showSkipButton && !_showError && !_isAuthenticating)
              TextButton(
                onPressed: widget.onSkip,
                child: const Text(
                  'Utiliser mon mot de passe',
                  style: TextStyle(color: Colors.black54, fontSize: 15),
                ),
              ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// Animated builder helper
class AnimatedBuilder extends StatelessWidget {
  final Animation<double> animation;
  final Widget Function(BuildContext, Widget?) builder;
  final Widget? child;

  const AnimatedBuilder({
    super.key,
    required this.animation,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder2(
      animation: animation,
      builder: builder,
      child: child,
    );
  }
}

class AnimatedBuilder2 extends AnimatedWidget {
  final Widget Function(BuildContext, Widget?) builder;
  final Widget? child;

  const AnimatedBuilder2({
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
