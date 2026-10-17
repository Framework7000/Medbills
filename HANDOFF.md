# Handover — continue MedBills on a local machine

Read this first, then `README.md`. Branch: `claude/medbills-repo-t8ueeh`
(GitHub: Framework7000/Medbills). Everything below is pushed.

## Product shape (owner, Oct 2026 — this decides every trade-off)

- **Windows laptop = the main app**: billing counter, stock, purchases,
  reports, printing. The Mac is only standing in for Windows while testing,
  so every feature must behave the same on both. Don't build anything that
  works only on the Mac. Windows has no camera scanning (mobile_scanner
  doesn't support it), so it relies on a USB scanner and the phone.
- **iPhone = mainly the scanner.** Opening the app should go straight to one
  big camera that sends what it sees to the counter. Billing, stock and bills
  on the phone are a convenient extra, not the focus.
- **Smart Scan = ONE camera, no mode buttons.** It decides by itself:
  1. **Barcode / QR / DataMatrix**: decode live from the camera stream, and
     **also from any still photo** (`MobileScannerController.analyzeImage`)
     before any text reading. GS1 DataMatrix and the Schedule H2 QR codes
     (top 300 brands since Aug 2023) carry batch and expiry, so they are the
     most accurate source.
  2. **No code → read the text** and score pack vs supplier bill on real
     signals:
     - Bill: GSTIN, invoice/bill no., several batch numbers,
       Qty/Rate/Amount columns.
     - Pack: one brand, "Mfg/Exp/B.No/MRP … incl. of all taxes", "each
       tablet contains".

     Not the amount of text: a box's back panel is long.
  3. Pack → the bill (or the receiving draft). Bill → saved photo + review
     → stock.
  4. Match against the **full catalogue**, not only medicines in stock. A
     medicine that isn't stocked yet offers "Add to stock".
- **Text reading on Mac and Windows too** (owner: on-device only, no AI
  service): macOS Vision (`VNRecognizeTextRequest`) and Windows
  `Windows.Media.Ocr`, through a small platform channel feeding the same
  `OcrPage`. A bill photo dropped on the PC then gets read like one taken
  on the phone.
- **Accuracy is measured, not assumed.** Keep a real-world test set: about
  20 packs, 5 supplier bills and 10 barcodes/QRs, photographed on the
  iPhone XR. Photos stay out of git; save the OCR text dumps as test
  fixtures. Report the hit rate per kind after every scan change. Targets:
  - codes: 99%
  - pack → right medicine and strength: 90%+
  - bill lines right before any edit: 80%+
- Medicine catalogue: see `catalogue/README.md` (GST 5% + H1 fixes first,
  then the full Indian catalogue).

## ⚠️ The project lives on an external drive now

Mid-session the Mac ran low on storage and the owner moved `~/Developer`
(both the project and the Flutter SDK) to an external volume:
**`/Volumes/External/developer/Medbills`** and
**`/Volumes/External/developer/flutter-3.47.4`**. It's APFS — code signing
works fine there — but:
- **The external drive has to be plugged in** for any of this to work.
- The first build after the move needed a real (if slow) cache rebuild —
  cached SPM/git objects in `build/ios|macos/SourcePackages` had stale
  absolute paths baked in (`/Users/aryansingh/developer/...` instead of the
  new path). If you ever move the project again, expect the same: either
  `flutter clean` (slow, re-downloads everything) or the faster targeted fix
  — `rm -rf build/macos/SourcePackages build/macos/Build` (or the `ios`
  equivalent) then rebuild, which keeps Dart/pub caches warm.
- **Turn off Spotlight indexing on a freshly-attached external drive**
  before building (`mdutil -i off /Volumes/External`) — it competes hard for
  I/O with Xcode on a USB connection and made one build take over an hour.
- `macos/Runner/Configs/Local.xcconfig` (this Mac's real signing identity,
  gitignored) survived the move fine — filesystem moves aren't git
  operations, so untracked files come along.

## What the owner wants

A pharmacy (medical store, Madhya Pradesh) billing + stock app that works
"perfectly everywhere":
- **Windows laptop / Mac** — big-screen counter app (`.exe` installer for Windows).
- **iPhone (XR now, iPhone 17 for the brother)** — phone app, used in the shop
  **without cables**; installing should be "just press Install".
- All devices share one live store database (Firebase project `medbills-176df`).
- The web page (claude.ai artifact `VjMM6vXGRdGic36XngpUL4`) is only a demo.
- Scanning should be "smart" — one entry point that figures out whether it's
  looking at a barcode, a medicine pack, or a supplier bill, rather than
  making the user pick a mode first. Text reading is on-device only (owner's
  choice: no AI service — not Gemini, not a cloud OCR API — for patient-data
  privacy; this was re-confirmed this session when asked).
- Wireless phone → counter scanning should feel instant and alive: visible
  send/receive confirmation, not a silent write.
- Udhaar (credit sales) is **not used by this store** — hidden by default,
  not deleted.
- The owner follows the blueprint's 12 rules (see README "Rules the code follows").

## State (all done, all pushed)

- App: Flutter 3.47.4, Riverpod, Firebase (Auth + Firestore). 91 widget/unit
  tests pass, `flutter analyze` clean (run `cd scripts && dart pub get` once first).
- Firestore security rules are proven against the emulator, not just read
  through — `firestore_rules_test/` replays every write
  `FirestorePharmacyRepository` makes, as owner / pharmacist / counterStaff,
  plus cross-store isolation, deactivated accounts, and the scan-undo rule
  below — 64/64 pass (`cd firestore_rules_test && npm install && npm test`).

### Smart Scan (this session's main feature work)
- One camera screen replaces the old four separate scan cards (scan into
  bill / read a pack / scan a supplier bill / check a medicine). A barcode
  goes straight to the bill (or the chosen counter); a capture button reads
  anything without a barcode and `lib/domain/services/capture_classifier.dart`
  decides pack vs. supplier bill from the OCR text, so nobody picks a mode
  first.
- **Found and fixed a real parsing bug** using the owner's own supplier bill
  (Bhagwati Pharma Sales) as a test case: the parser only looked for a batch
  code near the expiry date and only read quantities from after it — a
  different (and equally real) bill layout puts the batch right after the
  item name with the price columns in between, which produced **zero lines
  read** on the owner's actual bill. Fixed in `supplier_bill_parser.dart`,
  with the owner's real bill layout now a permanent regression test.
- Phone → counter scanning now animates both ends: the sender shows
  "Sending to `<counter>`…" then a checkmark burst + haptic on confirm (or a
  shake + red on failure), respecting iOS/macOS "Reduce Motion". A slow send
  (2.5 s+) shows "Waiting for internet…" instead of looking stuck — this
  app's writes queue locally and send themselves once back online, so a slow
  send almost always means exactly that. The receiving counter shows each
  scan arriving as an animated card stack, not a plain snackbar.
- **3-second Undo** after every send to a counter. Cancelling updates the
  scanEvent to `cancelled`; the counter reverses exactly what that one scan
  added (`CartNotifier.removeUnits`), even if it already applied it, without
  touching anything added since. Needed a small `firestore.rules` change:
  only the original sender may move a scanEvent to `cancelled`, and may do
  so even after the counter marked it `done`.
- On Mac/Windows (no on-device OCR — ML Kit is phone-only), the capture
  button now offers camera **or** "Choose a file" (same picker Purchases
  already used), so a bill photo already on the computer can be attached
  without a webcam. True OS-level drag-and-drop onto the window was **not**
  added (would need a new `desktop_drop`-style dependency) — still open.

### Udhaar — hidden, not deleted
- A prior commit in this session deleted Udhaar entirely; this was wrong —
  it's now a `udhaarEnabled` flag on `StoreProfile` (Settings → "Udhaar
  accounts", owner-only, **off by default**). The nav tab, payment chip and
  credit-customer picker only appear once turned on; the code and any
  existing customer/ledger data were never removed. This store doesn't use
  it, so it stays off.
- UPI's label was briefly changed to "UPI · Razorpay" earlier this session;
  reverted — nothing is wired to Razorpay, so the label shouldn't suggest it
  is. Real integration would need the owner's Razorpay account/API keys,
  which haven't been requested or provided.

### Inventory
- Each stock batch now shows when it was **received** (not just when it
  expires), and managers see its margin next to the cost. A medicine's own
  detail screen lists its recent sales (units/revenue/cost/profit for
  managers), each tappable to the full invoice — not just the store-wide
  figures in Reports. The Stock nav icon carries a badge with the
  low+out-of-stock count.

### Builds / CI
- Mac app runs for real on this Mac, signed with the owner's free Apple
  Developer team (`Z9MZ6L5GMS`), installed at `/Applications/MedBills.app`.
  (Screen was locked when this session finished verifying it — process was
  confirmed alive and crash-free via `ps`/crash-log check, but **re-open it
  and look** before trusting that further.)
- iPhone XR: rebuilt and reinstalled from the new external-drive path;
  needs the one-time post-install trust tap again (Settings → General → VPN
  & Device Management → Trust) — this was pending when the session ended
  (the phone needed the owner to tap it and the Mac's screen had locked).
  **Check whether that trust tap happened and the app actually opens.**
- GitHub Actions / the `latest-build` release were last confirmed green at
  commit `15488fe` (before this session's Smart Scan/Udhaar-toggle work) —
  **not re-confirmed since**; the branch has moved substantially. Check CI
  on the latest commit before assuming the release download links are
  current.
- `.github/workflows/ios-testflight.yml`: needs `APPLE_TEAM_ID`,
  `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`,
  `APP_STORE_CONNECT_KEY` repo secrets (paid Apple Developer account). Not yet run.
- Live Firestore: `stores/store_primary`, 92 medicines, owner sign-in
  `yash@gmail.com` (password given to the owner directly in chat, never in
  the repo).

## What the owner asked for that is NOT done yet

A very large combined feature spec arrived mid-session (phrased as lettered
sections A–I). Given everything else already in flight, only part of it
landed — here's the honest split:

- **Done**: the Smart Scan classifier + animations + undo (B/E above),
  hiding Udhaar behind a toggle (G), the desktop file-picker half of C.
  **A** — the phone now remembers its last-used counter across restarts
  (`ScanTargetMemory`, shared_preferences) and shows "Counter offline"
  instead of silently falling back to this device's own bill when that
  remembered counter isn't listening; a "Not delivered" card on the Scan
  tab lists scans no counter picked up within 10 minutes.
  **D** — added a widget test (`test/presentation/scan_queue_test.dart`)
  that proves a remote scan lands on a counter's cart immediately even
  while a quantity-picker dialog is open there — not dropped or delayed.
  Writing it caught two real bugs, now fixed: `_askCounterName` was
  disposing its `TextEditingController` via the dialog's pop future
  (which resolves before the exit transition finishes, while the field
  is still on screen) — it's now its own `StatefulWidget` that disposes
  in its own `dispose()`. And `BillingScreen.dispose()` called
  `ref.read()` to stop an active station, which throws once Riverpod has
  already marked the widget's `ref` disposed — it now reads the repo
  from a field captured when the station started. Per-action
  who/device attribution (`ScanEvent.createdBy/createdByName/
  deviceLabel`, same on `SaleInvoice`/`PurchaseRecord`/`BillScan`/audit
  entries) and the `firestore.rules` role split (counter staff can scan
  and capture bill photos; only owner/pharmacist can receive stock or
  link barcodes) were re-checked and are already correct — no changes
  needed there.
  **B** (remainder) — the phone's Smart Scan now has a Selling/Receiving
  switch (`ScanModeToggle`). Selling is unchanged. Receiving: each
  photographed pack merges into one running draft purchase
  (`receivingDraftProvider`/`ReceivingDraftNotifier`, keyed by medicine +
  batch) instead of going straight onto a customer's bill; "Review &
  receive" saves it as a normal `BillScan` and opens the same
  `BillReviewScreen` a photographed supplier bill uses, so pricing and
  final receipt still need a pharmacist/owner — nothing is stock until
  then. Scope note: only the camera-capture path (pack-label OCR) feeds
  the draft; a plain barcode scan in Receiving mode still behaves as a
  sale, since most Indian OTC packs' barcodes carry no batch/expiry to
  receive against — `Gs1Parser` already reads batch/expiry off the GS1
  DataMatrix ones, so wiring barcode scans into receiving too is a
  reasonable next step, just not done here.
  Also added: a warning (`bill_scan_screen.dart`'s `_receive()`) before
  receiving a bill whose supplier + invoice number already matches an
  existing `PurchaseRecord` from a *different* scan — catches the same
  paper bill being photographed/received twice; the pharmacist can
  still proceed, it's a warning, not a lock.
  `capture_classifier.dart` renamed to the requested
  `smart_scan_classifier.dart`, with its own test file
  (`test/domain/smart_scan_classifier_test.dart`) — there were no
  dedicated tests for it before despite the earlier note here, only
  inline coverage of the other parsers in `scan_parsers_test.dart`.
  **E** (remainder) — the bill list itself now animates: a new line
  (`_CartRowAnimator` in `billing_screen.dart`) fades and slides in on
  its first appearance (its widget key is only ever fresh once, so this
  naturally fires exactly once per line, not on every rebuild); editing
  an existing line's quantity afterwards pulses it with a brief
  highlight instead of silently updating. The Payable total, both on
  the phone's checkout bar and the full checkout panel, now eases to
  its new value (`CountUpAmount` in `widgets/common.dart`) instead of
  jumping. This is on top of the animated arrival toast that already
  existed — that's unchanged.
  **C** (remainder) — a supplier bill photo can now be dragged straight
  onto the Purchases window on Mac/Windows (`desktop_drop` package,
  `SupplierBillDropZone` in `bill_scan_screen.dart`, wrapping
  `purchases_screen.dart`'s body), with a highlighted drop overlay while
  dragging over it and a rejection message for a non-image file. Reuses
  `receiveBillPhoto` exactly as "Choose a file" already did, so it goes
  through the same OCR/review pipeline — only the entry point is new.
  No macOS entitlement changes were needed; drag-and-drop is already
  covered by the existing `com.apple.security.files.user-selected.read-write`
  sandbox entitlement. Does nothing on a phone (no OS drag source to
  drop from there) — `DeviceFeatures.isPhone` gates it off.
  **F** — every one of the 123 Material icon usages across 20 files is now
  a Phosphor icon, one weight ("Regular") throughout, no mixed styles and
  no Apple SF Symbols. Hit a real blocker partway through: the obvious
  package, `phosphor_flutter` (pub.dev's "latest" is still 2.1.0), doesn't
  compile on this Flutter SDK — `PhosphorIconData extends IconData`, and
  Flutter made `IconData` a `final` class, so it fails with "The class
  'IconData' can't be extended outside of its library". `flutter analyze`
  didn't catch this; only `flutter test`'s full compile did — worth
  remembering next time a new dependency is added here. Switched to
  `phosphoricons_flutter` (a maintained fork built for exactly this;
  same `PhosphorIconsRegular.xxx` API, verified every icon name used here
  exists in it before swapping), which compiles clean. Also added
  `visualDensity: VisualDensity.adaptivePlatformDensity` to the theme —
  standard (full touch targets) on phone, denser lists/controls on
  Mac/Windows, with no per-screen changes needed since Material widgets
  read it from the theme automatically. Trimmed the most verbose
  instructional subtitle text on the Scan screen (Smart Scan, USB/Bluetooth
  scanner, the receiving-draft helper) down to the essentials.
  **What's honestly incomplete**: the text trim only covered the Scan
  screen, not an exhaustive pass over every screen's helper/subtitle
  copy. The Mac app couldn't be visually confirmed live in this
  environment (a real `flutter build macos` succeeded, but the launched
  process showed no window here) — the owner did confirm the icons on
  the real iPhone look right (screenshot, Billing screen), which is the
  automated suite plus one real device, not a Mac glance.

  **Bill-reading, post-F**: the owner reported the bill reader
  "isn't understanding what's written" and asked for more medicines,
  a smarter read, and full edit power when a medicine isn't known yet.
  What was already there, confirmed working: an unmatched line already
  gets a clearly-flagged "(not matched)" row with a search field that
  offers "New medicine" (full editor: generic, manufacturer, HSN, GST,
  schedule, pack size) right there, and receiving stock from it works
  the same as any other line. What was actually wrong: a *weak* match —
  the matcher's best guess, but below its own confidence bar, or with a
  close second candidate — was auto-filled as if it were certain, with
  no flag at all. Fixed: only a confident match auto-fills now; anything
  weaker is treated like an unmatched line (same warning styling, guess
  kept as the search starting point) rather than silently shown as
  settled. Catalogue expanded 163 → 210. On Mac (no on-device OCR by the
  owner's own standing choice — no cloud OCR for patient-data privacy),
  the messaging after a bill capture and the empty-lines state used to
  read like something had failed; reworded to lead with what actually
  works there (type the line, search or add new) instead of apologizing
  for a phone not being used.

  **Send bill to a counter ("send to PC")**: the owner flagged that a
  pack photographed on the phone always landed on the phone's own bill
  even when a counter was chosen as the scan target — only raw barcode
  scans respected that choice. Fixed (`_sendOrAddToBill` in
  `scan_billing.dart`, shared by both paths now). Also added: a "Send
  this bill to a counter" button on the phone's Billing app bar
  (desktop icon, phone-only, shown when the cart has lines and a
  counter is online) that sends the *entire* built-up bill — exact
  quantities per line, not one pack at a time — and clears the phone's
  own bill once sent. Needed a new `ScanEvent.units` field (null = one
  pack, as a physical scan always was; set = an exact quantity) and
  `addScannedToBill`'s new `requestedUnits` parameter, capped at what's
  actually free. The owner's stated intent: the phone is mainly a
  capture device (scan, photograph a bill, photograph a pack) and the
  PC is where everything gets finished — this is a step toward that,
  not the whole of it.
- **Not done**:
  - **H** — correctly left undone on purpose (Razorpay/UPI QR, separate
    per-person logins, Excel export/backups) — the owner said to wait.
  - A dedicated picker UI for choosing *which* counter to send the bill
    to when more than one is online exists (a plain list dialog) but
    hasn't been seen live — only exercised by a test with a single
    counter, since only one was ever registered in this session.

## Next steps (in order)

1. **Confirm the iPhone XR actually launched** — the trust tap and launch
   verification were still pending when this session ended.
2. **Re-open the Mac app and look at it** — it was verified alive via the
   process list only; the screen was locked, so nothing was seen on screen.
3. **Live-sync + phone→counter tests** with the real devices, now including
   the new Smart Scan animations and Undo — ask the owner to actually watch
   a scan arrive and try cancelling one within 3 seconds.
4. **Re-confirm GitHub Actions is green** on the current commit (not just
   the older one above) before trusting the release download links.
5. **Windows**: download `MedBills-Setup.exe` from the release once (4) is
   confirmed, install on the brother's laptop, sign in, confirm live sync.
6. **iPhone 17 (brother):** see "Brother's setup" below — unchanged from
   before, still needs the owner's Apple Developer Program purchase.
7. Whichever of the "not done yet" list above the owner still wants —
   confirm priority before starting; it's a lot of further work on top of
   an already long session.
8. Owner tasks: fill store details in Settings (GSTIN, drug licence, address);
   rotate the Firebase service-account key shared in chat in an earlier
   session if that hasn't been done yet.

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
  another machine (each Mac that wants real signing needs its own).
- Do not touch the `users/{uid}` Firebase Auth/Firestore accounts, deploy
  Firestore rules, or request a fresh service-account key without being
  asked — the owner was explicit about this across multiple sessions.
- On a freshly-attached external drive: `mdutil -i off <volume>` before a
  big build, or Spotlight will fight Xcode for I/O.
