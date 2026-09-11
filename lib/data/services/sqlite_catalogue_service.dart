import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/models/medicine.dart';
import '../../domain/models/schedule_type.dart';

/// Searches the bundled, read-only SQLite catalogue (the full 253,973-row
/// Indian medicine dataset) shipped as `assets/catalogue.db`. Desktop
/// platforms use `sqflite_common_ffi`; mobile uses the platform `sqflite`
/// plugin directly.
class SqliteCatalogueService {
  Database? _database;

  Future<Database> _open() async {
    if (_database != null) return _database!;

    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final path = await getDatabasesPath();
    final dbPath = '$path/catalogue.db';
    _database = await openDatabase(dbPath, readOnly: true);
    return _database!;
  }

  Future<List<Medicine>> search(String query, {int limit = 50}) async {
    final db = await _open();
    final rows = await db.query(
      'medicines',
      where: 'name LIKE ? OR generic_name LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      limit: limit,
    );
    return rows.map((row) {
      return Medicine(
        id: row['id'] as String,
        storeId: 'store_primary',
        name: row['name'] as String,
        genericName: row['generic_name'] as String? ?? '',
        manufacturer: row['manufacturer'] as String? ?? '',
        type: row['type'] as String? ?? '',
        packSizeLabel: row['pack_size_label'] as String? ?? '',
        hsnCode: row['hsn_code'] as String? ?? '',
        gstRate: (row['gst_rate'] as num?)?.toDouble() ?? 12.0,
        scheduleType: ScheduleType.fromString(row['schedule_type'] as String?),
        minStock: (row['min_stock'] as num?)?.toInt() ?? 0,
        shelfLocation: row['shelf_location'] as String? ?? '',
        updatedAt: DateTime.now(),
      );
    }).toList();
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
