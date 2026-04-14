# Submit a Nudge

A nudge is a short, passive reminder that appears in your terminal at the right moment — no clicks, no confirmations, no interruptions. Just a single line that surfaces the right command when context makes it relevant.

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
- Must be passive — no required user action
- Cooldown must be ≥ 5 minutes for repeating nudges

## How to submit

1. Fork this repo
2. Create `community/submissions/your-slug-nudge-name/nudge.json`
3. Fill in the template above
4. Run `bash tests/release-hygiene.sh`
5. Open a PR

That's it. Lightweight review — maintainer checks passivity, cooldown, and message clarity.

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
  "comment": "Example — fires every 20 tool calls as a session capture reminder"
}
```
