# Kanban Board
<!-- Updated: 2026-04-11 -->

## Backlog

## Todo

### T-018: Watch upstream PR #59 — batched AskUserQuestion support
> Multiple AskUserQuestion calls arrive in a burst; this open PR queues them and adds a confirm-all step.
- **priority**: high
- **effort**: M
- **source**: wxtsky/CodeIsland PR #59 (open, not yet merged) — 2026-04-10
#### Criteria
- [ ] Monitor wxtsky/CodeIsland PR #59 for merge
- [ ] `QuestionPayload` (or a new wrapper) supports a list/queue of pending questions
- [ ] `AppState` aggregates incoming `AskUserQuestion` events into the queue instead of replacing
- [ ] `QuestionBarView` / `ApprovalBarView` renders multi-question UI with per-item answer selection
- [ ] Explicit "Submit answers" confirmation step before writing response back to socket
- [ ] Regression tests added for queue state transitions (pending → answered → submitted)
- [ ] `swift build && swift test` passes

### T-019: Fix permission requests auto-rejected when multiple arrive in quick succession
> When several PermissionRequest events arrive before the user can click, earlier ones are silently dropped/rejected.
- **priority**: high
- **effort**: S
- **source**: wxtsky/CodeIsland issue #57 (open, no upstream fix yet) — 2026-04-10
#### Criteria
- [ ] Reproduce locally: trigger 3+ tool permission requests in rapid succession
- [ ] `HookServer` / `RequestQueueService` queues pending requests rather than replacing
- [ ] `ApprovalBarView` shows a counter badge when multiple requests are queued (e.g. "1 of 3")
- [ ] Responding to one request advances to the next rather than dismissing all
- [ ] Auto-approve rules still apply per-tool before showing UI
- [ ] `swift build && swift test` passes

### T-016: v1.0.17 session lifecycle and PID reliability fixes
> PID reuse guard, reliable exit detection, model-retry backfill, and session cleanup bugfixes from upstream v1.0.17.
- **priority**: high
- **effort**: M
- **source**: wxtsky/CodeIsland v1.0.17 — commits dbc1cdf, 51526db (Apr 9, 2026)
#### Criteria
- [ ] `ProcessIdentity` struct tracks PID + process start time to guard against PID reuse on process restart
- [ ] In-flight Stop hook race condition fixed (session not removed if Stop event arrives mid-cleanup)
- [ ] Dead-monitor session cleanup uses grace period instead of waiting 10 minutes
- [ ] `modelReadAttempted` Set cleared on session removal (prevent memory leak)
- [ ] Model detection backfill retries with cooldown instead of permanently giving up on first miss
- [ ] `swift build && swift test` passes

### T-017: v1.0.17 compact bar UX — project name, instant switch, rotation interval
> Show project name while working; instantly switch to next session when active one stops; configurable rotation interval.
- **priority**: medium
- **effort**: S
- **source**: wxtsky/CodeIsland v1.0.17 — commit dbc1cdf (Apr 9, 2026)
#### Criteria
- [ ] Compact bar shows project/CWD name during all non-idle states (working, waiting, compacting)
- [ ] When an active session stops, bar immediately switches to the next running session without delay
- [ ] Settings → Behavior page has rotation interval picker: 3s / 5s / 8s / 10s (default 5s)
- [ ] Rotation interval setting persisted via `Settings.swift` / UserDefaults
- [ ] `swift build && swift test` passes

### T-011: Fix Warp terminal triggering Terminal.app on session completion
> Terminal detection should use bundle ID matching, not string contains on TERM_PROGRAM; fixes Warp users seeing Terminal.app pop open.
- **priority**: high
- **effort**: XS
- **source**: wxtsky/CodeIsland v1.0.16 — fix: Warp terminal no longer triggers Terminal.app on completion (#40)
#### Criteria
- [ ] `TerminalVisibilityDetector.swift` uses `NSRunningApplication.bundleIdentifier` matching instead of `TERM_PROGRAM` string contains
- [ ] Fallback paths return `false` when terminal identity is uncertain
- [ ] Ghostty requires dual-criteria validation; WezTerm/tmux/kitty simplified
- [ ] `swift build && swift test` passes

### T-012: Fix stuck session auto-reset and hook exec PID tracking
> Sessions stuck "thinking" for 2+ min auto-reset; hook bridge uses exec to inherit PID correctly.
- **priority**: high
- **effort**: S
- **source**: wxtsky/CodeIsland v1.0.16 — fix: hook exec PID tracking, stuck detection, smart suppress; fix: reset stuck sessions with monitor but no active tool after 2 min
#### Criteria
- [ ] Hook install script uses `exec` so bridge binary replaces bash and inherits PID
- [ ] `ProcessMonitorService` or equivalent triggers idle reset after 2 min of no tool activity
- [ ] Four stuck-detection scenarios handled: monitor+tool, monitor+no-tool, no-monitor+tool, no-monitor+no-tool
- [ ] `swift build && swift test` passes

### T-013: Fix Ghostty tab focus for tmux sessions
> Clicking "jump to terminal" in a Ghostty+tmux setup focuses the correct tab, not just the app.
- **priority**: medium
- **effort**: S
- **source**: wxtsky/CodeIsland v1.0.16 — PR #43: fix: focus Ghostty tab for tmux sessions
#### Criteria
- [ ] `TerminalActivator.swift` derives tmux window key (session name, window index) when tmux is detected
- [ ] Raw `TMUX` env var preserved from hook payload and passed to tmux subprocesses
- [ ] Ghostty AppleScript runs via `/usr/bin/osascript` out-of-process
- [ ] Falls back to existing CWD/session-ID matching if tmux window match fails
- [ ] `swift build && swift test` passes

### T-014: Menu bar icon when panel is auto-hidden
> When auto-hide is on and panel is invisible, a menu bar icon provides access to Settings and Quit.
- **priority**: medium
- **effort**: S
- **source**: wxtsky/CodeIsland v1.0.16 — PR #39: feat: add menu bar icon for auto-hide
#### Criteria
- [ ] `NSStatusItem` created when auto-hide setting is enabled
- [ ] Menu bar icon hidden when auto-hide is disabled
- [ ] Icon menu has "Settings..." and "Quit" options
- [ ] Icon shows/hides dynamically when setting is toggled at runtime
- [ ] `swift build && swift test` passes

### T-015: Make entire session card clickable to jump to terminal
> Clicking anywhere on a session card navigates to that terminal, not just the small icon.
- **priority**: medium
- **effort**: S
- **source**: wxtsky/CodeIsland v1.0.16 — feat: click entire session card to jump to terminal (#37)
#### Criteria
- [ ] Session card wrapped in `Button { jumpToTerminal() }` in `SessionListView.swift`
- [ ] Terminal icon remains as non-interactive visual badge
- [ ] NSPanel compatibility verified (Button, not gesture, for panel context)
- [ ] `swift build && swift test` passes

### T-006: Port sidebar settings row text spacing fix
> Add `.padding(.leading, 2)` to settings sidebar label text to fix icon-text alignment.
- **priority**: low
- **effort**: XS
#### Criteria
- [ ] `.padding(.leading, 2)` added to `SidebarRow` label text in `Sources/CodeIsland/SettingsView.swift`
- [ ] `swift build` passes

### T-007: Global keyboard shortcuts settings page
> Add a Shortcuts settings page with user-configurable key bindings (incl. default ⌘⇧I panel toggle).
- **priority**: medium
- **effort**: M
#### Criteria
- [ ] `shortcuts` case added to `SettingsPage` enum
- [ ] `ShortcutsPage` view with recording UI, conflict detection, clear/reset
- [ ] Default `⌘⇧I` panel toggle wired in `PanelWindowController.swift`
- [ ] Bindings persisted via `Settings.swift` / UserDefaults
- [ ] `swift build && swift test` passes

### T-008: Silent Dynamic Island mode during active work
> Add behavior toggle to suppress mascot animation while working, keeping alerts for approvals/completions.
- **priority**: medium
- **effort**: M
#### Criteria
- [ ] `silentWorkMode` setting registered in `Settings.swift`
- [ ] `effectiveMascotStatus()` maps running/processing → idle when enabled
- [ ] Compact bar and session card views use `effectiveMascotStatus()`
- [ ] Approval/question/completion states NOT suppressed
- [ ] Toggle in BehaviorPage with preview animation
- [ ] Unit tests added; `swift build && swift test` passes

## Doing

### [T-011: Cherry-pick features tu reference projects](tasks/T-011-reference-sync-apr09.md)
> Replicate 7 features tu upstream, open-vibe-island, notchi — adapt theo kien truc minh.
- **priority**: high
- **effort**: L
#### Criteria
- [x] T-011a: Hook exec PID fix
- [x] T-011b: Structured tool status display
- [x] T-011c: PID liveness check
- [x] T-011d: Click session card → jump terminal
- [x] T-011e: Stale subagent cleanup
- [x] T-011f: Dynamic approval buttons
- [ ] ~~T-011g: Auto-scroll activity feed~~ (skipped — no expandable messages in our UI)
- [x] `swift build && swift test` passes on all changes

## Done

### [T-006: Typed HookEvent thay rawJSON](tasks/T-006-typed-hook-events.md)
> EventMetadata struct + typed fields thay rawJSON: [String: Any]. All consumers updated.
- **priority**: high
- **effort**: M
- **completed**: 2026-04-08

### [T-007: SessionSnapshot conform Sendable + Codable](tasks/T-007-sendable-codable-snapshot.md)
> SessionSnapshot + all nested types Codable/Sendable. PersistedSession removed, direct encode/decode.
- **priority**: high
- **effort**: S
- **completed**: 2026-04-08

### [T-008: Test coverage cho reduceEvent()](tasks/T-008-reducer-tests.md)
> 41 Swift Testing tests covering all event types, edge cases, actionable state preservation.
- **priority**: high
- **effort**: M
- **completed**: 2026-04-08

### [T-009: Event-driven wiring thay callbacks](tasks/T-009-event-driven-wiring.md)
> Services use weak appState reference. 9 callbacks removed from CompletionQueue + RequestQueue.
- **priority**: medium
- **effort**: M
- **completed**: 2026-04-08

### [T-010: Sprite mascot system tu notchi](tasks/T-010-sprite-mascot-system.md)
> 17 sprite PNGs, MascotState/EmotionState models, SpriteSheetView + motion helpers, MascotView wired.
- **priority**: medium
- **effort**: L
- **completed**: 2026-04-08

### [T-001: Tach NotchPanelView thanh cac file rieng](tasks/T-001-split-notch-panel-view.md)
> 1786 dong → 368 dong + 6 file moi. Dead code xoa (PixelText, inlineMarkdown).

- **priority**: critical
- **effort**: L
- **completed**: 2026-04-07

### [T-002: Tach AppState thanh 4 services](tasks/T-002-split-appstate.md)
> 1186 dong → 745 dong. 4 services: ProcessMonitorService, SessionDiscoveryService, CompletionQueueService, RequestQueueService.

- **priority**: critical
- **effort**: L
- **completed**: 2026-04-07

### [T-003: Modernize L10n sang @Observable](tasks/T-003-modernize-l10n.md)
> @Observable + @Environment(\.l10n) thay ObservableObject + @ObservedObject. 13 views updated. @Bindable cho GeneralPage.

- **priority**: high
- **effort**: M
- **completed**: 2026-04-07

### [T-004: Tach SettingsView thanh 9 files](tasks/T-004-split-settings-view.md)
> 1009 dong → 119 dong + 9 file moi (AppLogoView + 7 pages + shared). Dead code xoa (PageHeader).

- **priority**: medium
- **effort**: S
- **completed**: 2026-04-07

### [T-005: Modernize concurrency patterns](tasks/T-005-modernize-concurrency.md)
> 9 Timer → Task loop, 6 DispatchQueue.global → Task.detached, 2 asyncAfter → Task.sleep, FSEventStream → AsyncStream wrapper.

- **priority**: medium
- **effort**: M
- **completed**: 2026-04-07

## Blocked
