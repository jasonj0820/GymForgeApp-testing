#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -project MoneyPilot.xcodeproj -scheme MoneyPilot -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
sim_id=$(xcrun simctl list devices available -j | python3 -c 'import sys,json; ds=json.load(sys.stdin)["devices"]; print(next(d["udid"] for group in ds.values() for d in group if d["name"].startswith("iPhone")))')
xcodebuild -project MoneyPilot.xcodeproj -scheme MoneyPilot -destination "platform=iOS Simulator,id=$sim_id" CODE_SIGNING_ALLOWED=NO test
