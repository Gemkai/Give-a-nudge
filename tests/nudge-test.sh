#!/usr/bin/env bash
# Give a Nudge — smoke test
# Usage: bash give-a-nudge/tests/nudge-test.sh

PASS=0; FAIL=0; SKIP=0

pass()  { echo -e "[PASS] $1"; (( PASS++ )); }
fail()  { echo -e "[FAIL] $1"; (( FAIL++ )); }
skip()  { echo -e "[SKIP] $1"; (( SKIP++ )); }

check_file() {
  local label="$1" path="$2"
  if [[ -f "$path" ]]; then pass "$label exists"
  else                       fail "$label missing: $path"; fi
}

# Helper to count items in a JSON array or check key existence
# Uses jq if available, falls back to python.
json_count() {
  local file="$1"
  local key="$2" # e.g. .nudges

  if command -v jq &>/dev/null; then
    jq "$key | length" "$file" 2>/dev/null || echo 0
    return
  fi

  local py_cmd
  if   command -v python3 &>/dev/null; then py_cmd="python3"
  elif command -v python  &>/dev/null; then py_cmd="python"
  else echo 0; return; fi

  $py_cmd -c "import json, sys; d=json.load(open(sys.argv[1])); k=sys.argv[2].strip('.'); print(len(d.get(k, [])))" "$file" "$key" 2>/dev/null || echo 0
}

echo "Give a Nudge — smoke test"
echo "========================="

# ── 1. Dependency check ──────────────────────────────────────────────────────
HAS_JSON=false
if command -v jq &>/dev/null; then
  pass "jq available"
  HAS_JSON=true
elif command -v python3 &>/dev/null || command -v python &>/dev/null; then
  pass "python available (jq fallback)"
  HAS_JSON=true
else
  fail "neither jq nor python found — JSON tests will fail"
fi

# ── 2 & 3. Per-environment checks ────────────────────────────────────────────
# Support Windows HOME if run in a bash shell (e.g. Git Bash)
MY_HOME="${HOME:-$USERPROFILE}"
# Convert Windows path to Unix-style for bash if it contains backslashes
[[ "$MY_HOME" == *"\\"* ]] && MY_HOME="$(echo "/$MY_HOME" | sed 's/\\/\//g' | sed 's/://')"

for env in claude gemini; do
  case "$env" in
    claude) HOOKS_DIR="$MY_HOME/.claude/hooks"; STATE_PATH="$MY_HOME/.claude/nudge-state.json" ;;
    gemini) HOOKS_DIR="$MY_HOME/.gemini/hooks"; STATE_PATH="$MY_HOME/.gemini/nudge-state.json" ;;
  esac
  LABEL="${env^} CLI"

  PARENT_DIR="${HOOKS_DIR%/hooks}"
  if [[ ! -d "$PARENT_DIR" ]]; then
    skip "$LABEL hooks not installed (${PARENT_DIR} absent)"
    continue
  fi

  check_file "~/${env}/hooks/nudge-runner.sh"    "$HOOKS_DIR/nudge-runner.sh"
  check_file "~/${env}/hooks/on-session-start.sh" "$HOOKS_DIR/on-session-start.sh"
  check_file "~/${env}/hooks/on-tool-use.sh"     "$HOOKS_DIR/on-tool-use.sh"
  check_file "~/${env}/hooks/on-stop.sh"         "$HOOKS_DIR/on-stop.sh"
  check_file "~/${env}/hooks/notify-linux.sh"    "$HOOKS_DIR/notify-linux.sh"
  check_file "~/${env}/hooks/notify-mac.sh"      "$HOOKS_DIR/notify-mac.sh"
  check_file "~/${env}/hooks/notify-windows.ps1" "$HOOKS_DIR/notify-windows.ps1"

  NUDGES_FILE=""
  if   [[ -f "$PARENT_DIR/nudges.json" ]]; then NUDGES_FILE="$PARENT_DIR/nudges.json"
  elif [[ -f "$PARENT_DIR/nudge.json"  ]]; then NUDGES_FILE="$PARENT_DIR/nudge.json"; fi

  if [[ -z "$NUDGES_FILE" ]]; then
    fail "~/${env}/nudges.json missing"
  else
    NUDGE_COUNT=$(json_count "$NUDGES_FILE" ".nudges")
    if [[ "$NUDGE_COUNT" -gt 0 ]]; then
      pass "~/${env}/nudges.json exists (${NUDGE_COUNT} nudges)"
    else
      fail "~/${env}/nudges.json has 0 nudges or is malformed"
    fi
  fi

  # Smoke test the runner (dry run)
  if [[ -f "$HOOKS_DIR/on-tool-use.sh" ]]; then
    TOOL_PAYLOAD='{"tool_name":"Write","tool_input":{"file_path":"/tmp/nudge-test-probe.txt"}}'
    STATE_FILE=/tmp/nudge-test-state.json \
      bash "$HOOKS_DIR/on-tool-use.sh" <<< "$TOOL_PAYLOAD" &>/dev/null
    if [[ $? -eq 0 ]]; then pass "runner exits 0 on tool_use event ($LABEL)"
    else                     fail "runner non-zero exit on tool_use event ($LABEL)"; fi
  fi
done

echo "========================="
echo "${PASS} passed, ${FAIL} failed, ${SKIP} skipped"

# Cleanup
rm -f /tmp/nudge-test-state.json /tmp/nudge-test-probe.txt

[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
