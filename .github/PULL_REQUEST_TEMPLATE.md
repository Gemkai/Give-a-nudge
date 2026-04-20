# Give a Nudge - Pull Request

> Lightweight template - fill in what applies, skip the rest.

## Nudge details (for community submissions or core promotions)

- **Tier:** <!-- community catalog (unreviewed/manual opt-in) | core promotion (reviewed/default) -->
- **Nudge ID:** <!-- e.g. security-dockerfile -->
- **Category:** <!-- context_clearing | usage_monitoring | security_review | debugging | command_discovery -->
- **Trigger event:** <!-- tool_use | session_start | stop -->
- **Condition:** <!-- e.g. last_file_ext == .dockerfile, or blank for unconditional -->
- **Cooldown (minutes):** <!-- 0 = every time, 30 = once per 30 min, 480 = once per session -->
- **Environments tested:** <!-- claude-code | gemini-cli | both -->

## Message preview

```text
nudge: <your message here>
```

## Description

<!-- What behavior does this nudge encourage? Why is it useful at this trigger point? -->

## Checklist

- [ ] Message starts with `nudge: ` (lowercase, space after colon)
- [ ] Message is one line, under 120 characters
- [ ] Cooldown is appropriate (no cooldown 0 nudge that fires on every tool call)
- [ ] `comment` field explains when and why it fires
- [ ] Community submissions pass: `bash tests/validate-community-submissions.sh`
- [ ] Core promotions pass: `bash tests/nudge-test.sh` after updating `core/*/nudges.json`
- [ ] Hygiene: `bash tests/release-hygiene.sh` passes and no secrets / personal paths were added
- [ ] I understand community catalog entries are unreviewed and manual opt-in until promoted into core
