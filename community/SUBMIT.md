# Submit a Community Nudge

A nudge is a short, passive reminder that appears in your terminal at the right moment - no clicks, no confirmations, no interruptions. Just a single line that surfaces the right command when context makes it relevant.

This folder is the **community catalog tier**:

- submissions here are unreviewed
- submissions here are manual opt-in
- submissions here are not installed by default
- merging a submission means it passed CI and policy checks, not that it was promoted into core

## The template

Create a file at `community/submissions/your-slug-your-nudge-name/nudge.json`:

```json
{
  "id": "your-nudge-id",
  "category": "context_clearing | usage_monitoring | security_review | debugging | command_discovery",
  "trigger": {
    "event": "session_start | tool_use | stop",
    "condition": ""
  },
  "cooldown_minutes": 60,
  "message": "nudge: your message here.",
  "environments": ["claude-code", "gemini-cli"],
  "comment": "one line: when and why this fires"
}
```

## Rules

- Message must start with `nudge: `
- Message must be a single line
- Message must be 120 characters or fewer
- Must be passive - no required user action
- Must use a supported trigger event: `session_start`, `tool_use`, or `stop`
- Must use a supported condition string
- Cooldown must be appropriate for the trigger

Supported condition strings:

- `""` (unconditional)
- `context_pct >= N`
- `session_duration_minutes >= N`
- `tool_call_count_mod_10 == 0`
- `tool_call_count_mod_20 == 0`
- `last_file_ext == .env`
- `last_output_has_error == true`

## How to submit

1. Fork this repo
2. Create `community/submissions/your-slug-nudge-name/nudge.json`
3. Fill in the template above
4. Run `bash tests/release-hygiene.sh`
5. Run `bash tests/validate-community-submissions.sh`
6. Open a PR

If you want your nudge to ship by default, that is a separate **promotion to core** step and requires a maintainer-reviewed PR touching `core/*/nudges.json`.

To try a catalog nudge locally, inspect it first, then copy its JSON object into your own `~/.claude/nudges.json` or `~/.gemini/nudges.json`.

## Example

```json
{
  "id": "example-session-capture",
  "category": "command_discovery",
  "trigger": {
    "event": "tool_use",
    "condition": "tool_call_count_mod_20 == 0"
  },
  "cooldown_minutes": 60,
  "message": "nudge: working on a large task? /session-summary captures your progress before context rolls over.",
  "environments": ["claude-code", "gemini-cli"],
  "comment": "Example - fires every 20 tool calls as a session capture reminder"
}
```
