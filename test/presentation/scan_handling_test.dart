import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/presentation/scan/scan_billing.dart';
import 'package:nuskha_pms/state/providers.dart';

String _b64(Object json) => base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');

/// Runs real scans through the same handler the camera and USB scanner use.
void main() {
  late WidgetRef ref;
  late BuildContext context;

  // Signed in first, as in real use (the receiving list is cleared when
  // the signed-in user changes).
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Consumer(builder: (c, r, _) {
          ref = r;
          context = c;
          r.watch(currentUserProvider);
          r.watch(stockIndexProvider); // loaded, as the scan screens keep it
          return const SizedBox();
        }),
      ),
    ));
    await tester.pumpAndSettle();
    expect(ref.read(currentUserProvider), isNotNull);
    expect(ref.read(stockIndexProvider).hasValue, isTrue);
  }

  testWidgets('a supplier bill QR is read out, not rejected as an unknown barcode', (tester) async {
    await pump(tester);
    final qr = '${_b64({'alg': 'RS256', 'typ': 'JWT'})}.'
        '${_b64({'data': jsonEncode({'SellerGstin': '23AAKFS1234C1Z9', 'BuyerGstin': '23ABCDE1234F1Z5', 'DocNo': 'SSP/2627/0456', 'DocTyp': 'INV', 'DocDt': '08/10/2026', 'TotInvVal': 15998.5, 'ItemCnt': 12, 'MainHsnCode': '3004', 'Irn': 'abc'}), 'iss': 'NIC'})}.'
        'c2ln';
    final feedback = await handleScannedCode(context, ref, qr);
    expect(feedback.ok, isTrue);
    expect(feedback.message, contains('Supplier bill'));
    expect(feedback.message, contains('SSP/2627/0456'));
    expect(feedback.message, contains('15,998.5'));
    expect(feedback.actionLabel, 'Details');
  });

  testWidgets('an expired pack is refused with a clear warning', (tester) async {
    await pump(tester);
    final feedback = await handleScannedCode(context, ref, '(01)08901234567890(17)200100(10)OLD1');
    expect(feedback.ok, isFalse);
    expect(feedback.message, contains('EXPIRED'));
  });

  testWidgets('on the phone in Receiving mode a pack code goes onto the receiving list with its batch, expiry and MRP',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await pump(tester);
      ref.read(scanModeProvider.notifier).state = ScanMode.receiving;
      final feedback = await handleScannedCode(
          context, ref, 'Brand Name: Dolo 650 | Batch No: DOBS3975 | Exp Date: 05/2030 | MRP: Rs. 33.60');
      expect(feedback.ok, isTrue);
      expect(feedback.message, contains('receiving draft'));
      final line = ref.read(receivingDraftProvider).lines.single;
      expect(line.medicineName, startsWith('Dolo 650'));
      expect(line.batchNumber, 'DOBS3975');
      expect((line.expiryMonth, line.expiryYear), (5, 2030));
      expect(line.mrpPaise, 3360);
      // The same pack again is one more pack on the same line.
      await handleScannedCode(context, ref, 'Brand Name: Dolo 650 | Batch No: DOBS3975 | Exp Date: 05/2030');
      expect(ref.read(receivingDraftProvider).lines.single.packs, 2);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
