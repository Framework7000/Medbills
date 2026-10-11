import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_options.dart';
import 'presentation/app.dart';
import 'state/providers.dart';

/// The installed apps (iPhone, Mac, Windows, Android) always use the shared
/// cloud store. The web build is a demo unless built with
/// `--dart-define=ENABLE_FIREBASE_WEB=true`.
const _firebaseOnWeb = bool.fromEnvironment('ENABLE_FIREBASE_WEB');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var cloud = false;
  if (!kIsWeb || _firebaseOnWeb) {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      // Local cache: stock and bills stay readable during a network drop.
      // Sales themselves are transactions and need a connection.
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
      cloud = true;
    } catch (e, st) {
      debugPrint('Firebase init failed, starting demo mode: $e\n$st');
    }
  }
  runApp(ProviderScope(
    overrides: [cloudModeProvider.overrideWithValue(cloud)],
    child: const MedBillsApp(),
  ));
}
