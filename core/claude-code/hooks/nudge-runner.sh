#!/usr/bin/env bash
# Give a Nudge — core runtime for Claude Code
# Called by hook scripts. Reads hook payload from stdin. Always exits 0.

set -o pipefail
trap 'exit 0' ERR

EVENT_TYPE="${1:-}"
APP_TYPE="claude"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NUDGES_JSON="${SCRIPT_DIR}/../nudges.json"
STATE_FILE="${STATE_FILE:-${HOME}/.${APP_TYPE}/nudge-state.json}"
LOCK_DIR="${STATE_FILE}.lockdir"
DEFAULT_STATE_JSON='{"last_fired":{},"session_tool_count":0,"session_start_time":""}'

HAS_JQ=false
if command -v jq >/dev/null 2>&1; then
  HAS_JQ=true
fi

PYTHON_BIN=""
if command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="python3"
elif command -v python >/dev/null 2>&1; then
  PYTHON_BIN="python"
fi

PAYLOAD=""
if [ ! -t 0 ]; then
  PAYLOAD=$(cat 2>/dev/null || true)
fi

[[ -z "$EVENT_TYPE" ]] && exit 0
[[ ! -f "$NUDGES_JSON" ]] && exit 0
[[ "$HAS_JQ" == false && -z "$PYTHON_BIN" ]] && exit 0

build_path_json() {
  local path_json="["
  local key
  for key in "$@"; do
    path_json="${path_json}\"${key}\","
  done
  path_json="${path_json%,}]"
  printf '%s' "$path_json"
}

json_get_text_path() {
  local json_text="$1"
  local default_value="$2"
  shift 2

  if [[ -z "$json_text" ]]; then
    printf '%s\n' "$default_value"
    return
  fi

  if [[ -n "$PYTHON_BIN" ]]; then
    "$PYTHON_BIN" - "$json_text" "$default_value" "$@" <<'PY'
import json
import sys

text = sys.argv[1]
default = sys.argv[2]
path = sys.argv[3:]

try:
    value = json.loads(text)
    for key in path:
        if isinstance(value, dict):
            value = value.get(key)
        else:
            value = None
            break

    if value is None:
        print(default)
    elif isinstance(value, bool):
        print("true" if value else "false")
    else:
        print(value)
except Exception:
    print(default)
PY
    return
  fi

  local path_json
  path_json="$(build_path_json "$@")"
  printf '%s' "$json_text" | jq -r --argjson path "$path_json" --arg default "$default_value" '
    try getpath($path) catch $default
    | if . == null then $default else . end
  ' 2>/dev/null || printf '%s\n' "$default_value"
}

json_get_file_path() {
  local json_file="$1"
  local default_value="$2"
  shift 2

  if [[ ! -f "$json_file" ]]; then
    printf '%s\n' "$default_value"
    return
  fi

  if [[ -n "$PYTHON_BIN" ]]; then
    "$PYTHON_BIN" - "$json_file" "$default_value" "$@" <<'PY'
import json
import sys

path = sys.argv[1]
default = sys.argv[2]
keys = sys.argv[3:]

try:
    with open(path, "r", encoding="utf-8") as handle:
        value = json.load(handle)

    for key in keys:
        if isinstance(value, dict):
            value = value.get(key)
        else:
            value = None
            break

    if value is None:
        print(default)
    elif isinstance(value, bool):
        print("true" if value else "false")
    else:
        print(value)
except Exception:
    print(default)
PY
    return
  fi

  local path_json
  path_json="$(build_path_json "$@")"
  jq -r --argjson path "$path_json" --arg default "$default_value" '
    try getpath($path) catch $default
    | if . == null then $default else . end
  ' "$json_file" 2>/dev/null || printf '%s\n' "$default_value"
}

json_file_is_valid() {
  local json_file="$1"
  [[ ! -f "$json_file" ]] && return 1

  if [[ -n "$PYTHON_BIN" ]]; then
    "$PYTHON_BIN" - "$json_file" <<'PY' >/dev/null 2>&1
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    json.load(handle)
PY
    return $?
  fi

  jq -e . "$json_file" >/dev/null 2>&1
}

matching_nudges_for_event() {
  local event_name="$1"

  if [[ -n "$PYTHON_BIN" ]]; then
    "$PYTHON_BIN" - "$NUDGES_JSON" "$event_name" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    data = json.load(handle)

for nudge in data.get("nudges", []):
    if nudge.get("trigger", {}).get("event") == sys.argv[2]:
        print(json.dumps(nudge, separators=(",", ":")))
PY
    return
  fi

  jq -c --arg event "$event_name" '.nudges[] | select(.trigger.event == $event)' "$NUDGES_JSON" 2>/dev/null || true
}

acquire_lock() {
  local retries=0
  while ! mkdir "$LOCK_DIR" 2>/dev/null; do
    sleep 0.1
    retries=$((retries + 1))
    [[ "$retries" -gt 50 ]] && return 1
  done
  return 0
}

release_lock() {
  rmdir "$LOCK_DIR" 2>/dev/null || true
}

with_state_lock() {
  acquire_lock || return 1
  "$@"
  local status=$?
  release_lock
  return "$status"
}

write_default_state() {
  mkdir -p "$(dirname "$STATE_FILE")"
  printf '%s\n' "$DEFAULT_STATE_JSON" > "$STATE_FILE"
}

date_to_epoch() {
  local timestamp="$1"
  date -u -d "$timestamp" +%s 2>/dev/null \
    || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$timestamp" +%s 2>/dev/null \
    || printf '0\n'
}

state_action_jq() {
  local action="$1"
  shift

  if [[ ! -f "$STATE_FILE" ]] || ! json_file_is_valid "$STATE_FILE"; then
    write_default_state
  fi

  case "$action" in
    ensure)
      printf 'ok\n'
      ;;
    prepare)
      local event_name="$1"
      local now
      now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
      local tmp
      tmp="$(mktemp "${STATE_FILE}.XXXXXX")" || return 1
      jq --arg now "$now" --arg event "$event_name" '
        .last_fired = (.last_fired // {})
        | .session_tool_count = (.session_tool_count // 0)
        | .session_start_time = (.session_start_time // "")
        | if .session_start_time == "" then .session_start_time = $now else . end
        | if $event == "tool_use" then .session_tool_count += 1 else . end
      ' "$STATE_FILE" > "$tmp" 2>/dev/null && mv "$tmp" "$STATE_FILE" || {
        rm -f "$tmp"
        return 1
      }
      printf 'ok\n'
      ;;
    get_tool_count)
      jq -r '.session_tool_count // 0' "$STATE_FILE" 2>/dev/null || printf '0\n'
      ;;
    get_session_start)
      jq -r '.session_start_time // ""' "$STATE_FILE" 2>/dev/null || printf '\n'
      ;;
    claim)
      local nudge_id="$1"
      local cooldown_minutes="$2"
      local last_fired
      last_fired="$(jq -r --arg id "$nudge_id" '.last_fired[$id] // ""' "$STATE_FILE" 2>/dev/null || printf '\n')"
      local ready=true

      if [[ "$cooldown_minutes" -gt 0 && -n "$last_fired" ]]; then
        local last_epoch
        local now_epoch
        last_epoch="$(date_to_epoch "$last_fired")"
        now_epoch="$(date -u +%s)"
        if [[ "$last_epoch" -gt 0 ]]; then
          local elapsed_minutes
          elapsed_minutes=$(((now_epoch - last_epoch) / 60))
          [[ "$elapsed_minutes" -lt "$cooldown_minutes" ]] && ready=false
        fi
      fi

      if [[ "$ready" == true ]]; then
        local now
        now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        local tmp
        tmp="$(mktemp "${STATE_FILE}.XXXXXX")" || return 1
        jq --arg id "$nudge_id" --arg ts "$now" '.last_fired[$id] = $ts' "$STATE_FILE" > "$tmp" 2>/dev/null && mv "$tmp" "$STATE_FILE" || {
          rm -f "$tmp"
          return 1
        }
        printf 'true\n'
      else
        printf 'false\n'
      fi
      ;;
  esac
}

state_action_py() {
  local action="$1"
  shift

  "$PYTHON_BIN" - "$STATE_FILE" "$action" "$@" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone

path = sys.argv[1]
action = sys.argv[2]
args = sys.argv[3:]


def default_state():
    return {"last_fired": {}, "session_tool_count": 0, "session_start_time": ""}


def load_state():
    try:
        with open(path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
        if not isinstance(data, dict):
            raise ValueError("state root must be an object")
    except Exception:
        return default_state()

    if not isinstance(data.get("last_fired"), dict):
        data["last_fired"] = {}
    try:
        data["session_tool_count"] = int(data.get("session_tool_count", 0))
    except Exception:
        data["session_tool_count"] = 0
    if not isinstance(data.get("session_start_time", ""), str):
        data["session_start_time"] = ""
    return data


def write_state(data):
    directory = os.path.dirname(path)
    if directory:
      os.makedirs(directory, exist_ok=True)

    tmp_path = f"{path}.tmp"
    with open(tmp_path, "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2)
        handle.write("\n")
    os.replace(tmp_path, path)


def utc_now():
    return datetime.now(timezone.utc)


def utc_now_iso():
    return utc_now().replace(microsecond=0).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_timestamp(value):
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(timezone.utc)
    except Exception:
        return None


data = load_state()

if action == "ensure":
    write_state(data)
    print("ok")
elif action == "prepare":
    event_name = args[0]
    if not data.get("session_start_time"):
        data["session_start_time"] = utc_now_iso()
    if event_name == "tool_use":
        data["session_tool_count"] = int(data.get("session_tool_count", 0)) + 1
    write_state(data)
    print("ok")
elif action == "get_tool_count":
    print(int(data.get("session_tool_count", 0)))
elif action == "get_session_start":
    print(data.get("session_start_time", ""))
elif action == "claim":
    nudge_id = args[0]
    cooldown_minutes = int(args[1])
    ready = True

    if cooldown_minutes > 0:
        last_fired = parse_timestamp(str(data.get("last_fired", {}).get(nudge_id, "")))
        if last_fired is not None:
            ready = (utc_now() - last_fired).total_seconds() >= cooldown_minutes * 60

    if ready:
        data.setdefault("last_fired", {})[nudge_id] = utc_now_iso()
        write_state(data)
        print("true")
    else:
        print("false")
PY
}

state_action() {
  local action="$1"
  shift

  if [[ -n "$PYTHON_BIN" ]]; then
    state_action_py "$action" "$@"
  else
    state_action_jq "$action" "$@"
  fi
}

session_minutes_since() {
  local timestamp="$1"
  [[ -z "$timestamp" ]] && {
    printf '0\n'
    return
  }

  if [[ -n "$PYTHON_BIN" ]]; then
    "$PYTHON_BIN" - "$timestamp" <<'PY'
import sys
from datetime import datetime, timezone

value = sys.argv[1]

try:
    start = datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(timezone.utc)
    now = datetime.now(timezone.utc)
    delta = now - start
    print(max(0, int(delta.total_seconds() // 60)))
except Exception:
    print(0)
PY
    return
  fi

  local start_epoch
  start_epoch="$(date_to_epoch "$timestamp")"
  [[ "$start_epoch" -eq 0 ]] && {
    printf '0\n'
    return
  }
  local now_epoch
  now_epoch="$(date -u +%s)"
  printf '%s\n' $(((now_epoch - start_epoch) / 60))
}

normalize_percentage() {
  local used_pct="$1"
  local remaining_pct="$2"

  if [[ "$used_pct" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    printf '%s\n' "${used_pct%.*}"
    return
  fi

  if [[ "$remaining_pct" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    if [[ -n "$PYTHON_BIN" ]]; then
      "$PYTHON_BIN" - "$remaining_pct" <<'PY'
import sys

remaining = float(sys.argv[1])
used = max(0, min(100, int(100 - remaining)))
print(used)
PY
      return
    fi

    local whole_remaining="${remaining_pct%.*}"
    printf '%s\n' $((100 - whole_remaining))
    return
  fi

  printf '0\n'
}

detect_file_extension() {
  local file_path="$1"
  local filename
  filename="${file_path##*/}"

  if [[ "$filename" == .* && "$filename" != *.*.* ]]; then
    printf '%s\n' "$filename"
    return
  fi

  if [[ "$filename" == *.* ]]; then
    printf '.%s\n' "${filename##*.}"
    return
  fi

  printf '\n'
}

evaluate_condition() {
  local condition="$1"
  [[ -z "$condition" ]] && {
    printf 'true\n'
    return
  }

  case "$condition" in
    "context_pct >= "*)
      local threshold="${condition#context_pct >= }"
      if [[ "$CONTEXT_PCT" =~ ^[0-9]+$ && "$threshold" =~ ^[0-9]+$ && "$CONTEXT_PCT" -ge "$threshold" ]]; then
        printf 'true\n'
      else
        printf 'false\n'
      fi
      ;;
    "session_duration_minutes >= "*)
      local threshold="${condition#session_duration_minutes >= }"
      if [[ "$SESSION_DURATION_MINUTES" =~ ^[0-9]+$ && "$threshold" =~ ^[0-9]+$ && "$SESSION_DURATION_MINUTES" -ge "$threshold" ]]; then
        printf 'true\n'
      else
        printf 'false\n'
      fi
      ;;
    "tool_call_count_mod_20 == 0")
      if [[ "$TOOL_CALL_COUNT" -gt 0 && $((TOOL_CALL_COUNT % 20)) -eq 0 ]]; then
        printf 'true\n'
      else
        printf 'false\n'
      fi
      ;;
    "tool_call_count_mod_10 == 0")
      if [[ "$TOOL_CALL_COUNT" -gt 0 && $((TOOL_CALL_COUNT % 10)) -eq 0 ]]; then
        printf 'true\n'
      else
        printf 'false\n'
      fi
      ;;
    "last_file_ext == .env")
      if [[ "$FILE_EXT" == ".env" ]]; then
        printf 'true\n'
      else
        printf 'false\n'
      fi
      ;;
    "last_output_has_error == true")
      if [[ "$LAST_OUTPUT_HAS_ERROR" == "true" ]]; then
        printf 'true\n'
      else
        printf 'false\n'
      fi
      ;;
    *)
      printf 'false\n'
      ;;
  esac
}

deliver_nudge() {
  local raw_message="$1"
  local message
  message=$(printf '%s' "$raw_message" | tr -d '\000-\010\013-\037\177')

  if [ -t 1 ]; then
    printf '%s\n' "$message"
    return
  fi

  if [[ "${NUDGE_DESKTOP_NOTIFY:-false}" != "true" ]]; then
    return
  fi

  local notify_dir="${NUDGE_NOTIFY_DIR:-$SCRIPT_DIR}"
  local uname_out
  uname_out="$(uname -s 2>/dev/null || printf 'unknown')"
  local notify_script=""
  local powershell_bin=""

  case "$uname_out" in
    Darwin*)
      notify_script="${notify_dir}/notify-mac.sh"
      ;;
    Linux*)
      notify_script="${notify_dir}/notify-linux.sh"
      ;;
    MINGW*|MSYS*|CYGWIN*)
      notify_script="${notify_dir}/notify-windows.ps1"
      if command -v powershell.exe >/dev/null 2>&1; then
        powershell_bin="powershell.exe"
      elif command -v pwsh >/dev/null 2>&1; then
        powershell_bin="pwsh"
      fi
      ;;
  esac

  if [[ "$notify_script" == *.ps1 ]]; then
    if [[ -n "$powershell_bin" && -f "$notify_script" ]]; then
      local notify_script_win="$notify_script"
      if command -v cygpath >/dev/null 2>&1; then
        notify_script_win="$(cygpath -w "$notify_script")"
      fi
      "$powershell_bin" -File "$notify_script_win" -Message "$message" >/dev/null 2>&1 &
    fi
  else
    [[ -f "$notify_script" ]] && bash "$notify_script" "$message" >/dev/null 2>&1 &
  fi
}

with_state_lock state_action ensure >/dev/null 2>&1 || exit 0
with_state_lock state_action prepare "$EVENT_TYPE" >/dev/null 2>&1 || exit 0

TOOL_CALL_COUNT="$(state_action get_tool_count 2>/dev/null || printf '0\n')"
SESSION_START_TIME="$(state_action get_session_start 2>/dev/null || printf '\n')"
SESSION_DURATION_MINUTES="$(session_minutes_since "$SESSION_START_TIME")"

FILE_PATH="$(json_get_text_path "$PAYLOAD" "" tool_input file_path)"
if [[ -z "$FILE_PATH" ]]; then
  FILE_PATH="$(json_get_text_path "$PAYLOAD" "" tool_input path)"
fi
FILE_EXT="$(detect_file_extension "$FILE_PATH")"

CONTEXT_PCT=0
SESSION_ID="$(json_get_text_path "$PAYLOAD" "" session_id)"
if [[ "$SESSION_ID" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  local_bridge="${TMPDIR:-/tmp}/claude-ctx-${SESSION_ID}.json"
  if [[ -f "$local_bridge" ]]; then
    bridge_used_pct="$(json_get_file_path "$local_bridge" "" used_pct)"
    bridge_remaining_pct="$(json_get_file_path "$local_bridge" "" remaining_percentage)"
    CONTEXT_PCT="$(normalize_percentage "$bridge_used_pct" "$bridge_remaining_pct")"
  fi
fi

LAST_OUTPUT_HAS_ERROR="false"

MATCHING_NUDGES="$(matching_nudges_for_event "$EVENT_TYPE")"
[[ -z "$MATCHING_NUDGES" ]] && exit 0

while IFS= read -r nudge; do
  [[ -z "$nudge" ]] && continue

  nudge_id="$(json_get_text_path "$nudge" "" id)"
  nudge_message="$(json_get_text_path "$nudge" "" message)"
  nudge_cooldown="$(json_get_text_path "$nudge" "0" cooldown_minutes)"
  nudge_condition="$(json_get_text_path "$nudge" "" trigger condition)"

  [[ -z "$nudge_id" || -z "$nudge_message" ]] && continue
  [[ "$nudge_cooldown" =~ ^[0-9]+$ ]] || nudge_cooldown=0

  condition_met="$(evaluate_condition "$nudge_condition")"
  [[ "$condition_met" != "true" ]] && continue

  if [[ "$(with_state_lock state_action claim "$nudge_id" "$nudge_cooldown" 2>/dev/null || printf 'false\n')" == "true" ]]; then
    deliver_nudge "$nudge_message"
  fi
done <<< "$MATCHING_NUDGES"

exit 0
