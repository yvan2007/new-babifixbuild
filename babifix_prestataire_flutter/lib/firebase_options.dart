// Aligné sur Firebase projet « babifix » — app Android com.babifix.prestataire
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
    appId: '1:772061649757:android:6654bfe8e363d4b99726b4',
    messagingSenderId: '772061649757',
    projectId: 'babifix',
    storageBucket: 'babifix.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCCDzdHbBeHdoe08f7XrfPzvDsdnJkda7w',
    appId: '1:772061649757:ios:CONFIGUREZ_IOS',
    messagingSenderId: '772061649757',
    projectId: 'babifix',
    storageBucket: 'babifix.firebasestorage.app',
    iosBundleId: 'com.babifix.prestataire',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCCDzdHbBeHdoe08f7XrfPzvDsdnJkda7w',
    appId: '1:772061649757:web:CONFIGUREZ_WEB',
    messagingSenderId: '772061649757',
    projectId: 'babifix',
    storageBucket: 'babifix.firebasestorage.app',
  );
}
