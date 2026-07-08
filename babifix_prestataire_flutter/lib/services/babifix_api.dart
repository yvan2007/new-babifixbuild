/// Clients API BABIFIX (prestataire) — Phase F (escrow), B (catalogue),
/// D (calls), C (chat enrichi), G (reçu PDF).
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../babifix_api_config.dart';
import '../models/babifix_models.dart';
import '../shared/services/babifix_user_store.dart';

class BabifixApiException implements Exception {
  final int statusCode;
  final String code;
  final String message;
  final Map<String, dynamic>? body;
  BabifixApiException(this.statusCode, this.code, this.message, [this.body]);

  @override
  String toString() => 'BabifixApi $statusCode/$code: $message';
}

Map<String, dynamic> _decode(http.Response r) {
  if (r.body.isEmpty) return {};
  try {
    final d = jsonDecode(r.body);
    return d is Map<String, dynamic> ? d : {};
  } catch (_) {
    return {};
  }
}

void _ensureOk(http.Response r) {
  if (r.statusCode >= 200 && r.statusCode < 300) return;
  final j = _decode(r);
  throw BabifixApiException(
    r.statusCode,
    (j['error'] ?? 'http_error').toString(),
    (j['message'] ?? j['detail'] ?? r.reasonPhrase ?? 'Erreur réseau').toString(),
    j,
  );
}

// ---------------------------------------------------------------------------
// Escrow API
// ---------------------------------------------------------------------------
class EscrowApi {
  static Future<EscrowQuote> quote(String reference) async {
    final r = await BabifixUserStore.authGet(
      '/api/reservations/$reference/payment/quote',
    );
    _ensureOk(r);
    return EscrowQuote.fromJson(_decode(r));
  }
}

// ---------------------------------------------------------------------------
// Provider API (infos prestataire)
// ---------------------------------------------------------------------------
class ProviderApi {
  /// Taux de commission EFFECTIF (%) du prestataire (réduction premium
  /// incluse). Repli 18% si indisponible.
  static Future<int> effectiveCommissionRate() async {
    try {
      final r = await BabifixUserStore.authGet('/api/prestataire/me');
      if (r.statusCode != 200) return 18;
      final prov = (_decode(r)['provider'] as Map<String, dynamic>?) ?? {};
      final v = prov['commission_rate_effective'];
      return v is num ? v.toInt() : 18;
    } catch (_) {
      return 18;
    }
  }
}

// ---------------------------------------------------------------------------
// Devis API (prestataire-side : création + consultation)
// ---------------------------------------------------------------------------
class DevisApi {
  /// Lire le devis d'une réservation.
  static Future<Devis?> get(String reference) async {
    final r = await BabifixUserStore.authGet(
      '/api/client/reservations/$reference/devis',
    );
    if (r.statusCode == 404) return null;
    _ensureOk(r);
    final j = _decode(r);
    final d = j['devis'];
    if (d == null) return null;
    return Devis.fromJson(Map<String, dynamic>.from(d as Map));
  }

  /// Créer un devis (presta) avec lignes structurées.
  static Future<Devis> create({
    required String reference,
    required String diagnostic,
    String? dateProposee,
    String? heureDebut,
    String? heureFin,
    int validiteJours = 7,
    String notePrestataire = '',
    List<String> photosPrestataire = const [],
    double remise = 0,
    bool draft = false,
    required List<LigneDevis> lignes,
  }) async {
    final r = await BabifixUserStore.authPost(
      '/api/prestataire/requests/$reference/devis',
      body: jsonEncode({
        'diagnostic': diagnostic,
        if (dateProposee != null) 'date_proposee': dateProposee,
        if (heureDebut != null) 'heure_debut': heureDebut,
        if (heureFin != null) 'heure_fin': heureFin,
        'validite_jours': validiteJours,
        'note_prestataire': notePrestataire,
        if (photosPrestataire.isNotEmpty)
          'photos_prestataire': photosPrestataire,
        if (remise > 0) 'remise': remise,
        if (draft) 'draft': true,
        'lignes': lignes.map((l) => l.toJson()).toList(),
      }),
    );
    _ensureOk(r);
    final j = _decode(r);
    return Devis.fromJson(Map<String, dynamic>.from(j['devis'] as Map));
  }

  /// Envoie une ESTIMATION (fourchette indicative, non payable). Le devis ferme
  /// suivra. Pas de lignes nécessaires.
  static Future<void> createEstimation({
    required String reference,
    required String diagnostic,
    required double prixMin,
    required double prixMax,
    String notePrestataire = '',
  }) async {
    final r = await BabifixUserStore.authPost(
      '/api/prestataire/requests/$reference/devis',
      body: jsonEncode({
        'diagnostic': diagnostic,
        'note_prestataire': notePrestataire,
        'est_estimation': true,
        'prix_min': prixMin,
        'prix_max': prixMax,
        'lignes': const [],
      }),
    );
    _ensureOk(r);
  }

  /// Demande une VISITE de diagnostic avec caution (déductible du devis).
  static Future<void> requestVisit({
    required String reference,
    required double cautionMontant,
    String cautionMotif = '',
  }) async {
    final r = await BabifixUserStore.authPost(
      '/api/prestataire/requests/$reference/request-visit',
      body: jsonEncode({
        'caution_montant': cautionMontant,
        'caution_motif': cautionMotif,
      }),
    );
    _ensureOk(r);
  }

  /// Renvoie le brouillon de devis du prestataire (ou null s'il n'y en a pas).
  static Future<Map<String, dynamic>?> getDraft(String reference) async {
    final r = await BabifixUserStore.authGet(
      '/api/prestataire/requests/$reference/devis/draft',
    );
    if (r.statusCode != 200) return null;
    final j = _decode(r);
    final draft = j['draft'];
    if (draft is Map) return Map<String, dynamic>.from(draft);
    return null;
  }
}

// ---------------------------------------------------------------------------
// Catalogue API
// ---------------------------------------------------------------------------
class CatalogueApi {
  static final Map<int, List<CatalogueItem>> _cache = {};

  static Future<List<CatalogueItem>> forCategory(int categoryId,
      {bool forceRefresh = false}) async {
    if (!forceRefresh && _cache.containsKey(categoryId)) {
      return _cache[categoryId]!;
    }
    final r = await BabifixUserStore.authGet(
      '/api/categories/$categoryId/catalogue',
    );
    _ensureOk(r);
    final j = _decode(r);
    final items = (j['items'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => CatalogueItem.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    _cache[categoryId] = items;
    return items;
  }
}

// ---------------------------------------------------------------------------
// Calls API
// ---------------------------------------------------------------------------
class CallsApi {
  static Future<CallInvite> initiate({
    required String reservationReference,
    bool isVideo = false,
    bool diagnostic = false,
  }) async {
    final r = await BabifixUserStore.authPost(
      '/api/calls/initiate',
      body: jsonEncode({
        'reservation_reference': reservationReference,
        'kind': isVideo ? 'VIDEO' : 'VOICE',
        // Visio-diagnostic : appel vidéo autorisé avant l'acceptation.
        if (diagnostic) 'diagnostic': true,
      }),
    );
    _ensureOk(r);
    return CallInvite.fromJson(_decode(r));
  }

  static Future<CallInvite> answer(int callId) async {
    final r = await BabifixUserStore.authPost(
      '/api/calls/$callId/answer',
      body: jsonEncode({}),
    );
    _ensureOk(r);
    return CallInvite.fromJson(_decode(r));
  }

  static Future<CallRecord> reject(int callId) async {
    final r = await BabifixUserStore.authPost(
      '/api/calls/$callId/reject',
      body: jsonEncode({}),
    );
    _ensureOk(r);
    return CallRecord.fromJson(
      Map<String, dynamic>.from(_decode(r)['call'] as Map),
    );
  }

  static Future<CallRecord> end(int callId) async {
    final r = await BabifixUserStore.authPost(
      '/api/calls/$callId/end',
      body: jsonEncode({}),
    );
    _ensureOk(r);
    return CallRecord.fromJson(
      Map<String, dynamic>.from(_decode(r)['call'] as Map),
    );
  }

  static Future<List<CallRecord>> history() async {
    final r = await BabifixUserStore.authGet('/api/calls/history');
    _ensureOk(r);
    final list = (_decode(r)['calls'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => CallRecord.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    return list;
  }
}

// ---------------------------------------------------------------------------
// Media API (B7) — upload sécurisé d'image
// ---------------------------------------------------------------------------
class MediaApi {
  static Future<String> uploadFile(String filePath) async {
    final token = await BabifixUserStore.getApiToken();
    final uri = Uri.parse('${babifixApiBaseUrl()}/api/media/upload');
    final req = http.MultipartRequest('POST', uri);
    if (token != null && token.isNotEmpty) {
      req.headers['Authorization'] = 'Bearer $token';
    }
    req.files.add(await http.MultipartFile.fromPath('file', filePath));
    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode >= 400) {
      throw BabifixApiException(
        resp.statusCode, 'upload_failed', resp.body,
      );
    }
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    return (j['url'] ?? '').toString();
  }

  static String absolute(String url) {
    if (url.startsWith('http')) return url;
    return '${babifixApiBaseUrl()}$url';
  }
}

// ---------------------------------------------------------------------------
// Reservation cycle (prestataire)
// ---------------------------------------------------------------------------
class ReservationApi {
  /// HTTP 409 `acompte_required` retourné dans Map sans throw.
  static Future<Map<String, dynamic>> demarrer(String reference) async {
    final r = await BabifixUserStore.authPost(
      '/api/prestataire/requests/$reference/demarrer',
      body: jsonEncode({}),
    );
    final j = _decode(r);
    if (r.statusCode == 409) return {'error': 'acompte_required', ...j};
    _ensureOk(r);
    return j;
  }

  static Future<Map<String, dynamic>> terminer(String reference) async {
    final r = await BabifixUserStore.authPost(
      '/api/prestataire/requests/$reference/terminer',
      body: jsonEncode({}),
    );
    _ensureOk(r);
    return _decode(r);
  }

  static Future<Map<String, dynamic>> uploadPhotos(
    String reference, {
    required String type,
    required List<String> photos,
  }) async {
    final r = await BabifixUserStore.authPost(
      '/api/prestataire/requests/$reference/photos',
      body: jsonEncode({
        'type': type,
        if (type == 'avant') 'photos_avant': photos,
        if (type == 'apres') 'photos_apres': photos,
      }),
    );
    _ensureOk(r);
    return _decode(r);
  }
}
