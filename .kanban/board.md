# Kanban Board
<!-- Updated: 2026-05-04 -->

## Backlog

## Todo

### T-048: Fix main-thread block in detectClaudeVersion() — app freezes on activation
> `ConfigInstaller.detectClaudeVersion()` calls `proc.waitUntilExit()` synchronously. It is invoked from `checkAndRepairHooks()` on `@MainActor AppDelegate`, which runs on every app-activation event (user switching back to the app) and every 300 s via background timer. Slow Claude CLI startup or permission dialogs will freeze the entire app UI.
- **priority**: high
- **effort**: XS
- **source**: wxtsky/CodeIsland issue #139; upstream fix in v1.0.24 commits `61ab21e`/`7748e48`/`67d8039`/`78000a7`/`fecfed9` (Apr 29, 2026)
#### Criteria
- [ ] In `AppDelegate.checkAndRepairHooks()`: wrap `ConfigInstaller.verifyAndRepair()` call in `Task.detached(priority: .utility) { ... }` so the synchronous subprocess no longer blocks the main actor
- [ ] Add a 5-second timeout to `detectClaudeVersion()` (`proc.waitUntilExit()` → timer-based cancel + `waitUntilExit()` on background thread, or use `AsyncProcess` pattern)
- [ ] `app.activate` notification observer callback in `AppDelegate` already runs on `.main` queue — keep only UI-update code there; move `checkAndRepairHooks()` off main
- [ ] `swift build && swift test` passes

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

### T-034: Fix ConfigInstaller destructive reformat of ~/.claude/settings.json
> ConfigInstaller.swift uses JSONSerialization with .sortedKeys, which reorders all keys, escapes forward slashes, and strips trailing newlines on every install/repair cycle. Noisy for users who version-control their Claude settings.
- **priority**: high
- **effort**: S
- **source**: wxtsky/CodeIsland issue #106, commit `adf41b6` (v1.0.22, Apr 23, 2026) — upstream fix available
#### Criteria
- [ ] Port `JSONMinimalEditor.swift` from upstream `adf41b6` — minimal-diff editor that splices key/value changes without rewriting the whole file
- [ ] Update `ConfigInstaller.swift` to use `JSONMinimalEditor` instead of `JSONSerialization.data(..., [.prettyPrinted, .sortedKeys])`
- [ ] Port `JSONMinimalEditorTests.swift` (14 tests covering comment preservation, idempotency, malformed input)
- [ ] Manual check: install hooks on a real `~/.claude/settings.json` with comments and custom key order; confirm no reformat
- [ ] `swift build && swift test` passes

### T-035: Fix agent disappearing from island bar when switching macOS Spaces
> Upstream issue #104: session's agent indicator disappears when returning to the desktop where the terminal lives. Root cause: stale fullscreen-space latch in PanelWindowController keeps panel hidden for up to 1.5s after a Space switch.
- **priority**: medium
- **effort**: XS
- **source**: wxtsky/CodeIsland issue #104, commit `0850f35` (v1.0.22, Apr 23, 2026) — upstream fix available
#### Criteria
- [ ] In `PanelWindowController.swift` Space-switch handler, clear the fullscreen-space latch immediately when entering a non-fullscreen Space (don't wait for next poll interval)
- [ ] Port the 8-line fix from `0850f35` in `PanelWindowController.swift`
- [ ] Reproduce locally before and after: switch from fullscreen Space to regular Desktop and back
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
> When several PermissionRequest events arrive before the user can click, earlier ones are silently dropped/rejected. Upstream fix: tool_use_id deduplication cache (see T-040 for the port task).
- **priority**: high
- **effort**: S
- **source**: wxtsky/CodeIsland issue #57, commit `0a6ab92` (v1.0.22, Apr 23, 2026) — upstream fix available via tool_use_id cache (T-040)
#### Criteria
- [ ] Implement T-040 first (tool_use_id cache) — it directly solves the deduplication problem
- [ ] Verify that burst `PermissionRequest` events with same `tool_use_id` are deduplicated (in-place replace + stale waiter denied)
- [ ] `ApprovalBarView` shows a counter badge when multiple distinct requests are queued (e.g. "1 of 3")
- [ ] Responding to one request advances to the next; orphaned requests drained on `PostToolUse`
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

### T-036: Click-to-jump on permission approval card
> Extend ApprovalBar with click-to-jump navigation — clicking the card focuses the terminal for that session, mirroring session card behaviour. Includes shake + error sound on failure.
- **priority**: medium
- **effort**: S
- **source**: wxtsky/CodeIsland PR #108 MERGED, commit `4aac30f` (v1.0.22, Apr 23, 2026)
#### Criteria
- [ ] `ApprovalBar` supports click-to-jump via `handleCardClick()` reusing terminal activation logic
- [ ] On failed jump (session gone or remote): error sound + shake animation
- [ ] Extract `JumpAnimationHelper` namespace to share shake sequence `[8, -8, 6, -6, 3, -3, 0]` between `ApprovalBarView` and `SessionListView` (removes duplication)
- [ ] Auto-collapse after successful jump respects T-027 setting (3 retries: 120ms / 320ms / 640ms)
- [ ] Coordinate with T-031 (dismiss button) — both modify `ApprovalBar`
- [ ] `swift build && swift test` passes

### T-037: Fix stale PermissionDenied hook surviving Claude Code downgrade
> ConfigInstaller.swift version-gates PermissionDenied to Claude Code ≥ 2.1.89, but verifyAndRepair() short-circuits without cleaning stale versioned hooks. A user who installed with ≥ 2.1.89 then downgraded retains a PermissionDenied entry that Claude Code < 2.1.89 rejects at startup.
- **priority**: high
- **effort**: XS
- **source**: wxtsky/CodeIsland issue #107, commit `adf41b6` (v1.0.22, Apr 23, 2026) — upstream fix removes invalid PermissionDenied entry from Claude Code hook list
#### Criteria
- [ ] Port the `PermissionDenied` removal from `adf41b6` — remove invalid entry from Claude Code's registered hook event list in `ConfigInstaller.swift`
- [ ] Add `hasStaleVersionedHooks` check in the early-return guard so full strip-and-reinstall fires when stale versioned hooks are detected
- [ ] `swift build && swift test` passes
- [ ] Note: this is bundled in the same commit as T-034 (JSONMinimalEditor) — implement together

### T-038: Fix UpdateChecker.swift wrong upstream repo reference (or remove)
> UpdateChecker.swift hardcodes `wxtsky/CodeIsland` as the releases repo, making a silent outbound call to GitHub API on every app launch. Upstream PR #113 (remove checker) was abandoned; upstream instead added Sparkle (external dep) which we can't use (zero external deps policy).
- **priority**: medium
- **effort**: XS
- **source**: wxtsky/CodeIsland PR #113 CLOSED/ABANDONED (Apr 23, 2026); upstream went with Sparkle (`27ac918`) instead — bug still confirmed in our `UpdateChecker.swift:8` + `AppDelegate.swift:88`
#### Criteria
- [ ] Decide: remove checker entirely (zero outbound calls, aligns with our zero-deps policy) OR fix repo URL to `nguyenvanduocit/CodeIsland` if we publish releases on our fork
- [ ] If removing: delete `Sources/CodeIsland/UpdateChecker.swift`; remove `UpdateChecker.shared.checkForUpdates(silent: true)` from `AppDelegate.swift:88`; remove any Settings UI that exposes manual "Check for Updates"
- [ ] If keeping: change `private let repo = "wxtsky/CodeIsland"` → `"nguyenvanduocit/CodeIsland"` at `UpdateChecker.swift:8`
- [ ] Do NOT add Sparkle — it is an external dependency violating our zero-deps constraint
- [ ] `swift build && swift test` passes

### T-039: Fix Terminal.app tab activation — priority-based matching (tty → auto-title → fallback)
> Clicking a session card does nothing for users on macOS built-in Terminal.app because TerminalActivator has no tab-level matching for it — non-Ghostty terminals fall through to app.activate() only. Upstream rewrote this as priority-based AppleScript (tty → auto tab name → custom title → deminiaturize), fixing the "shake but nothing happens" bug.
- **priority**: high
- **effort**: S
- **source**: wxtsky/CodeIsland issue #116, commit `0850f35` (v1.0.22, Apr 23, 2026) — upstream fix available (supersedes `5624480`)
#### Criteria
- [ ] Port `TerminalActivator.swift` changes from `0850f35` (+74, -32 lines): add `activateTerminalApp()` for `com.apple.Terminal` bundle ID
- [ ] Cascading AppleScript strategy: tty exact match → auto tab name (cwd + command) → custom title → deminiaturize first minimized window
- [ ] Explicitly activate + unhide Terminal.app in Swift before AppleScript runs so hidden windows come to front
- [ ] Coordinate with T-020 (broader terminal activation overhaul) — both touch `TerminalActivator.swift`; port T-039 first as it is narrower
- [ ] `swift build && swift test` passes

### T-040: Port tool_use_id deduplication cache to fix burst PermissionRequest rejection
> Upstream `0a6ab92` introduces a `PreToolUseRecord` cache keyed on `tool_use_id`. Duplicate PermissionRequest events (same tool_use_id) are deduplicated in-place; stale waiters are denied; orphaned requests drained on PostToolUse. This is the upstream fix for T-019.
- **priority**: high
- **effort**: M
- **source**: wxtsky/CodeIsland commit `0a6ab92` (v1.0.22, Apr 23, 2026) — cherry-pick `AppState+ToolUseCache.swift` only
#### Criteria
- [ ] Port `AppState+ToolUseCache.swift` (+112 lines) — `PreToolUseRecord` struct with TTL (15 min), insert on `PreToolUse` events, lookup on `PermissionRequest`
- [ ] On duplicate `PermissionRequest` (same `tool_use_id`): replace queued entry in-place, deny stale waiter
- [ ] On `PostToolUse` / failure: purge completed records + drain orphaned permission requests
- [ ] Backfill missing `PermissionRequest` metadata from cached `PreToolUse` record
- [ ] Skip: `AppState+TranscriptTailer.swift` (separate concern) and `AppState+CodexAppServer.swift` (Codex-specific)
- [ ] Verify `tool_use_id` field is present in our typed `HookEvent` / `EventMetadata`
- [ ] Also port `e18f884` (Apr 30, 2026): replace "blanket drain" with surgical `tool_use_id`-targeted drain in `AppState.swift`; prevents parallel tool completions from falsely denying unrelated pending permissions; port 2 regression tests (`testStopEventDoesNotDenyPendingPermission`, `testParallelPostToolUseDoesNotDenyUnrelatedPendingPermission`)
- [ ] `swift build && swift test` passes

### T-041: Default mascot setting + fix IDE smart-suppress
> Users can choose which mascot sprite displays when no sessions are active. IDE smart-suppress is also fixed: panel now correctly suppresses when IDE app is frontmost (was broken — always returned false).
- **priority**: medium
- **effort**: XS
- **source**: wxtsky/CodeIsland commit `657a4db` (v1.0.22, Apr 23, 2026)
#### Criteria
- [ ] `Settings.swift` adds `defaultSource` key (default `"claude"`)
- [ ] `NotchPanelView.displaySource` checks `SettingsManager.defaultSource` when `totalSessionCount == 0`
- [ ] Settings → Mascots page has a `Picker` for idle mascot selection
- [ ] `TerminalVisibilityDetector.swift`: flip IDE terminal detection to return `true` (suppress) when IDE is frontmost; use app-frontmost signal instead of assuming terminals are always hidden
- [ ] Port `257778b` bugfix (Apr 30, 2026): change default-mascot trigger from `totalSessionCount == 0` → `summary.status == .idle` so idle-with-sessions also shows the user's preferred mascot (not just the empty state)
- [ ] `swift build && swift test` passes

### T-042: Configurable auto-approve tools in settings
> HookServer.swift currently hardcodes the auto-approve tool list. Make it configurable per-tool in Settings → Behavior, with defaults matching existing behaviour.
- **priority**: medium
- **effort**: S
- **source**: wxtsky/CodeIsland PR #126 MERGED, commit `d3c1e25` (v1.0.23, Apr 25, 2026)
#### Criteria
- [ ] `Settings.swift` adds `autoApproveToolsRaw` String key (comma-separated); getter/setter parse/serialise manually — do NOT add `@retroactive Set<String> RawRepresentable` conformance (see `7008e9a`)
- [ ] `HookServer.swift` reads from `SettingsManager.autoApproveTools` (parsed Set<String>) instead of hardcoded set
- [ ] Settings → Behavior page adds per-tool toggles; use `autoApproveBinding(for:)` helper pattern from upstream `d3c1e25`
- [ ] Skip L10n additions (we don't ship L10n)
- [ ] Default value for `autoApproveToolsRaw` should be empty string (empty set), not the old hardcoded list — matches upstream `b0a6989` (Apr 29, 2026)
- [ ] `swift build && swift test` passes

### T-044: Warp pane-precision jumping via SQLite
> Clicking a session card should land Warp users in the exact pane matching their session's cwd. Currently all non-Ghostty terminals fall through to no-op activation.
- **priority**: high
- **effort**: M
- **source**: wxtsky/CodeIsland commit `65da9fb` (v1.0.22, Apr 23, 2026) — missed from April 24 scout
#### Criteria
- [ ] Port `Sources/CodeIslandCore/WarpPaneResolver.swift` from `65da9fb` (219 lines) — `WarpPaneMatch` struct + `WarpPaneResolver` read-only SQLite reader with firmlink normalisation (`/tmp↔/private/tmp`, `/var↔/private/var`, `/etc↔/private/etc`)
- [ ] `TerminalActivator.swift`: add Warp bundle-name check → `activateWarp(cwd:)` (+71 lines); `sendWarpGoToTab(position:)` synthesises `Cmd+<n>` via CoreGraphics for tabs 1–9
- [ ] Fallback to plain app activation when SQLite file absent, query returns no match, or Accessibility permission denied
- [ ] Port `Tests/CodeIslandCoreTests/WarpPaneResolverTests.swift` from upstream
- [ ] Uses `import SQLite3` (macOS SDK system library — no external dependencies added)
- [ ] Coordinate with T-039 (Terminal.app fix also modifies `TerminalActivator.swift`) — port T-039 first
- [ ] Note: supersedes T-020's partial Warp window-level approach; no need to implement T-020 separately
- [ ] `swift build && swift test` passes

### T-045: Terminal jump robustness — Ghostty Accessibility fallback + Terminal.app variable shadowing
> TerminalActivator.swift has three additional robustness fixes beyond T-029/T-020: Ghostty System Events fallback when AppleScript is unreliable; Terminal.app minimised-window recovery on macOS 14; Terminal.app variable shadowing bug where `tty of t is tty` compared tab property to itself, silently jumping to wrong window in multi-session setups.
- **priority**: high
- **effort**: S
- **source**: wxtsky/CodeIsland commit `ed7cb7e` (v1.0.23, Apr 25, 2026)
#### Criteria
- [ ] Port Ghostty System Events fallback block (lines 393–411 upstream): when AppleScript focus is unreliable, force app frontmost via `System Events` Accessibility API + deminiaturise all windows; wrap in error handling for missing Accessibility permission
- [ ] Port Terminal.app identical fallback for minimised window recovery (lines 615–631 upstream)
- [ ] Rename local variables `tty` → `targetTty` and `dir` → `targetDir` in Terminal.app AppleScript block; update all three matching strategy references
- [ ] Apply on top of any T-020 / T-039 changes (all touch `TerminalActivator.swift`)
- [ ] `swift build && swift test` passes

### T-046: Webhook forwarding for hook events
> Power users want to route hook events to external services (Slack, CI webhooks, custom logging). Add a fire-and-forget HTTP POST option with configurable URL and event allow-list filter. Failures are silently ignored so webhook issues never disrupt the main event pipeline.
- **priority**: medium
- **effort**: M
- **source**: wxtsky/CodeIsland commit `b6a7007` (v1.0.23, Apr 25, 2026)
#### Criteria
- [ ] `Settings.swift` adds three keys: `webhookEnabled` (Bool, default false), `webhookURL` (String, default ""), `webhookEventFilter` (String, comma-separated, default "")
- [ ] `HookServer.swift` adds `forwardEventToWebhook()` — URLSession fire-and-forget POST; JSON envelope with event name, session ID, source, cwd, tool name, timestamp; 5s timeout; runs before route handlers; failures logged but not propagated
- [ ] Event filter: when non-empty, only forward events whose name appears in the comma-separated list; when empty, forward all
- [ ] Settings → Behavior page adds Webhook Forwarding section: enable toggle + conditional URL field + event filter field (monospaced font); strip whitespace from URL before use
- [ ] Skip L10n additions (we don't ship L10n)
- [ ] `swift build && swift test` passes

### T-047: Configurable cwd-substring blocklist to filter noisy background hooks
> Background plugins (claude-mem, etc.) fire hook events from their own directories, creating unwanted sessions in the panel. Add a user-configurable comma-separated blocklist of cwd substrings; any hook event whose working directory contains a match is silently dropped before state mutation.
- **priority**: medium
- **effort**: S
- **source**: wxtsky/CodeIsland commit `63e3ac6` (v1.0.23, Apr 25, 2026) — fixes issue #125
#### Criteria
- [ ] `Settings.swift` adds `excludedHookCwdSubstrings` key (String, comma-separated, default "")
- [ ] `HookServer.swift` adds `eventMatchesExcludedCwd()` helper; call in `processRequest()` before any session state mutation; silently drop matching events
- [ ] Settings → Behavior page adds "Ignore Hooks From Paths" section with a monospaced text field and placeholder examples (e.g. `.claude/plugins/claude-mem`)
- [ ] Skip L10n additions (we don't ship L10n)
- [ ] `swift build && swift test` passes

### T-043: Fix approval card rendering on macOS 26
> Upstream `05d174c` fixes transparency/rendering issues on macOS 26 (not yet released). Low priority — track for when macOS 26 ships.
- **priority**: low
- **effort**: XS
- **source**: wxtsky/CodeIsland commit `05d174c` (v1.0.22, Apr 23, 2026)
#### Criteria
- [ ] Port rendering fix for approval card from `05d174c` when macOS 26 is available for testing
- [ ] `swift build && swift test` passes

### T-049: Surface subagent count + tooltip on session card
> Show a "+N Sub" count badge in purple and per-agent tooltips (agent type + current tool) on session cards so multi-subagent sessions are easy to read at a glance.
- **priority**: medium
- **effort**: XS
- **source**: wxtsky/CodeIsland commits `ee25116` + `2cf2960` (v1.0.24, Apr 29, 2026) — upstream fix available; supersedes earlier "investigate" framing
#### Criteria
- [ ] In `NotchPanelView.swift` (or `SessionListView.swift`), add `.help()` tooltip to each `MiniAgentIcon`: text = "{agentType} — {currentTool}" when tool active, or just "{agentType}" when idle
- [ ] Add a `SessionTag` displaying "+N Sub" in purple to the session header when `subagentCount > 0`
- [ ] Extract subagent tooltip builder to a dedicated `@ViewBuilder` helper outside the main `body` (avoids recomputing on every `ViewBuilder` pass — perf fix from `2cf2960`)
- [ ] `swift build && swift test` passes

### T-050: Setting to disable auto-expand panel on agent completion
> Add a toggle so users who find the panel auto-expanding after every agent task can opt out. Defaults to enabled to preserve current behaviour.
- **priority**: medium
- **effort**: XS
- **source**: wxtsky/CodeIsland commit `d71b11e` (v1.0.24, Apr 29, 2026) — upstream fix available
#### Criteria
- [ ] `Settings.swift` adds `autoExpandOnCompletion` Bool key (default `true`)
- [ ] In `CompletionQueueService.enqueueCompletion()` (or wherever panel expansion is triggered), guard on `SettingsManager.autoExpandOnCompletion`; skip expansion when `false`
- [ ] Settings → Behavior page adds a toggle row for this setting
- [ ] `swift build && swift test` passes

### T-051: Plugin sub-sessions mode — separate / merge / hide
> claude-mem and similar plugins running inside a Claude session fire hook events with their own session ID, creating spurious cards. A 3-way setting (Separate/Merge/Hide) lets users decide how these `_via_plugin`-stamped events are handled. "Hide" auto-approves permissions to avoid blocking the main session.
- **priority**: medium
- **effort**: S
- **source**: wxtsky/CodeIsland commit `af7bbb1` (v1.0.24, Apr 29, 2026) — upstream fix available
#### Criteria
- [ ] `CodeIslandBridge/main.swift`: stamp `_via_plugin = true` in the forwarded JSON when source was inferred via process ancestry (no explicit `--source` flag)
- [ ] `HookEvent` / `EventMetadata`: add `isViaPlugin: Bool` parsed field
- [ ] `Settings.swift` adds `pluginSessionMode` key (String, default `"separate"`; values: `"separate"` / `"merge"` / `"hide"`)
- [ ] `HookServer.swift`: pre-filter `isViaPlugin` events per mode before reducer — "Merge" rewrites session ID to match parent (look up by source + CLI PID); "Hide" drops event and auto-approves any `PermissionRequest` in it
- [ ] Settings → Sessions page has a segmented picker for the mode
- [ ] Skip L10n additions (we don't ship L10n)
- [ ] `swift build && swift test` passes

### T-052: Hook event ring buffer + diagnostics export
> Maintain a 100-event in-memory ring buffer of received hook events (timestamp, source, session ID, event name, tool, plugin flag) and export it to `state/hook-events.json` during diagnostics. Makes it possible to triage session-routing bugs without guessing. Also includes a harden pass on `UserPromptSubmit` prompt extraction.
- **priority**: low
- **effort**: S
- **source**: wxtsky/CodeIsland commits `94f7ca8` + `0972e8b` (v1.0.24, Apr 29, 2026) — upstream fix available
#### Criteria
- [ ] Add `DiagnosticHookEvent` struct (timestamp, source, sessionId prefix-12, eventName, toolName, isViaPlugin)
- [ ] `AppState.swift` adds `recentHookEvents: [DiagnosticHookEvent]` (capped at 100, FIFO); expose `recordHookEvent()` method
- [ ] `HookServer.swift` calls `recordHookEvent()` after event construction, before routing
- [ ] `DiagnosticsExporter.swift` (create if absent) writes ring buffer to `state/hook-events.json` with ISO 8601 fractional-second timestamps
- [ ] Port `UserPromptSubmit` prompt-extraction hardening from `0972e8b`
- [ ] `swift build && swift test` passes

### T-053: Fix AskUserQuestion answer broken in Claude Code ≥2.1.121 (missing questions in updatedInput)
> Newer Claude Code versions require the original `questions` array echoed back inside `updatedInput` when answering AskUserQuestion via PermissionRequest. Our response omits it, causing a "tool selection error" on click. Root cause confirmed CodeIsland-side by upstream PR #153.
- **priority**: high
- **effort**: XS
- **source**: wxtsky/CodeIsland issue #150 + PR #153 (open, May 2, 2026) — reference implementation available; PR not yet merged but fix is confirmed and safe to port now
#### Criteria
- [ ] In `RequestQueueService.swift` `answer()`, change the `isFromPermission` branch to build `updatedInput` from `pending.event.toolInput ?? [:]` as base, then stamp `questions` from `pending.event.toolInput?["questions"] as? [[String: Any]]`, `answers: [answerKey: answer]`, and `answer: answer` (backward-compat single-answer field)
- [ ] Extract a private `askUserQuestionUpdatedInput(event:answers:answer:)` helper (mirrors upstream PR #153 pattern) so any future multi-answer path reuses the same logic
- [ ] Add test to `AppStateQuestionFlowTests` (or `RequestQueueServiceTests`) asserting that the PermissionRequest response payload contains `questions`, `answers`, and `answer` fields
- [ ] `swift build && swift test` passes

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

### T-028: Message input bar — watch abandoned
> Upstream PR #76 (MessageInputBar + TerminalWriter) was closed by contributor on Apr 17, 2026 after maintainer flagged unresolved IME issues, hardcoded delays, and clipboard pollution. Not merged; not worth porting.
- **priority**: low
- **effort**: L
- **completed**: 2026-04-18 (upstream abandoned)

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
