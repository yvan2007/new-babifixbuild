// Aligné sur Firebase projet « babifix » — exécutez `flutterfire configure` si vous ajoutez iOS/Web.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return ios;
      default:
        return android;
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCCDzdHbBeHdoe08f7XrfPzvDsdnJkda7w',
    appId: '1:772061649757:android:665fd184158ee3259726b4',
    messagingSenderId: '772061649757',
    projectId: 'babifix',
    storageBucket: 'babifix.firebasestorage.app',
  );

  /// À remplacer après ajout d’une app iOS dans Firebase + flutterfire configure.
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCCDzdHbBeHdoe08f7XrfPzvDsdnJkda7w',
    appId: '1:772061649757:ios:CONFIGUREZ_IOS',
    messagingSenderId: '772061649757',
    projectId: 'babifix',
    storageBucket: 'babifix.firebasestorage.app',
    iosBundleId: 'com.babifix.client',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCCDzdHbBeHdoe08f7XrfPzvDsdnJkda7w',
    appId: '1:772061649757:web:CONFIGUREZ_WEB',
    messagingSenderId: '772061649757',
    projectId: 'babifix',
    storageBucket: 'babifix.firebasestorage.app',
  );
}
