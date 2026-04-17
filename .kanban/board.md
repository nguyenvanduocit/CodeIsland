# Kanban Board
<!-- Updated: 2026-04-17 -->

## Backlog

## Todo

### T-026: Configurable notch height modes to fix panel misalignment
> Some Macs (e.g. MacBook Air 15") have a 1px gap between the panel and the physical notch. Add three height modes: align to notch (default), align to menubar, or custom slider.
- **priority**: medium
- **effort**: S
- **source**: wxtsky/CodeIsland PR #80 (MERGED Apr 13, 2026)
#### Criteria
- [ ] `Settings.swift` adds `notchHeightMode` key with enum: `notch` / `menubar` / `custom`; `notchHeightOffset` key (Int, default 0) for custom mode
- [ ] `PanelWindowController.swift` height calculation reads the mode; `menubar` uses `NSStatusBar.system.thickness`; `custom` applies user offset
- [ ] Settings → Appearance page has a segmented picker for mode + a slider (visible only when `custom` selected)
- [ ] Changing the setting instantly rebuilds the panel (no restart required)
- [ ] `swift build && swift test` passes

### T-027: Auto-collapse panel after successful session jump (opt-in)
> When clicking a session card, optionally collapse the panel if the terminal switch succeeded. On failure, show shake + error sound.
- **priority**: medium
- **effort**: S
- **source**: wxtsky/CodeIsland PR #86 MERGED (Apr 15, 2026), commit `1f9618b`
#### Criteria
- [ ] `Settings.swift` adds `autoCollapseAfterSessionJump` Bool key (default `false`)
- [ ] `TerminalActivator` returns a success/failure result from `activate()` (or a completion closure)
- [ ] On successful jump when setting is on: collapse panel (hide `sessionList` / `completionCard` surface)
- [ ] On failed jump: play error sound + trigger shake animation on the session card
- [ ] Remote sessions excluded from auto-collapse
- [ ] Settings → Behavior page has a toggle with preview animation
- [ ] `swift build && swift test` passes

### T-030: Bump stuck-session idle threshold from 60s to 300s for long-thinking agents
> Unmonitored sessions with no active tool are auto-reset to idle after 60s — too aggressive for agents doing extended reasoning without tool calls.
- **priority**: high
- **effort**: XS
- **source**: wxtsky/CodeIsland commit `48520de` (v1.0.20, Apr 13, 2026) — fixes issue #75
#### Criteria
- [ ] In `AppState.swift` stuck-detection loop, change `threshold = session.currentTool != nil ? 180 : 60` → `threshold = session.currentTool != nil ? 180 : 300`
- [ ] `swift build && swift test` passes

### T-031: Add dismiss action for permission requests
> Add a third "Dismiss" button to the approval bar that abandons the request without sending Allow/Deny to Claude Code. Dismissed sessions are skipped in the queue and re-surface on a new permission event.
- **priority**: medium
- **effort**: S
- **source**: wxtsky/CodeIsland PR #93 MERGED (Apr 16, 2026), commit `fb64020`
#### Criteria
- [ ] Port dismiss action to `ApprovalBarView` — third button alongside Allow/Deny
- [ ] `AppState` / `RequestQueueService` tracks dismissed sessions and skips them when selecting next queued request
- [ ] Dismissed session re-enters queue when a new permission event arrives for that session
- [ ] Multi-session: dismissing advances to next pending session
- [ ] Unit tests cover dismiss-skip, re-display, and multi-session scenarios (ref: upstream `AppStatePermissionFlowTests.swift`)
- [ ] `swift build && swift test` passes

### T-033: Reduce screen-poll interval 1s → 5s to cut Energy Impact
> `CGWindowListCopyWindowInfo` runs every 1 second as a fallback poller; measurably shows in Energy Impact. Notifications already cover common-path display switches — 5s is sufficient for the drag-across-displays edge case.
- **priority**: high
- **effort**: XS
- **source**: wxtsky/CodeIsland commit `136737a` (v1.0.21, Apr 16, 2026) — fixes issue #92
#### Criteria
- [ ] Change `Task.sleep(for: .seconds(1))` → `.seconds(5)` at `PanelWindowController.swift:426` in `configureAutoScreenPolling()`
- [ ] `swift build && swift test` passes

### T-032: Fix fenced code block rendering in chat view
> `AttributedString(markdown:inlineOnlyPreservingWhitespace)` misparses fenced code blocks — the language identifier merges into the first line and all newlines inside the fence collapse. Split on fence markers and render code bodies as literal `AttributedString`.
- **priority**: high
- **effort**: S
- **source**: wxtsky/CodeIsland commit `cf9fb81` (v1.0.21, Apr 16, 2026) — fixes issue #101
#### Criteria
- [ ] `ChatMessageTextFormatter.inlineMarkdown(_:)` detects ` ``` ` fence markers and splits the input into fenced/non-fenced segments
- [ ] Non-fenced segments rendered via existing `AttributedString(markdown:)` path
- [ ] Fenced segments rendered as literal `AttributedString` (no markdown parsing) preserving all newlines and raw content
- [ ] Language identifier stripped from code body before rendering
- [ ] Segments concatenated in order and cached in `markdownCache` as before
- [ ] Tests added for: code block with language tag, code block without tag, multiple code blocks, code block with markdown-like content inside
- [ ] `swift build && swift test` passes

### T-028: Message input bar — send prompts from notch panel (watch)
> Large upstream PR adds MessageInputBar + TerminalWriter so users can send prompts to Claude Code without switching to the terminal.
- **priority**: low
- **effort**: L
- **source**: wxtsky/CodeIsland PR #76 (open, Apr 13, 2026) — **do not implement until merged upstream and reviewed**
#### Criteria
- [ ] Wait for wxtsky/CodeIsland PR #76 to be merged and reviewed by upstream maintainer
- [ ] Evaluate `TerminalWriter` module compatibility with our `TerminalActivator` pattern
- [ ] If merged: port `MessageInputBar` component (requires `TerminalWriter` for keystroke injection)
- [ ] If merged: port ApprovalBar persistent input field (attach context to approve/deny actions)
- [ ] System tag stripping (`<task-notification>`, `<system-reminder>`) may be cherry-picked independently
- [ ] `swift build && swift test` passes

### T-029: Fix Ghostty: clicking session triggers quick terminal instead of focusing tab
> When a Claude Code session is running in Ghostty, clicking the session card in the panel triggers Ghostty's quick-terminal (Quake dropdown) instead of focusing the correct window/tab.
- **priority**: high
- **effort**: XS
- **source**: wxtsky/CodeIsland issue #84; upstream fix in commit `48520de` (v1.0.20, Apr 13, 2026)
#### Criteria
- [ ] Remove `app.activate()` at `TerminalActivator.swift:98` inside `activateGhostty()` — calling it before the AppleScript is what triggers Ghostty Quick Terminal; the AppleScript's `focus t; activate` handles activation correctly after focusing the right window
- [ ] Verify: clicking session in Ghostty focuses the correct window; quick terminal is not triggered
- [ ] `swift build && swift test` passes

### T-024: Fix settings window close causes panel flicker (NSApp.hide nil)
> SettingsWindowController.swift:55 calls NSApp.hide(nil) in the close handler, hiding the entire app instead of just reverting the activation policy — causes the notch panel to briefly flicker off/on.
- **priority**: high
- **effort**: XS
- **source**: wxtsky/CodeIsland PR #70 (open, Apr 12 2026)
#### Criteria
- [ ] Remove `NSApp.hide(nil)` from `SettingsWindowController.swift` close observer
- [ ] Defer `NSApp.setActivationPolicy(.accessory)` via `DispatchQueue.main.async`
- [ ] Extract `clearCloseObserver()` helper to avoid duplicate observer registration on repeated open/close
- [ ] `swift build` passes; verify no panel flicker when closing settings

### T-025: Defer completion card auto-collapse when mouse is inside panel
> When the 5-second auto-collapse timer fires while the cursor is already hovering over the panel, the completion card dismisses instantly — jarring UX. Should wait until mouse leaves.
- **priority**: medium
- **effort**: S
- **source**: wxtsky/CodeIsland PR #69 (open, Apr 12 2026)
#### Criteria
- [ ] Add `deferCollapseOnMouseLeave: Bool` flag to `CompletionQueueService`
- [ ] In `showNextOrCollapse()`: if mouse is inside panel (`completionHasBeenEntered == true`), set flag and return early instead of collapsing
- [ ] In `NotchPanelView` hover handler: on mouse-leave when `deferCollapseOnMouseLeave` is set, trigger collapse and clear flag
- [ ] Reset `deferCollapseOnMouseLeave` in `cancel()` / `doShowCompletion()`
- [ ] `swift build && swift test` passes

### T-020: Terminal activation improvements — Warp/Alacritty/Hyper/tmux/IDE
> Upstream b51fd5f added window-level matching for Warp, Alacritty, Hyper; IDE shortest-title heuristic; terminal-not-running launch fallback; tmux-detached handling. Our TerminalActivator.swift supports Ghostty only.
- **priority**: high
- **effort**: M
- **source**: wxtsky/CodeIsland commit b51fd5f — 2026-04-11 (absorbs T-011 Warp fix)
#### Criteria
- [ ] `TerminalActivator.swift` `knownTerminals` expanded to include Warp, Alacritty, Hyper, iTerm2
- [ ] Warp/Alacritty/Hyper: window-level matching via System Events AppleScript (bundle-ID routing)
- [ ] `TerminalVisibilityDetector.swift` uses bundle-ID matching for Warp (fixes T-011: Warp triggering Terminal.app)
- [ ] IDE window matching: shortest-title heuristic when multiple windows share same project name
- [ ] Terminal not running: fallback to `NSWorkspace.open(application:)` launch instead of silent failure
- [ ] tmux detached: skip stale inner TTY, fall back to CWD/app activation
- [ ] `swift build && swift test` passes

### T-021: Configurable island width for non-notch displays
> Upstream added a 50%-150% width slider in Settings for users on non-notch Macs. Our width is fixed (panelWidth in NotchPanelView).
- **priority**: medium
- **effort**: S
- **source**: wxtsky/CodeIsland commit b51fd5f (issue #56) — 2026-04-11
#### Criteria
- [ ] `Settings.swift` adds `islandWidthScale` key (default 1.0, range 0.5–1.5)
- [ ] `NotchPanelView.panelWidth` reads `islandWidthScale` from settings
- [ ] Settings → Appearance/Display page has a width scale slider (50% – 150%)
- [ ] Setting persisted via UserDefaults and applied at runtime without restart
- [ ] `swift build && swift test` passes

### T-022: cmux surface-level precise terminal jump
> PR #50 merged upstream as d599150 (2026-04-11). Adds precise cmux/tmux window-level focus when jumping to terminal. Was "watch, not merged yet" per April 11 scout.
- **priority**: medium
- **effort**: M
- **source**: wxtsky/CodeIsland PR #50 → commit d599150 — 2026-04-11
#### Criteria
- [ ] `TerminalActivator.swift` detects cmux multiplexer (similar to existing tmux path)
- [ ] Resolves cmux session + window from hook metadata (CMUX env vars or similar)
- [ ] AppleScript / shell command focuses the correct cmux window (not just app-level)
- [ ] Falls back to CWD/app activation if cmux window can't be identified
- [ ] `swift build && swift test` passes

### T-023: Migrate hook config from ~/.claude/hooks/ to ~/.codeisland/
> Upstream b51fd5f migrated hook installation target from ~/.claude/hooks/ to ~/.codeisland/ with auto-cleanup of old paths. Our ConfigInstaller.swift still writes to ~/.claude/hooks/.
- **priority**: medium
- **effort**: S
- **source**: wxtsky/CodeIsland commit b51fd5f (issue #32) — 2026-04-11
#### Criteria
- [ ] `ConfigInstaller.swift` writes bridge + hook script to `~/.codeisland/` instead of `~/.claude/hooks/`
- [ ] Auto-cleanup removes old `~/.claude/hooks/codeisland-*` files on first launch after migration
- [ ] `hookCommand` in Claude Code hooks config updated to use new path
- [ ] Bridge binary path updated in hook script template
- [ ] No regressions for fresh installs (directory created if missing)
- [ ] `swift build && swift test` passes

### T-018: Implement multi-question AskUserQuestion wizard UI
> PR #59 + #60 merged upstream (abfc3b7, 2026-04-11). Wizard-style one-at-a-time questions with Back nav, MultiSelect, and drainQuestions on disconnect.
- **priority**: high
- **effort**: M
- **source**: wxtsky/CodeIsland PR #59/#60 → commit abfc3b7 — 2026-04-11
#### Criteria
- [ ] `AskUserQuestionState` (or equivalent) accumulates multiple `AskUserQuestion` events into a queue in the reducer (`SessionSnapshot.swift`)
- [ ] `AppState.answerQuestionMulti` sends answers with positional matching; `drainQuestions` sends deny on disconnect
- [ ] `QuestionBarView` renders one question at a time with Back navigation
- [ ] MultiSelect checkbox support and "Other" free-text input handled
- [ ] Explicit confirm/send step before writing response back to socket
- [ ] Answer key dedup (header-based, collision-safe) prevents duplicate submissions
- [ ] Skip: remote SSH monitoring bundled in abfc3b7 — cherry-pick question flow only
- [ ] Unit tests cover multi-question, dedup, skip, disconnect (ref: upstream `AppStateQuestionFlowTests.swift`)
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
