import 'date_value.dart';

enum CreditEntryType {
  creditSale('Credit sale'),
  paymentReceived('Payment received'),
  saleCancelled('Sale cancelled');

  const CreditEntryType(this.label);
  final String label;

  /// Effect on the outstanding balance, in the direction of [amountPaise].
  int signOf() => this == CreditEntryType.creditSale ? 1 : -1;
}

/// Rule 10: the credit (udhaar) ledger is append-only. The balance on the
/// customer is maintained alongside, inside the same transaction.
class CreditLedgerEntry {
  final String id;
  final String storeId;
  final String customerId;
  final CreditEntryType type;
  final int amountPaise; // always positive; direction comes from [type]
  final String? invoiceNumber;
  final String notes;
  final DateTime timestamp;
  final String createdBy;
  final String createdByName;

  const CreditLedgerEntry({
    required this.id,
    required this.storeId,
    required this.customerId,
    required this.type,
    required this.amountPaise,
    this.invoiceNumber,
    this.notes = '',
    required this.timestamp,
    required this.createdBy,
    required this.createdByName,
  });

  int get signedAmountPaise => amountPaise * type.signOf();

  Map<String, dynamic> toMap() => {
        'id': id,
        'storeId': storeId,
        'customerId': customerId,
        'type': type.name,
        'amountPaise': amountPaise,
        'invoiceNumber': invoiceNumber,
        'notes': notes,
        'timestamp': timestamp,
        'createdBy': createdBy,
        'createdByName': createdByName,
      };

  factory CreditLedgerEntry.fromMap(Map<String, dynamic> map) => CreditLedgerEntry(
        id: readString(map['id']),
        storeId: readString(map['storeId'], 'store_primary'),
        customerId: readString(map['customerId']),
        type: CreditEntryType.values.firstWhere(
          (e) => e.name == map['type'],
          orElse: () => CreditEntryType.creditSale,
        ),
        amountPaise: readInt(map['amountPaise']),
        invoiceNumber: map['invoiceNumber'] as String?,
        notes: readString(map['notes']),
        timestamp: readDate(map['timestamp']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        createdBy: readString(map['createdBy']),
        createdByName: readString(map['createdByName']),
      );
}

class CustomerCredit {
  final String id;
  final String storeId;
  final String name;
  final String phoneNumber;
  final int creditLimitPaise; // 0 = no limit set
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

  bool get isOverLimit => creditLimitPaise > 0 && outstandingBalancePaise > creditLimitPaise;

  CustomerCredit copyWith({String? name, String? phoneNumber, int? creditLimitPaise, int? outstandingBalancePaise}) {
    return CustomerCredit(
      id: id,
      storeId: storeId,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      creditLimitPaise: creditLimitPaise ?? this.creditLimitPaise,
      outstandingBalancePaise: outstandingBalancePaise ?? this.outstandingBalancePaise,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'storeId': storeId,
        'name': name,
        'phoneNumber': phoneNumber,
        'creditLimitPaise': creditLimitPaise,
        'outstandingBalancePaise': outstandingBalancePaise,
        'createdAt': createdAt,
      };

  factory CustomerCredit.fromMap(Map<String, dynamic> map) => CustomerCredit(
        id: readString(map['id']),
        storeId: readString(map['storeId'], 'store_primary'),
        name: readString(map['name']),
        phoneNumber: readString(map['phoneNumber']),
        creditLimitPaise: readInt(map['creditLimitPaise']),
        outstandingBalancePaise: readInt(map['outstandingBalancePaise']),
        createdAt: readDate(map['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
}
