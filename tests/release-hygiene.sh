#!/usr/bin/env bash
# Release hygiene checks for public-safe repository contents.
# Usage: bash tests/release-hygiene.sh

set -u

PASS=0
FAIL=0

pass() { echo "[PASS] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

scan_pattern() {
  local pattern="$1"
  local label="$2"
  local output_file
  output_file="$(mktemp)"

  if grep -RInE --binary-files=without-match --exclude-dir=.git --exclude=release-hygiene.sh "$pattern" "$ROOT_DIR" >"$output_file"; then
    fail "$label"
    cat "$output_file"
  else
    pass "$label"
  fi

  rm -f "$output_file"
}

echo "Give a Nudge - release hygiene"
echo "=============================="

scan_pattern \
  '[A-Za-z0-9._%+-]+@(gmail\.com|outlook\.com|yahoo\.com|icloud\.com|proton(mail)?\.com)\b' \
  "no personal email addresses in repo"

scan_pattern \
  'C:\\Users\\[^\\]+|/Users/[^/]+|/home/[^/]+' \
  "no absolute user-home paths committed"

scan_pattern \
  'gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9]{20,}|AIza[0-9A-Za-z\-_]{35}|AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]+PRIVATE KEY-----|ssh-rsa|ssh-ed25519|Bearer [A-Za-z0-9._-]{20,}|(mongodb(\+srv)?|postgres(ql)?|mysql|amqp):\/\/[^[:space:]]+:[^[:space:]]+@' \
  "no committed secret-looking material"

scan_pattern \
  'https://github\.com/your-org/' \
  "no placeholder repository URL left behind"

echo "=============================="
echo "$PASS passed, $FAIL failed"

[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
