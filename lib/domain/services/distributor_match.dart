import '../models/supplier_account.dart';

String _slug(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Words every firm name has that say nothing about which firm it is.
const _commonWords = {
  'pharma', 'pharmaceutical', 'pharmaceuticals', 'medical', 'medicals', 'medicos', 'distributor', 'distributors',
  'agency', 'agencies', 'enterprise', 'enterprises', 'trader', 'traders', 'healthcare', 'surgical', 'surgicals',
  'chemist', 'chemists', 'stockist', 'stockists', 'associates', 'corporation', 'sales', 'pvt', 'ltd', 'private',
  'limited', 'and', 'the', 'co', 'm', 's',
};

/// What is left of a firm's name without the [_commonWords]: "Apna Medical
/// Agency" → "apna".
String _distinctive(String name) => name
    .toLowerCase()
    .split(RegExp(r'[^a-z0-9]+'))
    .where((w) => w.isNotEmpty && !_commonWords.contains(w))
    .join();

/// The shop's own distributor that a scanned bill is from — the GSTIN read
/// off the bill is exact; otherwise a distributor whose full name appears in
/// the bill's text, or a name read with a letter or two wrong ("APNA MEDICAL
/// AGENCV"). Null when it is none of them (a new distributor): the name read
/// from the bill is then used as it is.
Distributor? matchDistributor({
  required String gstin,
  required String supplierName,
  required String ocrText,
  required Iterable<Distributor> distributors,
}) {
  final list = distributors.where((d) => d.name.trim().isNotEmpty).toList();
  final g = gstin.trim().toUpperCase();
  if (g.isNotEmpty) {
    for (final d in list) {
      if (d.gstin.trim().toUpperCase() == g) return d;
    }
  }

  // The whole name, letters and digits only, inside the bill's text. A name
  // has to say more than "Medical Agency" to count.
  final text = _slug(ocrText);
  Distributor? best;
  for (final d in list) {
    final name = _slug(d.name);
    if (name.length < 6 || _distinctive(d.name).length < 3) continue;
    if (text.contains(name) && (best == null || name.length > _slug(best.name).length)) best = d;
  }
  if (best != null) return best;

  // The name read from the bill, a letter or two off.
  final read = _slug(supplierName);
  if (read.length < 6) return null;
  Distributor? closest;
  var closestScore = 0.0;
  for (final d in list) {
    final name = _slug(d.name);
    if (name.length < 6) continue;
    final longer = name.length > read.length ? name.length : read.length;
    final score = 1 - _distance(read, name) / longer;
    if (score > closestScore) {
      closest = d;
      closestScore = score;
    }
  }
  return closestScore >= 0.85 ? closest : null;
}

int _distance(String a, String b) {
  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      current[j] = [previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost].reduce((x, y) => x < y ? x : y);
    }
    previous = current;
  }
  return previous[b.length];
}
