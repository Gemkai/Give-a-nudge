# Contributing

## Submit a community nudge

See [community/SUBMIT.md](community/SUBMIT.md) for the full guide. Short version:

1. Fork the repo
2. Create `community/submissions/your-slug-nudge-name/nudge.json`
3. Run `bash tests/release-hygiene.sh`
4. Run `bash tests/validate-community-submissions.sh`
5. Open a PR

Community submissions are the **unreviewed manual-opt-in tier**. They are not installed by default and merging one does not mean it has been promoted into the curated core set.

PRs that only add or update `community/submissions/<slug>/nudge.json` can auto-merge after CI passes. Anything else stays in the manual review lane.

## Promote a nudge into core

If you want a nudge to ship by default, open a separate PR editing:

- `core/claude-code/nudges.json`
- `core/gemini-cli/nudges.json`

Core nudges are the **reviewed tier** and should stay maintainer-curated.

## Report a bug

Open a GitHub issue and include:

- Your OS and environment (Claude Code / Gemini CLI, version)
- What you expected to happen
- What actually happened
- Output of `bash tests/nudge-test.sh`

## Request a new core nudge

Open a GitHub issue with:

- The category it belongs to (`context_clearing`, `usage_monitoring`, `security_review`, `debugging`, `command_discovery`)
- The trigger event (`session_start`, `tool_use`, `stop`)
- Your proposed message (must start with `nudge: `)
- Why it helps a fresh install user specifically
