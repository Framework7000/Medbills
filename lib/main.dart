import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_options.dart';
import 'presentation/app.dart';
import 'presentation/theme.dart';
import 'state/providers.dart';

/// The installed apps (iPhone, Mac, Windows, Android) always use the shared
/// store database — they never fall back to demo data, so a bill can never
/// be made into a store that isn't the real one. The web build is a demo
/// unless built with `--dart-define=ENABLE_FIREBASE_WEB=true`.
const _firebaseOnWeb = bool.fromEnvironment('ENABLE_FIREBASE_WEB');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb && !_firebaseOnWeb) {
    _run(cloud: false);
    return;
  }
  await _startCloud();
}

Future<void> _startCloud() async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      // Local cache: stock and bills stay readable during a network drop.
      // Sales themselves are transactions and need a connection.
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    }
    _run(cloud: true);
  } catch (e) {
    runApp(_StartupFailed(error: '$e', onRetry: _startCloud));
  }
}

void _run({required bool cloud}) {
  runApp(ProviderScope(
    overrides: [cloudModeProvider.overrideWithValue(cloud)],
    child: const MedBillsApp(),
  ));
}

class _StartupFailed extends StatelessWidget {
  const _StartupFailed({required this.error, required this.onRetry});
  final String error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(Space.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.cloud_off_outlined, size: 48, color: AppColors.danger),
                  const SizedBox(height: Space.l),
                  Text('MedBills could not start', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: Space.s),
                  const Text(
                    'Check the internet connection and try again. If it keeps happening, restart the device.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Space.s),
                  Text(error,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted)),
                  const SizedBox(height: Space.l),
                  FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Try again')),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
