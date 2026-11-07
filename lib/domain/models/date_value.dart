/// Reads a date out of a persisted map. The data layer normalises
/// backend-specific timestamp types to [DateTime] before handing maps to
/// domain models, and older records stored ISO-8601 strings.
DateTime? readDate(Object? value) {
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return null;
}

int readInt(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

double readDouble(Object? value, [double fallback = 0]) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

String readString(Object? value, [String fallback = '']) {
  if (value is String) return value;
  if (value == null) return fallback;
  return value.toString();
}

/// A number that may have a fraction (4.5 strips), kept as an int when whole.
num readNum(Object? value, [num fallback = 0]) {
  num? n;
  if (value is num) n = value;
  if (value is String) n = num.tryParse(value);
  if (n == null) return fallback;
  return n == n.roundToDouble() ? n.round() : n;
}

/// Parses a typed pack count such as "4", "4.5" or "4,5" (>= 0), or null.
num? parsePacks(String input) {
  final t = input.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d{1,5}(\.\d{1,2})?$').hasMatch(t)) return null;
  return readNum(t);
}

/// "4", "4.5" — a pack count for display.
String formatPacks(num packs) => packs == packs.roundToDouble() ? '${packs.round()}' : '$packs';
