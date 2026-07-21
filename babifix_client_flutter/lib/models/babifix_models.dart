/// Modèles partagés BABIFIX (client) — Phase A→G.
///
/// Tous les modèles tolèrent les anciens JSON (champs absents).
library babifix_models;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
double _asDouble(dynamic v, [double def = 0]) {
  if (v == null) return def;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? def;
}

int _asInt(dynamic v, [int def = 0]) {
  if (v == null) return def;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? def;
}

String _asStr(dynamic v, [String def = '']) {
  if (v == null) return def;
  return v.toString();
}

DateTime? _asDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  return DateTime.tryParse(v.toString());
}

// ---------------------------------------------------------------------------
// LigneDevis
// ---------------------------------------------------------------------------
enum DevisLineType {
  fourniture('FOURNITURE', 'Fourniture'),
  mainOeuvre('MAIN_OEUVRE', "Main d'œuvre"),
  // Le déplacement est compris dans la main-d'œuvre : on n'affiche plus
  // « Déplacement » (anciennes lignes incluses) → libellé « Main d'œuvre ».
  deplacement('DEPLACEMENT', "Main d'œuvre"),
  autre('AUTRE', 'Autre');

  final String code;
  final String label;
  const DevisLineType(this.code, this.label);

  static DevisLineType fromCode(String code) {
    return DevisLineType.values.firstWhere(
      (e) => e.code == code.toUpperCase(),
      orElse: () => DevisLineType.autre,
    );
  }
}

class LigneDevis {
  final int? id;
  final DevisLineType typeLigne;
  final String description;
  final double quantite;
  final double prixUnitaire;
  final String unite;
  final String marque;
  final int? catalogueItemId;
  final double total;

  const LigneDevis({
    this.id,
    required this.typeLigne,
    required this.description,
    required this.quantite,
    required this.prixUnitaire,
    this.unite = '',
    this.marque = '',
    this.catalogueItemId,
    required this.total,
  });

  factory LigneDevis.fromJson(Map<String, dynamic> j) => LigneDevis(
        id: j['id'] is int ? j['id'] : _asInt(j['id']),
        typeLigne: DevisLineType.fromCode(_asStr(j['type_ligne'], 'AUTRE')),
        description: _asStr(j['description']),
        quantite: _asDouble(j['quantite'], 1),
        prixUnitaire: _asDouble(j['prix_unitaire']),
        unite: _asStr(j['unite']),
        marque: _asStr(j['marque']),
        catalogueItemId: j['catalogue_item_id'] == null
            ? null
            : _asInt(j['catalogue_item_id']),
        total: _asDouble(j['total']),
      );

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'type_ligne': typeLigne.code,
        'description': description,
        'quantite': quantite,
        'prix_unitaire': prixUnitaire,
        if (unite.isNotEmpty) 'unite': unite,
        if (marque.isNotEmpty) 'marque': marque,
        if (catalogueItemId != null) 'catalogue_item_id': catalogueItemId,
      };

  LigneDevis copyWith({
    DevisLineType? typeLigne,
    String? description,
    double? quantite,
    double? prixUnitaire,
    String? unite,
    String? marque,
    int? catalogueItemId,
  }) {
    final q = quantite ?? this.quantite;
    final p = prixUnitaire ?? this.prixUnitaire;
    return LigneDevis(
      id: id,
      typeLigne: typeLigne ?? this.typeLigne,
      description: description ?? this.description,
      quantite: q,
      prixUnitaire: p,
      unite: unite ?? this.unite,
      marque: marque ?? this.marque,
      catalogueItemId: catalogueItemId ?? this.catalogueItemId,
      total: q * p,
    );
  }
}

// ---------------------------------------------------------------------------
// Devis
// ---------------------------------------------------------------------------
enum DevisStatus {
  brouillon('BROUILLON', 'Brouillon'),
  envoye('ENVOYE', 'Envoyé'),
  accepte('ACCEPTE', 'Accepté'),
  refuse('REFUSE', 'Refusé'),
  expire('EXPIRE', 'Expiré');

  final String code;
  final String label;
  const DevisStatus(this.code, this.label);
  static DevisStatus fromCode(String c) => DevisStatus.values
      .firstWhere((e) => e.code == c.toUpperCase(), orElse: () => DevisStatus.brouillon);
}

class Devis {
  final int? id;
  final String reference;
  final String diagnostic;
  final String? dateProposee;
  final String? heureDebut;
  final String? heureFin;
  final double sousTotal;
  final int commissionRate;
  final double commissionMontant;
  final double totalTtc;
  final double netPrestataire;
  final String notePrestataire;
  final int validiteJours;
  final double remise;
  final DevisStatus statut;
  final List<String> photosPrestataire;
  final List<LigneDevis> lignes;
  // Devis en 2 temps : estimation (fourchette indicative, non payable).
  final bool estEstimation;
  final double prixMin;
  final double prixMax;

  const Devis({
    this.id,
    required this.reference,
    required this.diagnostic,
    this.dateProposee,
    this.heureDebut,
    this.heureFin,
    required this.sousTotal,
    required this.commissionRate,
    required this.commissionMontant,
    required this.totalTtc,
    required this.netPrestataire,
    this.notePrestataire = '',
    this.validiteJours = 7,
    this.remise = 0,
    required this.statut,
    this.photosPrestataire = const [],
    required this.lignes,
    this.estEstimation = false,
    this.prixMin = 0,
    this.prixMax = 0,
  });

  factory Devis.fromJson(Map<String, dynamic> j) {
    final lignes = (j['lignes'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => LigneDevis.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    return Devis(
      id: j['id'] == null ? null : _asInt(j['id']),
      reference: _asStr(j['reference']),
      diagnostic: _asStr(j['diagnostic']),
      dateProposee: j['date_proposee']?.toString(),
      heureDebut: j['heure_debut']?.toString(),
      heureFin: j['heure_fin']?.toString(),
      sousTotal: _asDouble(j['sous_total']),
      commissionRate: _asInt(j['commission_rate'], 18),
      commissionMontant: _asDouble(j['commission_montant']),
      totalTtc: _asDouble(j['total_ttc']),
      netPrestataire: _asDouble(j['net_prestataire']),
      notePrestataire: _asStr(j['note_prestataire']),
      validiteJours: _asInt(j['validite_jours'], 7),
      remise: _asDouble(j['remise']),
      statut: DevisStatus.fromCode(_asStr(j['statut'], 'BROUILLON')),
      photosPrestataire: (j['photos_prestataire'] as List? ?? const [])
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList(),
      lignes: lignes,
      estEstimation: j['est_estimation'] == true,
      prixMin: _asDouble(j['prix_min']),
      prixMax: _asDouble(j['prix_max']),
    );
  }

  List<LigneDevis> lignesByType(DevisLineType t) =>
      lignes.where((l) => l.typeLigne == t).toList();

  double sousTotalByType(DevisLineType t) =>
      lignesByType(t).fold<double>(0, (s, l) => s + l.total);

  /// commissionRate/commissionMontant/netPrestataire sont figés au moment de
  /// l'ENVOI du devis (avant toute déduction de caution/transport). Une fois
  /// la caution réglée, le VRAI calcul se fait sur le reste — sans ça, la
  /// carte devis affiche encore la commission d'origine (ex. 1 800 F) alors
  /// que le détail du règlement, juste en dessous, affiche la vraie valeur
  /// réconciliée (ex. 1 260 F) : deux chiffres différents pour la même
  /// "Commission BABIFIX" sur le même écran.
  Devis copyWithReconciled({
    required int commissionRate,
    required double commissionMontant,
    required double netPrestataire,
  }) {
    return Devis(
      id: id,
      reference: reference,
      diagnostic: diagnostic,
      dateProposee: dateProposee,
      heureDebut: heureDebut,
      heureFin: heureFin,
      sousTotal: sousTotal,
      commissionRate: commissionRate,
      commissionMontant: commissionMontant,
      totalTtc: totalTtc,
      netPrestataire: netPrestataire,
      notePrestataire: notePrestataire,
      validiteJours: validiteJours,
      remise: remise,
      statut: statut,
      photosPrestataire: photosPrestataire,
      lignes: lignes,
      estEstimation: estEstimation,
      prixMin: prixMin,
      prixMax: prixMax,
    );
  }
}

// ---------------------------------------------------------------------------
// CatalogueItem
// ---------------------------------------------------------------------------
class CatalogueItem {
  final int id;
  final DevisLineType typeLigne;
  final String nom;
  final String description;
  final String unite;
  final String marque;
  final double prixUnitaireIndicatif;

  const CatalogueItem({
    required this.id,
    required this.typeLigne,
    required this.nom,
    required this.description,
    required this.unite,
    required this.marque,
    required this.prixUnitaireIndicatif,
  });

  factory CatalogueItem.fromJson(Map<String, dynamic> j) => CatalogueItem(
        id: _asInt(j['id']),
        typeLigne: DevisLineType.fromCode(_asStr(j['type_ligne'], 'AUTRE')),
        nom: _asStr(j['nom']),
        description: _asStr(j['description']),
        unite: _asStr(j['unite']),
        marque: _asStr(j['marque']),
        prixUnitaireIndicatif: _asDouble(j['prix_unitaire_indicatif']),
      );
}

// ---------------------------------------------------------------------------
// EscrowQuote
// ---------------------------------------------------------------------------
enum EscrowStrategy { cashCommissionOnly, mobileFull, unknown }

EscrowStrategy escrowStrategyFromString(String s) {
  switch (s.toUpperCase()) {
    case 'CASH_COMMISSION_ONLY':
      return EscrowStrategy.cashCommissionOnly;
    // Mobile Money est versé en deux temps : le backend renvoie MOBILE_DEPOSIT
    // (phase acompte 30 %) puis MOBILE_REMAINDER (phase solde 70 %). Les deux —
    // ainsi que l'ancien MOBILE_FULL — sont la stratégie "Mobile Money". Sans
    // ça, isMobile restait toujours faux → escrow affiché à 0, mauvais libellés.
    case 'MOBILE_FULL':
    case 'MOBILE_DEPOSIT':
    case 'MOBILE_REMAINDER':
      return EscrowStrategy.mobileFull;
    default:
      return EscrowStrategy.unknown;
  }
}

class EscrowQuote {
  final String reference;
  final int? reservationId;
  final String paymentType;
  final EscrowStrategy strategy;
  final int? devisId;
  final String devisReference;
  final double totalDevis;
  final double commissionMontant;
  final double netPrestataire;
  final double amountDueOnline;
  final double cashRemainderDueToProvider;
  final bool acompteValide;
  final String mobileMoneyOperator;
  final DateTime? fundsReleasedAt;

  const EscrowQuote({
    required this.reference,
    this.reservationId,
    required this.paymentType,
    required this.strategy,
    this.devisId,
    required this.devisReference,
    required this.totalDevis,
    required this.commissionMontant,
    required this.netPrestataire,
    required this.amountDueOnline,
    required this.cashRemainderDueToProvider,
    required this.acompteValide,
    this.mobileMoneyOperator = '',
    this.fundsReleasedAt,
    this.commissionRate = 18,
  });

  /// Taux RÉEL (envoyé par le serveur, ex. 18). NE PAS le reconstituer en
  /// divisant commissionMontant par totalDevis : depuis que la commission
  /// est calculée sur le reste APRÈS caution (pas sur le total brut), ce
  /// calcul donnait un pourcentage faux (13 % au lieu de 18 %) dès qu'une
  /// caution avait été déduite.
  final int commissionRate;

  factory EscrowQuote.fromJson(Map<String, dynamic> j) => EscrowQuote(
        reference: _asStr(j['reference']),
        reservationId:
            j['reservation_id'] == null ? null : _asInt(j['reservation_id']),
        paymentType: _asStr(j['payment_type']),
        strategy: escrowStrategyFromString(_asStr(j['strategy'])),
        devisId: j['devis_id'] == null ? null : _asInt(j['devis_id']),
        devisReference: _asStr(j['devis_reference']),
        totalDevis: _asDouble(j['total_devis']),
        commissionMontant: _asDouble(j['commission_montant']),
        netPrestataire: _asDouble(j['net_prestataire']),
        amountDueOnline: _asDouble(j['amount_due_online']),
        cashRemainderDueToProvider:
            _asDouble(j['cash_remainder_due_to_provider']),
        acompteValide: j['acompte_valide'] == true,
        mobileMoneyOperator: _asStr(j['mobile_money_operator']),
        fundsReleasedAt: _asDate(j['funds_released_at']),
        commissionRate: _asInt(j['commission_rate'], 18),
      );

  bool get isCash => strategy == EscrowStrategy.cashCommissionOnly;
  bool get isMobile => strategy == EscrowStrategy.mobileFull;
}

// ---------------------------------------------------------------------------
// Message (chat)
// ---------------------------------------------------------------------------
enum MessageKind { user, devisCard, system }

MessageKind messageKindFromString(String s) {
  switch (s.toUpperCase()) {
    case 'DEVIS_CARD':
      return MessageKind.devisCard;
    case 'SYSTEM':
      return MessageKind.system;
    default:
      return MessageKind.user;
  }
}

class ChatMessage {
  final int id;
  final int conversationId;
  final int senderId;
  final String body;
  final MessageKind kind;
  final Map<String, dynamic>? payloadJson;
  final DateTime? createdAt;
  final bool lu;

  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.body,
    required this.kind,
    this.payloadJson,
    this.createdAt,
    required this.lu,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: _asInt(j['id']),
        conversationId: _asInt(j['conversation_id'] ?? j['conversation']),
        senderId: _asInt(j['sender_id'] ?? j['sender']),
        body: _asStr(j['body']),
        kind: messageKindFromString(_asStr(j['kind'], 'USER')),
        payloadJson: j['payload_json'] is Map
            ? Map<String, dynamic>.from(j['payload_json'])
            : null,
        createdAt: _asDate(j['created_at']),
        lu: j['lu'] == true,
      );
}

// ---------------------------------------------------------------------------
// Call
// ---------------------------------------------------------------------------
enum CallStatus { ringing, answered, rejected, missed, ended, cancelled }
enum CallKind { voice, video }

CallStatus callStatusFromString(String s) {
  switch (s.toUpperCase()) {
    case 'ANSWERED':
      return CallStatus.answered;
    case 'REJECTED':
      return CallStatus.rejected;
    case 'MISSED':
      return CallStatus.missed;
    case 'ENDED':
      return CallStatus.ended;
    case 'CANCELLED':
      return CallStatus.cancelled;
    default:
      return CallStatus.ringing;
  }
}

class CallRecord {
  final int id;
  final String roomName;
  final CallKind kind;
  final CallStatus status;
  final int callerId;
  final int calleeId;
  final String callerName;
  final String calleeName;
  final String? reservationReference;
  final DateTime startedAt;
  final DateTime? answeredAt;
  final DateTime? endedAt;
  final int durationSeconds;
  final String liveKitUrl;

  const CallRecord({
    required this.id,
    required this.roomName,
    required this.kind,
    required this.status,
    required this.callerId,
    required this.calleeId,
    required this.callerName,
    required this.calleeName,
    this.reservationReference,
    required this.startedAt,
    this.answeredAt,
    this.endedAt,
    required this.durationSeconds,
    required this.liveKitUrl,
  });

  factory CallRecord.fromJson(Map<String, dynamic> j) => CallRecord(
        id: _asInt(j['id']),
        roomName: _asStr(j['room_name']),
        kind: _asStr(j['kind'], 'VOICE') == 'VIDEO'
            ? CallKind.video
            : CallKind.voice,
        status: callStatusFromString(_asStr(j['status'])),
        callerId: _asInt(j['caller_id']),
        calleeId: _asInt(j['callee_id']),
        callerName: _asStr(j['caller_name']),
        calleeName: _asStr(j['callee_name']),
        reservationReference: j['reservation_reference']?.toString(),
        startedAt: _asDate(j['started_at']) ?? DateTime.now(),
        answeredAt: _asDate(j['answered_at']),
        endedAt: _asDate(j['ended_at']),
        durationSeconds: _asInt(j['duration_seconds']),
        liveKitUrl: _asStr(j['livekit_url']),
      );

  bool get isVideo => kind == CallKind.video;
}

class CallInvite {
  final CallRecord call;
  final String token;
  final bool resumed;

  const CallInvite({required this.call, required this.token, this.resumed = false});

  factory CallInvite.fromJson(Map<String, dynamic> j) => CallInvite(
        call: CallRecord.fromJson(Map<String, dynamic>.from(j['call'] as Map)),
        token: _asStr(j['token']),
        resumed: j['resumed'] == true,
      );
}

// ---------------------------------------------------------------------------
// Reservation timeline step (purely UI-side)
// ---------------------------------------------------------------------------
class ReservationStep {
  final String code;
  final String label;
  final bool reached;
  final bool active;
  final DateTime? at;

  const ReservationStep({
    required this.code,
    required this.label,
    required this.reached,
    required this.active,
    this.at,
  });
}

List<ReservationStep> buildReservationTimeline({
  required String currentStatut,
  bool acompteValide = false,
  DateTime? createdAt,
  DateTime? prestationTermineeAt,
  DateTime? clientConfirmeAt,
  DateTime? fundsReleasedAt,
}) {
  // Ordre canonique
  const order = [
    'DEMANDE_ENVOYEE',
    'DEVIS_ENVOYE',
    'DEVIS_ACCEPTE',
    'ACOMPTE_VERSE',
    'INTERVENTION_EN_COURS',
    'Terminee',
    'Confirmee',
    'FONDS_LIBERES',
  ];
  const labels = {
    'DEMANDE_ENVOYEE': 'Demande envoyée',
    'DEVIS_ENVOYE': 'Devis reçu',
    'DEVIS_ACCEPTE': 'Devis accepté',
    'ACOMPTE_VERSE': 'Acompte versé',
    'INTERVENTION_EN_COURS': 'Intervention en cours',
    'Terminee': 'Travaux terminés',
    'Confirmee': 'Travaux confirmés',
    'FONDS_LIBERES': 'Fonds libérés',
  };

  int currentIdx = order.indexOf(currentStatut);
  if (currentIdx < 0) currentIdx = 0;

  // Étape "acompte versé" est virtuelle : positionnée après DEVIS_ACCEPTE
  // si acompteValide=true.
  final steps = order.map((code) {
    bool reached;
    DateTime? at;
    switch (code) {
      case 'DEVIS_ACCEPTE':
        // Si l'acompte est versé, le devis a FORCÉMENT été accepté avant →
        // ne jamais laisser cette étape grise alors que la suivante est verte.
        reached = order.indexOf(code) <= currentIdx || acompteValide;
        break;
      case 'ACOMPTE_VERSE':
        reached = acompteValide || currentIdx >= order.indexOf('INTERVENTION_EN_COURS');
        break;
      case 'Terminee':
        reached = prestationTermineeAt != null ||
            currentIdx >= order.indexOf('Terminee');
        at = prestationTermineeAt;
        break;
      case 'Confirmee':
        reached = clientConfirmeAt != null ||
            currentIdx >= order.indexOf('Confirmee');
        at = clientConfirmeAt;
        break;
      case 'FONDS_LIBERES':
        reached = fundsReleasedAt != null;
        at = fundsReleasedAt;
        break;
      default:
        reached = order.indexOf(code) <= currentIdx;
        if (code == 'DEMANDE_ENVOYEE') at = createdAt;
    }
    final active = code == currentStatut ||
        (code == 'ACOMPTE_VERSE' && acompteValide &&
         currentStatut == 'DEVIS_ACCEPTE');
    return ReservationStep(
      code: code,
      label: labels[code] ?? code,
      reached: reached,
      active: active,
      at: at,
    );
  }).toList();

  // MONOTONICITÉ : une étape atteinte implique que TOUTES les précédentes le
  // sont. Évite tout maillon grisé au milieu (ex. « Devis accepté » gris alors
  // que « Acompte versé » est vert).
  int lastReached = -1;
  for (int i = 0; i < steps.length; i++) {
    if (steps[i].reached) lastReached = i;
  }
  for (int i = 0; i < lastReached; i++) {
    if (!steps[i].reached) {
      steps[i] = ReservationStep(
        code: steps[i].code,
        label: steps[i].label,
        reached: true,
        active: steps[i].active,
        at: steps[i].at,
      );
    }
  }
  return steps;
}
