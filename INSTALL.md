# Install MedBills in the shop

Everything downloads from one page:
**https://github.com/Framework7000/Medbills/releases/tag/latest-build**

All devices share the same online store database. Install, sign in, and
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

## iPhone (the scanner), free Apple ID, renews itself

Apple stops apps installed with a free Apple ID after 7 days. AltStore
renews MedBills automatically over the shop Wi-Fi while the laptop is on,
so nobody has to plug the phone in every week.

One-time setup on the shop Windows laptop (about 15 minutes):
1. Install **iTunes** and **iCloud** from apple.com (not the Microsoft
   Store versions), then **AltServer** from altstore.io.
2. Connect the iPhone by cable and unlock it. Tap **Trust** on the phone.
3. In the AltServer icon (bottom-right of the taskbar), choose
   **Install AltStore → your iPhone** and sign in with your Apple ID.
4. On the iPhone, go to Settings → General → VPN & Device Management →
   your Apple ID → **Trust**. Also turn on Settings → Privacy & Security →
   **Developer Mode** (the phone restarts).
5. In iTunes, tick **"Sync with this iPhone over Wi-Fi"** for the iPhone.
6. On the iPhone, download **MedBills-iOS-unsigned.ipa** from the page
   above, open it with **AltStore** (Share → AltStore), and wait for it to
   install.

After that, keep AltServer running on the laptop (it starts with Windows)
and the iPhone on the same Wi-Fi. AltStore renews MedBills by itself.
If the laptop was off for a whole week, open AltStore on the iPhone and tap
**Refresh All**. Bills and stock are never lost, because they live in the
online database, not on the phone.

## First time, owner only

Settings → **Update medicines** → **Update all**. This updates GST to 5% and
the Schedule H1 corrections. Past bills are not changed.
