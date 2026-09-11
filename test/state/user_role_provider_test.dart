import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/state/user_role_provider.dart';

void main() {
  group('UserAuthNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
      addTearDown(container.dispose);
    });

    test('defaults to Yash Bhaiya as Pharmacist', () {
      final profile = container.read(userAuthProvider);
      expect(profile.name, 'Yash Bhaiya');
      expect(profile.role, UserRole.pharmacist);
    });

    test('switches to Owner', () {
      container.read(userAuthProvider.notifier).loginAsOwner();
      expect(container.read(userAuthProvider).role, UserRole.owner);
    });

    test('switches to Counter Staff', () {
      container.read(userAuthProvider.notifier).loginAsCounterStaff();
      expect(container.read(userAuthProvider).role, UserRole.counterStaff);
    });
  });
}
