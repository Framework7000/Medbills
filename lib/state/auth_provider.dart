import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Streams the current Firebase auth user. Not yet wired to real login UI
/// (see blueprint section 17, limitation 3) — the app currently drives
/// role state from [userAuthProvider] with hardcoded profiles.
final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});
