# MedBills (Nuskha PMS)

Cross-platform pharmacy (medical store) management system built with Flutter,
Riverpod, and Firebase. See the full architecture, rules, and defect history
this codebase was rebuilt from in the project blueprint shared with this
repository's maintainers.

## Getting started

This repo ships the Dart/Flutter source (`lib/`, `test/`) and `pubspec.yaml`.
Platform runner folders (`android/`, `ios/`, `windows/`, `macos/`, `web/`) are
generated locally, not committed, so first-time setup is:

```bash
flutter create --platforms=windows,web,android,macos .
flutter pub get
```

### Run

```bash
flutter run -d windows   # or -d chrome, -d macos, etc.
```

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

## Known limitations

- The bundled medicine catalogue is a 31-item in-memory seed; the full
  253,973-row dataset ships as a read-only SQLite file in production
  (`lib/data/services/sqlite_catalogue_service.dart` is wired for it).
- Invoice numbering is currently client-side; production needs a Cloud
  Function (Rule 6).
- Firebase Auth is not yet wired to real login UI — roles are switched via
  `UserAuthNotifier` for now.
- Firestore Security Rules enforcing `storeId`-scoped access are not yet
  included in this repo.
