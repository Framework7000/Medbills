# Medicine catalogue — plan, sources, rules

Goal: every medicine sold in India is searchable in MedBills by any name it
goes by (brand, generic or old British name, short form or misspelling), with
schedule, GST, HSN, pack and reference MRP filled in. Owner's request,
Oct 2026.

## The truth about "official"

No government body publishes a complete list of Indian **brands**, so the
catalogue combines two kinds of data:

| Layer | Source | Official? |
| --- | --- | --- |
| Schedule H1 / X / H (who needs a prescription and a register) | Drugs Rules, 1945, as amended (CDSCO) | Yes |
| GST rate | GST Council 56th meeting, rates from 22-09-2025 (CBIC Notifications 9 and 10/2025-CT(Rate)) | Yes |
| Generic products with MRP | Jan Aushadhi (PMBI) product list | Yes |
| ~2.5 lakh brand products: name, maker, pack, composition, price | Kaggle "A-Z Medicine Dataset of India" (prices Nov 2022) | No. Compiled from an online pharmacy; check its licence before shipping it |

Schedule and GST for **every** product are worked out per salt from the
official lists. The brand data contributes only names, makers, packs and
compositions. A reference MRP is just a hint; the real MRP always comes from
the batch received (Rule 1).

## Two errors found in the current catalogue (fix first)

1. **GST:** 204 of 210 medicines are at 12%, but medicines have been at 5%
   since 22-09-2025. Customer prices don't change (MRP includes GST), but
   the GST printed on bills and in reports is wrong. Exceptions: insulin and
   ORS are already 5%. Dettol and Savlon are at 18%; confirm their rate from
   a purchase bill.
2. **Schedule H1 mislabelled as H:** these are H1 by law (GSR 588(E)), so
   they need patient and doctor details recorded:
   - med_066 Monocef (ceftriaxone)
   - med_067 Taxim-O, med_068 Mahacef and med_105 Zifi (cefixime)
   - med_069 Gudcef (cefpodoxime)
   - med_102 Levoflox (levofloxacin)
   - med_039 and med_196, the moxifloxacin eye drops

   Clonazepam and pregabalin are already H1. Pregabalin becomes H1 by law
   around 16-11-2026 (GSR 377(E)); stricter now is lawful.

The live store's medicine documents carry the old values too, so they need
an in-app correction (see the task list).

## Files

```
catalogue/reference/
  schedule_h1.csv           46 entries of GSR 588(E) + pregabalin (#51). Serials 47–50: copy from the official consolidated text.
  schedule_x.csv            Schedule X salts.
  schedule_extra_strict.csv shop policy: stricter than the law (clonazepam → H1).
  schedule_h.csv            TO CREATE: every Schedule H entry, one salt per row, from the official Drugs Rules text.
  salt_aliases.csv          the same salt under different names (paracetamol = acetaminophen = PCM, frusemide = furosemide, …).
  nil_rated_drugs.csv       0% GST drugs. 3 known; fill the rest verbatim from the CBIC notification.
  gst_rules.csv             rate rules and how sure each one is.
catalogue/sources/          downloaded raw files (git-ignored).
scripts/catalogue/build_catalogue.py   builds assets/catalogue/catalogue.json.gz (+ catalogue_report.txt)
```

Classification rules in the builder (`--selftest` checks them):
- The strictest salt wins: X > H1 > H > OTC.
- **OTC only when** every salt is resolved, none is on a schedule list, the
  salt appears in at least 3 products, and it isn't one or two letters away
  from a scheduled salt (a likely typo). Anything else is **UNKNOWN**, which
  can't be sold until the pharmacist sets it (Rule 11). Without
  `schedule_h.csv`, nothing becomes OTC.
- GST is 5%, or 0% only if every salt is on the nil list. HSN: 300410 for
  penicillins, 300420 for other antibiotics, 300490 for everything else.
- Discontinued products are dropped; duplicates (same name + maker + pack)
  are merged.
- Tested on 250k rows: about 1 min, 5.8 MB gzipped.

## Where to download (open them on a normal internet connection)

- Kaggle A-Z dataset: https://www.kaggle.com/datasets/shudhanshusingh/az-medicine-dataset-of-india
  (note the licence shown on the page).
- Jan Aushadhi product list: https://janaushadhi.gov.in/ProductList.aspx
  (export or copy the full table: Drug Code, Generic Name, Unit Size, MRP, Group Name).
- Drugs Rules, 1945 (Schedules H, H1, X): https://cdsco.gov.in/opencms/en/Acts-and-rules/Drugs-Rules/
  - H1 cross-check: https://drugscontrol.py.gov.in/sites/default/files/2023-03/Schedule-H1-1.pdf
- GST rates (Chapter 30, nil list): https://cbic-gst.gov.in/gst-goods-services-rates.html
  (Notifications 9/2025 and 10/2025-Central Tax (Rate)).
- Optional extras: NLEM 2022 and the NPPA ceiling prices (nppa.gov.in) give
  official price caps for scheduled formulations.

## Rules for the app

- Ship the catalogue as an app asset. **Never** write the 2.5 lakh entries to
  Firestore (cost, and the free tier allows 20k writes a day). A medicine
  becomes a store document only when it is first stocked, as today
  (`catalogueId`).
- The 210 hand-checked entries stay and win over imported ones with the
  same name and maker.
- Past sales are never changed. Corrections apply to future sales only.
