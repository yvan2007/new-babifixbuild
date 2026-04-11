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
