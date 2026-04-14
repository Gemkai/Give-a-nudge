#!/usr/bin/env bash
# =============================================================================
# Give a Nudge — Installer
# =============================================================================
# Usage: Run from the repo root (the give-a-nudge/ parent directory):
#   bash give-a-nudge/install.sh
#
# Installs hook integrations for Claude Code and/or Gemini CLI.
# Safe to run multiple times (idempotent). Backs up settings.json before
# patching. Never uses rm -rf or other destructive operations.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -----------------------------------------------------------------------------
# Colours & helpers
# -----------------------------------------------------------------------------
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${CYAN}[nudge]${RESET} $*"; }
success() { echo -e "${GREEN}[nudge]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[nudge] WARNING:${RESET} $*"; }
error()   { echo -e "${RED}[nudge] ERROR:${RESET} $*" >&2; }
header()  { echo -e "\n${BOLD}${CYAN}=== $* ===${RESET}"; }

# -----------------------------------------------------------------------------
# 1. Detect available tools / environments
# -----------------------------------------------------------------------------
header "Detecting environments"

HAS_CLAUDE=false
HAS_GEMINI=false

if command -v claude &>/dev/null; then
  info "claude CLI found: $(command -v claude)"
  HAS_CLAUDE=true
elif [[ -d "$HOME/.claude" ]]; then
  info "~/.claude/ directory found (Claude Code home detected without CLI in PATH)"
  HAS_CLAUDE=true
fi

if command -v gemini &>/dev/null; then
  info "gemini CLI found: $(command -v gemini)"
  HAS_GEMINI=true
elif [[ -d "$HOME/.gemini" ]]; then
  info "~/.gemini/ directory found (Gemini CLI home detected without CLI in PATH)"
  HAS_GEMINI=true
fi

if [[ "$HAS_CLAUDE" == false && "$HAS_GEMINI" == false ]]; then
  error "Neither Claude Code nor Gemini CLI was found on this system."
  error "Install at least one of:"
  error "  Claude Code:  https://claude.ai/download"
  error "  Gemini CLI:   https://ai.google.dev/gemini-api/docs/gemini-cli"
  exit 1
fi

# -----------------------------------------------------------------------------
# 2. Check for JSON processing tools
# -----------------------------------------------------------------------------
header "Checking for JSON tools"

HAS_JQ=false
HAS_PY=false

if command -v jq &>/dev/null; then
  HAS_JQ=true
  info "jq found: $(command -v jq)"
fi

if command -v python3 &>/dev/null || command -v python &>/dev/null; then
  HAS_PY=true
  info "python found"
fi

if [[ "$HAS_JQ" == false && "$HAS_PY" == false ]]; then
  warn "Neither jq nor python found. Automatic settings.json patching will be skipped."
  warn "For best results, install jq or python."
fi

# -----------------------------------------------------------------------------
# Helper: back up a file before modifying it
# -----------------------------------------------------------------------------
backup_file() {
  local file="$1"
  if [[ -f "$file" ]]; then
    cp "$file" "${file}.nudge-bak"
    info "Backed up $file → ${file}.nudge-bak"
  fi
}

# -----------------------------------------------------------------------------
# Helper: copy a hook file and make it executable
# -----------------------------------------------------------------------------
install_hook() {
  local src="$1"
  local dest_dir="$2"
  local filename
  filename="$(basename "$src")"

  if [[ ! -f "$src" ]]; then
    warn "Source file not found, skipping: $src"
    return
  fi

  cp "$src" "$dest_dir/$filename"
  if [[ "$filename" == *.sh ]]; then
    chmod +x "$dest_dir/$filename"
  fi
  info "  Installed $filename → $dest_dir/$filename"
}

# -----------------------------------------------------------------------------
# Helper: merge JSON objects (deep merge: base * patch)
# -----------------------------------------------------------------------------
merge_json() {
  local base_file="$1"
  local patch_json="$2"

  local tmp_patch=""
  local tmp_result=""

  if [[ "$HAS_JQ" == true ]]; then
    tmp_patch="$(mktemp)"
    tmp_result="$(mktemp)"
    trap 'rm -f "$tmp_patch" "$tmp_result"' RETURN
    echo "$patch_json" > "$tmp_patch"
    if jq -s '.[0] * .[1]' "$base_file" "$tmp_patch" > "$tmp_result"; then
      mv "$tmp_result" "$base_file"
      return 0
    fi
    rm -f "$tmp_result"
    return 1
  fi

  if [[ "$HAS_PY" == true ]]; then
    local py_cmd
    if command -v python3 &>/dev/null; then py_cmd="python3"
    else py_cmd="python"; fi
    tmp_result="$(mktemp)"

    if $py_cmd -c "
import json, sys
def merge(a, b):
    for k, v in b.items():
        if k in a and isinstance(a[k], dict) and isinstance(v, dict):
            merge(a[k], v)
        else:
            a[k] = v
    return a

with open(sys.argv[1], 'r') as f: base = json.load(f)
patch = json.loads(sys.argv[2])
res = merge(base, patch)
with open(sys.argv[3], 'w') as f:
    json.dump(res, f, indent=2)
    f.write('\n')
" "$base_file" "$patch_json" "$tmp_result"; then
      mv "$tmp_result" "$base_file"
      return 0
    fi

    rm -f "$tmp_result"
    return 1
  fi

  return 1
}

# -----------------------------------------------------------------------------
# Helper: write settings.json from scratch when it doesn't exist
# -----------------------------------------------------------------------------
write_new_settings() {
  local dest="$1"
  local content="$2"
  echo "$content" > "$dest"
  info "  Created $dest"
}

# =============================================================================
# 3. Install Claude Code integration
# =============================================================================
install_claude() {
  header "Installing Claude Code integration"

  local hooks_src="$SCRIPT_DIR/core/claude-code/hooks"
  local nudges_src="$SCRIPT_DIR/core/claude-code/nudges.json"
  local desktop_src="$SCRIPT_DIR/desktop"
  local hooks_dest="$HOME/.claude/hooks"
  local settings="$HOME/.claude/settings.json"

  # Create hooks directory
  mkdir -p "$hooks_dest"
  info "Hooks directory: $hooks_dest"

  # Copy hook scripts
  install_hook "$hooks_src/nudge-runner.sh"     "$hooks_dest"
  install_hook "$hooks_src/on-session-start.sh" "$hooks_dest"
  install_hook "$hooks_src/on-tool-use.sh"      "$hooks_dest"
  install_hook "$hooks_src/on-stop.sh"          "$hooks_dest"
  install_hook "$desktop_src/notify-linux.sh"   "$hooks_dest"
  install_hook "$desktop_src/notify-mac.sh"     "$hooks_dest"
  install_hook "$desktop_src/notify-windows.ps1" "$hooks_dest"

  # Copy nudges.json
  local nudges_dest
  nudges_dest="$(dirname "$hooks_dest")/nudges.json"
  if [[ -f "$nudges_src" ]]; then
    cp "$nudges_src" "$nudges_dest"
    info "  Installed nudges.json → $nudges_dest"
  fi

  # Patch settings.json
  local hook_block
  hook_block='{
  "hooks": {
    "SessionStart": [ { "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/on-session-start.sh" } ] } ],
    "PreToolUse": [ { "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/on-tool-use.sh" } ] } ],
    "PostToolUse": [ { "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/on-tool-use.sh" } ] } ],
    "Stop": [ { "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/on-stop.sh" } ] } ]
  }
}'

  if [[ -f "$settings" ]]; then
    backup_file "$settings"
    if merge_json "$settings" "$hook_block"; then
      success "  Merged hook entries into $settings"
    else
      warn "  JSON merge failed (no jq or python found). Add manually."
    fi
  else
    write_new_settings "$settings" "$hook_block"
  fi

  INSTALLED_CLAUDE=true
}

# =============================================================================
# 4. Install Gemini CLI integration
# =============================================================================
install_gemini() {
  header "Installing Gemini CLI integration"

  local hooks_src="$SCRIPT_DIR/core/gemini-cli/hooks"
  local nudges_src="$SCRIPT_DIR/core/gemini-cli/nudges.json"
  local desktop_src="$SCRIPT_DIR/desktop"
  local hooks_dest="$HOME/.gemini/hooks"
  local settings="$HOME/.gemini/settings.json"

  # Create hooks directory
  mkdir -p "$hooks_dest"
  info "Hooks directory: $hooks_dest"

  # Copy hook scripts
  install_hook "$hooks_src/nudge-runner.sh"     "$hooks_dest"
  install_hook "$hooks_src/on-session-start.sh" "$hooks_dest"
  install_hook "$hooks_src/on-tool-use.sh"      "$hooks_dest"
  install_hook "$hooks_src/on-stop.sh"          "$hooks_dest"
  install_hook "$desktop_src/notify-linux.sh"   "$hooks_dest"
  install_hook "$desktop_src/notify-mac.sh"     "$hooks_dest"
  install_hook "$desktop_src/notify-windows.ps1" "$hooks_dest"

  # Copy nudges.json
  local nudges_dest
  nudges_dest="$(dirname "$hooks_dest")/nudges.json"
  if [[ -f "$nudges_src" ]]; then
    cp "$nudges_src" "$nudges_dest"
    info "  Installed nudges.json → $nudges_dest"
  fi

  # Patch settings.json
  local hook_block
  hook_block='{
  "enableHooks": true,
  "hooks": {
    "BeforeTool":    "bash ~/.gemini/hooks/on-tool-use.sh",
    "AfterTool":     "bash ~/.gemini/hooks/on-tool-use.sh",
    "SessionStart":  "bash ~/.gemini/hooks/on-session-start.sh",
    "AfterAgent":    "bash ~/.gemini/hooks/on-stop.sh"
  }
}'

  if [[ -f "$settings" ]]; then
    backup_file "$settings"
    if merge_json "$settings" "$hook_block"; then
      success "  Merged hook entries into $settings"
    else
      warn "  JSON merge failed (no jq or python found). Add manually."
    fi
  else
    write_new_settings "$settings" "$hook_block"
  fi

  INSTALLED_GEMINI=true
}

# =============================================================================
# 5. Run installs
# =============================================================================
INSTALLED_CLAUDE=false
INSTALLED_GEMINI=false

[[ "$HAS_CLAUDE" == true ]] && install_claude
[[ "$HAS_GEMINI" == true ]] && install_gemini

header "Installation complete"
success "Give a Nudge is installed and ready."
exit 0
