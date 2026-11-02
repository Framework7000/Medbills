import 'package:shared_preferences/shared_preferences.dart';

/// Remembers which counter this phone last sent scans to, across restarts —
/// so picking a target isn't needed every single time the app opens.
/// `id == ''` means "the bill on this device" was explicitly chosen.
class ScanTargetMemory {
  static const _idKey = 'lastScanTargetId';
  static const _nameKey = 'lastScanTargetName';

  static Future<void> save(String id, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_idKey, id);
    await prefs.setString(_nameKey, name);
  }

  /// Returns (id, name), or null if nothing has ever been picked.
  static Future<(String, String)?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_idKey);
    final name = prefs.getString(_nameKey);
    if (id == null || name == null) return null;
    return (id, name);
  }
}

/// This computer's own counter identity, so it reappears on the phones under
/// the same id and name every time MedBills opens — no setup per launch.
class CounterMemory {
  static const _idKey = 'counterStationId';
  static const _nameKey = 'counterStationName';
  static const _offKey = 'counterStationOff';

  /// (id, name), or null on first use.
  static Future<(String, String)?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_idKey);
    final name = prefs.getString(_nameKey);
    if (id == null || name == null) return null;
    return (id, name);
  }

  static Future<void> save(String id, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_idKey, id);
    await prefs.setString(_nameKey, name);
    await prefs.setBool(_offKey, false);
  }

  /// The person switched receiving off: don't turn it back on by itself.
  static Future<void> setOff(bool off) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_offKey, off);
  }

  static Future<bool> isOff() async => (await SharedPreferences.getInstance()).getBool(_offKey) ?? false;
}
