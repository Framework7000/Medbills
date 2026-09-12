# scripts/

Standalone Dart CLI tools for MedBills. This folder has its own
`pubspec.yaml` with no `flutter` SDK dependency, so these scripts run with
a plain Dart SDK (`dart run`) on any machine — a CI runner or a laptop
without Flutter installed — independent of the main app's dependencies.

## seed_mp_medicines.dart

Seeds the live Firestore database with 42 authentic, fast-moving Madhya
Pradesh pharmacy formulations (real brand names, manufacturers, HSN codes,
GST rates, and CDSCO schedule classifications), each with one starter
batch (realistic batch number, expiry 6–24 months out, quantity 100–500
base units).

Writes the exact document shape `MedicineRepository` / `BatchRepository`
expect (`lib/domain/models/medicine.dart` and `batch.dart`), so once your
`lib/firebase_options.dart` points at the same project, the app reads this
data immediately.

### Setup

```bash
cd scripts
dart pub get
```

### Preview without writing anything

```bash
dart run seed_mp_medicines.dart --dry-run
```

### Seed a real project

1. In the Firebase console, create a service account with Firestore
   read/write access (Project Settings → Service Accounts → Generate new
   private key) and download the JSON key.
2. Run:

```bash
dart run seed_mp_medicines.dart \
    --project your-firebase-project-id \
    --credentials /path/to/service-account.json
```

`--project` is optional — it defaults to the `project_id` already inside
the service account JSON. `--credentials` defaults to
`$GOOGLE_APPLICATION_CREDENTIALS` if set.

Re-running the script is safe: every write is a `patch` (upsert) keyed by
medicine id, so it converges rather than duplicating documents.

### What it does not do

It does not touch the bundled 253,973-row SQLite catalogue
(`assets/catalogue.db`, read by `SqliteCatalogueService`) — that's the
read-only master search index. This script only populates the live
per-store inventory (`medicines` + `medicines/{id}/batches`), i.e. what
`store_primary` actually has on its shelves.
