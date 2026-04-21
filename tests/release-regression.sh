#!/usr/bin/env bash
# Release regression tests for Give a Nudge.
# Usage: bash tests/release-regression.sh

set -u

PASS=0
FAIL=0

pass() { echo "[PASS] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

json_get() {
  local file="$1"
  local expr="$2"

  local py_cmd=""
  if command -v python3 >/dev/null 2>&1; then
    py_cmd="python3"
  elif command -v python >/dev/null 2>&1; then
    py_cmd="python"
  fi

  [[ -z "$py_cmd" ]] && return 1

  "$py_cmd" - "$file" "$expr" <<'PY'
import json
import sys

path = sys.argv[1]
expr = sys.argv[2]

with open(path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

if expr == "last_fired_count":
    print(len(data.get("last_fired", {})))
elif expr == "session_tool_count":
    print(data.get("session_tool_count", 0))
elif expr.startswith("last_fired_has:"):
    key = expr.split(":", 1)[1]
    print("true" if key in data.get("last_fired", {}) else "false")
elif expr.startswith("last_fired_value:"):
    key = expr.split(":", 1)[1]
    print(data.get("last_fired", {}).get(key, ""))
else:
    raise SystemExit(f"unsupported expr: {expr}")
PY
}

assert_eq() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$label"
  else
    fail "$label (expected '$expected', got '$actual')"
  fi
}

assert_file_exists() {
  local path="$1"
  local label="$2"
  if [[ -f "$path" ]]; then
    pass "$label"
  else
    fail "$label (missing: $path)"
  fi
}

assert_file_missing() {
  local path="$1"
  local label="$2"
  if [[ ! -e "$path" ]]; then
    pass "$label"
  else
    fail "$label (unexpected path: $path)"
  fi
}

assert_file_contains() {
  local path="$1"
  local needle="$2"
  local label="$3"
  if grep -Fq "$needle" "$path"; then
    pass "$label"
  else
    fail "$label (missing '$needle' in $path)"
  fi
}

copy_runner_fixture() {
  local env_name="$1"
  local dest_root="$2"
  mkdir -p "$dest_root/hooks"
  cp "core/${env_name}/hooks/nudge-runner.sh" "$dest_root/hooks/"
  cp "core/${env_name}/hooks/on-tool-use.sh" "$dest_root/hooks/"
  cp "core/${env_name}/hooks/on-session-start.sh" "$dest_root/hooks/"
  cp "core/${env_name}/hooks/on-stop.sh" "$dest_root/hooks/"
  cp "core/${env_name}/nudges.json" "$dest_root/nudges.json"
}

test_no_false_positive_tool_use() {
  local env_name="$1"
  local tmp_root
  tmp_root="$(mktemp -d)"
  copy_runner_fixture "$env_name" "$tmp_root"

  local state="$tmp_root/state.json"
  printf '{}\n' | STATE_FILE="$state" bash "$tmp_root/hooks/nudge-runner.sh" tool_use >/dev/null 2>&1

  assert_eq "$(json_get "$state" "last_fired_count")" "0" "$env_name: no nudge fires on empty tool payload"
  assert_eq "$(json_get "$state" "session_tool_count")" "1" "$env_name: tool counter increments once"

  rm -rf "$tmp_root"
}

test_env_edit_nudge_only() {
  local env_name="$1"
  local tmp_root
  tmp_root="$(mktemp -d)"
  copy_runner_fixture "$env_name" "$tmp_root"

  local state="$tmp_root/state.json"
  local payload='{"tool_name":"Write","tool_input":{"file_path":"/tmp/.env"}}'
  printf '%s\n' "$payload" | STATE_FILE="$state" bash "$tmp_root/hooks/nudge-runner.sh" tool_use >/dev/null 2>&1

  assert_eq "$(json_get "$state" "last_fired_count")" "1" "$env_name: only one nudge fires for .env edits"
  assert_eq "$(json_get "$state" "last_fired_has:security-env-file")" "true" "$env_name: .env edit fires security nudge"

  rm -rf "$tmp_root"
}

test_session_start_cooldown() {
  local env_name="$1"
  local tmp_root
  tmp_root="$(mktemp -d)"
  copy_runner_fixture "$env_name" "$tmp_root"

  local state="$tmp_root/state.json"
  printf '{}\n' | STATE_FILE="$state" bash "$tmp_root/hooks/nudge-runner.sh" session_start >/dev/null 2>&1
  local first_ts
  first_ts="$(json_get "$state" "last_fired_value:discovery-session-start")"

  sleep 1
  printf '{}\n' | STATE_FILE="$state" bash "$tmp_root/hooks/nudge-runner.sh" session_start >/dev/null 2>&1
  local second_ts
  second_ts="$(json_get "$state" "last_fired_value:discovery-session-start")"

  assert_eq "$second_ts" "$first_ts" "$env_name: session-start cooldown blocks immediate repeat"

  rm -rf "$tmp_root"
}

test_invalid_state_recovers() {
  local env_name="$1"
  local tmp_root
  tmp_root="$(mktemp -d)"
  copy_runner_fixture "$env_name" "$tmp_root"

  local state="$tmp_root/state.json"
  printf 'not-json\n' > "$state"
  printf '{}\n' | STATE_FILE="$state" bash "$tmp_root/hooks/nudge-runner.sh" tool_use >/dev/null 2>&1

  if command -v jq >/dev/null 2>&1; then
    if jq -e . "$state" >/dev/null 2>&1; then
      pass "$env_name: invalid state file is repaired"
    else
      fail "$env_name: invalid state file remains unreadable"
    fi
  else
    local py_cmd="python"
    if command -v python3 >/dev/null 2>&1; then
      py_cmd="python3"
    fi
    if "$py_cmd" -m json.tool "$state" >/dev/null 2>&1; then
      pass "$env_name: invalid state file is repaired"
    else
      fail "$env_name: invalid state file remains unreadable"
    fi
  fi

  rm -rf "$tmp_root"
}

test_malicious_nudge_id_does_not_execute() {
  local env_name="$1"
  local tmp_root
  tmp_root="$(mktemp -d)"
  mkdir -p "$tmp_root/hooks"
  cp "core/${env_name}/hooks/nudge-runner.sh" "$tmp_root/hooks/"

  local marker="$tmp_root/pwned"
  cat > "$tmp_root/nudges.json" <<EOF
{
  "version": "1.0",
  "environment": "${env_name}",
  "nudges": [
    {
      "id": "x'] = 1; __import__(\"pathlib\").Path(\"${marker}\").write_text(\"owned\"); data['last_fired']['x",
      "category": "security_review",
      "trigger": {
        "event": "session_start",
        "condition": ""
      },
      "cooldown_minutes": 0,
      "message": "nudge: security test",
      "environments": ["${env_name}"],
      "comment": "security regression"
    }
  ]
}
EOF

  local state="$tmp_root/state.json"
  printf '{}\n' | STATE_FILE="$state" bash "$tmp_root/hooks/nudge-runner.sh" session_start >/dev/null 2>&1

  assert_file_missing "$marker" "$env_name: malicious nudge id cannot execute code"

  rm -rf "$tmp_root"
}

test_notify_uses_installed_helper() {
  local env_name="$1"
  local tmp_root
  tmp_root="$(mktemp -d)"
  mkdir -p "$tmp_root/hooks"
  cp "core/${env_name}/hooks/nudge-runner.sh" "$tmp_root/hooks/"

  cat > "$tmp_root/nudges.json" <<'EOF'
{
  "version": "1.0",
  "environment": "test",
  "nudges": [
    {
      "id": "notify-test",
      "category": "command_discovery",
      "trigger": {
        "event": "session_start",
        "condition": ""
      },
      "cooldown_minutes": 0,
      "message": "nudge: notify test",
      "environments": ["test"],
      "comment": "notify regression"
    }
  ]
}
EOF

  local marker="$tmp_root/notified"
  case "$(uname -s)" in
    Linux*)
      cat > "$tmp_root/hooks/notify-linux.sh" <<EOF
#!/usr/bin/env bash
printf 'notified\n' > "${marker}"
EOF
      chmod +x "$tmp_root/hooks/notify-linux.sh"
      ;;
    Darwin*)
      cat > "$tmp_root/hooks/notify-mac.sh" <<EOF
#!/usr/bin/env bash
printf 'notified\n' > "${marker}"
EOF
      chmod +x "$tmp_root/hooks/notify-mac.sh"
      ;;
    MINGW*|MSYS*|CYGWIN*)
      local marker_win="$marker"
      if command -v cygpath >/dev/null 2>&1; then
        marker_win="$(cygpath -w "$marker")"
      fi
      cat > "$tmp_root/hooks/notify-windows.ps1" <<EOF
param([string]\$Message = "Give a Nudge")
Set-Content -Path "${marker_win}" -Value "notified"
EOF
      ;;
    *)
      fail "$env_name: unknown OS for desktop notify test"
      rm -rf "$tmp_root"
      return
      ;;
  esac

  local state="$tmp_root/state.json"
  printf '{}\n' | NUDGE_DESKTOP_NOTIFY=true STATE_FILE="$state" bash "$tmp_root/hooks/nudge-runner.sh" session_start >/dev/null 2>&1
  sleep 1

  assert_file_exists "$marker" "$env_name: desktop notify uses installed helper path"

  rm -rf "$tmp_root"
}

test_installer_preserves_invalid_settings() {
  local tmp_root
  tmp_root="$(mktemp -d)"
  local home_dir="$tmp_root/home"
  mkdir -p "$home_dir/.claude"
  printf '{invalid json\n' > "$home_dir/.claude/settings.json"

  if HOME="$home_dir" bash install.sh >/dev/null 2>&1; then
    pass "installer completes when Claude settings are malformed"
  else
    fail "installer should not abort on malformed Claude settings"
  fi

  assert_file_contains "$home_dir/.claude/settings.json" "{invalid json" "installer preserves malformed settings instead of clobbering them"
  assert_file_exists "$home_dir/.claude/settings.json.nudge-bak" "installer creates backup before touching malformed settings"

  rm -rf "$tmp_root"
}

test_installer_registers_claude_session_start_and_notify_helpers() {
  local tmp_root
  tmp_root="$(mktemp -d)"
  local home_dir="$tmp_root/home"
  mkdir -p "$home_dir/.claude"

  if HOME="$home_dir" bash install.sh >/dev/null 2>&1; then
    pass "installer runs for fresh Claude home"
  else
    fail "installer should succeed for fresh Claude home"
  fi

  local settings="$home_dir/.claude/settings.json"
  assert_file_contains "$settings" "on-session-start.sh" "installer registers Claude session-start hook"
  assert_file_exists "$home_dir/.claude/hooks/notify-linux.sh" "installer copies Linux desktop helper"
  assert_file_exists "$home_dir/.claude/hooks/notify-mac.sh" "installer copies macOS desktop helper"
  assert_file_exists "$home_dir/.claude/hooks/notify-windows.ps1" "installer copies Windows desktop helper"

  rm -rf "$tmp_root"
}

echo "Give a Nudge — release regression test"
echo "======================================"

for env_name in claude-code gemini-cli; do
  test_no_false_positive_tool_use "$env_name"
  test_env_edit_nudge_only "$env_name"
  test_session_start_cooldown "$env_name"
  test_invalid_state_recovers "$env_name"
  test_malicious_nudge_id_does_not_execute "$env_name"
  test_notify_uses_installed_helper "$env_name"
done

test_installer_preserves_invalid_settings
test_installer_registers_claude_session_start_and_notify_helpers

if bash tests/validate-community-submissions.sh; then
  pass "community submission validation passes"
else
  fail "community submission validation passes"
fi

if bash tests/release-hygiene.sh; then
  pass "release hygiene checks pass"
else
  fail "release hygiene checks pass"
fi

echo "======================================"
echo "$PASS passed, $FAIL failed"

[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
