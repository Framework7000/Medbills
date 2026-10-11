import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../domain/models/app_user.dart';

sealed class SessionState {
  const SessionState();
}

class SessionLoading extends SessionState {
  const SessionLoading();
}

class SignedOut extends SessionState {
  const SignedOut();
}

/// Signed in to Firebase, but no active staff profile for this account.
class NoStoreAccess extends SessionState {
  final String email;
  const NoStoreAccess(this.email);
}

class SignedIn extends SessionState {
  final AppUser user;
  const SignedIn(this.user);
}

class AuthFailure implements Exception {
  final String message;
  const AuthFailure(this.message);

  @override
  String toString() => message;
}

abstract class AuthService {
  bool get isDemo;
  Stream<SessionState> watchSession();
  Future<void> signIn(String email, String password);
  Future<void> signOut();
  Future<void> changePassword(String currentPassword, String newPassword);
}

class FirebaseAuthService implements AuthService {
  FirebaseAuthService(this._auth, this._db);

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  @override
  bool get isDemo => false;

  @override
  Stream<SessionState> watchSession() {
    return _auth.authStateChanges().asyncExpand((user) {
      if (user == null) return Stream<SessionState>.value(const SignedOut());
      return _db.collection('users').doc(user.uid).snapshots().map<SessionState>((snap) {
        final data = snap.data();
        if (!snap.exists || data == null || data['active'] != true) {
          return NoStoreAccess(user.email ?? '');
        }
        return SignedIn(AppUser.fromMap({...data, 'uid': user.uid}));
      }).transform(StreamTransformer<SessionState, SessionState>.fromHandlers(
        handleError: (error, stack, sink) => sink.add(NoStoreAccess(user.email ?? '')),
      ));
    });
  }

  @override
  Future<void> signIn(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_message(e));
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> changePassword(String currentPassword, String newPassword) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) throw const AuthFailure('You are signed out.');
    if (newPassword.length < 8) throw const AuthFailure('New password must be at least 8 characters.');
    try {
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: user.email!, password: currentPassword),
      );
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_message(e));
    }
  }

  static String _message(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'That email address is not valid.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
      case 'INVALID_LOGIN_CREDENTIALS':
        return 'Email or password is incorrect.';
      case 'too-many-requests':
        return 'Too many attempts. Wait a minute and try again.';
      case 'network-request-failed':
        return 'No internet connection. Connect to the internet and try again.';
      case 'weak-password':
        return 'Choose a stronger password (at least 8 characters).';
      case 'requires-recent-login':
        return 'Please sign out and sign in again, then retry.';
      default:
        return e.message ?? 'Sign-in failed (${e.code}).';
    }
  }
}

/// Demo session for the web preview: always signed in, role switchable.
class DemoAuthService implements AuthService {
  DemoAuthService({UserRole role = UserRole.owner}) {
    _emit(role);
  }

  final _controller = StreamController<SessionState>.broadcast();
  late SessionState _current;

  static const storeId = 'demo_store';

  void _emit(UserRole role) {
    _current = SignedIn(AppUser(
      uid: 'demo-${role.name}',
      storeId: storeId,
      name: 'Demo ${role.label}',
      email: 'demo@medbills.local',
      role: role,
    ));
    _controller.add(_current);
  }

  void switchRole(UserRole role) => _emit(role);

  @override
  bool get isDemo => true;

  @override
  Stream<SessionState> watchSession() => Stream<SessionState>.multi((c) {
        c.add(_current);
        final sub = _controller.stream.listen(c.add);
        c.onCancel = sub.cancel;
      });

  @override
  Future<void> signIn(String email, String password) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> changePassword(String currentPassword, String newPassword) async {
    throw const AuthFailure('Passwords can\'t be changed in the demo.');
  }
}
