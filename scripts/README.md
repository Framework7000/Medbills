# scripts/

Plain-Dart tools (no Flutter needed) for setting up the store's Firebase
project. Both need a Firebase service-account key: Firebase Console → Project
settings → Service accounts → Generate new private key. Keep that file off
GitHub (the repo ignores `*firebase-adminsdk*.json`) and pass it by path.

```bash
cd scripts
dart pub get
```

## provision_firebase.dart

Idempotent setup of a project:

1. Registers the iOS/macOS (`com.medbills.nuskhaPms`), Android
   (`com.medbills.nuskha_pms`) and web apps and writes
   `lib/firebase_options.dart`.
2. Enables email/password sign-in.
3. Deploys `../firestore.rules` and `../firestore.indexes.json`.
4. Creates the store document and staff accounts (`--staff role:Name:email`,
   roles `owner`, `pharmacist`, `counterStaff`). A new account's password is
   printed once — hand it over and have them change it in Settings.

```bash
dart run provision_firebase.dart --credentials /path/to/key.json \
  --store-name "Your Pharmacy" \
  --staff "owner:Owner Name:owner@yourstore.in" \
  --staff "counterStaff:Counter:counter@yourstore.in"

# After editing firestore.rules:
dart run provision_firebase.dart --credentials /path/to/key.json --rules-only
```

## seed_store_medicines.dart

Loads the medicine master (brand, generic, maker, pack size, HSN, GST, drug
schedule) into `stores/{store}/medicines` from the catalogue the app itself
ships (`lib/data/repositories/global_catalogue_repository.dart`).

It creates **no stock**: batches only come from real deliveries entered in
Purchases. Re-running is safe — medicines already in the store are left
untouched, so edits made in the app are kept.

```bash
dart run seed_store_medicines.dart --dry-run                     # preview
dart run seed_store_medicines.dart --credentials /path/to/key.json
```

`--remove-legacy` deletes the root-level `medicines/med_NNN` documents (with
their made-up batches) written by the first version of this script; nothing
else is touched.
