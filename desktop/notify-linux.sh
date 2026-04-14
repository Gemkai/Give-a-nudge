#!/usr/bin/env bash
# Give a Nudge — Linux notification (opt-in for desktop app users)
# Requires: libnotify (sudo apt install libnotify-bin OR sudo dnf install libnotify)
# Enable: set NUDGE_DESKTOP_NOTIFY=true in your shell profile
MESSAGE="${1:-Give a Nudge}"
notify-send "Give a Nudge" "$MESSAGE" --expire-time=5000 &>/dev/null &
exit 0
