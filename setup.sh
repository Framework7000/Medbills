#!/usr/bin/env bash
# Resumes MedBills (Nuskha PMS) on a fresh local clone — generates the
# gitignored platform runner folders, fetches dependencies for both the
# app and the scripts/ CLI tools, and prints what to do next.
#
# Usage (after cloning and checking out claude/medbills-repo-t8ueeh):
#   ./setup.sh

set -euo pipefail

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK not found on PATH."
  echo "Install it first: https://docs.flutter.dev/get-started/install"
  exit 1
fi

echo "== Flutter version =="
flutter --version
echo

echo "== Generating platform runner folders (android/ios/windows/macos/web) =="
flutter create --platforms=windows,web,android,macos .
echo

echo "== Fetching app dependencies =="
flutter pub get
echo

echo "== Fetching scripts/ (Firestore seed CLI) dependencies =="
(cd scripts && dart pub get)
echo

cat <<'EOF'
Setup complete.

Next steps:

  Run the app:
    flutter run -d chrome     # or -d windows / -d macos / an Android device

  Verify everything still passes:
    flutter analyze
    flutter test

  This repo's lib/firebase_options.dart already points at a real,
  seeded Firebase project (medbills-176df). Desktop/mobile builds connect
  to it automatically. Web builds are opt-in — see the "Firebase project"
  section in README.md for why — enable with:
    flutter run -d chrome --dart-define=ENABLE_FIREBASE_WEB=true

  To re-seed or reset that project's Firestore data (or point at your own
  project instead), see scripts/README.md — you'll need a service account
  key from Firebase Console → Project Settings → Service Accounts →
  Generate new private key. Never commit that key file to this repo.
EOF
