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
    this.distanceKm,
    this.premiumTier = 'standard',
    this.premiumBadge = '',
  });

  final int id;
  final String nom;
  final String specialite;
  final String ville;
  final String imageUrl;
  final double? tarif;
  final bool disponible;

  /// Abonnement premium ('standard'|'bronze'|'silver'|'gold') + libellé badge.
  final String premiumTier;
  final String premiumBadge;
  bool get isPremium => premiumTier != 'standard' && premiumTier.isNotEmpty;

  /// Distance (km) entre le client et ce prestataire — fournie par l'API
  /// `/api/public/providers/?lat=&lon=` (champ `distance_km`).
  final double? distanceKm;

  RecentProviderCard copyWith({bool? disponible}) => RecentProviderCard(
    id: id,
    nom: nom,
    specialite: specialite,
    ville: ville,
    imageUrl: imageUrl,
    tarif: tarif,
    disponible: disponible ?? this.disponible,
    distanceKm: distanceKm,
    premiumTier: premiumTier,
    premiumBadge: premiumBadge,
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
    this.distanceKm,
  });

  /// Distance (km) du prestataire derrière ce service.
  final double? distanceKm;

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
  ClientReservation({
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
    this.canPayDeposit = false,
    this.canPayRemainder = false,
    this.needCashRemainder = false,
    this.receiptAvailable = false,
    this.clientConfirmed = false,
    this.disputeOuverte = false,
    this.latitude,
    this.longitude,
    this.addressLabel = '',
    this.addressStreet = '',
    this.addressQuartier = '',
    this.addressVille = '',
    this.addressPays = '',
    this.addressRepere = '',
    this.addressIsApproximate = false,
    this.statusLabel = '',
    this.interventionStartedAt,
    this.prestationTermineeAt,
    this.montantVerse = 0,
    this.fundsReleased = false,
    this.serviceTitle = '',
    this.providerName = '',
    this.scheduledDate = '',
    this.cautionMontant = 0,
    this.fraisMiseEnRelation = 500,
    this.cautionMotif = '',
    this.cautionPayee = false,
    this.canPayCaution = false,
    this.visiteEffectuee = false,
  });

  final String title;
  final String whenLabel;
  final String amount;
  final String status;

  /// Date prévue choisie par le client (ISO yyyy-mm-dd) — affichée sur la carte.
  final String scheduledDate;
  final String reference;
  final int id;
  final bool canRate;
  bool rated;
  final String paymentType;
  final String cashFlowStatus;
  final bool canConfirmService;
  final bool canPay;
  final bool canViewDevis;
  final bool canAcceptDevis;
  final bool canPayDeposit;
  final bool canPayRemainder;
  final bool needCashRemainder;
  final bool receiptAvailable;

  /// Le client a confirmé la réception des travaux (séquestre/cash réglé).
  /// Sert à classer la réservation comme « Terminée » même en mode espèces,
  /// où le statut backend reste « Confirmee ».
  final bool clientConfirmed;
  final bool disputeOuverte;
  final String statusLabel;

  /// Caution de visite de diagnostic (Phase 3).
  /// Phase 5 : la caution = TRANSPORT (100 % prestataire). Le client règle EN
  /// PLUS un frais fixe de mise en relation (revenu BABIFIX).
  final double cautionMontant;
  final String cautionMotif;
  final bool cautionPayee;
  final bool canPayCaution;
  final double fraisMiseEnRelation;

  /// Le prestataire a déclaré avoir effectué la visite de diagnostic. AVANT
  /// ça, la caution réglée par le client reste en ESCROW (pas encore versée
  /// au prestataire) — sans exposer ce champ, le client n'avait aucun moyen
  /// de savoir où était son argent entre le paiement de la caution et la
  /// visite.
  final bool visiteEffectuee;

  /// Lieu d'intervention si enregistré (carte dans l'avis).
  final double? latitude;
  final double? longitude;
  final String addressLabel;
  final String addressStreet;
  final String addressQuartier;
  final String addressVille;
  final String addressPays;
  final String addressRepere;
  final bool addressIsApproximate;

  /// Chrono de la prestation : début + fin (preuve horodatée de la durée).
  final DateTime? interventionStartedAt;
  final DateTime? prestationTermineeAt;

  /// Montant payé en ligne et séquestré (escrow), + si déjà libéré au presta.
  final double montantVerse;
  final bool fundsReleased;

  /// Intitulé de la prestation + nom du prestataire (affichés sur la carte).
  final String serviceTitle;
  final String providerName;
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
