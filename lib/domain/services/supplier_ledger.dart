import '../models/supplier_account.dart';

/// One credit bill with what has been paid against it so far.
class BillBalance {
  final SupplierBill bill;
  final int paidPaise;
  final DateTime dueOn;

  const BillBalance({required this.bill, required this.paidPaise, required this.dueOn});

  int get balancePaise => bill.totalPaise - paidPaise;
  bool get isPaid => balancePaise <= 0;
  bool get isPartlyPaid => paidPaise > 0 && !isPaid;
  bool isOverdueAt(DateTime now) => !isPaid && DateTime(now.year, now.month, now.day).isAfter(dueOn);
  int daysOverdue(DateTime now) => DateTime(now.year, now.month, now.day).difference(dueOn).inDays;
}

/// Everything about one distributor: bills, payments and what is owed.
class DistributorAccount {
  final Distributor distributor;
  final List<SupplierBill> bills; // newest first, cancelled left out
  final List<SupplierPayment> payments; // newest first, cancelled left out
  final List<BillBalance> creditBills; // oldest first

  const DistributorAccount({
    required this.distributor,
    required this.bills,
    required this.payments,
    required this.creditBills,
  });

  int get creditBilledPaise => creditBills.fold(0, (s, b) => s + b.bill.totalPaise);
  int get cashBilledPaise => bills.where((b) => !b.isCredit).fold(0, (s, b) => s + b.totalPaise);
  int get paidPaise => payments.fold(0, (s, p) => s + p.amountPaise);

  /// What the shop still owes (negative = paid in advance).
  int get outstandingPaise => creditBilledPaise - paidPaise;

  List<BillBalance> get unpaid => creditBills.where((b) => !b.isPaid).toList();

  BillBalance? get nextDue {
    final open = unpaid..sort((a, b) => a.dueOn.compareTo(b.dueOn));
    return open.isEmpty ? null : open.first;
  }
}

/// A credit bill to pay soon or already late.
class PaymentReminder {
  final DistributorAccount account;
  final BillBalance bill;
  const PaymentReminder(this.account, this.bill);
}

class SupplierLedger {
  final Map<String, DistributorAccount> accounts;
  const SupplierLedger(this.accounts);

  /// Reminders are shown this many days before a bill falls due.
  static const remindDaysBefore = 3;

  static String _key(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static SupplierLedger build({
    required List<Distributor> distributors,
    required List<SupplierBill> bills,
    required List<SupplierPayment> payments,
  }) {
    final byId = {for (final d in distributors) d.id: d};
    // A bill or payment may name a distributor not yet in the list.
    Distributor of(String id, String name) => byId.putIfAbsent(
          id,
          () => Distributor(id: id, storeId: '', name: name, createdAt: DateTime.fromMillisecondsSinceEpoch(0)),
        );
    final billsBy = <String, List<SupplierBill>>{};
    for (final b in bills.where((b) => !b.cancelled && b.distributorId.isNotEmpty)) {
      of(b.distributorId, b.distributorName);
      (billsBy[b.distributorId] ??= []).add(b);
    }
    final paysBy = <String, List<SupplierPayment>>{};
    for (final p in payments.where((p) => !p.cancelled && p.distributorId.isNotEmpty)) {
      of(p.distributorId, p.distributorName);
      (paysBy[p.distributorId] ??= []).add(p);
    }

    final accounts = <String, DistributorAccount>{};
    for (final d in byId.values) {
      final dBills = (billsBy[d.id] ?? <SupplierBill>[])..sort((a, b) => b.billDate.compareTo(a.billDate));
      final dPays = (paysBy[d.id] ?? <SupplierPayment>[])..sort((a, b) => b.paidOn.compareTo(a.paidOn));
      final credit = dBills.where((b) => b.isCredit).toList()
        ..sort((a, b) {
          final c = a.billDate.compareTo(b.billDate);
          return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
        });
      final paid = List<int>.filled(credit.length, 0);

      // A payment naming a bill goes to that bill first; the rest (and
      // payments naming no bill) clear the oldest bills first.
      var pool = 0;
      for (final p in dPays.reversed) {
        var left = p.amountPaise;
        final key = _key(p.billNumber);
        if (key.isNotEmpty) {
          for (var i = 0; i < credit.length && left > 0; i++) {
            if (_key(credit[i].billNumber) != key) continue;
            final take = (credit[i].totalPaise - paid[i]).clamp(0, left);
            paid[i] += take;
            left -= take;
          }
        }
        pool += left;
      }
      for (var i = 0; i < credit.length && pool > 0; i++) {
        final take = (credit[i].totalPaise - paid[i]).clamp(0, pool);
        paid[i] += take;
        pool -= take;
      }

      accounts[d.id] = DistributorAccount(
        distributor: d,
        bills: dBills,
        payments: dPays,
        creditBills: [
          for (var i = 0; i < credit.length; i++)
            BillBalance(bill: credit[i], paidPaise: paid[i], dueOn: credit[i].dueOn(d.creditDays)),
        ],
      );
    }
    return SupplierLedger(accounts);
  }

  /// Distributors by what is owed, largest first; then the rest by name.
  List<DistributorAccount> get sorted => accounts.values.toList()
    ..sort((a, b) {
      final c = b.outstandingPaise.compareTo(a.outstandingPaise);
      return c != 0 ? c : a.distributor.name.toLowerCase().compareTo(b.distributor.name.toLowerCase());
    });

  int get totalOutstandingPaise =>
      accounts.values.fold(0, (s, a) => s + (a.outstandingPaise > 0 ? a.outstandingPaise : 0));

  /// Unpaid credit bills due within [remindDaysBefore] days or already late,
  /// latest due date last.
  List<PaymentReminder> remindersAt(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final soon = today.add(const Duration(days: remindDaysBefore));
    final list = [
      for (final a in accounts.values)
        for (final b in a.unpaid)
          if (!b.dueOn.isAfter(soon)) PaymentReminder(a, b),
    ]..sort((x, y) => x.bill.dueOn.compareTo(y.bill.dueOn));
    return list;
  }

  /// The bill a payment against [billNumber] would go to, for suggestions.
  BillBalance? findBill(String distributorId, String billNumber) {
    final key = _key(billNumber);
    if (key.isEmpty) return null;
    for (final b in accounts[distributorId]?.creditBills ?? const <BillBalance>[]) {
      if (_key(b.bill.billNumber) == key) return b;
    }
    return null;
  }
}
