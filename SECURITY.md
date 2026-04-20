# Security Policy

## Supported Versions

| Version | Supported |
|---|---|
| v1.x (current) | Yes |

## Threat Model

Give a Nudge is a local CLI tool - it runs bash hooks on your own machine with
your own user privileges. The primary trust boundary is `nudges.json`: the
project ships a curated core config, but users can install community nudges.
Community content is the main attack surface.

**In scope:**
- Malicious `nudges.json` content (crafted messages, injected conditions)
- Shell injection via hook payload fields
- Desktop notification script injection (macOS osascript, Linux notify-send)
- State file manipulation

**Out of scope:**
- Attacks requiring root or physical access
- Attacks on the user's underlying OS or AI CLI tool

## Reporting a Vulnerability

**Do not post exploit details in a public GitHub issue.**

Preferred channel: GitHub's private vulnerability reporting for this
repository (`Security` -> `Report a vulnerability`).

If private reporting is not enabled yet, open a minimal issue requesting a
private contact path and omit reproduction details until a maintainer responds.

Include:
- Affected file(s) and line numbers
- Steps to reproduce
- Impact assessment
- Suggested fix (optional but appreciated)

Expected response: within 72 hours. Fixes targeted within 14 days for
High/Critical.

## Security Design Notes

- Nudge messages are passed through `tr -d` to strip control characters before terminal output
- macOS notifications use AppleScript `on run argv` - message never interpolated into script string
- `SESSION_ID` from hook payload is validated to `^[a-zA-Z0-9_-]+$` before path construction
- State file writes are repaired on invalid JSON, then written atomically via temp file + replace under a lock directory
- Hook scripts use `printf '%s\n'` instead of `echo` to prevent `-n`/`-e` flag injection
- Inline Python helpers pass dynamic values as arguments, not interpolated source, so community nudge IDs cannot become executable code
- Community catalog entries are not installed or executed automatically; users must opt in manually
- Community nudge submissions should be validated by CI against the schema and policy checks in `tests/validate-community-submissions.py`
