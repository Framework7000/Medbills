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

- App: Flutter 3.47.4, Riverpod, Firebase (Auth + Firestore). 90 widget/unit
  tests pass, `flutter analyze` clean (run `cd scripts && dart pub get` once first).
- **Firestore security rules are now proven, not just read through.**
  `firestore_rules_test/` replays every write `FirestorePharmacyRepository`
  makes against `firestore.rules` in the real Firestore emulator, as owner /
  pharmacist / counterStaff, plus cross-store isolation and deactivated-account
  checks — 62/62 pass (`cd firestore_rules_test && npm install && npm test`).
- **Mac app runs for real on this Mac**, signed with the owner's free Apple
  Developer team (`Z9MZ6L5GMS`) and installed at `/Applications/MedBills.app`.
  Every screen (Billing, Scan, Stock, Bills, Udhaar, Purchases, Reports,
  Settings) was walked through live and renders cleanly at both normal and
  resized-small windows. The in-app camera scan flow (Scan → "Scan into bill")
  was exercised too: it asks for camera permission and shows a live preview.
  Signed in as the owner (`yash@gmail.com`), session persists across restarts.
- Fixed a real bug found during that walkthrough: `NavigationRail` didn't
  scroll on a short/resized desktop window and threw a `RenderFlex
  overflowed` banner. Fixed in `lib/presentation/home_shell.dart` (the rail is
  now wrapped in a `SingleChildScrollView`) and covered by a new test size
  (`Short Mac window (900×600)`) in `test/presentation/app_smoke_test.dart`.
- **Fixed a macOS CI regression** introduced while getting this Mac signing
  for real: `DEVELOPMENT_TEAM`/`CODE_SIGN_IDENTITY` had been hardcoded
  straight into `macos/Runner.xcodeproj/project.pbxproj`, which broke
  `flutter build macos --release` on GitHub's runners (no such
  certificate/team there). Moved the real identity into
  `macos/Runner/Configs/Local.xcconfig` — gitignored, included optionally
  from `AppInfo.xcconfig` — so this Mac still signs for real and CI (and any
  other machine) still falls back to the existing ad-hoc `"-"` signing with
  `macos/Runner/Unsigned.entitlements`. Verified both paths build locally
  before pushing.
- GitHub Actions `.github/workflows/build.yml` builds on real machines and
  publishes to https://github.com/Framework7000/Medbills/releases/tag/latest-build :
  `MedBills-Setup.exe` (Inno Setup, per-user, VC++ runtime bundled),
  `MedBills-Mac.dmg` (ad-hoc signed, no sandbox), `MedBills-Android.apk`,
  `MedBills-iOS-unsigned.ipa`, portable Windows zip.
  **Check this is still true before trusting it** — at the time of writing,
  `releases/tag/latest-build` 404s even though an earlier run's `release` job
  reported success; the next push's run (after this handover) should confirm
  whether that was a one-off or whether the `release` job needs a real look
  (`gh release create ... dist/*` with the glob possibly expanding to nothing,
  or a permissions issue that doesn't fail the step loudly). Don't assume the
  download links in the workflow's own release notes work until you've
  clicked one.
- `.github/workflows/ios-testflight.yml`: uploads to TestFlight once these repo
  secrets exist: `APPLE_TEAM_ID`, `APP_STORE_CONNECT_KEY_ID`,
  `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_KEY` (needs a paid Apple
  Developer account and an App Store Connect app for `com.medbills.nuskhaPms`).
  This is the "iPhone 17 without cable" path. Not yet run.
- Live Firestore: `stores/store_primary` with 92 medicines (no stock yet — stock
  comes only from real purchases), owner account simplified to a single
  sign-in: `yash@gmail.com` / password given to the owner directly in chat
  (never stored in the repo). Untouched on purpose: root `imd_e2e_dolo` and
  `scan_events`.

## Next steps (in order)

1. **Confirm the `latest-build` release actually has fresh assets** (see the
   warning above) — open the Releases page, or
   `curl -I https://github.com/Framework7000/Medbills/releases/download/latest-build/MedBills-Setup.exe`
   and expect a redirect, not 404.
2. **Install on the owner's iPhone XR** (cable, on this Mac — Xcode and
   CocoaPods are already set up): `flutter pub get && cd ios && pod install
   && cd ..`, open `ios/Runner.xcworkspace` → Runner → Signing & Capabilities
   → Team `Z9MZ6L5GMS` is already selected project-wide, then
   `flutter run --release -d <XR's udid>` (passes
   `-allowProvisioningUpdates` automatically). On the phone: Settings →
   Privacy & Security → Developer Mode on (needed once); after install,
   Settings → General → VPN & Device Management → trust the developer
   certificate (needed again after every reinstall). A free Apple ID account
   can only have 3 apps installed at once — if you hit "maximum number of
   installed apps", remove an old/stale one first
   (`xcrun devicectl device info apps --device <udid>`, then
   `xcrun devicectl device uninstall app --device <udid> <bundle-id>`).
   Sign in as owner and test: Scan tab (camera barcode, Read pack, Scan
   supplier bill), Billing, a real stock-in via Purchases, a test sale
   (cancel it after — never delete).
3. **Live-sync test**: with the Mac app and the iPhone app both signed in,
   confirm a sale/stock change on one shows up on the other within a couple
   of seconds.
4. **Phone → counter**: Billing → Scan (F3) → "Use a phone as the scanner"
   on the Mac/Windows counter; on the iPhone Scan tab choose that counter;
   scan a pack and watch it land on the counter's bill.
5. **Windows**: download `MedBills-Setup.exe` from the release (once step 1
   above is confirmed working), install on the brother's laptop, sign in,
   make sure a sale on the iPhone shows up on Windows live.
6. **iPhone 17 (brother):** owner buys Apple Developer Program, adds the four
   secrets, runs "iPhone → TestFlight"; brother installs from TestFlight —
   see "Brother's setup" below for the exact steps to hand him.
7. Owner tasks: fill store details in Settings (GSTIN, drug licence, address —
   printed on every bill); rotate the Firebase service-account key that was
   shared in chat during an earlier session (delete key `d929e6bea1…` in
   Google Cloud → IAM → Service accounts) if that hasn't been done yet.

## Brother's setup (Windows laptop + iPhone 17, no cables)

**Windows laptop:**
1. Open the latest-build release page, download `MedBills-Setup.exe`.
2. Double-click it. If Windows shows "Windows protected your PC" (normal —
   the app isn't bought through the Microsoft Store), click **More info** →
   **Run anyway**.
3. Finish the installer, open MedBills, sign in with the owner-provided
   account.
4. If a sale rung up on another device doesn't show up, check the laptop's
   internet connection — sales need it; stock/bills still display from the
   last sync while offline.

**iPhone 17 (TestFlight, no cable):**
This needs the owner to do two things first — nobody can shortcut this
without paying for a Developer account:
1. Owner enrols in the **Apple Developer Program** (one-time, ~₹8,300/yr) at
   developer.apple.com.
2. Owner (or whoever has repo access) creates an App Store Connect app for
   `com.medbills.nuskhaPms` and adds four GitHub repo secrets:
   `APPLE_TEAM_ID`, `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`,
   `APP_STORE_CONNECT_KEY` — then runs the "iPhone → TestFlight" GitHub
   Action (Actions tab → that workflow → Run workflow).
3. Once that upload finishes (check App Store Connect → TestFlight), add the
   brother's Apple ID email as a TestFlight tester there.
4. Brother installs the **TestFlight** app from the App Store, accepts the
   email invite, installs MedBills from inside TestFlight — no cable, no
   Xcode, no Developer Mode toggle (that's only for cable/Xcode installs).
5. Sign in with the owner-provided account; everything syncs with the same
   live store as the Mac/Windows/XR.

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
- `macos/Runner/Configs/Local.xcconfig` holds this Mac's real signing identity
  and is gitignored on purpose — don't commit it, and don't copy it to
  another machine (each Mac that wants real signing needs its own, with its
  own Team ID / identity).
- Do not touch the `users/{uid}` Firebase Auth/Firestore accounts or request
  a fresh service-account key without being asked — the owner was explicit
  about this during the last session.
