# Give a Nudge — Pull Request

> Lightweight template — fill in what applies, skip the rest.

## Nudge details (for community nudge submissions)

- **Nudge ID:** <!-- e.g. security-dockerfile -->
- **Category:** <!-- context_clearing | usage_monitoring | security_review | debugging | command_discovery -->
- **Trigger event:** <!-- tool_use | session_start | pre_commit -->
- **Condition:** <!-- e.g. last_file_ext == .dockerfile, or blank for unconditional -->
- **Cooldown (minutes):** <!-- 0 = every time, 30 = once per 30 min, 480 = once per session -->
- **Environments tested:** <!-- claude-code | gemini-cli | both -->

## Message preview

```
nudge: <your message here>
```

## Description

<!-- What behavior does this nudge encourage? Why is it useful at this trigger point? -->

## Checklist

- [ ] Message starts with `nudge: ` (lowercase, space after colon)
- [ ] Message is one line, under 120 characters
- [ ] Cooldown is appropriate (no nudge with cooldown 0 that fires on every tool call)
- [ ] `comment` field explains when and why it fires
- [ ] Tested: `bash nudge-test.sh` passes after adding this nudge
- [ ] Hygiene: `bash tests/release-hygiene.sh` passes and no secrets / personal paths were added
