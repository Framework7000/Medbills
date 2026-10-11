# MedBills (Nuskha PMS)

Pharmacy billing and stock for a medical store, built with Flutter + Firebase.
One shared store database: every iPhone, Mac, Windows PC and Android phone
signed in to the store sees the same bills, stock and udhaar in real time.

| Device | What it is for |
| --- | --- |
| **Windows / Mac** (counter) | Billing with keyboard shortcuts (F2 search, F9 complete), USB/Bluetooth barcode scanner, A4 / 80 mm printing, reports, purchases. Can receive scans sent from a phone. |
| **iPhone / Android** | Everything above, plus camera barcode scanning, reading a medicine pack from a photo, and photographing supplier bills. |
| **Web** | A demo with sample data only (for showing the app). It does not touch the store database. |

## Features

- **Billing** — search by brand, generic or maker; FEFO batch picking (nearest
  expiry first); strips and loose tablets; cash / UPI / card / udhaar; GST
  extracted from MRP per slab with CGST/SGST split and round-off; Schedule H1/X
  sales blocked until patient and doctor details are entered; A4 GST invoice
  or 80 mm thermal print, PDF, WhatsApp bill.
- **Scanning**
  - *Barcode*: EAN/UPC, GS1 DataMatrix (with batch + expiry) and the text QR
    codes on Indian packs. A scan adds one pack, from the scanned batch if it's
    on the shelf. Expired packs are refused. Unknown barcodes can be linked to
    a medicine once and are recognised everywhere after that.
  - *Read pack*: photograph a strip — the app reads the printed text on the
    phone itself and finds the exact medicine (brand **and** strength, so
    Dolo 650 is never taken for Dolo 500), plus batch, expiry and MRP.
  - *Supplier bill*: photograph the bill — the picture is kept, and the
    supplier, GSTIN, drug licence, bill number, date and every line (medicine,
    batch, expiry, quantity, free, rate, MRP) are read out. You check and
    correct each line, then receive the whole bill into stock in one go.
  - *Phone → counter*: switch on "Receive scans from a phone" on the counter
    PC; on the phone, scan and choose that counter — items appear on the
    counter's bill.
  - All text reading happens on the device; nothing is sent to an AI service.
- **Stock** — batches with expiry, MRP and cost; low / out / expiring /
  expired / unclassified filters; block a batch (recall).
- **Purchases** — receive stock by hand or from a scanned bill; free/scheme
  quantities; margin shown.
- **Bills** — search any bill by number, customer, phone or medicine; managers
  can cancel with a reason (stock and udhaar are restored, nothing is deleted).
- **Udhaar** — customer accounts with credit limit, ledger, payments.
- **Reports** — today / month / custom: collections, GST by slab, payment
  modes, purchase cost and margin, top medicines, Schedule H1/X register,
  stock alerts.
- **Roles** — Owner (everything), Pharmacist (stock, cancellations, reports),
  Counter staff (billing only). Enforced by Firestore security rules on the
  server, not just hidden in the app.

## Run it on your machines

Install Flutter (https://docs.flutter.dev/get-started/install), then:

```bash
git clone https://github.com/Framework7000/Medbills.git
cd Medbills && git checkout claude/medbills-repo-t8ueeh
./setup.sh
```

| Platform | Needs | Run / build |
| --- | --- | --- |
| Windows | Visual Studio 2022 with "Desktop development with C++" | `flutter run -d windows` · `flutter build windows` |
| Mac | Xcode + CocoaPods (`sudo gem install cocoapods`) | `flutter run -d macos` · `flutter build macos` |
| iPhone (iOS 15.5+, e.g. XR, 11–17) | Xcode on a Mac, iPhone connected | `flutter run -d <iphone>` · `flutter build ipa` |
| Android (6.0+) | Android Studio | `flutter run -d <phone>` · `flutter build apk` |

**Apple signing (iPhone and Mac):** open `ios/Runner.xcworkspace` (and
`macos/Runner.xcworkspace`) in Xcode → Runner → *Signing & Capabilities* →
choose your Team (a free Apple ID works for your own devices). The Mac app
needs this for sign-in to work (it stores the login in the Keychain).

Sign in with a staff account (see below). After the first sign-in the store's
data stays readable if the internet drops; completing a sale needs a
connection, so two counters can never sell the same last strip.

## Store database (Firebase project `medbills-176df`)

`lib/firebase_options.dart` already points at the store's project. Layout:

```
users/{uid}                         staff profile: storeId, role, active
stores/{storeId}                    store name, address, GSTIN, drug licences
  medicines/{id}                    master: brand, generic, pack, HSN, GST, schedule, barcode
  batches/{medicineId__BATCH}       stock in base units, expiry, MRP + cost per pack
  sales/{id}                        GST invoice; never deleted, only cancelled
  counters/{financialYear}          next invoice number (rules allow +1 only)
  purchases/{id}                    every stock-in, linked to its scanned bill
  customers/{id}/ledger/{id}        udhaar accounts and entries
  billScans/{id}, billScanImages/{id}   photographed supplier bills
  stations/{id}, scanEvents/{id}    phone → counter scanning
  auditLog/{id}                     cancellations, master edits, blocks
```

Staff accounts, security rules and the store document are created by
`scripts/provision_firebase.dart`; the medicine master is loaded by
`scripts/seed_store_medicines.dart` (see `scripts/README.md`). Both need the
Firebase service-account key — keep it off GitHub (it's git-ignored).

To add a staff member later:

```bash
cd scripts
dart run provision_firebase.dart --credentials /path/to/key.json \
  --staff "counterStaff:Ravi:ravi@yourstore.in"
```

## Rules the code follows

1. Medicine and Batch are separate records.
2. Stock is held in base units (tablets); packs are converted at the edges.
3. Every stock change runs in a Firestore transaction that reads before writing.
4. MRP is GST-inclusive; tax is extracted, never added.
5. GST is rounded once per slab, not per line.
6. Invoice numbers come from a per-financial-year counter advanced inside the
   sale transaction; security rules only allow it to move by exactly +1.
7. `lib/domain/` has no Firebase imports.
8. Every document carries `storeId`.
9. Schedule H1/X sales are blocked until patient and prescriber are recorded.
10. Sales are never deleted — cancelled with a reason and an audit entry.
11. An unclassified drug is `UNKNOWN` and cannot be sold, never OTC.
12. Money is integer paise, never a floating-point number.

## Code layout

```
lib/domain/        pure Dart: models, GST maths, FEFO, checkout rules,
                   barcode/pack/bill text readers (fully unit-tested)
lib/data/          PharmacyRepository: Firestore (real store) and in-memory (demo)
lib/state/         Riverpod providers, cart
lib/platform/      PDF/print, WhatsApp, on-device text reading, photo compression
lib/presentation/  screens (phone, tablet and desktop layouts)
scripts/           provisioning and medicine-master seeding (plain Dart)
```

```bash
flutter analyze
flutter test        # 88 tests: maths, rules, both repositories, scanning,
                    # and every screen at iPhone SE / XR / iPad / desktop sizes
```

## Known limits

- Text reading (pack and bill photos) runs on iPhone and Android. On Windows
  and Mac you can attach a bill photo and type the lines, or photograph it
  with the phone — it appears on the counter instantly.
- Bill reading is rule-based, so unusual bill layouts need more correction;
  every value is shown next to the row it came from before stock is added.
- Drug schedules in the bundled catalogue were checked against CDSCO
  classifications, but the pharmacist should confirm any medicine before
  first sale (Stock → medicine → edit).
- The native apps could not be compiled in the cloud environment this was
  built in (Linux, no Xcode/Visual Studio); build them on your Mac / PC.
