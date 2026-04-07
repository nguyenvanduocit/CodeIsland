# CodeIsland — Product Requirements Document

## Vision

CodeIsland is an open-source macOS menu bar app that monitors Claude Code sessions in real-time, providing a unified dashboard, notification system, sound feedback, and remote permission approval — all through a sleek Dynamic Island-style notch panel.

**Inspired by**: CodeIsland (closed-source, paid)
**Goal**: Feature-complete open-source alternative for Claude Code users

---

## Target Users

- Developers using Claude Code
- Power users running multiple Claude Code sessions simultaneously across terminals
- Teams wanting visibility into Claude Code agent activity
- Developers on macOS 14+ (Sonoma and newer)

---

## Core Features

### Implemented Features

#### F1: Socket Server (IPC Core) — **[Implemented]**
- Unix domain socket at `/tmp/codeisland-{UID}.sock`
- NWListener (Network framework) for event ingestion
- Accept JSON messages from hook bridges
- Support fire-and-forget (event forwarding) and held-connection (permission/question approval) modes
- User-only permissions (0700)
- Payload safety: 1MB max, graceful error handling

**Status**: Production-ready. Socket auto-cleaned on app launch/shutdown.

---

#### F2: Hook Bridge CLI — **[Implemented]**
- Lightweight Swift CLI: `codeisland-bridge`
- Reads JSON from stdin (piped by Claude Code hooks)
- Forwards to Unix socket with 3-second non-blocking timeout
- Terminal environment detection: tmux, Kitty, iTerm2, Ghostty, Warp, WezTerm
- Session ID validation (drops events without it)
- CODEISLAND_SKIP env var support for selective suppression
- CODEISLAND_DEBUG env var for debug logging
- For PermissionRequest and questions: holds connection, waits for app response, outputs to stdout
- Signal safety: ignores SIGPIPE, has alarm deadline for stuck hangs
- Logs to `/tmp/codeisland-bridge.log` (when CODEISLAND_DEBUG set)

**Status**: Production-ready. Supports fire-and-forget and blocking modes.

---

#### F3: Session Tracking — **[Implemented]**
- Track all active Claude Code sessions
- Per-session data:
  - Session ID, CWD, source ("claude"), status (5 states), current tool, tool description
  - Model name, session title
  - Terminal info: bundleId, iTerm sessionId, TTY path, Kitty window ID, tmux pane, CLI PID
  - Last user prompt, last assistant message, recent chat preview (3 messages max)
  - Tool history (configurable max, default 20 entries)
  - Subagent states (agentId, agentType, status)
  - YOLO mode detection
  
- Persist to `~/.codeisland/sessions.json` (JSON format, no CoreData)
- Auto-cleanup: idle session timeout (default 10min), orphaned process cleanup, stuck session reset (60s for processing, 180s for long-running tools)

**Status**: Production-ready. SessionSnapshot is the core data model.

---

#### F5: Notch Panel (Dynamic Island) — **[Implemented]**
- Floating borderless NSPanel anchored to display notch (MacBook) or menu bar height (external displays)
- Multi-display support via ScreenDetector (picks notch-equipped display first, then main display)
- Two states via IslandSurface enum:
  - **Collapsed**: Compact bar showing mascot, session count, and status indicator
  - **Expanded**: Full session list with detailed information
  - **Approval card**: Permission approval interface (sessionId-bound)
  - **Question card**: User question prompt (sessionId-bound)
  - **Completion card**: Auto-shown success notification (sessionId-bound)
  
- Hover detection with configurable delay (prevents accidental triggers)
- Adaptive width based on screen geometry and session state
- Smooth SwiftUI animations between states
- Smart positioning: clamps to visible screen area, avoids overlapping content
- Responsive to mouse enter/exit and keyboard events

**Status**: Production-ready. Supports macOS 12+ (notch detection), falls back to simulated notch on non-notch screens.

---

#### F8: Terminal Tab Jumping — **[Implemented]**
- Click session → focus correct terminal window/tab
- Supports 10+ terminal emulators:
  - **Tab-level**: Ghostty, iTerm2, Terminal.app, WezTerm, kitty (AppleScript + OSC2 + direct activation)
  - **App-level**: Alacritty, Warp, Hyper, Tabby, Rio, cmux
  - **IDE integrated terminals**: VS Code, VSCodium, Windsurf, Codeium, JetBrains IDEs, Zed, Xcode, Nova, Android Studio (no tab-switching)
  - **Multiplexers**: tmux pane targeting, screen fallback
  
- Multi-method approach:
  - Bundle ID lookup (most accurate)
  - iTerm sessionId direct activation
  - TTY path matching for terminal tabs
  - Kitty window ID targeting
  - tmux pane selection
  - OSC2 title matching for Ghostty
  - Process detection fallback
  
- Requires Accessibility permission (requested at first launch)

**Status**: Production-ready. Handles edge cases: IDE terminals, tmux nesting.

---

#### F9: Permission Approval from UI — **[Implemented]**
- Approval card in Notch panel when permission requested
- Flow: Allow / Always / Deny buttons with confirmation
- Question flow: Display question with optional multi-choice options
- Context display: tool name, command/file, workspace context
- Send decision back through socket → bridge → Claude Code (JSON response format)
- Support Claude Code hook protocol (stdout JSON response)
- Integrated with AppState's permission queue and continuation-based response handling

**Status**: Production-ready. Handles both permission and question events.

---

#### F10: Sound Feedback — **[Implemented]**
- Play 8-bit WAV sounds on key events:
  - SessionStart (chime)
  - Stop/TaskComplete (success)
  - PostToolUseFailure (error)
  - PermissionRequest (approval alert)
  - UserPromptSubmit (confirm)
  - Boot sound on app launch
  
- 5 user-configurable event toggles + global master toggle
- Volume control (0–100, stored in UserDefaults)
- Per-event sound mute
- Pre-loaded sound cache for instant playback
- Smart suppression option (suppress probe/health-check sessions)
- SPM resource bundle integration (sounds in Resources/)

**Status**: Production-ready. NSSound-based playback.

---

### Partial Implementation

#### F4: Menu Bar App — **[Partial]**
- **Status**: LSUIElement-only (no menu bar icon)
- **Current approach**: Notch-only UI, no traditional menu bar presence
- **Why**: Notch panel is always visible and responsive; menu bar icon would be redundant
- **Future**: Can add menu bar icon + popover if requested, but currently not a priority

**Note**: App does not appear in Dock (LSUIElement = true). Access via: Spotlight search "CodeIsland" or click Notch panel.

---

#### F6: Auto-Configuration — **[Partial]**
- **Implemented**: Auto-install hooks to Claude Code on app launch
- **Hook format**: Claude Code nested format (matcher + hooks)
- **Not yet**: Visual setup wizard or onboarding flow
- **Current**: Silent install via ConfigInstaller.install() and periodic auto-repair

**Status**: Functional but minimal UI. Users don't see setup steps, hooks just appear.

---

#### F17: Themeable UI — **[Partial]**
- **Implemented**: System dark/light mode detection and automatic switching
- **Customizable**: Panel height, font size, content density
- **Settings UI**: Full settings window with 7 pages (General, Behavior, Appearance, Mascots, Sound, Hooks, About)
- **Not yet**: Custom accent colors, theme marketplace
- **Current**: Supports English and Chinese (simplified)

**Status**: Core UI theme support complete.

---

### Not Yet Implemented

#### F7: macOS Notifications — **[Planned]**
- Notify when AI session needs input (Stop event)
- Notify when permission approval needed
- Notify when AI asks a question
- Click notification → jump to correct terminal tab
- Notification grouping by session
- Note: Notch panel currently serves this purpose; notifications would be redundant but valuable for background notification center access

---

#### F11: StatusLine Integration — **[Planned]**
- Inject bash script into Claude Code's `statusLine.command`
- Extract rate_limits data from Claude Code's status JSON
- Display usage quotas in Notch panel (5h / 7d limits)
- Composable with user's existing statusLine scripts

---

#### F12: Keyboard Shortcuts — **[Planned]**
- Global hotkey to toggle Notch panel (e.g., ⌘⇧V)
- Global hotkey to jump to most recent active session
- Configurable via settings

---

#### F14: Session History — **[Planned]**
- Store completed sessions with summary
- Search past sessions by date or keywords
- View conversation highlights and tool usage stats
- Export session transcripts

---

#### F16: Custom Sound Packs — **[Planned]**
- Allow users to import custom sound pack ZIP files
- Sound pack marketplace (future)
- Community-submitted packs

---

#### License & Trial System — **[Planned]**
- License key validation
- 30-day trial period with watermark
- Prompt to purchase after trial expires

---

#### Onboarding Wizard — **[Planned]**
- Step-by-step setup flow on first launch
- Request Accessibility permission
- Preview and apply hook configuration
- Completion confirmation

---

#### Sentry Crash Reporting — **[Planned]**
- Automated crash collection
- Stack trace symbolication
- Optional opt-in privacy

---

#### Sparkle Auto-Update — **[Interim]**
- Currently uses UpdateChecker (GitHub API polling)
- Checks for new releases every app launch (silent check)
- Prompts user if update available
- Future: Replace with Sparkle framework for delta updates

---

### Removed Features

#### F15: Analytics Dashboard — **[Removed]**
- Original plan: Track sessions per day/week, tools used frequency, average session duration, permission approval rate
- **Reason**: Complexity without clear user demand; can be re-added as opt-in analytics later

---

## Technical Architecture

### Tech Stack

| Component | Technology |
|---|---|
| **App** | Swift 5.9+ / SwiftUI |
| **Min macOS** | 14.0 (Sonoma) — for SwiftUI stability and features |
| **UI Framework** | SwiftUI + AppKit (NSPanel, NSWindowController for borderless floating window) |
| **IPC** | Unix domain sockets (Network.framework NWListener/NWConnection) |
| **Bridge CLI** | Swift SPM executable, ~100KB binary |
| **Persistence** | JSON files (Foundation JSONEncoder/Decoder, no CoreData) |
| **Accessibility** | AXUIElement (ApplicationServices framework) |
| **Audio** | AppKit NSSound (WAV playback) |
| **Process Monitoring** | Darwin proc_pidinfo, DispatchSourceProcess for process lifetime tracking |
| **File Watching** | FSEvents (FSEventStreamRef) for config file changes |
| **Terminal Interaction** | AppleScript (iTerm2, Terminal.app), OSC2 sequences (Ghostty), direct process communication |
| **Auto-Update** | UpdateChecker with GitHub API (interim), planned Sparkle migration |
| **Crash Reporting** | None (open-source; GitHub issues as feedback mechanism) |
| **Build System** | Swift Package Manager (SPM 5.9), Xcode 15+ |
| **Third-Party Dependencies** | Zero (fully self-contained, native Apple frameworks only) |

---

### Project Structure

```
CodeIsland/
├── Sources/
│   ├── CodeIslandCore/              # Shared models (SPM target)
│   │   ├── Models.swift             # AgentStatus, HookEvent, SubagentState, ToolHistoryEntry
│   │   ├── SessionSnapshot.swift    # Core session data model
│   │   ├── SocketPath.swift         # Socket path constant
│   │   └── ChatMessageTextFormatter.swift
│   │
│   ├── CodeIsland/                  # Main app (SPM executable target)
│   │   ├── CodeIslandApp.swift      # @main, minimal SwiftUI app wrapper
│   │   ├── AppDelegate.swift        # NSApplicationDelegate, lifecycle management
│   │   ├── AppState.swift           # Observable app state, session management
│   │   ├── HookServer.swift         # Unix socket listener (NWListener)
│   │   ├── SessionPersistence.swift # Load/save sessions to JSON
│   │   │
│   │   ├── IslandSurface.swift      # Surface state enum (collapsed, sessionList, approvalCard, etc.)
│   │   ├── PanelWindowController.swift  # NSPanel lifecycle, window positioning
│   │   ├── ScreenDetector.swift     # Notch detection, multi-display support
│   │   ├── NotchPanelView.swift     # Main SwiftUI view
│   │   ├── NotchAnimation.swift     # Animation presets
│   │   ├── TerminalActivator.swift  # Terminal tab jumping coordinator
│   │   ├── TerminalVisibilityDetector.swift  # Terminal state detection
│   │   │
│   │   ├── BuddyView.swift          # Claude mascot view
│   │   ├── MascotView.swift
│   │   ├── PixelCharacterView.swift
│   │   │
│   │   ├── SettingsView.swift       # Settings window (7 pages)
│   │   ├── Settings.swift           # SettingsManager, SettingsKey constants
│   │   ├── SettingsWindowController.swift
│   │   ├── L10n.swift               # Localization manager
│   │   │
│   │   ├── SoundManager.swift       # Event sound coordinator
│   │   ├── ConfigInstaller.swift    # Hook installation for Claude Code
│   │   ├── SessionTitleStore.swift  # Session title persistence
│   │   ├── UpdateChecker.swift      # GitHub releases polling
│   │   ├── DebugHarness.swift       # Preview mode for development
│   │   └── Resources/               # SPM resource bundle
│   │       └── Resources/*.wav      # 8-bit sounds
│   │
│   └── CodeIslandBridge/            # Bridge CLI (SPM executable target)
│       └── main.swift               # Bridge entry point, socket communication
│
├── Tests/
│   ├── CodeIslandCoreTests/
│   │   ├── SessionSnapshotTitleTests.swift
│   │   ├── ChatMessageTextFormatterTests.swift
│   │   ├── DerivedSessionStateTests.swift
│   │   └── ...
│   │
│   └── CodeIslandTests/
│       ├── PanelWindowControllerTests.swift
│       ├── ScreenDetectorTests.swift
│       ├── SessionTitleStoreTests.swift
│       └── ...
│
├── Package.swift                    # SPM package definition (3 targets, 0 external deps)
├── Info.plist                       # App metadata (LSUIElement=true, version 1.0.6)
├── Assets.xcassets/                 # App icon
├── build.sh                         # Build script
└── install.sh                       # Installation script
```

---

### Data Models

#### AgentStatus (5 states)
```swift
public enum AgentStatus {
    case idle
    case processing
    case running
    case waitingApproval
    case waitingQuestion
}
```

#### SessionSnapshot (Core session data)
```swift
public struct SessionSnapshot {
    // Status & activity
    var status: AgentStatus
    var currentTool: String?
    var toolDescription: String?
    var lastActivity: Date
    
    // Workspace context
    var cwd: String?
    var model: String?
    
    // Content
    var lastUserPrompt: String?
    var lastAssistantMessage: String?
    var recentMessages: [ChatMessage]  // Max 3
    
    // Terminal info (for tab jumping)
    var termApp: String?
    var itermSessionId: String?
    var ttyPath: String?
    var kittyWindowId: String?
    var tmuxPane: String?
    var tmuxClientTty: String?
    var termBundleId: String?
    var cliPid: pid_t?
    
    // Identity
    var source: String  // "claude"
    var sessionTitle: String?
    var sessionTitleSource: SessionTitleSource?
    var providerSessionId: String?
    
    // Tool tracking
    var toolHistory: [ToolHistoryEntry]  // Max 20 configurable
    var subagents: [String: SubagentState]
    var isYoloMode: Bool?
}
```

#### HookEvent (Incoming from bridge)
```swift
public struct HookEvent {
    let eventName: String
    let sessionId: String?
    let toolName: String?
    let agentId: String?
    let toolInput: [String: Any]?
    let rawJSON: [String: Any]  // Full payload
}
```

#### ToolHistoryEntry
```swift
public struct ToolHistoryEntry: Identifiable {
    let id = UUID()
    let tool: String
    let description: String?
    let timestamp: Date
    let success: Bool
    let agentType: String?  // nil = main thread
}
```

---

### Supported AI Source

**claude** — Claude Code (CLI)

- Config file: `~/.claude/settings.json`
- Events via the codeisland-bridge binary
- Hook script dispatcher: `~/.claude/hooks/codeisland-hook.sh`

---

### Supported Terminals (10+)

**Tab-level switching** (most precise):
- Ghostty (OSC2 + direct activation)
- iTerm2 (AppleScript + sessionId)
- Terminal.app (AppleScript)
- WezTerm (tab targeting)
- kitty (window ID targeting)

**App-level switching** (whole app focus):
- Alacritty
- Warp
- Hyper
- Tabby
- Rio
- cmux

**IDE terminals** (IDE focus, no tab switching):
- VS Code / VSCodium
- Windsurf
- Codeium
- JetBrains IDEs
- Zed
- Xcode
- Nova
- Android Studio

**Multiplexers**:
- tmux (pane targeting)
- screen

---

## Key Design Decisions

### 1. LSUIElement-Only Approach
**Decision**: No menu bar icon; Notch panel is the sole UI.
**Rationale**: Notch is always visible and responsive. Menu bar icon would clutter the menu bar and be redundant for power users. Accessibility via Spotlight ("CodeIsland") is sufficient.

### 2. Socket-Based IPC Over HTTP
**Decision**: Unix domain sockets (NWListener) instead of HTTP server.
**Rationale**: Lower overhead, per-user namespace isolation (socket at `/tmp/codeisland-{UID}.sock`), no port conflicts, perfect for local IPC on a single machine.

### 3. Zero External Dependencies
**Decision**: All Apple frameworks, no third-party packages.
**Rationale**: Reduces attack surface, no dependency version conflicts, easier cross-version macOS support, smaller binary size.

### 4. Fire-and-Forget + Held Connection Pattern
**Decision**: Bridge uses two modes: async events (fire-and-forget) and blocking events (permission/question hold connection until answer).
**Rationale**: Minimal bridge complexity, minimal Claude Code changes, natural request-response for approvals without requiring HTTP polling.

### 5. Process Monitoring for Smart Cleanup
**Decision**: Track terminal process PIDs; auto-kill orphaned Claude processes; auto-timeout stuck sessions.
**Rationale**: Handles terminal crashes gracefully; prevents stale session accumulation.

### 6. Multi-Method Terminal Tab Jumping
**Decision**: Bundle ID lookup → TTY matching → OSC2 → process detection fallback.
**Rationale**: Different terminals expose session info differently. Multiple fallbacks ensure high success rate.

### 7. Flat Project Structure (No Deep Layers)
**Decision**: All code in `CodeIsland/` and `CodeIslandCore/` targets; no domain layer, service layer, repository pattern.
**Rationale**: Single-purpose app, minimal coupling, code is colocated by feature, easy to find and modify.

### 8. SessionSnapshot as Single Source of Truth
**Decision**: One mutable struct shared across AppState, UI, and persistence.
**Rationale**: No synchronization overhead, mutations are explicit, easy to debug state changes.

---

## Open-Source Considerations

### Why Open Source?
- **User trust**: Closed-source AI monitoring tool raises privacy concerns. Open source = verifiable.
- **Community extensibility**: Users can add support for new terminals via PRs.
- **No vendor lock-in**: Users can fork and self-host if needed.
- **Learning resource**: Clean Swift/SwiftUI codebase for macOS developers.

### License
- **MIT License** — permissive, allows commercial use with attribution.
- No external copyleft dependencies (enables MIT licensing).

### Community Contribution Paths
1. **New terminal support**: Add to TerminalActivator's knownTerminals list and implement activation method.
2. **New UI themes**: Update SettingsView appearance toggles.
3. **New sound packs**: Contribute WAV files to Resources/.
4. **Translations**: Add language entries to L10n.swift.

### Self-Hosting
- Binary distributable as `.app` bundle or via Homebrew formula.
- No server backend required; runs purely on-device.
- Users can build from source and codesign with their own cert.

---

## Success Metrics

### User Adoption
- GitHub stars / community forks
- Monthly active users (tracked via build downloads and optional telemetry)
- User-contributed PRs and issues

### Reliability
- <0.1% socket connection failure rate (with auto-repair)
- Session tracking accuracy: 99%+ (all active sessions detected, no false negatives)
- Terminal jumping success: >95% across supported terminals
- Crash rate: <0.01% (open-source, user reports via GitHub)

### Performance
- App memory footprint: <50 MB (typical; peaks <100 MB during large session lists)
- Socket latency: <100ms avg (from bridge write to app response)
- UI frame rate: 60 FPS (smooth animations, no jank)
- Startup time: <2 seconds

---

## Build & Release Workflow

### Build
```bash
./build.sh
# Outputs: .build/release/CodeIsland.app
```

### Install (User)
```bash
./install.sh
# Copies app to /Applications, sets up Launch Agent, installs codeisland-bridge
```

### Test
```bash
swift test
# Runs CodeIslandCoreTests and CodeIslandTests
```

### Type Check
```bash
swift build --configuration release
# Ensures no compilation errors
```

### Version Management
- Current version: 1.0.6 (in Info.plist)
- Semver: MAJOR.MINOR.PATCH
- Release notes on GitHub Releases page
- Auto-check for updates at app launch (UpdateChecker)

---

## Roadmap (Future Phases)

### Phase 2 (Q2 2026)
- [ ] F7: macOS Notifications
- [ ] F12: Keyboard Shortcuts (global hotkeys)
- [ ] Session History backend
- [ ] Settings import/export

### Phase 3 (Q3 2026)
- [ ] F11: StatusLine Integration (Claude Code rate limits)
- [ ] F14: Session History UI + search
- [ ] Sparkle auto-update migration
- [ ] Crash reporting (optional Sentry)

### Phase 4 (Q4 2026)
- [ ] F16: Custom sound packs
- [ ] License & trial system (if commercialization decision made)
- [ ] Onboarding wizard UI
- [ ] macOS 15+ optimizations

---

## Testing Strategy

### Test Files
- `CodeIslandCoreTests/`: SessionSnapshot title logic, chat formatting
- `CodeIslandTests/`: PanelWindowController positioning, ScreenDetector multi-display, SessionTitleStore persistence

### Manual Testing Checklist
- [ ] Socket server: starts, stops, handles stale cleanup
- [ ] Bridge: sends events, receives permission responses, handles disconnects
- [ ] Session tracking: creates, updates, persists, cleans up
- [ ] Notch panel: appears on correct display, responds to hover, animates smoothly
- [ ] Terminal jumping: focus correct terminal/tab (test all 10+ supported)
- [ ] Permission approval: displays card, sends response, clears on disconnect
- [ ] Sound feedback: plays correct sound for each event, respects mute settings
- [ ] Settings: all toggles/sliders work, persist across app restart
- [ ] Hooks: auto-install on first launch, auto-repair on app activation
- [ ] Multi-session: handle 5+ simultaneous sessions without lag
- [ ] Notch-less display: simulate notch with correct fake width

---

## Known Limitations & Future Work

### Current Limitations
1. **No menu bar icon**: Notch is sole UI entry point. (Planned for Phase 2.)
2. **No notifications**: Notch panel serves this purpose; native notifications would be redundant but valuable. (Planned: F7.)
3. **No keyboard shortcuts**: Manual UI access only. (Planned: F12.)
4. **No session history**: Completed sessions are removed. (Planned: F14.)
5. **No custom themes**: System dark/light only.
6. **Interim auto-update**: UpdateChecker instead of Sparkle. (Will migrate Phase 3.)

### macOS Compatibility
- **Min**: macOS 14.0 (Sonoma)
- **Max**: macOS 15+ (current development)
- **Tested**: 14.x, 15.x
- **Notch**: Native support on MacBook Pro 14"/16" (2021+); simulated notch on other displays.

---

## Conclusion

CodeIsland is a focused, open-source macOS monitoring tool for Claude Code sessions. The implementation prioritizes:
- **User privacy**: On-device only, verifiable via GitHub
- **Developer experience**: Clean architecture, easy to extend
- **Reliability**: Zero external dependencies, native Apple frameworks
- **Simplicity**: Notch-only UI, minimal config, auto-install hooks

Current MVP (v1.0.6) covers all P0 and P2 features, with P1 features in active development.
