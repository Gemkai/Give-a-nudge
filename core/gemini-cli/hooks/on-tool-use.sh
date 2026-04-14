#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="${SCRIPT_DIR}/nudge-runner.sh"
PAYLOAD=$(cat 2>/dev/null || true)
if command -v timeout &>/dev/null; then
  printf '%s\n' "$PAYLOAD" | timeout 0.5 bash "$RUNNER" tool_use 2>/dev/null || true
else
  printf '%s\n' "$PAYLOAD" | bash "$RUNNER" tool_use 2>/dev/null || true
fi
exit 0
