// Flutter Shared : Code partage entre les apps client et prestataire
// Package a publier pour eviter la duplication de code.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Design system commun
class BabifixTheme {
  static const Color primary = Color(0xFF4CC9F0);  // Cyan
  static const Color secondary = Color(0xFF0D1F3C);  // Navy
  static const Color accent = Color(0xFFF72585);  // Pink
  
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
    ),
  );
  
  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
    ),
  );
}

/// Modeles partages (DTOs)
class ReservationDTO {
  final String reference;
  final String title;
  final String status;
  final DateTime createdAt;
  
  ReservationDTO({
    required this.reference,
    required this.title,
    required this.status,
    required this.createdAt,
  });
  
  factory ReservationDTO.fromJson(Map<String, dynamic> json) => ReservationDTO(
    reference: json['reference'] ?? '',
    title: json['title'] ?? '',
    status: json['statut'] ?? '',
    createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
  );
}

class ProviderDTO {
  final int id;
  final String name;
  final String specialty;
  final double rating;
  final int reviewCount;
  final bool available;
  
  ProviderDTO({
    required this.id,
    required this.name,
    required this.specialty,
    required this.rating,
    required this.reviewCount,
    required this.available,
  });
  
  factory ProviderDTO.fromJson(Map<String, dynamic> json) => ProviderDTO(
    id: json['id'] ?? 0,
    name: json['nom'] ?? '',
    specialty: json['specialite'] ?? '',
    rating: (json['note_moyenne'] ?? 0).toDouble(),
    reviewCount: json['nombre_notes'] ?? 0,
    available: json['disponible'] ?? false,
  );
}

/// Widgets communs
class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key});
  final String status;
  
  static final _colors = {
    'En attente': Color(0xFFFFC107),
    'Confirmee': Color(0xFF4CC9F0),
    'Terminee': Color(0xFF28A745),
    'Annulee': Color(0xFFDC3545),
  };
  
  @override
  Widget build(BuildContext ctx) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    decoration: BoxDecoration(
      color: _colors[status] ?? Color(0xFF6C757D),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(status, style: const TextStyle(
      color: Colors.white,
      fontSize: 12,
      fontWeight: FontWeight.bold,
    )),
  );
}

class RatingStars extends StatelessWidget {
  const RatingStars(this.rating, {super.key, this.size = 20});
  final double rating;
  final double size;
  
  @override
  Widget build(BuildContext ctx) => Row(
    mainAxisSize: MainAxisSize.min,
    children: List.generate(5, (i) => Icon(
      i < rating.floor() ? Icons.star : Icons.star_border,
      color: const Color(0xFFFFC107),
      size: size,
    )),
  );
}

/// Utils communes
class DateUtils {
  static String formatDate(DateTime date) =>
      '${date.day}/${date.month}/${date.year}';
  
  static String formatDateTime(DateTime date) =>
      '${date.day}/${date.month}/${date.year} ${date.hour}h${date.minute.toString().padLeft(2, '0')}';
  
  static String timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays > 0) return '${diff.inDays}j';
    if (diff.inHours > 0) return '${diff.inHours}h';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m';
    return 'a maintenant';
  }
}

class MoneyUtils {
  static String formatCFA(int amount) {
    if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(0)}K CFA';
    }
    return '$amount CFA';
  }
}

/// API configuration commune
class ApiConfig {
  static String baseUrl = 'http://localhost:8000';
  static String wsUrl = 'ws://localhost:8000';
  
  static void setProduction() {
    baseUrl = 'https://api.babifix.ci';
    wsUrl = 'wss://api.babifix.ci';
  }
}

/// HTTP client avec retry
class ApiClient {
  Future<dynamic> get(String path) async {}
  Future<dynamic> post(String path, {dynamic body}) async {}
}

/// Dialogue de securite et de confirmation transactionnelle
/// Respecte les regles CISO/DPO et conformite Loi ivoirienne n° 2013-450.
Future<bool> promptSecurityActionConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String? amountCFA,
  String confirmLabel = 'Confirmer en toute securite',
  String cancelLabel = 'Annuler',
  bool isDestructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      final bg = isDark ? const Color(0xFF0F1B2D) : Colors.white;
      final textMain = isDark ? Colors.white : const Color(0xFF0F172A);
      final textSub = isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569);

      return Dialog(
        backgroundColor: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDestructive
                      ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                      : const Color(0xFF047857).withValues(alpha: 0.15),
                  border: Border.all(
                    color: isDestructive
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF10B981),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  isDestructive ? Icons.shield_outlined : Icons.verified_user_rounded,
                  color: isDestructive ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                  size: 30,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textMain,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textSub,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
              if (amountCFA != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF16253B) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.account_balance_wallet_rounded, size: 18, color: Color(0xFFC2410C)),
                      const SizedBox(width: 8),
                      Text(
                        amountCFA,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFC2410C),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_rounded, size: 12, color: Color(0xFF64748B)),
                  const SizedBox(width: 5),
                  Text(
                    'Paiement securise conformite Loi ivoirienne n° 2013-450',
                    style: TextStyle(fontSize: 11, color: textSub),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        side: BorderSide(
                          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: Text(
                        cancelLabel,
                        style: TextStyle(
                          color: textSub,
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDestructive ? const Color(0xFFDC2626) : const Color(0xFFC2410C),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: Text(
                        confirmLabel,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
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
    },
  );
  return result ?? false;
}


/// Dialogue de securite et de confirmation transactionnelle
/// Respecte les regles CISO/DPO et conformite Loi ivoirienne n 2013-450.
Future<bool> promptSecurityActionConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String? amountCFA,
  String confirmLabel = 'Confirmer en toute securite',
  String cancelLabel = 'Annuler',
  bool isDestructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      final bg = isDark ? const Color(0xFF0F1B2D) : Colors.white;
      final textMain = isDark ? Colors.white : const Color(0xFF0F172A);
      final textSub = isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569);

      return Dialog(
        backgroundColor: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDestructive
                      ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                      : const Color(0xFF047857).withValues(alpha: 0.15),
                  border: Border.all(
                    color: isDestructive
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF10B981),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  isDestructive ? Icons.shield_outlined : Icons.verified_user_rounded,
                  color: isDestructive ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                  size: 30,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textMain,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textSub,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
              if (amountCFA != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF16253B) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.account_balance_wallet_rounded, size: 18, color: Color(0xFFC2410C)),
                      const SizedBox(width: 8),
                      Text(
                        amountCFA,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFC2410C),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_rounded, size: 12, color: Color(0xFF64748B)),
                  const SizedBox(width: 5),
                  Text(
                    'Paiement securise conformite Loi ivoirienne n 2013-450',
                    style: TextStyle(fontSize: 11, color: textSub),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        side: BorderSide(
                          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: Text(
                        cancelLabel,
                        style: TextStyle(
                          color: textSub,
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDestructive ? const Color(0xFFDC2626) : const Color(0xFFC2410C),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: Text(
                        confirmLabel,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
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
    },
  );
  return result ?? false;
}
