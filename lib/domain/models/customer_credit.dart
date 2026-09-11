import 'package:decimal/decimal.dart';

enum CreditEntryType { creditSale, paymentReceived }

/// Rule 10: credit ledger is append-only. Balance is derived, never
/// overwritten in place.
class CreditLedgerEntry {
  final String id;
  final String customerId;
  final CreditEntryType type;
  final int amountPaise; // Rule 12
  final String? invoiceNumber;
  final String notes;
  final DateTime timestamp;

  const CreditLedgerEntry({
    required this.id,
    required this.customerId,
    required this.type,
    required this.amountPaise,
    this.invoiceNumber,
    this.notes = '',
    required this.timestamp,
  });

  Decimal get amountRupees =>
      (Decimal.fromInt(amountPaise) / Decimal.fromInt(100)).toDecimal();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customerId': customerId,
      'type': type.name,
      'amountPaise': amountPaise,
      'invoiceNumber': invoiceNumber,
      'notes': notes,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory CreditLedgerEntry.fromMap(Map<String, dynamic> map) {
    return CreditLedgerEntry(
      id: map['id'] as String,
      customerId: map['customerId'] as String,
      type: CreditEntryType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => CreditEntryType.creditSale,
      ),
      amountPaise: (map['amountPaise'] as num?)?.toInt() ?? 0,
      invoiceNumber: map['invoiceNumber'] as String?,
      notes: map['notes'] as String? ?? '',
      timestamp: map['timestamp'] != null
          ? DateTime.parse(map['timestamp'] as String)
          : DateTime.now(),
    );
  }
}

class CustomerCredit {
  final String id;
  final String storeId;
  final String name;
  final String phoneNumber;
  final int creditLimitPaise;
  final int outstandingBalancePaise;
  final DateTime createdAt;

  const CustomerCredit({
    required this.id,
    required this.storeId,
    required this.name,
    required this.phoneNumber,
    required this.creditLimitPaise,
    required this.outstandingBalancePaise,
    required this.createdAt,
  });

  bool get isOverLimit => outstandingBalancePaise > creditLimitPaise;

  Decimal get outstandingBalanceRupees =>
      (Decimal.fromInt(outstandingBalancePaise) / Decimal.fromInt(100)).toDecimal();

  CustomerCredit copyWith({int? outstandingBalancePaise}) {
    return CustomerCredit(
      id: id,
      storeId: storeId,
      name: name,
      phoneNumber: phoneNumber,
      creditLimitPaise: creditLimitPaise,
      outstandingBalancePaise:
          outstandingBalancePaise ?? this.outstandingBalancePaise,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'storeId': storeId,
      'name': name,
      'phoneNumber': phoneNumber,
      'creditLimitPaise': creditLimitPaise,
      'outstandingBalancePaise': outstandingBalancePaise,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory CustomerCredit.fromMap(Map<String, dynamic> map) {
    return CustomerCredit(
      id: map['id'] as String,
      storeId: map['storeId'] as String? ?? 'store_primary',
      name: map['name'] as String? ?? '',
      phoneNumber: map['phoneNumber'] as String? ?? '',
      creditLimitPaise: (map['creditLimitPaise'] as num?)?.toInt() ?? 0,
      outstandingBalancePaise:
          (map['outstandingBalancePaise'] as num?)?.toInt() ?? 0,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'] as String)
          : DateTime.now(),
    );
  }
}
