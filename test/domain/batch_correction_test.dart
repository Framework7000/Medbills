import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/domain/services/batch_correction.dart';

import '../support/fixtures.dart';

void main() {
  final now = DateTime(2026, 11, 3);
  final b = batch('dolo', 'DL2401', expiry: DateTime(2027, 12, 31), mrpPaise: 3360, costPaise: 2400);

  BatchCorrection fix({DateTime? expiry, DateTime? received, int? mrp, int? cost}) => BatchCorrection(
        expiryDate: expiry ?? b.expiryDate,
        receivedAt: received ?? b.createdAt,
        mrpPaise: mrp ?? b.mrpPaise,
        purchasePricePaise: cost ?? b.purchasePricePaise,
      );

  test('no change is recognised as no change', () {
    expect(fix().changes(b), isFalse);
    expect(fix().describeAgainst(b), isEmpty);
  });

  test('describes only what changed, old to new', () {
    final c = fix(expiry: DateTime(2028, 3, 31), mrp: 3500);
    expect(c.changes(b), isTrue);
    expect(c.describeAgainst(b), 'expiry 12/2027 → 03/2028, MRP ₹33.60 → ₹35.00');
  });

  test('a received-date change on the same day is not a change', () {
    final c = fix(received: DateTime(b.createdAt.year, b.createdAt.month, b.createdAt.day, 18, 30));
    expect(c.changes(b), isFalse);
  });

  test('refuses nonsense with plain reasons', () {
    expect(fix().problems(now), isEmpty);
    expect(fix(mrp: 0).problems(now), ['Enter the MRP.']);
    expect(fix(cost: -1).problems(now), ['Enter the purchase price.']);
    expect(fix(expiry: DateTime(1999, 1, 31)).problems(now), ['Check the expiry year.']);
    expect(fix(received: DateTime(2026, 12, 25)).problems(now), ['Received date cannot be in the future.']);
    expect(fix(received: DateTime(2026, 11, 3)).problems(now), isEmpty, reason: 'today is fine');
    expect(fix(received: DateTime(2026, 11, 4)).problems(now), isEmpty, reason: 'one day of timezone slack');
  });
}
