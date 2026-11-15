#!/bin/zsh
# MK23: builds Splitday for the iOS Simulator and takes a picture of each screen in demo mode
# (made-up data, no permission prompts). GitHub runs this on every push; the pictures land on the
# `ci-screens` branch so a build can be looked at before it's installed.
#
#   zsh Scripts/screenshots.sh            → build/screens/*.jpg
set -uo pipefail
cd "$(dirname "$0")/.."
OUT="build/screens"
DERIVED="build/sim"
BUNDLE="com.jason.gymforge"
rm -rf "$OUT"; mkdir -p "$OUT"

# Screen names understood by DemoRoot (iOS/Views/DiagnosticsView.swift). "-end" = bottom of the page.
SCREENS=(today today-end workouts progress progress-end lift body body-end coach coach-end routine
         settings settings-you settings-training settings-sounds settings-data diagnostics whatsnew
         history nutrition recovery plan review month preview workout workout-end)

echo "Building for the simulator…"
xcodebuild -project GymForge.xcodeproj -scheme GymForge -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES ARCHS=arm64 \
  build > build/sim-build.log 2>&1
APP="$DERIVED/Build/Products/Debug-iphonesimulator/GymForge.app"
if [[ ! -d "$APP" ]]; then
  echo "Simulator build failed:" >&2
  grep -E "error:|\*\* BUILD" build/sim-build.log | head -40 >&2
  exit 1
fi

# Newest available iPhone (a Pro Max if there is one: more of each page fits).
DEVICE=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
best = None
for runtime, devices in json.load(sys.stdin)["devices"].items():
    if "iOS" not in runtime: continue
    for d in devices:
        if not d["name"].startswith("iPhone"): continue
        key = (runtime, "Pro Max" in d["name"], d["name"])
        if best is None or key > best[0]: best = (key, d["udid"], d["name"])
print(best[1] if best else "")
')
[[ -z "$DEVICE" ]] && { echo "No iPhone simulator available" >&2; exit 1; }
echo "Simulator: $DEVICE"
xcrun simctl boot "$DEVICE" 2>/dev/null
xcrun simctl bootstatus "$DEVICE" -b > /dev/null
xcrun simctl install "$DEVICE" "$APP" || exit 1
xcrun simctl status_bar "$DEVICE" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 2>/dev/null

shoot() {   # name, appearance
  xcrun simctl ui "$DEVICE" appearance "$2" 2>/dev/null
  # Australian region: weeks start on Monday and dates read day-first, as on the phone this is built for.
  xcrun simctl launch "$DEVICE" "$BUNDLE" -demo YES -screen "$1" -AppleLocale en_AU -AppleLanguages "(en-AU)" > /dev/null 2>&1 \
    || { echo "  ✗ $1 didn't launch"; return; }
  sleep 7
  local png="$OUT/$1-$2.png"
  xcrun simctl io "$DEVICE" screenshot "$png" > /dev/null 2>&1
  xcrun simctl terminate "$DEVICE" "$BUNDLE" > /dev/null 2>&1
  # Small JPEGs: the pictures are for looking at, and the branch they go to shouldn't balloon.
  if [[ -f "$png" ]]; then
    sips -Z 1500 -s format jpeg -s formatOptions 70 "$png" --out "${png%.png}.jpg" > /dev/null 2>&1 && rm -f "$png"
    echo "  ✓ $1 ($2)"
  else
    echo "  ✗ $1: no picture"
  fi
}

# The very first launch after install is slow (the first picture came out blank), so warm up once.
xcrun simctl launch "$DEVICE" "$BUNDLE" -demo YES -screen today > /dev/null 2>&1; sleep 15
xcrun simctl terminate "$DEVICE" "$BUNDLE" > /dev/null 2>&1
for screen in "${SCREENS[@]}"; do shoot "$screen" light; done
for screen in today progress lift workout; do shoot "$screen" dark; done

xcrun simctl shutdown "$DEVICE" 2>/dev/null
COUNT=$(ls "$OUT" | wc -l | tr -d ' ')
echo "Done: $COUNT pictures in $OUT"
[[ "$COUNT" -gt 0 ]]
