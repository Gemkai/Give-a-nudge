# HANDOFF — Give a Nudge Public Release — 2026-04-20

## Mission
Shipping Give a Nudge (Jemakai Blyden) as a public open-source repo at github.com/Gemkai/Give-a-nudge — a config-driven behavioral nudge system for Claude Code and Gemini CLI.

## Current State (What's Done)
- [x] Streak tracker — added to both runners (Claude Code + Gemini CLI). Blocks any nudge that fires 3+ consecutive times. State key: `nudge_streak: {id, count}`.
- [x] Gemini runner write_tool_count bug fixed — was always 0; now tracked correctly via TOOL_NAME extraction.
- [x] pack + tier schema — every nudge has `"pack": "starter"` and `"tier": "CRITICAL|HIGH|MEDIUM|INFO"`.
- [x] 10 new nudges added — workflow-commit-reminder, workflow-session-handoff, workflow-subagent-context, workflow-plan-multistep, info-compact-clear-cycle, info-line-number-reference, info-suppress-explanations, info-mcp-prune-session, info-claudeignore-hygiene (CC only), info-model-reminder (CC only).
- [x] LICENSE updated — copyright holder is now "Jemakai Blyden".
- [x] packs/security branch — 6 security nudges per environment in `core/*/packs/security.json`, targeting users with a security-audit skill.
- [x] Pushed to GitHub — main + packs/security both live.
- [x] CI fix — release-hygiene.yml was using `python` (not available on ubuntu-22.04); fixed to `python3`. Pushed and CI should be green.

## Next Immediate Action
Check https://github.com/Gemkai/Give-a-nudge/actions to confirm the CI fix went green. If it's still failing, look for a second issue in the regression test suite (`tests/release-regression.sh`) — specifically any `date` or `mktemp` invocation that behaves differently on Linux.

## Critical Context (Don't Re-Discover)
- **safe.directory**: The repo has a git ownership mismatch between CodexSandboxOffline and jemak users. Always run `git config --global --add safe.directory "$(pwd)"` (from the repo root) at the start of any session that needs git commands.
- **Pre-commit hook**: Antigravity Doctor v2 runs on every commit. It checks global `~/.gemini/antigravity/` invariants — failures here block commits even though they're unrelated to give-a-nudge. The `orchestration/nudge_system.py -> scratch` issue from this session was fixed by moving the file.
- **READ-BEFORE-EDIT hook**: A hook fires before every edit to `nudge-runner.sh` and `nudges.json` requiring a Read before each Edit. Always re-read the target line range before editing these files.
- **Vanilla compatibility rule**: Starter pack nudges must not reference OMC/Antigravity skills (`/simplify`, `/scout`, `/health-monitor`, etc.). Only `/compact`, `/clear`, `/model` (Claude Code native) are allowed. Use "look for or build a X skill" phrasing for everything else.
- **Gemini context_pct always 0**: `lessons-compact-number-loss` fires on Claude Code (context bridge exists) but never on Gemini (no bridge). Not a bug — known limitation.
- **packs/security branch**: Does NOT auto-merge to main. Intentionally separate. Users must manually copy nudges from `core/*/packs/security.json` into their local nudges.json to opt in.
- **write_tool_count conditions on Gemini**: Gemini-specific nudges use `tool_call_count_mod_10` or `session_duration_minutes` instead of `write_tool_count` where the trigger intent is "active editing session" — this was a deliberate substitution since write_tool_count was broken in Gemini until this session.

## Blocked / Waiting On
- CI confirmation — the `python3` fix should resolve the failure, but needs to be verified at github.com/Gemkai/Give-a-nudge/actions.
- README still references example nudge messages using `/security-audit` and `/scout` (OMC skills) in the "Example nudges" section — these are vanilla-incompatible examples. Low priority but worth cleaning up before wide promotion.

## Files Modified This Session
| File | Change |
|------|--------|
| `core/claude-code/nudges.json` | +10 nudges, pack+tier fields on all 20 nudges |
| `core/gemini-cli/nudges.json` | +10 nudges, pack+tier fields on all 18 nudges |
| `core/claude-code/hooks/nudge-runner.sh` | Streak tracker (DEFAULT_STATE_JSON, jq cases, Python handlers, deliver loop) |
| `core/gemini-cli/hooks/nudge-runner.sh` | Streak tracker + write_tool_count fix |
| `core/claude-code/packs/security.json` | New file — 6 security pack nudges (packs/security branch only) |
| `core/gemini-cli/packs/security.json` | New file — 6 security pack nudges (packs/security branch only) |
| `LICENSE` | Copyright → "Jemakai Blyden" |
| `.github/workflows/release-hygiene.yml` | `python` → `python3` (CI fix) |
| `README.md`, `CONTRIBUTING.md`, `ROADMAP.md`, `SECURITY.md` | Prose cleanup from previous session |
| `community/README.md` | New file — catalog rules and promotion path |
| `community/SUBMIT.md` | Updated |
| `.github/workflows/community-catalog.yml` | New — CI for community submissions |
| `.github/workflows/community-catalog-automerge.yml` | New — auto-merge for catalog-only PRs |
| `tests/validate-community-submissions.py` | New — Python schema validator for submissions |
| `tests/validate-community-submissions.sh` | New — shell wrapper |
| `tests/release-regression.sh` | Wired in community submission validation |

## Nudge Counts (final)
- Claude Code: 20 nudges (starter pack) + 6 (packs/security branch)
- Gemini CLI: 18 nudges (starter pack) + 6 (packs/security branch)

## Commands to Resume
```bash
# Fix git ownership if needed (run once per session)
git config --global --add safe.directory "$(pwd)"

# Check current branch state
git log --oneline --all --graph

# Run full test suite locally
bash tests/release-regression.sh
```
