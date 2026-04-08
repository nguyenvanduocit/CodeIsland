# Changelog

All notable changes to this fork are documented here. Based on upstream [wxtsky/CodeIsland](https://github.com/wxtsky/CodeIsland) v1.0.6–v1.0.9.

## [Unreleased]

### Added
- **Typed hook events** — `HookEvent` uses typed fields (`EventMetadata`, `QuestionPayload`, etc.) instead of `[String: Any]` dictionaries
- **Sendable/Codable models** — All `CodeIslandCore` types conform to `Sendable` + `Codable` for safe concurrency and persistence
- **Pure reducer architecture** — `reduceEvent()` returns `[SideEffect]` (Elm-style), fully testable with 41 Swift Testing tests
- **Sprite mascot system** — Pixel art mascot with emotion states (happy/sad/sob), score-based decay, and sprite sheet animations (17 PNGs)
- **Session context menu** — Fork session, kill process, and export chat history from each session card
- **Session ID copy button** — Replaced fork-only button with copy-to-clipboard (fork moved to context menu)
- **Diagnostics support** — `os_signpost` startup timing, MetricKit payloads, memory high-water marks via Console
- **Session usage reader** — Token usage display per session from transcript files
- **Extracted services** — `CompletionQueueService`, `RequestQueueService`, `ProcessMonitorService`, `SessionDiscoveryService` with weak `appState` refs
- **Decomposed views** — `ApprovalBarView`, `QuestionBarView`, `NotchPanelShape`, `NotchSharedHelpers`, 7 settings page files split from monoliths
- **Kanban task board** — `.kanban/board.md` with task tracking for development work

### Changed
- **Claude Code exclusive** — Removed multi-CLI support (Codex, OpenCode). Single-target simplifies all hook parsing and UI
- **README rewritten** — Fork identity, architecture docs, upstream sync table
- **Service communication** — Services hold `weak var appState` directly, no callbacks or protocol indirection

### Fixed
- **Session lifecycle race** — `recentlyExitedSessions` guard (30s TTL) prevents late socket events from resurrecting removed sessions
- **Permission/question handling** — Deny requests for recently exited sessions instead of recreating them

### Upstream cherry-picks (v1.0.7–v1.0.9)
- Half-close race fix, startup race fix
- Auto-approve tools set, CLI version compatibility
- Compact bar display improvements
- Horizontal drag (always-on, no setting toggle)
- Ghostty exact matching (avoid misidentifying libghostty apps)

### Not synced from upstream
- Global keyboard shortcuts
- Tool status in compact bar
- In-app auto-update, CI/CD pipeline
- Copilot CLI support (not needed)
