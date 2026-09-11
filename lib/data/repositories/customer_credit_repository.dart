import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/customer_credit.dart';

/// Rule 3: stock/balance mutations happen inside `runTransaction`, all
/// reads before all writes. Rule 10: the ledger itself is append-only.
class CustomerCreditRepository {
  CustomerCreditRepository(this._firestore);

  final FirebaseFirestore _firestore;
  final _uuid = const Uuid();

  CollectionReference<Map<String, dynamic>> get _customers =>
      _firestore.collection('customerCredits');

  CollectionReference<Map<String, dynamic>> _ledgerOf(String customerId) {
    return _customers.doc(customerId).collection('ledger');
  }

  Stream<List<CustomerCredit>> watchCustomers({required String storeId}) {
    return _customers
        .where('storeId', isEqualTo: storeId)
        .snapshots()
        .map((snap) => snap.docs.map((d) => CustomerCredit.fromMap(d.data())).toList());
  }

  Stream<List<CreditLedgerEntry>> watchLedger(String customerId) {
    return _ledgerOf(customerId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => CreditLedgerEntry.fromMap(d.data())).toList());
  }

  Future<void> appendLedgerEntry({
    required CustomerCredit customer,
    required CreditEntryType type,
    required int amountPaise,
    String? invoiceNumber,
    String notes = '',
  }) async {
    final customerRef = _customers.doc(customer.id);
    final entryRef = _ledgerOf(customer.id).doc(_uuid.v4());

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(customerRef);
      final currentBalance = snapshot.exists
          ? ((snapshot.data()?['outstandingBalancePaise'] as num?)?.toInt() ?? 0)
          : customer.outstandingBalancePaise;

      final delta = type == CreditEntryType.creditSale ? amountPaise : -amountPaise;
      final newBalance = currentBalance + delta;

      final entry = CreditLedgerEntry(
        id: entryRef.id,
        customerId: customer.id,
        type: type,
        amountPaise: amountPaise,
        invoiceNumber: invoiceNumber,
        notes: notes,
        timestamp: DateTime.now(),
      );

      transaction.set(entryRef, entry.toMap());
      transaction.set(
        customerRef,
        customer.copyWith(outstandingBalancePaise: newBalance).toMap(),
      );
    });
  }

  Future<void> saveCustomer(CustomerCredit customer) {
    return _customers.doc(customer.id).set(customer.toMap());
  }
}
