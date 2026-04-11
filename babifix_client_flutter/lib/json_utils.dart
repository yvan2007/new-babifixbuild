import 'dart:convert';

/// Extrait un message lisible depuis le corps d’erreur DRF / JSON (400, etc.).
String babifixFormatApiErrorBody(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      if (decoded['error'] != null) {
        // Prefer the human-readable 'message' field if present alongside the error code.
        if (decoded['message'] != null && '${decoded['message']}'.isNotEmpty) {
          return '${decoded['message']}';
        }
        return '${decoded['error']}';
      }
      if (decoded['detail'] != null) return '${decoded['detail']}';
      final detail = decoded['non_field_errors'];
      if (detail is List && detail.isNotEmpty) {
        return detail.map((e) => '$e').join(' ');
      }
      final parts = <String>[];
      decoded.forEach((k, v) {
        if (v is List) {
          parts.add('$k: ${v.map((e) => '$e').join(', ')}');
        } else if (v is Map) {
          parts.add('$k: $v');
        } else {
          parts.add('$k: $v');
        }
      });
      if (parts.isNotEmpty) return parts.join(' — ');
    }
    if (decoded is List && decoded.isNotEmpty) {
      return decoded.map((e) => '$e').join(' ');
    }
  } catch (_) {}
  return '';
}

/// Parse JSON values safely (évite Null → int runtime errors).
int jsonInt(dynamic v, [int fallback = 0]) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) {
    final p = int.tryParse(v);
    return p ?? fallback;
  }
  return fallback;
}

bool jsonBool(dynamic v, [bool fallback = false]) {
  if (v == null) return fallback;
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final t = v.toLowerCase();
    if (t == 'true' || t == '1' || t == 'yes') return true;
    if (t == 'false' || t == '0' || t == 'no') return false;
  }
  return fallback;
}

double jsonDouble(dynamic v, [double fallback = 0]) {
  if (v == null) return fallback;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is num) return v.toDouble();
  if (v is String) {
    final p = double.tryParse(v);
    return p ?? fallback;
  }
  return fallback;
}

/// Comme [jsonDouble] mais `null` si la valeur est absente ou non numérique.
double? jsonDoubleNullable(dynamic v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is num) return v.toDouble();
  if (v is String) {
    return double.tryParse(v);
  }
  return null;
}
