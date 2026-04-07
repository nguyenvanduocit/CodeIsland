# CodeIsland — Architecture Deep Dive

## System Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         macOS System                                    │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │          CodeIsland App (Swift/SwiftUI, menu bar)               │   │
│  │                                                                  │   │
│  │  ┌─────────────────┐  ┌──────────────┐  ┌──────────────────┐   │   │
│  │  │  HookServer     │  │   AppState   │  │ SessionSnapshot  │   │   │
│  │  │  (NWListener on │  │  (in-memory  │  │  (pure reducer   │   │   │
│  │  │   unix socket)  │──│  sessions +  │──│   pattern)       │   │   │
│  │  └────────┬────────┘  │  UI state)   │  │                  │   │   │
│  │           │           └──────────────┘  └──────────────────┘   │   │
│  │  ┌────────▼──────────────────────────────────────────────────┐   │   │
│  │  │                Event Handler                               │   │   │
│  │  │  Routes via SessionSnapshot.source                        │   │   │
│  │  └──┬──────┬──────┬──────┬──────┬──────┬─────────────────────┘   │   │
│  │     │      │      │      │      │      │                         │   │
│  │  ┌──▼──┐┌──▼──┐┌──▼──┐┌──▼──┐┌──▼──┐┌──▼──────────────────┐    │   │
│  │  │Panel││Sound││Term-││Title││Perm-││QuestionCard         │    │   │
│  │  │View ││Mgr  ││inal ││Store││ission│                      │    │   │
│  │  │     │      │Activ.││     ││Queue │                      │    │   │
│  │  └─────┘└─────┘└─────┘└─────┘└─────┘└─────────────────────┘    │   │
│  │                                                                  │   │
│  │  ┌─────────────────────────────────────────────────────────┐    │   │
│  │  │    Process Monitoring (DispatchSource per session)      │    │   │
│  │  │    Tracks CLI process exit, grace period cleanup        │    │   │
│  │  └─────────────────────────────────────────────────────────┘    │   │
│  │                                                                  │   │
│  │  ┌─────────────────────────────────────────────────────────┐    │   │
│  │  │         PanelWindowController (NSWindow)                │    │   │
│  │  │  • Multi-display support via ScreenDetector             │    │   │
│  │  │  • NotchPanelView (SwiftUI content view)               │    │   │
│  │  │  • Screen-hop animation (18pt offset, 0.14s fade)      │    │   │
│  │  └─────────────────────────────────────────────────────────┘    │   │
│  │                                                                  │   │
│  │  ┌─────────────────────────────────────────────────────────┐    │   │
│  │  │         Data Persistence & Discovery                   │    │   │
│  │  │  • SessionPersistence → ~/.codeisland/sessions.json    │    │   │
│  │  │  • SessionTitleStore (Claude title lookup)             │    │   │
│  │  │  • TerminalVisibilityDetector (smart suppress)         │    │   │
│  │  │  • ConfigInstaller (hook setup for Claude Code)        │    │   │
│  │  └─────────────────────────────────────────────────────────┘    │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │                    Data Flow Channel                             │    │
│  │                                                                  │    │
│  │  Channel 1: CLI Hook Bridge (codeisland-bridge binary)          │    │
│  │  ┌──────────┐    stdin     ┌─────────────┐   unix    ┌──────┐  │    │
│  │  │Claude    │───(JSON)───>│codeisland-   │──socket──>│Hook  │  │    │
│  │  │Code      │             │bridge        │   IPC     │Server│  │    │
│  │  │          │             │--source      │           │      │  │    │
│  │  │          │             │claude        │           │      │  │    │
│  │  └──────────┘             └─────────────┘           └──────┘  │    │
│  └─────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘
```

## Component Deep Dive

### 1. HookServer (Main IPC Listener)

The core IPC mechanism using Network.framework's `NWListener` on a Unix domain socket.

**Location:** `HookServer.swift`

**Behavior:**
- Listens on `SocketPath.path` (resolves to `/tmp/codeisland-{UID}.sock`)
- Uses `NWProtocolTCP.Options()` over Unix domain endpoints
- Accepts multiple concurrent connections via `newConnectionHandler`
- Receives data recursively until EOF or error
- Enforces 1MB maximum payload size safety limit
- Handles two event types:
  - **Fire-and-forget:** Parse JSON, route to `AppState.handleEvent()`, return `{}`
  - **Request-response:** PermissionRequest or Notification-wrapped questions
    - Hold connection open via peer-disconnect monitor
    - Resume when user approves/denies
    - Send JSON response then close

**Protocol:**
- Client connects → writes complete JSON → for requests: waits for response → closes
- For permission/question: server holds until `AppState.handlePermission*()` continuation completes

**Key Methods:**
- `receiveAll(connection:accumulated:)`: Recursive data accumulation (avoids buffer size limits)
- `monitorPeerDisconnect(connection:sessionId:)`: Detects bridge disconnect (user answered in terminal)
- `processRequest(data:connection:)`: Event routing with source validation

### 2. AppState (Session & Request Management)

The central state machine holding all session state and request queues.

**Location:** `AppState.swift`

**Core State:**
```swift
var sessions: [String: SessionSnapshot] = [:]      // keyed by session ID
var activeSessionId: String?
var permissionQueue: [PermissionRequest] = []      // FIFO queue
var questionQueue: [QuestionRequest] = []          // FIFO queue
var surface: IslandSurface = .collapsed            // UI surface enum
var rotatingSessionId: String?                     // mascot rotation
```

**Session Lifecycle:**
- `SessionStart` event → create SessionSnapshot
- `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, etc. → update session.status
- `Stop` event → set status to `.idle`
- Cleanup timer (60s): Remove orphaned processes, reset stuck sessions, timeout idle sessions
- Process monitor: DispatchSource tracks CLI process exit → grace period (5s) → remove if no activity

**Request Handling:**
- `handlePermissionRequest()`: Add to queue, show UI, resume continuation on user decision
- `handleQuestion()`: Add to question queue, show question bar, resume on answer
- `handlePeerDisconnect(sessionId:)`: Bridge disconnected — user answered in terminal, drain queues

**State Refresh:**
- `refreshDerivedState()`: Updates UI (surface changes, session visibility)
- `startRotationIfNeeded()`: Rotate mascot among active sessions (3s interval)

**Cleanup Timers:**
- Every 60s: Kill orphaned processes (parent PID ≤ 1), reset stuck sessions (processing >60s, others >180s)
- Remove idle sessions after user timeout (default 10 minutes)

### 3. SessionSnapshot (Pure Reducer Pattern)

The immutable session model — a pure struct representing one Claude Code session's state.

**Location:** `SessionSnapshot.swift` (CodeIslandCore)

**Core Fields:**
```swift
status: AgentStatus                           // idle, processing, running, waitingApproval, waitingQuestion
currentTool: String?                          // "bash", "python_interpreter", etc.
toolDescription: String?                      // human-readable tool purpose
lastActivity: Date                            // for cleanup timeouts
cwd: String?                                  // working directory
model: String?                                // "claude-opus-4-6", etc.
source: String                                // "claude"
termApp: String?                              // TERM_PROGRAM ("iTerm2", "Apple_Terminal", etc.)
termBundleId: String?                         // com.googlecode.iterm2 (more reliable)
itermSessionId: String?                       // iTerm2 unique session ID
ttyPath: String?                              // /dev/ttys001
kittyWindowId: String?                        // Kitty window ID
tmuxPane: String?                             // %0, %1 (tmux pane ID)
tmuxClientTty: String?                        // outer terminal TTY (for detection in tmux)
cliPid: pid_t?                                // Bridge _ppid (parent of Claude CLI process)
sessionTitle: String?                         // user-set or AI-generated title
sessionTitleSource: SessionTitleSource?       // claudeCustomTitle, claudeAiTitle
recentMessages: [ChatMessage]                 // last 3 messages for preview
toolHistory: [ToolHistoryEntry]              // recent tools used (max N)
subagents: [String: SubagentState]           // Claude sub-agents (Claude Code multi-agent)
isYoloMode: Bool?                             // nil=unchecked, false=not YOLO, true=YOLO
```

**Key Computed Properties:**
- `displayName`: Folder name from cwd (unless it's a timestamp, then parent)
- `shortModelName`: "opus", "sonnet", "haiku"
- `sourceLabel`: "Claude"
- `terminalName`: "iTerm2", "Terminal", "VS Code", "tmux" (from bundleId first, then TERM_PROGRAM)
- `isIDETerminal`: Boolean — true if running in VS Code / JetBrains / Xcode integrated terminal
- `subtitle`: cwd path (last 2 components) or model name

**Methods:**
- `addRecentMessage()`: Keep rolling window of last 3 messages
- `recordTool()`: Log tool execution (name, success, timestamp)

### 4. ConfigInstaller (Hook Lifecycle Management)

Installs, verifies, and repairs hooks for Claude Code.

**Location:** `ConfigInstaller.swift`

**Hook Paths:**
- Claude Code: `~/.claude/settings.json` → `hooks[eventName][].matcher` + `hooks[eventName][].hooks[].command`

**Bridge Installation:**
- Bridge binary: `~/.claude/hooks/codeisland-bridge` (auto-extracted from bundle)
- Hook script: `~/.claude/hooks/codeisland-hook.sh` (v3) — dispatcher with nc fallback

**Verification & Repair:**
- `verifyAndRepair()`: Re-installs missing hooks
- Detects stale "async" keys in legacy hook entries

### 5. TerminalActivator (Tab/Pane Activation)

Brings the correct terminal window/tab/pane to focus based on session info.

**Location:** `TerminalActivator.swift`

**Supported Activation Levels:**

**IDE Integrated Terminal:**
- VS Code, JetBrains, Xcode, Zed, Nova → activate IDE (no tab switching possible)

**Tab-Level Activation:**
- **iTerm2:** AppleScript with unique session ID or CWD title match
- **Terminal.app:** AppleScript matching TTY in selected tab
- **Ghostty:** AppleScript matching CWD in window title
- **WezTerm:** CLI `wezterm cli list/activate-tab` by TTY or CWD
- **kitty:** CLI `kitten @ focus-window/focus-tab` by window ID or CWD
- **tmux:** CLI `tmux select-window/select-pane` by pane ID (takes priority over terminal app)

**Fallback:**
- Unknown terminals: app-level activation via `open -a` or NSWorkspace

### 6. PanelWindowController (UI Window Management)

Creates and manages the borderless, click-through panel window.

**Location:** `PanelWindowController.swift`

**Window Type:** `KeyablePanel` (custom NSPanel subclass)
- `canBecomeKey = true` — allows first click to fire actions
- `NotchHostingView` wrapper — guards against SwiftUI constraint-update re-entrancy

**Multi-Display Support:**
- `ScreenDetector.preferredScreen` → selects screen with notch first, then main, then active window overlap
- Signature-based persistence — remembers position per screen config

**Screen Hop Animation:**
- 18pt offset (outgoing), 30pt offset (incoming)
- Fade out: 0.14s
- Pause: 0.06s
- Fade in: 0.34s

**Content View:** `NotchPanelView` (SwiftUI)
- Compact bar (minimal state)
- Session list (expanded)
- Approval card (permission decision UI)
- Question card (user input)
- Completion card (task finished notification)

### 7. ScreenDetector (Multi-Display Detection)

Detects screen notch, menu bar height, and preferred screen for panel placement.

**Location:** `ScreenDetector.swift`

**Notch Detection:**
- macOS 12+: `screen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea`
- Non-notch: Simulated width = screen width × 14% (160–240pt range)

**Menu Bar Height:**
- From `screen.frame.maxY - screen.visibleFrame.maxY`
- Fallback: 25pt (standard menu bar)

**Preferred Screen Selection:**
1. Check which screen contains the frontmost application window (highest overlap)
2. Fall back to screen with physical notch
3. Fall back to main screen

### 8. SoundManager (Event Audio Feedback)

Plays 8-bit WAV sound effects in response to hook events.

**Location:** `SoundManager.swift`

**Implementation:** Simple NSSound playback (not complex synthesis)

**Event-Sound Mapping:**
| Event | Sound File | Settings Key | Label |
|-------|-----------|--------------|-------|
| SessionStart | 8bit_start | soundSessionStart | 会话开始 |
| Stop | 8bit_complete | soundTaskComplete | 任务完成 |
| PostToolUseFailure | 8bit_error | soundTaskError | 任务错误 |
| PermissionRequest | 8bit_approval | soundApprovalNeeded | 需要审批 |
| UserPromptSubmit | 8bit_submit | soundPromptSubmit | 任务确认 |

**Features:**
- Pre-load all sounds on init (caching)
- Volume control via UserDefaults (0–100%)
- Boot sound on app launch
- Preview function for settings UI

### 9. SessionTitleStore (Title Resolution)

Resolves session titles from Claude Code.

**Location:** `SessionTitleStore.swift`

**Claude Titles:**
- Source: `~/.claude/projects/{projectDirEncoded}/{sessionId}.jsonl`
- Fields: `type: "custom-title"` or `type: "ai-title"`
- Priority: custom-title > ai-title
- Reads head + tail of file (efficient for large files)

**Session Title Source Enum:**
```
case claudeCustomTitle
case claudeAiTitle
```

### 10. TerminalVisibilityDetector (Smart Suppress)

Detects whether a session's terminal tab is currently visible (to avoid duplicate notifications).

**Location:** `TerminalVisibilityDetector.swift`

**Two Levels:**

**App-Level (Fast, Main Thread Safe):**
- Check if terminal's `bundleIdentifier` or app name matches frontmost application
- No AppleScript or subprocess calls

**Tab-Level (Slow, Background Thread Only):**
- **IDE terminals:** Return false (can't query tab state, show notification to be safe)
- **iTerm2:** AppleScript current session ID match
- **Ghostty:** System Events window title match (CWD in title)
- **Terminal.app:** AppleScript TTY match on selected tab
- **WezTerm:** CLI `wezterm cli list` for active pane by TTY/CWD
- **kitty:** CLI `kitten @ ls` for focused window by ID/CWD
- **tmux:** CLI `tmux display-message` current pane vs stored pane ID

**Usage in AppState:**
- Called before sending notifications to avoid showing notification when user is already viewing the terminal

### 11. NotchPanelView & IslandSurface

**IslandSurface Enum (UI State):**
```swift
case collapsed                               // Compact bar only
case sessionList                             // Expanded session list
case approvalCard(sessionId: String)         // Permission decision
case questionCard(sessionId: String)         // User question prompt
case completionCard(sessionId: String)       // Task completion notification
```

**NotchPanelView Components:**
- Compact bar: Rotating mascot, session count, active status indicator
- Session list: Scrollable list with tool info, status, terminal jump button
- Approval card: Allow/Deny buttons with permission description
- Question card: Text input (or yes/no buttons) for user response
- Completion card: "Task finished" notification with session name

**Mascot Views:** `BuddyView` (Claude), `MascotView`, `PixelCharacterView`

**Mascot Rotation:**
- Cycles through active sessions (non-idle) every 3 seconds
- Only if 2+ active sessions exist

### 12. L10n (Localization)

**Location:** `L10n.swift`

Provides Chinese (simplified) localization for UI strings.

**Supported Keys:**
- UI labels (session states, button texts, menu items)
- Sound event names (会话开始, 任务完成, 需要审批, etc.)
- Error messages, onboarding strings

### 13. UpdateChecker (Current Interim Auto-Update)

Interim solution pending Sparkle integration.

**Location:** `UpdateChecker.swift`

**Behavior:**
- Checks GitHub API (codeisland repository) for latest release
- Compares against bundled version
- Shows update notification if newer version available

**Future [Planned]:**
- Replace with Sparkle framework
- Check https://edwluo.github.io/code-island-updates/appcast.xml
- Auto-download + install every 6 hours (SUScheduledCheckInterval: 21600)

### 14. codeisland-bridge (CLI Hook Forwarder)

The native bridge binary replacing shell + nc for hook forwarding.

**Location:** `CodeIslandBridge/main.swift`

**Features:**
- Proper JSON parsing (no string manipulation)
- Deep terminal environment detection:
  - `_term_app` (TERM_PROGRAM env)
  - `_iterm_session` (ITERM_SESSION_ID)
  - `_tty` (tty path from /dev/tty)
  - `_ppid` (parent process ID)
  - tmux detection (`TMUX_PANE`, `TMUX`)
  - Ghostty detection
  - Kitty detection (`KITTY_WINDOW_ID`)
  - iTerm2 session ID extraction
- POSIX socket communication to HookServer
- Session ID validation (drops events without `session_id`)
- Timeout management (5–8s for non-blocking, no timeout for permission requests)
- `CODEISLAND_SKIP` env var support (skip event)
- Debug logging (`CODEISLAND_DEBUG=1` → `/tmp/codeisland-bridge.log`)
- Signal handling:
  - `SIGPIPE` ignored (broken pipe safety)
  - `SIGALRM` deadline enforcement (immediate exit if hung)

**Flow:**
1. Check CODEISLAND_SKIP env
2. Verify socket exists and is a socket (stat)
3. Read stdin with 5s timeout (alarm)
4. Parse JSON
5. Validate session_id
6. Arm timeout alarm (type-dependent)
7. Detect terminal environment
8. Connect to socket (3s non-blocking)
9. Send JSON + detected fields
10. Receive response
11. Output to stdout
12. Exit

### 15. Models & Structures (CodeIslandCore)

**Location:** `CodeIslandCore/Models.swift`

**Key Types:**
- `AgentStatus`: Enum with cases: `idle`, `processing`, `running`, `waitingApproval`, `waitingQuestion`
- `HookEvent`: Parsed hook event from bridge
- `PermissionRequest`: Queue item for approval UI
- `QuestionRequest`: Queue item for question UI
- `ToolHistoryEntry`: Recorded tool use (tool, description, timestamp, success, agent type)
- `SubagentState`: State of a Claude Code sub-agent
- `ChatMessage`: User/assistant message for preview

**Socket Path (SocketPath.swift):**
```swift
public static var path: String {
    "/tmp/codeisland-\(getuid()).sock"
}
```
Ensures per-user socket isolation via UID suffix.

---

## Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    Claude Code                               │
│                                                              │
│  User types prompt                                           │
│       ↓                                                      │
│  UserPromptSubmit hook fires                                 │
│       ↓                                                      │
│  bridge reads JSON from stdin                                │
│       ↓                                                      │
│  bridge detects: _term_app, _tty, _ppid, _iterm_session      │
│       ↓                                                      │
│  bridge connects to /tmp/codeisland-{UID}.sock               │
│       ↓                                                      │
│  HookServer receives JSON                                    │
│       ↓                                                      │
│  SessionSnapshot created/updated in AppState                │
│       ↓                                                      │
│  PanelWindowController updates UI                            │
│       ↓                                                      │
│  (if tool permission needed)                                 │
│  PermissionRequest hook fires                                │
│       ↓                                                      │
│  bridge sends JSON, holds connection open                    │
│       ↓                                                      │
│  HookServer stores pending in permissionQueue                │
│       ↓                                                      │
│  NotchPanel shows approval card                              │
│       ↓                         ← User clicks Allow ←─────   │
│  appState.handlePermissionRequest() completes continuation    │
│       ↓                                                      │
│  HookServer sends response to bridge                         │
│       ↓                                                      │
│  bridge outputs JSON to stdout                               │
│       ↓                                                      │
│  Claude Code reads response, proceeds with permission        │
│       ↓                                                      │
│  PreToolUse hook fires                                       │
│       ↓                                                      │
│  (same event flow as above, no wait)                         │
│       ↓                                                      │
│  Tool executes (bash, python_interpreter, etc.)              │
│       ↓                                                      │
│  PostToolUse hook fires                                       │
│       ↓                                                      │
│  Update UI: tool succeeded                                   │
│       ↓                                                      │
│  AI generates response                                       │
│       ↓                                                      │
│  Stop hook fires                                             │
│       ↓                                                      │
│  Update UI: "Waiting for input"                              │
│  Play sound (if enabled)                                     │
│  Send macOS notification (if terminal not visible)           │
│  Show completion card (if not auto-collapsed)                │
│       ↓                                                      │
│  User clicks session to jump to terminal                     │
│       ↓                                                      │
│  TerminalActivator.activate() runs appropriate mechanism     │
│       (iTerm AppleScript, kitty CLI, tmux, etc.)             │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Security Model

### Threat Surface

1. **Unix socket** (`/tmp/codeisland-{UID}.sock`): User-only permissions (`0700` default), but any process running as the same user can connect and inject fake events
2. **Bridge binary**: Runs with same user privileges, reads JSON from stdin
3. **Hook injection**: ConfigInstaller modifies `settings.json` — any process with file access can overwrite
4. **No encryption**: Socket communication is plaintext JSON (local only, acceptable)
5. **No authentication**: Socket has no per-connection auth (user-scoped permission is the boundary)

### Mitigations

- Socket is user-scoped via UID suffix (prevents cross-user injection)
- Bridge is minimal, simple forwarder (small attack surface)
- Payload size limit (1MB) prevents DoS via large JSON
- Session ID validation in bridge (drops malformed events early)
- Process monitor with grace period prevents session resource leaks
- Per-user socket ensures no privilege elevation possible

### Privacy Considerations

- **Event logging:** Bridge logs to `/tmp/codeisland-bridge.log` (only event names + session IDs, no content)
- **Session storage:** `~/.codeisland/sessions.json` contains:
  - Session metadata (ID, CWD, model, start time)
  - Recent messages (user prompts + AI responses, truncated)
  - Terminal info (bundle ID, TTY, tmux pane)
  - Tool history (tool names, success flags)
  - All stored **unencrypted** in JSON
- **No content exfiltration to remote servers** (only bundled analytics/telemetry if present)

---

## Planned Features

### Onboarding System [Planned]

Multi-step onboarding flow with demo and confetti.

### License & Trial System [Planned]

License key validation with 30-day trial.

### Advanced Sound System [Planned]

SoundPackStore, SoundSynthesizer, OutputDeviceObserver.

Current: Simple NSSound playback only.

### Sparkle Auto-Update [Planned]

Replace UpdateChecker (interim: GitHub API) with Sparkle framework.

---

## Session State Machine

```
                    [idle] ←──────────────────────┐
                    ↓ (SessionStart)               │
                    ↓                              │
        ┌───────────┴──────────────┐               │
        ↓                          ↓               │
   [processing]               [running]            │
   (thinking,                 (tool)               │
    generating)                                    │
        ↓                          ↓               │
        └───────────┬──────────────┘               │
                    ↓                              │
              [Stop event]                         │
                    ↓                              │
         ┌──────────┴────────────┐                 │
         ↓                       ↓                 │
   [idle]              [waitingApproval] (PermissionRequest)
                              ↓ (user approves)   │
                              ↓                   │
                         Continue → [processing]  │
                                                  │
[waitingQuestion] ← Notification + QuestionPayload
         ↓ (user answers)
         ↓
   Continue → [processing]
         
         (SessionEnd) ───────────────────→ [idle] (cleanup + remove)
```

---

## Socket Protocol

### Request (client → server)

```json
{
  "session_id": "abc123-def456",
  "hook_event_name": "UserPromptSubmit",
  "_source": "claude",
  "eventData": {
    "prompt": "user message"
  },
  "_term_app": "iTerm2",
  "_tty": "/dev/ttys001",
  "_ppid": 12345,
  "_iterm_session": "W0C604A0-1234-...",
  "additional": "fields..."
}
```

### Response (server → client)

**Fire-and-forget:**
```json
{}
```

**Permission/Question (after user decision):**
```json
{
  "hookSpecificOutput": {
    "decision": {
      "behavior": "allow"     // or "deny"
    }
  }
}
```

or for questions:

```json
{
  "answer": "yes"             // or user's text input
}
```

---

## Directory Structure

```
~/.codeisland/
  sessions.json              # Persisted SessionSnapshot list (JSON)

~/.claude/
  hooks/
    codeisland-hook.sh       # Hook dispatcher script (v3)
    codeisland-bridge        # Native bridge binary
  settings.json              # Contains hook entries

/tmp/
  codeisland-{UID}.sock      # Unix domain socket
  codeisland-bridge.log      # Debug log (CODEISLAND_DEBUG=1)
```
