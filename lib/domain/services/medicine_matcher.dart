import '../models/medicine.dart';
import 'ocr_text.dart';

class MedicineMatch {
  final Medicine medicine;
  final int score;
  const MedicineMatch(this.medicine, this.score);
}

class MatchResult {
  /// Best first. Empty when nothing on the pack names a known brand.
  final List<MedicineMatch> candidates;
  const MatchResult(this.candidates);

  MedicineMatch? get best => candidates.isEmpty ? null : candidates.first;

  /// True when the top match is clearly the one — brand and strength agree
  /// and no other medicine comes close. Otherwise the user picks.
  bool get isConfident {
    if (candidates.isEmpty || candidates.first.score < MedicineMatcher.confidentScore) return false;
    return candidates.length == 1 || candidates.first.score - candidates[1].score >= 4;
  }
}

/// Finds the exact medicine named in OCR text (a pack, or one row of a
/// supplier bill). The brand must appear; every other word and every
/// strength in the medicine's name counts for or against it, so "Dolo 650"
/// is never confused with "Dolo 500" and "Pan-D" never with "Pan 40".
class MedicineMatcher {
  static const confidentScore = 14;
  static const minimumScore = 8;

  /// Words that describe the dosage form, not the product.
  static const _formWords = {
    'TABLET', 'TABLETS', 'TAB', 'TABS', 'CAPSULE', 'CAPSULES', 'CAP', 'CAPS', 'SYRUP', 'SYP',
    'SUSPENSION', 'SUSP', 'GEL', 'CREAM', 'OINTMENT', 'DROPS', 'DROP', 'EYE', 'EAR', 'INJECTION', 'INJ',
    'STRIP', 'IP', 'BP', 'USP', 'MG', 'ML', 'GM', 'G', 'MCG', 'IU', 'POWDER', 'SACHET', 'SOLUTION', 'SKIN',
    'PAEDIATRIC', 'PEDIATRIC', 'PAIN', 'RELIEF', 'THE', 'AND', 'OF',
  };

  static List<String> _tokens(String text) => normaliseOcr(text)
      .replaceAllMapped(RegExp(r'(?<=[A-Z])(?=\d)|(?<=\d)(?=[A-Z])'), (_) => ' ')
      .split(' ')
      .map((t) => t.replaceAll(RegExp(r'^\.+|\.+$'), ''))
      .where((t) => t.isNotEmpty)
      .toList();

  static MatchResult match(String ocrText, Iterable<Medicine> medicines) {
    final tokens = _tokens(ocrText).toSet();
    final words = tokens.where((t) => RegExp(r'[A-Z]').hasMatch(t)).toList();
    final results = <MedicineMatch>[];
    for (final m in medicines) {
      final score = _score(m, tokens, words);
      if (score >= minimumScore) results.add(MedicineMatch(m, score));
    }
    results.sort((a, b) => b.score.compareTo(a.score));
    return MatchResult(results.take(6).toList());
  }

  static int _score(Medicine m, Set<String> tokens, List<String> words) {
    final nameTokens = _tokens(m.name).where((t) => !_formWords.contains(t)).toList();
    final brand = nameTokens.where((t) => !_isNumber(t)).toList();
    final numbers = nameTokens.where(_isNumber).toList();
    if (brand.isEmpty) return 0;

    // The brand root must be on the pack (allowing one OCR slip in long words).
    if (!_present(brand.first, tokens, words)) return 0;
    var score = 10;
    for (final t in brand.skip(1)) {
      score += _present(t, tokens, words) ? 4 : -6;
    }
    for (final n in numbers) {
      score += tokens.contains(n) ? 5 : -5;
    }
    final maker = _tokens(m.manufacturer).where((t) => t.length >= 3 && !_isNumber(t)).firstOrNull;
    if (maker != null && tokens.contains(maker)) score += 2;
    var genericHits = 0;
    for (final g in _tokens(m.genericName).where((t) => t.length >= 5 && !_isNumber(t)).toSet()) {
      if (tokens.contains(g) && genericHits < 3) genericHits++;
    }
    return score + genericHits;
  }

  static bool _isNumber(String t) => RegExp(r'^\d+(\.\d+)?$').hasMatch(t);

  static bool _present(String token, Set<String> tokens, List<String> words) {
    if (tokens.contains(token)) return true;
    if (token.length < 4) return false;
    final allowed = token.length >= 8 ? 2 : 1;
    return words.any((w) => (w.length - token.length).abs() <= allowed && _distance(w, token) <= allowed);
  }

  static int _distance(String a, String b) {
    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        final best = previous[j] + 1 < current[j - 1] + 1 ? previous[j] + 1 : current[j - 1] + 1;
        current[j] = best < previous[j - 1] + cost ? best : previous[j - 1] + cost;
      }
      previous = current;
    }
    return previous[b.length];
  }
}
