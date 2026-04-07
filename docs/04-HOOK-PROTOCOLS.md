# AI Tool Hook Protocols — Reference

## Overview

CodeIsland communicates with Claude Code through its **hook system**. The bridge binary reads hook events from stdin and forwards them to the Unix socket.

---

## 1. Claude Code

### Configuration

File: `~/.claude/settings.json`

```json
{
  "hooks": {
    "{EventName}": [
      {
        "matcher": "*",
        "hooks": [
          {
            "command": "~/.claude/hooks/codeisland-hook.sh",
            "type": "command",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

Note: Claude Code uses the hook script (which dispatches to the bridge binary or nc fallback).

### Events

Claude Code registers 13 events in total:

| Event | Timeout | Async | Trigger |
|---|---|---|---|
| `UserPromptSubmit` | 5s | true | User sends message |
| `PreToolUse` | 5s | false | Before tool execution |
| `PostToolUse` | 5s | true | After tool execution succeeds |
| `PostToolUseFailure` | 5s | true | Tool execution failed |
| `PermissionRequest` | 86400s | false | AI needs permission (24h timeout for UI approval) |
| `PermissionDenied` | 5s | true | Permission was denied |
| `Stop` | 5s | true | AI stops generating (response complete) |
| `SubagentStart` | 5s | true | Subagent spawned |
| `SubagentStop` | 5s | true | Subagent completed |
| `SessionStart` | 5s | false | New session created |
| `SessionEnd` | 5s | true | Session terminated |
| `Notification` | 86400s | false | Notification with optional blocking question |
| `PreCompact` | 5s | true | Before context compaction |

### Stdin JSON Schema

Hooks receive stdin as JSON:

```json
{
  "session_id": "UUID",
  "hook_event_name": "UserPromptSubmit|PreToolUse|PostToolUse|...",
  "cwd": "/absolute/path",
  "model": "claude-opus-4-6",
  "tool_name": "Bash",
  "tool_input": { "command": "ls -la" },
  "tool_response": "file1.txt\nfile2.txt",
  "tool_use_id": "toolu_xxx",
  "prompt": "user's message",
  "message": "notification text",
  "agent_id": "agent_uuid",
  "agent_type": "Specialist",
  "question": "Do you approve?",
  "permission_mode": "auto|suggest|manual",
  "rate_limits": { "type": "token_based", "remaining": 12345 },
  
  "_source": "claude",
  "_ppid": 1234,
  "_term_app": "iTerm.app",
  "_term_bundle": "com.googlecode.iterm2",
  "_iterm_session": "w0t0p0:GUID",
  "_tty": "/dev/ttys001",
  "_kitty_window": "1",
  "_tmux": "session,0,0",
  "_tmux_pane": "%0",
  "_tmux_client_tty": "/dev/ttys001"
}
```

### Stdout Protocol (PermissionRequest & Notification only)

The hook can output JSON to stdout to influence behavior:

```json
{
  "hookSpecificOutput": {
    "decision": {
      "behavior": "allow",
      "reason": "Approved from CodeIsland"
    }
  }
}
```

| behavior | Effect |
|---|---|
| `"allow"` | Allow this one time |
| `"always"` | Allow and remember for session |
| `"deny"` | Deny the action |

If no stdout output or empty: Claude Code shows its normal prompt.

### Timeout Behavior

- Most events: 5 second timeout
- PermissionRequest / Notification: 86400 seconds (24 hours) — allows time for user interaction or async approval
- If timeout reached: hook is killed, Claude Code falls back to terminal prompt

---

## Bridge Implementation Guide

### Unified Event Format

The bridge reads stdin as JSON, enriches it with environment and terminal info, and sends it to the Unix socket:

```json
{
  "session_id": "string",
  "hook_event_name": "SessionStart|PreToolUse|PostToolUse|UserPromptSubmit|Stop|Notification|PermissionRequest|PermissionDenied|SubagentStart|SubagentStop|PreCompact",
  "cwd": "string?",
  "model": "string?",
  "tool_name": "string?",
  "tool_input": "object?",
  "tool_response": "string?",
  "prompt": "string?",
  "last_assistant_message": "string?",
  "message": "string?",
  "question": "string?",
  "permission_mode": "string?",
  "agent_id": "string?",
  "agent_type": "string?",
  
  "_source": "claude",
  "_ppid": "int (parent process PID)",
  "_term_app": "string? (TERM_PROGRAM)",
  "_term_bundle": "string? (__CFBundleIdentifier)",
  "_iterm_session": "string? (iTerm session GUID)",
  "_tty": "string? (TTY path like /dev/ttys001)",
  "_kitty_window": "string? (Kitty window ID)",
  "_tmux": "string? (TMUX env var)",
  "_tmux_pane": "string? (TMUX_PANE)",
  "_tmux_client_tty": "string? (TTY of tmux client)"
}
```

### Bridge Architecture

The bridge (codeisland-bridge binary):

1. Receives stdin as JSON from hook
2. Validates session_id (drops events without it)
3. Collects deep terminal environment (TERM_PROGRAM, ITERM_SESSION_ID, TMUX, etc.)
4. Detects TTY via POSIX open("/dev/tty") + ttyname(fd)
5. Enriches JSON with `_term_app`, `_term_bundle`, `_tty`, `_ppid`, `_source`, etc.
6. Connects to Unix socket `/tmp/codeisland-{uid}.sock`
7. Sends enriched JSON
8. For blocking events (PermissionRequest, Notification with question), waits for response and outputs to stdout
9. For non-blocking events, fire-and-forget with 3s socket timeout

### Terminal Environment Collection

The bridge collects these environment variables:

```
TERM_PROGRAM           → _term_app
__CFBundleIdentifier   → _term_bundle
ITERM_SESSION_ID       → _iterm_session (extract GUID after ":")
KITTY_WINDOW_ID        → _kitty_window
TMUX                   → _tmux
TMUX_PANE              → _tmux_pane
```

### TTY Detection

```swift
func detectTTY() -> String {
    let fd = open("/dev/tty", O_RDONLY | O_NOCTTY)
    if fd >= 0 {
        if let name = ttyname(fd) {
            close(fd)
            return String(cString: name)  // e.g. "/dev/ttys001"
        }
        close(fd)
    }
    return ""
}
```

### Socket Communication

Bridge uses Unix domain sockets (AF_UNIX):

- Socket path: `/tmp/codeisland-{uid}.sock`
- Non-blocking connect with 3s timeout
- Send timeouts: 3s (non-blocking) or 86400s (blocking)
- Recv timeouts: 3s (non-blocking) or 86400s (blocking)
- Blocking events: wait for server response indefinitely (user interaction)
- Non-blocking events: fire-and-forget

### Permission & Question Handling

The HookServer detects blocking events:

**PermissionRequest:** Any `PermissionRequest` event
- Special case: if `tool_name` is "AskUserQuestion", route to QuestionBar
- Server waits for user interaction, sends response back through socket
- Bridge forwards response to stdout

**Notification with Question:** `Notification` events with non-empty `question` field
- Server waits for user response via QuestionBar
- Bridge forwards response to stdout

**Peer Disconnect Monitoring:** Server monitors if bridge process disconnects, which indicates user answered in terminal.

### Skip Conditions

Environment variable: `CODEISLAND_SKIP`

If set, the bridge exits immediately (code 0) without processing.

```bash
CODEISLAND_SKIP=1 {hook-command}  # Hook executes but bridge does nothing
```

### Debug Logging

Set `CODEISLAND_DEBUG` environment variable:

```bash
CODEISLAND_DEBUG=1 {hook-command}
```

Log file: `/tmp/codeisland-bridge.log`

Log format:
```
[2026-04-07T12:34:56Z] event=Stop session=uuid1 permission=false question=false
```

---

## Hook Script (Claude Code)

File: `~/.claude/hooks/codeisland-hook.sh`

The hook script is a dispatcher that:

1. Attempts to execute the bridge binary (`~/.claude/hooks/codeisland-bridge`)
2. Falls back to shell + nc (netcat) if bridge is not available
3. Reads stdin JSON and enriches with terminal info
4. Sends to Unix socket

```bash
#!/bin/bash
# CodeIsland hook v3 — native bridge with shell fallback
BRIDGE="$HOME/.claude/hooks/codeisland-bridge"
if [ -x "$BRIDGE" ]; then
  "$BRIDGE" "$@"
  exit $?
fi
# Fallback: nc (netcat) approach with basic env collection
SOCK="/tmp/codeisland-$(id -u).sock"
[ -S "$SOCK" ] || exit 0
INPUT=$(cat)
_ITERM_GUID="${ITERM_SESSION_ID##*:}"
TERM_INFO="\"_term_app\":\"${TERM_PROGRAM:-}\",\"_iterm_session\":\"${_ITERM_GUID:-}\",\"_tty\":\"$(tty 2>/dev/null || true)\",\"_ppid\":$PPID"
PATCHED="${INPUT%}},${TERM_INFO}}"
if echo "$INPUT" | grep -q '"PermissionRequest"'; then
  echo "$PATCHED" | nc -U -w 120 "$SOCK" 2>/dev/null || true
else
  echo "$PATCHED" | nc -U -w 2 "$SOCK" 2>/dev/null || true
fi
```

---

## Supported Sources

| Source | CLI | Config Path |
|---|---|---|
| `claude` | Claude Code | `~/.claude/settings.json` |

---

## Installation Strategy

ConfigInstaller (Sources/CodeIsland/ConfigInstaller.swift):

1. Creates hook directory: `~/.claude/hooks/`
2. Installs hook script: `~/.claude/hooks/codeisland-hook.sh`
3. Installs bridge binary: `~/.claude/hooks/codeisland-bridge`
4. Inserts hooks into `~/.claude/settings.json`

Repair (verifyAndRepair):
- Re-installs missing hooks
- Detects and upgrades stale hook script versions
- Ensures bridge binary is current

---

## Reference: Hook Event Data Payloads

### UserPromptSubmit

```json
{
  "hook_event_name": "UserPromptSubmit",
  "prompt": "user message",
  "cwd": "/path",
  "model": "claude-opus-4-6"
}
```

### PreToolUse

```json
{
  "hook_event_name": "PreToolUse",
  "tool_name": "Bash",
  "tool_input": { "command": "ls -la" },
  "cwd": "/path"
}
```

### PostToolUse

```json
{
  "hook_event_name": "PostToolUse",
  "tool_name": "Bash",
  "tool_response": "file1.txt\nfile2.txt",
  "cwd": "/path"
}
```

### Stop

```json
{
  "hook_event_name": "Stop",
  "last_assistant_message": "Here are the files...",
  "stop_reason": "end_turn|user|interrupted",
  "cwd": "/path"
}
```

### PermissionRequest

```json
{
  "hook_event_name": "PermissionRequest",
  "tool_name": "Bash",
  "tool_input": { "command": "rm -rf /" },
  "cwd": "/path"
}
```

Response (to stdout):
```json
{
  "hookSpecificOutput": {
    "decision": {
      "behavior": "allow|deny|always",
      "reason": "Approved by user"
    }
  }
}
```

### Notification (with optional question)

```json
{
  "hook_event_name": "Notification",
  "message": "Notification text",
  "question": "Do you want to proceed?",
  "cwd": "/path"
}
```

### SubagentStart

```json
{
  "hook_event_name": "SubagentStart",
  "agent_id": "agent_uuid",
  "agent_type": "Specialist",
  "cwd": "/path"
}
```

### SessionStart

```json
{
  "hook_event_name": "SessionStart",
  "session_id": "uuid",
  "cwd": "/path",
  "model": "claude-opus-4-6",
  "workspace_roots": ["/path"]
}
```

### SessionEnd

```json
{
  "hook_event_name": "SessionEnd",
  "session_id": "uuid"
}
```

---

## Troubleshooting

### Hook not firing

1. Check if config path exists: `~/.claude/settings.json`
2. Verify hook command is correct: `grep -r "codeisland" ~/.claude/settings.json`
3. Ensure bridge binary is executable: `ls -la ~/.claude/hooks/codeisland-bridge`
4. Check socket exists: `ls -la /tmp/codeisland-$(id -u).sock`
5. Enable debug logging: `CODEISLAND_DEBUG=1`
6. Check log: `tail /tmp/codeisland-bridge.log`

### Permission prompt not working

1. Verify PermissionRequest timeout is 86400 (24 hours)
2. Check HookServer is running (listening on socket)
3. Verify bridge is sending response to stdout
4. Check Claude Code terminal for permission prompt

### Terminal detection not working

1. Ensure `/dev/tty` is accessible
2. Check TTY detection: `tty` command in shell
3. For tmux: verify `TMUX` and `TMUX_PANE` env vars are set
4. For iTerm: verify `ITERM_SESSION_ID` includes colon separator
