#!/bin/zsh
# Rebuilds Splitday with YOUR Xcode Personal Team and installs it straight onto your iPhone.
# Nothing re-signs it afterwards, so Apple Health keeps working, and running this every few days
# means the free 7-day signature never runs out (Scripts/schedule_refresh.sh sets that up).
#
#   zsh Scripts/auto_install.sh "Jason's iPhone"      (the name shown by: xcrun devicectl list devices)
#
# Needs: Xcode signed in to your Apple ID (Xcode → Settings → Accounts), and the iPhone plugged in
# or on the same Wi-Fi with "Connect via network" ticked in Xcode → Window → Devices and Simulators.
set -euo pipefail
cd "$(dirname "$0")/.."
# A new build number every build, so iOS re-reads the widget list (new widgets show up without a restart).
BUILD_NUMBER="$(date +%Y%m%d%H%M)"

DEVICE="${1:-${SPLITDAY_DEVICE:-}}"
if [[ -z "$DEVICE" ]]; then
  echo "Which iPhone? Run again with its name in quotes, e.g. zsh Scripts/auto_install.sh \"Jason's iPhone\"" >&2
  xcrun devicectl list devices >&2 || true
  exit 1
fi

echo "$(date): building Splitday…"
DD="build/auto"
xcodebuild \
  -project GymForge.xcodeproj \
  -scheme GymForge \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DD" \
  -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  build -quiet

APP="$DD/Build/Products/Release-iphoneos/GymForge.app"
[[ -d "$APP" ]] || { echo "Build finished but $APP is missing" >&2; exit 1; }

echo "$(date): installing on $DEVICE…"
# Installing over the existing app keeps all your data (same bundle ID, same team).
xcrun devicectl device install app --device "$DEVICE" "$APP"
echo "$(date): done ✓ (signed for another 7 days)"
