import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fr'),
  ];

  /// The title of the application
  ///
  /// In fr, this message translates to:
  /// **'BABIFIX'**
  String get appTitle;

  /// No description provided for @welcome.
  ///
  /// In fr, this message translates to:
  /// **'Bienvenue sur BABIFIX'**
  String get welcome;

  /// No description provided for @login.
  ///
  /// In fr, this message translates to:
  /// **'Connexion'**
  String get login;

  /// No description provided for @register.
  ///
  /// In fr, this message translates to:
  /// **'S\'inscrire'**
  String get register;

  /// No description provided for @email.
  ///
  /// In fr, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @password.
  ///
  /// In fr, this message translates to:
  /// **'Mot de passe'**
  String get password;

  /// No description provided for @phone.
  ///
  /// In fr, this message translates to:
  /// **'Téléphone'**
  String get phone;

  /// No description provided for @address.
  ///
  /// In fr, this message translates to:
  /// **'Adresse'**
  String get address;

  /// No description provided for @home.
  ///
  /// In fr, this message translates to:
  /// **'Accueil'**
  String get home;

  /// No description provided for @services.
  ///
  /// In fr, this message translates to:
  /// **'Services'**
  String get services;

  /// No description provided for @bookings.
  ///
  /// In fr, this message translates to:
  /// **'Réservations'**
  String get bookings;

  /// No description provided for @messages.
  ///
  /// In fr, this message translates to:
  /// **'Messages'**
  String get messages;

  /// No description provided for @profile.
  ///
  /// In fr, this message translates to:
  /// **'Profil'**
  String get profile;

  /// No description provided for @settings.
  ///
  /// In fr, this message translates to:
  /// **'Paramètres'**
  String get settings;

  /// No description provided for @logout.
  ///
  /// In fr, this message translates to:
  /// **'Déconnexion'**
  String get logout;

  /// No description provided for @save.
  ///
  /// In fr, this message translates to:
  /// **'Enregistrer'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In fr, this message translates to:
  /// **'Annuler'**
  String get cancel;

  /// No description provided for @confirm.
  ///
  /// In fr, this message translates to:
  /// **'Confirmer'**
  String get confirm;

  /// No description provided for @search.
  ///
  /// In fr, this message translates to:
  /// **'Rechercher'**
  String get search;

  /// No description provided for @categories.
  ///
  /// In fr, this message translates to:
  /// **'Catégories'**
  String get categories;

  /// No description provided for @prestataire.
  ///
  /// In fr, this message translates to:
  /// **'Prestataire'**
  String get prestataire;

  /// No description provided for @prestataires.
  ///
  /// In fr, this message translates to:
  /// **'Prestataires'**
  String get prestataires;

  /// No description provided for @reservation.
  ///
  /// In fr, this message translates to:
  /// **'Réservation'**
  String get reservation;

  /// No description provided for @reservations.
  ///
  /// In fr, this message translates to:
  /// **'Réservations'**
  String get reservations;

  /// No description provided for @makeReservation.
  ///
  /// In fr, this message translates to:
  /// **'Réserver'**
  String get makeReservation;

  /// No description provided for @pay.
  ///
  /// In fr, this message translates to:
  /// **'Payer'**
  String get pay;

  /// No description provided for @payment.
  ///
  /// In fr, this message translates to:
  /// **'Paiement'**
  String get payment;

  /// No description provided for @confirmReservation.
  ///
  /// In fr, this message translates to:
  /// **'Confirmer la réservation'**
  String get confirmReservation;

  /// No description provided for @cancelReservation.
  ///
  /// In fr, this message translates to:
  /// **'Annuler la réservation'**
  String get cancelReservation;

  /// No description provided for @rate.
  ///
  /// In fr, this message translates to:
  /// **'Noter'**
  String get rate;

  /// No description provided for @addReview.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter un avis'**
  String get addReview;

  /// No description provided for @chat.
  ///
  /// In fr, this message translates to:
  /// **'Chat'**
  String get chat;

  /// No description provided for @sendMessage.
  ///
  /// In fr, this message translates to:
  /// **'Envoyer'**
  String get sendMessage;

  /// No description provided for @typeMessage.
  ///
  /// In fr, this message translates to:
  /// **'Tapez votre message...'**
  String get typeMessage;

  /// No description provided for @noMessages.
  ///
  /// In fr, this message translates to:
  /// **'Aucun message'**
  String get noMessages;

  /// No description provided for @noReservations.
  ///
  /// In fr, this message translates to:
  /// **'Aucune réservation'**
  String get noReservations;

  /// No description provided for @noProviders.
  ///
  /// In fr, this message translates to:
  /// **'Aucun prestataire'**
  String get noProviders;

  /// No description provided for @noResults.
  ///
  /// In fr, this message translates to:
  /// **'Aucun résultat'**
  String get noResults;

  /// No description provided for @loading.
  ///
  /// In fr, this message translates to:
  /// **'Chargement...'**
  String get loading;

  /// No description provided for @error.
  ///
  /// In fr, this message translates to:
  /// **'Erreur'**
  String get error;

  /// No description provided for @retry.
  ///
  /// In fr, this message translates to:
  /// **'Réessayer'**
  String get retry;

  /// No description provided for @success.
  ///
  /// In fr, this message translates to:
  /// **'Succès'**
  String get success;

  /// No description provided for @offline.
  ///
  /// In fr, this message translates to:
  /// **'Vous êtes hors ligne'**
  String get offline;

  /// No description provided for @biometricLogin.
  ///
  /// In fr, this message translates to:
  /// **'Connexion biométrique'**
  String get biometricLogin;

  /// No description provided for @forgotPassword.
  ///
  /// In fr, this message translates to:
  /// **'Mot de passe oublié ?'**
  String get forgotPassword;

  /// No description provided for @dontHaveAccount.
  ///
  /// In fr, this message translates to:
  /// **'Pas de compte ?'**
  String get dontHaveAccount;

  /// No description provided for @alreadyHaveAccount.
  ///
  /// In fr, this message translates to:
  /// **'Déjà un compte ?'**
  String get alreadyHaveAccount;

  /// No description provided for @client.
  ///
  /// In fr, this message translates to:
  /// **'Client'**
  String get client;

  /// No description provided for @provider.
  ///
  /// In fr, this message translates to:
  /// **'Prestataire'**
  String get provider;

  /// No description provided for @admin.
  ///
  /// In fr, this message translates to:
  /// **'Administrateur'**
  String get admin;

  /// No description provided for @pending.
  ///
  /// In fr, this message translates to:
  /// **'En attente'**
  String get pending;

  /// No description provided for @accepted.
  ///
  /// In fr, this message translates to:
  /// **'Accepté'**
  String get accepted;

  /// No description provided for @refused.
  ///
  /// In fr, this message translates to:
  /// **'Refusé'**
  String get refused;

  /// No description provided for @confirmed.
  ///
  /// In fr, this message translates to:
  /// **'Confirmé'**
  String get confirmed;

  /// No description provided for @cancelled.
  ///
  /// In fr, this message translates to:
  /// **'Annulé'**
  String get cancelled;

  /// No description provided for @completed.
  ///
  /// In fr, this message translates to:
  /// **'Terminé'**
  String get completed;

  /// No description provided for @inProgress.
  ///
  /// In fr, this message translates to:
  /// **'En cours'**
  String get inProgress;

  /// No description provided for @total.
  ///
  /// In fr, this message translates to:
  /// **'Total'**
  String get total;

  /// No description provided for @date.
  ///
  /// In fr, this message translates to:
  /// **'Date'**
  String get date;

  /// No description provided for @time.
  ///
  /// In fr, this message translates to:
  /// **'Heure'**
  String get time;

  /// No description provided for @status.
  ///
  /// In fr, this message translates to:
  /// **'Statut'**
  String get status;

  /// No description provided for @amount.
  ///
  /// In fr, this message translates to:
  /// **'Montant'**
  String get amount;

  /// No description provided for @fcfa.
  ///
  /// In fr, this message translates to:
  /// **'FCFA'**
  String get fcfa;

  /// No description provided for @selectCategory.
  ///
  /// In fr, this message translates to:
  /// **'Sélectionner une catégorie'**
  String get selectCategory;

  /// No description provided for @selectProvider.
  ///
  /// In fr, this message translates to:
  /// **'Sélectionner un prestataire'**
  String get selectProvider;

  /// No description provided for @selectDate.
  ///
  /// In fr, this message translates to:
  /// **'Sélectionner une date'**
  String get selectDate;

  /// No description provided for @selectTime.
  ///
  /// In fr, this message translates to:
  /// **'Sélectionner un créneau'**
  String get selectTime;

  /// No description provided for @choosePaymentMethod.
  ///
  /// In fr, this message translates to:
  /// **'Choisir le mode de paiement'**
  String get choosePaymentMethod;

  /// No description provided for @orangeMoney.
  ///
  /// In fr, this message translates to:
  /// **'Orange Money'**
  String get orangeMoney;

  /// No description provided for @mtnMoney.
  ///
  /// In fr, this message translates to:
  /// **'MTN Moov Money'**
  String get mtnMoney;

  /// No description provided for @wave.
  ///
  /// In fr, this message translates to:
  /// **'Wave'**
  String get wave;

  /// No description provided for @cash.
  ///
  /// In fr, this message translates to:
  /// **'Espèces'**
  String get cash;

  /// No description provided for @reservationConfirmed.
  ///
  /// In fr, this message translates to:
  /// **'Réservation confirmée !'**
  String get reservationConfirmed;

  /// No description provided for @reservationCancelled.
  ///
  /// In fr, this message translates to:
  /// **'Réservation annulée'**
  String get reservationCancelled;

  /// No description provided for @thankYou.
  ///
  /// In fr, this message translates to:
  /// **'Merci !'**
  String get thankYou;

  /// No description provided for @orderPlaced.
  ///
  /// In fr, this message translates to:
  /// **'Votre réservation a été enregistrée'**
  String get orderPlaced;

  /// No description provided for @providersNearYou.
  ///
  /// In fr, this message translates to:
  /// **'Prestataires près de chez vous'**
  String get providersNearYou;

  /// No description provided for @bookIn30Seconds.
  ///
  /// In fr, this message translates to:
  /// **'Réservez en 30 secondes'**
  String get bookIn30Seconds;

  /// No description provided for @paySimply.
  ///
  /// In fr, this message translates to:
  /// **'Payez en FCA, simplement'**
  String get paySimply;

  /// No description provided for @artisansVerified.
  ///
  /// In fr, this message translates to:
  /// **'Artisans vérifiés près de chez vous'**
  String get artisansVerified;

  /// No description provided for @plumbing.
  ///
  /// In fr, this message translates to:
  /// **'Plomberie'**
  String get plumbing;

  /// No description provided for @electricity.
  ///
  /// In fr, this message translates to:
  /// **'Électricité'**
  String get electricity;

  /// No description provided for @cleaning.
  ///
  /// In fr, this message translates to:
  /// **'Ménage'**
  String get cleaning;

  /// No description provided for @painting.
  ///
  /// In fr, this message translates to:
  /// **'Peinture'**
  String get painting;

  /// No description provided for @gardening.
  ///
  /// In fr, this message translates to:
  /// **'Jardinage'**
  String get gardening;

  /// No description provided for @cooking.
  ///
  /// In fr, this message translates to:
  /// **'Cuisine'**
  String get cooking;

  /// No description provided for @childcare.
  ///
  /// In fr, this message translates to:
  /// **'Garde d\'enfants'**
  String get childcare;

  /// No description provided for @lessons.
  ///
  /// In fr, this message translates to:
  /// **'Cours particuliers'**
  String get lessons;

  /// No description provided for @viewAll.
  ///
  /// In fr, this message translates to:
  /// **'Voir tout'**
  String get viewAll;

  /// No description provided for @viewProfile.
  ///
  /// In fr, this message translates to:
  /// **'Voir le profil'**
  String get viewProfile;

  /// No description provided for @addToFavorites.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter aux favoris'**
  String get addToFavorites;

  /// No description provided for @removeFromFavorites.
  ///
  /// In fr, this message translates to:
  /// **'Retirer des favoris'**
  String get removeFromFavorites;

  /// No description provided for @contactProvider.
  ///
  /// In fr, this message translates to:
  /// **'Contacter le prestataire'**
  String get contactProvider;

  /// No description provided for @about.
  ///
  /// In fr, this message translates to:
  /// **'À propos'**
  String get about;

  /// No description provided for @version.
  ///
  /// In fr, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @termsOfService.
  ///
  /// In fr, this message translates to:
  /// **'Conditions générales d\'utilisation'**
  String get termsOfService;

  /// No description provided for @privacyPolicy.
  ///
  /// In fr, this message translates to:
  /// **'Politique de confidentialité'**
  String get privacyPolicy;

  /// No description provided for @help.
  ///
  /// In fr, this message translates to:
  /// **'Aide'**
  String get help;

  /// No description provided for @notifications.
  ///
  /// In fr, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @enableNotifications.
  ///
  /// In fr, this message translates to:
  /// **'Activer les notifications'**
  String get enableNotifications;

  /// No description provided for @darkMode.
  ///
  /// In fr, this message translates to:
  /// **'Mode sombre'**
  String get darkMode;

  /// No description provided for @language.
  ///
  /// In fr, this message translates to:
  /// **'Langue'**
  String get language;

  /// No description provided for @french.
  ///
  /// In fr, this message translates to:
  /// **'Français'**
  String get french;

  /// No description provided for @english.
  ///
  /// In fr, this message translates to:
  /// **'English'**
  String get english;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
