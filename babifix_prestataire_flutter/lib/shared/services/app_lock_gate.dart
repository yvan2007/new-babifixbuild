import 'package:flutter/material.dart';

import 'app_lock_service.dart';

/// Enveloppe l'application : si le verrou est activé, affiche un écran de
/// déverrouillage (biométrie / code du téléphone) au lancement ET au retour
/// d'arrière-plan, avant de laisser voir le contenu.
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate>
    with WidgetsBindingObserver {
  bool _locked = false;
  bool _authenticating = false;
  bool _checkedAtStart = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLockAtStart());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _maybeLockAtStart() async {
    final enabled = await AppLockService.isEnabled();
    if (!mounted) return;
    if (enabled) {
      setState(() => _locked = true);
      await _tryUnlock();
    }
    _checkedAtStart = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Ne pas re-verrouiller pendant que le prompt d'auth est affiché
    // (il fait passer l'app en "inactive/paused").
    if (_authenticating) return;
    if (!_checkedAtStart) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // L'app part en arrière-plan → on (re)verrouille pour le prochain retour.
      AppLockService.isEnabled().then((enabled) {
        if (enabled && mounted) setState(() => _locked = true);
      });
    } else if (state == AppLifecycleState.resumed && _locked) {
      _tryUnlock();
    }
  }

  Future<void> _tryUnlock() async {
    if (_authenticating) return;
    setState(() => _authenticating = true);
    bool ok = false;
    try {
      ok = await AppLockService.authenticate();
    } finally {
      if (mounted) {
        setState(() {
          _authenticating = false;
          if (ok) _locked = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_locked) _buildLockScreen(context),
      ],
    );
  }

  Widget _buildLockScreen(BuildContext context) {
    return Positioned.fill(
      child: Material(
        color: const Color(0xFF0B1B34),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: const Color(0xFF4CC9F0).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_rounded,
                    size: 46, color: Color(0xFF4CC9F0)),
              ),
              const SizedBox(height: 24),
              const Text(
                'BABIFIX Pro verrouillé',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  'Déverrouillez avec votre empreinte, Face ID ou le code de votre téléphone.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF94A3B8), height: 1.45),
                ),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: _authenticating ? null : _tryUnlock,
                icon: _authenticating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFF0B1B34)),
                      )
                    : const Icon(Icons.fingerprint_rounded),
                label: Text(_authenticating ? 'Authentification…' : 'Déverrouiller'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4CC9F0),
                  foregroundColor: const Color(0xFF0B1B34),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
