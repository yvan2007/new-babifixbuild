import 'package:flutter/material.dart';

import 'wallet_pin_service.dart';

/// Affiche le dialogue de code PIN du portefeuille.
///
/// - Si aucun PIN n'existe encore → flux de création (saisie + confirmation).
/// - Si un PIN existe → flux de vérification.
///
/// Retourne `true` si l'utilisateur est autorisé (PIN créé ou vérifié),
/// `false` ou `null` s'il annule.
Future<bool> showWalletPinDialog(BuildContext context) async {
  final hasPin = await WalletPinService.hasPin();
  if (!context.mounted) return false;
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _WalletPinDialog(isSetup: !hasPin),
  );
  return ok ?? false;
}

class _WalletPinDialog extends StatefulWidget {
  const _WalletPinDialog({required this.isSetup});
  final bool isSetup;

  @override
  State<_WalletPinDialog> createState() => _WalletPinDialogState();
}

class _WalletPinDialogState extends State<_WalletPinDialog> {
  String _entry = '';
  String _firstEntry = ''; // pour la confirmation lors de la création
  bool _confirming = false;
  String? _error;
  bool _busy = false;

  String get _title {
    if (widget.isSetup) {
      return _confirming ? 'Confirmez votre code' : 'Créez un code à 4 chiffres';
    }
    return 'Entrez votre code';
  }

  String get _subtitle {
    if (widget.isSetup) {
      return _confirming
          ? 'Saisissez à nouveau le même code.'
          : 'Ce code protègera vos demandes de retrait.';
    }
    return 'Code requis pour confirmer la transaction.';
  }

  Future<void> _onDigit(String d) async {
    if (_busy || _entry.length >= 4) return;
    setState(() {
      _entry += d;
      _error = null;
    });
    if (_entry.length == 4) {
      await _onComplete();
    }
  }

  void _onBackspace() {
    if (_busy || _entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  Future<void> _onComplete() async {
    setState(() => _busy = true);
    try {
      if (widget.isSetup) {
        if (!_confirming) {
          // 1ère saisie → passer à la confirmation
          _firstEntry = _entry;
          setState(() {
            _confirming = true;
            _entry = '';
          });
        } else {
          if (_entry == _firstEntry) {
            await WalletPinService.setPin(_entry);
            if (mounted) Navigator.of(context).pop(true);
          } else {
            setState(() {
              _error = 'Les codes ne correspondent pas. Recommencez.';
              _confirming = false;
              _entry = '';
              _firstEntry = '';
            });
          }
        }
      } else {
        final ok = await WalletPinService.verifyPin(_entry);
        if (ok) {
          if (mounted) Navigator.of(context).pop(true);
        } else {
          setState(() {
            _error = 'Code incorrect. Réessayez.';
            _entry = '';
          });
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline_rounded,
                size: 40, color: Color(0xFF4CC9F0)),
            const SizedBox(height: 12),
            Text(_title,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface)),
            const SizedBox(height: 6),
            Text(_subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.6), height: 1.4)),
            const SizedBox(height: 20),
            // Points de progression
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (i) {
                final filled = i < _entry.length;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 9),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled
                        ? const Color(0xFF4CC9F0)
                        : cs.onSurface.withValues(alpha: 0.15),
                  ),
                );
              }),
            ),
            const SizedBox(height: 14),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(_error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Color(0xFFEF4444),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
              ),
            const SizedBox(height: 6),
            _buildKeypad(cs),
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeypad(ColorScheme cs) {
    final keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '⌫'];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.7,
      children: keys.map((k) {
        if (k.isEmpty) return const SizedBox.shrink();
        final isBack = k == '⌫';
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _busy
              ? null
              : (isBack ? _onBackspace : () => _onDigit(k)),
          child: Center(
            child: isBack
                ? Icon(Icons.backspace_outlined, color: cs.onSurface)
                : Text(k,
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface)),
          ),
        );
      }).toList(),
    );
  }
}
