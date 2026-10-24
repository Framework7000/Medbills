import 'date_value.dart';

/// One item line read from a supplier bill. Every field may be missing or
/// wrong — the pharmacist checks each line before it becomes stock.
class BillDraftLine {
  final String rawText; // the row as read, shown for checking
  final String? medicineId; // matched store/catalogue medicine
  final String medicineName;
  final String batchNumber;
  final int? expiryMonth;
  final int? expiryYear;
  final int packs;
  final int freePacks;
  final int ratePaise; // per pack
  final int mrpPaise; // per pack
  final bool include; // false = skip this line when receiving
  final bool received; // already became stock — never received twice

  const BillDraftLine({
    required this.rawText,
    this.medicineId,
    this.medicineName = '',
    this.batchNumber = '',
    this.expiryMonth,
    this.expiryYear,
    this.packs = 0,
    this.freePacks = 0,
    this.ratePaise = 0,
    this.mrpPaise = 0,
    this.include = true,
    this.received = false,
  });

  BillDraftLine copyWith({
    String? medicineId,
    String? medicineName,
    String? batchNumber,
    int? expiryMonth,
    int? expiryYear,
    int? packs,
    int? freePacks,
    int? ratePaise,
    int? mrpPaise,
    bool? include,
    bool? received,
  }) {
    return BillDraftLine(
      rawText: rawText,
      medicineId: medicineId ?? this.medicineId,
      medicineName: medicineName ?? this.medicineName,
      batchNumber: batchNumber ?? this.batchNumber,
      expiryMonth: expiryMonth ?? this.expiryMonth,
      expiryYear: expiryYear ?? this.expiryYear,
      packs: packs ?? this.packs,
      freePacks: freePacks ?? this.freePacks,
      ratePaise: ratePaise ?? this.ratePaise,
      mrpPaise: mrpPaise ?? this.mrpPaise,
      include: include ?? this.include,
      received: received ?? this.received,
    );
  }

  Map<String, dynamic> toMap() => {
        'rawText': rawText,
        'medicineId': medicineId,
        'medicineName': medicineName,
        'batchNumber': batchNumber,
        'expiryMonth': expiryMonth,
        'expiryYear': expiryYear,
        'packs': packs,
        'freePacks': freePacks,
        'ratePaise': ratePaise,
        'mrpPaise': mrpPaise,
        'include': include,
        'received': received,
      };

  factory BillDraftLine.fromMap(Map<String, dynamic> map) {
    final month = readInt(map['expiryMonth']);
    final year = readInt(map['expiryYear']);
    return BillDraftLine(
      rawText: readString(map['rawText']),
      medicineId: map['medicineId'] as String?,
      medicineName: readString(map['medicineName']),
      batchNumber: readString(map['batchNumber']),
      expiryMonth: month == 0 ? null : month,
      expiryYear: year == 0 ? null : year,
      packs: readInt(map['packs']),
      freePacks: readInt(map['freePacks']),
      ratePaise: readInt(map['ratePaise']),
      mrpPaise: readInt(map['mrpPaise']),
      include: map['include'] != false,
      received: map['received'] == true,
    );
  }
}

/// The header and lines read from a supplier bill.
class BillDraft {
  final String supplierName;
  final String supplierGstin;
  final String supplierDrugLicence;
  final String invoiceNumber;
  final DateTime? invoiceDate;
  final int? billTotalPaise;
  final List<BillDraftLine> lines;

  const BillDraft({
    this.supplierName = '',
    this.supplierGstin = '',
    this.supplierDrugLicence = '',
    this.invoiceNumber = '',
    this.invoiceDate,
    this.billTotalPaise,
    this.lines = const [],
  });

  BillDraft copyWith({
    String? supplierName,
    String? supplierGstin,
    String? supplierDrugLicence,
    String? invoiceNumber,
    DateTime? invoiceDate,
    int? billTotalPaise,
    List<BillDraftLine>? lines,
  }) {
    return BillDraft(
      supplierName: supplierName ?? this.supplierName,
      supplierGstin: supplierGstin ?? this.supplierGstin,
      supplierDrugLicence: supplierDrugLicence ?? this.supplierDrugLicence,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      invoiceDate: invoiceDate ?? this.invoiceDate,
      billTotalPaise: billTotalPaise ?? this.billTotalPaise,
      lines: lines ?? this.lines,
    );
  }

  /// Sum of the included lines at the purchase rate (before any GST the
  /// supplier adds on top), for comparing with the bill's printed total.
  int get linesTotalPaise =>
      lines.where((l) => l.include || l.received).fold(0, (sum, l) => sum + l.packs * l.ratePaise);

  Map<String, dynamic> toMap() => {
        'supplierName': supplierName,
        'supplierGstin': supplierGstin,
        'supplierDrugLicence': supplierDrugLicence,
        'invoiceNumber': invoiceNumber,
        'invoiceDate': invoiceDate,
        'billTotalPaise': billTotalPaise,
        'lines': lines.map((l) => l.toMap()).toList(),
      };

  factory BillDraft.fromMap(Map<String, dynamic> map) {
    final total = map['billTotalPaise'];
    return BillDraft(
      supplierName: readString(map['supplierName']),
      supplierGstin: readString(map['supplierGstin']),
      supplierDrugLicence: readString(map['supplierDrugLicence']),
      invoiceNumber: readString(map['invoiceNumber']),
      invoiceDate: readDate(map['invoiceDate']),
      billTotalPaise: total == null ? null : readInt(total),
      lines: [
        for (final l in (map['lines'] as List? ?? const []))
          BillDraftLine.fromMap(Map<String, dynamic>.from(l as Map)),
      ],
    );
  }
}

enum BillScanStatus { draft, received, discarded }

/// A photographed supplier bill: the picture is kept (stored separately)
/// together with what was read from it and what became stock.
class BillScan {
  final String id;
  final String storeId;
  final DateTime createdAt;
  final String createdBy;
  final String createdByName;
  final BillScanStatus status;
  final BillDraft draft;
  final String ocrText;
  final bool hasImage;
  final int receivedLines;
  final DateTime? receivedAt;
  final String receivedByName;

  const BillScan({
    required this.id,
    required this.storeId,
    required this.createdAt,
    required this.createdBy,
    required this.createdByName,
    this.status = BillScanStatus.draft,
    required this.draft,
    this.ocrText = '',
    this.hasImage = false,
    this.receivedLines = 0,
    this.receivedAt,
    this.receivedByName = '',
  });

  BillScan copyWith({BillDraft? draft, BillScanStatus? status, int? receivedLines, DateTime? receivedAt, String? receivedByName}) {
    return BillScan(
      id: id,
      storeId: storeId,
      createdAt: createdAt,
      createdBy: createdBy,
      createdByName: createdByName,
      status: status ?? this.status,
      draft: draft ?? this.draft,
      ocrText: ocrText,
      hasImage: hasImage,
      receivedLines: receivedLines ?? this.receivedLines,
      receivedAt: receivedAt ?? this.receivedAt,
      receivedByName: receivedByName ?? this.receivedByName,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'storeId': storeId,
        'createdAt': createdAt,
        'createdBy': createdBy,
        'createdByName': createdByName,
        'status': status.name,
        'draft': draft.toMap(),
        'ocrText': ocrText,
        'hasImage': hasImage,
        'receivedLines': receivedLines,
        'receivedAt': receivedAt,
        'receivedByName': receivedByName,
      };

  factory BillScan.fromMap(Map<String, dynamic> map) => BillScan(
        id: readString(map['id']),
        storeId: readString(map['storeId']),
        createdAt: readDate(map['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        createdBy: readString(map['createdBy']),
        createdByName: readString(map['createdByName']),
        status: BillScanStatus.values.firstWhere((s) => s.name == map['status'], orElse: () => BillScanStatus.draft),
        draft: BillDraft.fromMap(Map<String, dynamic>.from((map['draft'] as Map?) ?? const {})),
        ocrText: readString(map['ocrText']),
        hasImage: map['hasImage'] == true,
        receivedLines: readInt(map['receivedLines']),
        receivedAt: readDate(map['receivedAt']),
        receivedByName: readString(map['receivedByName']),
      );
}
