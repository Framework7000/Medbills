import 'date_value.dart';

/// Lower-case letters and digits only, so "Shree Ganesh Pharma" and
/// "SHREE GANESH  PHARMA." are the same distributor.
String _slug(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// A distributor, stockist or MR the shop buys from. One shared list for
/// every device.
class Distributor {
  final String id;
  final String storeId;
  final String name;
  final String phone;
  final String gstin;
  /// Days of credit this distributor normally gives (for payment reminders).
  final int creditDays;
  final DateTime createdAt;

  const Distributor({
    required this.id,
    required this.storeId,
    required this.name,
    this.phone = '',
    this.gstin = '',
    this.creditDays = 30,
    required this.createdAt,
  });

  static const defaultCreditDays = 30;

  /// The same name always gives the same id, on every device.
  static String idFor(String name) {
    final slug = _slug(name);
    return slug.isEmpty ? '' : 'd_${slug.length > 60 ? slug.substring(0, 60) : slug}';
  }

  static String tidyName(String name) => name.trim().replaceAll(RegExp(r'\s+'), ' ');

  Distributor copyWith({String? name, String? phone, String? gstin, int? creditDays}) => Distributor(
        id: id,
        storeId: storeId,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        gstin: gstin ?? this.gstin,
        creditDays: creditDays ?? this.creditDays,
        createdAt: createdAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'storeId': storeId,
        'name': name,
        'phone': phone,
        'gstin': gstin,
        'creditDays': creditDays,
        'createdAt': createdAt,
      };

  factory Distributor.fromMap(Map<String, dynamic> m) => Distributor(
        id: readString(m['id']),
        storeId: readString(m['storeId'], 'store_primary'),
        name: readString(m['name']),
        phone: readString(m['phone']),
        gstin: readString(m['gstin']),
        creditDays: readInt(m['creditDays'], defaultCreditDays),
        createdAt: readDate(m['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// Bought for cash (paid there and then) or on credit (udhaar, pay later).
enum PurchasePayment {
  cash('Cash', 'Paid'),
  credit('Credit', 'Udhaar');

  const PurchasePayment(this.label, this.short);
  final String label;
  final String short;

  static PurchasePayment fromString(String? v) =>
      PurchasePayment.values.firstWhere((p) => p.name == v, orElse: () => PurchasePayment.credit);
}

/// One supplier bill (invoice): what was bought, from whom, for how much,
/// and whether it was paid in cash or is owed. Stock received against a bill
/// adds its cost here automatically; the amount can be set to the bill's
/// exact printed total.
class SupplierBill {
  final String id;
  final String storeId;
  final String distributorId;
  final String distributorName;
  final String billNumber;
  final DateTime billDate;
  /// Purchase cost of the stock received against this bill, added up.
  final int itemsPaise;
  /// The bill's printed total, if typed; otherwise [itemsPaise] is used.
  final int? amountPaise;
  final PurchasePayment payment;
  /// When a credit bill should be paid by (reminders); null = bill date + credit days.
  final DateTime? dueDate;
  /// An old bill entered to record money already owed (not a purchase made today).
  final bool isOpening;
  final String note;
  final bool cancelled;
  final DateTime createdAt;
  final String createdBy;
  final String createdByName;

  const SupplierBill({
    required this.id,
    required this.storeId,
    required this.distributorId,
    required this.distributorName,
    required this.billNumber,
    required this.billDate,
    this.itemsPaise = 0,
    this.amountPaise,
    required this.payment,
    this.dueDate,
    this.isOpening = false,
    this.note = '',
    this.cancelled = false,
    required this.createdAt,
    required this.createdBy,
    required this.createdByName,
  });

  int get totalPaise => amountPaise ?? itemsPaise;
  bool get isCredit => payment == PurchasePayment.credit;

  DateTime dueOn(int creditDays) =>
      dueDate ?? DateTime(billDate.year, billDate.month, billDate.day + creditDays);

  /// One bill per distributor and bill number. Without a bill number, one
  /// per distributor per day.
  static String idFor(String distributorId, String billNumber, DateTime date) {
    final no = _slug(billNumber);
    final key = no.isNotEmpty
        ? no
        : 'day${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
    return '${distributorId}__${key.length > 40 ? key.substring(0, 40) : key}';
  }

  SupplierBill copyWith({
    String? distributorId,
    String? distributorName,
    String? billNumber,
    DateTime? billDate,
    int? itemsPaise,
    int? amountPaise,
    bool clearAmount = false,
    PurchasePayment? payment,
    DateTime? dueDate,
    bool clearDueDate = false,
    bool? isOpening,
    String? note,
    bool? cancelled,
  }) =>
      SupplierBill(
        id: id,
        storeId: storeId,
        distributorId: distributorId ?? this.distributorId,
        distributorName: distributorName ?? this.distributorName,
        billNumber: billNumber ?? this.billNumber,
        billDate: billDate ?? this.billDate,
        itemsPaise: itemsPaise ?? this.itemsPaise,
        amountPaise: clearAmount ? null : amountPaise ?? this.amountPaise,
        payment: payment ?? this.payment,
        dueDate: clearDueDate ? null : dueDate ?? this.dueDate,
        isOpening: isOpening ?? this.isOpening,
        note: note ?? this.note,
        cancelled: cancelled ?? this.cancelled,
        createdAt: createdAt,
        createdBy: createdBy,
        createdByName: createdByName,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'storeId': storeId,
        'distributorId': distributorId,
        'distributorName': distributorName,
        'billNumber': billNumber,
        'billDate': billDate,
        'itemsPaise': itemsPaise,
        'amountPaise': amountPaise,
        'payment': payment.name,
        'dueDate': dueDate,
        'isOpening': isOpening,
        'note': note,
        'cancelled': cancelled,
        'createdAt': createdAt,
        'createdBy': createdBy,
        'createdByName': createdByName,
      };

  factory SupplierBill.fromMap(Map<String, dynamic> m) => SupplierBill(
        id: readString(m['id']),
        storeId: readString(m['storeId'], 'store_primary'),
        distributorId: readString(m['distributorId']),
        distributorName: readString(m['distributorName']),
        billNumber: readString(m['billNumber']),
        billDate: readDate(m['billDate']) ?? readDate(m['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        itemsPaise: readInt(m['itemsPaise']),
        amountPaise: m['amountPaise'] == null ? null : readInt(m['amountPaise']),
        payment: PurchasePayment.fromString(m['payment'] as String?),
        dueDate: readDate(m['dueDate']),
        isOpening: m['isOpening'] == true,
        note: readString(m['note']),
        cancelled: m['cancelled'] == true,
        createdAt: readDate(m['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        createdBy: readString(m['createdBy']),
        createdByName: readString(m['createdByName']),
      );
}

enum PaidVia {
  cash('Cash'),
  upi('UPI'),
  bank('Bank'),
  cheque('Cheque');

  const PaidVia(this.label);
  final String label;

  static PaidVia fromString(String? v) => PaidVia.values.firstWhere((p) => p.name == v, orElse: () => PaidVia.cash);
}

/// Money paid to a distributor or MR against what the shop owes.
class SupplierPayment {
  final String id;
  final String storeId;
  final String distributorId;
  final String distributorName;
  final int amountPaise;
  final PaidVia via;
  /// The bill this pays, if it is for one bill (otherwise oldest bills first).
  final String billNumber;
  final DateTime paidOn;
  final String note;
  final bool cancelled;
  final DateTime createdAt;
  final String createdBy;
  final String createdByName;

  const SupplierPayment({
    required this.id,
    required this.storeId,
    required this.distributorId,
    required this.distributorName,
    required this.amountPaise,
    required this.via,
    this.billNumber = '',
    required this.paidOn,
    this.note = '',
    this.cancelled = false,
    required this.createdAt,
    required this.createdBy,
    required this.createdByName,
  });

  SupplierPayment copyWith({
    String? distributorId,
    String? distributorName,
    int? amountPaise,
    PaidVia? via,
    String? billNumber,
    DateTime? paidOn,
    String? note,
    bool? cancelled,
  }) =>
      SupplierPayment(
        id: id,
        storeId: storeId,
        distributorId: distributorId ?? this.distributorId,
        distributorName: distributorName ?? this.distributorName,
        amountPaise: amountPaise ?? this.amountPaise,
        via: via ?? this.via,
        billNumber: billNumber ?? this.billNumber,
        paidOn: paidOn ?? this.paidOn,
        note: note ?? this.note,
        cancelled: cancelled ?? this.cancelled,
        createdAt: createdAt,
        createdBy: createdBy,
        createdByName: createdByName,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'storeId': storeId,
        'distributorId': distributorId,
        'distributorName': distributorName,
        'amountPaise': amountPaise,
        'via': via.name,
        'billNumber': billNumber,
        'paidOn': paidOn,
        'note': note,
        'cancelled': cancelled,
        'createdAt': createdAt,
        'createdBy': createdBy,
        'createdByName': createdByName,
      };

  factory SupplierPayment.fromMap(Map<String, dynamic> m) => SupplierPayment(
        id: readString(m['id']),
        storeId: readString(m['storeId'], 'store_primary'),
        distributorId: readString(m['distributorId']),
        distributorName: readString(m['distributorName']),
        amountPaise: readInt(m['amountPaise']),
        via: PaidVia.fromString(m['via'] as String?),
        billNumber: readString(m['billNumber']),
        paidOn: readDate(m['paidOn']) ?? readDate(m['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        note: readString(m['note']),
        cancelled: m['cancelled'] == true,
        createdAt: readDate(m['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        createdBy: readString(m['createdBy']),
        createdByName: readString(m['createdByName']),
      );
}

List<String> distributorProblems(Distributor d) => [
      if (d.name.trim().isEmpty || d.id.isEmpty) 'Enter the distributor\'s name.',
      if (d.creditDays < 0 || d.creditDays > 365) 'Credit days must be 0–365.',
    ];

List<String> supplierBillProblems(SupplierBill b) => [
      if (b.distributorId.isEmpty || b.distributorName.trim().isEmpty) 'Choose the distributor.',
      if (b.totalPaise <= 0) 'Enter the bill amount.',
      if (b.amountPaise != null && b.amountPaise! < 0) 'The amount cannot be negative.',
      if (b.billDate.isAfter(DateTime.now().add(const Duration(days: 1)))) 'The bill date is in the future.',
      if (b.dueDate != null && b.dueDate!.isBefore(DateTime(b.billDate.year, b.billDate.month, b.billDate.day)))
        'The due date is before the bill date.',
    ];

List<String> supplierPaymentProblems(SupplierPayment p) => [
      if (p.distributorId.isEmpty || p.distributorName.trim().isEmpty) 'Choose who was paid.',
      if (p.amountPaise <= 0) 'Enter the amount paid.',
      if (p.paidOn.isAfter(DateTime.now().add(const Duration(days: 1)))) 'The payment date is in the future.',
    ];
