import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/domain/models/sale_invoice.dart';
import 'package:nuskha_pms/state/bill_history_provider.dart';

void main() {
  group('BillHistoryNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
      addTearDown(container.dispose);
    });

    test('seeds with default invoices', () {
      expect(container.read(billHistoryProvider).length, 2);
    });

    test('addInvoice prepends to history', () {
      final notifier = container.read(billHistoryProvider.notifier);
      final newInvoice = SaleInvoice(
        invoiceNumber: 'INV-NEW',
        storeId: 'store_primary',
        timestamp: DateTime.now(),
        customerName: 'New Customer',
        customerPhone: '9000000000',
        paymentMode: 'Cash',
        grandTotalPaise: 1000,
        gstTotalPaise: 100,
        items: const [],
      );
      notifier.addInvoice(newInvoice);
      expect(container.read(billHistoryProvider).first.invoiceNumber, 'INV-NEW');
    });

    test('purgeOldRecords removes invoices older than 180 days', () {
      final notifier = container.read(billHistoryProvider.notifier);
      final oldInvoice = SaleInvoice(
        invoiceNumber: 'INV-OLD',
        storeId: 'store_primary',
        timestamp: DateTime.now().subtract(const Duration(days: 200)),
        customerName: 'Old Customer',
        customerPhone: '9000000000',
        paymentMode: 'Cash',
        grandTotalPaise: 1000,
        gstTotalPaise: 100,
        items: const [],
      );
      notifier.addInvoice(oldInvoice);
      expect(
        container.read(billHistoryProvider).any((i) => i.invoiceNumber == 'INV-OLD'),
        isFalse,
      );
    });
  });
}
