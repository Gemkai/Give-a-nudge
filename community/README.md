# Community Catalog

`community/submissions/` is the unreviewed community tier for Give a Nudge.

What this means:

- Entries here are not installed by default
- Entries here are not read by the runtime automatically
- A merged community submission means it passed format and policy checks, not that a maintainer personally endorses it
- Users must inspect it and opt in manually before adding it to their local `~/.claude/nudges.json` or `~/.gemini/nudges.json`

Core vs community:

- `core/claude-code/nudges.json` and `core/gemini-cli/nudges.json`
  These are the reviewed core tier. They ship by default and should stay maintainer-curated.
- `community/submissions/*/nudge.json`
  This is the community catalog tier. It is a public library of opt-in nudges with CI validation only.

Promotion path:

1. A nudge can start in `community/submissions/`
2. If it proves useful, a maintainer can promote it in a separate PR
3. Promotion means copying or adapting it into the relevant `core/*/nudges.json`
4. Only promoted core nudges are installed by default

Auto-merge lane:

- PRs that change only `community/submissions/<slug>/nudge.json`
- and pass `Community Catalog` plus `Release Hygiene`
- can merge automatically without maintainer review

Anything touching core nudges, workflows, docs, or scripts stays in the manual review lane.

To contribute a new community nudge, see [SUBMIT.md](SUBMIT.md).
