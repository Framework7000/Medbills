/// "Two Hundred Thirty Four Rupees and Fifty Paise only" — the amount in
/// words printed on an invoice, in the Indian system (lakh, crore).
String rupeesInWords(int paise) {
  if (paise < 0) return 'Minus ${rupeesInWords(-paise)}';
  final rupees = paise ~/ 100;
  final p = paise % 100;
  final r = rupees == 0 ? 'Zero' : _words(rupees);
  final rs = '$r Rupee${rupees == 1 ? '' : 's'}';
  return p == 0 ? '$rs only' : '$rs and ${_words(p)} Paise only';
}

const _ones = [
  '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 'Eleven', 'Twelve',
  'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen',
];
const _tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];

String _two(int n) => n < 20 ? _ones[n] : [_tens[n ~/ 10], _ones[n % 10]].where((s) => s.isNotEmpty).join(' ');

String _three(int n) {
  final h = n ~/ 100, rest = n % 100;
  return [if (h > 0) '${_ones[h]} Hundred', if (rest > 0) _two(rest)].join(' ');
}

String _words(int n) {
  final parts = <String>[];
  final crore = n ~/ 10000000;
  n %= 10000000;
  final lakh = n ~/ 100000;
  n %= 100000;
  final thousand = n ~/ 1000;
  n %= 1000;
  if (crore > 0) parts.add('${_words(crore)} Crore');
  if (lakh > 0) parts.add('${_two(lakh)} Lakh');
  if (thousand > 0) parts.add('${_two(thousand)} Thousand');
  if (n > 0) parts.add(_three(n));
  return parts.join(' ');
}
