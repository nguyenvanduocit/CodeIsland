# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# CodeIsland

macOS notch-panel app for monitoring Claude Code AI agent sessions. ~10,400 lines Swift, 83 tests, zero external dependencies.

## Build & Test

```bash
swift build                # Debug build
swift test                 # Run all tests (42 XCTest + 41 Swift Testing)
./restart.sh               # Dev cycle: kill → rebuild → launch
./build.sh                 # Release universal binary (arm64 + x86_64) + app bundle
./install.sh               # Install to /Applications
./install-skills.sh        # Install Claude Code skills
```

- SPM-only, no Xcode project. No external dependencies.
- No CI — always run `swift build && swift test` before committing.

## Architecture

Three SPM targets with strict dependency direction: Core ← App, Core ← Bridge.

### CodeIslandCore (pure logic, no SwiftUI)

Models and business logic. Zero UI imports. All types are `Sendable` + `Codable`.

| File | Purpose |
|------|---------|
| `Models.swift` | `AgentStatus`, `HookEvent` (typed — `EventMetadata` + typed fields, no rawJSON), `SubagentState`, `ToolHistoryEntry`, `ChatMessage`, `HookResponse`, `QuestionPayload` |
| `SessionSnapshot.swift` | `SessionSnapshot` (Sendable, Codable), `reduceEvent()` pure reducer, `extractMetadata()`, `SideEffect` enum, `TokenUsage`, `deriveSessionSummary()` |
| `MascotState.swift` | `MascotTask`, `MascotEmotion`, `MascotState` — sprite animation state model (ported from notchi) |
| `EmotionState.swift` | `EmotionState` — emotion scoring + decay (happy/sad/sob thresholds, 60s decay cycle) |
| `ProcessScanner.swift` | `ClaudeProcessMatcher`, `ProcessScanner` — finds running Claude processes |
| `EventLog.swift` | `EventLog` — persists hook events received while app not running |
| `ChatMessageTextFormatter.swift` | Markdown-to-attributed-string for chat display |
| `SocketPath.swift` | Unix socket path computation |

### CodeIsland (macOS app)

| Layer | Files |
|-------|-------|
| **State** | `AppState.swift` (central @Observable, owns services), `IslandSurface.swift` (panel state enum) |
| **Services** | `CompletionQueueService`, `RequestQueueService` (weak appState ref, no callbacks), `ProcessMonitorService`, `SessionDiscoveryService`, `HookServer` (NWListener Unix socket) |
| **Views** | `NotchPanelView`, `SessionListView`, `ApprovalBarView`, `QuestionBarView`, `MascotView` → `SpriteMascotView` |
| **Mascot** | `SpriteMascotView` (sprite sheet renderer), `SpriteSheetView` (TimelineView frame extractor), `SpriteMotion` (bob/tremble), `PixelCharacterView` (ClawdView fallback), `BuddyView` (fallback) |
| **Settings** | `SettingsView` + 7 page files, `Settings.swift` (keys/defaults/manager) |
| **Infrastructure** | `PanelWindowController`, `ScreenDetector`, `TerminalActivator`, `TerminalVisibilityDetector`, `ConfigInstaller`, `UpdateChecker`, `SoundManager`, `SessionPersistence`, `SessionTitleStore`, `SessionUsageReader` |

### CodeIslandBridge (compiled binary)

Native hook event forwarder. Compiled as `codeisland-bridge`, installed into Claude Code hooks config. Forwards JSON payloads to Unix socket `/tmp/codeisland-<uid>.sock`.

## Key Design Patterns

### Pure Reducer + Side Effects (Elm Architecture)

`reduceEvent(sessions:event:maxHistory:) -> [SideEffect]` is a pure function:
- Input: current sessions dict + typed HookEvent
- Output: mutated sessions + list of side effects to execute
- Side effects: `.playSound`, `.tryMonitorSession`, `.stopMonitor`, `.removeSession`, `.enqueueCompletion`, `.setActiveSession`
- AppState.executeEffect() runs the side effects after the reducer

This is the core architectural pattern. All session state transitions go through the reducer. Tests cover all 15+ event types.

### Typed Hook Events

`HookEvent` has typed fields — no `rawJSON: [String: Any]`:
- `metadata: EventMetadata` — shared fields (cwd, model, terminal info, etc.)
- Event-specific: `prompt`, `lastAssistantMessage`, `errorDetails`, `isInterrupt`, `agentType`, `newCwd`, `question`, etc.
- `askUserPayload: QuestionPayload?` — pre-parsed from AskUserQuestion tool_input
- `toolDescription: String?` — derived from tool_input at parse time

### Permission Auto-Approve

HookServer auto-approves `PermissionRequest` events without showing UI when any of these hold:
1. Tool is in `autoApproveTools` set (TaskCreate, TodoWrite, etc.)
2. Session's `permissionMode` is `"bypassPermissions"` (from snapshot or event metadata)
3. User previously clicked "Always" for that tool in that session (`autoApprovedTools` dict in AppState)

Auto-approved requests use `touchSession()` — lightweight metadata extraction without the full reducer pipeline (no sound, no status changes). The "Always" memory is per-session and cleaned up on session removal.

### Service Communication

Services hold `weak var appState: AppState?` and access properties directly. No callback closures, no protocol indirection. Simple and traceable.

### Sprite Mascot System (from notchi)

- `MascotState` = `MascotTask` (idle/working/sleeping/compacting/waiting) + `MascotEmotion` (neutral/happy/sad/sob)
- Each task has: `animationFPS`, `bobDuration`, `bobAmplitude`, `frameCount`
- Sprite sheets: 17 PNGs in `Resources/sprites/` (task_emotion.png)
- Fallback chain: exact → sad (for sob) → neutral
- `EmotionState`: score-based with decay (0.92x per 60s), thresholds: sad 0.45, happy 0.6, sob 0.9

## Upstream Sync

Upstream: `wxtsky/CodeIsland`

Last synced commit: `c016c4a` (v1.0.9)

| Date | Upstream version | Commit | Sync type | Notes |
|------|-----------------|--------|-----------|-------|
| 2026-04-07 | v1.0.6 | `5550ef2` | Full sync | Baseline — all features up to v1.0.6 included |
| 2026-04-07 | v1.0.7 | `f00f2e7` | Cherry-pick bugfixes | half-close race, startup race, auto-approve tools, CLI version compat, compact bar display |
| 2026-04-07 | v1.0.8 | `447ed88` | Cherry-pick feature | Horizontal drag (always-on, no setting toggle) |
| 2026-04-07 | v1.0.9 | `c016c4a` | Cherry-pick bugfix | Ghostty exact matching — avoid misidentifying libghostty apps |

Unsynced from v1.0.7: global shortcuts, tool status in compact bar, in-app auto-update, CI/CD pipeline.
Unsynced from v1.0.8: Copilot CLI support (not needed — Claude Code only).

We only support Claude Code (no Codex/OpenCode). Cherry-pick relevant changes instead of full merge.

To check new upstream changes: `gh api repos/wxtsky/CodeIsland/compare/<last-synced-commit>...<new-tag> --jq '.commits[] | .sha[:7] + " " + (.commit.message | split("\n")[0])'`

### Vibe Island (Feature Watch)

Also monitor feature changes from `vibeislandapp/vibe-island` — a similar notch-panel app. Cherry-pick good ideas when applicable.

To check recent changes: `gh api repos/vibeislandapp/vibe-island/commits --jq '.[] | .sha[:7] + " " + (.commit.message | split("\n")[0])' | head -20`

## Conventions

- Swift 5.9+, macOS 14+ target, SPM-only
- `@Observable` + `@MainActor` for all state and services
- Pure reducer pattern: `reduceEvent()` returns `[SideEffect]`
- All Core types: `Sendable` + `Codable` (custom CodingKeys exclude transient fields)
- Services hold `weak var appState` — no callback closures
- Typed HookEvent — no `[String: Any]` dictionaries (use `EventMetadata` + typed fields)
- Monospaced pixel aesthetic for UI
- Tests: XCTest for existing + Swift Testing (`@Test`, `#expect`) for new tests
- Sprite assets: PNG files in `Resources/sprites/`, loaded via `Bundle.module`

## Architectural Principles

1. **Pure Core, Imperative Shell** — CodeIslandCore has zero side effects. All I/O in CodeIsland app layer.
2. **Value semantics** — SessionSnapshot is a struct. Mutations via reducer return new values.
3. **Typed over untyped** — No `[String: Any]`. Hook events parsed into typed structs at boundary.
4. **Direct references over indirection** — Services use weak appState, not protocols/callbacks/delegates.
5. **Test the reducer** — Pure function = easy to test. 41 tests cover all event types and edge cases.

<!-- kanban:start -->
## Task Board

!`bash .kanban/status.sh 2>/dev/null`

Board: `.kanban/board.md` | Archive: `.kanban/archive/`

**Session start:** Read `.kanban/board.md`. Resume Doing tasks.
**Session end:** Update `.kanban/board.md` — move completed tasks to Done, note blockers, update timestamp.

**Task format** (MUST follow exactly):
```
### T-NNN: Title
> One-line description
- **priority**: critical|high|medium|low
- **effort**: XS|S|M|L
#### Criteria
- [ ] Acceptance criterion
```

**Rules:** WIP limit = 2 in Doing. Pick highest-priority from Todo. Never skip criteria checkboxes.
<!-- kanban:end -->
