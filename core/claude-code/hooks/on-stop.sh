#!/usr/bin/env bash
# on-stop.sh — Thin Claude Code hook for the Stop event.
# Synchronous hook: runner writes nudges to stdout; do NOT mark async: true.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="${SCRIPT_DIR}/nudge-runner.sh"

# Capture stdin fully before handing off to the runner.
PAYLOAD=$(cat 2>/dev/null || true)

if command -v timeout &>/dev/null; then
  printf '%s\n' "$PAYLOAD" | timeout 0.5 bash "$RUNNER" stop 2>/dev/null || true
else
  printf '%s\n' "$PAYLOAD" | bash "$RUNNER" stop 2>/dev/null || true
fi

exit 0
