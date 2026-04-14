# Hook API Research — Claude Code

Researched from live `~/.claude/settings.json`, hook scripts, and handler source code.
All findings are empirically derived from working production hooks — not documentation.

---

## Available Events

Claude Code exposes five lifecycle hook events. Each event name is used as a key in
`~/.claude/settings.json` under the `"hooks"` object.

| Event | When it fires | Can block? | stdin payload |
|-------|--------------|------------|---------------|
| `SessionStart` | Once at session open | Yes (non-zero exit blocks start) | Minimal session info |
| `SessionEnd` | Once at session close | No (async only, side-effects) | Session summary |
| `Stop` | After every Claude response (end of turn) | Yes (exit 2 = block, prompt user) | Turn summary |
| `PreToolUse` | Before Claude invokes any tool | Yes (exit 2 = block + prompt user; exit 1 = hard block) | Full tool call |
| `PostToolUse` | After a tool returns | Advisory only | Tool call + result |

Plus one special hook type:

| Type | Key in settings.json | Notes |
|------|---------------------|-------|
| `statusLine` | `"statusLine"` (top-level, not under `"hooks"`) | Runs before every prompt render; stdout becomes the status bar text |

### Hook Groups and Matchers

Each event supports an array of hook groups. Groups can have an optional `"matcher"` field
(regex applied to `tool_name`) that scopes the group to specific tools:

```json
{
  "PreToolUse": [
    {
      "matcher": "Bash",
      "hooks": [{ "type": "command", "command": "..." }]
    },
    {
      "matcher": "Write|Edit",
      "hooks": [{ "type": "command", "command": "..." }]
    }
  ]
}
```

Known matcher values observed in production: `Bash`, `Write`, `Edit`, `Read`, `Skill`,
`MultiEdit`, `Agent`, `Task`. Matchers are pipe-delimited regex alternations.

### Hook Configuration Options

Each hook entry within a group supports:

```json
{
  "type": "command",
  "command": "<shell command string>",
  "async": true,          // optional — run detached (stdout NOT injected back)
  "timeout": 10000        // optional — milliseconds before Claude kills the process
}
```

**Critical:** `"async": true` suppresses stdout. Any hook that needs to inject
`additionalContext` back into Claude's prompt MUST be synchronous (omit `async` or
set `async: false`). See CLAUDE.md global rules for details.

---

## Available Environment Variables

### Process Environment Variables (set by Claude Code in the hook process)

| Variable | Available in | Description |
|----------|-------------|-------------|
| `CLAUDE_CONFIG_DIR` | All hooks | Path to the Claude home dir (default: `~/.claude`). Observed in `gsd-statusline.js:76` and `gsd-check-update.js:18`. Overrides the default `~/.claude` path when set. |
| `USERPROFILE` / `HOME` | All hooks | Standard OS home dir variable. Used by hooks to locate `~/.claude` when `CLAUDE_CONFIG_DIR` is absent. |
| `GEMINI_API_KEY` | All hooks | When set, hooks use it to detect they're running under Gemini CLI rather than Claude Code (observed in `gsd-context-monitor.js:153` for `hookEventName` routing). |

No `CLAUDE_CONTEXT_PCT`, `CLAUDE_TOOL_NAME`, `CLAUDE_SESSION_ID`, or similar
Claude-specific env vars were found in any hook script. **Claude Code does NOT
inject hook-specific env vars.** All signal comes via stdin JSON.

### Stdin JSON Payload by Event

All hooks receive their data via **stdin as a JSON object**. The schema varies by event.

#### PreToolUse payload

```jsonc
{
  "tool_name": "Write",            // string — the tool being called
  "tool_input": {                  // object — tool-specific arguments
    "file_path": "/abs/path/to/file.ts",   // Write/Edit/Read tools
    "content": "...",              // Write tool — full file content
    "new_string": "...",           // Edit tool — replacement string
    "old_string": "...",           // Edit tool — string being replaced
    "command": "git push ...",     // Bash tool — shell command string
    "skill": "my-skill-name"       // Skill tool
  },
  "session_id": "abc123",          // string — current session identifier
  "session_type": "task",          // string — "task" when inside a subagent
  "cwd": "/path/to/project",       // string — working directory at hook time
  "tool_input.is_subagent": true   // bool — present when running as Task subagent
}
```

Sources: `guardrails.py:115`, `gsd-prompt-guard.js:43-58`, `gsd-workflow-guard.js:25-40`,
`test_gate.py:61-65`.

#### PostToolUse payload

```jsonc
{
  "tool_name": "Edit",             // string — tool that just ran
  "tool_input": { ... },           // same as PreToolUse
  "session_id": "abc123",          // string
  "cwd": "/path/to/project",       // string
  // tool_output / exit_code / is_error fields: NOT observed in any PostToolUse handler.
  // The gsd-context-monitor reads context % from a bridge file written by statusLine,
  // not from the PostToolUse payload directly.
}
```

**Important finding:** No PostToolUse handler in this codebase reads a `tool_output`,
`exit_code`, `is_error`, or error/traceback field directly from the stdin payload.
The only error-signal consumption is through session state files (`stop_reasons` list
in `current_session.json`) accumulated across turns — not from the immediate hook payload.

#### Stop payload

```jsonc
{
  "stop_reason": "end_turn",       // string — why Claude stopped
  "reason": "...",                 // alternative field name (same data)
  "tool_name": "...",              // optional — last tool used before stopping
  "tool": "..."                    // alternative field name
}
```

Source: `session_tracker.py:49-55`.

#### StatusLine payload

```jsonc
{
  "model": { "display_name": "claude-sonnet-4-5" },
  "workspace": { "current_dir": "/path/to/project" },
  "session_id": "abc123",
  "context_window": {
    "remaining_percentage": 72.4   // float — % of context window still available
  }
}
```

Sources: `gsd-statusline.js:22-24`, `context-bar.py`.

#### SessionStart / SessionEnd payload

Minimal. The `session_diagnostic.py` (SessionStart) does not read from stdin at all —
it derives state from session files on disk. No confirmed schema for these events.

---

## Signals Safe for v1

These signals are confirmed available from the hook payload or derivable at hook time
without additional infrastructure:

| Signal | Source | How to read it |
|--------|--------|---------------|
| **Tool name** | PreToolUse / PostToolUse stdin | `data.tool_name` |
| **File path being edited** | PreToolUse stdin (Write/Edit/Read) | `data.tool_input.file_path` |
| **File extension** | Derived from file path | `path.extname(data.tool_input.file_path)` |
| **Bash command string** | PreToolUse stdin (Bash) | `data.tool_input.command` |
| **Working directory** | All events stdin | `data.cwd` |
| **Session ID** | All events stdin | `data.session_id` |
| **Context window %** | StatusLine stdin only | `data.context_window.remaining_percentage` |
| **Context % (in other hooks)** | Bridge file written by statusLine | Read `/tmp/claude-ctx-{session_id}.json` |
| **Stop reason** | Stop event stdin | `data.stop_reason` |
| **Is subagent** | PreToolUse stdin | `data.session_type === 'task'` |
| **Content being written** | PreToolUse stdin (Write) | `data.tool_input.content` |
| **Replacement string** | PreToolUse stdin (Edit) | `data.tool_input.new_string` |

### Context % Bridge Pattern (recommended for PostToolUse/Stop hooks)

The statusLine hook runs before every render and writes a bridge file. Other hooks
read it to get the context percentage without needing it in their own payload:

```python
# In any hook that knows session_id:
import json, os, tempfile, pathlib
bridge = pathlib.Path(tempfile.gettempdir()) / f"claude-ctx-{session_id}.json"
if bridge.exists():
    metrics = json.loads(bridge.read_text())
    remaining_pct = metrics["remaining_percentage"]  # float
    used_pct = metrics["used_pct"]                   # int, 0-100, normalized
```

The `used_pct` field is already normalized to the usable context range (excludes
the ~16.5% autocompact buffer), so 100% = context exhausted.

---

## Signals Deferred to v2

These signals are NOT available in the raw hook payload and require additional
infrastructure to support:

| Signal | Status | Reason |
|--------|--------|--------|
| `CLAUDE_CONTEXT_PCT` env var | Not available | No env vars are injected. Use bridge file pattern above. |
| Tool output / stdout of last Bash command | Not observed in payload | PostToolUse payload does not include the tool's return value. |
| Tool error flag (`is_error`) | Not in hook payload | `is_error` appears in JSONL transcript files (`projects/*/**.jsonl`) but NOT in the hook stdin JSON. |
| Stack trace / error text | Not in hook payload | Must mine the JSONL transcript (`~/.claude/projects/**/*.jsonl`) post-session. |
| Number of tool errors in current turn | Not in hook payload | Derivable only from session state file accumulated across turns. |
| Last-edited file extension as env var | Not available | Derive from `data.tool_input.file_path` in PreToolUse/PostToolUse instead. |
| Claude's current model in PreToolUse | Not in non-statusLine payloads | Only confirmed available in the statusLine payload (`data.model.display_name`). |

---

## Notes

### Hook Output: How to Inject Messages Back to Claude

A hook can inject text into Claude's next prompt by writing JSON to stdout:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "Your advisory message here."
  }
}
```

Use `"PostToolUse"` or `"PreToolUse"` as the `hookEventName` value depending on
the event. This works for advisory warnings. To hard-block, exit with code 2 (prompts
user for confirmation) or code 1 (hard fail with error).

**stdout vs stderr:** Any text printed to stdout that is NOT valid JSON will corrupt
the hook channel. Always print human-readable warnings to stderr, structured JSON to
stdout. Silent `exit(0)` is the correct default when there is nothing to report.

### Async vs Sync — The Critical Rule

- Sync hooks (no `async` field): stdout is injected as `additionalContext`.
- Async hooks (`"async": true`): stdout is silently discarded. Use only for side-effects
  (file writes, telemetry). A previous bug in this codebase had all Stop hooks marked
  async, silently killing the entire nudge system for multiple sessions.

### Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Success, proceed normally |
| `1` | Error — Claude shows an error message, tool may be blocked |
| `2` | Block + prompt user — Claude asks the user whether to proceed (used for guardrails) |

### Windows-Specific Notes

- Stdin may not close promptly on Windows/Git Bash. Production hooks use a 3-10 second
  `setTimeout(() => process.exit(0), ...)` guard to prevent indefinite hanging.
- Use `process.stdout.write(JSON.stringify(data))` — never `console.log` — to keep
  output on a single line without a trailing newline that might break JSON parsing.
- Route logs to stderr or to file. ANSI codes in stdout corrupt the JSON stream.

### JSONL Transcript (for post-hoc analysis only)

The full conversation, including tool results with `is_error` flags, is written to
JSONL files at `~/.claude/projects/<project-hash>/<session-id>.jsonl`. This is useful
for post-session analysis (e.g., `auto_eureka.py` mines it for correction events) but
is NOT available to hooks at hook execution time.

---

# Hook API Research — Gemini CLI

Researched from the installed `@google/gemini-cli@0.34.0` npm package source
(`~/.gemini/settings.json`, `gemini-cli-core` TypeScript declarations, and compiled JS).
All findings are derived from the installed package at:
`%APPDATA%\npm\node_modules\@google\gemini-cli\`

## Installed: yes

Version `0.34.0` is installed globally via npm. The `gemini` binary is NOT on `PATH`
(not symlinked into the npm bin directory that is on PATH), but the package is fully
present and resolvable. `~/.gemini/` directory exists with `settings.json` and `GEMINI.md`.

---

## Available Events

Gemini CLI has a full hook system. Event names come from the `HookEventName` enum in
`gemini-cli-core/dist/src/hooks/types.d.ts`:

| Event | When it fires | Can block? | Key stdin fields (beyond base) |
|-------|--------------|------------|-------------------------------|
| `BeforeTool` | Before any tool executes | Yes — exit 2+ = deny/block | `tool_name`, `tool_input`, `mcp_context?`, `original_request_name?` |
| `AfterTool` | After any tool returns | Advisory (can inject context) | `tool_name`, `tool_input`, `tool_response` |
| `BeforeAgent` | Before the agent loop starts a turn | Yes | `prompt` |
| `AfterAgent` | After agent turn completes | Yes (can clear context) | `prompt`, `prompt_response`, `stop_hook_active` |
| `SessionStart` | On session open (startup, resume, or clear) | Yes | `source` (enum: `startup` / `resume` / `clear`) |
| `SessionEnd` | On session close | No | `reason` (enum: `exit` / `clear` / `logout` / `prompt_input_exit` / `other`) |
| `PreCompress` | Before context compression | Advisory | `trigger` (enum: `manual` / `auto`) |
| `BeforeModel` | Before every LLM API call | Yes (can inject synthetic response) | `llm_request` (full LLM request object) |
| `AfterModel` | After every LLM API response | Yes (can modify response) | `llm_request`, `llm_response` |
| `BeforeToolSelection` | Before the model selects which tools to use | Yes (can modify tool config) | `llm_request` |
| `Notification` | On system notifications (e.g., tool permission prompts) | Advisory | `notification_type`, `message`, `details` |

Gemini CLI has **11 events** vs Claude Code's **5 events + statusLine**.
Notable additions: `BeforeAgent`, `AfterAgent`, `PreCompress`, `BeforeModel`,
`AfterModel`, `BeforeToolSelection`, `Notification`.

### Hook Definition Format in settings.json

Hooks are registered under a `"hooks"` key in `~/.gemini/settings.json` (user-level)
or in a project-level `GEMINI.md`-adjacent settings file. The schema mirrors Claude Code:

```json
{
  "hooks": {
    "BeforeTool": [
      {
        "matcher": "write_file|read_file",
        "sequential": false,
        "hooks": [
          {
            "type": "command",
            "command": "python /path/to/hook.py",
            "timeout": 30000,
            "env": { "MY_VAR": "value" }
          }
        ]
      }
    ],
    "AfterAgent": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "node /path/to/nudge.js"
          }
        ]
      }
    ]
  },
  "enableHooks": true
}
```

**Key differences from Claude Code format:**
- The `"sequential"` field is supported at the group level (Claude Code does not have this)
- The `"env"` field is supported per hook entry (custom env vars merged into the hook process env)
- `"enableHooks": true` must be set in settings.json for hooks to fire (explicit opt-in)
- No `"async"` field — Gemini CLI hooks are synchronous by default

**Hook type options:**
- `"type": "command"` — shell command hook (equivalent to Claude Code `command` type)
- `"type": "runtime"` — programmatic JS function hook (internal use only, not settable via JSON)

### Matcher Field

The `matcher` string is applied to `tool_name` for `BeforeTool`/`AfterTool` events, and
to the `trigger` or `source` field for lifecycle events. It is a regex string.
For events that have no natural matcher (e.g., `AfterAgent`), omit the `matcher` field.

---

## Available Environment Variables

### Gemini-Injected Variables (always set in hook process env)

| Variable | Description |
|----------|-------------|
| `GEMINI_PROJECT_DIR` | Absolute path to the CWD at hook execution time (same value as `cwd` in stdin JSON) |
| `CLAUDE_PROJECT_DIR` | Same value as `GEMINI_PROJECT_DIR` — set explicitly for cross-CLI compatibility |

**Source:** `hookRunner.js` lines 232–236:
```js
const env = {
    ...sanitizeEnvironment(process.env, this.config.sanitizationConfig),
    GEMINI_PROJECT_DIR: input.cwd,
    CLAUDE_PROJECT_DIR: input.cwd,  // For compatibility
    ...hookConfig.env,              // Per-hook custom env vars (from settings.json)
};
```

### Environment Sanitization

Gemini CLI runs all hook processes with a **sanitized copy of the parent env** — secrets
and credentials are stripped before the hook sees them. The sanitization rules are:

**Always passed through:**
`PATH`, `SYSTEMROOT`, `COMSPEC`, `PATHEXT`, `WINDIR`, `TEMP`, `TMP`, `USERPROFILE`,
`SYSTEMDRIVE`, `HOME`, `LANG`, `SHELL`, `TMPDIR`, `USER`, `LOGNAME`, `TERM`, `COLORTERM`

**Always stripped (by name pattern):**
Any env var whose name matches: `TOKEN`, `SECRET`, `PASSWORD`, `PASSWD`, `KEY`, `AUTH`,
`CREDENTIAL`, `CREDS`, `PRIVATE`, `CERT` (case-insensitive regex)

**Always stripped (by name):**
`CLIENT_ID`, `DB_URI`, `CONNECTION_STRING`, `AWS_DEFAULT_REGION`, `AZURE_CLIENT_ID`,
`AZURE_TENANT_ID`, `SLACK_WEBHOOK_URL`, `TWILIO_ACCOUNT_SID`, `DATABASE_URL`,
`GOOGLE_CLOUD_PROJECT`, `GOOGLE_CLOUD_ACCOUNT`, `FIREBASE_PROJECT_ID`

**Always stripped (by value pattern):**
PEM private keys, certificates, credential URLs, GitHub tokens, Google API keys,
AWS Access Key IDs, JWT tokens, Stripe keys, Slack tokens.

**Exception — never stripped regardless of name:**
Any env var whose name starts with `GEMINI_CLI_` is always passed through.

**Implication for Nudge hooks:** Do NOT rely on `GEMINI_API_KEY` being visible to a hook
script (it matches the `KEY` pattern and will be stripped). Pass any needed secrets via
the `"env"` field in the hook config in settings.json, or use the `GEMINI_CLI_` prefix
to force pass-through (e.g., `GEMINI_CLI_NUDGE_TOKEN`).

### Stdin JSON Payload — Base Fields (all events)

Every hook receives a JSON object on stdin. Common base fields on every event:

```jsonc
{
  "session_id": "abc-123-uuid",        // string — current session identifier
  "transcript_path": "/path/to/conv",  // string — path to the conversation transcript file
  "cwd": "/path/to/project",           // string — working directory at hook time
  "hook_event_name": "BeforeTool",     // string — the event that fired
  "timestamp": "2026-04-12T10:00:00Z"  // ISO 8601 timestamp
}
```

**Differences from Claude Code base payload:** Gemini CLI adds `transcript_path`,
`hook_event_name`, and `timestamp` to every event. Claude Code only provides `session_id`
and `cwd` in the base payload (other fields vary by event).

### Stdin JSON Payload — Per-Event Additional Fields

#### BeforeTool
```jsonc
{
  "tool_name": "write_file",
  "tool_input": { /* tool-specific args */ },
  "mcp_context": {                       // optional, only for MCP tools
    "server_name": "my-mcp",
    "tool_name": "actual_tool",
    "command": "...", "args": [...], "cwd": "...", "url": "...", "tcp": "..."
  },
  "original_request_name": "..."        // optional — original name before aliasing
}
```

#### AfterTool
```jsonc
{
  "tool_name": "write_file",
  "tool_input": { /* same as BeforeTool */ },
  "tool_response": { /* tool return value */ },   // ← PRESENT in Gemini, absent in Claude Code
  "mcp_context": { /* optional */ },
  "original_request_name": "..."
}
```

**Important:** `tool_response` IS available in the Gemini AfterTool payload. Claude Code
does NOT include the tool's return value in the PostToolUse stdin payload.

#### BeforeAgent / AfterAgent
```jsonc
// BeforeAgent
{ "prompt": "user message text" }

// AfterAgent
{
  "prompt": "user message text",
  "prompt_response": "model reply text",
  "stop_hook_active": false    // bool — whether a stop hook is currently suppressing output
}
```

#### SessionStart
```jsonc
{ "source": "startup" }  // enum: "startup" | "resume" | "clear"
```

#### SessionEnd
```jsonc
{ "reason": "exit" }  // enum: "exit" | "clear" | "logout" | "prompt_input_exit" | "other"
```

#### PreCompress
```jsonc
{ "trigger": "auto" }  // enum: "manual" | "auto"
```

#### BeforeModel / AfterModel / BeforeToolSelection
```jsonc
// BeforeModel / BeforeToolSelection
{ "llm_request": { /* decoupled LLM request object */ } }

// AfterModel
{
  "llm_request": { /* decoupled LLM request object */ },
  "llm_response": { /* decoupled LLM response object */ }
}
```

#### Notification
```jsonc
{
  "notification_type": "ToolPermission",   // only known type currently
  "message": "string",
  "details": { /* arbitrary object */ }
}
```

---

## Hook Output Format

Hook scripts write JSON to stdout. Gemini CLI parses it with the same exit-code logic as
Claude Code for plain-text fallback, but the structured JSON fields are richer:

```jsonc
{
  "continue": true,              // bool — whether to continue execution
  "stopReason": "...",           // string — reason if stopping
  "suppressOutput": false,       // bool — suppress this hook's output from UI
  "systemMessage": "...",        // string — message to show in CLI
  "decision": "allow",           // enum: "ask" | "block" | "deny" | "approve" | "allow"
  "reason": "...",               // string — reason for decision (shown to user)
  "hookSpecificOutput": {        // event-specific structured output
    "hookEventName": "BeforeTool",
    "tool_input": { /* modified tool input */ },      // BeforeTool: modify args
    "additionalContext": "...",                        // AfterTool/BeforeAgent/SessionStart
    "clearContext": true,                              // AfterAgent: clear conversation context
    "llm_request": { /* partial */ },                  // BeforeModel: modify request
    "llm_response": { /* partial */ },                 // AfterModel/BeforeModel: synthetic response
    "toolConfig": { /* modified tool config */ }       // BeforeToolSelection: change available tools
  }
}
```

### Exit Code Behavior (plain-text fallback)

| Exit Code | Meaning |
|-----------|---------|
| `0` | Success, allow (plain text output → systemMessage) |
| `1` | Non-blocking error (plain text → "Warning: <text>", still allows) |
| `2+` | Blocking deny (plain text → reason shown, execution stopped) |

---

## Differences from Claude Code

| Aspect | Claude Code | Gemini CLI |
|--------|-------------|------------|
| **Total events** | 5 + statusLine | 11 (no statusLine equivalent) |
| **Event names** | `SessionStart`, `SessionEnd`, `Stop`, `PreToolUse`, `PostToolUse` | `SessionStart`, `SessionEnd`, `BeforeAgent`, `AfterAgent`, `BeforeTool`, `AfterTool`, `BeforeModel`, `AfterModel`, `BeforeToolSelection`, `PreCompress`, `Notification` |
| **Name mapping** | `PreToolUse` | `BeforeTool` |
| **Name mapping** | `PostToolUse` | `AfterTool` |
| **Name mapping** | `Stop` | `AfterAgent` (closest equivalent) |
| **No equivalent** | `statusLine` | No built-in status bar hook |
| **No equivalent** | — | `BeforeModel`, `AfterModel`, `BeforeToolSelection`, `PreCompress`, `Notification` |
| **`tool_response` in AfterTool** | NOT present | PRESENT — tool output is in stdin payload |
| **`async` field** | Supported — silently discards stdout | Not supported — all hooks are synchronous |
| **Base stdin fields** | `session_id`, `cwd` (minimal) | `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `timestamp` |
| **Env var: project dir** | Not injected (derive from `cwd` in stdin) | `GEMINI_PROJECT_DIR` and `CLAUDE_PROJECT_DIR` both injected |
| **Env sanitization** | None documented | Active — strips credentials, API keys by pattern |
| **`GEMINI_CLI_` prefix** | N/A | Always passes through sanitization (safe prefix for custom vars) |
| **Opt-in required** | No (hooks fire if configured) | Yes — `"enableHooks": true` must be in settings.json |
| **Sequential execution** | Not configurable per-group | `"sequential": true` on a hook group runs hooks in order, passing modified input forward |
| **Settings file location** | `~/.claude/settings.json` | `~/.gemini/settings.json` |
| **Project-level hooks** | Supported (project `settings.json`) | Supported, but requires folder to be "trusted" |
| **Blocking decision field** | Exit code only (0/1/2) | Exit code OR `"decision": "deny"/"block"` in JSON output |

---

## Notes

### Cross-CLI Hook Compatibility

Gemini CLI explicitly sets `CLAUDE_PROJECT_DIR` as an alias for `GEMINI_PROJECT_DIR`
(source: `hookRunner.js:235`). This means a hook script that reads `CLAUDE_PROJECT_DIR`
will work under both CLIs without modification. The Nudge hook scripts that currently
read `CLAUDE_PROJECT_DIR` do NOT need changes for Gemini CLI compatibility.

### `tool_response` Availability

This is the most significant functional difference for Nudge hooks: Gemini CLI's
`AfterTool` payload includes `tool_response` (the full tool output). Claude Code's
`PostToolUse` does not. Nudge v2 hooks targeting Gemini can react to tool output
inline without the JSONL transcript mining workaround needed on Claude Code.

### No statusLine Equivalent

Gemini CLI has no equivalent to Claude Code's `statusLine` hook. The context window
percentage bridge pattern (`/tmp/claude-ctx-{session_id}.json`) used in Claude Code
does NOT apply to Gemini CLI. Use `BeforeModel` or `AfterModel` hooks to monitor
context state — the `llm_request` object includes the full message history.

### AfterAgent vs Stop

Claude Code's `Stop` event fires after each model response turn. Gemini CLI's closest
equivalent is `AfterAgent`, which fires after a full agent turn (which may include
multiple tool calls). `AfterAgent` also has `stop_hook_active` (bool) and the full
`prompt_response` string. It can trigger context clearing via `"clearContext": true`
in `hookSpecificOutput`.

### Trusted Folder Requirement for Project Hooks

Project-level hooks (hooks defined in a project directory) only fire if the folder is
in Gemini CLI's trusted folder list. User-level hooks in `~/.gemini/settings.json` are
not subject to this restriction.

### Env Var Naming Convention for Nudge

To safely pass custom variables to hook scripts under Gemini CLI without sanitization
stripping them, prefix them with `GEMINI_CLI_`:
```json
{
  "env": { "GEMINI_CLI_NUDGE_ENDPOINT": "http://localhost:3000" }
}
```
This prefix is whitelisted in `environmentSanitization.js` and bypasses all pattern checks.

### Source Files Inspected

- `%APPDATA%\npm\node_modules\@google\gemini-cli\node_modules\@google\gemini-cli-core\dist\src\hooks\types.d.ts`
- `%APPDATA%\npm\node_modules\@google\gemini-cli\node_modules\@google\gemini-cli-core\dist\src\hooks\hookRunner.js`
- `%APPDATA%\npm\node_modules\@google\gemini-cli\node_modules\@google\gemini-cli-core\dist\src\hooks\hookEventHandler.js`
- `%APPDATA%\npm\node_modules\@google\gemini-cli\node_modules\@google\gemini-cli-core\dist\src\hooks\hookRegistry.js`
- `%APPDATA%\npm\node_modules\@google\gemini-cli\node_modules\@google\gemini-cli-core\dist\src\services\environmentSanitization.js`
- `%APPDATA%\npm\node_modules\@google\gemini-cli\node_modules\@google\gemini-cli-core\dist\src\config\config.d.ts`
