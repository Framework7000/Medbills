import 'package:flutter_riverpod/flutter_riverpod.dart';

enum UserRole { owner, pharmacist, counterStaff }

class UserProfile {
  final String name;
  final UserRole role;

  const UserProfile({required this.name, required this.role});
}

class UserAuthNotifier extends StateNotifier<UserProfile> {
  UserAuthNotifier()
      : super(const UserProfile(name: 'Yash Bhaiya', role: UserRole.pharmacist));

  void loginAsYashBhaiya() {
    state = const UserProfile(name: 'Yash Bhaiya', role: UserRole.pharmacist);
  }

  void loginAsOwner() {
    state = const UserProfile(name: 'Store Owner', role: UserRole.owner);
  }

  void loginAsCounterStaff() {
    state = const UserProfile(name: 'Counter Staff', role: UserRole.counterStaff);
  }
}

final userAuthProvider = StateNotifierProvider<UserAuthNotifier, UserProfile>((ref) {
  return UserAuthNotifier();
});
