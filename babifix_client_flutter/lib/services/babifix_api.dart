/// Clients API BABIFIX (client) — Phase F (escrow), B (catalogue), D (calls),
/// C (chat enrichi), G (reçu PDF).
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../babifix_api_config.dart';
import '../models/babifix_models.dart';
import '../user_store.dart';

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
    (j['message'] ?? j['detail'] ?? r.reasonPhrase ?? 'Erreur réseau')
        .toString(),
    j,
  );
}

// ---------------------------------------------------------------------------
// Escrow API
// ---------------------------------------------------------------------------
class EscrowApi {
  /// Phase F — GET /api/reservations/<ref>/payment/quote
  static Future<EscrowQuote> quote(String reference) async {
    final r = await BabifixUserStore.authGet(
      '/api/reservations/$reference/payment/quote',
    );
    _ensureOk(r);
    return EscrowQuote.fromJson(_decode(r));
  }

  /// Confirmation client → libère les fonds (mobile) ou acte le cash.
  static Future<Map<String, dynamic>> confirmCompletion(String reference) async {
    final r = await BabifixUserStore.authPost(
      '/api/client/demandes/$reference/confirmer-travaux',
      body: jsonEncode({}),
    );
    _ensureOk(r);
    return _decode(r);
  }
}

// ---------------------------------------------------------------------------
// Devis API
// ---------------------------------------------------------------------------
class DevisApi {
  /// GET /api/client/reservations/<ref>/devis
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

  /// POST /api/client/reservations/<ref>/devis/accept
  static Future<void> accept(String reference) async {
    final r = await BabifixUserStore.authPost(
      '/api/client/reservations/$reference/devis/accept',
      body: jsonEncode({}),
    );
    _ensureOk(r);
  }

  /// POST /api/client/reservations/<ref>/devis/refuse
  static Future<void> refuse(String reference, {String motif = ''}) async {
    final r = await BabifixUserStore.authPost(
      '/api/client/reservations/$reference/devis/refuse',
      body: jsonEncode({'motif': motif}),
    );
    _ensureOk(r);
  }
}

// ---------------------------------------------------------------------------
// Catalogue API
// ---------------------------------------------------------------------------
class CatalogueApi {
  /// GET /api/categories/<id>/catalogue
  static Future<List<CatalogueItem>> forCategory(int categoryId) async {
    final r = await BabifixUserStore.authGet(
      '/api/categories/$categoryId/catalogue',
    );
    _ensureOk(r);
    final j = _decode(r);
    final items = (j['items'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => CatalogueItem.fromJson(Map<String, dynamic>.from(m)))
        .toList();
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
  }) async {
    final r = await BabifixUserStore.authPost(
      '/api/calls/initiate',
      body: jsonEncode({
        'reservation_reference': reservationReference,
        'kind': isVideo ? 'VIDEO' : 'VOICE',
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
// Reservation execution API (cycle)
// ---------------------------------------------------------------------------
class ReservationApi {
  /// Prestataire : démarrer l'intervention. Renvoie un map avec `error`
  /// `acompte_required` (HTTP 409) si non payé — le caller doit le gérer.
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
    required String type, // "avant" | "apres"
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

// ---------------------------------------------------------------------------
// Dispute API (B6)
// ---------------------------------------------------------------------------
class DisputeApi {
  /// POST /api/client/reservations/<ref>/dispute
  static Future<Map<String, dynamic>> open({
    required String reservationReference,
    required String motif,
    String priorite = 'Moyenne',
  }) async {
    final r = await BabifixUserStore.authPost(
      '/api/client/reservations/$reservationReference/dispute',
      body: jsonEncode({'motif': motif, 'priorite': priorite}),
    );
    _ensureOk(r);
    return _decode(r);
  }
}

// ---------------------------------------------------------------------------
// Media API (B7) — upload sécurisé d'image et récupération d'URL canonique
// ---------------------------------------------------------------------------
class MediaApi {
  /// Upload binaire via multipart. Retourne l'URL relative (à préfixer
  /// avec [babifixApiBaseUrl] pour l'afficher).
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
        resp.statusCode,
        'upload_failed',
        resp.body,
      );
    }
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    return (j['url'] ?? '').toString();
  }

  /// Convertit une URL relative (`/media/...`) en URL absolue.
  static String absolute(String url) {
    if (url.startsWith('http')) return url;
    return '${babifixApiBaseUrl()}$url';
  }
}

// ---------------------------------------------------------------------------
// Receipt PDF API (Phase G)
// ---------------------------------------------------------------------------
class ReceiptApi {
  /// Renvoie les octets du PDF (téléchargement).
  static Future<List<int>> downloadPdf(String reference) async {
    final r = await BabifixUserStore.authGet(
      '/api/client/reservations/$reference/receipt/pdf/',
    );
    _ensureOk(r);
    return r.bodyBytes;
  }
}
