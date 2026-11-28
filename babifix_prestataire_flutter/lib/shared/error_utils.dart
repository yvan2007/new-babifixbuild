import 'dart:convert';

String userFriendlyError(dynamic error, [int? statusCode]) {
  if (statusCode != null) {
    switch (statusCode) {
      case 400: return 'Requête invalide.';
      case 401: return 'Session expirée. Veuillez vous reconnecter.';
      case 403: return 'Accès refusé.';
      case 404: return 'Introuvable.';
      case 409: return 'Cette action est déjà en cours.';
      case 422: return 'Données invalides.';
      case 429: return 'Trop de tentatives. Réessayez dans quelques instants.';
      case 500: return 'Erreur serveur. Réessayez plus tard.';
      case 502: return 'Service temporairement indisponible.';
      case 503: return 'Maintenance en cours. Réessayez plus tard.';
    }
  }

  if (error == null) return 'Une erreur est survenue. Réessayez.';

  final msg = error.toString().toLowerCase();

  if (msg.contains('connection timed out')) {
    return 'Connexion impossible. Vérifiez votre connexion internet.';
  }
  if (msg.contains('failed host lookup') || msg.contains('no address associated with hostname')) {
    return 'Impossible de joindre le serveur. Vérifiez votre connexion.';
  }
  if (msg.contains('connection refused')) {
    return 'Serveur inaccessible. Réessayez plus tard.';
  }
  if (msg.contains('handshake error') || msg.contains('certificate')) {
    return 'Erreur de sécurité. Mettez l\'application à jour.';
  }
  if (msg.contains('no internet') || msg.contains('network is unreachable')) {
    return 'Pas de connexion internet.';
  }
  if (msg.contains('timeout')) {
    return 'La requête a pris trop de temps. Réessayez.';
  }
  if (msg.contains('format exception') || msg.contains('type')) {
    return 'Données reçues invalides. Réessayez.';
  }

  return 'Une erreur est survenue. Réessayez.';
}

/// Extrait le message d'erreur d'une réponse JSON Django si possible.
/// Retourne null si le corps n'est pas du JSON ou n'a pas de champ detail/error.
String translateErrorCode(String code) {
  switch (code.trim()) {
    case 'forbidden_role':
    case 'role_forbidden':
    case 'wrong_app_role':
      return 'Acces reserve a l\'application Prestataire. Reconnectez-vous avec votre compte Pro.';
    case 'missing_token':
    case 'invalid_token':
    case 'authentication_required':
      return 'Session expiree. Veuillez vous reconnecter.';
    case 'kyc_required_to_operate':
      return 'Completez et faites valider votre dossier KYC avant d\'effectuer cette action.';
    case 'insufficient_wallet_balance':
      return 'Solde Wallet insuffisant pour cette operation.';
    case 'account_disabled':
      return 'Compte suspendu ou desactive. Contactez le support BABIFIX.';
    default:
      return code;
  }
}

String? apiErrorMessage(String body) {
  try {
    final data = jsonDecode(body) as Map<String, dynamic>;
    final msg = data['message'] as String?;
    if (msg != null && msg.isNotEmpty) return msg;
    final detail = data['detail'] as String?;
    if (detail != null && detail.isNotEmpty) return translateErrorCode(detail);
    final error = data['error'] as String?;
    if (error != null && error.isNotEmpty) return translateErrorCode(error);
  } catch (_) {}
  return null;
}
