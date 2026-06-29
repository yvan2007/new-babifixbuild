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
import '../auth/auth_screen.dart';
import '../../shared/widgets/babifix_suggestion_chips.dart';
import '../../shared/widgets/address_search_field.dart';
import '../../shared/widgets/babifix_osm_map.dart';
import '../../shared/widgets/gps_location_card.dart';
import '../../shared/widgets/payment_method_logo.dart';
import '../../shared/widgets/babifix_ring_loader.dart';
import '../../shared/widgets/babifix_snackbar.dart';
import '../../shared/geo_utils.dart';

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
  // Point de repère libre saisi par le client (ex : « à côté de la pharmacie
  // Saint-Joseph », « en face de l'école Sainte-Marie »). Affiché en
  // surbrillance dans la fiche prestataire — c'est souvent la donnée la
  // plus utile pour trouver le client sur place.
  final _repereCtrl = TextEditingController();
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
  // Date prévue choisie par le client (envoyée comme scheduled_date) → sert à
  // empêcher le presta de démarrer avant le jour prévu.
  DateTime? _selectedDate;
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
  // Carnet d'adresses du client (Maison, Bureau…).
  List<Map<String, dynamic>> _savedAddresses = [];

  void initState() {
    super.initState();
    // GPS automatique — non bloquant.
    // Si l'utilisateur autorise, on récupère sa position + ville en
    // reverse-geocoding et on pré-remplit le champ adresse. Il pourra
    // toujours saisir une autre adresse à la main (non obligatoire).
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryAutoLocate());
    _loadSavedAddresses();
  }

  Future<void> _loadSavedAddresses() async {
    try {
      final r = await BabifixUserStore.authGet('/api/client/addresses');
      if (r.statusCode == 200 && mounted) {
        final d = jsonDecode(r.body) as Map<String, dynamic>;
        setState(() {
          _savedAddresses =
              List<Map<String, dynamic>>.from(d['addresses'] ?? []);
        });
      }
    } catch (_) {}
  }

  /// Le client choisit une adresse enregistrée → on place le pin dessus.
  void _applySavedAddress(Map<String, dynamic> a) {
    final lat = (a['latitude'] as num?)?.toDouble();
    final lon = (a['longitude'] as num?)?.toDouble();
    if (lat == null || lon == null) return;
    setState(() {
      _mapPin = LatLng(lat, lon);
      _mapPinFromUser = true;
      _addressCtrl.text = '${a['address_label'] ?? a['label'] ?? ''}'.trim();
      _repereCtrl.text = '${a['address_repere'] ?? ''}'.trim();
    });
    _mapCtrlMoveSafe(_mapPin);
    showBabifixToast(context,
        type: BabifixToastType.success,
        message: 'Adresse « ${a['label']} » sélectionnée.');
  }

  void _mapCtrlMoveSafe(LatLng p) {
    // La carte se recadrera via mapPin (passé en paramètre au widget enfant).
  }

  /// Enregistre le lieu actuellement choisi (pin) dans le carnet.
  Future<void> _saveCurrentLocation() async {
    final labelCtrl = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A1628),
        title: const Text('Enregistrer ce lieu',
            style: TextStyle(color: Colors.white, fontSize: 17)),
        content: TextField(
          controller: labelCtrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Maison, Bureau, Chez maman…',
            hintStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, labelCtrl.text.trim()),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (label == null || label.isEmpty) return;
    try {
      final r = await BabifixUserStore.authPost(
        '/api/client/addresses',
        body: jsonEncode({
          'label': label,
          'latitude': _mapPin.latitude,
          'longitude': _mapPin.longitude,
          'address_label': _addressCtrl.text.trim(),
          'address_repere': _repereCtrl.text.trim(),
          'is_default': _savedAddresses.isEmpty,
        }),
      );
      if (r.statusCode == 201) {
        await _loadSavedAddresses();
        if (mounted) {
          showBabifixToast(context,
              type: BabifixToastType.success,
              message: 'Lieu « $label » enregistré.');
        }
      }
    } catch (_) {}
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
      // Garde-fou : si le GPS (émulateur) est hors CI, on retombe sur Abidjan
      // pour éviter de stocker des coordonnées (37, -122) dans la réservation.
      final LatLng safePin = isInCotedIvoire(pos.latitude, pos.longitude)
          ? LatLng(pos.latitude, pos.longitude)
          : const LatLng(kAbidjanLat, kAbidjanLon);
      setState(() {
        _mapPin = safePin;
        _mapPinFromUser = true; // → on enverra lat/lng au backend
        _gpsState = GpsLocationState.detected;
      });
      // Reverse-geocoding → libellé lisible « Quartier, Ville » (jamais de
      // coordonnées brutes). Ne remplit que si l'utilisateur n'a rien saisi.
      await _reverseGeocodeShort(
        safePin,
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
    _repereCtrl.dispose();
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

    // Rue + numéro (essentiels pour qu'un artisan puisse trouver l'adresse).
    final house = pick(['house_number']);
    final road = pick(['road', 'street', 'pedestrian', 'footway', 'path']);
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
    // 1. Rue (+ numéro si dispo) — la plus précise
    if (road.isNotEmpty) {
      parts.add(house.isNotEmpty ? '$house $road' : road);
    }
    // 2. Quartier — repère intermédiaire
    if (quartier.isNotEmpty && !parts.contains(quartier)) parts.add(quartier);
    // 3. Ville — toujours utile au cas où l'artisan vient d'ailleurs
    if (ville.isNotEmpty && !parts.contains(ville)) parts.add(ville);
    // 4. Fallback : si rien d'autre, au moins la région
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
      _selectedDate = date;
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
      // L'endpoint exige un token client → on l'envoie (sinon 401 + l'écran
      // de dispo restait vide).
      final token = await BabifixUserStore.getApiToken();
      final resp = await http.get(
        uri,
        headers: token != null ? {'Authorization': 'Bearer $token'} : null,
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() {
          _providerAvailable = data['available'] as bool?;
          if (data['available'] == true) {
            // Avis NON bloquant : si le presta a déjà une intervention ce
            // jour-là, on le signale + on propose d'autres jours (optionnel).
            if (data['busy_that_day'] == true) {
              final sugg = (data['suggested_dates'] as List?)
                      ?.map((e) => '$e')
                      .toList() ??
                  const [];
              final notice = (data['notice'] as String?) ??
                  'Ce prestataire a déjà une intervention ce jour-là.';
              _availabilityMessage = sugg.isNotEmpty
                  ? '$notice\nJours libres : ${sugg.join(' · ')}'
                  : notice;
            } else {
              _availabilityMessage = 'Prestataire disponible !';
            }
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
      'address_repere': _repereCtrl.text.trim(),
      'client_message': _msgCtrl.text.trim(),
      'disponibilites_client': _disponibilites,
      if (_selectedDate != null)
        'scheduled_date':
            _selectedDate!.toIso8601String().split('T')[0],
      'is_urgent': _isUrgent,
      'payment_type': _paymentType,
      // NB : on n'envoie PAS l'opérateur Mobile Money ici. Le client le
      // choisira au moment du paiement, une fois le devis reçu (montant connu).
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
        var token = await BabifixUserStore.getApiToken();
        if ((token == null || token.isEmpty) && mounted) {
          // Pas connecté → on ouvre l'écran d'auth ; au retour (connecté), on
          // RELANCE automatiquement la création (avant : erreur sèche, le client
          // devait tout recommencer sa réservation).
          bool loggedIn = false;
          await Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => AuthScreen(
                onAuthSuccess: () {
                  loggedIn = true;
                  Navigator.of(context).maybePop();
                },
              ),
            ),
          );
          if (loggedIn) token = await BabifixUserStore.getApiToken();
        }
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
          repereCtrl: _repereCtrl,
          msgCtrl: _msgCtrl,
          mapPin: _mapPin,
          gpsState: _gpsState,
          onGpsRefresh: () => _tryAutoLocate(forceRefresh: true),
          savedAddresses: _savedAddresses,
          onPickSaved: _applySavedAddress,
          onUseCurrent: () => _tryAutoLocate(forceRefresh: true),
          onSaveCurrent: _saveCurrentLocation,
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

/// Suggestions d'« ajout rapide » adaptées à la catégorie/spécialité du
/// prestataire (déduites par mots-clés). Repli générique si non reconnu.
List<String> babifixCategorySuggestions(String? specialite) {
  final s = (specialite ?? '').toLowerCase();
  bool has(List<String> kws) => kws.any((k) => s.contains(k));
  if (has(['plomb', 'fuite', 'sanitaire', 'eau'])) {
    return ['Fuite d\'eau', 'Robinet qui goutte', 'WC bouché',
      'Chauffe-eau en panne', 'Installation sanitaire', 'C\'est urgent'];
  }
  if (has(['élect', 'elect', 'courant'])) {
    return ['Panne de courant', 'Prise défectueuse', 'Court-circuit',
      'Installation de prise', 'Tableau électrique', 'C\'est urgent'];
  }
  if (has(['ménage', 'menage', 'nettoy', 'propret'])) {
    return ['Ménage complet', 'Nettoyage après travaux', 'Vitres',
      'Repassage', 'Grand ménage', 'Entretien régulier'];
  }
  if (has(['menuis', 'parquet', 'meuble', 'bois'])) {
    return ['Meuble à réparer', 'Porte qui coince', 'Pose de parquet',
      'Étagère à monter', 'Sur-mesure', 'Réparation'];
  }
  if (has(['déménag', 'demenag', 'manuten', 'transport'])) {
    return ['Déménagement appartement', 'Quelques cartons', 'Meubles lourds',
      'Besoin d\'un camion', 'Étage sans ascenseur', 'C\'est urgent'];
  }
  if (has(['peint', 'enduit'])) {
    return ['Peinture d\'une pièce', 'Tout l\'appartement', 'Reprise de fissures',
      'Plafond', 'Extérieur', 'Demander un devis'];
  }
  if (has(['clim', 'froid', 'réfrig', 'refrig'])) {
    return ['Clim ne refroidit plus', 'Installation de clim', 'Entretien / recharge',
      'Bruit anormal', 'Fuite', 'C\'est urgent'];
  }
  if (has(['jardin', 'espace vert', 'gazon', 'tonte', 'élagage'])) {
    return ['Tonte de pelouse', 'Taille de haie', 'Débroussaillage',
      'Élagage', 'Entretien régulier', 'Nettoyage jardin'];
  }
  if (has(['coiff', 'beaut', 'esthét', 'esthet', 'maquill'])) {
    return ['À domicile', 'Coupe', 'Coiffure événement', 'Soins',
      'Pour femme', 'Pour homme'];
  }
  if (has(['mécan', 'mecan', 'auto', 'voiture', 'garage'])) {
    return ['Panne moteur', 'Vidange', 'Freins', 'Batterie',
      'Diagnostic', 'Dépannage sur place'];
  }
  if (has(['électroménager', 'electromenager', 'frigo', 'machine'])) {
    return ['Appareil en panne', 'Ne s\'allume plus', 'Bruit anormal',
      'Diagnostic', 'Pièce à changer', 'C\'est urgent'];
  }
  // Repli générique
  return ['Ça ne fonctionne plus', 'Réparation', 'Installation à faire',
    'Entretien', 'Diagnostic', 'C\'est urgent'];
}

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
            const SizedBox(height: 10),
            // Bulles : suggestions ADAPTÉES à la catégorie du prestataire.
            BabifixSuggestionChips(
              controller: problemeCtrl,
              accent: _kBlue,
              title: 'Ajout rapide',
              suggestions: babifixCategorySuggestions(providerSpecialite),
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
    required this.repereCtrl,
    required this.msgCtrl,
    required this.mapPin,
    required this.onMapPinChanged,
    required this.onMapTap,
    required this.onNext,
    required this.onBack,
    required this.gpsState,
    required this.onGpsRefresh,
    required this.savedAddresses,
    required this.onPickSaved,
    required this.onUseCurrent,
    required this.onSaveCurrent,
  });

  // Carnet d'adresses du client (Maison, Bureau…) + actions.
  final List<Map<String, dynamic>> savedAddresses;
  final ValueChanged<Map<String, dynamic>> onPickSaved;
  final VoidCallback onUseCurrent;
  final VoidCallback onSaveCurrent;

  final Color textColor;
  final Color subColor;
  final TextEditingController addressCtrl;
  // Point de repère libre saisi par le client — affiché en surbrillance
  // dans la fiche prestataire (donnée la plus précieuse sur le terrain).
  final TextEditingController repereCtrl;
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

  IconData _iconForLabel(String label) {
    final l = label.toLowerCase();
    if (l.contains('maison') || l.contains('domicile') || l.contains('chez')) {
      return Icons.home_rounded;
    }
    if (l.contains('bureau') || l.contains('travail')) {
      return Icons.work_rounded;
    }
    return Icons.place_rounded;
  }

  /// Sélecteur intelligent : « Je suis sur place » (GPS actuel), ou une adresse
  /// enregistrée (Maison, Bureau…), ou enregistrer le lieu choisi.
  Widget _buildAddressSourceSelector() {
    final chips = <Widget>[
      // Position actuelle
      _sourceChip(
        icon: Icons.my_location_rounded,
        label: 'Je suis sur place',
        onTap: widget.onUseCurrent,
        highlight: true,
      ),
      // Adresses enregistrées
      ...widget.savedAddresses.map((a) => _sourceChip(
            icon: _iconForLabel('${a['label'] ?? ''}'),
            label: '${a['label'] ?? 'Adresse'}',
            onTap: () => widget.onPickSaved(a),
          )),
      // Enregistrer le lieu actuel
      _sourceChip(
        icon: Icons.bookmark_add_rounded,
        label: 'Enregistrer ce lieu',
        onTap: widget.onSaveCurrent,
        dashed: true,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.tips_and_updates_rounded, size: 15, color: _kCyan),
            const SizedBox(width: 6),
            Text(
              'Où aura lieu la prestation ?',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Choisissez votre position actuelle ou une adresse enregistrée.',
          style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.45)),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: chips.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => chips[i],
          ),
        ),
      ],
    );
  }

  Widget _sourceChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool highlight = false,
    bool dashed = false,
  }) {
    final bg = highlight
        ? _kBlue.withValues(alpha: 0.18)
        : Colors.white.withValues(alpha: 0.06);
    final border = dashed
        ? _kCyan.withValues(alpha: 0.45)
        : (highlight ? _kBlue : Colors.white.withValues(alpha: 0.14));
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border, width: 1),
        ),
        child: Row(
          children: [
            Icon(icon, size: 15, color: highlight ? _kCyan : Colors.white70),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: highlight ? Colors.white : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

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
              const SizedBox(height: 16),

              // ── Sélecteur intelligent : où aura lieu la prestation ? ──
              _buildAddressSourceSelector(),
              const SizedBox(height: 16),

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
                    const SizedBox(height: 12),
                    // ── Champ Point de repère (libre, optionnel) ──────────
                    // Affiché en surbrillance dans la fiche prestataire :
                    // c'est souvent l'info la plus utile pour trouver le
                    // client sur place (« en face de la pharmacie X »).
                    _RepereTextField(controller: widget.repereCtrl),
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
            if (providerId != null) ...[
              // Sélecteur UNIQUE de disponibilité : choisir un jour ici vérifie
              // la dispo ET enregistre la date prévue (plus de second champ
              // « Vérifier la disponibilité » redondant).
              _AvailabilityCalendar(
                providerId: providerId!,
                selectedLabel: disponibilites,
                onPick: onDisponibilitesChanged,
                onDateSelected: onCheckAvailability,
              ),
              // Message de résultat (disponible / conflit + jours libres) affiché
              // juste sous le calendrier après le choix d'un jour.
              if (availabilityMessage != null &&
                  availabilityMessage!.isNotEmpty) ...[
                const SizedBox(height: 12),
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
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 15, color: _kBlue.withValues(alpha: 0.85)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      "Vous choisirez l'opérateur (Orange, MTN, Wave, Moov) au "
                      "moment du paiement, une fois le devis reçu.",
                      style: TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          color: Colors.white.withValues(alpha: 0.6)),
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

// ─────────────────────────────────────────────────────────────────────────────
// _RepereTextField — champ texte « Point de repère » avec icône pin verte,
// libellé clair et placeholder concret. Optionnel mais fortement recommandé
// pour aider l'artisan à trouver le client sur place.
// ─────────────────────────────────────────────────────────────────────────────
class _RepereTextField extends StatelessWidget {
  const _RepereTextField({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF22C55E);
    return Container(
      decoration: BoxDecoration(
        color: green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: green.withValues(alpha: 0.30), width: 1.2),
      ),
      child: TextField(
        controller: controller,
        maxLength: 200,
        maxLines: 2,
        minLines: 1,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          isDense: true,
          counterText: '',
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          border: InputBorder.none,
          prefixIcon: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: green.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.pin_drop_rounded, size: 18, color: green),
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 0, minHeight: 0),
          labelText: 'Point de repère (optionnel)',
          labelStyle: const TextStyle(
            color: green,
            fontWeight: FontWeight.w700,
            fontSize: 12,
            letterSpacing: 0.4,
          ),
          hintText: 'ex : en face de la pharmacie Saint-Joseph',
          hintStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 12.5,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }
}

// ── Calendrier de disponibilité animé (client) ──────────────────────────────
// Lit /api/public/providers/<id>/availability/ et affiche les prochains jours.
// Les jours où le prestataire a des créneaux (et n'est pas en congé) sont
// mis en avant et cliquables ; on choisit ensuite un créneau horaire.
class _AvailabilityCalendar extends StatefulWidget {
  const _AvailabilityCalendar({
    required this.providerId,
    required this.selectedLabel,
    required this.onPick,
    this.onDateSelected,
  });

  final int providerId;
  final String selectedLabel;
  final ValueChanged<String> onPick;

  /// Appelé avec la date choisie quand on tape un jour disponible — sert à
  /// vérifier la dispo et à enregistrer la date prévue (plus besoin d'un second
  /// sélecteur « Vérifier la disponibilité »).
  final ValueChanged<DateTime>? onDateSelected;

  @override
  State<_AvailabilityCalendar> createState() => _AvailabilityCalendarState();
}

class _AvailabilityCalendarState extends State<_AvailabilityCalendar> {
  static const _kCyan = Color(0xFF4CC9F0);
  static const _kNavy = Color(0xFF050D1A);
  static const _kCard = Color(0xFF0D1525);
  static const _wd = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

  bool _loading = true;
  bool _hasAvailability = false;
  bool _error = false;
  List<Map<String, dynamic>> _days = [];
  int _selectedDayIndex = -1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final resp = await http.get(
        Uri.parse(
          '${babifixApiBaseUrl()}/api/public/providers/${widget.providerId}/availability/',
        ),
      );
      if (resp.statusCode == 200) {
        final j = jsonDecode(resp.body) as Map<String, dynamic>;
        final days =
            ((j['days'] as List?) ?? const []).cast<Map<String, dynamic>>();
        if (mounted) {
          setState(() {
            _hasAvailability = j['has_availability'] == true;
            _days = days.take(14).toList();
            _loading = false;
          });
        }
      } else if (mounted) {
        setState(() {
          _error = true;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = true;
          _loading = false;
        });
      }
    }
  }

  String _seg(String iso, int i) {
    final p = iso.split('-');
    return p.length == 3 ? p[i] : '';
  }

  void _pickSlot(Map<String, dynamic> day, Map<String, dynamic> slot) {
    final iso = '${day['date']}';
    final wd = (day['weekday'] as num?)?.toInt() ?? 0;
    final label =
        '${_wd[wd]} ${_seg(iso, 2)}/${_seg(iso, 1)} · ${slot['start']}–${slot['end']}';
    widget.onPick(label);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.event_available_rounded, color: _kCyan, size: 18),
            const SizedBox(width: 8),
            const Text(
              'Disponibilités du prestataire',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: BabifixRingLoader.cyan(size: 28)),
          )
        else if (_error || !_hasAvailability)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kCyan.withValues(alpha: 0.18)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    color: _kCyan.withValues(alpha: 0.8), size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _error
                        ? "Disponibilités indisponibles pour le moment. Indiquez vos préférences ci-dessous."
                        : "Ce prestataire n'a pas encore publié ses créneaux. Indiquez vos préférences ci-dessous.",
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          )
        else ...[
          SizedBox(
            height: 86,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _days.length,
              itemBuilder: (_, i) => _dayChip(i),
            ),
          ),
          _buildSlots(),
        ],
      ],
    );
  }

  Widget _dayChip(int index) {
    final day = _days[index];
    final available = day['available'] == true;
    final blocked = day['blocked'] == true;
    final selected = index == _selectedDayIndex;
    final iso = '${day['date']}';
    final wd = (day['weekday'] as num?)?.toInt() ?? 0;
    final onLight = selected ? _kNavy : null;
    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 300 + index * 35),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: 1),
      builder: (_, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, (1 - v) * 14), child: child),
      ),
      child: GestureDetector(
        onTap: available
            ? () {
                final newIndex = selected ? -1 : index;
                setState(() => _selectedDayIndex = newIndex);
                if (newIndex >= 0) {
                  // Date choisie → vérif dispo + enregistrement de la date prévue.
                  final d = DateTime.tryParse('${day['date']}');
                  if (d != null) widget.onDateSelected?.call(d);
                }
              }
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 54,
          margin: const EdgeInsets.only(right: 10),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? _kCyan
                : (available ? _kCard : Colors.white.withValues(alpha: 0.03)),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? _kCyan
                  : (available
                      ? const Color(0xFF22C55E).withValues(alpha: 0.45)
                      : Colors.white.withValues(alpha: 0.06)),
              width: available && !selected ? 1.3 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _wd[wd],
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: onLight ??
                      (available ? Colors.white70 : Colors.white24),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _seg(iso, 2),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color:
                      onLight ?? (available ? Colors.white : Colors.white24),
                ),
              ),
              const SizedBox(height: 5),
              // Indicateur d'état clair : ✓ vert = disponible · ✕ gris =
              // indisponible · cadenas = congé bloqué.
              if (blocked)
                const Icon(Icons.lock_rounded, size: 13, color: Color(0xFFEF4444))
              else if (available)
                Icon(Icons.check_circle_rounded,
                    size: 13,
                    color: selected ? _kNavy : const Color(0xFF22C55E))
              else
                const Icon(Icons.cancel_rounded,
                    size: 13, color: Colors.white24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSlots() {
    if (_selectedDayIndex < 0 || _selectedDayIndex >= _days.length) {
      return const SizedBox.shrink();
    }
    final day = _days[_selectedDayIndex];
    final slots = ((day['slots'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    final iso = '${day['date']}';
    final wd = (day['weekday'] as num?)?.toInt() ?? 0;
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      child: Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Créneaux du ${_wd[wd]} ${_seg(iso, 2)}/${_seg(iso, 1)}',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Colors.white60,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in slots)
                  _slotChip(day, s,
                      '${_wd[wd]} ${_seg(iso, 2)}/${_seg(iso, 1)} · ${s['start']}–${s['end']}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _slotChip(
      Map<String, dynamic> day, Map<String, dynamic> slot, String label) {
    final selected = widget.selectedLabel == label;
    return GestureDetector(
      onTap: () => _pickSlot(day, slot),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? _kCyan : _kCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? _kCyan : _kCyan.withValues(alpha: 0.25),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule_rounded,
                size: 15, color: selected ? _kNavy : _kCyan),
            const SizedBox(width: 6),
            Text(
              '${slot['start']} – ${slot['end']}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: selected ? _kNavy : Colors.white,
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 6),
              const Icon(Icons.check_rounded, size: 15, color: _kNavy),
            ],
          ],
        ),
      ),
    );
  }
}
