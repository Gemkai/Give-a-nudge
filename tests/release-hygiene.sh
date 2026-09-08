#!/usr/bin/env bash
# Release hygiene checks for public-safe repository contents.
# Usage: bash tests/release-hygiene.sh

set -u

PASS=0
FAIL=0

pass() { echo "[PASS] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELF_PATH="tests/release-hygiene.sh"

scan_pattern() {
  local pattern="$1"
  local label="$2"
  local content_out names_list names_out
  content_out="$(mktemp)" || { fail "$label (could not create a scratch file -- scan not run)"; return; }
  names_list="$(mktemp)" || { fail "$label (could not create a scratch file -- scan not run)"; rm -f "$content_out"; return; }
  names_out="$(mktemp)" || { fail "$label (could not create a scratch file -- scan not run)"; rm -f "$content_out" "$names_list"; return; }
  # Defense in depth against an interrupted run leaving scratch files behind on a
  # local dev machine (this script also runs outside ephemeral CI, per CONTRIBUTING.md).
  trap 'rm -f "$content_out" "$names_list" "$names_out"' RETURN

  # Search git-tracked content only -- never a raw filesystem walk. This is what Git
  # will actually commit/ship, so a dependency tree (node_modules, .venv, dist, build,
  # __pycache__, ...) is excluded for free whenever it's gitignored, with NO name-based
  # guessing: a file that IS tracked under a directory named "dist" or "build" (build
  # artifacts genuinely get committed sometimes) is still scanned, unlike a plain
  # `--exclude-dir=dist` filesystem walk, which would silently create a scanning blind
  # spot on tracked content.
  #
  # -l/--name-only: we only ever report a filename, never the matched bytes -- asking
  # git to hand back just the filename means there is no code path anywhere in this
  # function that can leak the actual secret text, including the error branch below
  # (an earlier version captured full "path:line:content" matches and had to remember
  # to strip content in every branch; forgetting one was exactly how this got flagged).
  #
  # stderr is merged into the same stream deliberately: `git grep` can print a
  # per-file error (e.g. permission denied reading a tracked file) to stderr while
  # STILL exiting 1 ("no match"), if nothing else in the repo happened to match --
  # verified empirically. Trusting the exit code alone would silently reproduce the
  # exact bug this rewrite exists to fix, just one level down.
  git -C "$ROOT_DIR" grep --no-color -I -l -E "$pattern" -- . ":(exclude)$SELF_PATH" \
    >"$content_out" 2>&1
  local content_rc=$?

  # Also check tracked FILENAMES themselves, not just file contents -- a secret can be
  # committed as (or embedded in) a filename, and a content-only scan would miss it.
  git -C "$ROOT_DIR" ls-files -z -- . ":(exclude)$SELF_PATH" >"$names_list" 2>>"$content_out"
  local names_ls_rc=$?
  tr '\0' '\n' <"$names_list" | grep -nE "$pattern" >"$names_out"
  local names_rc=$?

  local errored=0
  [[ "$content_rc" -gt 1 ]] && errored=1
  [[ "$names_ls_rc" -ne 0 ]] && errored=1
  [[ "$names_rc" -gt 1 ]] && errored=1
  # rc=1 ("no match") plus leaked output can only mean an error was printed -- a
  # genuinely clean, error-free run produces zero bytes on this stream.
  [[ "$content_rc" -eq 1 && -s "$content_out" ]] && errored=1

  if [[ "$errored" -eq 1 ]]; then
    fail "$label (scan error -- treated as unclean, not skipped)"
    # Safe to dump verbatim: with -l, this stream only ever contains filenames or
    # git's own diagnostic text, never matched secret bytes.
    [[ -s "$content_out" ]] && sed 's/^/    /' "$content_out"
  elif [[ "$content_rc" -eq 0 || "$names_rc" -eq 0 ]]; then
    fail "$label"
    # Report which files matched, never the matching bytes themselves -- a rule/filename
    # is enough to act on, and this scan's own job is to keep secret-looking material out
    # of logs, not put it there when the scan itself fails.
    [[ "$content_rc" -eq 0 ]] && sort -u "$content_out" | sed 's/^/    /'
    # A filename MATCH can mean the secret itself is the filename (e.g. an API key
    # used as a literal name) -- redact the matched substring before printing so this
    # path can't leak the very thing it exists to catch.
    [[ "$names_rc" -eq 0 ]] && cut -d: -f2- "$names_out" \
      | sed -E "s/($pattern)/[REDACTED]/g" | sed 's/^/    (filename) /'
  else
    pass "$label"
  fi
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
