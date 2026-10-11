import 'date_value.dart';

enum UserRole {
  owner,
  pharmacist,
  counterStaff;

  static UserRole fromString(String? value) {
    return UserRole.values.firstWhere(
      (r) => r.name == value,
      orElse: () => UserRole.counterStaff,
    );
  }

  String get label {
    switch (this) {
      case UserRole.owner:
        return 'Owner';
      case UserRole.pharmacist:
        return 'Pharmacist';
      case UserRole.counterStaff:
        return 'Counter Staff';
    }
  }

  /// Stock in, medicine master edits, sale cancellation.
  bool get canManageStock => this == UserRole.owner || this == UserRole.pharmacist;

  bool get canCancelSales => canManageStock;

  bool get canViewReports => canManageStock;

  bool get canEditStore => this == UserRole.owner;
}

class AppUser {
  final String uid;
  final String storeId;
  final String name;
  final String email;
  final UserRole role;
  final bool active;

  const AppUser({
    required this.uid,
    required this.storeId,
    required this.name,
    required this.email,
    required this.role,
    this.active = true,
  });

  factory AppUser.fromMap(Map<String, dynamic> map) {
    return AppUser(
      uid: readString(map['uid']),
      storeId: readString(map['storeId']),
      name: readString(map['name'], 'Staff'),
      email: readString(map['email']),
      role: UserRole.fromString(map['role'] as String?),
      active: map['active'] == true,
    );
  }
}
