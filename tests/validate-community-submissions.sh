#!/usr/bin/env bash
# Validate community catalog submissions.
# Usage: bash tests/validate-community-submissions.sh

set -euo pipefail

if command -v python3 >/dev/null 2>&1; then
  exec python3 tests/validate-community-submissions.py
fi

if command -v python >/dev/null 2>&1; then
  exec python tests/validate-community-submissions.py
fi

echo "[FAIL] python or python3 is required to validate community submissions" >&2
exit 1
