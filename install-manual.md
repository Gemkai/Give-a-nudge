# Give a Nudge — Manual Installation Guide

## Section 1: Prerequisites

| Requirement | Notes |
|---|---|
| `bash` or bash-compatible shell | Required for all hook scripts |
| `jq` or Python 3 | Required for JSON parsing. Install `jq` via `brew install jq`, `apt install jq`, or [jq.dev](https://jqlang.github.io/jq/). Python 3 also works as a fallback. |
| Claude Code CLI | Required for Claude Code integration |
| Gemini CLI | Required for Gemini CLI integration |
| Desktop notification tool | Optional — see Section 4 |

---

## Section 2: Claude Code — Manual Install

### 2a. Copy files

```bash
cp -r core/claude-code/hooks/ ~/.claude/hooks/
cp core/claude-code/nudges.json ~/.claude/nudges.json
chmod +x ~/.claude/hooks/*.sh
cp desktop/notify-linux.sh ~/.claude/hooks/      # optional but recommended
cp desktop/notify-mac.sh ~/.claude/hooks/        # optional but recommended
cp desktop/notify-windows.ps1 ~/.claude/hooks/   # optional but recommended
```

### 2b. Register hooks in `~/.claude/settings.json`

Add the following under the top-level `"hooks"` key. Create the file if it doesn't exist.

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/on-session-start.sh"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/on-tool-use.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/on-tool-use.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/on-stop.sh"
          }
        ]
      }
    ]
  }
}
```

**Important:** Do not add `"async": true` to any hook entry. Nudges print to stdout — async hooks suppress that output and nudges will silently vanish.

### 2c. Verify

```bash
echo '{}' | bash ~/.claude/hooks/on-tool-use.sh
```

No output and exit code 0 = correct. A nudge may fire if state context triggers one.

---

## Section 3: Gemini CLI — Manual Install

### 3a. Copy files

```bash
cp -r core/gemini-cli/hooks/ ~/.gemini/hooks/
cp core/gemini-cli/nudges.json ~/.gemini/nudges.json
chmod +x ~/.gemini/hooks/*.sh
cp desktop/notify-linux.sh ~/.gemini/hooks/      # optional but recommended
cp desktop/notify-mac.sh ~/.gemini/hooks/        # optional but recommended
cp desktop/notify-windows.ps1 ~/.gemini/hooks/   # optional but recommended
```

### 3b. Register hooks in `~/.gemini/settings.json`

```json
{
  "enableHooks": true,
  "hooks": {
    "BeforeTool": "bash ~/.gemini/hooks/on-tool-use.sh",
    "AfterTool": "bash ~/.gemini/hooks/on-tool-use.sh",
    "SessionStart": "bash ~/.gemini/hooks/on-session-start.sh",
    "AfterAgent": "bash ~/.gemini/hooks/on-stop.sh"
  }
}
```

`"enableHooks": true` is required — without it Gemini CLI ignores all hook entries.

### 3c. Verify

```bash
echo '{}' | bash ~/.gemini/hooks/on-tool-use.sh
```

Same expectation as Claude Code: silent exit with code 0.

---

## Section 4: Desktop Notifications (Optional)

Terminal stdout is the primary nudge channel. Desktop notifications are opt-in for users who want them outside terminal sessions.

**macOS**

```bash
cp desktop/notify-mac.sh ~/.claude/hooks/   # or ~/.gemini/hooks/
export NUDGE_DESKTOP_NOTIFY=true
```

**Linux** — requires `libnotify-bin` (`apt install libnotify-bin`)

```bash
cp desktop/notify-linux.sh ~/.claude/hooks/
export NUDGE_DESKTOP_NOTIFY=true
```

**Windows** — requires PowerShell

```powershell
Copy-Item desktop\notify-windows.ps1 $env:USERPROFILE\.claude\hooks\
$env:NUDGE_DESKTOP_NOTIFY = "true"
```

If PowerShell blocks the script, run: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`

See `desktop/README.md` for full setup details and persistent environment variable configuration.

---

## Section 5: Customizing Nudges

Edit `nudges.json` in your CLI home directory (`~/.claude/nudges.json` or `~/.gemini/nudges.json`).

- **Disable a nudge:** Remove its entry from the array, or set `"cooldown_minutes": 99999`
- **Add a nudge:** Follow the schema documented in `community/SUBMIT.md`

Changes take effect immediately — no restart required.

---

## Section 6: Uninstall

**Claude Code**

```bash
# Remove hook entries from ~/.claude/settings.json (delete the "hooks" key)
rm -rf ~/.claude/hooks/
rm -f ~/.claude/nudge-state.json
```

**Gemini CLI**

```bash
# Remove hook entries from ~/.gemini/settings.json (delete "enableHooks" and "hooks" keys)
rm -rf ~/.gemini/hooks/
rm -f ~/.gemini/nudge-state.json
```

If you manually added a session-start command anywhere else in your shell profile, remove that line too.
