import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../user_store.dart';
import '../../shared/widgets/address_search_field.dart';
import '../../shared/widgets/babifix_osm_map.dart';
import '../../shared/widgets/gps_location_card.dart';
import '../../shared/widgets/payment_method_logo.dart';
import '../../shared/widgets/babifix_ring_loader.dart';
import '../../shared/widgets/babifix_snackbar.dart';

/// Flow de réservation en 4 étapes :
/// 0 → Date & heure  1 → Adresse  2 → Récapitulatif  3 → Confirmation
class BookingFlowScreen extends StatefulWidget {
  const BookingFlowScreen({
    super.key,
    required this.serviceTitle,
    required this.servicePrice,
    this.providerName,
    this.providerPhoto,
    this.providerRating,
    this.providerSpecialite,
    this.providerId,
    this.onConfirm,
  });

  final String serviceTitle;
  final int servicePrice;
  final String? providerName;
  final String? providerPhoto;
  final double? providerRating;
  final String? providerSpecialite;
  final int? providerId;
  final Future<Map<String, dynamic>?> Function(Map<String, dynamic> data)?
  onConfirm;

  @override
  State<BookingFlowScreen> createState() => _BookingFlowScreenState();
}

class _BookingFlowScreenState extends State<BookingFlowScreen> {
  int _step = 0;

  final _problemeCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  final _prixProposeCtrl = TextEditingController();
  bool _submitting = false;
  String _paymentType = 'ESPECES';
  String _mmOperator = 'ORANGE_MONEY';
  bool _isUrgent = false;
  String _disponibilites = '';
  bool _checkingAvailability = false;
  bool? _providerAvailable;
  String _availabilityMessage = '';
  List<Map<String, dynamic>> _availableCreneaux = [];
  String _reservationReference = '';

  LatLng _mapPin = BabifixOsmLocationPicker.defaultCenter;

  /// `true` après un tap sur la carte ou « Ma position » — sinon on n'envoie pas lat/lng à l'API.
  bool _mapPinFromUser = false;
  bool _gpsAutoTried = false;
  bool _resolvingGps = false;
  GpsLocationState _gpsState = GpsLocationState.idle;
  List<Uint8List> _photos = [];

  static const _steps = ['Problème', 'Adresse', 'Disponibilité', 'Envoyé'];

  @override
  void initState() {
    super.initState();
    // GPS automatique — non bloquant.
    // Si l'utilisateur autorise, on récupère sa position + ville en
    // reverse-geocoding et on pré-remplit le champ adresse. Il pourra
    // toujours saisir une autre adresse à la main (non obligatoire).
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryAutoLocate());
  }

  Future<void> _tryAutoLocate({bool forceRefresh = false}) async {
    if (_gpsAutoTried && !forceRefresh) return;
    _gpsAutoTried = true;
    if (!mounted) return;
    setState(() {
      _resolvingGps = true;
      _gpsState = GpsLocationState.resolving;
    });
    try {
      // Vérifie la permission, demande si nécessaire
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) setState(() => _gpsState = GpsLocationState.denied);
        return;
      }
      final svcOn = await Geolocator.isLocationServiceEnabled();
      if (!svcOn) {
        if (mounted) setState(() => _gpsState = GpsLocationState.denied);
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      ).timeout(const Duration(seconds: 10));

      if (!mounted) return;
      setState(() {
        _mapPin = LatLng(pos.latitude, pos.longitude);
        _mapPinFromUser = true; // → on enverra lat/lng au backend
        _gpsState = GpsLocationState.detected;
      });
      // Reverse-geocoding → libellé lisible « Quartier, Ville » (jamais de
      // coordonnées brutes). Ne remplit que si l'utilisateur n'a rien saisi.
      await _reverseGeocodeShort(
        LatLng(pos.latitude, pos.longitude),
        overwrite: _addressCtrl.text.trim().isEmpty,
      );
    } catch (_) {
      // Échec : on bascule en état "denied" pour proposer la saisie manuelle.
      if (mounted) {
        setState(() {
          _gpsState = _gpsState == GpsLocationState.detected
              ? _gpsState
              : GpsLocationState.denied;
        });
      }
    } finally {
      if (mounted) setState(() => _resolvingGps = false);
    }
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    _msgCtrl.dispose();
    _prixProposeCtrl.dispose();
    super.dispose();
  }

  void _goTo(int step) {
    setState(() => _step = step);
  }

  // ── Reverse-geocoding « court » ────────────────────────────────────────────
  // Construit un libellé lisible (« Cocody, Abidjan ») à partir des champs
  // d'adresse Nominatim, plutôt qu'un display_name verbeux ou des coordonnées.
  int _revGeoSeq = 0;

  String _shortPlaceLabel(Map<String, dynamic> addr) {
    String pick(List<String> keys) {
      for (final k in keys) {
        final v = (addr[k] ?? '').toString().trim();
        if (v.isNotEmpty) return v;
      }
      return '';
    }

    final quartier = pick([
      'suburb',
      'neighbourhood',
      'quarter',
      'city_district',
      'residential',
      'hamlet',
    ]);
    final ville = pick([
      'city',
      'town',
      'municipality',
      'village',
      'county',
    ]);
    final region = pick(['state', 'region']);
    final parts = <String>[];
    if (quartier.isNotEmpty) parts.add(quartier);
    if (ville.isNotEmpty && ville != quartier) parts.add(ville);
    if (parts.isEmpty && region.isNotEmpty) parts.add(region);
    return parts.join(', ');
  }

  Future<void> _reverseGeocodeShort(LatLng p, {bool overwrite = true}) async {
    final seq = ++_revGeoSeq;
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?lat=${p.latitude}&lon=${p.longitude}'
        '&format=json&addressdetails=1&accept-language=fr&zoom=16',
      );
      final r = await http
          .get(url, headers: {'User-Agent': 'BABIFIX/1.0 client'})
          .timeout(const Duration(seconds: 6));
      // Une requête plus récente a pris le relais → on ignore ce résultat.
      if (!mounted || seq != _revGeoSeq) return;
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final addr = (j['address'] as Map<String, dynamic>?) ?? const {};
        var label = _shortPlaceLabel(addr);
        if (label.isEmpty) {
          label = (j['display_name'] ?? '')
              .toString()
              .split(',')
              .take(2)
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .join(', ');
        }
        if (label.isNotEmpty &&
            (overwrite || _addressCtrl.text.trim().isEmpty)) {
          setState(() => _addressCtrl.text = label);
        }
      }
    } catch (_) {
      // Silencieux : on conserve l'adresse existante, jamais de coordonnées.
    }
  }

  Future<void> _checkProviderAvailability(DateTime date) async {
    if (widget.providerId == null) return;

    setState(() {
      _checkingAvailability = true;
      _providerAvailable = null;
      _availabilityMessage = '';
    });

    try {
      final uri = Uri.parse(
        '${babifixApiBaseUrl()}/api/client/check-provider-availability'
        '?provider_id=${widget.providerId}'
        '&date=${date.toIso8601String().split('T')[0]}',
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() {
          _providerAvailable = data['available'] as bool?;
          if (data['available'] == true) {
            _availabilityMessage = 'Prestataire disponible!';
            _availableCreneaux =
                (data['creneaux'] as List?)
                    ?.map((c) => c as Map<String, dynamic>)
                    .toList() ??
                [];
          } else {
            _availabilityMessage = data['message'] as String? ?? 'Indisponible';
          }
        });
      }
    } catch (e) {
      setState(() {
        _providerAvailable = null;
        _availabilityMessage = '';
      });
    }

    setState(() => _checkingAvailability = false);
  }

  /// Vérifie auprès du serveur s'il existe déjà une prestation active avec ce
  /// prestataire (→ blocage strict) ou dans la même catégorie chez un autre
  /// prestataire (→ avertissement confirmable). Retourne `true` si on peut
  /// poursuivre la réservation, `false` si on doit l'interrompre.
  Future<bool> _precheckDuplicates() async {
    try {
      final token = await BabifixUserStore.getApiToken();
      if (token == null || token.isEmpty) return true; // login géré plus loin
      final uri =
          Uri.parse(
            '${babifixApiBaseUrl()}/api/client/reservations/check-duplicate',
          ).replace(
            queryParameters: {
              if (widget.providerId != null)
                'provider_id': '${widget.providerId}',
              'title': widget.serviceTitle,
            },
          );
      final resp = await http
          .get(uri, headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) return true; // tolérant : backend tranchera
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      final dupProvider = j['duplicate_provider'] as Map<String, dynamic>?;
      final dupCategory = j['duplicate_category'] as Map<String, dynamic>?;
      if (!mounted) return false;
      if (dupProvider != null) {
        await _showDuplicateProviderDialog(dupProvider);
        return false; // blocage strict — on ne réserve pas
      }
      if (dupCategory != null) {
        final proceed = await _showDuplicateCategoryDialog(dupCategory);
        return proceed == true;
      }
      return true;
    } catch (_) {
      return true; // en cas d'erreur réseau, on laisse le backend décider
    }
  }

  Future<void> _showDuplicateProviderDialog(Map<String, dynamic> info) {
    final ref = (info['reference'] ?? '').toString();
    final presta = (info['prestataire'] ?? 'ce prestataire').toString();
    return showDialog<void>(
      context: context,
      builder: (ctx) => _DuplicateDialog(
        accent: const Color(0xFFEF4444),
        icon: Icons.block_rounded,
        title: 'Prestation déjà en cours',
        message:
            'Vous avez déjà une prestation en cours avec $presta'
            '${ref.isNotEmpty ? ' (réf. $ref)' : ''}.\n\n'
            "Pour un bon suivi, terminez cette prestation avant d'en "
            'réserver une nouvelle avec le même prestataire.',
        primaryLabel: "J'ai compris",
        onPrimary: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  Future<bool?> _showDuplicateCategoryDialog(Map<String, dynamic> info) {
    final cat = (info['category'] ?? '').toString();
    final presta = (info['prestataire'] ?? 'un autre prestataire').toString();
    final ref = (info['reference'] ?? '').toString();
    return showDialog<bool>(
      context: context,
      builder: (ctx) => _DuplicateDialog(
        accent: const Color(0xFFF59E0B),
        icon: Icons.warning_amber_rounded,
        title: 'Prestation similaire en cours',
        message:
            'Vous avez déjà une prestation '
            '${cat.isNotEmpty ? '« $cat »' : 'de cette catégorie'} en cours '
            'avec $presta${ref.isNotEmpty ? ' (réf. $ref)' : ''}.\n\n'
            "Il est recommandé de terminer une prestation avant d'en lancer "
            'une autre dans la même catégorie. Voulez-vous tout de même '
            'continuer ?',
        secondaryLabel: 'Annuler',
        onSecondary: () => Navigator.of(ctx).pop(false),
        primaryLabel: 'Continuer quand même',
        onPrimary: () => Navigator.of(ctx).pop(true),
      ),
    );
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    // Pré-vérification anti-doublon (UX) — le backend bloque aussi en dur.
    final canProceed = await _precheckDuplicates();
    if (!canProceed) {
      if (mounted) setState(() => _submitting = false);
      return;
    }
    final data = <String, dynamic>{
      'title': widget.serviceTitle,
      'description_probleme': _problemeCtrl.text.trim(),
      'address_label': _addressCtrl.text.trim(),
      'client_message': _msgCtrl.text.trim(),
      'disponibilites_client': _disponibilites,
      'is_urgent': _isUrgent,
      'payment_type': _paymentType,
      if (_paymentType == 'MOBILE_MONEY')
        'mobile_money_operator': _mmOperator,
      if (widget.providerId != null) 'provider_id': widget.providerId,
      if (widget.providerName != null) 'prestataire_name': widget.providerName,
    };
    if (_mapPinFromUser) {
      data['latitude'] = _mapPin.latitude;
      data['longitude'] = _mapPin.longitude;
    }
    if (_photos.isNotEmpty) {
      data['photo_attachments'] = _photos
          .map((b) => 'data:image/jpeg;base64,${base64Encode(b)}')
          .toList();
    }

    debugPrint('📤 RESERVATION SUBMIT — data: ${jsonEncode(data)}');
    if (!mounted) return;
    showBabifixToast(
      context,
      type: BabifixToastType.info,
      title: 'Réservation',
      message: 'Envoi de votre demande au prestataire…',
      duration: const Duration(seconds: 2),
    );

    bool ok = false;
    String? reference;
    String? errorMsg;
    if (widget.onConfirm != null) {
      final result = await widget.onConfirm!(data);
      if (result != null) {
        ok = result['ok'] == true;
        reference = result['reference'] as String?;
        errorMsg = result['error'] as String?;
      }
    } else {
      // Pas de callback fourni (ex: ouverture depuis la fiche prestataire) :
      // on crée la réservation DIRECTEMENT via l'API. Avant, cette branche
      // simulait un faux succès → la demande n'arrivait jamais au presta.
      try {
        final token = await BabifixUserStore.getApiToken();
        if (token == null || token.isEmpty) {
          errorMsg = 'Connectez-vous pour réserver';
        } else {
          final resp = await http.post(
            Uri.parse('${babifixApiBaseUrl()}/api/client/reservations'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              ...data,
              // S'assurer que le flux devis (visible côté presta) est activé.
              'use_devis': true,
            }),
          );
          if (resp.statusCode == 201) {
            final j = jsonDecode(resp.body) as Map<String, dynamic>;
            ok = j['ok'] == true || j['reference'] != null;
            reference = j['reference'] as String?;
          } else {
            try {
              final body = jsonDecode(resp.body) as Map<String, dynamic>;
              // Privilégier le message lisible (ex: doublon) sur le code brut.
              errorMsg =
                  (body['message'] ??
                          body['error'] ??
                          'Erreur ${resp.statusCode}')
                      .toString();
            } catch (_) {
              errorMsg = 'Erreur ${resp.statusCode}';
            }
          }
        }
      } catch (e) {
        errorMsg = 'Erreur réseau : $e';
      }
    }
    if (!mounted) return;
    setState(() {
      _submitting = false;
      if (reference != null) _reservationReference = reference;
    });
    if (ok) {
      debugPrint('✅ RESERVATION OK — reference: $reference');
      if (!mounted) return;
      showBabifixToast(
        context,
        type: BabifixToastType.success,
        title: 'Demande envoyée',
        message: reference != null && reference.isNotEmpty
            ? 'Votre demande a bien été transmise (réf. $reference).'
            : 'Votre demande a bien été transmise au prestataire.',
      );
      _goTo(3);
    } else {
      debugPrint('❌ RESERVATION FAILED — error: $errorMsg');
      if (!mounted) return;
      showBabifixToast(
        context,
        type: BabifixToastType.error,
        title: 'Réservation impossible',
        message: errorMsg ?? 'Une erreur est survenue. Réessayez.',
        duration: const Duration(seconds: 4),
      );
    }
  }

  Widget _buildCurrentStep(BuildContext context, Color text, Color sub) {
    switch (_step) {
      case 0:
        return _StepProbleme(
          textColor: text,
          subColor: sub,
          problemeCtrl: _problemeCtrl,
          photos: _photos,
          onPhotosChanged: (p) => setState(() => _photos = p),
          onNext: () {
            if (_problemeCtrl.text.trim().isEmpty) {
              showBabifixToast(
        context,
        type: BabifixToastType.info,
        message: 'Décrivez votre problème.',
      );
              return;
            }
            _goTo(1);
          },
          providerName: widget.providerName,
          providerSpecialite: widget.providerSpecialite,
          providerRating: widget.providerRating,
        );
      case 1:
        return _StepAddress(
          textColor: text,
          subColor: sub,
          addressCtrl: _addressCtrl,
          msgCtrl: _msgCtrl,
          mapPin: _mapPin,
          gpsState: _gpsState,
          onGpsRefresh: () => _tryAutoLocate(forceRefresh: true),
          onMapPinChanged: (p) => setState(() {
            _mapPin = p;
            _mapPinFromUser = true;
          }),
          onMapTap: (p) {
            setState(() {
              _mapPin = p;
              _mapPinFromUser = true;
            });
            // Convertit la position en libellé lisible « Quartier, Ville ».
            _reverseGeocodeShort(p, overwrite: true);
          },
          onNext: () {
            // GPS auto fait foi : si on a une position validée par
            // l'utilisateur, on accepte même si le champ texte est
            // vide. Sinon on demande une saisie manuelle.
            final hasGps = _mapPinFromUser;
            final hasText = _addressCtrl.text.trim().isNotEmpty;
            if (!hasGps && !hasText) {
              showBabifixToast(
        context,
        type: BabifixToastType.success,
        message: "Activez votre position ou renseignez une adresse.",
      );
              return;
            }
            // Si pas de texte mais GPS dispo, on tente un libellé lisible
            // (jamais de coordonnées brutes affichées à l'utilisateur).
            if (!hasText) {
              _addressCtrl.text = 'Position sélectionnée sur la carte';
              _reverseGeocodeShort(_mapPin, overwrite: true);
            }
            _goTo(2);
          },
          onBack: () => _goTo(0),
        );
      case 2:
        return _StepDisponibilite(
          textColor: text,
          subColor: sub,
          disponibilites: _disponibilites,
          onDisponibilitesChanged: (v) => setState(() => _disponibilites = v),
          isUrgent: _isUrgent,
          onUrgentChanged: (v) => setState(() => _isUrgent = v),
          paymentType: _paymentType,
          onPaymentTypeChanged: (v) => setState(() => _paymentType = v),
          mmOperator: _mmOperator,
          onMmOperatorChanged: (v) => setState(() => _mmOperator = v),
          onConfirm: _submit,
          onBack: () => _goTo(1),
          submitting: _submitting,
          providerId: widget.providerId,
          checkingAvailability: _checkingAvailability,
          providerAvailable: _providerAvailable,
          availabilityMessage: _availabilityMessage,
          availableCreneaux: _availableCreneaux,
          onCreneauSelected: (v) => setState(() => _disponibilites = v),
          onCheckAvailability: _checkProviderAvailability,
        );
      default:
        return _StepDone(
          textColor: text,
          serviceTitle: widget.serviceTitle,
          reference: _reservationReference.isNotEmpty
              ? _reservationReference
              : null,
          providerName: widget.providerName,
          price: widget.servicePrice,
          onClose: () => Navigator.of(context).pop(),
          onOpenChat: widget.providerId != null
              ? () {
                  Navigator.of(context).pop();
                  // Navigate to chat - would need to be implemented via router
                }
              : null,
        );
    }
  }

  static const _kNavy = Color(0xFF050D1A);
  static const _kBlue = Color(0xFF4CC9F0);
  static const _kCyan = Color(0xFF4CC9F0);

  @override
  Widget build(BuildContext context) {
    // Force dark theme for the entire booking flow so AppBar, system overlays
    // and step indicators all stay consistent regardless of phone theme.
    return Theme(
      data: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: _kBlue,
          secondary: _kCyan,
          surface: Color(0xFF0A1628),
          onSurface: Colors.white,
          onSurfaceVariant: Color(0x80FFFFFF),
        ),
        scaffoldBackgroundColor: _kNavy,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF060E1C),
          foregroundColor: Colors.white,
          elevation: 0,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      child: PopScope(
        canPop: _step == 3,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          if (_step == 0) {
            final hasData = _problemeCtrl.text.isNotEmpty || _photos.isNotEmpty;
            if (hasData) {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Quitter la demande ?'),
                  content: const Text(
                    'Les informations saisies seront perdues.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Annuler'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Quitter'),
                    ),
                  ],
                ),
              );
              if (confirm == true && context.mounted) {
                Navigator.of(context).pop();
              }
            } else {
              Navigator.of(context).pop();
            }
            return;
          }
          if (_step > 0 && _step < 3) {
            _goTo(_step - 1);
          }
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Réserver'),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: _StepIndicator(steps: _steps, current: _step),
            ),
          ),
          body: SizedBox.expand(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: SizedBox.expand(
                key: ValueKey(_step),
                child: _buildCurrentStep(
                  context,
                  Colors.white,
                  const Color(0x80FFFFFF),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Step indicator ────────────────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.steps, required this.current});

  final List<String> steps;
  final int current;

  @override
  Widget build(BuildContext context) {
    final divider = Theme.of(context).dividerColor;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          for (int i = 0; i < steps.length; i++) ...[
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 4,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  color: i <= current ? BabifixDesign.cyan : divider,
                ),
              ),
            ),
            if (i < steps.length - 1) const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}

// ── Step 0 : Problème ─────────────────────────────────────────────────────────

class _StepProbleme extends StatelessWidget {
  const _StepProbleme({
    required this.textColor,
    required this.subColor,
    required this.problemeCtrl,
    required this.photos,
    required this.onPhotosChanged,
    required this.onNext,
    this.providerName,
    this.providerSpecialite,
    this.providerRating,
  });

  final Color textColor;
  final Color subColor;
  final TextEditingController problemeCtrl;
  final List<Uint8List> photos;
  final ValueChanged<List<Uint8List>> onPhotosChanged;
  final VoidCallback onNext;
  final String? providerName;
  final String? providerSpecialite;
  final double? providerRating;

  static const _kNavy = Color(0xFF050D1A);
  static const _kBlue = Color(0xFF4CC9F0);
  static const _kBlueDark = Color(0xFF1D4ED8);
  static const _kCyan = Color(0xFF4CC9F0);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kNavy,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header prestataire ───────────────────────────────────────────
            if (providerName != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _kBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _kBlue.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: _kCyan,
                      child: const Icon(Icons.person, color: _kNavy),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            providerName!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          if (providerSpecialite != null)
                            Text(
                              providerSpecialite!,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (providerRating != null) ...[
                      Row(
                        children: [
                          const Icon(
                            Icons.star,
                            color: Color(0xFFF59E0B),
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            providerRating!.toStringAsFixed(1),
                            style: const TextStyle(
                              color: Color(0xFFF59E0B),
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            // ── Titre ───────────────────────────────────────────────────────
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      colors: [
                        _kBlue.withValues(alpha: 0.25),
                        _kBlue.withValues(alpha: 0.08),
                      ],
                    ),
                  ),
                  child: const Icon(
                    Icons.build_circle_outlined,
                    color: _kCyan,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Votre problème',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Text(
                      'Décrivez ce que vous avez besoin',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 28),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0D1525),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _kBlue.withValues(alpha: 0.2)),
              ),
              child: TextField(
                controller: problemeCtrl,
                maxLines: 5,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Décrivez votre problème en quelques mots...',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () async {
                final picker = await _showImagePicker(context);
                if (picker != null && picker.isNotEmpty) {
                  onPhotosChanged([...photos, ...picker]);
                }
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1525),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _kBlue.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.add_a_photo_outlined,
                      color: _kCyan.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      photos.isEmpty
                          ? 'Ajouter des photos (optionnel)'
                          : '${photos.length} photo(s) ajoutée(s)',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: onNext,
              child: Container(
                width: double.infinity,
                height: 54,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_kBlue, _kBlueDark]),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: _kBlue.withValues(alpha: 0.45),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Center(
                  child: Text(
                    'Continuer',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
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

  Future<List<Uint8List>?> _showImagePicker(BuildContext context) async {
    return showModalBottomSheet<List<Uint8List>>(
      context: context,
      backgroundColor: const Color(0xFF0A1628),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: _kCyan),
              title: const Text(
                'Prendre une photo',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () async {
                final img = await _pickImageFromCamera();
                if (ctx.mounted) Navigator.pop(ctx, img != null ? [img] : null);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: _kCyan),
              title: const Text(
                'Choisir dans la galerie',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () async {
                final imgs = await _pickImagesFromGallery();
                if (ctx.mounted) Navigator.pop(ctx, imgs);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<Uint8List?> _pickImageFromCamera() async {
    try {
      final picker = ImagePicker();
      final XFile? img = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (img == null) return null;
      return await img.readAsBytes();
    } catch (e) {
      return null;
    }
  }

  Future<List<Uint8List>?> _pickImagesFromGallery() async {
    try {
      final picker = ImagePicker();
      final List<XFile> imgs = await picker.pickMultiImage(imageQuality: 85);
      if (imgs.isEmpty) return null;
      final bytes = <Uint8List>[];
      for (final img in imgs) {
        bytes.add(await img.readAsBytes());
      }
      return bytes;
    } catch (e) {
      return null;
    }
  }
}

class _PremiumPickerCard extends StatelessWidget {
  const _PremiumPickerCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.isSet,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool isSet;
  final VoidCallback onTap;

  static const _kBlue = Color(0xFF4CC9F0);
  static const _kCyan = Color(0xFF4CC9F0);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSet
                ? _kBlue.withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.10),
            width: isSet ? 1.5 : 1,
          ),
          boxShadow: isSet
              ? [
                  BoxShadow(
                    color: _kBlue.withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  colors: isSet
                      ? [
                          _kBlue.withValues(alpha: 0.35),
                          _kBlue.withValues(alpha: 0.12),
                        ]
                      : [
                          Colors.white.withValues(alpha: 0.08),
                          Colors.white.withValues(alpha: 0.03),
                        ],
                ),
              ),
              child: Icon(
                icon,
                color: isSet ? _kCyan : Colors.white.withValues(alpha: 0.35),
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.white.withValues(alpha: 0.40),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: isSet
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.35),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              isSet
                  ? Icons.check_circle_rounded
                  : Icons.arrow_forward_ios_rounded,
              color: isSet ? _kCyan : Colors.white.withValues(alpha: 0.25),
              size: isSet ? 20 : 16,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Step 1 : Adresse ──────────────────────────────────────────────────────────

class _StepAddress extends StatefulWidget {
  const _StepAddress({
    required this.textColor,
    required this.subColor,
    required this.addressCtrl,
    required this.msgCtrl,
    required this.mapPin,
    required this.onMapPinChanged,
    required this.onMapTap,
    required this.onNext,
    required this.onBack,
    required this.gpsState,
    required this.onGpsRefresh,
  });

  final Color textColor;
  final Color subColor;
  final TextEditingController addressCtrl;
  final TextEditingController msgCtrl;
  final LatLng mapPin;
  // Recherche / sélection d'un lieu : le libellé est déjà connu, on ne
  // re-géocode pas (sinon on écraserait l'adresse choisie).
  final ValueChanged<LatLng> onMapPinChanged;
  // Tap/déplacement sur la carte : déclenche un reverse-geocoding pour
  // afficher « Quartier, Ville » au lieu de coordonnées brutes.
  final ValueChanged<LatLng> onMapTap;
  final VoidCallback onNext;
  final VoidCallback onBack;
  final GpsLocationState gpsState;
  final VoidCallback onGpsRefresh;

  @override
  State<_StepAddress> createState() => _StepAddressState();
}

class _StepAddressState extends State<_StepAddress> {
  bool _showDetails = false;

  static const _kNavy = Color(0xFF050D1A);
  static const _kBlue = Color(0xFF4CC9F0);
  static const _kBlueDark = Color(0xFF1D4ED8);
  static const _kCyan = Color(0xFF4CC9F0);

  @override
  Widget build(BuildContext context) {
    final addressCtrl = widget.addressCtrl;
    final msgCtrl = widget.msgCtrl;
    final mapPin = widget.mapPin;
    final onMapPinChanged = widget.onMapPinChanged;
    final onBack = widget.onBack;
    final onNext = widget.onNext;
    return Theme(
      data: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: _kBlue,
          secondary: _kCyan,
          surface: Color(0xFF0A1628),
        ),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: _kCyan,
          selectionColor: Color(0x554CC9F0),
          selectionHandleColor: _kCyan,
        ),
      ),
      child: Container(
        color: _kNavy,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.viewInsetsOf(context).bottom + 28,
          ),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Titre ────────────────────────────────────────────────
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        colors: [
                          _kBlue.withValues(alpha: 0.25),
                          _kBlue.withValues(alpha: 0.08),
                        ],
                      ),
                    ),
                    child: const Icon(
                      Icons.location_on_rounded,
                      color: _kCyan,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lieu d\'intervention',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: -0.3,
                          ),
                        ),
                        Text(
                          'Indiquez l\'adresse exacte',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0x72FFFFFF),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),

              // ── Carte adresse ─────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: _kBlue.withValues(alpha: 0.18),
                          ),
                          child: const Icon(
                            Icons.edit_location_alt_rounded,
                            color: _kCyan,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Rechercher une adresse',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              'Ou touchez la carte ci-dessous',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.40),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Carte GPS animée (loading → détectée → refusée)
                    GpsLocationCard(
                      state: widget.gpsState,
                      addressText: addressCtrl.text,
                      onRefresh: widget.onGpsRefresh,
                    ),
                    const SizedBox(height: 10),
                    BabifixAddressSearchField(
                      controller: addressCtrl,
                      onPlaceSelected: (latLng, _) => onMapPinChanged(latLng),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // ── Carte OSM ─────────────────────────────────────────────
              Row(
                children: [
                  const Icon(Icons.map_rounded, color: _kCyan, size: 18),
                  const SizedBox(width: 6),
                  const Text(
                    'Positionnez le marqueur',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _kBlue.withValues(alpha: 0.30)),
                  boxShadow: [
                    BoxShadow(
                      color: _kBlue.withValues(alpha: 0.12),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BabifixOsmLocationPicker(
                    marker: mapPin,
                    onMarkerMoved: widget.onMapTap,
                    height: 230,
                  ),
                ),
              ),

              const SizedBox(height: 22),

              // ── Bouton détails optionnels ─────────────────────────────────
              GestureDetector(
                onTap: () => setState(() => _showDetails = !_showDetails),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _showDetails
                        ? _kBlue.withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _showDetails
                          ? _kBlue
                          : Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _showDetails
                            ? Icons.expand_less_rounded
                            : Icons.add_circle_outline_rounded,
                        color: _kCyan,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _showDetails
                            ? 'Masquer les détails'
                            : 'Ajouter des détails (optionnel)',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Message + Photos (dépliable) ────────────────────────────────
              if (_showDetails) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              color: _kBlue.withValues(alpha: 0.18),
                            ),
                            child: const Icon(
                              Icons.chat_bubble_outline_rounded,
                              color: _kCyan,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Détails du problème',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                'Message + photos',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white.withValues(alpha: 0.40),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D1525),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _kBlue.withValues(alpha: 0.2),
                          ),
                        ),
                        child: TextField(
                          controller: msgCtrl,
                          maxLines: 3,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Précisions, accès, contraintes...',
                            hintStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.3),
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.all(16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 28),

              // ── Boutons ───────────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: onBack,
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15),
                          ),
                        ),
                        child: const Center(
                          child: Text(
                            'Retour',
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: onNext,
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_kBlue, _kBlueDark],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: _kBlue.withValues(alpha: 0.40),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Text(
                            'Continuer',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
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
    );
  }
}

// ── Step 2 : Disponibilité ────────────────────────────────────────────────────

class _StepDisponibilite extends StatelessWidget {
  const _StepDisponibilite({
    required this.textColor,
    required this.subColor,
    required this.disponibilites,
    required this.onDisponibilitesChanged,
    required this.isUrgent,
    required this.onUrgentChanged,
    required this.paymentType,
    required this.onPaymentTypeChanged,
    required this.mmOperator,
    required this.onMmOperatorChanged,
    required this.onConfirm,
    required this.onBack,
    required this.submitting,
    this.providerId,
    this.checkingAvailability,
    this.providerAvailable,
    this.availabilityMessage,
    this.availableCreneaux = const [],
    this.onCreneauSelected,
    this.onCheckAvailability,
  });

  final Color textColor;
  final Color subColor;
  final String disponibilites;
  final ValueChanged<String> onDisponibilitesChanged;
  final bool isUrgent;
  final ValueChanged<bool> onUrgentChanged;
  final String paymentType;
  final ValueChanged<String> onPaymentTypeChanged;
  final String mmOperator;
  final ValueChanged<String> onMmOperatorChanged;
  final Future<void> Function() onConfirm;
  final VoidCallback onBack;
  final bool submitting;
  final int? providerId;
  final bool? checkingAvailability;
  final bool? providerAvailable;
  final String? availabilityMessage;
  final List<Map<String, dynamic>> availableCreneaux;
  final ValueChanged<String>? onCreneauSelected;
  final Future<void> Function(DateTime)? onCheckAvailability;

  static const _kNavy = Color(0xFF050D1A);
  static const _kBlue = Color(0xFF4CC9F0);
  static const _kBlueDark = Color(0xFF1D4ED8);
  static const _kCyan = Color(0xFF4CC9F0);
  static const _kRed = Color(0xFFDC2626);

  @override
  Widget build(BuildContext context) {

    return Container(
      color: _kNavy,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      colors: [
                        _kBlue.withValues(alpha: 0.25),
                        _kBlue.withValues(alpha: 0.08),
                      ],
                    ),
                  ),
                  child: const Icon(
                    Icons.schedule_rounded,
                    color: _kCyan,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Disponibilités',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Text(
                      'Quand êtes-vous disponible ?',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (providerId != null && onCheckAvailability != null) ...[
              const Text(
                'Vérifier la disponibilité du prestataire',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () async {
                  final now = DateTime.now();
                  final date = await showDatePicker(
                    context: context,
                    initialDate: now.add(const Duration(days: 1)),
                    firstDate: now,
                    lastDate: now.add(const Duration(days: 60)),
                  );
                  if (date != null) {
                    onCheckAvailability?.call(date);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1525),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _kBlue.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        color: _kCyan.withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Vérifier disponibilité',
                        style: TextStyle(color: Colors.white70),
                      ),
                      const Spacer(),
                      if (checkingAvailability == true)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: BabifixRingLoader.cyan(size: 28),
                        )
                      else if (providerAvailable == true)
                        const Icon(Icons.check_circle, color: Colors.green)
                      else if (providerAvailable == false)
                        const Icon(Icons.cancel, color: Colors.red),
                    ],
                  ),
                ),
              ),
              if (availabilityMessage != null &&
                  availabilityMessage!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:
                        (providerAvailable == true
                                ? Colors.green
                                : providerAvailable == false
                                ? Colors.red
                                : _kBlue)
                            .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color:
                          (providerAvailable == true
                                  ? Colors.green
                                  : providerAvailable == false
                                  ? Colors.red
                                  : _kBlue)
                              .withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    availabilityMessage!,
                    style: TextStyle(
                      color: providerAvailable == true
                          ? Colors.green
                          : providerAvailable == false
                          ? Colors.red
                          : Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ],
            if (availableCreneaux.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Text(
                'Créneaux disponibles',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in availableCreneaux)
                    _CreneauChip(
                      label: c['label'] as String? ?? 'Créneau',
                      timeRange: c['time_range'] as String? ?? '',
                      selected: disponibilites == c['id'].toString(),
                      onTap: () => onCreneauSelected?.call(
                        c['id'].toString(),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            // ── Mode de paiement ──────────────────────────────────────────
            const Text(
              'Mode de paiement',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _PaymentOption(
                    icon: Icons.payments_rounded,
                    label: 'Espèces',
                    selected: paymentType == 'ESPECES',
                    onTap: () => onPaymentTypeChanged('ESPECES'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PaymentOption(
                    icon: Icons.phone_android_rounded,
                    label: 'Mobile Money',
                    selected: paymentType == 'MOBILE_MONEY',
                    onTap: () => onPaymentTypeChanged('MOBILE_MONEY'),
                  ),
                ),
              ],
            ),
            if (paymentType == 'MOBILE_MONEY') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _MmOperatorChip(
                      label: 'Orange',
                      color: const Color(0xFFFF6600),
                      selected: mmOperator == 'ORANGE_MONEY',
                      onTap: () => onMmOperatorChanged('ORANGE_MONEY'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MmOperatorChip(
                      label: 'MTN',
                      color: const Color(0xFFFFCC00),
                      selected: mmOperator == 'MTN_MOMO',
                      onTap: () => onMmOperatorChanged('MTN_MOMO'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MmOperatorChip(
                      label: 'Wave',
                      color: const Color(0xFF1A9BFC),
                      selected: mmOperator == 'WAVE',
                      onTap: () => onMmOperatorChanged('WAVE'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MmOperatorChip(
                      label: 'Moov',
                      color: const Color(0xFF007AC1),
                      selected: mmOperator == 'MOOV',
                      onTap: () => onMmOperatorChanged('MOOV'),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            GestureDetector(
              onTap: () => onUrgentChanged(!isUrgent),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isUrgent
                      ? _kRed.withValues(alpha: 0.15)
                      : const Color(0xFF0D1525),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isUrgent ? _kRed : _kBlue.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isUrgent
                          ? Icons.warning_rounded
                          : Icons.warning_amber_rounded,
                      color: isUrgent ? _kRed : _kCyan.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Intervention urgente',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'Le prestataire intervient dès que possible',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: isUrgent,
                      onChanged: onUrgentChanged,
                      activeThumbColor: _kRed,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: onBack,
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15),
                        ),
                      ),
                      child: const Center(
                        child: Text(
                          'Retour',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: submitting ? null : onConfirm,
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_kBlue, _kBlueDark],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: _kBlue.withValues(alpha: 0.40),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Center(
                        child: submitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: BabifixRingLoader.cyan(size: 28),
                              )
                            : const Text(
                                'Envoyer la demande',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CreneauChip extends StatelessWidget {
  const _CreneauChip({
    required this.label,
    required this.timeRange,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String timeRange;
  final bool selected;
  final VoidCallback onTap;

  static const _kCyan = Color(0xFF4CC9F0);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? _kCyan.withValues(alpha: 0.2) : const Color(0xFF0D1525),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? _kCyan : Colors.white.withValues(alpha: 0.1),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.access_time_rounded,
                  size: 16,
                  color: selected ? _kCyan : Colors.white.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? _kCyan : Colors.white70,
                  ),
                ),
              ],
            ),
            if (timeRange.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                timeRange,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.35),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PaymentModeTile extends StatelessWidget {
  const _PaymentModeTile({
    required this.selected,
    required this.onTap,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.textColor,
    required this.subColor,
    this.footer,
  });

  final bool selected;
  final VoidCallback onTap;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color textColor;
  final Color subColor;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              width: selected ? 2 : 1,
              color: selected
                  ? BabifixDesign.cyan
                  : theme.dividerColor.withValues(alpha: 0.65),
            ),
            color: selected
                ? BabifixDesign.cyan.withValues(alpha: 0.08)
                : cs.surface,
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: BabifixDesign.cyan.withValues(alpha: 0.18),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 168),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            BabifixDesign.cyan.withValues(alpha: 0.2),
                            BabifixDesign.cyan.withValues(alpha: 0.05),
                          ],
                        ),
                      ),
                      child: Icon(icon, color: BabifixDesign.iconOnDark, size: 22),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: subColor,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
                footer ?? const SizedBox(height: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MmOperatorLogoChip extends StatelessWidget {
  const _MmOperatorLogoChip({
    required this.methodId,
    required this.selected,
    required this.onTap,
  });

  final String methodId;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              width: selected ? 2 : 1,
              color: selected
                  ? BabifixDesign.cyan
                  : theme.dividerColor.withValues(alpha: 0.6),
            ),
            color: selected
                ? BabifixDesign.cyan.withValues(alpha: 0.1)
                : cs.surface,
          ),
          child: BabifixPaymentMethodLogo(methodId: methodId, height: 30),
        ),
      ),
    );
  }
}

// ── Bannière chip (ligne d'info dans le header gradient) ─────────────────────

class _BannerChip extends StatelessWidget {
  const _BannerChip({required this.icon, required this.label, this.maxWidth});
  final IconData icon;
  final String label;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    Widget text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12,
        color: Colors.white.withValues(alpha: 0.85),
        fontWeight: FontWeight.w500,
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: Colors.white.withValues(alpha: 0.6)),
        const SizedBox(width: 5),
        maxWidth != null
            ? ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth!),
                child: text,
              )
            : Flexible(child: text),
      ],
    );
  }
}

// ── Ligne de détail premium ───────────────────────────────────────────────────

class _SummaryRow2 extends StatelessWidget {
  const _SummaryRow2({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.iconBgDark,
    required this.label,
    required this.value,
    required this.isLight,
    required this.textColor,
    required this.subColor,
    this.valueMaxLines,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final Color iconBgDark;
  final String label;
  final String value;
  final bool isLight;
  final Color textColor;
  final Color subColor;
  final int? valueMaxLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isLight ? iconBg : iconBgDark,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 22, color: iconColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: subColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: valueMaxLines,
                  overflow: valueMaxLines != null
                      ? TextOverflow.ellipsis
                      : null,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Step 3 : Confirmation ─────────────────────────────────────────────────────

class _StepDone extends StatelessWidget {
  const _StepDone({
    required this.textColor,
    required this.serviceTitle,
    required this.onClose,
    this.reference,
    this.providerName,
    this.price,
    this.onOpenChat,
  });

  final Color textColor;
  final String serviceTitle;
  final VoidCallback onClose;
  final String? reference;
  final String? providerName;
  final int? price;
  final VoidCallback? onOpenChat;

  @override
  Widget build(BuildContext context) {
    final sub = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 700),
            tween: Tween(begin: 0, end: 1),
            curve: Curves.elasticOut,
            builder: (_, v, __) => Transform.scale(
              scale: v,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: BabifixDesign.cyan.withValues(alpha: 0.15),
                ),
                child: Icon(
                  Icons.check_circle_rounded,
                  size: 60,
                  color: BabifixDesign.iconOnDark,
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'Demande envoyée !',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: textColor,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Votre demande a été transmise au prestataire. '
            'Vous recevrez un devis sous peu.',
            textAlign: TextAlign.center,
            style: TextStyle(color: sub, height: 1.5, fontSize: 15),
          ),
          if (reference != null) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Column(
                children: [
                  const Text(
                    'Référence de votre demande',
                    style: TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    reference!,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF4CC9F0),
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (providerName != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onOpenChat,
                icon: const Icon(Icons.chat_bubble_outline),
                label: Text('Discuter avec $providerName'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF4CC9F0),
                  side: const BorderSide(color: Color(0xFF4CC9F0)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onClose,
              child: const Text('Retour à l\'accueil'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentOption extends StatelessWidget {
  const _PaymentOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF4CC9F0).withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? const Color(0xFF4CC9F0)
                : Colors.white.withValues(alpha: 0.1),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? const Color(0xFF4CC9F0) : Colors.white54, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? const Color(0xFF4CC9F0) : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MmOperatorChip extends StatelessWidget {
  const _MmOperatorChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? color : Colors.white.withValues(alpha: 0.1), width: selected ? 2 : 1),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: selected ? color : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }
}

/// Dialogue premium réutilisable pour l'anti-doublon de réservation
/// (blocage « même prestataire » ou avertissement « même catégorie »).
class _DuplicateDialog extends StatelessWidget {
  const _DuplicateDialog({
    required this.accent,
    required this.icon,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final Color accent;
  final IconData icon;
  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF0B1B34);
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: accent, size: 32),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: navy,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF475569),
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 22),
            ElevatedButton(
              onPressed: onPrimary,
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                primaryLabel,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (secondaryLabel != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: onSecondary,
                style: TextButton.styleFrom(
                  foregroundColor: navy,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(
                  secondaryLabel!,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
