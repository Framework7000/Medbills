# Install MedBills in the shop

Everything downloads from one page:
**https://github.com/Framework7000/Medbills/releases/tag/latest-build**

All devices share the same online store database. The Windows laptop is
the counter; an Android phone is the scanner. Install, sign in, and
they show the same bills and stock. No cables are needed after setup.

## Windows laptop (the main counter app)

1. Download **MedBills-Setup.exe** and double-click it.
2. If a blue box says "Windows protected your PC", click **More info → Run anyway**.
   This happens only once. The installer isn't code-signed, so Windows asks.
3. Press **Install**. A **MedBills** icon appears on the desktop.
4. Open it and sign in with the shop account.

No admin password, no code, nothing else to install. Every build is checked
automatically on a clean Windows computer, 5 rounds of install → open →
uninstall, before it appears on the download page.

## Android phone (the scanner)

1. On the phone, open this link in Chrome:
   https://github.com/Framework7000/Medbills/releases/download/latest-build/MedBills-Android.apk
2. Tap **Download**, then open the file. If Android asks, allow
   **Install unknown apps** for Chrome, then tap **Install**.
3. Open MedBills, allow the **camera**, and sign in with the shop login.

It never expires and needs no cable or computer. To update, open the same
link and install again over the old one. Data stays, because it lives online.

**Using it:** MedBills opens straight into the camera.
- Any barcode, QR or DataMatrix on a medicine, or the QR on a supplier
  bill, is read the moment it's in view.
- For a medicine pack or a whole supplier bill without a code, press the
  round button.
- The chip at the top shows where scans go ("To Windows PC counter"). It
  picks the shop computer by itself when that's the only one open. Tap it
  to switch between Selling and Receiving.
- Medicines appear on the Windows bill at once. A supplier bill pops up on
  Windows with a **Review** button.

The Windows computer receives phone scans whenever MedBills is open on it.
Nothing needs switching on.

(An iPhone also works, but with a free Apple ID it must be renewed every
7 days: see AltStore at altstore.io. Android has no such limit.)

## First time, owner only

Settings → **Update medicines** → **Update all**. This updates GST to 5% and
the Schedule H1 corrections. Past bills are not changed.
