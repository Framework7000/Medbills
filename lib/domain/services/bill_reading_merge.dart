import '../models/bill_scan.dart';

/// Puts together two or more readings of the same bill photo (the photo as
/// taken, and a cleaned copy with shadows and faint print evened out).
///
/// Nothing is guessed: the fullest reading is the base, a field it missed is
/// filled only from another reading that actually read it, and where the
/// readings disagree the figures that make sense together (rate below MRP,
/// a normal margin) are kept. A row only another reading saw is added when
/// it has a batch, an expiry and a quantity.
BillDraft combineBillReadings(List<BillDraft> readings) {
  final drafts = readings.where((d) => d.lines.isNotEmpty || _headerScore(d) > 0).toList();
  if (drafts.isEmpty) return readings.isEmpty ? const BillDraft() : readings.first;
  if (drafts.length == 1) return drafts.single;
  drafts.sort((a, b) => _score(b).compareTo(_score(a)));
  var base = drafts.first;
  for (final other in drafts.skip(1)) {
    base = _combine(base, other);
  }
  return base;
}

int _headerScore(BillDraft d) =>
    (d.supplierName.isNotEmpty ? 1 : 0) +
    (d.supplierGstin.isNotEmpty ? 1 : 0) +
    (d.invoiceNumber.isNotEmpty ? 1 : 0) +
    (d.invoiceDate != null ? 1 : 0) +
    (d.billTotalPaise != null ? 1 : 0);

int _lineScore(BillDraftLine l) =>
    (l.batchNumber.isNotEmpty ? 1 : 0) +
    (l.expiryMonth != null ? 1 : 0) +
    (l.packs > 0 ? 1 : 0) +
    (l.ratePaise > 0 ? 1 : 0) +
    (l.mrpPaise > 0 ? 1 : 0) +
    (l.medicineId != null ? 1 : 0) +
    (_pricesAgree(l) ? 2 : 0);

int _score(BillDraft d) => _headerScore(d) + d.lines.fold(0, (s, l) => s + _lineScore(l));

/// Rate below MRP with a margin a distributor would give (generics can be
/// sold at a large margin), and the "MRP" is not just the line amount.
bool _pricesAgree(BillDraftLine l) {
  if (l.ratePaise <= 0 || l.mrpPaise <= 0 || l.ratePaise >= l.mrpPaise) return false;
  final margin = (l.mrpPaise - l.ratePaise) / l.mrpPaise;
  if (margin < 0.05 || margin > 0.8) return false;
  final amount = l.packs * l.ratePaise;
  return !(l.packs > 1 && (l.mrpPaise - amount).abs() <= amount * 0.02);
}

bool _close(int a, int b) => (a - b).abs() <= (a > b ? a : b) * 0.01;

/// Letters and digits OCR mixes up (O/0, I/1, S/5, B/8, Z/2) folded together,
/// so "ACO310" and "AC0310" are the same batch.
String _foldBatch(String s) => s
    .toUpperCase()
    .replaceAll(RegExp(r'[^A-Z0-9]'), '')
    .replaceAll('O', '0')
    .replaceAll(RegExp('[IL]'), '1')
    .replaceAll('S', '5')
    .replaceAll('B', '8')
    .replaceAll('Z', '2');

String _nameKey(String s) {
  final letters = s.toUpperCase().replaceAll(RegExp('[^A-Z]'), '');
  return letters.length < 4 ? '' : letters.substring(0, letters.length < 6 ? letters.length : 6);
}

bool _sameRow(BillDraftLine a, BillDraftLine b) {
  final batchA = _foldBatch(a.batchNumber), batchB = _foldBatch(b.batchNumber);
  if (batchA.length >= 3 && batchA == batchB) return true;
  if (a.medicineId != null && a.medicineId == b.medicineId) {
    return batchA.isEmpty || batchB.isEmpty || batchA == batchB;
  }
  final nameA = _nameKey(a.medicineName);
  if (nameA.isEmpty || nameA != _nameKey(b.medicineName)) return false;
  // Same name: the same row when nothing read in both contradicts it.
  if (batchA.isNotEmpty && batchB.isNotEmpty) return false;
  if (a.expiryMonth != null && b.expiryMonth != null &&
      (a.expiryMonth != b.expiryMonth || a.expiryYear != b.expiryYear)) {
    return false;
  }
  return true;
}

BillDraftLine _fill(BillDraftLine base, BillDraftLine other) {
  var line = base;
  if (line.medicineId == null && other.medicineId != null) {
    line = line.copyWith(medicineId: other.medicineId, medicineName: other.medicineName);
  } else if (line.medicineName.trim().length < 3 && other.medicineName.trim().length >= 3) {
    line = line.copyWith(medicineName: other.medicineName);
  }
  if (line.batchNumber.isEmpty && other.batchNumber.isNotEmpty) line = line.copyWith(batchNumber: other.batchNumber);
  if (line.expiryMonth == null && other.expiryMonth != null) {
    line = line.copyWith(expiryMonth: other.expiryMonth, expiryYear: other.expiryYear);
  }
  if (line.packs <= 0 && other.packs > 0) {
    line = line.copyWith(packs: other.packs, freePacks: other.freePacks);
  } else if (line.packs > 0 && other.packs > 0 && line.packs != other.packs) {
    // The two readings saw different quantities: neither is trusted, the
    // pharmacist fills it in.
    line = line.copyWith(packs: 0, freePacks: 0);
  }
  // Prices: a pair that makes sense beats one that doesn't; two sensible
  // pairs that differ are both doubtful and left blank; otherwise a missing
  // figure is taken from the other reading only if the pair then makes sense.
  final baseAgrees = _pricesAgree(line), otherAgrees = _pricesAgree(other);
  if (!baseAgrees && otherAgrees) {
    line = line.copyWith(ratePaise: other.ratePaise, mrpPaise: other.mrpPaise);
  } else if (baseAgrees && otherAgrees) {
    if (!_close(line.ratePaise, other.ratePaise)) line = line.copyWith(ratePaise: 0);
    if (!_close(line.mrpPaise, other.mrpPaise)) line = line.copyWith(mrpPaise: 0);
  } else if (!baseAgrees) {
    if (line.ratePaise <= 0 && other.ratePaise > 0 && _pricesAgree(line.copyWith(ratePaise: other.ratePaise))) {
      line = line.copyWith(ratePaise: other.ratePaise);
    } else if (line.mrpPaise <= 0 && other.mrpPaise > 0 && _pricesAgree(line.copyWith(mrpPaise: other.mrpPaise))) {
      line = line.copyWith(mrpPaise: other.mrpPaise);
    }
  }
  // Still a pair that doesn't make sense (an MRP six times the rate is the
  // line amount): keep the figure the other reading confirms, drop the other.
  if (!_pricesAgree(line) && line.ratePaise > 0 && line.mrpPaise > 0) {
    final rateSeen = _close(line.ratePaise, other.ratePaise), mrpSeen = _close(line.mrpPaise, other.mrpPaise);
    if (rateSeen && !mrpSeen) line = line.copyWith(mrpPaise: 0);
    if (mrpSeen && !rateSeen) line = line.copyWith(ratePaise: 0);
  }
  return line;
}

BillDraft _combine(BillDraft base, BillDraft other) {
  final used = <int>{};
  final lines = <BillDraftLine>[];
  for (final line in base.lines) {
    final match = _indexWhere(other.lines, (i, o) => !used.contains(i) && _sameRow(line, o));
    if (match < 0) {
      lines.add(line);
    } else {
      used.add(match);
      lines.add(_fill(line, other.lines[match]));
    }
  }
  for (var i = 0; i < other.lines.length; i++) {
    final o = other.lines[i];
    if (used.contains(i)) continue;
    final strong = o.batchNumber.isNotEmpty && o.expiryMonth != null && o.packs > 0;
    if (strong && !lines.any((l) => _sameRow(l, o))) lines.add(o);
  }
  return base.copyWith(
    supplierName: _nameQuality(other.supplierName) > _nameQuality(base.supplierName) ? other.supplierName : null,
    supplierGstin: base.supplierGstin.isEmpty ? other.supplierGstin : null,
    supplierDrugLicence: base.supplierDrugLicence.isEmpty ? other.supplierDrugLicence : null,
    invoiceNumber: base.invoiceNumber.isEmpty ? other.invoiceNumber : null,
    invoiceDate: base.invoiceDate ?? other.invoiceDate,
    billTotalPaise: base.billTotalPaise ?? other.billTotalPaise,
    lines: lines,
  );
}

/// Share of a supplier name that is letters and spaces: "Apna Medical
/// Agency" scores 1, a misread "_[teumamo 256 [5.00" much less.
double _nameQuality(String name) =>
    name.trim().isEmpty ? 0 : name.replaceAll(RegExp('[^A-Za-z ]'), '').length / name.length;

int _indexWhere<T>(List<T> list, bool Function(int index, T item) test) {
  for (var i = 0; i < list.length; i++) {
    if (test(i, list[i])) return i;
  }
  return -1;
}
