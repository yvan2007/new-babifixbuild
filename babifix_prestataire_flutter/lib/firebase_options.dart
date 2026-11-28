import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

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
    apiKey: 'AIzaSyCN3ZTrGvUi7bt6PbUcTIMvxziHej6EJgw',
    appId: '1:583956327591:ios:d7a5d8578338310ec9bf82',
    messagingSenderId: '583956327591',
    projectId: 'babifix-b6454',
    storageBucket: 'babifix-b6454.firebasestorage.app',
    iosClientId:
        '583956327591-0l9n3anpn4bsndscsfqd18om7j2472pf.apps.googleusercontent.com',
    iosBundleId: 'com.babifix.babifixPrestataireFlutter',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDXVEZS3Q530r3BN4ahhfO9R5w5wUiByIw',
    appId: '1:583956327591:web:ebf65c598f2b4a1ac9bf82',
    messagingSenderId: '583956327591',
    projectId: 'babifix-b6454',
    authDomain: 'babifix-b6454.firebaseapp.com',
    storageBucket: 'babifix-b6454.firebasestorage.app',
    measurementId: 'G-Y35LX0146N',
  );
}
