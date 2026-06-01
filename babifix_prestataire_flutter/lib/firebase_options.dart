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
    apiKey: 'AIzaSyDKhKQrtReopLkxJuqdh1-6XvdzooUSgxQ',
    appId: '1:583956327591:android:88a76c5f8efa0875c9bf82',
    messagingSenderId: '583956327591',
    projectId: 'babifix-b6454',
    storageBucket: 'babifix-b6454.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDKhKQrtReopLkxJuqdh1-6XvdzooUSgxQ',
    appId: '1:583956327591:ios:CONFIGUREZ_IOS',
    messagingSenderId: '583956327591',
    projectId: 'babifix-b6454',
    storageBucket: 'babifix-b6454.firebasestorage.app',
    iosBundleId: 'com.babifix.prestataire',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDKhKQrtReopLkxJuqdh1-6XvdzooUSgxQ',
    appId: '1:583956327591:web:CONFIGUREZ_WEB',
    messagingSenderId: '583956327591',
    projectId: 'babifix-b6454',
    storageBucket: 'babifix-b6454.firebasestorage.app',
  );
}
