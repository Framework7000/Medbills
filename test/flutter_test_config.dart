import 'dart:async';

import 'package:nuskha_pms/presentation/scan/scan_billing.dart';

/// Runs before every test file. Widget tests have no camera, so a phone-sized
/// app starts on Billing as before instead of opening the scanner.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  PhoneStartup.scannerFirst = false;
  await testMain();
}
