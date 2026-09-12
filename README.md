# MedBills (Nuskha PMS)

Cross-platform pharmacy (medical store) management system built with Flutter,
Riverpod, and Firebase. See the full architecture, rules, and defect history
this codebase was rebuilt from in the project blueprint shared with this
repository's maintainers.

## Resuming this project on your own machine

Everything built in the Claude session so far — the app, the tests, the
Firebase connection, the seeded Firestore data — is captured in this git
repo on the `claude/medbills-repo-t8ueeh` branch. Nothing was left only in
the cloud session; picking it up locally is just: clone, generate the
gitignored platform folders, fetch dependencies.

```bash
git clone https://github.com/Framework7000/Medbills.git
cd Medbills
git checkout claude/medbills-repo-t8ueeh
./setup.sh
```

`setup.sh` runs `flutter create --platforms=...` (regenerates the
`android/`/`ios/`/`windows/`/`macos/`/`web/` runner folders — these were
never committed, they're build scaffolding, not source), `flutter pub
get`, and `dart pub get` inside `scripts/`, then prints what to do next.
Requires the Flutter SDK already installed
(https://docs.flutter.dev/get-started/install).

You'll land in exactly the state this session left off in:
- `lib/firebase_options.dart` already points at the real, seeded Firebase
  project (`medbills-176df`) — desktop/mobile builds connect to it
  automatically, no extra setup.
- Firestore already has the 42-medicine Madhya Pradesh catalogue in it
  (written by `scripts/seed_mp_medicines.dart` from this session).
- All 46 tests and `flutter analyze` pass as of the last commit.

### Run

```bash
flutter run -d chrome     # or -d windows / -d macos / an Android device
```

Web builds don't auto-connect to Firebase by default — see "Firebase
project" below for why, and how to opt in.

### Test

```bash
flutter analyze
flutter test
```

## Architecture

```
lib/main.dart        Presentation — widgets, views, dialogs
lib/state/**         Riverpod StateNotifiers and stream providers
lib/domain/**        Pure Dart — GST math, FEFO, barcode parsing, validation
                      (no Firebase imports — unit-testable offline)
lib/data/**          The only layer touching Firestore/SQLite; repositories
                      return domain models, never raw snapshots
```

## Non-negotiable rules

1. Medicine and Batch are separate collections — batch data (expiry,
   purchase price, MRP, quantity) never gets flattened onto the product.
2. All stock quantities are stored in base units (tablets), converted to
   strips/boxes only at the UI layer.
3. Every stock decrement runs inside a Firestore `runTransaction`.
4. MRP in India is GST-inclusive — tax is extracted (`mrp / (1 + rate/100)`),
   never added on top.
5. GST is rounded once per tax slab, not per line item.
6. Invoice numbers are issued server-side, never client-generated.
7. Nothing under `lib/domain/` imports `cloud_firestore` or any Firebase
   package.
8. Every root document carries a `storeId`, even for a single-store
   deployment today.
9. Schedule H1 sales are hard-blocked until patient + prescriber are
   captured.
10. Sales are never deleted — cancellations are recorded with a reason and
    an audit entry; the customer credit ledger is append-only.
11. An unclassified drug's schedule defaults to `unknown`, never `otc`.
12. Money is never a `double` in persistence — integer paise or `Decimal`.

## Firebase project

`lib/firebase_options.dart` carries real credentials for a connected
Firebase project (`medbills-176df`), and its Firestore has been seeded
with the 42-medicine Madhya Pradesh catalogue via
`scripts/seed_mp_medicines.dart` (see `scripts/README.md`) — verified by
reading the documents back, independent of the app. Inventory Master
(`lib/main.dart`) reads live from `medicinesStreamProvider` /
`firestoreStockForMedicineProvider` (`lib/state/medicine_providers.dart`)
whenever `databaseStatusProvider.isConnected` is true, falling back to the
local in-memory catalogue otherwise. Every other screen (Billing,
Purchases, Bill History) still reads from local Riverpod providers either
way, so nothing in the UI breaks regardless of connection state.

**Web builds don't attempt the connection by default.** `firebase_core`'s
web implementation lazily loads the Firebase JS SDK via `import()` from
`https://www.gstatic.com`. Verified directly against this exact hosting
setup: that host returns `403` here, and the failure surfaces as an
*uncaught* JS-level error that Dart's `try/catch` in `main()` cannot
see — it blanks the entire page instead of just failing to connect. Since
that's a property of the network/CSP the page is served from rather than
whether credentials are configured, it can't be detected safely at
runtime, so web builds skip the call unless built with
`--dart-define=ENABLE_FIREBASE_WEB=true` (desktop/mobile builds don't have
this failure mode and always attempt it). The hosted build here is the
safe default — it runs in Local mode. A green "Cloud" / grey "Local" badge
under the sidebar avatar shows which mode is active; **Cloud mode has not
been visually verified in a browser**, only proven correct by direct
Firestore reads and `flutter analyze`/`flutter test` passing — try it with
`flutter run -d chrome --dart-define=ENABLE_FIREBASE_WEB=true` somewhere
that can actually reach `gstatic.com` (e.g. real Firebase Hosting), or on
a desktop/mobile build.

To point this at your own project instead:

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

This overwrites `lib/firebase_options.dart`. Then re-run the seed script
against your project's own service account (see `scripts/README.md`).

## Known limitations

- The bundled in-app medicine catalogue is a ~95-item in-memory seed; the
  full 253,973-row dataset ships as a read-only SQLite file in production
  (`lib/data/services/sqlite_catalogue_service.dart` is wired for it).
- Inventory Master reads live Firestore data when connected (see above),
  but Purchases and Billing checkout still only write to the local
  `inventoryBatchesProvider` ledger, not `BatchRepository` — so stock
  changes made in the app don't yet round-trip to Firestore. Only
  `scripts/seed_mp_medicines.dart` writes real batch data currently.
- Invoice numbering is currently client-side; production needs a Cloud
  Function (Rule 6).
- Firebase Auth is not yet wired to real login UI — roles are switched via
  `UserAuthNotifier` for now.
- Firestore Security Rules enforcing `storeId`-scoped access are not yet
  included in this repo.
- Schedule H1 sales (Rule 9) are hard-blocked at Billing Counter checkout:
  completing a sale with any H1 item shows a non-dismissible form
  requiring patient name/phone and doctor name/registration number before
  the sale can proceed (`ScheduleH1Compliance` in `lib/domain/services/`,
  captured on `SaleInvoice`). Inventory also flags every prescription item
  with an "Rx" badge.
