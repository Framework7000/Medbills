/// Rule 2: stock is always held in base units (tablets, capsules, sachets,
/// or whole bottles/tubes/inhalers/vials that are never split). MRP is
/// printed per pack, so a pack's unit count is what converts between them.
class PackUnits {
  static final _countThenUnit = RegExp(
    r'(\d+)\s*(tablets?|tabs?|capsules?|caps?|sachets?|lozenges?|pessaries|suppositor(?:y|ies))\b',
    caseSensitive: false,
  );
  static final _stripOf = RegExp(r'strip\s+of\s+(\d+)', caseSensitive: false);
  static final _containerCount = RegExp(
    r'\b(?:bottle|box|jar|pack)\s+(?:of\s+)?(\d+)\b(?!\s*(?:ml|g|gm|mg|mcg|l|kg|%))',
    caseSensitive: false,
  );

  /// Best-effort unit count from a pack label such as "Strip of 15",
  /// "10 Capsules Strip" or "Bottle 120". Liquids, creams, inhalers and
  /// injections ("100ml Bottle", "Tube 50g", "Inhaler", "1 Vial") are sold
  /// whole, so they count as one unit.
  static int fromLabel(String label) {
    for (final pattern in [_stripOf, _countThenUnit, _containerCount]) {
      final match = pattern.firstMatch(label);
      if (match != null) {
        final value = int.tryParse(match.group(1)!);
        if (value != null && value > 0) return value;
      }
    }
    return 1;
  }

  /// Splits [units] into whole packs and loose units, e.g. 32 tablets of a
  /// strip-of-15 → (2, 2).
  static (int packs, int loose) split(int units, int unitsPerPack) {
    final perPack = unitsPerPack < 1 ? 1 : unitsPerPack;
    return (units ~/ perPack, units % perPack);
  }

  /// Human-readable stock, e.g. "2 strips + 2" / "14 units" / "3".
  static String describe(int units, int unitsPerPack) {
    if (unitsPerPack <= 1) return '$units';
    final (packs, loose) = split(units, unitsPerPack);
    if (packs == 0) return '$loose loose';
    if (loose == 0) return '$packs × $unitsPerPack';
    return '$packs × $unitsPerPack + $loose';
  }
}
