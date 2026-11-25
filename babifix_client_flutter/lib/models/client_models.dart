import 'package:flutter/material.dart';

/// Onglet filtre catalogue (icone Material, SVG Admin local ou reseau).
class CategoryTab {
  const CategoryTab({
    this.icon,
    this.iconeSlug = '',
    this.iconNetworkUrl,
    required this.label,
    required this.filterKey,
    this.color,
    this.groupe = 'Maison & Services',
    this.regimeKyc = 'STANDARD_TERRAIN',
    this.searchKeywords = '',
  });

  final IconData? icon;
  final String iconeSlug;
  final String? iconNetworkUrl;
  final String label;
  final String filterKey;
  final Color? color;
  final String groupe;
  final String regimeKyc;
  final String searchKeywords;
  bool get isSensitive => regimeKyc == 'SENSIBLE_CASIER';
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
    this.averageRating = 0.0,
    this.ratingCount = 0,
    this.isCertified = false,
    this.palier = 'PALIER_1_PROXIMITE',
    this.palierLabel = 'Artisan Proximité',
    this.eliteScore = 0.0,
    this.trustReasons = const [],
    this.casierVerifie = false,
    this.regimeKyc = 'STANDARD_TERRAIN',
    this.avgResponseMin,
    this.completedJobs = 0,
  });

  final int id;
  final String nom;
  final String specialite;
  final String ville;
  final String imageUrl;
  final double? tarif;
  final bool disponible;

  /// Abonnement premium ('standard'|'silver'|'gold') + libelle badge.
  final String premiumTier;
  final String premiumBadge;
  bool get isPremium => premiumTier != 'standard' && premiumTier.isNotEmpty;
  bool get isGold => premiumTier.toLowerCase() == 'gold';
  bool get isSilver => premiumTier.toLowerCase() == 'silver';

  /// Note moyenne, nombre d'avis, certification terrain et palier d'intervention.
  final double averageRating;
  final int ratingCount;
  final bool isCertified;
  final String palier;
  final String palierLabel;
  final double eliteScore;
  final List<String> trustReasons;
  final bool casierVerifie;
  final String regimeKyc;
  final int? avgResponseMin;
  final int completedJobs;

  /// Distance (km) entre le client et ce prestataire : fournie par l'API
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
    averageRating: averageRating,
    ratingCount: ratingCount,
    isCertified: isCertified,
    palier: palier,
    palierLabel: palierLabel,
    eliteScore: eliteScore,
    trustReasons: trustReasons,
    casierVerifie: casierVerifie,
    regimeKyc: regimeKyc,
    avgResponseMin: avgResponseMin,
    completedJobs: completedJobs,
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
    this.premiumBadge = '',
    this.premiumTier = 'standard',
    this.palierLabel = 'Artisan Proximité',
    this.isCertified = false,
    this.ratingCount = 0,
    this.eliteScore = 0.0,
    this.trustReasons = const [],
    this.casierVerifie = false,
    this.regimeKyc = 'STANDARD_TERRAIN',
    this.ville = '',
    this.avgResponseMin,
    this.completedJobs = 0,
  });

  final String premiumBadge;
  final String premiumTier;
  final String palierLabel;
  final bool isCertified;
  final int ratingCount;
  final double eliteScore;
  final List<String> trustReasons;
  final bool casierVerifie;
  final String regimeKyc;
  final String ville;
  final int? avgResponseMin;
  final int completedJobs;

  bool get isGold => premiumTier.toLowerCase() == 'gold';
  bool get isSilver => premiumTier.toLowerCase() == 'silver';

  /// Distance (km) du prestataire derriere ce service.
  final double? distanceKm;

  final String title;
  final String category;
  final String duration;
  final int price;
  final double rating;
  final bool verified;
  final Color color;
  final String imageUrl;

  /// ID prestataire cote API (0 si inconnu).
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
    distanceKm: distanceKm,
    premiumBadge: premiumBadge,
    premiumTier: premiumTier,
    palierLabel: palierLabel,
    isCertified: isCertified,
    ratingCount: ratingCount,
    eliteScore: eliteScore,
    trustReasons: trustReasons,
    casierVerifie: casierVerifie,
    regimeKyc: regimeKyc,
    ville: ville,
    avgResponseMin: avgResponseMin,
    completedJobs: completedJobs,
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
