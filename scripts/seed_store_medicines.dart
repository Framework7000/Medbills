// Loads the medicine master (names, makers, pack sizes, HSN, GST, drug
// schedule) into a store in the live Firestore database, from the same
// catalogue the app ships (lib/data/repositories/global_catalogue_repository.dart),
// so the app and the database can never disagree about a medicine.
//
// It does NOT create stock. Stock exists only when someone receives a real
// supplier delivery in the app's Purchases screen — a pharmacy's stock
// register must never contain made-up quantities or batch numbers.
//
// Safe to re-run: medicines that already exist in the store are left
// untouched, so shelf locations and schedule corrections made in the app
// are never overwritten.
//
// Usage (plain Dart SDK, no Flutter needed):
//   cd scripts && dart pub get
//   dart run seed_store_medicines.dart --credentials /path/to/service-account.json
//   dart run seed_store_medicines.dart --dry-run
//
// Options: --store (default store_primary), --project (default: the key's
// project_id), --remove-legacy (deletes the root-level medicines/{med_NNN}
// documents and their batches written by the previous version of this
// script; any other document in that collection is left alone).

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:googleapis/firestore/v1.dart' as fs;
import 'package:googleapis_auth/auth_io.dart' as auth;

// The app's own catalogue is the single source of medicine data.
// ignore: avoid_relative_lib_imports
import '../lib/data/repositories/global_catalogue_repository.dart';

fs.Value _value(Object? v) {
  if (v == null) return fs.Value(nullValue: 'NULL_VALUE');
  if (v is String) return fs.Value(stringValue: v);
  if (v is bool) return fs.Value(booleanValue: v);
  if (v is int) return fs.Value(integerValue: '$v');
  if (v is double) return fs.Value(doubleValue: v);
  if (v is DateTime) return fs.Value(timestampValue: v.toUtc().toIso8601String());
  throw ArgumentError('Unsupported value $v');
}

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('credentials', help: 'Service-account JSON key (or set GOOGLE_APPLICATION_CREDENTIALS)')
    ..addOption('project', help: 'Firebase project id (defaults to the key\'s project_id)')
    ..addOption('store', defaultsTo: 'store_primary', help: 'Store id to load the medicines into')
    ..addFlag('dry-run', negatable: false, help: 'List what would be written; touch nothing')
    ..addFlag('remove-legacy', negatable: false, help: 'Delete root-level medicines written by the old seed script')
    ..addFlag('help', abbr: 'h', negatable: false);
  final args = parser.parse(arguments);
  if (args['help'] as bool) {
    stdout.writeln(parser.usage);
    return;
  }

  final storeId = args['store'] as String;
  final medicines = GlobalCatalogueRepository().search('').map((e) => e.medicine.copyWith(storeId: storeId)).toList();

  if (args['dry-run'] as bool) {
    for (final m in medicines) {
      stdout.writeln('${m.id.padRight(9)} ${m.name.padRight(34)} ${m.scheduleType.code.padRight(7)} '
          'GST ${m.gstRate.toStringAsFixed(0).padLeft(2)}%  HSN ${m.hsnCode}  ${m.packSizeLabel} (${m.unitsPerPack})');
    }
    stdout.writeln('\n${medicines.length} medicines would be added to stores/$storeId/medicines.');
    return;
  }

  final keyPath = args['credentials'] as String? ?? Platform.environment['GOOGLE_APPLICATION_CREDENTIALS'];
  if (keyPath == null) {
    stderr.writeln('Pass --credentials /path/to/key.json (or --dry-run).');
    exitCode = 64;
    return;
  }
  final key = jsonDecode(File(keyPath).readAsStringSync()) as Map<String, dynamic>;
  final projectId = args['project'] as String? ?? key['project_id'] as String;
  final client = await auth.clientViaServiceAccount(
    auth.ServiceAccountCredentials.fromJson(key),
    [fs.FirestoreApi.datastoreScope],
  );
  final api = fs.FirestoreApi(client).projects.databases.documents;
  final root = 'projects/$projectId/databases/(default)/documents';

  try {
    final store = await _tryGet(api, '$root/stores/$storeId');
    if (store == null) {
      stderr.writeln('stores/$storeId does not exist. Run provision_firebase.dart first.');
      exitCode = 1;
      return;
    }

    var added = 0;
    var kept = 0;
    for (final m in medicines) {
      final doc = fs.Document(fields: {
        for (final e in m.copyWith(updatedAt: DateTime.now()).toMap().entries) e.key: _value(e.value),
      });
      try {
        await api.patch(doc, '$root/stores/$storeId/medicines/${m.id}', currentDocument_exists: false);
        added++;
      } on fs.DetailedApiRequestError catch (e) {
        if (e.status == 409 || e.status == 400 || e.status == 412) {
          kept++; // already in the store — leave the store's own edits alone
        } else {
          rethrow;
        }
      }
    }
    stdout.writeln('stores/$storeId/medicines: $added added, $kept already present (unchanged).');

    if (args['remove-legacy'] as bool) {
      final legacyIds = medicines.map((m) => m.id).toSet();
      final removed = await _deleteCollection(api, root, 'medicines',
          recurseInto: 'batches', only: (id) => legacyIds.contains(id));
      stdout.writeln('Removed $removed legacy root-level documents.');
    }
  } finally {
    client.close();
  }
}

Future<fs.Document?> _tryGet(fs.ProjectsDatabasesDocumentsResource api, String name) async {
  try {
    return await api.get(name);
  } on fs.DetailedApiRequestError catch (e) {
    if (e.status == 404) return null;
    rethrow;
  }
}

/// Deletes the documents in [parent]/[collection] whose id passes [only]
/// (all, if null), each with its [recurseInto] subcollection. Returns the
/// number of documents deleted.
Future<int> _deleteCollection(fs.ProjectsDatabasesDocumentsResource api, String parent, String collection,
    {String? recurseInto, bool Function(String id)? only}) async {
  var count = 0;
  String? page;
  do {
    final list = await api.list(parent, collection, pageSize: 300, pageToken: page);
    for (final doc in list.documents ?? const <fs.Document>[]) {
      if (only != null && !only(doc.name!.split('/').last)) continue;
      if (recurseInto != null) count += await _deleteCollection(api, doc.name!, recurseInto);
      await api.delete(doc.name!);
      count++;
    }
    page = list.nextPageToken;
  } while (page != null && page.isNotEmpty);
  return count;
}
