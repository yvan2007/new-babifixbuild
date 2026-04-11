# À exécuter si tu veux régénérer Firebase (ex. après ajout iOS).
# Usage : PowerShell — peut demander connexion Google dans le navigateur.
Set-Location "$PSScriptRoot\..\babifix_client_flutter"
flutter pub get
flutterfire configure
