#!/usr/bin/env bash
# Give a Nudge — macOS notification (opt-in for desktop app users)
# Requires: macOS with osascript (built-in, no install needed)
# Enable: set NUDGE_DESKTOP_NOTIFY=true in your shell profile
#
# Security: message is passed as an AppleScript argv argument — never
# interpolated into the script string — preventing osascript injection.
osascript - "${1:-Give a Nudge}" <<'APPLESCRIPT' &>/dev/null &
on run argv
  set msg to item 1 of argv
  display notification msg with title "Give a Nudge"
end run
APPLESCRIPT
exit 0
