import '../services/billing_calculator.dart';
import 'date_value.dart';
import 'schedule_type.dart';

enum PaymentMode {
  cash('Cash'),
  upi('UPI'),
  card('Card'),
  credit('Credit');

  const PaymentMode(this.label);
  final String label;

  static PaymentMode fromString(String? value) => PaymentMode.values.firstWhere(
        (m) => m.name == value || m.label == value,
        orElse: () => PaymentMode.cash,
      );
}

enum SaleStatus { completed, cancelled }

/// One invoice line: exactly one batch of one medicine.
class SaleLine {
  final String medicineId;
  final String batchId;
  final String name;
  final String batchNumber;
  final DateTime expiryDate;
  final String hsnCode;
  final double gstRate;
  final ScheduleType scheduleType;
  final int unitsPerPack;
  final int quantity; // base units
  final int mrpPaise; // per pack, GST-inclusive
  final int lineTotalPaise;
  final int costPaise; // purchase cost of this line, for profit reporting

  const SaleLine({
    required this.medicineId,
    required this.batchId,
    required this.name,
    required this.batchNumber,
    required this.expiryDate,
    required this.hsnCode,
    required this.gstRate,
    required this.scheduleType,
    required this.unitsPerPack,
    required this.quantity,
    required this.mrpPaise,
    required this.lineTotalPaise,
    required this.costPaise,
  });

  BillLine get billLine => BillLine(lineTotalPaise: lineTotalPaise, gstRate: gstRate);

  Map<String, dynamic> toMap() => {
        'medicineId': medicineId,
        'batchId': batchId,
        'name': name,
        'batchNumber': batchNumber,
        'expiryDate': expiryDate,
        'hsnCode': hsnCode,
        'gstRate': gstRate,
        'scheduleType': scheduleType.code,
        'unitsPerPack': unitsPerPack,
        'quantity': quantity,
        'mrpPaise': mrpPaise,
        'lineTotalPaise': lineTotalPaise,
        'costPaise': costPaise,
      };

  factory SaleLine.fromMap(Map<String, dynamic> map) => SaleLine(
        medicineId: readString(map['medicineId']),
        batchId: readString(map['batchId']),
        name: readString(map['name']),
        batchNumber: readString(map['batchNumber']),
        expiryDate: readDate(map['expiryDate']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        hsnCode: readString(map['hsnCode']),
        gstRate: readDouble(map['gstRate']),
        scheduleType: ScheduleType.fromString(map['scheduleType'] as String?),
        unitsPerPack: readInt(map['unitsPerPack'], 1),
        quantity: readInt(map['quantity']),
        mrpPaise: readInt(map['mrpPaise']),
        lineTotalPaise: readInt(map['lineTotalPaise']),
        costPaise: readInt(map['costPaise']),
      );
}

/// Patient + prescriber record required for Schedule H1/X sales (Rule 9).
class PrescriptionRecord {
  final String patientName;
  final String patientPhone;
  final String doctorName;
  final String doctorRegistrationNumber;

  const PrescriptionRecord({
    required this.patientName,
    required this.patientPhone,
    required this.doctorName,
    required this.doctorRegistrationNumber,
  });

  bool get isComplete =>
      patientName.trim().isNotEmpty &&
      patientPhone.trim().isNotEmpty &&
      doctorName.trim().isNotEmpty &&
      doctorRegistrationNumber.trim().isNotEmpty;

  Map<String, dynamic> toMap() => {
        'patientName': patientName,
        'patientPhone': patientPhone,
        'doctorName': doctorName,
        'doctorRegistrationNumber': doctorRegistrationNumber,
      };

  factory PrescriptionRecord.fromMap(Map<String, dynamic> map) => PrescriptionRecord(
        patientName: readString(map['patientName']),
        patientPhone: readString(map['patientPhone']),
        doctorName: readString(map['doctorName']),
        doctorRegistrationNumber: readString(map['doctorRegistrationNumber']),
      );
}

/// An append-only sale record (Rule 10: never deleted — only cancelled with
/// a reason and an audit entry).
class SaleInvoice {
  final String id;
  final String storeId; // Rule 8
  final String invoiceNumber;
  final DateTime createdAt;
  final String createdBy;
  final String createdByName;
  final String customerName;
  final String customerPhone;
  final String? customerId; // set for credit (udhaar) sales
  final PaymentMode paymentMode;
  final List<SaleLine> lines;
  final List<GstSlab> slabs;
  final int grossPaise;
  final int payablePaise;
  final PrescriptionRecord? prescription;
  final SaleStatus status;
  final String? cancellationReason;
  final DateTime? cancelledAt;
  final String? cancelledByName;

  const SaleInvoice({
    required this.id,
    required this.storeId,
    required this.invoiceNumber,
    required this.createdAt,
    required this.createdBy,
    required this.createdByName,
    required this.customerName,
    required this.customerPhone,
    this.customerId,
    required this.paymentMode,
    required this.lines,
    required this.slabs,
    required this.grossPaise,
    required this.payablePaise,
    this.prescription,
    this.status = SaleStatus.completed,
    this.cancellationReason,
    this.cancelledAt,
    this.cancelledByName,
  });

  bool get isCancelled => status == SaleStatus.cancelled;
  int get taxablePaise => slabs.fold(0, (sum, s) => sum + s.taxablePaise);
  int get gstPaise => slabs.fold(0, (sum, s) => sum + s.gstPaise);
  int get roundOffPaise => payablePaise - grossPaise;
  int get costPaise => lines.fold(0, (sum, l) => sum + l.costPaise);
  int get itemCount => lines.length;

  Map<String, dynamic> toMap() => {
        'id': id,
        'storeId': storeId,
        'invoiceNumber': invoiceNumber,
        'createdAt': createdAt,
        'createdBy': createdBy,
        'createdByName': createdByName,
        'customerName': customerName,
        'customerPhone': customerPhone,
        'customerId': customerId,
        'paymentMode': paymentMode.name,
        'lines': lines.map((l) => l.toMap()).toList(),
        'slabs': slabs.map((s) => s.toMap()).toList(),
        'grossPaise': grossPaise,
        'taxablePaise': taxablePaise,
        'gstPaise': gstPaise,
        'payablePaise': payablePaise,
        'prescription': prescription?.toMap(),
        'status': status.name,
        'cancellationReason': cancellationReason,
        'cancelledAt': cancelledAt,
        'cancelledByName': cancelledByName,
      };

  factory SaleInvoice.fromMap(Map<String, dynamic> map) {
    List<Map<String, dynamic>> listOfMaps(Object? v) =>
        ((v as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final prescription = map['prescription'];
    return SaleInvoice(
      id: readString(map['id']),
      storeId: readString(map['storeId'], 'store_primary'),
      invoiceNumber: readString(map['invoiceNumber']),
      createdAt: readDate(map['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      createdBy: readString(map['createdBy']),
      createdByName: readString(map['createdByName']),
      customerName: readString(map['customerName'], 'Walk-in Customer'),
      customerPhone: readString(map['customerPhone']),
      customerId: map['customerId'] as String?,
      paymentMode: PaymentMode.fromString(map['paymentMode'] as String?),
      lines: listOfMaps(map['lines']).map(SaleLine.fromMap).toList(),
      slabs: listOfMaps(map['slabs']).map(GstSlab.fromMap).toList(),
      grossPaise: readInt(map['grossPaise']),
      payablePaise: readInt(map['payablePaise']),
      prescription: prescription is Map
          ? PrescriptionRecord.fromMap(Map<String, dynamic>.from(prescription))
          : null,
      status: map['status'] == 'cancelled' ? SaleStatus.cancelled : SaleStatus.completed,
      cancellationReason: map['cancellationReason'] as String?,
      cancelledAt: readDate(map['cancelledAt']),
      cancelledByName: map['cancelledByName'] as String?,
    );
  }
}
