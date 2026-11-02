#!/usr/bin/env bash
# Installs MedBills on the running Android emulator, opens it, checks it is
# still running after 25 s (with a screenshot), uninstalls it — 5 times.
set -euo pipefail
APK="$1"
PKG=com.medbills.nuskha_pms
mkdir -p android-screenshots
for i in 1 2 3 4 5; do
  echo "=== Round $i of 5 ==="
  adb install -r -g "$APK" >/dev/null
  adb shell pm list packages | grep -q "$PKG" || { echo "Round $i: not installed"; exit 1; }
  adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  sleep 25
  PID=$(adb shell pidof "$PKG" | tr -d '\r' || true)
  if [ -z "$PID" ]; then
    echo "Round $i: MedBills closed by itself"
    adb logcat -d -t 200 | grep -iE "AndroidRuntime|FATAL|flutter" || true
    exit 1
  fi
  adb exec-out screencap -p > "android-screenshots/round-$i.png"
  MEM=$(adb shell dumpsys meminfo "$PKG" | grep -m1 "TOTAL" | awk '{print $2}' | tr -d '\r' || true)
  echo "Round $i: running after 25 s (pid $PID, memory ${MEM:-?} KB)"
  adb shell am force-stop "$PKG"
  adb uninstall "$PKG" >/dev/null
  if adb shell pm list packages | grep -q "$PKG"; then echo "Round $i: uninstall failed"; exit 1; fi
  echo "Round $i: OK"
done
echo "All 5 rounds passed."
