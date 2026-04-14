# Desktop Notification Setup (Opt-In)

Give a Nudge is **terminal-first** — nudges appear automatically in CLI sessions (Claude Code terminal, Gemini CLI). No setup needed if you use the CLI.

This folder is for users running **Claude Code Desktop** or a **GUI wrapper** around Gemini CLI, where stdout from hooks is not visible.

## How to enable

The installer copies the helper scripts into `~/.claude/hooks/` or `~/.gemini/hooks/`. To turn notifications on, add this to your shell profile (`~/.bashrc`, `~/.zshrc`, or equivalent):

```bash
export NUDGE_DESKTOP_NOTIFY=true
```

Then restart your terminal or run `source ~/.bashrc`.

## Platform setup

### Mac (no prerequisites)
osascript is built into macOS. No install needed. Works immediately after setting the env var.

### Linux
Install libnotify:
```bash
# Debian/Ubuntu
sudo apt install libnotify-bin

# Fedora/RHEL
sudo dnf install libnotify
```

### Windows
Install BurntToast (recommended — richer notifications):
```powershell
Install-Module -Name BurntToast -Scope CurrentUser
```

Or use the built-in .NET fallback — no install needed, but notifications are less polished.

## Test your setup

Run one of these from a terminal after enabling `NUDGE_DESKTOP_NOTIFY=true`:

```bash
printf '{}' | NUDGE_DESKTOP_NOTIFY=true bash ~/.claude/hooks/nudge-runner.sh session_start >/dev/null
printf '{}' | NUDGE_DESKTOP_NOTIFY=true bash ~/.gemini/hooks/nudge-runner.sh session_start >/dev/null
```

A desktop notification should appear within a few seconds.

## How it works

When `NUDGE_DESKTOP_NOTIFY=true` is set and nudge-runner.sh detects it is not running in a terminal (`[ -t 1 ]` is false), it calls the appropriate notify script for your OS instead of printing to stdout.
