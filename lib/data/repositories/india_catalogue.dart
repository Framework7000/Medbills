import 'dart:convert';

import 'package:archive/archive.dart';

import '../../domain/models/medicine.dart';
import '../../domain/models/schedule_type.dart';
import 'global_catalogue_repository.dart' show CatalogueEntry;

/// Every medicine sold in India that we have data for (≈2.46 lakh brands),
/// bundled with the app as `assets/catalogue/india.tsv.gz` — built by
/// `scripts/catalogue/build_catalogue.py` from the Indian Medicine Dataset
/// (MIT licence, prices as of Nov 2022). It is searched on the device and
/// never copied into the store database: a medicine becomes a store record
/// only when it is first stocked.
///
/// Schedule and GST come from the official lists, per salt (H1/X; 5% GST
/// from 22-09-2025). Everything else is UNKNOWN until the pharmacist
/// confirms it (Rule 11), and the brand data is not government data, so
/// picking one always opens the editor first.
class IndiaCatalogue {
  IndiaCatalogue._(this._rows, this._keys, this._names, this._aliases);

  final List<String> _rows; // raw TSV lines
  final List<String> _keys; // " name composition maker " normalised
  final List<String> _names; // name normalised with spaces removed ("dolo650tablet")
  final List<MapEntry<String, String>> _aliases; // other name → canonical salt, longest first

  int get length => _rows.length;

  static const _columns = 11; // id name composition maker pack units mrp mrpAsOf schedule gst hsn

  /// Decodes the bundled files. Heavy (≈2.5 lakh rows) — call off the UI
  /// thread with `compute`.
  static IndiaCatalogue fromAssets((List<int> gzipped, String aliasesTsv) files) {
    final text = utf8.decode(const GZipDecoder().decodeBytes(files.$1));
    return fromTsv(text, files.$2);
  }

  static IndiaCatalogue fromTsv(String tsv, String aliasesTsv) {
    final rows = <String>[];
    final keys = <String>[];
    final names = <String>[];
    for (final line in const LineSplitter().convert(tsv)) {
      final f = line.split('\t');
      if (f.length < _columns || f[1].isEmpty) continue;
      rows.add(line);
      keys.add(' ${_norm('${f[1]} ${f[2]} ${f[3]}')} ');
      names.add(_norm(f[1]).replaceAll(' ', ''));
    }
    final aliases = <MapEntry<String, String>>[
      for (final line in const LineSplitter().convert(aliasesTsv))
        if (line.contains('\t')) MapEntry(line.split('\t')[0], line.split('\t')[1]),
    ]..sort((a, b) => b.key.length.compareTo(a.key.length));
    return IndiaCatalogue._(rows, keys, names, aliases);
  }

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  /// Medicines matching every word of [query] — brand, salt (under any of
  /// its names: amoxycillin = amoxicillin, PCM = paracetamol) or maker.
  /// Spaces and hyphens don't matter ("dolo650" finds "Dolo 650"). Brands
  /// starting with the query come first.
  List<CatalogueEntry> search(String query, {int limit = 40}) {
    var q = ' ${_norm(query)} ';
    if (q.trim().isEmpty) return const [];
    for (final a in _aliases) {
      if (q.contains(' ${a.key} ')) q = q.replaceAll(' ${a.key} ', ' ${a.value} ');
    }
    final tokens = q.trim().split(' ');
    final squashed = tokens.join();
    final starts = <int>[];
    final others = <int>[];
    for (var i = 0; i < _rows.length; i++) {
      final key = _keys[i];
      final name = _names[i];
      var all = true;
      for (final t in tokens) {
        if (!key.contains(t) && !name.contains(t)) {
          all = false;
          break;
        }
      }
      if (!all && !name.contains(squashed)) continue;
      if (name.startsWith(squashed) || name.startsWith(tokens.first)) {
        starts.add(i);
        if (starts.length >= limit * 4) break;
      } else if (others.length < limit) {
        others.add(i);
      }
    }
    int byLength(int a, int b) => _names[a].length.compareTo(_names[b].length);
    starts.sort(byLength);
    return [...starts, ...others].take(limit).map(_entry).toList();
  }

  /// The medicine a pack's printed brand names, when one clearly matches
  /// ("Dolo 650" → "Dolo 650 Tablet"), else null.
  CatalogueEntry? byBrand(String brand) {
    final b = _norm(brand).replaceAll(' ', '');
    if (b.length < 3) return null;
    for (final e in search(brand, limit: 10)) {
      if (_norm(e.medicine.name).replaceAll(' ', '').startsWith(b)) return e;
    }
    return null;
  }

  CatalogueEntry? byId(String id) {
    for (var i = 0; i < _rows.length; i++) {
      if (_rows[i].startsWith('$id\t')) return _entry(i);
    }
    return null;
  }

  CatalogueEntry _entry(int i) {
    final f = _rows[i].split('\t');
    final units = int.tryParse(f[5]) ?? 1;
    final medicine = Medicine(
      id: f[0],
      storeId: '',
      catalogueId: f[0],
      name: f[1],
      genericName: _titleCase(f[2]),
      manufacturer: f[3],
      type: '',
      packSizeLabel: _sentenceCase(f[4]),
      unitsPerPack: units < 1 ? 1 : units,
      hsnCode: f[10].isEmpty ? '300490' : f[10],
      gstRate: double.tryParse(f[9]) ?? 5.0,
      scheduleType: ScheduleType.fromString(f[8]),
      minStock: 0,
      shelfLocation: '',
      updatedAt: DateTime(2022, 11, 1),
    );
    return CatalogueEntry(medicine: medicine, referenceMrpPaise: int.tryParse(f[6]) ?? 0);
  }

  static String _titleCase(String s) => s
      .split(' ')
      .map((w) => w.isEmpty || RegExp(r'^\d').hasMatch(w) ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  static String _sentenceCase(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
