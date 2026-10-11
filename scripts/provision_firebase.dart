// Provisions a Firebase project for MedBills, idempotently:
//
//   1. Registers the iOS/macOS (com.medbills.nuskhaPms), Android
//      (com.medbills.nuskha_pms) and Web apps if missing, and writes their
//      real SDK config into lib/firebase_options.dart.
//   2. Enables Email/Password sign-in.
//   3. Deploys ../firestore.rules and ../firestore.indexes.json.
//   4. Creates the store profile and staff accounts (users/{uid} profiles
//      carry storeId + role, which the security rules check).
//
// Usage:
//   cd scripts && dart pub get
//   dart run provision_firebase.dart --credentials /path/to/service-account.json \
//       --staff "owner:Store Owner:owner@example.com" \
//       --staff "pharmacist:Pharmacist:pharmacist@example.com" \
//       --staff "counterStaff:Counter:counter@example.com"
//
// A staff account that doesn't exist yet is created with a random password
// printed once to stdout; existing accounts keep their password. Every step
// can be re-run safely.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';
import 'package:googleapis/firebaserules/v1.dart' as rules;
import 'package:googleapis/firestore/v1.dart' as firestore;
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:http/http.dart' as http;

const _appleBundleId = 'com.medbills.nuskhaPms';
const _androidPackage = 'com.medbills.nuskha_pms';
const _webDisplayName = 'MedBills Web';

late http.Client _client;
late String _projectId;

Future<Map<String, dynamic>> _json(http.Response r, String what) async {
  if (r.statusCode >= 300) {
    throw Exception('$what failed (${r.statusCode}): ${r.body}');
  }
  return r.body.isEmpty ? <String, dynamic>{} : jsonDecode(r.body) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> _get(String url, String what) =>
    _client.get(Uri.parse(url)).then((r) => _json(r, what));

Future<Map<String, dynamic>> _post(String url, Object body, String what) => _client
    .post(Uri.parse(url), headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
    .then((r) => _json(r, what));

Future<Map<String, dynamic>> _patch(String url, Object body, String what) => _client
    .patch(Uri.parse(url), headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
    .then((r) => _json(r, what));

Future<Map<String, dynamic>> _waitForOperation(Map<String, dynamic> op) async {
  var current = op;
  for (var i = 0; i < 30 && current['done'] != true; i++) {
    await Future<void>.delayed(const Duration(seconds: 2));
    current = await _get('https://firebase.googleapis.com/v1beta1/${op['name']}', 'poll operation');
  }
  if (current['done'] != true) throw Exception('Operation ${op['name']} timed out');
  if (current['error'] != null) throw Exception('Operation failed: ${current['error']}');
  return current['response'] as Map<String, dynamic>;
}

/// Returns the appId of the first app matching [matches], creating one with
/// [createBody] if none exists.
Future<String> _ensureApp(
  String kind,
  bool Function(Map<String, dynamic>) matches,
  Map<String, dynamic> createBody,
) async {
  final base = 'https://firebase.googleapis.com/v1beta1/projects/$_projectId/$kind';
  final list = await _get(base, 'list $kind');
  for (final app in (list['apps'] as List<dynamic>? ?? const [])) {
    final map = app as Map<String, dynamic>;
    if (matches(map)) return map['appId'] as String;
  }
  stdout.writeln('  creating $kind ...');
  final op = await _post(base, createBody, 'create $kind');
  final response = await _waitForOperation(op);
  return response['appId'] as String;
}

String _plistValue(String plist, String key) {
  final match = RegExp('<key>$key</key>\\s*<string>([^<]*)</string>').firstMatch(plist);
  if (match == null) throw Exception('$key missing from GoogleService-Info.plist');
  return match.group(1)!;
}

Future<Map<String, Map<String, String>>> _registerApps() async {
  stdout.writeln('== Registering apps ==');
  final webAppId = await _ensureApp(
    'webApps',
    (_) => true,
    {'displayName': _webDisplayName},
  );
  final web = await _get(
      'https://firebase.googleapis.com/v1beta1/projects/$_projectId/webApps/$webAppId/config',
      'web config');

  final iosAppId = await _ensureApp(
    'iosApps',
    (a) => a['bundleId'] == _appleBundleId,
    {'bundleId': _appleBundleId, 'displayName': 'MedBills iOS/macOS'},
  );
  final iosConfig = await _get(
      'https://firebase.googleapis.com/v1beta1/projects/$_projectId/iosApps/$iosAppId/config',
      'ios config');
  final plist = utf8.decode(base64Decode(iosConfig['configFileContents'] as String));

  final androidAppId = await _ensureApp(
    'androidApps',
    (a) => a['packageName'] == _androidPackage,
    {'packageName': _androidPackage, 'displayName': 'MedBills Android'},
  );
  final androidConfig = await _get(
      'https://firebase.googleapis.com/v1beta1/projects/$_projectId/androidApps/$androidAppId/config',
      'android config');
  final googleServices =
      jsonDecode(utf8.decode(base64Decode(androidConfig['configFileContents'] as String)))
          as Map<String, dynamic>;
  final client = (googleServices['client'] as List<dynamic>).cast<Map<String, dynamic>>().firstWhere(
      (c) => (c['client_info'] as Map<String, dynamic>)['android_client_info']['package_name'] ==
          _androidPackage);
  final projectInfo = googleServices['project_info'] as Map<String, dynamic>;

  stdout.writeln('  web: $webAppId\n  ios/macos: $iosAppId\n  android: $androidAppId');

  return {
    'web': {
      'apiKey': web['apiKey'] as String,
      'appId': web['appId'] as String,
      'messagingSenderId': web['messagingSenderId'] as String,
      'projectId': web['projectId'] as String,
      'authDomain': web['authDomain'] as String,
      'storageBucket': web['storageBucket'] as String,
    },
    'apple': {
      'apiKey': _plistValue(plist, 'API_KEY'),
      'appId': _plistValue(plist, 'GOOGLE_APP_ID'),
      'messagingSenderId': _plistValue(plist, 'GCM_SENDER_ID'),
      'projectId': _plistValue(plist, 'PROJECT_ID'),
      'storageBucket': _plistValue(plist, 'STORAGE_BUCKET'),
      'iosBundleId': _plistValue(plist, 'BUNDLE_ID'),
    },
    'android': {
      'apiKey': ((client['api_key'] as List<dynamic>).first as Map<String, dynamic>)['current_key']
          as String,
      'appId': (client['client_info'] as Map<String, dynamic>)['mobilesdk_app_id'] as String,
      'messagingSenderId': projectInfo['project_number'] as String,
      'projectId': projectInfo['project_id'] as String,
      'storageBucket': projectInfo['storage_bucket'] as String,
    },
  };
}

String _options(String name, Map<String, String> values) {
  final fields = values.entries.map((e) => "    ${e.key}: '${e.value}',").join('\n');
  return '  static const FirebaseOptions $name = FirebaseOptions(\n$fields\n  );\n';
}

Future<void> _writeOptions(String path, Map<String, Map<String, String>> configs) async {
  final buffer = StringBuffer()
    ..writeln('// GENERATED by scripts/provision_firebase.dart for project $_projectId.')
    ..writeln('// Re-run that script (or `flutterfire configure`) to regenerate.')
    ..writeln('// These are client identifiers, not secrets: access is enforced by')
    ..writeln('// Firebase Auth + firestore.rules, not by hiding these values.')
    ..writeln('// ignore_for_file: type=lint')
    ..writeln("import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;")
    ..writeln("import 'package:flutter/foundation.dart'")
    ..writeln('    show TargetPlatform, defaultTargetPlatform, kIsWeb;')
    ..writeln()
    ..writeln('class DefaultFirebaseOptions {')
    ..writeln('  static FirebaseOptions get currentPlatform {')
    ..writeln('    if (kIsWeb) return web;')
    ..writeln('    switch (defaultTargetPlatform) {')
    ..writeln('      case TargetPlatform.android:')
    ..writeln('        return android;')
    ..writeln('      case TargetPlatform.iOS:')
    ..writeln('        return ios;')
    ..writeln('      case TargetPlatform.macOS:')
    ..writeln('        return macos;')
    ..writeln('      case TargetPlatform.windows:')
    ..writeln('        return windows;')
    ..writeln('      default:')
    ..writeln('        throw UnsupportedError(')
    ..writeln("          'MedBills supports iOS, Android, macOS, Windows and web.',")
    ..writeln('        );')
    ..writeln('    }')
    ..writeln('  }')
    ..writeln()
    ..write(_options('web', configs['web']!))
    ..writeln()
    ..write(_options('android', configs['android']!))
    ..writeln()
    ..write(_options('ios', configs['apple']!))
    ..writeln()
    ..write(_options('macos', configs['apple']!))
    ..writeln()
    // Windows has no native Firebase app type; FlutterFire uses the web app.
    ..write(_options('windows', configs['web']!))
    ..writeln('}');
  await File(path).writeAsString(buffer.toString());
  stdout.writeln('  wrote $path');
}

Future<void> _enableEmailAuth() async {
  stdout.writeln('== Enabling Email/Password sign-in ==');
  final url =
      'https://identitytoolkit.googleapis.com/admin/v2/projects/$_projectId/config?updateMask=signIn.email.enabled,signIn.email.passwordRequired';
  final response = await _client.patch(Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'signIn': {
          'email': {'enabled': true, 'passwordRequired': true},
        },
      }));
  if (response.statusCode == 404 || response.body.contains('CONFIGURATION_NOT_FOUND')) {
    stdout.writeln('  auth not initialised yet — initialising');
    await _post(
        'https://identitytoolkit.googleapis.com/v2/projects/$_projectId/identityPlatform:initializeAuth',
        {}, 'initialise auth');
    await _patch(url, {
      'signIn': {
        'email': {'enabled': true, 'passwordRequired': true},
      },
    }, 'enable email auth');
  } else {
    await _json(response, 'enable email auth');
  }
  stdout.writeln('  done');
}

Future<void> _deployRules(rules.FirebaseRulesApi api, String rulesPath) async {
  stdout.writeln('== Deploying Firestore rules ==');
  final source = await File(rulesPath).readAsString();
  final ruleset = await api.projects.rulesets.create(
    rules.Ruleset(
      source: rules.Source(files: [rules.File(name: 'firestore.rules', content: source)]),
    ),
    'projects/$_projectId',
  );
  final releaseName = 'projects/$_projectId/releases/cloud.firestore';
  try {
    await api.projects.releases.patch(
      rules.UpdateReleaseRequest(release: rules.Release(name: releaseName, rulesetName: ruleset.name)),
      releaseName,
    );
  } on rules.DetailedApiRequestError catch (e) {
    if (e.status != 404) rethrow;
    await api.projects.releases.create(
      rules.Release(name: releaseName, rulesetName: ruleset.name),
      'projects/$_projectId',
    );
  }
  stdout.writeln('  released ${ruleset.name}');
}

Future<void> _deployIndexes(firestore.FirestoreApi api, String indexesPath) async {
  stdout.writeln('== Deploying Firestore indexes ==');
  final spec = jsonDecode(await File(indexesPath).readAsString()) as Map<String, dynamic>;
  final db = 'projects/$_projectId/databases/(default)';

  for (final raw in (spec['indexes'] as List<dynamic>)) {
    final index = raw as Map<String, dynamic>;
    final group = index['collectionGroup'] as String;
    final parent = '$db/collectionGroups/$group';
    final fields = (index['fields'] as List<dynamic>).cast<Map<String, dynamic>>();
    final existing = await api.projects.databases.collectionGroups.indexes.list(parent);
    final already = (existing.indexes ?? []).any((i) {
      if (!(i.name ?? '').contains('/collectionGroups/$group/')) return false;
      final paths = (i.fields ?? [])
          .where((f) => f.fieldPath != '__name__')
          .map((f) => '${f.fieldPath}:${f.order}')
          .join(',');
      return i.queryScope == index['queryScope'] &&
          paths == fields.map((f) => '${f['fieldPath']}:${f['order']}').join(',');
    });
    if (already) {
      stdout.writeln('  $group index exists');
      continue;
    }
    await api.projects.databases.collectionGroups.indexes.create(
      firestore.GoogleFirestoreAdminV1Index(
        queryScope: index['queryScope'] as String,
        fields: fields
            .map((f) => firestore.GoogleFirestoreAdminV1IndexField(
                  fieldPath: f['fieldPath'] as String,
                  order: f['order'] as String,
                ))
            .toList(),
      ),
      parent,
    );
    stdout.writeln('  $group index created (builds in the background)');
  }

  for (final raw in (spec['fieldOverrides'] as List<dynamic>? ?? const [])) {
    final override = raw as Map<String, dynamic>;
    final name =
        '$db/collectionGroups/${override['collectionGroup']}/fields/${override['fieldPath']}';
    await api.projects.databases.collectionGroups.fields.patch(
      firestore.GoogleFirestoreAdminV1Field(
        indexConfig: firestore.GoogleFirestoreAdminV1IndexConfig(
          indexes: (override['indexes'] as List<dynamic>).cast<Map<String, dynamic>>().map((i) {
            return firestore.GoogleFirestoreAdminV1Index(
              queryScope: i['queryScope'] as String,
              fields: [
                firestore.GoogleFirestoreAdminV1IndexField(
                  fieldPath: override['fieldPath'] as String,
                  order: i['order'] as String?,
                  arrayConfig: i['arrayConfig'] as String?,
                ),
              ],
            );
          }).toList(),
        ),
      ),
      name,
      updateMask: 'indexConfig',
    );
    stdout.writeln('  ${override['collectionGroup']}.${override['fieldPath']} override applied');
  }
}

String _randomPassword() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';
  final random = Random.secure();
  return List.generate(14, (_) => chars[random.nextInt(chars.length)]).join();
}

firestore.Value _s(String v) => firestore.Value(stringValue: v);
firestore.Value _b(bool v) => firestore.Value(booleanValue: v);
firestore.Value _t(DateTime v) => firestore.Value(timestampValue: v.toUtc().toIso8601String());

Future<void> _ensureStore(firestore.FirestoreApi api, String storeId, String storeName) async {
  stdout.writeln('== Store profile ==');
  final name = 'projects/$_projectId/databases/(default)/documents/stores/$storeId';
  try {
    await api.projects.databases.documents.get(name);
    stdout.writeln('  stores/$storeId exists');
  } on firestore.DetailedApiRequestError catch (e) {
    if (e.status != 404) rethrow;
    await api.projects.databases.documents.patch(
      firestore.Document(fields: {
        'storeId': _s(storeId),
        'name': _s(storeName),
        'addressLine': _s(''),
        'city': _s(''),
        'state': _s('Madhya Pradesh'),
        'phone': _s(''),
        'gstin': _s(''),
        'drugLicenseNumbers': _s(''),
        'createdAt': _t(DateTime.now()),
      }),
      name,
    );
    stdout.writeln('  created stores/$storeId');
  }
}

Future<void> _ensureStaff(
  firestore.FirestoreApi api,
  String storeId,
  List<String> staffSpecs,
) async {
  stdout.writeln('== Staff accounts ==');
  for (final spec in staffSpecs) {
    final parts = spec.split(':');
    if (parts.length != 3) throw Exception('--staff must be role:Name:email, got "$spec"');
    final role = parts[0];
    final displayName = parts[1];
    final email = parts[2].toLowerCase();
    if (!{'owner', 'pharmacist', 'counterStaff'}.contains(role)) {
      throw Exception('Unknown role "$role"');
    }

    final lookup = await _post(
      'https://identitytoolkit.googleapis.com/v1/projects/$_projectId/accounts:lookup',
      {'email': [email]},
      'lookup $email',
    );
    String uid;
    final users = lookup['users'] as List<dynamic>?;
    if (users != null && users.isNotEmpty) {
      uid = (users.first as Map<String, dynamic>)['localId'] as String;
      stdout.writeln('  $role $email exists (uid $uid) — password unchanged');
    } else {
      final password = _randomPassword();
      final created = await _post(
        'https://identitytoolkit.googleapis.com/v1/projects/$_projectId/accounts',
        {'email': email, 'password': password, 'displayName': displayName, 'emailVerified': true},
        'create $email',
      );
      uid = created['localId'] as String;
      stdout.writeln('  CREATED $role  $email  password: $password');
    }

    await api.projects.databases.documents.patch(
      firestore.Document(fields: {
        'uid': _s(uid),
        'storeId': _s(storeId),
        'name': _s(displayName),
        'email': _s(email),
        'role': _s(role),
        'active': _b(true),
      }),
      'projects/$_projectId/databases/(default)/documents/users/$uid',
    );
  }
}

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('credentials', help: 'Service account JSON (defaults to \$GOOGLE_APPLICATION_CREDENTIALS)')
    ..addOption('project', help: 'Project ID (defaults to the service account\'s project_id)')
    ..addOption('store-id', defaultsTo: 'store_primary')
    ..addOption('store-name', defaultsTo: 'MedBills Pharmacy')
    ..addMultiOption('staff', help: 'role:Display Name:email (repeatable)')
    ..addOption('options-out', defaultsTo: '../lib/firebase_options.dart')
    ..addOption('rules', defaultsTo: '../firestore.rules')
    ..addOption('indexes', defaultsTo: '../firestore.indexes.json')
    ..addFlag('help', abbr: 'h', negatable: false);
  final args = parser.parse(arguments);
  if (args['help'] as bool) {
    stdout.writeln(parser.usage);
    return;
  }

  final credentialsPath =
      args['credentials'] as String? ?? Platform.environment['GOOGLE_APPLICATION_CREDENTIALS'];
  if (credentialsPath == null) {
    stderr.writeln('Pass --credentials or set GOOGLE_APPLICATION_CREDENTIALS.');
    exitCode = 1;
    return;
  }
  final credentials =
      jsonDecode(await File(credentialsPath).readAsString()) as Map<String, dynamic>;
  _projectId = args['project'] as String? ?? credentials['project_id'] as String;

  _client = await auth.clientViaServiceAccount(
    auth.ServiceAccountCredentials.fromJson(credentials),
    ['https://www.googleapis.com/auth/cloud-platform'],
  );
  final firestoreApi = firestore.FirestoreApi(_client);
  final rulesApi = rules.FirebaseRulesApi(_client);

  try {
    final configs = await _registerApps();
    await _writeOptions(args['options-out'] as String, configs);
    await _enableEmailAuth();
    await _deployRules(rulesApi, args['rules'] as String);
    await _deployIndexes(firestoreApi, args['indexes'] as String);
    await _ensureStore(firestoreApi, args['store-id'] as String, args['store-name'] as String);
    await _ensureStaff(firestoreApi, args['store-id'] as String, args['staff'] as List<String>);
    stdout.writeln('\nProvisioning complete for $_projectId.');
  } finally {
    _client.close();
  }
}
