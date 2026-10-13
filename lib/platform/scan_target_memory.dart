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
