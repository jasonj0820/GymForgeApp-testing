#!/bin/zsh
# Runs Scripts/auto_install.sh automatically every Monday and Thursday at 12:30, so Splitday is
# re-signed well before its 7 days run out. If the Mac is asleep then, it runs when it wakes.
#
#   zsh Scripts/schedule_refresh.sh "Jason's iPhone"     → turn on
#   zsh Scripts/schedule_refresh.sh --off                → turn off
#
# Log: ~/Library/Logs/Splitday/refresh.log
set -euo pipefail
cd "$(dirname "$0")/.."

LABEL="com.jason.splitday.refresh"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/Splitday"

launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
if [[ "${1:-}" == "--off" ]]; then
  rm -f "$PLIST"
  echo "Auto-refresh turned off."
  exit 0
fi

DEVICE="${1:?Usage: zsh Scripts/schedule_refresh.sh \"Jason's iPhone\"  (name from: xcrun devicectl list devices)}"
mkdir -p "$HOME/Library/LaunchAgents" "$LOG_DIR"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>$PWD/Scripts/auto_install.sh</string>
    <string>$DEVICE</string>
  </array>
  <key>StartCalendarInterval</key>
  <array>
    <dict><key>Weekday</key><integer>1</integer><key>Hour</key><integer>12</integer><key>Minute</key><integer>30</integer></dict>
    <dict><key>Weekday</key><integer>4</integer><key>Hour</key><integer>12</integer><key>Minute</key><integer>30</integer></dict>
  </array>
  <key>StandardOutPath</key><string>$LOG_DIR/refresh.log</string>
  <key>StandardErrorPath</key><string>$LOG_DIR/refresh.log</string>
</dict>
</plist>
EOF

plutil -lint "$PLIST" >/dev/null
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Auto-refresh on: Mondays and Thursdays at 12:30 for $DEVICE."
echo "Log: $LOG_DIR/refresh.log  ·  Turn off: zsh Scripts/schedule_refresh.sh --off"
