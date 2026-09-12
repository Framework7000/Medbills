// `web` below carries real credentials for the `medbills-176df` Firebase
// project (fetched via the Firebase Management API using a service
// account, since `flutterfire configure`'s own CLI login couldn't reach
// Firebase's auth infrastructure from this environment). Firestore has
// been seeded with the 42-medicine Madhya Pradesh catalogue via
// scripts/seed_mp_medicines.dart.
//
// android/ios/macos/windows still carry placeholder values — only a Web
// App was registered on this project. Run `flutterfire configure` for a
// project you own to fill those in for the other platforms:
//   dart pub global activate flutterfire_cli
//   flutterfire configure
//
// main.dart wraps Firebase.initializeApp() in a try/catch and, on web,
// skips the call entirely while a platform's config still carries
// placeholder values — see the comment there for why.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for this platform. '
          'Run `flutterfire configure` to generate real options.',
        );
    }
  }

  static const web = FirebaseOptions(
    apiKey: 'AIzaSyD7T4EYOVti0OA0SyBC2Pr1-khnC3E6c0c',
    appId: '1:773457964393:web:c445deb0d17fcb944ce1f8',
    messagingSenderId: '773457964393',
    projectId: 'medbills-176df',
    authDomain: 'medbills-176df.firebaseapp.com',
    storageBucket: 'medbills-176df.firebasestorage.app',
  );

  static const android = FirebaseOptions(
    apiKey: 'REPLACE_WITH_YOUR_API_KEY',
    appId: 'REPLACE_WITH_YOUR_APP_ID',
    messagingSenderId: 'REPLACE_WITH_YOUR_SENDER_ID',
    projectId: 'REPLACE_WITH_YOUR_PROJECT_ID',
    storageBucket: 'REPLACE_WITH_YOUR_PROJECT_ID.appspot.com',
  );

  static const ios = FirebaseOptions(
    apiKey: 'REPLACE_WITH_YOUR_API_KEY',
    appId: 'REPLACE_WITH_YOUR_APP_ID',
    messagingSenderId: 'REPLACE_WITH_YOUR_SENDER_ID',
    projectId: 'REPLACE_WITH_YOUR_PROJECT_ID',
    storageBucket: 'REPLACE_WITH_YOUR_PROJECT_ID.appspot.com',
    iosBundleId: 'com.medbills.nuskhaPms',
  );

  static const macos = FirebaseOptions(
    apiKey: 'REPLACE_WITH_YOUR_API_KEY',
    appId: 'REPLACE_WITH_YOUR_APP_ID',
    messagingSenderId: 'REPLACE_WITH_YOUR_SENDER_ID',
    projectId: 'REPLACE_WITH_YOUR_PROJECT_ID',
    storageBucket: 'REPLACE_WITH_YOUR_PROJECT_ID.appspot.com',
    iosBundleId: 'com.medbills.nuskhaPms',
  );

  static const windows = FirebaseOptions(
    apiKey: 'REPLACE_WITH_YOUR_API_KEY',
    appId: 'REPLACE_WITH_YOUR_APP_ID',
    messagingSenderId: 'REPLACE_WITH_YOUR_SENDER_ID',
    projectId: 'REPLACE_WITH_YOUR_PROJECT_ID',
    storageBucket: 'REPLACE_WITH_YOUR_PROJECT_ID.appspot.com',
  );
}
