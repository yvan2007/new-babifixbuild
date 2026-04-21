import 'package:flutter/material.dart';

/// Onglet filtre catalogue (icône Material ou SVG réseau).
class CategoryTab {
  const CategoryTab({
    this.icon,
    this.iconNetworkUrl,
    required this.label,
    required this.filterKey,
    this.color,
  });

  final IconData? icon;
  final String? iconNetworkUrl;
  final String label;
  final String filterKey;
  final Color? color;
}

class PaymentMethodOption {
  const PaymentMethodOption({
    required this.id,
    required this.label,
    required this.logoUrl,
  });

  final String id;
  final String label;
  final String logoUrl;
}

class RecentProviderCard {
  const RecentProviderCard({
    required this.id,
    required this.nom,
    required this.specialite,
    required this.ville,
    required this.imageUrl,
    this.tarif,
    this.disponible = true,
  });

  final int id;
  final String nom;
  final String specialite;
  final String ville;
  final String imageUrl;
  final double? tarif;
  final bool disponible;

  RecentProviderCard copyWith({bool? disponible}) => RecentProviderCard(
    id: id,
    nom: nom,
    specialite: specialite,
    ville: ville,
    imageUrl: imageUrl,
    tarif: tarif,
    disponible: disponible ?? this.disponible,
  );
}

class ClientService {
  const ClientService({
    required this.title,
    required this.category,
    required this.duration,
    required this.price,
    required this.rating,
    required this.verified,
    required this.color,
    required this.imageUrl,
    this.providerId = 0,
    this.disponible = true,
  });

  final String title;
  final String category;
  final String duration;
  final int price;
  final double rating;
  final bool verified;
  final Color color;
  final String imageUrl;

  /// ID prestataire côté API (0 si inconnu).
  final int providerId;

  /// false si le prestataire s'est mis indisponible.
  final bool disponible;

  ClientService copyWith({bool? disponible}) => ClientService(
    title: title,
    category: category,
    duration: duration,
    price: price,
    rating: rating,
    verified: verified,
    color: color,
    imageUrl: imageUrl,
    providerId: providerId,
    disponible: disponible ?? this.disponible,
  );
}

class ClientReservation {
  const ClientReservation({
    required this.title,
    required this.whenLabel,
    required this.amount,
    required this.status,
    this.reference = '',
    this.id = 0,
    this.canRate = false,
    this.rated = false,
    this.paymentType = 'ESPECES',
    this.cashFlowStatus = '',
    this.canConfirmService = false,
    this.canPay = false,
    this.canViewDevis = false,
    this.canAcceptDevis = false,
    this.disputeOuverte = false,
    this.latitude,
    this.longitude,
    this.addressLabel = '',
  });

  final String title;
  final String whenLabel;
  final String amount;
  final String status;
  final String reference;
  final int id;
  final bool canRate;
  final bool rated;
  final String paymentType;
  final String cashFlowStatus;
  final bool canConfirmService;
  final bool canPay;
  final bool canViewDevis;
  final bool canAcceptDevis;
  final bool disputeOuverte;

  /// Lieu d'intervention si enregistré (carte dans l'avis).
  final double? latitude;
  final double? longitude;
  final String addressLabel;
}

class ClientActualiteItem {
  const ClientActualiteItem({
    required this.id,
    required this.titre,
    required this.description,
    required this.imageUrl,
    required this.categorieTag,
    required this.dateLabel,
  });

  final int id;
  final String titre;
  final String description;
  final String imageUrl;
  final String categorieTag;
  final String dateLabel;
}

// ClientChatMsg is defined in features/chat/chat_room_screen.dart
