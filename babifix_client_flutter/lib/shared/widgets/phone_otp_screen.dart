import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../user_store.dart';
import 'babifix_ring_loader.dart';

class PhoneOtpScreen extends StatefulWidget {
  const PhoneOtpScreen({
    super.key,
    required this.onVerified,
    this.initialPhone,
    this.authToken,
    this.apiBase,
  });

  final VoidCallback onVerified;
  final String? initialPhone;
  final String? authToken;
  final String? apiBase;

  @override
  State<PhoneOtpScreen> createState() => _PhoneOtpScreenState();
}

class _PhoneOtpScreenState extends State<PhoneOtpScreen> {
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _sending = false;
  bool _verifying = false;
  bool _codeSent = false;
  String? _verificationId;
  int _countdown = 0;
  Timer? _timer;
  String? _error;
  String? _fbError;

  @override
  void initState() {
    super.initState();
    if (widget.initialPhone != null && widget.initialPhone!.isNotEmpty) {
      _phoneCtrl.text = widget.initialPhone!;
    }
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _countdown = 30;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_countdown <= 0) {
        t.cancel();
      }
      if (mounted) setState(() => _countdown--);
    });
  }

  /// Normalise un saisi local CI ("01 02 03 04 05") en E.164 ("+2250102030405").
  String _toE164(String raw) {
    var s = raw.trim().replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (s.startsWith('+')) return s;
    if (s.startsWith('00')) return '+${s.substring(2)}';
    if (s.startsWith('225')) return '+$s';
    return '+225$s';
  }

  Future<void> _sendCode() async {
    final raw = _phoneCtrl.text.trim();
    if (raw.isEmpty || raw.length < 8) {
      setState(() => _error = 'Numéro de téléphone invalide');
      return;
    }
    final phone = _toE164(raw);
    setState(() {
      _sending = true;
      _error = null;
      _fbError = null;
    });

    try {
      await fb.FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (cred) async {
          if (!mounted) return;
          _codeCtrl.text = cred.smsCode ?? '';
          await _verifyCode(cred);
        },
        verificationFailed: (e) {
          if (!mounted) return;
          setState(() {
            _sending = false;
            _fbError = 'Erreur: ${e.message}';
          });
        },
        codeSent: (vid, token) {
          if (!mounted) return;
          setState(() {
            _verificationId = vid;
            _codeSent = true;
            _sending = false;
          });
          _startCountdown();
        },
        codeAutoRetrievalTimeout: (vid) {
          _verificationId = vid;
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _fbError = 'Erreur: $e';
      });
    }
  }

  Future<void> _verifyCode([fb.PhoneAuthCredential? cred]) async {
    if (cred == null) {
      final code = _codeCtrl.text.trim();
      if (code.isEmpty || code.length < 4) {
        setState(() => _error = 'Code invalide');
        return;
      }
      if (_verificationId == null) {
        setState(() => _error = 'Aucune vérification en cours');
        return;
      }
      cred = fb.PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: code,
      );
    }

    setState(() {
      _verifying = true;
      _error = null;
    });

    try {
      final userCred = await fb.FirebaseAuth.instance.signInWithCredential(cred);
      final idToken = await userCred.user?.getIdToken();
      if (idToken == null) throw Exception('No Firebase ID token');

      final ok = await _sendTokenToBackend(idToken);
      if (ok && mounted) {
        widget.onVerified();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _fbError = 'Code incorrect: $e';
      });
    }
  }

  Future<bool> _sendTokenToBackend(String idToken) async {
    final base = widget.apiBase ?? babifixApiBaseUrl();
    final token = widget.authToken ?? await BabifixUserStore.getApiToken();
    if (token == null || token.isEmpty) {
      setState(() => _error = 'Non authentifié');
      return false;
    }

    final res = await http.post(
      Uri.parse('$base/api/auth/verify-otp'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'firebase_token': idToken}),
    );

    if (res.statusCode == 200) {
      return true;
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    setState(() => _error = '${data['error'] ?? 'Erreur serveur'}');
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isLight = cs.brightness == Brightness.light;
    final bg = isLight ? const Color(0xFFF8FAFC) : const Color(0xFF0D1117);
    final cardBg = isLight ? Colors.white : const Color(0xFF161B22);
    final textPrimary = isLight ? const Color(0xFF0F172A) : Colors.white;
    final textSecondary = isLight ? const Color(0xFF64748B) : const Color(0xFF9CA3AF);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: cardBg,
        title: const Text('Vérification téléphone'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.phone_android_rounded,
              size: 64,
              color: BabifixDesign.iconOnLight,
            ),
            const SizedBox(height: 16),
            Text(
              'Vérifiez votre numéro',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Un code de vérification sera envoyé par SMS',
              style: theme.textTheme.bodyMedium?.copyWith(color: textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            if (!_codeSent) ...[
              Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: textSecondary.withValues(alpha: 0.2)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Numéro (+225 XX XX XX XX)',
                    border: InputBorder.none,
                    prefixText: '+225 ',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _sending ? null : _sendCode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: BabifixDesign.cyan,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _sending
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: BabifixRingLoader.cyan(size: 28),
                        )
                      : const Text(
                          'Envoyer le code',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                ),
              ),
            ],

            if (_codeSent) ...[
              Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: textSecondary.withValues(alpha: 0.2)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextField(
                  controller: _codeCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 28, letterSpacing: 8),
                  decoration: InputDecoration(
                    labelText: 'Code à 6 chiffres',
                    border: InputBorder.none,
                    counterText: '',
                  ),
                  onSubmitted: (_) => _verifyCode(),
                ),
              ),
              if (kDebugMode)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '🔧 Mode développement : entrez 000000',
                    style: TextStyle(color: BabifixDesign.warning, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
              const SizedBox(height: 16),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _verifying ? null : () => _verifyCode(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: BabifixDesign.cyan,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _verifying
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: BabifixRingLoader.cyan(size: 28),
                        )
                      : const Text(
                          'Vérifier',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              if (_countdown > 0)
                Text(
                  'Renvoyer dans $_countdown s',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: textSecondary),
                )
              else
                TextButton(
                  onPressed: _sending ? null : _sendCode,
                  child: const Text('Renvoyer le code'),
                ),
            ],

            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: BabifixDesign.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: BabifixDesign.error),
                  textAlign: TextAlign.center,
                ),
              ),
            ],

            if (_fbError != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: BabifixDesign.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _fbError!,
                  style: TextStyle(color: BabifixDesign.error, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
