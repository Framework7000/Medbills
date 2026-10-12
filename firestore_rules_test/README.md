# Firestore rules emulator test

Replays every write `FirestorePharmacyRepository` makes
(`lib/data/firestore_pharmacy_repository.dart`) against `../firestore.rules`
in the real Firestore emulator, authenticated as owner / pharmacist /
counterStaff — plus cross-store isolation and deactivated-account checks.

## Run it

Needs Node.js and a JDK (the emulator runs on the JVM).

```
cd firestore_rules_test
npm install
npm test
```

Expect `NN passed, 0 failed`. A failure means the app and the rules have
drifted apart — either the rule is too strict for something the app
legitimately does, or too loose for something it shouldn't be able to do.
