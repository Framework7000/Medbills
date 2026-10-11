#!/usr/bin/env bash
# Prepares a fresh clone of MedBills (Nuskha PMS): fetches dependencies for
# the app and the scripts/ tools, installs CocoaPods on a Mac, and prints
# how to run each platform.
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

echo "== Fetching app dependencies =="
flutter pub get
echo

echo "== Fetching scripts/ (Firebase setup tools) dependencies =="
(cd scripts && dart pub get)
echo

if [[ "$(uname)" == "Darwin" ]] && command -v pod >/dev/null 2>&1; then
  echo "== Installing CocoaPods for iPhone and Mac =="
  (cd ios && pod install)
  (cd macos && pod install)
  echo
fi

cat <<'DONE'
Setup complete.

  Windows:  flutter run -d windows        (needs Visual Studio 2022, C++ desktop)
  Mac:      flutter run -d macos          (needs Xcode; pick a signing Team once)
  iPhone:   flutter run -d <your iPhone>  (Xcode -> ios/Runner.xcworkspace -> Signing)
  Android:  flutter run -d <your phone>
  Demo web: flutter run -d chrome         (sample data only)

  Checks:   flutter analyze && flutter test

The apps connect to the store's Firebase project (lib/firebase_options.dart).
Sign in with a staff account. See README.md for adding staff.
DONE
