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

## Fixing a date or price after stock is received

Stock → the medicine → the **pencil** on its batch. Change the expiry
(month/year), the received date, the MRP or the cost, then **Save**. Owner
and pharmacist only. The quantity can't be changed here, bills already made
keep their prices, and every change is recorded (who, old → new).

While reviewing a supplier bill, the bill date and every line's expiry can
be edited before the stock is received. A finished sale's date can't be
changed (it's the GST invoice date): cancel it with a reason, which puts the
stock back, and bill again.

## Selling cheaper, discount, return

- **One medicine cheaper:** tap its amount on the bill (the small pencil),
  pick −5% / −10% or type the price or the line total. It can never go
  above MRP. On the PC you can also double-click the name.
- **Discount on the whole bill:** "Add discount" above Payable, ₹ or %.
- The bill and its history show MRP, the discount and what was charged.
  GST is worked out on the amount actually charged.
- **Return:** Bills → the bill → **Return** → how many came back → Cash /
  UPI / Udhaar reduced. The stock goes back, the refund counts on that
  day's figures, and the bill shows "Returned". A bill with a return can't
  be cancelled; return the rest instead.

## Stock count and stock value

Stock → the medicine → tap the stock on a batch (e.g. **23 × 60**). Type
the packs counted (and loose tablets), or tap − / +, or **Empty this
batch**. Choose a reason. Owner and pharmacist only, and each change is
recorded. The green box at the top of Stock is the total stock value, at
purchase rate and at MRP.

## Purchases: cash or udhaar, distributors, payments

- Receiving stock: pick the distributor (names come up as you type, the
  same list on every device), bill no., bill date, and **Cash (paid)** or
  **Udhaar (credit)**. Paid packs can be 4.5.
- **Purchase & Payment** tab (PC: "Payments" on the left; phone: More):
  - Udhaar owed, today's purchases (cash and udhaar separately), paid today.
  - **To pay** list: bills due in 3 days or late, with a **Pay** button.
  - **Add → Old bill (udhaar):** bills from before, so reminders work.
  - **Add → Payment:** to whom, how much, Cash / UPI / Bank / Cheque, for
    which bill, date.
  - Tap any bill or payment to change it, or **Remove** it (it stays on
    record as removed).
- **Reports** is the Profit & Loss: sales by cash / UPI / udhaar (chart),
  money in vs paid out (plus or minus), day by day, then three tables:
  1 Sales, 2 Purchase & Payment (what was bought, from whom, bill no.,
  payments), 3 Total.

## The bill: format, sign and seal, WhatsApp

Settings → **Bill look** → add the logo, signature and seal (mohar) photos
(sign on white paper, clear photo). Settings → store details → email, bank
details, terms. Every A4 bill then prints like the estimate format with
the sign and seal above "Authorized Signatory".

Bill → **WhatsApp** → "Send bill as PDF" or "Send bill as photo".
On the phone the share sheet opens: pick WhatsApp and the chat. On the PC
the file is saved in Downloads → "MedBills bills" and the customer's chat
opens: drag the file into it.

## First time, owner only

1. Settings → **Update medicines** → **Update all**. This updates GST to 5%,
   the Schedule H1 corrections, and syrups / drops / creams that were
   counted as "× 60" (their ml) to 1 per bottle, keeping the same number of
   bottles in stock. Past bills are not changed.
2. **Publish the new database rules** (needed for Purchase & Payment and
   returns, once): open https://console.firebase.google.com → project
   **medbills-176df** → Firestore Database → **Rules**. Replace everything
   with the contents of `firestore.rules` from
   https://github.com/Framework7000/Medbills/blob/claude/medbills-repo-t8ueeh/firestore.rules
   and press **Publish**. Until then, stock still goes in, but supplier
   bills, payments and returns are refused.
