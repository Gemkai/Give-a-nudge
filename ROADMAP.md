# Roadmap

## Now - v1.0

- 5 starter nudges across 4 active categories (context clearing, usage monitoring, security review, command discovery)
- Claude Code CLI support (PreToolUse, Stop, SessionStart hooks)
- Gemini CLI support (BeforeTool, AfterAgent, SessionStart hooks)
- Terminal-first delivery - nudges appear in CLI sessions automatically
- Opt-in desktop notifications for Claude Code Desktop and GUI wrapper users
- Config-driven (`nudges.json`) - no code needed to add a nudge
- Automated install script (cross-platform: Windows, Mac, Linux)
- Manual install guide
- Tiered nudge model: reviewed core nudges plus an unreviewed community catalog
- Community submission validation in CI
- MIT license

## Near-term (ongoing)

- New nudges added every 2 weeks by the maintainer
- Community catalog grows through CI-validated submissions
- Core promotions remain maintainer-reviewed
- Bug fixes for platform edge cases (Windows path quirks, Gemini CLI version changes)
- Testing on additional platforms as reports come in

## Future

- **Richer trigger signals** - as Claude Code and Gemini CLI expose more hook payload data, unlock error pattern detection and richer context signals
- **Desktop notification improvements** - richer Windows toast format, notification grouping
- **Multi-maintainer governance** - if community grows, formal review process
- **Additional CLI environments** - as the agentic CLI ecosystem expands
