# Contributing

## Submit a community nudge

See [community/SUBMIT.md](community/SUBMIT.md) for the full guide. Short version: fork, create `community/submissions/your-slug-nudge-name/nudge.json`, run `bash tests/release-hygiene.sh`, then open a PR.

## Report a bug

Open a GitHub issue and include:
- Your OS and environment (Claude Code / Gemini CLI, version)
- What you expected to happen
- What actually happened
- Output of `bash tests/nudge-test.sh`

## Request a new core nudge

Open a GitHub issue with:
- The category it belongs to (context_clearing / usage_monitoring / security_review / debugging / command_discovery)
- The trigger event (session_start / tool_use / stop)
- Your proposed message (must start with `nudge: `)
- Why it helps a fresh install user specifically
