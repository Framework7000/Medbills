import 'package:decimal/decimal.dart';

/// A single line item within a [SaleInvoice]. Rule 12: money is integer paise.
class InvoiceItemRecord {
  final String medicineId;
  final String name;
  final String batchNumber;
  final String expiry;
  final int quantity;
  final int mrpPaise;
  final double gstRate;

  const InvoiceItemRecord({
    required this.medicineId,
    required this.name,
    required this.batchNumber,
    required this.expiry,
    required this.quantity,
    required this.mrpPaise,
    required this.gstRate,
  });

  int get totalPaise => mrpPaise * quantity;

  Decimal get totalRupees =>
      (Decimal.fromInt(totalPaise) / Decimal.fromInt(100)).toDecimal();

  Map<String, dynamic> toMap() {
    return {
      'medicineId': medicineId,
      'name': name,
      'batchNumber': batchNumber,
      'expiry': expiry,
      'quantity': quantity,
      'mrpPaise': mrpPaise,
      'gstRate': gstRate,
    };
  }

  factory InvoiceItemRecord.fromMap(Map<String, dynamic> map) {
    return InvoiceItemRecord(
      medicineId: map['medicineId'] as String? ?? '',
      name: map['name'] as String? ?? '',
      batchNumber: map['batchNumber'] as String? ?? '',
      expiry: map['expiry'] as String? ?? '',
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
      mrpPaise: (map['mrpPaise'] as num?)?.toInt() ?? 0,
      gstRate: (map['gstRate'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// An append-only sale record (Rule 10: never deleted, only cancelled with
/// an audit entry).
class SaleInvoice {
  final String invoiceNumber;
  final String storeId; // Rule 8
  final DateTime timestamp;
  final String customerName;
  final String customerPhone;
  final String paymentMode; // Cash, UPI, Card, Credit
  final int grandTotalPaise;
  final int gstTotalPaise;
  final List<InvoiceItemRecord> items;
  final bool isCancelled;
  final String? cancellationReason;

  // Rule 9: captured only when the cart contains a Schedule H1 item —
  // CDSCO requires retaining patient + prescriber identity for 3 years.
  final String? patientName;
  final String? patientPhone;
  final String? doctorName;
  final String? doctorRegistrationNumber;

  const SaleInvoice({
    required this.invoiceNumber,
    required this.storeId,
    required this.timestamp,
    required this.customerName,
    required this.customerPhone,
    required this.paymentMode,
    required this.grandTotalPaise,
    required this.gstTotalPaise,
    required this.items,
    this.isCancelled = false,
    this.cancellationReason,
    this.patientName,
    this.patientPhone,
    this.doctorName,
    this.doctorRegistrationNumber,
  });

  Decimal get grandTotalRupees =>
      (Decimal.fromInt(grandTotalPaise) / Decimal.fromInt(100)).toDecimal();

  Decimal get gstTotalRupees =>
      (Decimal.fromInt(gstTotalPaise) / Decimal.fromInt(100)).toDecimal();

  SaleInvoice copyWith({
    bool? isCancelled,
    String? cancellationReason,
  }) {
    return SaleInvoice(
      invoiceNumber: invoiceNumber,
      storeId: storeId,
      timestamp: timestamp,
      customerName: customerName,
      customerPhone: customerPhone,
      paymentMode: paymentMode,
      grandTotalPaise: grandTotalPaise,
      gstTotalPaise: gstTotalPaise,
      items: items,
      isCancelled: isCancelled ?? this.isCancelled,
      cancellationReason: cancellationReason ?? this.cancellationReason,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'invoiceNumber': invoiceNumber,
      'storeId': storeId,
      'timestamp': timestamp.toIso8601String(),
      'customerName': customerName,
      'customerPhone': customerPhone,
      'paymentMode': paymentMode,
      'grandTotalPaise': grandTotalPaise,
      'gstTotalPaise': gstTotalPaise,
      'items': items.map((e) => e.toMap()).toList(),
      'isCancelled': isCancelled,
      'cancellationReason': cancellationReason,
      'patientName': patientName,
      'patientPhone': patientPhone,
      'doctorName': doctorName,
      'doctorRegistrationNumber': doctorRegistrationNumber,
    };
  }

  factory SaleInvoice.fromMap(Map<String, dynamic> map) {
    return SaleInvoice(
      invoiceNumber: map['invoiceNumber'] as String,
      storeId: map['storeId'] as String? ?? 'store_primary',
      timestamp: map['timestamp'] != null
          ? DateTime.parse(map['timestamp'] as String)
          : DateTime.now(),
      customerName: map['customerName'] as String? ?? 'Walk-in Customer',
      customerPhone: map['customerPhone'] as String? ?? '',
      paymentMode: map['paymentMode'] as String? ?? 'Cash',
      grandTotalPaise: (map['grandTotalPaise'] as num?)?.toInt() ?? 0,
      gstTotalPaise: (map['gstTotalPaise'] as num?)?.toInt() ?? 0,
      items: ((map['items'] as List?) ?? [])
          .map((e) => InvoiceItemRecord.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      isCancelled: map['isCancelled'] as bool? ?? false,
      cancellationReason: map['cancellationReason'] as String?,
      patientName: map['patientName'] as String?,
      patientPhone: map['patientPhone'] as String?,
      doctorName: map['doctorName'] as String?,
      doctorRegistrationNumber: map['doctorRegistrationNumber'] as String?,
    );
  }
}
