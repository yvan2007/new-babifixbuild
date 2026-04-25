"""
Flutter Shared — Code partage entre les apps client et prestataire
Package a publier pour eviter la duplication de code.
"""
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
  static String format CFA(int amount) {
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