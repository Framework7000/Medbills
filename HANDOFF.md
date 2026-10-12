# Handover — continue MedBills on a local machine

Read this first, then `README.md`. Branch: `claude/medbills-repo-t8ueeh`
(GitHub: Framework7000/Medbills). Everything below is pushed.

## What the owner wants

A pharmacy (medical store, Madhya Pradesh) billing + stock app that works
"perfectly everywhere":
- **Windows laptop / Mac** — big-screen counter app (`.exe` installer for Windows).
- **iPhone (XR now, iPhone 17 for the brother)** — phone app, used in the shop
  **without cables**; installing should be "just press Install".
- All devices share one live store database (Firebase project `medbills-176df`).
- The web page (claude.ai artifact `VjMM6vXGRdGic36XngpUL4`) is only a demo.
- Scanning: barcode (camera / USB), read a medicine pack from a photo, scan a
  supplier bill photo (keeps the photo, reads supplier/GSTIN/bill no./lines),
  phone → counter scanning. Text reading is on-device only (owner's choice: no AI service).
- The owner follows the blueprint's 12 rules (see README "Rules the code follows").

## State (all done, all pushed)

- App: Flutter 3.47.4, Riverpod, Firebase (Auth + Firestore). 88 tests pass,
  `flutter analyze` clean (run `cd scripts && dart pub get` once first).
- GitHub Actions `.github/workflows/build.yml` builds on real machines and
  publishes https://github.com/Framework7000/Medbills/releases/tag/latest-build :
  `MedBills-Setup.exe` (Inno Setup, per-user, VC++ runtime bundled),
  `MedBills-Mac.dmg` (ad-hoc signed, no sandbox — `macos/Runner/Unsigned.entitlements`),
  `MedBills-Android.apk`, `MedBills-iOS-unsigned.ipa`, portable Windows zip.
  Windows/macOS/iOS/Android builds were confirmed compiling on GitHub runners
  before the installer/DMG/icon commit; check that the latest run is green.
- `.github/workflows/ios-testflight.yml`: uploads to TestFlight once these repo
  secrets exist: `APPLE_TEAM_ID`, `APP_STORE_CONNECT_KEY_ID`,
  `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_KEY` (needs a paid Apple
  Developer account and an App Store Connect app for `com.medbills.nuskhaPms`).
  This is the "iPhone 17 without cable" path. Not yet run.
- Live Firestore: `stores/store_primary` with 92 medicines (no stock yet — stock
  comes only from real purchases), 3 staff accounts (owner / pharmacist /
  counter @medbills-176df.firebaseapp.com — passwords were given to the owner
  in chat, never stored in the repo). Security rules deployed and checked with
  real sign-ins (18/18). Untouched on purpose: root `imd_e2e_dolo` and `scan_events`.

## Next steps (in order)

1. **Install on the owner's iPhone XR (cable, on a Mac with Xcode):**
   `flutter pub get && cd ios && pod install && cd ..`, open
   `ios/Runner.xcworkspace` → Runner → Signing & Capabilities → choose the
   owner's Team (free Apple ID works), then `flutter run --release -d <XR>`.
   On the phone: Settings → General → VPN & Device Management → Trust;
   Settings → Privacy & Security → Developer Mode on. Sign in as owner and
   test: Scan tab (camera barcode, Read pack, Scan supplier bill), Billing,
   a real stock-in via Purchases, a test sale (cancel it after — never delete).
2. **Mac app** on the same Mac: `flutter run --release -d macos` (select the
   same Team for `macos/Runner.xcworkspace`; keychain sharing needs it).
3. **Windows**: download `MedBills-Setup.exe` from the release, install on the
   laptop, sign in, make sure a sale on the iPhone shows up on Windows live.
4. **Phone → counter**: Windows Billing → Scan (F3) → "Use a phone as the
   scanner"; on the iPhone Scan tab choose that counter; scan a pack.
5. **Rules emulator test (was in progress):** replay every write the app makes
   (FirestorePharmacyRepository on fake_cloud_firestore → dump) against
   `firestore.rules` in the Firestore emulator as owner / pharmacist / counter.
   A partial read-through of the rules against the models found no mismatch, but it was
   NOT a full check, so treat the rules/app agreement as unproven until this runs.
   Also unproven: sign-in and Firestore from the native apps (only tested with a fake
   Firestore); the GitHub-built Mac DMG removes the keychain entitlement, so Firebase
   Auth may fail there with a keychain error — use a Mac build signed with a Team.
6. **iPhone 17 (brother):** owner buys Apple Developer Program, adds the four
   secrets, runs "iPhone → TestFlight"; brother installs from TestFlight.
7. Owner tasks: fill store details in Settings (GSTIN, drug licence, address —
   printed on every bill); change staff passwords; rotate the Firebase
   service-account key that was shared in chat (delete key `d929e6bea1…` in
   Google Cloud → IAM → Service accounts).

## Things to keep in mind

- Never fall back to demo data on native apps (`lib/main.dart` shows a
  "could not start" screen instead).
- Never invent stock or sales in the live store; test sales use real invoice
  numbers — cancel with a reason, never delete.
- Drug schedules in `lib/data/repositories/global_catalogue_repository.dart`
  were corrected (PPIs, montelukast, mefenamic, dicyclomine, framycetin = H;
  clonazepam = H1). The pharmacist should still confirm each before first sale.
- `flutter_launcher_icons` writes a wrong key into `ios/Runner.xcodeproj/project.pbxproj`
  (`ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = AppIcon`);
  revert that file after regenerating icons.
- Admin scripts (`scripts/`) need the service-account key by path; never commit it.
