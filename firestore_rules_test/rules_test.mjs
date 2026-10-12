// Replays every write MedBillsRepository makes (lib/data/firestore_pharmacy_repository.dart)
// against firestore.rules in the Firestore emulator, as owner / pharmacist /
// counterStaff, plus a few cross-store and inactive-account checks.
//
// Run with: npm test (wraps this in `firebase emulators:exec`).
import { readFileSync } from 'node:fs';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import {
  doc, setDoc, updateDoc, getDoc, collection, Timestamp,
} from 'firebase/firestore';

const STORE = 'store_primary';
const OTHER_STORE = 'store_other';

let failures = 0;
let passed = 0;

async function check(name, fn) {
  try {
    await fn();
    passed++;
    console.log(`  ok  ${name}`);
  } catch (e) {
    failures++;
    console.error(`FAIL  ${name}\n      ${e.message.split('\n')[0]}`);
  }
}

const testEnv = await initializeTestEnvironment({
  projectId: 'medbills-176df',
  firestore: {
    rules: readFileSync('../firestore.rules', 'utf8'),
    host: '127.0.0.1',
    port: 8080,
  },
});

// ---- seed fixtures with rules disabled ----
await testEnv.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();
  await setDoc(doc(db, 'users/owner-uid'), { storeId: STORE, role: 'owner', active: true, name: 'Store Owner' });
  await setDoc(doc(db, 'users/pharm-uid'), { storeId: STORE, role: 'pharmacist', active: true, name: 'Pharmacist' });
  await setDoc(doc(db, 'users/counter-uid'), { storeId: STORE, role: 'counterStaff', active: true, name: 'Counter' });
  await setDoc(doc(db, 'users/inactive-uid'), { storeId: STORE, role: 'counterStaff', active: false, name: 'Fired' });
  await setDoc(doc(db, 'users/other-store-uid'), { storeId: OTHER_STORE, role: 'owner', active: true, name: 'Other' });

  await setDoc(doc(db, `stores/${STORE}`), {
    storeId: STORE, name: 'MedBills Pharmacy', addressLine: '', city: '', state: 'Madhya Pradesh',
    phone: '', gstin: '', drugLicenseNumbers: '',
  });
  await setDoc(doc(db, `stores/${OTHER_STORE}`), { storeId: OTHER_STORE, name: 'Other Store' });

  await setDoc(doc(db, `stores/${STORE}/medicines/med-1`), {
    id: 'med-1', storeId: STORE, catalogueId: 'cat-1', name: 'Dolo 650', genericName: 'Paracetamol',
    manufacturer: 'Micro Labs', type: 'Tablet', packSizeLabel: '15', unitsPerPack: 15,
    hsnCode: '3004', gstRate: 12, scheduleType: 'none', barcode: '8901234567890',
    minStock: 10, shelfLocation: '', updatedAt: Timestamp.now(),
  });

  await setDoc(doc(db, `stores/${STORE}/batches/batch-1`), {
    id: 'batch-1', storeId: STORE, medicineId: 'med-1', batchNumber: 'B100',
    expiryDate: Timestamp.now(), purchasePricePaise: 1000, mrpPaise: 1500,
    quantity: 10, isBlocked: false, createdAt: Timestamp.now(),
  });

  await setDoc(doc(db, `stores/${STORE}/sales/sale-1`), {
    id: 'sale-1', storeId: STORE, invoiceNumber: 'INV/2026-27/0001', createdAt: Timestamp.now(),
    createdBy: 'counter-uid', createdByName: 'Counter', customerName: 'Walk-in Customer', customerPhone: '',
    customerId: null, paymentMode: 'cash', lines: [], slabs: [], grossPaise: 100, taxablePaise: 0,
    gstPaise: 0, payablePaise: 100, prescription: null, status: 'completed',
    cancellationReason: null, cancelledAt: null, cancelledByName: null,
  });

  await setDoc(doc(db, `stores/${STORE}/customers/cust-1`), {
    id: 'cust-1', storeId: STORE, name: 'Ramesh', phoneNumber: '9000000000',
    creditLimitPaise: 500000, outstandingBalancePaise: 0, createdAt: Timestamp.now(),
  });

  await setDoc(doc(db, `stores/${STORE}/counters/2026-27`), { storeId: STORE, next: 5 });

  await setDoc(doc(db, `stores/${STORE}/billScans/scan-1`), {
    id: 'scan-1', storeId: STORE, createdAt: Timestamp.now(), createdBy: 'counter-uid',
    createdByName: 'Counter', status: 'draft', draft: { lines: [] }, ocrText: '', hasImage: false,
    receivedLines: 0, receivedAt: null, receivedByName: null,
  });

  await setDoc(doc(db, `stores/${STORE}/stations/station-1`), {
    id: 'station-1', storeId: STORE, name: 'Counter 1', active: true, uid: 'owner-uid', updatedAt: Timestamp.now(),
  });
});

const owner = testEnv.authenticatedContext('owner-uid').firestore();
const pharm = testEnv.authenticatedContext('pharm-uid').firestore();
const counter = testEnv.authenticatedContext('counter-uid').firestore();
const inactive = testEnv.authenticatedContext('inactive-uid').firestore();
const otherStoreOwner = testEnv.authenticatedContext('other-store-uid').firestore();
const anon = testEnv.unauthenticatedContext().firestore();

console.log('\n--- users/{uid} ---');
await check('owner reads own profile', () => assertSucceeds(getDoc(doc(owner, 'users/owner-uid'))));
await check('owner cannot read another profile', () => assertFails(getDoc(doc(owner, 'users/pharm-uid'))));
await check('nobody can write a profile (even owner)', () =>
  assertFails(setDoc(doc(owner, 'users/owner-uid'), { storeId: STORE, role: 'owner', active: true, name: 'x' })));

console.log('\n--- stores/{storeId} ---');
await check('member can read the store', () => assertSucceeds(getDoc(doc(counter, `stores/${STORE}`))));
await check('non-member cannot read the store', () => assertFails(getDoc(doc(otherStoreOwner, `stores/${STORE}`))));
await check('inactive account cannot read the store', () => assertFails(getDoc(doc(inactive, `stores/${STORE}`))));
await check('anonymous cannot read the store', () => assertFails(getDoc(doc(anon, `stores/${STORE}`))));
await check('owner can update store details', () =>
  assertSucceeds(updateDoc(doc(owner, `stores/${STORE}`), { phone: '9876543210' })));
await check('pharmacist cannot update store details', () =>
  assertFails(updateDoc(doc(pharm, `stores/${STORE}`), { phone: '111' })));
await check('counterStaff cannot update store details', () =>
  assertFails(updateDoc(doc(counter, `stores/${STORE}`), { phone: '111' })));
await check('owner cannot change the storeId field', () =>
  assertFails(updateDoc(doc(owner, `stores/${STORE}`), { storeId: OTHER_STORE })));

console.log('\n--- counters/{fy} (invoice serial) ---');
await check('first-ever counter doc: any member can create it at next=2', () =>
  assertSucceeds(setDoc(doc(counter, `stores/${STORE}/counters/2027-28`), { storeId: STORE, next: 2 })));
await check('creating a counter doc that does not start at 2 fails', () =>
  assertFails(setDoc(doc(counter, `stores/${STORE}/counters/2028-29`), { storeId: STORE, next: 5 })));
await check('counter advances by exactly one', () =>
  assertSucceeds(updateDoc(doc(counter, `stores/${STORE}/counters/2026-27`), { next: 6 })));
await check('counter cannot skip a number', () =>
  assertFails(updateDoc(doc(pharm, `stores/${STORE}/counters/2026-27`), { next: 6 + 5 })));

console.log('\n--- medicines ---');
const newMed = {
  id: 'med-2', storeId: STORE, catalogueId: 'cat-2', name: 'Crocin', genericName: 'Paracetamol',
  manufacturer: 'GSK', type: 'Tablet', packSizeLabel: '15', unitsPerPack: 15, hsnCode: '3004',
  gstRate: 12, scheduleType: 'none', barcode: '8901111111111', minStock: 10, shelfLocation: '',
  updatedAt: Timestamp.now(),
};
await check('pharmacist can add a medicine', () => assertSucceeds(setDoc(doc(pharm, `stores/${STORE}/medicines/med-2`), newMed)));
await check('owner can edit a medicine', () =>
  assertSucceeds(updateDoc(doc(owner, `stores/${STORE}/medicines/med-1`), { minStock: 20 })));
await check('counterStaff cannot add a medicine', () =>
  assertFails(setDoc(doc(counter, `stores/${STORE}/medicines/med-3`), { ...newMed, id: 'med-3' })));
await check('counterStaff cannot edit a medicine', () =>
  assertFails(updateDoc(doc(counter, `stores/${STORE}/medicines/med-1`), { minStock: 1 })));
await check('editing a medicine cannot change its storeId', () =>
  assertFails(updateDoc(doc(owner, `stores/${STORE}/medicines/med-1`), { storeId: OTHER_STORE })));
await check('medicines are never deleted', () =>
  assertFails((async () => { const { deleteDoc } = await import('firebase/firestore'); return deleteDoc(doc(owner, `stores/${STORE}/medicines/med-1`)); })()));

console.log('\n--- batches (stock) ---');
await check('pharmacist can receive stock (create a batch)', () =>
  assertSucceeds(setDoc(doc(pharm, `stores/${STORE}/batches/batch-2`), {
    id: 'batch-2', storeId: STORE, medicineId: 'med-1', batchNumber: 'B200', expiryDate: Timestamp.now(),
    purchasePricePaise: 900, mrpPaise: 1400, quantity: 50, isBlocked: false, createdAt: Timestamp.now(),
  })));
await check('counterStaff cannot create a batch (cannot add stock)', () =>
  assertFails(setDoc(doc(counter, `stores/${STORE}/batches/batch-3`), {
    id: 'batch-3', storeId: STORE, medicineId: 'med-1', batchNumber: 'B300', expiryDate: Timestamp.now(),
    purchasePricePaise: 900, mrpPaise: 1400, quantity: 5, isBlocked: false, createdAt: Timestamp.now(),
  })));
await check('a batch cannot be created with negative quantity', () =>
  assertFails(setDoc(doc(pharm, `stores/${STORE}/batches/batch-4`), {
    id: 'batch-4', storeId: STORE, medicineId: 'med-1', batchNumber: 'B400', expiryDate: Timestamp.now(),
    purchasePricePaise: 900, mrpPaise: 1400, quantity: -1, isBlocked: false, createdAt: Timestamp.now(),
  })));
await check('counterStaff selling decreases batch quantity', () =>
  assertSucceeds(updateDoc(doc(counter, `stores/${STORE}/batches/batch-1`), { quantity: 9 })));
await check('counterStaff cannot increase batch quantity', () =>
  assertFails(updateDoc(doc(counter, `stores/${STORE}/batches/batch-1`), { quantity: 11 })));
await check('counterStaff cannot touch another field on a batch', () =>
  assertFails(updateDoc(doc(counter, `stores/${STORE}/batches/batch-1`), { quantity: 8, isBlocked: true })));
await check('manager (pharmacist) can increase batch quantity (stock-in correction)', () =>
  assertSucceeds(updateDoc(doc(pharm, `stores/${STORE}/batches/batch-1`), { quantity: 20 })));
await check('manager can block a batch', () =>
  assertSucceeds(updateDoc(doc(owner, `stores/${STORE}/batches/batch-1`), { isBlocked: true })));

console.log('\n--- sales (billing) ---');
const saleBase = {
  storeId: STORE, invoiceNumber: 'INV/2026-27/0099', createdAt: Timestamp.now(), createdByName: 'Counter',
  customerName: 'Walk-in Customer', customerPhone: '', customerId: null, paymentMode: 'cash', lines: [],
  slabs: [], grossPaise: 100, taxablePaise: 0, gstPaise: 0, payablePaise: 100, prescription: null,
  status: 'completed', cancellationReason: null, cancelledAt: null, cancelledByName: null,
};
await check('counterStaff can complete a sale as themselves', () =>
  assertSucceeds(setDoc(doc(counter, `stores/${STORE}/sales/sale-2`), { ...saleBase, id: 'sale-2', createdBy: 'counter-uid' })));
await check('cannot create a sale claiming to be someone else', () =>
  assertFails(setDoc(doc(counter, `stores/${STORE}/sales/sale-3`), { ...saleBase, id: 'sale-3', createdBy: 'owner-uid' })));
await check('cannot create a sale that is not completed', () =>
  assertFails(setDoc(doc(counter, `stores/${STORE}/sales/sale-4`), { ...saleBase, id: 'sale-4', createdBy: 'counter-uid', status: 'cancelled' })));
await check('manager can cancel a completed sale with a reason', () =>
  assertSucceeds(updateDoc(doc(pharm, `stores/${STORE}/sales/sale-1`), {
    status: 'cancelled', cancellationReason: 'Customer returned it', cancelledAt: Timestamp.now(),
    cancelledBy: 'pharm-uid', cancelledByName: 'Pharmacist',
  })));
await check('counterStaff cannot cancel a sale', () =>
  assertFails(updateDoc(doc(counter, `stores/${STORE}/sales/sale-2`), {
    status: 'cancelled', cancellationReason: 'test', cancelledAt: Timestamp.now(),
    cancelledBy: 'counter-uid', cancelledByName: 'Counter',
  })));
await check('cancelling without a reason fails', () =>
  assertFails(updateDoc(doc(owner, `stores/${STORE}/sales/sale-2`), {
    status: 'cancelled', cancellationReason: '', cancelledAt: Timestamp.now(),
    cancelledBy: 'owner-uid', cancelledByName: 'Owner',
  })));
await check('sales are never deleted', () =>
  assertFails((async () => { const { deleteDoc } = await import('firebase/firestore'); return deleteDoc(doc(owner, `stores/${STORE}/sales/sale-1`)); })()));

console.log('\n--- purchases ---');
await check('pharmacist can log a purchase for themselves', () =>
  assertSucceeds(setDoc(doc(pharm, `stores/${STORE}/purchases/purch-1`), {
    id: 'purch-1', storeId: STORE, medicineId: 'med-1', medicineName: 'Dolo 650', batchId: 'batch-1',
    batchNumber: 'B100', expiryDate: Timestamp.now(), unitsPerPack: 15, quantity: 50, freeQuantity: 0,
    purchasePricePaise: 900, mrpPaise: 1400, totalCostPaise: 45000, supplierName: 'ABC Distributors',
    supplierInvoiceNumber: 'SUP-1', billScanId: null, createdAt: Timestamp.now(), createdBy: 'pharm-uid',
    createdByName: 'Pharmacist',
  })));
await check('counterStaff cannot log a purchase', () =>
  assertFails(setDoc(doc(counter, `stores/${STORE}/purchases/purch-2`), {
    id: 'purch-2', storeId: STORE, medicineId: 'med-1', medicineName: 'Dolo 650', batchId: 'batch-1',
    batchNumber: 'B100', expiryDate: Timestamp.now(), unitsPerPack: 15, quantity: 50, freeQuantity: 0,
    purchasePricePaise: 900, mrpPaise: 1400, totalCostPaise: 45000, supplierName: 'ABC Distributors',
    supplierInvoiceNumber: 'SUP-2', billScanId: null, createdAt: Timestamp.now(), createdBy: 'counter-uid',
    createdByName: 'Counter',
  })));
await check('purchases are never edited or deleted', () =>
  assertFails(updateDoc(doc(owner, `stores/${STORE}/purchases/purch-1`), { quantity: 999 })));

console.log('\n--- customers / udhaar ledger ---');
await check('counterStaff can create a customer', () =>
  assertSucceeds(setDoc(doc(counter, `stores/${STORE}/customers/cust-2`), {
    id: 'cust-2', storeId: STORE, name: 'Suresh', phoneNumber: '9111111111',
    creditLimitPaise: 0, outstandingBalancePaise: 0, createdAt: Timestamp.now(),
  })));
await check('any member can update a customer (e.g. credit limit)', () =>
  assertSucceeds(updateDoc(doc(pharm, `stores/${STORE}/customers/cust-1`), { creditLimitPaise: 1000000 })));
await check('a ledger entry must be attributed to the writer', () =>
  assertFails(setDoc(doc(counter, `stores/${STORE}/customers/cust-1/ledger/entry-1`), {
    id: 'entry-1', storeId: STORE, customerId: 'cust-1', type: 'paymentReceived', amountPaise: 500,
    invoiceNumber: null, notes: '', timestamp: Timestamp.now(), createdBy: 'owner-uid', createdByName: 'Owner',
  })));
await check('a correctly attributed ledger entry succeeds', () =>
  assertSucceeds(setDoc(doc(counter, `stores/${STORE}/customers/cust-1/ledger/entry-2`), {
    id: 'entry-2', storeId: STORE, customerId: 'cust-1', type: 'paymentReceived', amountPaise: 500,
    invoiceNumber: null, notes: '', timestamp: Timestamp.now(), createdBy: 'counter-uid', createdByName: 'Counter',
  })));
await check('ledger entries are never edited', () =>
  assertFails(updateDoc(doc(owner, `stores/${STORE}/customers/cust-1/ledger/entry-2`), { amountPaise: 1 })));

console.log('\n--- photographed supplier bills ---');
await check('counterStaff can capture a bill photo draft', () =>
  assertSucceeds(setDoc(doc(counter, `stores/${STORE}/billScans/scan-2`), {
    id: 'scan-2', storeId: STORE, createdAt: Timestamp.now(), createdBy: 'counter-uid', createdByName: 'Counter',
    status: 'draft', draft: { lines: [] }, ocrText: '', hasImage: false, receivedLines: 0, receivedAt: null, receivedByName: null,
  })));
await check('the creator can edit their own draft', () =>
  assertSucceeds(updateDoc(doc(counter, `stores/${STORE}/billScans/scan-1`), { draft: { lines: [{ rawText: 'x' }] } })));
await check('a non-creator, non-manager cannot touch someone else’s draft', () =>
  assertFails(updateDoc(doc(pharm === counter ? counter : counter, `stores/${STORE}/billScans/scan-1`), { ocrText: 'hack' })));
await check('counterStaff (creator) cannot mark their own bill received', () =>
  assertFails(updateDoc(doc(counter, `stores/${STORE}/billScans/scan-1`), { status: 'received', receivedLines: 1, receivedAt: Timestamp.now(), receivedByName: 'Counter' })));
await check('a manager can mark a bill received', () =>
  assertSucceeds(updateDoc(doc(pharm, `stores/${STORE}/billScans/scan-1`), { status: 'received', receivedLines: 1, receivedAt: Timestamp.now(), receivedByName: 'Pharmacist' })));

console.log('\n--- stations / phone-to-counter scanning ---');
await check('any member can register their device as a station', () =>
  assertSucceeds(setDoc(doc(counter, `stores/${STORE}/stations/station-2`), {
    id: 'station-2', storeId: STORE, name: 'Counter 2', active: true, uid: 'counter-uid', updatedAt: Timestamp.now(),
  })));
await check('cannot register a station claiming someone else’s uid', () =>
  assertFails(setDoc(doc(counter, `stores/${STORE}/stations/station-3`), {
    id: 'station-3', storeId: STORE, name: 'Counter 3', active: true, uid: 'owner-uid', updatedAt: Timestamp.now(),
  })));
await check('any member can send its heartbeat (even if they did not create it)', () =>
  assertSucceeds(updateDoc(doc(pharm, `stores/${STORE}/stations/station-1`), { updatedAt: Timestamp.now() })));
await check('a phone can send a scan event to a station', () =>
  assertSucceeds(setDoc(doc(counter, `stores/${STORE}/scanEvents/evt-1`), {
    id: 'evt-1', storeId: STORE, stationId: 'station-1', rawBarcode: '8901234567890', medicineId: null,
    batchNumber: null, deviceLabel: 'iPhone', createdBy: 'counter-uid', createdByName: 'Counter',
    scannedAt: Timestamp.now(), status: 'pending',
  })));
await check('the counter can mark a scan event done', () =>
  assertSucceeds(updateDoc(doc(owner, `stores/${STORE}/scanEvents/evt-1`), { status: 'done' })));

console.log('\n--- audit log ---');
await check('any member can write an audit entry for themselves', () =>
  assertSucceeds(setDoc(doc(pharm, `stores/${STORE}/auditLog/audit-1`), {
    storeId: STORE, action: 'medicine_saved', refId: 'med-1', details: 'test', uid: 'pharm-uid',
    userName: 'Pharmacist', timestamp: Timestamp.now(),
  })));
await check('owner can read the audit log', () => assertSucceeds(getDoc(doc(owner, `stores/${STORE}/auditLog/audit-1`))));
await check('pharmacist cannot read the audit log', () => assertFails(getDoc(doc(pharm, `stores/${STORE}/auditLog/audit-1`))));
await check('counterStaff cannot read the audit log', () => assertFails(getDoc(doc(counter, `stores/${STORE}/auditLog/audit-1`))));

console.log('\n--- cross-store isolation & inactive accounts ---');
await check('a different store’s owner cannot read this store’s medicines', () =>
  assertFails(getDoc(doc(otherStoreOwner, `stores/${STORE}/medicines/med-1`))));
await check('a different store’s owner cannot write into this store', () =>
  assertFails(setDoc(doc(otherStoreOwner, `stores/${STORE}/customers/cust-x`), {
    id: 'cust-x', storeId: STORE, name: 'x', phoneNumber: '', creditLimitPaise: 0, outstandingBalancePaise: 0, createdAt: Timestamp.now(),
  })));
await check('a deactivated account cannot read anything in the store', () =>
  assertFails(getDoc(doc(inactive, `stores/${STORE}/medicines/med-1`))));
await check('an unauthenticated client cannot read anything', () =>
  assertFails(getDoc(doc(anon, `stores/${STORE}/medicines/med-1`))));

await testEnv.cleanup();

console.log(`\n${passed} passed, ${failures} failed`);
if (failures > 0) process.exit(1);
