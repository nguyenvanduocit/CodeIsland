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
|------|----------|
| `Models.swift` | `AgentStatus`, `HookEvent` (typed — `EventMetadata` + typed fields, no rawJSON), `SubagentState`, `ChatMessage`, `HookResponse`, `QuestionPayload` |
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
- `toolDescription: String?` — derived per tool type at parse time (Bash→description, Read→file:offset, Grep→pattern+dir, etc.)
- `permissionSuggestions: [[String: Any]]?` — raw permission update suggestions from Claude Code

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
| 2026-04-09 | post-v1.0.15 | `b995a58` | Selective cherry-pick | Structured tool status display, PID liveness check 30s, stuck detection |
| 2026-04-09 | post-v1.0.15 | `b18e5b9` | Cherry-pick bugfix | Hook exec PID fix — `exec` replaces bash for correct getppid() |
| 2026-04-09 | post-v1.0.15 | `668b889` | Cherry-pick UX | Click entire session card to jump terminal (Button wrap) |

Also ported from **open-vibe-island**: stale subagent cleanup (3min timeout + prompt clear), dynamic permission_suggestions parsing.

Unsynced from v1.0.7: global shortcuts, in-app auto-update, CI/CD pipeline.
Unsynced from v1.0.8: Copilot CLI support (not needed — Claude Code only).
Unsynced from post-v1.0.15: menu bar icon, MorphText animation, BlurFade transition, diagnostics exporter, custom sound per event, StatusItemController KVO refactor, Warp terminal fix, Ghostty tmux focus, notarization/DMG build.

**Scouted but not yet synced (v1.0.10–v1.0.16, April 7–9 2026):**
- v1.0.10–v1.0.15: mostly CI/DMG/icon build fixes — skip (not relevant to SPM-only build)
- v1.0.15: settings window sidebar transparency fix — low priority (T-006 in Todo already tracks sidebar spacing)
- v1.0.16: Warp terminal misdetection fix (T-011), stuck session / hook exec PID fix (T-012), Ghostty+tmux tab focus (T-013), menu bar icon for auto-hide (T-014), clickable session card (T-015)
- v1.0.16: developer ID signing + notarization — skip (build/release only)
- Open PR #42: remote SSH monitoring — skip for now (not merged; also targets Codex sessions)
- Open PR #50: cmux terminal surface-level precise jump — watch, not merged yet

**Scouted but not yet synced (v1.0.17, April 9 2026):**
- v1.0.17: PID reuse guard + session lifecycle overhaul (T-016), compact bar project name + instant switch + rotation interval setting (T-017)
- v1.0.17: multi-source discovery (Qoder/CodeBuddy/Cursor/Copilot) — skip (Claude Code only)
- v1.0.17: legacy hook cleanup (removes vibe-island entries) — skip (our bridge is different)

**Scouted (April 11 2026) — post-v1.0.17 activity:**
- Open PR #59 (2026-04-10): batched AskUserQuestion support — queues multiple questions, adds confirm-all step (T-018, watch for merge)
- Open issue #57 (2026-04-10): permission requests auto-rejected when multiple arrive in burst — no upstream fix yet (T-019)
- Open PR #42: remote SSH monitoring — skip (not merged; targets non-Claude tools)
- Open PR #50: cmux terminal precise jump — still open, watch (same as before)
- vibeislandapp/vibe-island: no code changes since 2026-04-03 (only docs/setup)

**Scouted (April 12 2026) — v1.0.18 activity:**
- v1.0.18 released 2026-04-11
- PR #59 + #60 MERGED → `abfc3b7`: multi-question AskUserQuestion wizard UI + MultiSelect + Back nav + `drainQuestions` (T-018 → promote to implement); remote SSH bundled — skip
- PR #61 MERGED (bundled in abfc3b7): completion queue fix — already in our `CompletionQueueService` (lines 650-658 in AppState.swift); no action needed
- PR #50 MERGED → `d599150`: cmux surface-level precise terminal jump (was watching; T-022)
- `b51fd5f`: terminal activation overhaul — Warp/Alacritty/Hyper window-level matching, IDE shortest-title heuristic, terminal-not-running launch fallback, tmux-detached handling (T-020; absorbs T-011 Warp fix)
- `b51fd5f` #56: configurable island width 50%-150% slider for non-notch displays (T-021)
- `b51fd5f` #32: hook config migrated from `~/.claude/hooks/` → `~/.codeisland/` with auto-cleanup (T-023; our ConfigInstaller still uses old paths)
- `b51fd5f` stuck session: waitingApproval/Question auto-reset after 300s with no monitor — cherry-pick as part of T-016 or T-019
- PR #64 (third-party CLI extensibility, Trae/StepFun) — skip (non-Claude tools)
- PR #67 (Turkish translation) — skip (we don't ship L10n)
- vibeislandapp/vibe-island: no code changes since 2026-04-03 (only docs/setup)

**Scouted (April 13 2026) — v1.0.19 activity:**
- v1.0.19 released 2026-04-12
- `2fd1330`: CLI config dedup via `defaultEvents(for:)` — not applicable (our ConfigInstaller only has Claude Code, no duplication)
- `8f25152`: Hermes event payload parsing fix — skip (Hermes is a non-Claude CLI)
- `6c8c352`: include antigravity and hermes in hook install list — skip (non-Claude CLIs)
- PR #64 MERGED: third-party CLI extensibility (Trae/StepFun/CodyBuddyCN) — skip (non-Claude CLIs)
- PR #67 MERGED: Turkish translation — skip (we don't ship L10n)
- PR #66 MERGED: release resource bundle fix — skip (CI/release infra)
- **PR #70** (open, Apr 12): fix settings close flicker — `NSApp.hide(nil)` in close handler hides entire app → panel flickers. We have this bug at `SettingsWindowController.swift:55` → **T-024**
- **PR #69** (open, Apr 12): defer completion card auto-collapse when mouse inside panel — timer fires while hovering causes jarring immediate dismiss. We have this issue in `CompletionQueueService.showNextOrCollapse()` → **T-025**
- PR #72 (open, Apr 12): Japanese/Korean L10n — skip (we don't ship L10n)
- Issue #75: agent thinking >1min → idle state — already covered by T-012 (stuck session auto-reset)
- vibeislandapp/vibe-island: no code changes since 2026-04-03 (only docs/setup)

**Scouted (April 15 2026) — post-v1.0.19 activity:**
- PR #70 MERGED (Apr 13): settings close flicker fix — now merged upstream; T-024 ready to implement
- PR #69 MERGED (Apr 13): defer completion card collapse on hover — now merged upstream; T-025 ready to implement
- **PR #80 MERGED (Apr 13)**: configurable notch height modes (align to notch/menubar/custom slider) — fixes 1px panel misalignment on MacBook Air 15" and similar → **T-026**
- **PR #86** (open, Apr 14): opt-in auto-collapse panel after successful session jump; failure → shake + error sound → **T-027** (watch for merge)
- PR #87 (open, Apr 14): OpenCode permission/question approval race fix — skip (OpenCode-specific)
- PR #90 (open, Apr 14): Kimi Code CLI support — skip (non-Claude CLI)
- PR #82 (open, Apr 13): CodeBuddy remote hook — skip (non-Claude CLI)
- PR #72 (open draft): Japanese/Korean L10n — skip (we don't ship L10n)
- **PR #76** (open, Apr 13): message input bar + TerminalWriter — direct prompt sending from notch panel, system tag parsing, ApprovalBar attachment input; large unreviewed PR, watch for upstream decision → **T-028** (watch, do not implement until merged)
- **Issue #84** (open, Apr 13): Ghostty click triggers quick terminal instead of focusing correct tab — user-reported bug, no upstream fix yet → **T-029**
- Issue #88 (open, Apr 14): request to auto-hide question/approval panel — addressed by T-027 if implemented
- Issue #91 (open, Apr 14): iPhone sync feature request — out of scope
- vibeislandapp/vibe-island: no code changes since 2026-04-03 (only docs/setup)
- ⚠️ **Missed in this scout**: v1.0.20 (Apr 13) content — `48520de` Ghostty activation fix + idle timeout fix; `356f9b6` haptic feedback. Caught in April 16 scout below.

**Scouted (April 16 2026) — v1.0.20 + post-v1.0.20 activity:**
- v1.0.20 released 2026-04-13 (missed in Apr 15 scout)
- `48520de`: fix Ghostty quick terminal — removes premature `app.activate()` in `activateGhostty()` before AppleScript runs; upstream fix for T-029 is a single line deletion in `TerminalActivator.swift:98` → **T-029 has upstream fix, implement now**
- `48520de`: fix idle fallback timeout 60s → 300s — unmonitored sessions with no active tool were auto-reset to idle after 60s, too short for long-thinking agents; fix is one line in `AppState.swift:189` → **T-030**
- `356f9b6`: haptic feedback on hover — nice-to-have, low priority; skip for now
- **PR #86 MERGED** (Apr 15, commit `1f9618b`): auto-collapse after session jump — was watching; now merged → **T-027 promote to implement**
- PR #87 MERGED (Apr 15): OpenCode approval fix — skip (OpenCode-specific)
- PR #90 MERGED (Apr 15): Kimi Code CLI support — skip (non-Claude CLI)
- PR #82 MERGED (Apr 15): CodeBuddy remote hook — skip (non-Claude CLI)
- **PR #93** (open, Apr 15): dismiss flow for permission prompts — adds "Dismiss" button to skip without Allow/Deny; watch for merge → **T-031** (watch)
- PR #76 (open, Apr 13): message input bar + TerminalWriter — still open, still watching (T-028)
- PR #72 (open draft): Japanese/Korean L10n — skip
- PR #98 (open, Apr 15): TraeCli hooks support — skip (non-Claude CLI)
- Issue #92 (open, Apr 15): high power consumption report — no technical details, no upstream fix yet; monitor
- vibeislandapp/vibe-island: no code changes since 2026-04-03 (only docs/setup)

**Scouted (April 17 2026) — v1.0.21 activity:**
- v1.0.21 released 2026-04-16
- **PR #93 MERGED** (Apr 16, commit `fb64020`): dismiss flow for permission prompts — was watching; now merged → **T-031 promote to implement** (`AppState.swift` +37, `NotchPanelView.swift` +4; adds Dismiss button that abandons the request without sending Allow/Deny, skips dismissed sessions in queue)
- **`cf9fb81`** (Apr 16): fix fenced code block rendering — `AttributedString(markdown:inlineOnlyPreservingWhitespace)` treats ``` as inline delimiters, merging language tag into first code line and collapsing all newlines; fix splits on fence markers and renders code bodies as literal `AttributedString`. We have the same bug in `ChatMessageTextFormatter.swift`. → **T-032**
- **`136737a`** (Apr 16): reduce screen-poll interval 1s → 5s — `CGWindowListCopyWindowInfo` every second was measurably showing in Energy Impact; notifications already cover common-path display switches, poller is fallback for drag-across-displays only. We have same 1s cadence at `PanelWindowController.swift:426`. XS fix. → **T-033**
- `8481f43` / `68dd40b` / `aaf0edc`: SSH auto-reconnect and per-host SSH_AUTH_SOCK — skip (SSH remote monitoring, not applicable)
- `ebe72c9`: infer source from process ancestry when hook lacks --source — skip (OpenCode/omo-plugin specific)
- `7c90f7c` / `bd74ca5`: sign/notarize build script + version bump — skip (CI/release only)
- PR #76 (open, Apr 16): message input bar + TerminalWriter updated — still open, still watching (T-028)
- Issue #84 (open, Ghostty click can't jump): T-029 has upstream fix (`48520de`), no change to watch status
- Issue #92 (high power): now resolved upstream by `136737a` (T-033)
- vibeislandapp/vibe-island: no code changes since 2026-04-03 (only docs/setup)

**Scouted (April 18 2026) — post-v1.0.21 activity:**
- No new commits, releases, or PRs since v1.0.21 (last commit `7c90f7c`, zero open PRs)
- **PR #76 CLOSED/ABANDONED** (Apr 17): message input bar + TerminalWriter — maintainer closed after IME incompatibility, hardcoded delays, clipboard pollution, and AppleScript race conditions remained unresolved after multiple review rounds; T-028 retired
- **Issue #106** (open, Apr 17): `installClaudeHooks()` destructively reformats `~/.claude/settings.json` — confirmed same bug in our `ConfigInstaller.swift:344,367` (`.sortedKeys` reorders keys, `\/` slash escaping, strips trailing newline) → **T-034**
- **Issue #104** (open, Apr 17): agent indicator disappears from island bar when returning to the Space where the terminal runs — our panel has `.canJoinAllSpaces` so window is fine; bug likely in content/visibility logic → **T-035** (investigate)
- Issue #105: opencode.json installer destructive reformat — skip (OpenCode-specific)
- Issue #103: Qwen Code support issues — skip (non-Claude CLI)
- Issue #102: Default role setting support — skip (feature request for other CLIs)
- Issue #100: permission modal flickering (black buttons / transparent areas) — no upstream fix; appears rendering-specific to their UI; skip unless reproduced locally
- vibeislandapp/vibe-island: only Discord webhook setup, README splits, and repo-rename link fixes since Apr 3 — nothing actionable

**Scouted (April 20 2026) — post-v1.0.21 activity:**
- **PR #108** (open, Apr 19): click-to-jump on permission approval card — extends `ApprovalBar` with `handleCardClick()` + `JumpAnimationHelper`; shake+error-sound on failure; we lack this on `ApprovalBarView.swift`; watch for merge → **T-036**
- **Issue #107** (open, Apr 19): Claude Code v2.0.73 rejects `PermissionDenied` hook as invalid — we have version gating (`"PermissionDenied": "2.1.89"`) but gap: `verifyAndRepair()` short-circuits if all compatible events present, leaving stale `PermissionDenied` from a prior install (when user had ≥ 2.1.89) even after Claude Code downgrade → **T-037** (fix staleness check)
- vibeislandapp/vibe-island: no code changes since 2026-04-03 — nothing actionable

**Scouted (April 22 2026) — post-v1.0.21 activity:**
- **PR #113** (open, Apr 20): Security: remove SSH remote feature and auto-update checker — upstream removes `UpdateChecker.swift` as part of a hardening pass ("zero network calls"). Our concern: `UpdateChecker.swift:8` hardcodes `wxtsky/CodeIsland` (wrong repo), and `AppDelegate.swift:88` calls it silently on every launch — making outbound HTTP to a third-party repo without user knowledge → **T-038** (fix or remove)
- PR #108 (click-to-jump on approval card): still open, still watching — T-036 unchanged
- PR #111 (open, Apr 20): pi-mono support — skip (non-Claude CLI)
- Issue #116 (open, Apr 21): macOS terminal jump fails to activate window — user report of shake-but-no-focus on macOS 14/M3; covered by T-020 (terminal activation overhaul) and T-029 (Ghostty fix); no new code to cherry-pick
- Issue #118 (open, Apr 21): ACP protocol support request — skip (unrelated protocol)
- Issue #117 (open, Apr 21): Hermes integration — skip (non-Claude CLI)
- Issue #115, #114, #112, #109 (open, Apr 20-21): hook forwarding, Codex icon, smart suppression, iOS — skip (non-Claude or out of scope)
- vibeislandapp/vibe-island: no new commits since Apr 3 — nothing actionable

**Scouted (April 23 2026) — post-v1.0.21 activity:**
- No new commits or releases since v1.0.21 (Apr 16)
- PR #120 (open, Apr 22): third-party CLI extensibility + Hermes/Gemini bridge hardening — skip (non-Claude CLIs)
- Issue #116 (closed Apr 22): macOS Terminal.app click-to-jump fix — previously noted as "no new code to cherry-pick" but closure comment references commit `5624480` with a principled rewrite of Terminal.app tab activation: priority-based matching (tty exact → auto tab name → fallback) instead of broken `custom title`-only approach. Commit not yet on main as of Apr 23 → **T-039** (watch for landing)
- Issue #119 (closed Apr 22): opencode.json config reformat — OpenCode-specific, skip
- Issue #115 (open, Apr 22): custom hook forwarding feature request — out of scope
- vibeislandapp/vibe-island: `ba1c889` (Apr 22) — docs/SEO badges only, nothing actionable

**Scouted (April 24 2026) — v1.0.22 activity:**
- v1.0.22 released 2026-04-23
- `adf41b6`: "fix: preserve user formatting when installing hooks (#105 #106 #119 #107 #103)" — new `JSONMinimalEditor.swift` splices targeted key/value changes without rewriting the file; fixes T-034 (destructive reformat) **and** T-037 (removes invalid `PermissionDenied` entry from Claude Code hook list); comes with 14 tests → **T-034 + T-037: upstream fix available, promote to implement**
- `0850f35`: "fix: Terminal.app minimized jump + multi-desktop panel visibility (#116 #104)" — `TerminalActivator.swift` gets cascading AppleScript fallback (tty exact → auto tab name → custom title → deminiaturize); supersedes `5624480` that T-039 was watching; `PanelWindowController.swift` clears stale fullscreen-space latch immediately → **T-039 + T-035: upstream fix available, promote to implement**
- `4aac30f`: "feat(panel): add click-to-jump on permission approval card (#108)" — PR #108 merged; `ApprovalBar` now navigates to terminal on click; `JumpAnimationHelper` centralises shake animation; auto-collapse aware → **T-036: now merged, remove "watch" gate and implement**
- `0a6ab92`: "feat: session monitoring overhaul — tool_use_id cache, JSONL tailing, Codex app-server" — new `AppState+ToolUseCache.swift` caches `PreToolUse` records by `tool_use_id`; deduplicates burst `PermissionRequest` events (in-place replace + deny stale waiter); fixes T-019 exactly; JSONL tailing is new feature; Codex app-server skip → **T-019 upstream fix: cherry-pick `AppState+ToolUseCache.swift` only (skip Codex parts)** → **T-040** (new)
- `657a4db`: "feat: default mascot setting + smart-suppress in IDE terminals (#102 #112)" — Settings picker lets user choose which mascot shows when idle; `TerminalVisibilityDetector.swift` now suppresses panel when IDE is frontmost (was broken) → **T-041** (new, medium priority)
- `27ac918`: Sparkle-based auto-update with ed25519 sig verification — adds Sparkle as external dependency (violates our zero-deps policy); skip Sparkle; T-038 still stands but note that upstream chose Sparkle over deleting the checker
- **PR #113 CLOSED/ABANDONED** (Apr 23): "Security: remove SSH remote feature and auto-update checker" — closed without merging; upstream went with Sparkle instead; T-038 must be resolved independently (fix repo URL or remove checker)
- `73c059b`: silence compiler warnings (Sendable + let + nil coalescing) — minor quality chore; skip unless we have the same warnings
- `aa84056`: performance benchmark tests for hot-path helpers — internal test improvement; skip
- `cfaa6c6` / `ed2dce4` / `6adb107` / `5ba0a5e`: third-party CLI extensibility, pi-mono, Codex bundle ID, Copilot field seeding — skip (non-Claude CLIs)
- `05d174c`: "fix: approval card rendering on macOS 26 (#100)" — fixes transparency rendering on macOS 26 (not yet released; future-proof) → **T-043** (low priority, watch)
- **PR #126** (open, Apr 23): "feat: make auto-approve tools configurable in settings" — `HookServer.swift` reads `autoApproveTools` from `SettingsManager` instead of hardcoded set; Settings Behavior page gets per-tool toggles → **T-042** (watch for merge)
- Issue #124 (open, Apr 23): macOS terminal click-to-jump still failing — covered by T-039 fix in `0850f35`
- Issue #125 (open, Apr 23): claude-mem plugin hook triggering issues — plugin-specific, skip
- Issue #127 (open, Apr 23): Kiro support request — non-Claude CLI, skip
- vibeislandapp/vibe-island: no new commits since Apr 22 (docs only) — nothing actionable

**Scouted (April 25 2026) — post-v1.0.22 activity:**
- No new commits or releases since v1.0.22 (Apr 23); latest is still `3d5ea9b`
- Open PRs: #126 (configurable auto-approve tools, T-042) — still open, still watching; #122 (TraeCli YAML hook fix) — skip
- Open issues: #128 (Apr 24, Claude Code auto-executes after plan) — Claude Code CLI behaviour, not our app; skip
- **⚠️ Missed from April 24 scout**: `65da9fb` "feat: Warp SQLite pane-precision jumping" — was in the v1.0.22 batch but absent from previous scout notes. New `WarpPaneResolver.swift` (219 lines) + `TerminalActivator.swift` (+71 lines) adds pane-precision tab-jumping for Warp via read-only SQLite query. Supersedes T-020 (Warp window-level). Uses `import SQLite3` (system lib, zero external deps). → **T-044** (new, high priority)
- vibeislandapp/vibe-island: `ba1c889` (Apr 22) remains the latest commit — docs/SEO only, nothing actionable

**Scouted (April 26 2026) — v1.0.23 activity:**
- v1.0.23 released 2026-04-25
- **PR #126 MERGED** (`d3c1e25`): configurable auto-approve tools in settings — `HookServer.swift` reads from `SettingsManager`; Settings Behavior page adds per-tool toggles → **T-042 promote to implement**. Also note: `7008e9a` (same batch) drops `@retroactive Set<String> RawRepresentable` conformance in favour of manual comma-string serialisation — implement T-042 following this pattern (store as `String`, parse/serialise manually)
- **`ed7cb7e`**: terminal jump robustness — Ghostty: System Events Accessibility API fallback when AppleScript unreliable; Terminal.app: identical fallback for minimised window recovery on macOS 14; Terminal.app variable shadowing fix (renamed `tty`/`dir` → `targetTty`/`targetDir` so AppleScript comparisons don't compare a variable to itself). Additive on top of T-020 (`b51fd5f`) and T-029 (`48520de`). → **T-045** (new, S effort)
- **`b6a7007`**: webhook forwarding for hook events — fire-and-forget HTTP POST to user-configured URL; configurable event allow-list filter; 5s timeout; HookServer + Settings + SettingsView changes only → **T-046** (new, M effort)
- **`63e3ac6`**: configurable cwd-substring blocklist for hook events — users can enter comma-separated path substrings; matching events silently dropped before state mutation; prevents background plugins (claude-mem, etc.) creating noise sessions → **T-047** (new, S effort)
- `9098aeb`: don't force remote sessions to idle on local timeout — skip (SSH remote sessions, not applicable)
- `9c1920e` / PR #131: ESP32 BLE companion device — skip (hardware)
- `8863a46`: Kiro CLI support — skip (non-Claude CLI)
- `1f7b419` / `5742e32`: TraeCli fixes — skip
- `9346ff3`: Codex $CODEX_HOME config — skip
- `746afa4`: WorkBuddy support — skip (non-Claude CLI)
- `79787e9`: refactor share TerminalActivator source→bundle-id map — introduces ESP32FocusCoordinator dependency; skip
- `97842e6`: test coverage for cwd filter + Kiro — internal, skip
- `9ef73c1`: trim whitespace around webhook URL — minor, bundled with T-046
- No new open PRs or issues relevant to us (only Kiro #127, opencode.jsonc #132, and non-Claude CLIs)
- vibeislandapp/vibe-island: still no new code since Apr 3 (docs/SEO only) — nothing actionable

**Scouted (April 27 2026) — post-v1.0.23 activity:**
- No new commits or releases since v1.0.23 (Apr 25); latest commit is `d887012` (appcast.xml chore)
- **PR #133** (open, Apr 26): "fix: prevent Sparkle crash in DEBUG mode when running without bundle ID" — adds `#if DEBUG` guard around Sparkle init in `UpdateChecker.swift`; not applicable (we don't use Sparkle; T-038 tracks our independent UpdateChecker fix)
- **PR #135** (open, Apr 26): "Chore: Polish Turkish translation" — skip (no L10n)
- **PR #136** (closed, Apr 26): opened on wrong repo in error — skip
- **Issue #134** (open, Apr 26): cursor-agent and qodercli support request — skip (non-Claude CLIs)
- vibeislandapp/vibe-island: `ba1c889` (Apr 22) remains the latest commit — docs/SEO only, nothing actionable
- ⚠️ GitHub Issues are **disabled** in `nguyenvanduocit/CodeIsland` — all tracking via this kanban board only

**Scouted (April 28 2026) — post-v1.0.23 activity:**
- No new commits or releases since v1.0.23 (Apr 25); latest upstream commit remains `d887012` (appcast.xml chore)
- **Issue #139** (open, Apr 27): app hangs silently on launch — main thread blocked by `detectClaudeVersion()` calling `proc.waitUntilExit()` on `@MainActor AppDelegate`; confirmed same bug in our `ConfigInstaller.swift:263` + `AppDelegate.checkAndRepairHooks()` triggered on every app-activation event → **T-048** (new, high priority, XS)
- **Issue #141** (open, Apr 27): feature request for visual indicator to distinguish subagent sessions — we already show active subagents within session cards; gap is top-level sessions spawned by Task tool looking identical to main-agent sessions → **T-049** (new, low priority, backlog)
- **Issue #140** (open, Apr 27): Light/Dark/System theme toggle request — skip (low demand, our pixel aesthetic is intentionally dark-only)
- **Issue #137** (open, Apr 27): update failure after showing "latest version" — Sparkle-specific; we don't use Sparkle (T-038 tracks our own UpdateChecker)
- **PR #138** (open, Apr 27): fix Sparkle abort-callback race — Sparkle-specific; skip
- PR #133/#135: Sparkle DEBUG guard + Turkish L10n polish — unchanged, still skip
- vibeislandapp/vibe-island: no new commits since Apr 22 — nothing actionable

**Scouted (April 29 2026) — post-v1.0.23 activity:**
- No new commits or releases since v1.0.23 (Apr 25); upstream still quiet
- **PR #144** (open, Apr 28): "feat: improve Buddy watch approval previews and alerts" — extends the ESP32 BLE hardware companion device (wearable desk pet); hardware-specific, not relevant to macOS app — skip
- **PR #138** (open, Apr 27): Sparkle abort-callback race — Sparkle-specific; still open, still skip (T-038 tracks our own UpdateChecker fix independently)
- **Issue #143** (open, Apr 28): pi-coding-agent support request — non-Claude CLI, skip
- **Issue #142** (open, Apr 28): iPhone companion app feature request — out of scope, skip
- vibeislandapp/vibe-island: no new commits since Apr 22 — nothing actionable
- **No new actionable items.** All tasks (T-016 through T-049) remain as previously documented.

**Scouted (May 2, 2026) — v1.0.24 + post-v1.0.24 activity:**
- v1.0.24 released 2026-04-29
- **BATCH `61ab21e`/`7748e48`/`67d8039`/`78000a7`/`fecfed9`** (Apr 29): main-thread hardening — `ProcessRunner` with timeout for `detectClaudeVersion`; move hook installation + `verifyAndRepair` off main thread; cap `TerminalActivator`/`VisibilityDetector` subprocess waits; dispatch Ghostty activation off main. Upstream fix for T-048 now available → **T-048 promote to implement**
- **`d71b11e`** (Apr 29): opt-in setting to disable auto-expand panel on agent completion — guard in `enqueueCompletion()`, new `autoExpandOnCompletion` key (default true), toggle in Settings → Behavior → **T-050** (new, XS)
- **`ee25116` + `2cf2960`** (Apr 29): surface "+N Sub" purple tag + per-agent tooltip on session cards (#141) — `agentType` and `currentTool` already in typed `HookEvent`; `@ViewBuilder` helper extracted for perf → **T-049 promoted from Backlog investigate to Todo implement**
- **`af7bbb1`** (Apr 29): Settings → Plugin Sub-Sessions: separate/merge/hide (#123) — bridge stamps `_via_plugin` on ancestry-inferred events; "Merge" folds into parent session; "Hide" auto-approves and drops. Directly relevant for claude-mem and similar plugins that fire hooks inside a Claude session → **T-051** (new, S)
- **`94f7ca8` + `0972e8b`** (Apr 29): hook event ring buffer — last 100 events in-memory, exported to `state/hook-events.json` in diagnostics; hardens `UserPromptSubmit` prompt extraction → **T-052** (new, S)
- **`e18f884`** (Apr 30): stop blanket-draining pending permissions on activity events (#147) — replaces "drain all" with surgical `tool_use_id`-targeted drain; fixes parallel MCP/plugin race where one completion denied another tool's pending permission; 2 regression tests added → cherry-pick alongside T-040; add to T-040 criteria
- **`257778b`** (Apr 30): fix: honor user default mascot when no session is actively working (#149) — trigger changed `totalSessionCount == 0` → `summary.status == .idle`; idle-with-sessions now shows default mascot → add to T-041 criteria
- `7d475b4` (Apr 30): collapse Cursor sub-agent processes onto one card (#148) — Cursor-specific, skip
- `b0a6989` (Apr 29): empty default `autoApproveTools` — T-042 should ship with empty default, not the old hardcoded list
- `a5331f3` (Apr 29): distinguish cursor-agent/qodercli source (#134) — Cursor-specific, skip
- PR #152 (open, May 1): route Codex subagent sessions by mode — Codex-specific, skip
- **Issue #150** (open, Apr 30): Claude Code 2.1.121 "quick-select" (快速选择) incompatibility — user reports tool selection error on click; no upstream fix yet → **T-053** (new, watch/investigate)
- Issue #151 (open, Apr 30): Codex native subagents shown as separate sessions — Codex-specific, skip
- vibeislandapp/vibe-island: `ba1c889` (Apr 22) remains the latest commit — docs/SEO only, nothing actionable

**Scouted (May 4, 2026) — post-v1.0.24 activity:**
- No new commits or releases since v1.0.24 (Apr 29); latest commit on main remains `257778b` (Apr 30)
- **PR #153** (open, May 2): "fix: 修复 AskUserQuestion 在新版 Claude Code 下的点击回答异常" — upstream fix for T-053 now has confirmed implementation: adds `askUserQuestionUpdatedInput()` private helper that builds `updatedInput` from `toolInput` base, preserves `questions` array, adds `answers` dict and backward-compat `answer` field; not yet merged into main → T-053 criteria already captures this accurately, status unchanged (implement now, don't wait for merge)
- PR #152 (open, May 1): route Codex subagent sessions by mode — Codex-specific, skip (unchanged)
- Issue #150 (open, Apr 30): Claude Code 2.1.121 incompatibility — PR #153 is the upstream fix; T-053 promoted from watch/investigate to **implement** (confirmed root cause + reference implementation)
- Issue #151 (open, Apr 30): Codex native subagents — Codex-specific, skip (unchanged)
- vibeislandapp/vibe-island: `ba1c889` (Apr 22) remains the latest commit — docs/SEO only, nothing actionable
- ⚠️ GitHub Issues are **disabled** in `nguyenvanduocit/CodeIsland` — all tracking via this kanban board only

**Scouted (May 8, 2026) — post-v1.0.24 activity:**
- No new commits or releases since v1.0.24; latest commit on main remains `257778b` (Apr 30)
- **PR #158** (open, May 7): "fix: preserve original questions in AskUserQuestion hook response" — second competing fix for T-053 bug; inline approach (3 targeted patches) vs PR #153's helper-method approach; root cause confirmed by user crash report in **Issue #157** (`"undefined is not an object (evaluating 'H.map')"` — Claude CLI loses `questions` array when `updatedInput` omits it) → T-053 criteria updated to reference PR #158 as simpler implementation path (our codebase has one answer path, not three, so no helper needed)
- PR #156 (open, May 6): "feat: add Cline support" — non-Claude CLI, skip
- **Issue #154** (open, May 4): "macmini M4多个桌面，只有在第一个桌面显示灵动岛" — panel permanently invisible on non-first desktops (Mac mini M4, no notch); filed AFTER v1.0.22 that contains `0850f35` T-035 fix; suggests T-035's fullscreen-space latch fix may be insufficient for non-notch multi-desktop case; upstream has no fix yet → T-035 criteria updated to note investigation needed for non-notch display path
- Issue #157 (open, May 7): AskUserQuestion crash — same root cause as T-053; PR #158 is the upstream fix (as above)
- Issue #155 (open, May 7): Codex PermissionRequest hook error — Codex-specific, skip
- Issues #159, #160 (open, May 7): kaku/opencode feature requests — non-Claude CLIs, skip
- vibeislandapp/vibe-island: `ba1c889` (Apr 22) remains the latest commit — docs/SEO only, nothing actionable

**Scouted (May 12, 2026) — post-v1.0.24 activity:**
- No new releases since v1.0.24 (Apr 29); 0 open PRs
- **`fa170b2`** (May 10): Merge pull request #153 — **T-053 fix confirmed merged**; source in kanban updated from "open" to "merged"
- **`d17709a`** (May 10): fix: resolve WezTerm-family panes by cli tty — adds `ttyForPid()` in `ProcessRunner.swift` (uses `ps -o tty=` with 5s timeout); `activateWeztermFamily()` now prefers dynamically-resolved TTY over captured env var when env has generic `/dev/tty`; same fallback in `TerminalVisibilityDetector.isWeztermFamilyTabActive()`. Part of T-055 batch (see below).
- `f5c92a5` (May 10): fix: pass flat hook events and complete IDE responses — `ConfigInstaller.swift` adds `--event` flag to flat hook format (TraeCli only); IDE completion sources (Cursor/Trae/CodeBuddy) now transition to idle. Flat hook format is TraeCli-specific; our bridge is a binary receiving event payload via stdin — not applicable. IDE-source completion is Cursor/Trae only. Skip.
- Cline support commits `6a28f06`, `50beca9`, `ccb0efd`, `d529682` (May 6–7), merge `ba86fbc` (May 10) — non-Claude CLI, skip
- Codex fixes `d119766`, `861adcf`, merges `acc0fc5`, `043e85a` (May 9–10) — Codex-specific, skip
- **⚠️ Missed from May 2+8 scouts — multiplexer terminal support batch (Apr 30):**
  - `4066315`: feat: support Zellij and Kaku jump-back, harden tmux multiplexer — Zellij: `ZELLIJ_PANE_ID`/`ZELLIJ_SESSION_NAME` env vars → `zellij action go-to-tab`; `parseZellijPaneId()` normalises `terminal_N`/numeric; Kaku (WezTerm fork): detected via bundle ID `fun.tw93.kaku`, shares `activateWeztermFamily()`; tmux: `switch-client -t` prefix for cross-session jumps; WezTerm: `WEZTERM_PANE` env var fast-path `wezterm cli activate-pane`; new `raiseAppWithoutQuickTerminal()` helper avoids Ghostty quick-terminal side-effect on Zellij activate; Bridge `main.swift` captures `ZELLIJ_PANE_ID`, `ZELLIJ_SESSION_NAME`, `WEZTERM_PANE`
  - `7b47019`: feat: detect Zellij and Kaku active pane in visibility checks — `TerminalVisibilityDetector.isZellijTabActive()` + `isWeztermFamilyTabActive()` updated with same tty priority
  - `06df412`: fix: persist multiplexer pane hints across app restarts — `SessionPersistence.PersistedSession` gains: `zellijPaneId`, `zellijSessionName`, `weztermPaneId`, `cmuxSurfaceId`, `cmuxWorkspaceId` — restored on session reload for precise post-restart jumps
  → **T-055** (new — missed two scouts; implement after T-020/T-039/T-045 which all touch `TerminalActivator.swift`)
- **Issue #169** (open, May 11): "claude code concurrent permission auto-rejection" — Claude Code 2.1.126; burst `PermissionRequest` events trigger "Denied by PermissionRequest hook" even after reinstall; no upstream fix beyond `0a6ab92` (T-040); confirms T-040 is still needed and not yet resolved upstream for all burst patterns
- vibeislandapp/vibe-island: `ba1c889` (Apr 22) remains the latest commit — nothing actionable

**Scouted (May 13, 2026) — post-v1.0.24 activity:**
- No new releases since v1.0.24 (Apr 29); latest release still v1.0.24
- `7e9697a` (May 10): fix: preserve remote opencode host identity — `RemoteInstaller.swift` + OpenCode remote hook JS/Python; OpenCode remote monitoring, skip
- `4fd5a64` (May 10): fix: resolve codex hooks and remote approval issues — new `CodexPermissionRules.swift`, `RemoteInstaller.swift` (+145), `codeisland-opencode-remote.js` (+301); Codex and OpenCode remote only; `TerminalVisibilityDetector.swift` (+57) and `PanelWindowController.swift` (-6) changes appear bundled — diff unavailable (rate limit); tentatively skip pending diff verification
- **PR #171** (open, May 12): "feat: 支持灵动岛宽度设置" — extends island width slider to real notch MacBooks (T-021 currently scope is non-notch only); changes guard from `guard !hasNotch else { return notchW }` to apply `collapsedWidthScale` on real notch too; compact/idle placeholder widths unified to scaled value; unit tests included; watch for merge → **update T-021 criteria when merged**
- PR #175 (open, May 12): fix: remove legacy codex hooks config — Codex `codex_hooks` migration to `hooks=true`; Codex-specific, skip
- **Issue #170** (open, May 12): "claude-code CLI plan mode interaction failure" — questions re-appear after answering in plan mode; likely symptom of T-053 (missing `questions` in AskUserQuestion `updatedInput`); upstream fix `fa170b2` (T-053) should resolve; no separate action needed — note in T-053 source
- **Issue #176** (open, May 12): "dual-screen panel jumps between physical monitors" — panel can't be pinned to preferred screen in two-monitor setup; no upstream fix yet; distinct from T-035 (Space-switching latch) → **T-056** (new)
- Issue #177 (open, May 13): support jumping to Claude Desktop App — out of scope (we are Claude Code CLI only), skip
- Issue #172 (open, May 12): adjust non-notch island length — same request as PR #171 / T-021, skip (already tracked)
- Issue #169 (May 11): already documented in May 12 scout
- vibeislandapp/vibe-island: `ba1c889` (Apr 22) remains the latest commit — nothing actionable

**Scouted (May 14, 2026) — post-v1.0.24 activity:**
- No new commits or releases since v1.0.24 (Apr 29); most recent upstream activity remains May 10 (already documented in May 12/13 scouts)
- Diff verification of `4fd5a64` (May 10) — previously "tentatively skip pending diff verification": `TerminalVisibilityDetector.swift` (+57) adds `isGhosttySessionVisibleInAnyWindow(_:)` — uses `CGWindowListCopyWindowInfo` to enumerate visible windows; matches by Ghostty bundle ID, session CWD (normalises `~`), and window title; suppresses approval/question UI when Ghostty Quick Terminal is already visible even when not system-frontmost. This is the upstream fix for T-054 → **T-054 promote to implement**
- Diff verification of `4fd5a64` `PanelWindowController.swift` (-6): removes menu bar gap fallback (`menuBarGap = screen.frame.maxY - screen.visibleFrame.maxY; if menuBarGap < 1 { return true }`); was a false-positive shortcut triggering when menu bar is hidden (fullscreen mode); removed in favour of other visibility mechanisms — may be relevant to T-035; port alongside T-035 `0850f35` changes
- PR #171 (island width for real notch): still open, T-021 criteria already updated to include it; no change
- No new PRs or issues affecting us since May 13 scout
- vibeislandapp/vibe-island: `ba1c889` (Apr 22) remains the latest commit — nothing actionable

**Scouted (May 16, 2026) — post-v1.0.24 activity:**
- No new commits or releases since v1.0.24 (Apr 29); latest upstream commit remains May 10 (same as May 14 scout)
- **Issue #179** (open, May 15): "multiple terminal windows — clicking island card can't jump to the correct terminal after switching" — user reports that when multiple terminal windows are open and they switch to another window, clicking a prior session's island card fails to focus the right one; no upstream fix yet; this scenario is addressed by the cascading tty-match strategy in T-039 and window-level matching in T-020; T-039 criteria updated to add explicit multi-window test → **no new task needed, T-039 covers it**
- PR #171 (island width for real notch): still open, T-021 unchanged
- PR #175 (remove legacy Codex hooks config): Codex-specific, skip
- vibeislandapp/vibe-island: `ba1c889` (Apr 22) remains the latest commit — nothing actionable

**Scouted (May 17, 2026) — post-v1.0.24 activity:**
- No new commits or releases since v1.0.24 (Apr 29); latest upstream commit still `d17709a` / `fa170b2` batch (May 10) — upstream quiet for 7 days
- PR #171 (island width for real notch): still open, still watching — T-021 unchanged
- PR #174 (CLOSED, May 12): "fix: clean hooks config and adhoc signing" — closed without merging (force-pushed, branch deleted); CI/release only, skip
- PR #175 (remove legacy Codex hooks config): Codex-specific, skip (unchanged)
- **`2c98861`** (May 2): "fix: preserve AskUserQuestion payload in PermissionRequest" — missed in May 4+8 scouts due to commit date ambiguity; adds `askUserQuestionUpdatedInput()` helper that was later merged as PR #153 (`fa170b2`, May 10); fully captured under T-053; no new task
- Issues #177 (Claude Desktop App support), #178 (ESP32 hardware) — skip (out of scope)
- vibeislandapp/vibe-island: `ba1c889` (Apr 22) remains the latest commit — nothing actionable
- **No new actionable items.** All open tasks documented in prior scouts remain as-is (T-016 through T-056). Note: GitHub Issues are disabled in nguyenvanduocit/CodeIsland; all tracking via kanban board only.

**Scouted (May 18, 2026) — post-v1.0.24 activity:**
- No new commits or releases since v1.0.24 (Apr 29); latest upstream commit still `d17709a` / `fa170b2` batch (May 10) — upstream quiet for 8 days
- PR #166 (CLOSED, May 10): "feat: multi-agent collaboration + Cursor hook event fix" — closed without merging; Cursor-specific, nothing to cherry-pick
- PR #171 (island width for real notch): still open, T-021 unchanged
- PR #175 (remove legacy Codex hooks config): Codex-specific, skip (unchanged)
- Issues #170 (plan mode, May 15) and #179 (multi-terminal jump, May 15): both already documented in May 13 and May 16 scouts respectively; no upstream fixes yet
- vibeislandapp/vibe-island: `ba1c889` (Apr 22) remains the latest commit — nothing actionable
- **No new actionable items.** All open tasks (T-016 through T-056) remain as previously documented. GitHub Issues are disabled in nguyenvanduocit/CodeIsland; all tracking via kanban board only.

**Scouted (May 19, 2026) — post-v1.0.24 activity:**
- No new commits or releases since v1.0.24 (Apr 29); latest upstream commit still `d17709a` / `fa170b2` batch (May 10) — upstream quiet for 9 days
- PR #171 (island width for real notch): still open, T-021 unchanged
- PR #175 (remove legacy Codex hooks config): Codex-specific, skip (unchanged)
- **Issue #180** (open, May 18): "手动已经在 cli 里选择了操作，但是刘海屏仍然展示选项" — panel stays stuck showing approval/question prompt after user answers directly in the terminal CLI instead of via island panel. Affects Claude Code sessions. No upstream fix yet → **T-057** (new)
- **Issue #181** (open, May 18): Codex auto-review mode triggers CodeIsland approval — Codex-specific, skip
- **Issue #182** (open, May 18): respect user-deleted Codex hook entries — Codex-specific, skip
- vibeislandapp/vibe-island: `ba1c889` (Apr 22) remains the latest commit — nothing actionable
- **One new task added (T-057).** All other open tasks (T-016 through T-056) remain as previously documented. GitHub Issues are disabled in nguyenvanduocit/CodeIsland; all tracking via kanban board only.

**Scouted (May 20, 2026) — post-v1.0.24 activity:**
- No new commits or releases since v1.0.24 (Apr 29); latest upstream commit still `d17709a` / `fa170b2` batch (May 10) — upstream quiet for 10 days
- No new PRs (most recent activity May 12: PR #171 island-width for real notch, PR #175 legacy Codex hooks — both already tracked)
- No new issues (most recent May 18: issues #180/#181/#182, all already documented in May 19 scout)
- vibeislandapp/vibe-island: `ba1c889` (Apr 22) remains the latest commit — nothing actionable
- **No new actionable items.** All open tasks (T-016 through T-057) remain as previously documented. GitHub Issues are disabled in nguyenvanduocit/CodeIsland; all tracking via kanban board only.

**Scouted (May 22, 2026) — post-v1.0.24 activity:**
- No new commits or releases since v1.0.24 (Apr 29); latest upstream commit still `d17709a` / `fa170b2` batch (May 10) — upstream quiet for 12 days
- PR #171 (island width for real notch): still open — T-021 unchanged
- PR #175 (remove legacy Codex hooks config): still open — Codex-specific, skip
- **PR #187** (open, May 21): "Improve Buddy Bluetooth recovery and signing" — ESP32/BLE hardware companion; `ESP32BridgeManager`, `ESP32StatePublisher`, `ESP32Protocol` changes only; out of scope for our macOS-app-only fork; skip
- **Issue #185** (open, May 21): "为什么我设置了外接显示器，但是我显示器还是没有？" — external monitor shows nothing; user confirms island only appears on MacBook built-in display even with external connected; screenshot provided; no upstream fix → reinforces T-056 (updated criteria)
- **Issue #186** (open, May 21): "Cannot display island on external monitor when both displays are active" — M5 Pro + Samsung 4K; display selector dropdown shows only "Built-in Retina Display" with no external-monitor option; clamshell (lid-closed) mode works fine; active dual-display mode does not → adds a new concrete failure mode to T-056: `ScreenDetector` fails to enumerate or surface external monitors in the settings picker when both displays are active; no upstream fix → T-056 criteria updated
- **Issue #188** (open, May 21): "Exploring an Apple ecosystem companion for CodeIsland" — proposal to build iPhone/Watch companion using MultipeerConnectivity; feature concept only, out of scope; skip
- **Issue #169** (updated May 21): burst permission auto-rejection — still open, no new upstream fix; T-040 still the correct resolution path
- **Issue #184** (open, May 20): "Windows version?" — out of scope; skip
- **Issue #183** (open, May 20): "Support custom CLI tools?" — out of scope for Claude Code-only fork; skip
- vibeislandapp/vibe-island: `ba1c889` (Apr 22) remains the latest commit — nothing actionable
- **T-056 updated** with new failure angle from issues #185/#186 (display picker missing external monitor option). No new tasks. All other open tasks (T-016 through T-057) remain as previously documented. GitHub Issues are disabled in nguyenvanduocit/CodeIsland; all tracking via kanban board only.

**Scouted (May 23, 2026) — post-v1.0.24 activity:**
- No new commits or releases since v1.0.24 (Apr 29); latest upstream commit still `d17709a` / `fa170b2` batch (May 10) — upstream quiet for 13 days
- **Issue #189** (open, May 22): "2026/05/22 不支持新版Antigravity" — Antigravity is a non-Claude CLI; not applicable to our Claude Code-only fork; skip
- PR #171 (island width for real notch): still open — T-021 unchanged
- PR #175 (remove legacy Codex hooks config): still open — Codex-specific, skip
- PR #187 (Buddy Bluetooth recovery): still open — ESP32/BLE hardware, skip
- vibeislandapp/vibe-island: `ba1c889` (Apr 22) remains the latest commit — docs/SEO only, nothing actionable
- **No new actionable items.** All open tasks (T-016 through T-057) remain as previously documented. GitHub Issues are disabled in nguyenvanduocit/CodeIsland; all tracking via kanban board only.

**Scouted (May 24, 2026) — post-v1.0.24 activity:**
- No new commits or releases since v1.0.24 (Apr 29); latest upstream commit still `7e9697a` (May 10) — upstream quiet for 14 days
- **Issue #190** (open, May 23): "ssh 连接失败" — SSH remote connection failure; SSH remote monitoring feature, not applicable to our Claude Code-only fork; skip
- PR #171 (island width for real notch): still open — T-021 unchanged
- PR #175 (remove legacy Codex hooks config): still open — Codex-specific, skip
- PR #187 (Buddy Bluetooth recovery): still open — ESP32/BLE hardware, skip
- vibeislandapp/vibe-island: `ba1c889` (Apr 22) remains the latest commit — docs/SEO only, nothing actionable
- **No new actionable items.** All open tasks (T-016 through T-057) remain as previously documented. GitHub Issues are disabled in nguyenvanduocit/CodeIsland; all tracking via kanban board only.

**Scouted (May 25, 2026) — post-v1.0.24 activity:**
- No new commits or releases since v1.0.24 (Apr 29); latest upstream commit still `7e9697a` (May 10) — upstream quiet for 15 days
- **PR #191** (open, May 24): "fix(AskUserQuestion): always include questions key and use question text as answer key" — reveals a **second bug** in our AskUserQuestion response not covered by PR #153 or current T-053 criteria: answer key uses `header` field but Claude Code looks up answers via the question text (`answers[question.question]`); all answers silently return empty string. Also ensures `questions` is always present in `updatedInput`. Our `RequestQueueService.swift:111` has `let answerKey = pending.question.header ?? "answer"` — should be `pending.question.question` → **T-053 criteria updated to include answer-key fix**
- PR #171 (island width for real notch): still open — T-021 unchanged
- PR #175 (remove legacy Codex hooks config): Codex-specific, still open — skip
- PR #187 (Buddy Bluetooth recovery): still open — ESP32/BLE hardware, skip
- vibeislandapp/vibe-island: `ba1c889` (Apr 22) remains the latest commit — nothing actionable
- ⚠️ GitHub Issues are **disabled** in `nguyenvanduocit/CodeIsland` — all tracking via kanban board only

**Scouted (May 26, 2026) — post-v1.0.24 activity:**
- No new commits or releases since v1.0.24 (Apr 29); latest upstream commit still `7e9697a` / `fa170b2` batch (May 10) — upstream quiet for 16 days
- **Issue #192** (open, May 25): "目前支持 ssh 远程的 custom cli 吗？" — user asking if remote SSH custom CLIs are supported; SSH remote monitoring not applicable to our Claude Code-only fork; skip
- PR #191 (AskUserQuestion double-fix): still open — T-053 criteria already updated in May 25 scout; no change
- PR #171 (island width for real notch): still open — T-021 unchanged
- PR #175 (remove legacy Codex hooks config): Codex-specific, still open — skip
- PR #187 (Buddy Bluetooth recovery): still open — ESP32/BLE hardware, skip
- vibeislandapp/vibe-island: `ba1c889` (Apr 22) remains the latest commit — nothing actionable
- **No new actionable items.** All open tasks (T-016 through T-057) remain as previously documented. GitHub Issues are disabled in nguyenvanduocit/CodeIsland; all tracking via kanban board only.

**Scouted (May 27, 2026) — v1.0.25 activity:**
- v1.0.25 released 2026-05-26
- **PR #171 MERGED** (`0929926`, v1.0.25): "feat: 支持灵动岛宽度设置" — island width slider now applies to real notch MacBooks, not just non-notch; was watching; T-021 criteria was already updated; source updated in kanban → **T-021 ready to implement**
- **PR #191 MERGED** (`29157ed`, v1.0.25): "fix(AskUserQuestion): always include questions key and use question text as answer key" — confirms both T-053 bugs fixed upstream: (1) `questions` always in `updatedInput`, (2) answer key uses question text not header; T-053 criteria was already correct → no criteria change needed; source updated in kanban
- **`e1faa46`** (v1.0.25): "fix(permissions): don't deny parallel tool calls sharing a tool_use_id (#169)" — follow-up fix to `AppState+ToolUseCache.swift` (T-040's target file); adds `toolInput` dictionary comparison before treating same-`tool_use_id` requests as duplicates; without this, parallel reads/writes (different paths, same `tool_use_id`) are incorrectly all denied; +11 lines + 43-line test; **T-040 criteria updated** to require porting `e1faa46` alongside `0a6ab92` → **must port both commits together**
- `6392b30` (v1.0.25): fix SSH remote Hermes hook install — SSH remote, skip
- `be8bec4` (v1.0.25): Codex hook auto-repair — Codex-specific, skip
- `6c7d66c` (v1.0.25): Buddy Bluetooth recovery — ESP32/BLE hardware, skip
- `14c2c10` (v1.0.25): silence JSONLTailer concurrent-capture test warnings — test-only, skip
- Issue #192 (SSH custom CLI): closed or no new info; skip
- PR #175 (remove legacy Codex hooks): Codex-specific, merged in this release — skip
- PR #187 (Buddy Bluetooth recovery): merged in this release — hardware, skip
- vibeislandapp/vibe-island: `ba1c889` (Apr 22) remains the latest commit — nothing actionable
- ⚠️ GitHub Issues are **disabled** in `nguyenvanduocit/CodeIsland` — all tracking via kanban board only

**Scouted (May 29, 2026) — post-v1.0.25 activity:**
- No new releases since v1.0.25 (May 26); upstream quiet for 3 days
- PR #197 (open, May 27): pi + OMP coding-agent integration — non-Claude CLI, skip
- Issue #196 (open, May 27): pi coding-agent integration request — non-Claude CLI, skip
- PR #195 (closed immediately May 27): "Fix plan mode answer and reduce CPU/MEM usage" — opened and closed within 1 minute (erroneous/duplicate PR); no content to extract; skip
- **Issue #198** (open, May 27): iTerm2 fullscreen/cross-Space jump failure — clicking a session card when iTerm2 is fullscreen or on another Space fails to focus the correct window/tab; no upstream fix yet; covered by T-020 (which includes iTerm2 in criteria); add explicit multi-window/fullscreen test scenario to T-020 criteria
- Issue #199 (open, May 28): Cursor multi-workspace jump — Cursor-specific, skip
- **Issue #200** (open, May 28): dual permission prompt — user reports that after installing CodeIsland, both the CodeIsland island panel AND Claude Code's own in-terminal prompt appear simultaneously for every `PermissionRequest`; must answer in both places for tool call to proceed. Our bridge already blocks on `recvAll()` and forwards the server response to stdout (lines 320–327 of `main.swift`). Likely cause: our `HookResponse.permission()` format (`{"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": {"behavior": "allow"}}}`) may not match what Claude Code's newer versions expect (`{"hookSpecificOutput": {"hookEventName": "PermissionRequest", "permissionDecision": "allow"}}`). No upstream fix yet — upstream is also investigating → **T-058** (new, high priority, XS)
- **`be8bec4`** (v1.0.25, May 26, re-evaluated): "fix(codex): respect user-deleted hook events during auto-repair" — was classified "Codex-specific, skip" in May 27 scout, but on review the `shouldPreservePartialHooks` logic is a general `verifyAndRepair()` improvement: if a user intentionally deletes a subset of our `~/.claude/settings.json` hook events, we forcibly restore them on next repair. Applicable to our Claude Code installer. Low priority since the scenario is rare → **T-059** (new, low priority, XS)
- vibeislandapp/vibe-island: `ba1c889` (Apr 22) remains the latest commit — nothing actionable
- ⚠️ GitHub Issues are **disabled** in `nguyenvanduocit/CodeIsland` — all tracking via kanban board only

**Scouted (May 31, 2026) — v1.0.26 + v1.0.27 activity:**
- v1.0.26 released 2026-05-30
- v1.0.27 released 2026-05-30
- **`f42e264` + `2fad1b1`** (v1.0.26, May 30): iTerm2 fullscreen/cross-Space jump fix — adds `select <window>` to all three iTerm2 match paths (session-id, tty, cwd) so a fullscreen window is raised and macOS switches to its Space; hardening wraps each `select <window>` in its own `try` so a mid-transition failure can't abort the surrounding script and silently skip the tab/session select. We have the same bug (no iTerm2 window-level select in our activation paths) → **T-060** (new, high priority, XS)
- `209959d` (v1.0.26, May 30): pi/OMP coding-agent integration — non-Claude CLI, skip
- SSH remote changes bundled in `f42e264` (remote uid probe) and `ef7db33` (custom CLI remote hooks) — SSH remote feature, skip
- **`c406771`** (v1.0.27, May 30): IDE multi-window CWD matching for agent sources — extends `activateIDEWindow(bundleId:cwd:)` to Cursor/Trae/Qoder/Factory *agent source* sessions when multiple workspace windows are open; NOT applicable to us (our sessions have terminal sources, not IDE agent sources; the existing `activateIDEWindow` path for IDE-integrated terminals was already correct); skip
- **PR #205 MERGED** (May 31, commit `f878234`): Warp tab activation improvements — `NSWorkspace.openApplication` raise (more reliable than `NSRunningApplication.activate()`); removes SQLite `nolock=1` flag (was failing on default macOS volumes); adds case-insensitive CWD matching; waits until Warp is frontmost before sending Cmd+digit tab shortcut; smart-suppress now checks Warp's active tab state (not just "is Warp frontmost"). Merged into main after the v1.0.27 release tag → **T-044 gate cleared; ready to implement; update source to include `f878234`**
- **Issue #200 closed "not_planned"** (May 30): upstream will not fix the dual permission prompt — T-058 must be resolved independently
- **Issue #169 closed "completed"** (May 30): burst permission auto-rejection confirmed fixed upstream via `0a6ab92` + `e1faa46` (T-040 criteria already captures this)
- **Issues #179, #198 closed "completed"** (May 30): multi-terminal jump and iTerm2 fullscreen jump — both closed after upstream fix in `f42e264`; confirms T-060 is the right cherry-pick
- **PR #207 MERGED** (May 31, commit `3eeafe9`): SSH stale remote socket cleanup before -R forwarding — SSH remote feature, skip
- vibeislandapp/vibe-island: `ba1c889` (Apr 22) remains the latest commit — nothing actionable
- ⚠️ GitHub Issues are **disabled** in `nguyenvanduocit/CodeIsland` — all tracking via kanban board only

**Scouted (June 1, 2026) — post-v1.0.27 activity:**
- No new releases since v1.0.27 (May 30); latest upstream activity is May 31
- **`f878234`** (May 31): **PR #205 MERGED** — Warp tab activation overhaul: `raiseAppWithoutQuickTerminal()` replaces blanket `NSRunningApplication.activate()` so Ghostty Quick Terminal is not triggered; Cmd+digit keystroke sent only once Warp is frontmost (retry loop); Cmd+9 maps to last tab (not 9th); SQLite opened without `nolock=1` (WAL writes now honoured); case-insensitive CWD matching. Also adds `isWarpSessionTabActive()` to `TerminalVisibilityDetector`. This was the explicit gate in T-044 criteria ("check if PR #205 has merged before implementing") → **T-044 gate cleared; source updated to include `f878234`; ready to implement**
- `3eeafe9` (May 31): SSH stale remote socket cleanup (#206/#207) — SSH remote, skip
- vibeislandapp/vibe-island: `ba1c889` (Apr 22) remains the latest commit — nothing actionable
- ⚠️ GitHub Issues are **disabled** in `nguyenvanduocit/CodeIsland` — all tracking via kanban board only

**Scouted (June 2, 2026) — post-v1.0.27 activity:**
- No new releases since v1.0.27 (May 30); only activity since May 31 scout is PR #205 merge commit and one SSH fix
- **`f878234`** (May 31): Warp tab activation overhaul (PR #205 merged) — already documented in May 31 scout; T-044 gate cleared, no change
- `3eeafe9` (May 31): SSH remote stale socket cleanup (PR #207 merged) — SSH remote, skip (unchanged)
- **PR #208** (open, May 31): "Refine notch hover timing and width scaling" — new 3-state hover machine (`collapsed → prehover → expanded`); quick pass-through reverses first-stage animation instead of opening full panel; expand after 0.5s, collapse 0.5s after leave; width slider 1% steps (was 10%), range unchanged (50%–150%); constants centralised in `NotchWidthScale`. Not yet merged → **T-061** (new, watch). Note: the 1% slider refinement is a natural addition to **T-021** criteria — update T-021 to note this when implementing the width slider.
- **Issue #212** (open, Jun 1): "使用 Cmux 多 session 时，所有会话会被一起展开" — user reports that with cmux + multiple sessions, ALL sessions in the panel expand simultaneously when one is clicked; no upstream fix yet; cmux is supported in our app (T-022 tracks pane-precise jump); this is a different issue (UI expand-group bug, not a jump bug) → **T-062** (new, investigate)
- **Issue #210** (open, Jun 1): "How to temporarily hide AskUserQuestion panel?" — user wants to dismiss/defer question or have panel hide when terminal opens; reinforces T-057 (stuck panel after in-terminal answer) and T-027 (auto-collapse after jump); no new upstream fix → T-057 criteria updated to note this user scenario
- **Issue #211** (open, Jun 1): Claude Desktop / Codex Desktop support request — out of scope for Claude Code-only fork; skip
- **Issue #209** (open, Jun 1): Codex plan mode can't trigger CodeIsland — Codex-specific, skip
- vibeislandapp/vibe-island: `ba1c889` (Apr 22) remains the latest commit — nothing actionable
- ⚠️ GitHub Issues are **disabled** in `nguyenvanduocit/CodeIsland` — all tracking via kanban board only

**Scouted (June 3, 2026) — post-v1.0.27 activity:**
- No new commits or releases since v1.0.27 (May 30); latest upstream activity remains May 31 (same as June 1/2 scouts) — upstream quiet for 3 days
- **Issue #213** (open, Jun 2): "Clicking a session should focus the corresponding terminal window/tab" — user running "Superset" terminal, an unsupported terminal app; `sessions.json` only contains `termApp`/`cliPid`/`sessionId` with no window/tab mapping; no upstream fix yet; not actionable for us (Superset is not a supported terminal); skip
- PR #208 (open, May 31): "Refine notch hover timing and width scaling" — still open, T-061 unchanged
- vibeislandapp/vibe-island: `ba1c889` (Apr 22) remains the latest commit — nothing actionable
- ⚠️ GitHub Issues are **disabled** in `nguyenvanduocit/CodeIsland` — all tracking via kanban board only
- **No new actionable items.** All open tasks (T-016 through T-062) remain as previously documented.

**Scouted (June 4, 2026) — post-v1.0.27 activity:**
- No new commits or releases since v1.0.27 (May 30); latest upstream commit remains `f878234` (May 31, Warp tab fix) — upstream quiet for 4 days
- **Issue #215** (open, Jun 3): "Support Google Antigravity 2 hooks" — non-Claude CLI (Antigravity 2), skip
- **Issue #214** (open, Jun 3): "Unable to reconnect to remote - 1.0.27 — ssh exited(255)" — SSH remote feature, not applicable to our Claude Code-only fork; skip
- PR #208 (open, May 31): "Refine notch hover timing and width scaling" — still open, T-061 unchanged
- vibeislandapp/vibe-island: `ba1c889` (Apr 22) remains the latest commit — nothing actionable
- ⚠️ GitHub Issues are **disabled** in `nguyenvanduocit/CodeIsland` — all tracking via kanban board only
- **No new actionable items.** All open tasks (T-016 through T-062) remain as previously documented.

**Scouted (June 5, 2026) — post-v1.0.27 activity:**
- No new commits or releases since v1.0.27 (May 30); latest upstream commit remains `f878234` (May 31, Warp tab fix) — upstream quiet for 5 days
- **Issue #216** (open, Jun 4): "Permission approval panel does not auto-dismiss after approving from terminal" — third report of T-057 (after issue #180 May 18 and issue #210 Jun 1); user approves via terminal CLI, island panel stays stuck showing the pending item; no upstream fix yet → T-057 criteria already accurate; no priority change (still low)
- **Issue #217** (open, Jun 4): "快捷键不生效" (keyboard shortcuts not working) — global hotkeys work briefly after restart but stop registering when the app loses focus; global shortcuts are explicitly listed as "Unsynced from v1.0.7" in our fork; not applicable
- **PR #218** (open, Jun 4): "feat(companion): add iPhone Buddy app and watch sync" — full iOS/watchOS companion app (Dynamic Island, Lock Screen widget, Apple Watch app, Bluetooth sync bridge); out of scope for macOS-only fork; skip
- PR #208 (open, May 31): "Refine notch hover timing and width scaling" — still open, T-061 unchanged
- vibeislandapp/vibe-island: `ba1c889` (Apr 22) remains the latest commit — nothing actionable
- ⚠️ Correction to prior scout note: GitHub Issues are **enabled** (not disabled) in `nguyenvanduocit/CodeIsland` — issues list is currently empty, not disabled. All task tracking remains in `.kanban/board.md`.
- **No new actionable items.** All open tasks (T-016 through T-062) remain as previously documented.

**Scouted (June 6, 2026) — post-v1.0.27 activity:**
- No new commits or releases since v1.0.27 (May 30); latest upstream commit remains `f878234` (May 31, Warp tab fix) — upstream quiet for 6 days
- Open PRs: #208 (prehover hover timing, T-061 — still watching) and #218 (iPhone companion app — skip, out of scope); no new PRs
- No new issues since June 5 scout; upstream issues page unchanged
- vibeislandapp/vibe-island: `ba1c889` (Apr 22) remains the latest commit — nothing actionable
- **No new actionable items.** All open tasks (T-016 through T-062) remain as previously documented. GitHub issues list in `nguyenvanduocit/CodeIsland` remains empty (0 issues).

**Scouted (June 7, 2026) — post-v1.0.27 activity:**
- No new commits or releases since v1.0.27 (May 30); latest commit remains `f878234` (May 31, Warp tab fix) — upstream quiet for 7 days
- PR #208 (open, May 31): "Refine notch hover timing and width scaling" — still open, T-061 unchanged
- PR #218 (open, Jun 4): iPhone companion app — still open; hardware/iOS companion, skip (out of scope)
- **Issue #219** (open, Jun 6): "外接显示器时与 Bartender 5 重叠" — panel visually overlaps with Bartender 5 (popular macOS menu bar manager) on external display; screenshot attached; no upstream fix yet; distinct from T-056 (which covers display picker enumeration and cross-screen jumping): this is a Y-position conflict with Bartender 5's managed menu bar overlay on non-notch external displays → **T-063** (new)
- **Issue #216** (open, Jun 4): third confirmation of T-057 (stuck panel after in-terminal answer) — T-057 criteria updated to note this additional report
- Issue #217 (open, Jun 4): global shortcuts stop registering after focus loss — global shortcuts explicitly "Unsynced from v1.0.7"; not applicable to our fork; skip
- vibeislandapp/vibe-island: `ba1c889` (Apr 22) remains the latest commit — nothing actionable
- ⚠️ GitHub Issues are **disabled** in `nguyenvanduocit/CodeIsland` — all tracking via kanban board only

**Scouted (June 8, 2026) — post-v1.0.27 activity:**
- No new commits or releases since v1.0.27 (May 30); latest commit remains `f878234` (May 31, Warp tab fix) — upstream quiet for 8 days
- PR #208 (open, May 31): "Refine notch hover timing and width scaling" — still open, T-061 unchanged
- PR #218 (open, Jun 4): iPhone companion app — still open; hardware/iOS companion, skip (out of scope)
- Issues: no new issues since June 7 scout; upstream issues page unchanged
- vibeislandapp/vibe-island: `ba1c889` (Apr 22) remains the latest commit — nothing actionable
- **No new actionable items.** All open tasks (T-016 through T-063) remain as previously documented.

**Scouted (June 9, 2026) — post-v1.0.27 activity:**
- No new commits or releases since v1.0.27 (May 30); latest commit remains `f878234` (May 31, Warp tab fix) — upstream quiet for 9 days
- **PR #222** (open, Jun 8): "feat: support Pi / OMP sessions and add a Pi mascot" — Pi/Oh-My-Pi is a non-Claude CLI; skip
- **Issue #220** (open, Jun 8): "cursor终端中打开的cc显示cursor图标" — when Claude Code is launched from inside Cursor IDE's integrated terminal, the session card shows the Cursor icon instead of the Claude Code icon; `ProcessScanner` likely classifies the session as a Cursor source because Cursor is the nearest ancestor in the process tree; no upstream fix yet → **T-064** (new, low priority, XS)
- Issue #221 (open, Jun 8): DingTalk robot approval push — request to integrate with DingTalk (Chinese enterprise messaging) for remote approval; external service integration, not applicable; skip
- Issue #143 (updated Jun 8): pi-coding-agent support closed/completed upstream — Pi is non-Claude CLI; skip
- PR #208 (open, May 31): "Refine notch hover timing and width scaling" — still open, T-061 unchanged
- PR #218 (open, Jun 4): iPhone companion app — still open; hardware/iOS companion, skip
- vibeislandapp/vibe-island: `ba1c889` (Apr 22) remains the latest commit — nothing actionable
- ⚠️ GitHub Issues are **disabled** in `nguyenvanduocit/CodeIsland` — all tracking via kanban board only

**Scouted (June 10, 2026) — post-v1.0.27 activity:**
- No new commits or releases since v1.0.27 (May 30); latest commit remains `f878234` (May 31, Warp tab fix) — upstream quiet for 10 days
- **Issue #223** (open, Jun 9): "请求支持 TRAE SOLO" — Trae Solo (standalone Trae IDE) support request; non-Claude CLI, skip
- PR #222 (open, Jun 8): Pi / OMP mascot — still open; non-Claude CLI, skip (unchanged from Jun 9 scout)
- PR #208 (open, May 31): "Refine notch hover timing and width scaling" — still open, T-061 unchanged
- PR #218 (open, Jun 4): iPhone companion app — still open; hardware/iOS companion, skip
- vibeislandapp/vibe-island: `ba1c889` (Apr 22) remains the latest commit — nothing actionable
- **No new actionable items.** All open tasks (T-016 through T-064) remain as previously documented. GitHub issues list in `nguyenvanduocit/CodeIsland` is empty (0 issues open).

**Scouted (June 11, 2026) — post-v1.0.27 activity:**
- No new commits or releases since v1.0.27 (May 30); latest upstream commit remains `f878234` (May 31, Warp tab fix) — upstream quiet for 11 days
- PR #208 (open, May 31): "Refine notch hover timing and width scaling" — still open, T-061 unchanged
- PR #218 (open, Jun 4): iPhone companion app — still open; hardware/iOS companion, skip (out of scope)
- PR #222 (open, Jun 8): Pi/OMP mascot — still open; non-Claude CLI, skip
- **Issue #224** (open, ~Jun 10): "没有任何会话在运行中，但灵动岛还是弹出待确认的提示" — no sessions running but island still shows a pending approval/question prompt; session ended (Stop event, crash, or process exit) while a PermissionRequest or AskUserQuestion was queued; `RequestQueueService` retains the orphaned item and the bar remains rendered. Distinct from T-057 (session still alive, user answered via terminal). Fix: drain pending queue entries for the session in `.removeSession` side-effect handler → **T-065** (new, high priority, XS)
- **Issue #225** (open, ~Jun 10): "性能释放问题,CPU占用过高" — "performance/resource release, CPU usage too high"; additional user report confirming T-033 (screen-poll interval 1s → 5s) is needed and still unimplemented; no new code to cherry-pick; T-033 criteria unchanged
- vibeislandapp/vibe-island issue #107: "hooks 写入 settings.json 时把ccstatusLine 配置覆盖掉了" — hooks reformat settings.json and overwrite unrelated keys; same root cause as T-034 (destructive reformat via JSONSerialization + sortedKeys); upstream fix already available as `adf41b6`; T-034 criteria unchanged
- vibeislandapp/vibe-island: `ba1c889` (Apr 22) remains the latest commit — nothing actionable
- ⚠️ GitHub Issues are **disabled** in `nguyenvanduocit/CodeIsland` (API returns 410) — all tracking via kanban board only

**Scouted (June 12, 2026) — post-v1.0.27 activity:**
- No new commits or releases since v1.0.27 (May 30); latest upstream commit remains `f878234` (May 31, Warp tab fix) — upstream quiet for 12 days
- PR #208 (open, May 31): "Refine notch hover timing and width scaling" — still open, T-061 unchanged
- PR #218 (open, Jun 4): iPhone companion app — still open; hardware/iOS companion, skip (out of scope)
- PR #222 (open, Jun 8): Pi/OMP mascot — still open; non-Claude CLI, skip
- No new issues since June 11 scout; issues #219–#225 already documented
- vibeislandapp/vibe-island: `ba1c889` (Apr 22) remains the latest commit — nothing actionable
- `nguyenvanduocit/CodeIsland` issue tracker confirmed empty (0 issues; tracker is enabled but has no entries)
- **No new actionable items.** All open tasks (T-016 through T-065) remain as previously documented.

**Scouted (June 13, 2026) — post-v1.0.27 activity:**
- No new commits or releases since v1.0.27 (May 30); latest upstream commit remains `f878234` (May 31, Warp tab fix) — upstream quiet for 13 days
- PR #208 (open, May 31): "Refine notch hover timing and width scaling" — still open, T-061 unchanged
- PR #218 (open, Jun 4): iPhone companion app — still open; hardware/iOS companion, skip (out of scope)
- PR #222 (open, Jun 8): Pi/OMP mascot — still open; non-Claude CLI, skip
- No new issues or PRs since June 12 scout; all issues #209–#225 already documented
- vibeislandapp/vibe-island: `ba1c889` (Apr 22) remains the latest commit — nothing actionable
- `nguyenvanduocit/CodeIsland` issue tracker remains empty (0 issues)
- **No new actionable items.** All open tasks (T-016 through T-065) remain as previously documented.

**Scouted (June 15, 2026) — post-v1.0.27 activity:**
- No new commits or releases since v1.0.27 (May 30); latest upstream commit remains `f878234` (May 31, Warp tab fix) — upstream quiet for 15 days
- PR #208 (open, May 31): "Refine notch hover timing and width scaling" — still open, T-061 unchanged
- PR #218 (open, Jun 4): iPhone companion app — still open; hardware/iOS companion, skip (out of scope)
- PR #222 (open, Jun 8): Pi/OMP mascot — still open; non-Claude CLI, skip
- **Issue #226** (open, Jun 13): "hermes agent 通知不起作用" (Hermes agent notifications not working) — Hermes is a non-Claude CLI; skip
- **Issue #225** (updated Jun 10): now has full body — CPU spike >100% for ~3 min on sleep/wake cycle on macOS 26.5.1 M1; specific reproducer: quit Claude Code → close lid → reopen → CPU spikes; root cause may be screen-poller or NWListener going haywire on wake; already catalogued as T-033 (screen-poll 1s→5s); noted for further investigation as T-033 may only partially address it
- vibeislandapp/vibe-island: `ba1c889` (Apr 22) remains the latest commit — nothing actionable
- `nguyenvanduocit/CodeIsland` issue tracker remains empty (0 issues)
- **No new actionable items.** All open tasks (T-016 through T-065) remain as previously documented.

**Scouted (June 16, 2026) — v1.0.28 activity:**
- v1.0.28 released 2026-06-15
- **`09aab35`** (Jun 15): "fix(permission): auto-dismiss orphan permission cards on terminal approval (#216)" — adds `resolveOrphanPermissionsOnActivity`: when a follow-up activity event (e.g. `PreToolUse`) arrives for a session, any pending permission cards whose `tool_use_id` is empty/nil are resolved as approved-in-terminal; id-bearing requests left untouched (parallel-tool-call protection from e18f884 intact). Upstream fix for T-057 → **T-057 promote to implement, priority → high**
- **`25acb1a`** (Jun 15): "fix(perf): pause mascot animation on sleep and while hidden (#225)" — introduces `MascotAnimationGate`: observes NSWorkspace sleep/wake + panel visibility; stops `TimelineView(.periodic)` animation when asleep or hidden; on re-show/wake bumps animation epoch so `TimelineView` re-anchors to now instead of replaying all missed ticks. Directly fixes the >100% CPU spike after sleep/wake (confirmed by issue #225). More comprehensive than T-033 poll-interval reduction → **T-033 criteria updated to include MascotAnimationGate**
- **`c07272d`** (Jun 15): "fix(permission): omit rule specifier for MCP tool always-allow (#224)" — 'Always allow' for MCP tools was silently broken: rule emitted as `mcp__server__tool(*)` but MCP tool calls carry no input specifier → rule never matched → same approval re-appeared on every use. Fix: emit bare tool name (no `ruleContent`) for `mcp__`-prefixed tools; non-MCP tools keep the `*` wildcard → **T-066** (new, high priority, XS)
- **`77e8c58`** (Jun 15): "fix(source): exclude desktop IDE hosts from ancestry inference (#220)" — when `claude` is run inside Cursor's integrated terminal, source inference picks up Cursor host process and mis-labels the session as Cursor source; fix excludes cursor/trae/qoder/codebuddy/stepfun/antigravity from `inferSource()` result. Upstream fix for T-064 → **T-064 source + criteria updated; promote to implement**
- `eefb3e4` (Jun 15): Superset terminal support — best-effort app-raise only (no per-pane AppleScript API on Superset); low value; skip
- `f2334944` (Jun 15): Carbon RegisterEventHotKey for global shortcuts — prerequisite for T-007; global shortcuts never implemented in our fork (unsynced since v1.0.7); skip until T-007 is started
- `70c95de` (Jun 15): Google Antigravity/Gemini hooks — non-Claude CLI, skip
- `27d96e1` (Jun 15): Hermes hooks to `~/.hermes/config.yaml` — non-Claude CLI, skip
- `2d8d19d` (Jun 15): Codex Desktop plan-mode user-input requests — Codex-specific, skip
- `8955e8` (Jun 15): iPhone Buddy iOS/watchOS companion (PR #218 merged) — out of scope, skip
- `f3b8d36` (Jun 15): Pi/OMP mascot (PR #222 merged) — non-Claude CLI, skip
- `0cf41a7` (Jun 15): drop unused Pi PR-preview PNG — repo chore, skip
- **Issue #212 closed "completed"** (Jun 15): cmux expand-all-sessions bug (T-062) — upstream closed as completed with no identifiable commit in v1.0.28 batch; T-062 still needs investigation in our codebase
- Issues #209, #213, #215, #216, #217, #220, #224, #225, #226 closed "completed" (Jun 15) — fixes for Claude Code-relevant ones captured above; others were Codex/non-Claude CLIs or SSH remote
- PR #208 (open): "Refine notch hover timing and width scaling" — T-061, still open, unchanged
- vibeislandapp/vibe-island: `ba1c889` (Apr 22) remains latest commit — nothing actionable
- ⚠️ GitHub Issues are **disabled** in `nguyenvanduocit/CodeIsland` (API returns 410) — all tracking via kanban board only

**Scouted (June 17, 2026) — post-v1.0.28 activity:**
- No new commits or releases since v1.0.28 (Jun 15); latest upstream commit remains `09aab35` — upstream quiet for 2 days
- **PR #228** (open, Jun 16): "fix(pi/omp): add pi/omp mascot option in setting view" — Pi/OMP is a non-Claude CLI; skip
- **Issue #227** (open, Jun 16): "该issue还是会复现" — user reports that issue #224 (orphan permission card with no active session) **still recurs** after the v1.0.28 fix (`09aab35`). The v1.0.28 fix only handles the "activity event arrives → dismiss nil-tool_use_id orphans" path; it does not drain queued items when the session process exits. Our T-065 (drain on `.removeSession` side effect) is a distinct, complementary fix still needed. T-065 criteria unchanged.
- **PR #208** status update: upstream owner reviewed and declined to merge in current form — PR bundles project rename (CodeIsland → UniIsland), ~1500 lines of new features including WeChat notification database access (requires Full Disk Access), and a `hideWhenNoSession` regression alongside the desired hover-timing and width-slider refinements. Owner requested a focused re-submission with just the hover/slider changes. T-061's gate ("wait for PR #208 to merge") now effectively means "wait for a focused re-PR" — update T-061 criteria accordingly.
- vibeislandapp/vibe-island: `ba1c889` (Apr 22) remains the latest commit — nothing actionable
- ⚠️ GitHub Issues are **disabled** in `nguyenvanduocit/CodeIsland` (API returns 410) — all tracking via kanban board only
- **No new actionable items.** All open tasks (T-016 through T-066) remain as previously documented. **T-061 gate updated**: not "PR #208 merges" but "a focused hover-timing re-PR merges."

**Scouted (June 20, 2026) — post-v1.0.28 activity:**
- No new commits or releases since v1.0.28 (Jun 15); latest upstream commit remains `09aab35` — upstream quiet for 5 days
- **PR #233** (open, Jun 19): "fix: support Google Antigravity tool-use approval and details" — Google Antigravity is non-Claude CLI; skip
- **PR #228** (open, Jun 16): "fix(pi/omp): add pi/omp mascot option in setting view" — Pi/OMP non-Claude CLI; skip (unchanged)
- **PR #208** (open, May 31): "Refine notch hover timing and width scaling" — still open, T-061 (gate: focused re-PR); unchanged
- **Issue #232** (open, Jun 18): "TRAE IDE不识别hooks" — TRAE is non-Claude CLI; skip
- **Issue #231** (open, Jun 18): "Island width setting applies to notch and non-notch displays" — bug report on v1.0.28: the width slider (labeled "non-notch only") affects both notch and non-notch displays since PR #171 broadened scope in v1.0.25; upstream label is misleading; when implementing T-021 in our fork, either restrict to non-notch-only or update the setting label to reflect both → **T-021 criteria updated**
- **Issue #230** (open, Jun 18): "CodeIsland buddy english localization" — Buddy is the ESP32/BLE hardware companion; skip
- **Issue #229** (open, Jun 17): "能不能适配14以下系统和intel旧机型" — request to support macOS <14 and Intel Macs; out of scope (we target macOS 14+ with `@Observable`); skip
- vibeislandapp/vibe-island: `ba1c889` (Apr 22) remains the latest commit — nothing actionable
- ⚠️ GitHub Issues are **disabled** in `nguyenvanduocit/CodeIsland` (API returns 410) — all tracking via kanban board only
- **No new actionable items.** T-021 criteria updated with label-accuracy note. All other open tasks (T-016 through T-066) remain as previously documented.

**Scouted (June 21, 2026) — post-v1.0.28 activity:**
- No new commits or releases since v1.0.28 (Jun 15); latest upstream commit remains `09aab35` — upstream quiet for 6 days
- **PR #234** (open, Jun 20): "Add German localization and improve macOS signing support" — German L10n (we don't ship L10n) + DMG signing improvements (CI/release only); skip
- **PR #233** (open, Jun 19): Google Antigravity support — non-Claude CLI; skip (unchanged from Jun 20 scout)
- **PR #228** (open, Jun 16): Pi/OMP mascot option — non-Claude CLI; skip (unchanged)
- **PR #208** (open, May 31): "Refine notch hover timing and width scaling" — still open, T-061 (gate: focused re-PR); unchanged
- vibeislandapp/vibe-island issue #148 (Jun 14, closed Jun 20): Claude Desktop workflow false-completion bug — Claude Desktop App, not Claude Code CLI; skip
- vibeislandapp/vibe-island: `ba1c889` (Apr 22) remains the latest commit — nothing actionable
- `nguyenvanduocit/CodeIsland` issue tracker: 0 open issues
- **No new actionable items.** All open tasks (T-016 through T-066) remain as previously documented.

**Scouted (June 22, 2026) — post-v1.0.28 activity:**
- No new commits or releases since v1.0.28 (Jun 15); latest upstream commit remains `09aab35` — upstream quiet for 7 days
- **Issue #235** (open, Jun 21): "Feature Request: Add OpenClaw support" — OpenClaw is a non-Claude CLI; skip
- PR #234 (open, Jun 20): German L10n + macOS signing — skip (unchanged from Jun 21 scout)
- PR #233 (open, Jun 19): Google Antigravity support — non-Claude CLI; skip (unchanged)
- PR #228 (open, Jun 16): Pi/OMP mascot option — non-Claude CLI; skip (unchanged)
- PR #208 (open, May 31): "Refine notch hover timing and width scaling" — still open, T-061 (gate: focused re-PR); unchanged
- vibeislandapp/vibe-island: 4 commits on Jun 21 (`a5aa8fd`, `744605b`, `a2bd5d3`, `c0cc7f7`) — docs/issue-template cleanup only (README streamline, removed Chinese from templates); no code changes; nothing actionable
- `nguyenvanduocit/CodeIsland` issue tracker: 0 open issues
- **No new actionable items.** All open tasks (T-016 through T-066) remain as previously documented.

**Scouted (June 23, 2026) — post-v1.0.28 activity:**
- No new commits or releases since v1.0.28 (Jun 15); latest upstream commit remains `09aab35` — upstream quiet for 8 days
- **PR #237** (open, Jun 22): "feat(activator): jump to host GUI client that embeds an agent as a server" — introduces `resolveHostClientBundleId(for:)`: walks process ancestry (max 32 hops, uses `proc_pidinfo()`), builds exclusion set of known terminals + agent apps, returns first regular GUI app not in the exclusion set; no hardcoded bundle IDs. Intended for scenarios where a CLI agent runs as a managed server inside a desktop client (e.g. OpenChamber) rather than a terminal. For our Claude Code-only fork, claude always runs in a real terminal — server-mode embedding is uncommon. Not yet merged → **T-067** (new, low priority, watch for merge)
- **PR #238** (open, Jun 22): "feat(ios): native iPad support + notch-aligned companion UI" — iOS/watchOS companion; macOS app untouched; out of scope; skip
- **Issue #236** (open, Jun 22): "Codex Desktop sessions are not shown while Claude sessions work" — Codex-specific; skip
- **Issue #239** (open, Jun 22): "Support for the herdr terminal multiplexer" — niche multiplexer; no upstream implementation, just a feature request; skip
- **Issue #240** (open, Jun 22): "远程SSH时，会看到其他人的对话和对话面板" — SSH remote session isolation request; SSH remote feature not applicable to our fork; skip
- vibeislandapp/vibe-island: `3e1e1e2` (Jun 22) — docs: streamline community templates and README — docs only, nothing actionable
- `nguyenvanduocit/CodeIsland` issue tracker: 0 open issues
- **One new watch item (T-067).** All other open tasks (T-016 through T-066) remain as previously documented.

**Scouted (June 24, 2026) — post-v1.0.28 activity:**
- No new commits or releases since v1.0.28 (Jun 15); latest upstream commit remains `09aab35` — upstream quiet for 9 days
- PR #237 (open, Jun 22): "feat(activator): jump to host GUI client..." — T-067, still open, unchanged
- PR #238 (open, Jun 23): "feat(ios): native iPad support + notch-aligned companion UI" — still open; iOS/watchOS companion, skip (out of scope)
- Issues #236/#239/#240: all already documented in June 23 scout; no change
- vibeislandapp/vibe-island: **issue #150** (open, Jun 21): "Claude/Codex sessions running in a git worktree under `.claude/worktrees/` are never shown in the island" — detailed root-cause analysis reveals `claudeProjectDirEncoded()` only replaces `/` not `.`, while Claude Code encodes both; any session cwd with a `.` path component (e.g. `.claude/worktrees/<branch>`) builds a wrong transcript path → `SessionTitleStore` and `SessionUsageReader` silently find nothing; session visibility unaffected (driven by hook events); title and usage data broken → confirmed in our `AppState.swift:731` → **T-068** (new, high priority, XS)
- vibeislandapp/vibe-island: issue #149 (closed Jun 21, duplicate of #150) — no additional content
- `nguyenvanduocit/CodeIsland` issue tracker: 0 open issues (issues API returns 410 — disabled)
- **One new task (T-068).** All other open tasks (T-016 through T-067) remain as previously documented.

**Scouted (June 25, 2026) — v1.0.29 + post-v1.0.28 activity:**
- **`a06ad44`** (Jun 24, direct push): "fix: resolve tool label and Trae hook issues" (fixes upstream #241, #231, #232) — adds `enum ToolNameDisplay` with `compact(_ tool:)` helper (24-char cap + `"..."` truncation) to `NotchPanelView.swift`; applies it to the compact bar center text; `CompactRightWing` description updated to "project name + session count" (gains `projectName` computed from `session.cwd`). Issue #241 was: long MCP tool names overflow the compact bar, pushing mascot and session count off-screen. We have the same bug in our `liveToolText` path. → **T-069** (new, high priority, XS)
- **`b426e93`** (Jun 24): "fix: resolve actionable issue regressions" — follow-up fix addressing regressions from the batch PR merges (mostly non-Claude CLIs); no additional action for our fork beyond T-069
- **PR #237 MERGED** (Jun 24, commit `0aece00`): "feat(activator): jump to host GUI client embedding the agent as server" — T-067 gate cleared. For our Claude Code-only fork: `resolveHostClientBundleId()` returns nil for terminal sessions (terminals are in the exclusion set); our `nativeAppBundles` is already `[:]` so the changed fallback path is also a no-op → **T-067 skip** (no action needed for our fork)
- **PR #238 MERGED** (Jun 24): "feat(ios): native iPad support + notch-aligned companion UI" — iOS companion; out of scope; skip. Note: bundled compile fix `PixelCharacterView` reads `mascotAnimationsActive/Epoch` env keys missing from iOS targets — not applicable (we have no iOS target)
- **PR #234 MERGED** (Jun 24): German L10n + macOS signing improvements — includes minor "Fix AppState deinit main-actor cleanup"; L10n skip; deinit fix is cosmetic (no crash in practice); skip
- **PR #233 MERGED** (Jun 24): Google Antigravity support — non-Claude CLI; skip
- **PR #228 MERGED** (Jun 24): Pi/OMP mascot option — non-Claude CLI; skip
- vibeislandapp/vibe-island: no new commits since Jun 22 — nothing actionable
- `nguyenvanduocit/CodeIsland` issue tracker: disabled (API returns 410) — all tracking via kanban board only
- **One new task (T-069).** T-067 retired (no-op for our fork). All other open tasks (T-016 through T-068) remain as previously documented.

**Scouted (June 26, 2026) — post-v1.0.29 activity:**
- No new commits or releases since v1.0.29 (Jun 24); latest upstream commits are `597b5ce` + `b426e93` (Jun 24) — upstream quiet for 2 days
- **`597b5ce`** (Jun 24): "fix: align antigravity permission routing" — modifies `HookServer.swift`, `AppState.swift`, `EventNormalizer.swift`, `CodeIslandBridge/main.swift` to route Gemini CLI/Google Antigravity `PreToolUse` events through the permission UI; changes `EventNormalizer` to treat "BeforeTool" as "PermissionRequest" for non-Claude sources; Antigravity/Gemini-specific → **skip**
- **Issue #242** (open, Jun 25): "ssh 的时候会覆盖我原来的hook" — SSH remote feature overwrites user's existing hooks; SSH remote monitoring not applicable to our Claude Code-only fork → skip
- vibeislandapp/vibe-island: no new commits since Jun 22 — nothing actionable
- `nguyenvanduocit/CodeIsland` issue tracker: disabled (API returns 410) — all tracking via kanban board only
- **No new actionable items.** All open tasks (T-016 through T-069) remain as previously documented.

**Scouted (June 27, 2026) — post-v1.0.29 activity:**
- No new commits or releases since v1.0.29 (Jun 24); latest upstream commit remains `b426e93` (Jun 24) — upstream quiet for 3 days
- **`b426e93`** (Jun 24, missed from June 26 scout): "fix: resolve actionable issue regressions" — most changes are Codex-specific (`AppState+CodexAppServer.swift` adds `codexAppServerExecutableURL()` helper, `CodexPermissionRules.swift` +130 lines, test coverage); the one Claude Code-adjacent change is `AppState.swift`: refactors `shouldSuppressAppLevel()` → extracts `shouldAutoOpenPendingSurface()` helper with injectable `isTerminalFrontmost` closure for testability (logic unchanged, no user-visible bug fix). No action needed; testability improvement only → **skip**
- PR #208 (open, May 31): "Refine notch hover timing and width scaling" — still open, T-061 (gate: focused re-PR); unchanged
- Issue #242 (open, Jun 25): SSH remote hooks overwrite — SSH remote feature, skip (unchanged)
- vibeislandapp/vibe-island: no new commits since Jun 22 — nothing actionable
- `nguyenvanduocit/CodeIsland` issue tracker: 0 open issues
- **No new actionable items.** All open tasks (T-016 through T-069) remain as previously documented.

**Scouted (June 28, 2026) — post-v1.0.29 activity:**
- No new commits or releases since v1.0.29 (Jun 24); latest upstream commit remains `b426e93` (Jun 24) — upstream quiet for 4 days
- PR #208 (open, May 31): "Refine notch hover timing and width scaling" — still open, T-061 (gate: focused re-PR); unchanged
- Issue #242 (open, Jun 25): SSH remote hooks overwrite — SSH remote feature, skip (unchanged)
- vibeislandapp/vibe-island: latest commit `3e1e1e2` (Jun 22) docs-only — nothing actionable
- `nguyenvanduocit/CodeIsland` issue tracker: 0 open issues
- **No new actionable items.** All open tasks (T-016 through T-069) remain as previously documented.

**Scouted (June 30, 2026) — post-v1.0.29 activity:**
- No new commits or releases since v1.0.29 (Jun 24); latest upstream commit remains `b426e93` (Jun 24) — upstream quiet for 6 days
- **Issue #243** (open, Jun 29): "CodeIsland repeatedly sends SIGTERM to launchd-managed daemon (Hermes gateway)" — our fork has the same `kill(pid, SIGTERM)` orphaned-process logic at `AppState.swift:225`; however it only fires for processes already in our sessions dict, which can only contain Claude Code hook-registered sessions; a launchd-managed daemon (ppid=1 always) would never enter our sessions dict in a Claude Code-only fork → **not applicable to our fork, skip**
- **Issue #244** (open, Jun 29): OMP (Oh My Pi) `ask` tool not triggering question UI — OMP is a non-Claude CLI; skip
- PR #208 (open, May 31): "Refine notch hover timing and width scaling" — still open, T-061 (gate: focused re-PR); unchanged
- vibeislandapp/vibe-island: issues #155 (OpenCode session deduplication) and #151 (Gajae Code support) updated — both non-applicable to our Claude Code-only fork; skip
- vibeislandapp/vibe-island: `ba1c889` (Apr 22) remains the latest commit — nothing actionable
- `nguyenvanduocit/CodeIsland` issue tracker: 0 open issues
- **No new actionable items.** All open tasks (T-016 through T-069) remain as previously documented.

**Scouted (July 1, 2026) — post-v1.0.29 activity:**
- No new commits or releases since v1.0.29 (Jun 24); latest upstream commit remains `b426e93` (Jun 24) — upstream quiet for 7 days
- No new PRs since Jun 24; PR #208 (open, May 31): "Refine notch hover timing and width scaling" — T-061 (gate: focused re-PR); unchanged
- No new issues since Jun 29 (issues #243/#244 already documented in Jun 30 scout)
- vibeislandapp/vibe-island: `24bbaf4` (Jun 30): "ci: auto-triage CLI-created issues" — CI-only, skip
- vibeislandapp/vibe-island issue #153 (closed Jun 30): "Usage bridge falsely reports 'script doesn't exist' for statusLine commands that use $HOME" — vibe-island's `fileExists` check expands `~` but not `$HOME`; fixed on their `main` (planned v1.0.40). **Not applicable to our fork** (we have no statusLine installation or bridge-installer UI)
- vibeislandapp/vibe-island issue #147 (open, updated Jun 30): sub-worker auto-approval not firing in on-my-claudecode /team mode — maintainer investigating; newer on-my-claudecode starts workers with `bypassPermissions` so the issue may be version-specific; no upstream fix yet; no action needed
- vibeislandapp/vibe-island issue #127 (open, updated Jun 25): Warp Tab Jumping sends layout-dependent keycodes and loops on Swiss QWERTZ — ongoing; our planned T-044 implementation uses Cmd+digit keystrokes (same approach) and would be subject to the same layout-dependency issue; note as a risk when implementing T-044
- `nguyenvanduocit/CodeIsland` issue tracker: 0 open issues
- **No new actionable items.** All open tasks (T-016 through T-069) remain as previously documented.

**Scouted (July 2, 2026) — post-v1.0.29 activity:**
- No new commits or releases since v1.0.29 (Jun 24); search returns 0 commits since Jun 30 — upstream quiet for 8 days
- No new PRs created after Jun 25; PR #208 (open, May 31): "Refine notch hover timing and width scaling" — T-061 (gate: focused re-PR); unchanged
- wxtsky/CodeIsland issue #245 (Jul 1): zcode support request — non-Claude CLI; skip
- vibeislandapp/vibe-island: no new PRs; issues #150 (worktree path encoding, closed Jun 30) and #153 ($HOME expansion, closed Jun 30) already documented in prior scouts
- vibeislandapp/vibe-island issue #147 (open): sub-worker auto-approval in on-my-claudecode /team mode — still open; no upstream fix; no new action
- `nguyenvanduocit/CodeIsland` issue tracker: 0 open issues
- **No new actionable items.** All open tasks (T-016 through T-069) remain as previously documented.

**Scouted (July 3, 2026) — post-v1.0.29 activity:**
- No new commits or releases since v1.0.29 (Jun 24); latest upstream commit remains `b426e93` (Jun 24) — upstream quiet for 9 days
- No new PRs; PR #208 (open, May 31): "Refine notch hover timing and width scaling" — T-061 (gate: focused re-PR); unchanged
- wxtsky/CodeIsland issue #245 (Jul 1, zcode support): already documented in Jul 2 scout; non-Claude CLI, skip; no new issues
- vibeislandapp/vibe-island: issue #145 (closed Jul 1, Chinese L10n bug) and issue #72 (closed Jul 1, settings UI text overlap) — vibe-island internal UI, not applicable; issue #147 (open, sub-worker auto-approval in team mode) — still open, no upstream fix, no new action
- vibeislandapp/vibe-island: `ba1c889` (Apr 22) remains the latest commit — nothing actionable
- `nguyenvanduocit/CodeIsland` issue tracker: 0 open issues
- **No new actionable items.** All open tasks (T-016 through T-069) remain as previously documented.

**Scouted (July 4, 2026) — post-v1.0.29 activity:**
- No new commits or releases since v1.0.29 (Jun 24); latest upstream commit remains `b426e93` (Jun 24) — upstream quiet for 10 days
- ⚠️ Note: v1.0.29 git tag not visible via `git fetch --tags` (highest visible tag is v1.0.28); CLAUDE.md references to "v1.0.29" were based on GitHub Releases UI (API inaccessible in this environment). The 8 commits above v1.0.28 (`a06ad44` through `b426e93`) are confirmed present on `upstream/main` — the release was shipped, tag status unclear.
- No new PRs or issues accessible (GitHub API scoped to our repo only; confirmed via git that no new commits exist since Jun 24)
- PR #208 (open, May 31): "Refine notch hover timing and width scaling" — T-061 (gate: focused re-PR); unchanged
- vibeislandapp/vibe-island: `24bbaf4` (Jun 30, CI auto-triage) remains the latest commit — nothing actionable
- `nguyenvanduocit/CodeIsland` issue tracker: 0 open issues
- **No new actionable items.** All open tasks (T-016 through T-069) remain as previously documented.

**Scouted (July 6, 2026) — v1.0.29 activity (upstream batch Jul 5–6, 2026):**
- Upstream pushed a large batch of 13 commits on Jul 5, 2026; confirmed as **v1.0.29** (git tag `73756d1 release: v1.0.29` on Jul 6). Prior CLAUDE.md entries citing "v1.0.29 released 2026-06-24" were incorrect — that batch (Jun 24 commits `a06ad44`–`b426e93`) shipped without a visible git tag at the time and was still under v1.0.28; the Jul 5–6 batch is the actual v1.0.29 release.
- **`4fbd0f9`**: "feat: recognize Claude Code Desktop sessions (#211)" — Claude Code Desktop (`com.anthropic.claudefordesktop`) shares `~/.claude/settings.json` and fires the same hooks; `SessionSnapshot.swift` bundle-ID mapping, `AppState.swift` native-app mode, `TerminalActivator.swift` exclusion from click-to-jump → **T-070** (new, high priority, S)
- **`4fdf5af`**: "feat(panel): auto-dodge third-party menu bar icons on external screens (#219)" — new `MenuBarIconAvoidance.swift` + `PanelWindowController.swift` integration; slides panel into nearest clear gap when Bartender 5/Ice occupy center space; upstream fix for T-063 → **T-063 promote to implement, priority medium** (updated criteria, source, and effort)
- **`e3ac11c`**: "feat(notch): three-stage hover interaction + 1% width-scale steps" — `collapsed → prehover → expanded` state machine; prehover visual (+7pt, 1.004 scale) while 0.5s timer runs; quick pass-through reverses without full expand; width slider 10% → 1% steps; 49-line unit test suite; **T-061 gate cleared** (PR #208 was closed, feature committed directly to main) → T-061 criteria updated, gate condition removed, priority raised to medium
- **`eb3ad03`**: "feat(ux): surface enabled approve/deny shortcuts on the approval card" — small shortcut badges on Allow/Deny buttons when global shortcuts are enabled; single-file change +34/-17 lines → **T-071** (new, low priority, XS; depends on T-007)
- **`0971ad3`**: "perf: gate every mascot's frame loop, not just Clawd's (#225 follow-up)" — new universal `MascotTimeline` wrapper replaces 4 raw `TimelineView(.periodic)` loops in all 17 non-Claude mascot views; 20fps floor; epoch re-anchor on wake; **T-033 criteria extended** to require universal wrapper (not just `PixelCharacterView` gate)
- **`d5fe917`**: "perf: 8fps idle mascot scenes + lazy BLE peripheral init" — caps idle mascot animation to 8fps; BLE init irrelevant; added to T-033 criteria as optional idle-fps cap
- **`2a289f9`**: "feat(mascots): motion-polish pass across all 18 characters (#15)" — visual polish of sprite animations; our mascot system uses separate sprite PNGs; low relevance since we only have Claude's sprite sheet; skip
- **`cf624dd`**: "fix: never SIGTERM launchd-managed daemons in orphan cleanup (#243)" — ppid=1 guard before `kill()`; previously evaluated as "not applicable to our fork"; maintaining skip (our sessions dict only contains Claude Code hook-registered sessions which always have a terminal parent)
- **`4f8308b`**: "feat(remote): per-host working-directory filter" — SSH remote feature; skip
- **`ee23ccf`**: "feat(omp/pi): bridge ask tool to question UI" — OMP/Pi non-Claude CLI; skip
- **`27837c0`**: "fix(remote): merge hooks instead of replacing event keys" — SSH remote; skip
- **`10fb1b2`**: "fix(companion): watchOS crash-loop self-healing" — hardware companion; skip
- **`779d755`**: "fix(mascot): map cursor-cli and qoder-cli to mascots" — non-Claude CLIs; skip
- **PR #208 CLOSED** (Jul 5): "Refine notch hover timing and width scaling" — declined in prior form; features extracted and committed as `e3ac11c`; T-061 gate condition removed
- **vibeislandapp/vibe-island**: `b80886a` (Jul 5) — "docs: expand README into full product overview" — docs only, nothing actionable
- **New tasks added**: T-070 (Claude Code Desktop), T-071 (shortcut badges); **tasks updated**: T-061 (gate cleared), T-063 (upstream fix available), T-033 (universal MascotTimeline)

**Scouted (July 7, 2026) — post-v1.0.29 activity:**
- No new commits or releases since v1.0.29 (Jul 6); latest upstream commit remains `73756d1` — upstream quiet
- `202ea87` (Jul 6, post-release): "feat(mascots): Kiro ghost + complete the settings mascot gallery" — Kiro is a non-Claude CLI; settings gallery now includes Kiro, Molty (OpenClaw), and Google Antigravity entries; not applicable to our fork; skip
- `531cf8c` (Jul 6, post-release): "docs: document keyboard shortcuts in both READMEs (#31)" — docs only; skip
- `4418d64` (Jul 6, post-release): "feat: OpenClaw integration — plugin pack, Molty mascot, installer (#235)" — OpenClaw (formerly Clawdbot/Moltbot) is a non-Claude CLI with a launchd daemon architecture; not applicable to our Claude Code-only fork; skip
- `73756d1` (Jul 6): "release: v1.0.29" — release chore; skip
- vibeislandapp/vibe-island: `018b06f` (Jul 7) "docs: align tagline agent count with section header" and `b80886a` (Jul 6, already in Jul 6 scout) "docs: expand README" — docs only, nothing actionable
- `nguyenvanduocit/CodeIsland` issue tracker: 0 open issues, 0 closed issues
- **No new actionable items.** All open tasks (T-016 through T-071) remain as previously documented.

**Scouted (July 10, 2026) — post-v1.0.29 activity:**
- No new commits or releases since v1.0.29 (Jul 6); latest upstream commit remains `73756d1` — upstream quiet for 4 days
- **PR #253** (open, Jul 7): "fix(activator): recognize Terax terminal for click-to-jump" — Terax (`app.crynta.terax`) is a real macOS terminal app; clicking a session card when Claude Code runs inside Terax falls back to Terminal.app; fix adds Terax to `knownTerminals` and routes to `activateByBundleId` (same pattern as Superset — webview tabs, no AppleScript); 2 files, ~52 additions + new `TeraxSupportTests`; not yet merged → **T-072** (new, low priority, XS; gate: wait for PR #253 to merge)
- **PR #255** (open, Jul 9): "fix: complete cursor-cli and qoder-cli routing (#248 follow-up)" — cursor-cli/qoder-cli session grouping and display fixes; non-Claude CLIs; skip
- **PR #252** (open, Jul 7): "修复 Codex 多行命令规则的字符串转义" — Codex Starlark rules string escaping; Codex-specific; skip
- **PR #251** (open, Jul 7): "Add Traditional Chinese (zh-Hant) localization" — L10n; skip
- Issue #254 (open, Jul 7): "是否可以增加一个定时任务的功能" — scheduled-task feature request; out of scope; skip
- Issue #250 (open, Jul 6): Starlark rules multiline string bug (`~/.codex/rules/`) — Codex-specific; skip
- Issue #244 (closed Jul 10): OMP ask tool support — non-Claude CLI; skip
- vibeislandapp/vibe-island: `018b06f` (Jul 7) remains the latest commit — docs only, nothing actionable
- ⚠️ GitHub Issues are **disabled** in `nguyenvanduocit/CodeIsland` (API returns 410) — all tracking via kanban board only
- **One new task (T-072).** All other open tasks (T-016 through T-071) remain as previously documented.

**Scouted (July 11, 2026) — v1.0.30 activity:**
- v1.0.30 released 2026-07-10 — large batch of 19 commits
- **PR #253 MERGED** (`def6162`, v1.0.30): Terax terminal click-to-jump — was watching; gate cleared → **T-072 gate removed, ready to implement**
- **`6bffcfd` + `c62ace8` + `a30462a`** (v1.0.30): "feat(sessions): git branch / worktree indicator on session cards" — new `GitBranchReader.swift` reads `.git/HEAD` without spawning git; walks up max 12 dirs; distinguishes linked worktrees (`⧉` badge) from submodules; `GitBranchInfo(branch:isWorktree:)` stored on `SessionSnapshot` (non-persisted); refreshes on cwd change + Stop; off-reducer detached task (per `a30462a`) prevents main-actor blocking on network-mounted cwds; toggle in Appearance settings; 137-line test suite → **T-074** (new, medium priority, S)
- **`73e7463` + `9814945` + `a30462a`** (v1.0.30): "feat(usage): Claude token-usage footer from local transcripts" — new `ClaudeUsageScanner.swift` aggregates token usage from `~/.claude/projects/**/*.jsonl`; deduplicates on `message.id` (tool-use continuation lines repeat ID); incremental per-file byte-offset reads (`FileCache`); shows last-5h + today windows + 12h hourly sparkline; lazy refresh throttled to 2 min; no API calls; toggle in Appearance; 87-assertion test suite → **T-073** (new, medium priority, M)
- **`8cd27ea`** (v1.0.30): "feat(behavior): glance completion mode — collapsed dot instead of expanding" — three-way `completionNotificationStyle` ("expand"/"glance"/"off") replacing the boolean `autoExpandOnCompletion`; migration provided; glance mode shows green dot on compact right wing, 10-min failsafe clears it on next panel open → **T-050 superseded**: update criteria from boolean to three-way mode; effort bumped XS → S
- **`da5f80b`** (v1.0.30): "feat(sound): quiet hours — mute event sounds inside a configured window" — `[start, end)` minute-of-day window; midnight-spanning (`start > end`) works correctly; settings previews stay audible; `nonisolated static isInQuietHours()` for testability → **T-075** (new, low priority, XS)
- **`d4dce1c`** (v1.0.30): "fix: always surface blocking AskUserQuestion cards under Smart Suppress (#256)" — adds `shouldAutoOpenQuestionSurface()` that bypasses Smart Suppress for AskUserQuestion (CLI blocks until answered so no terminal fallback exists); 115-line test suite; **not applicable to our fork** — we don't have the Smart Suppress feature; note: add to T-041 criteria when implementing Smart Suppress
- **`29e5256`** (v1.0.30): "fix: keep Cursor-scoped transcript_path cwd extraction Claude-safe" — scopes `.cursor/projects/` path fallback in `extractMetadata` to prevent cwd hijacking for Claude sessions in `$HOME`; **not applicable to our fork** — we don't have the Cursor `transcript_path` cwd extraction code; skip
- `0c19dc6`: ZCode integration — non-Claude CLI, skip
- `091dc74`: QoderWork integration — non-Claude CLI, skip
- `e69abbd`: cursor-cli/qoder-cli routing — non-Claude CLIs, skip
- `b59989b`: Traditional Chinese L10n — skip (we don't ship L10n)
- `ced6b6d`: Codex Starlark rules fix — Codex-specific, skip
- `2f84622`: Settings CLI row icons (mascot gallery) — mostly affects other-CLI settings rows; our Claude Code row uses the Claude mascot sprite; low value for Claude-only fork; skip
- `a7999c2`: --preview mode seeding — development chore, skip
- vibeislandapp/vibe-island: `018b06f` (Jul 7) remains the latest commit — nothing actionable
- ⚠️ GitHub Issues are **disabled** in `nguyenvanduocit/CodeIsland` (API returns 410) — all tracking via kanban board only
- **Three new tasks (T-073, T-074, T-075). T-072 gate cleared. T-050 criteria updated to three-way glance mode.**

**Scouted (July 12, 2026) — post-v1.0.30 activity:**
- No new commits or releases since v1.0.30 (Jul 10); latest upstream commit remains `3e2aec7` — upstream quiet for 2 days
- **vibeislandapp/vibe-island**: `3bb9959` (Jul 11) "Fix Discord community routing" + `83fed33` "Avoid duplicate Discord issue notifications" — CI/Discord webhook only; nothing actionable
- ⚠️ GitHub Issues are **disabled** in `nguyenvanduocit/CodeIsland` (API returns 410, creation attempts confirm) — all tracking via kanban board only
- Kanban board already up to date from Jul 11 scout (T-073, T-074, T-075 in Todo)
- **No new actionable items.** All open tasks (T-016 through T-075) remain as previously documented.

**Scouted (July 13, 2026) — post-v1.0.30 activity:**
- No new commits or releases since v1.0.30 (Jul 10); latest upstream commit remains `3e2aec7` — upstream quiet for 3 days
- **PR #257** (open, Jul 10): "fix: restore OpenCode plugin support for v2 events" — 4 files changed: `codeisland-opencode.js`, `codeisland-opencode-remote.js`, `RemoteInstaller.swift`, `ConfigInstaller.swift`; ESM migration + `session.next.*` / `permission.v2.*` / `question.v2.*` event mapping for OpenCode v2 runtime; OpenCode-specific, skip
- **Issue #258** (open, Jul 10): "Zcode 能否加入执行的按钮？" — user requests Allow/Always Allow/Deny permission controls for Zcode; non-Claude CLI, skip
- vibeislandapp/vibe-island: no new commits since Jul 11 (Discord routing fixes, CI-only) — nothing actionable
- `nguyenvanduocit/CodeIsland` issue tracker: 0 open issues (tracker enabled, empty)
- **No new actionable items.** All open tasks (T-016 through T-075) remain as previously documented.

**Scouted (July 14, 2026) — post-v1.0.30 activity:**
- No new commits or releases since v1.0.30 (Jul 10); latest upstream commit remains `3e2aec7` — upstream quiet for 4 days
- **PR #259** (closed/abandoned, Jul 13): "chore(ios): retarget companion to local bundle ID and refresh icons" — iOS companion app icon chore; iOS-specific, out of scope; skip
- **Issue #260** (open, Jul 13): "Request for English language on the iOS app" — iOS companion app L10n request; out of scope; skip
- PR #256 (merged, Jul 10): "修复：智能抑制下 OMP 提问卡片无法操作" — confirmed AskUserQuestion always-surface fix under Smart Suppress; already captured as `d4dce1c` in Jul 11 scout; applicable only when T-041 (Smart Suppress) is implemented; no separate action
- PR #257 (open): OpenCode v2 events — still open, unchanged from Jul 13 scout; skip
- Issue #258 (open): Zcode permission button — non-Claude CLI; skip (unchanged from Jul 13 scout)
- vibeislandapp/vibe-island: `3bb9959` (Jul 11) remains the latest commit — nothing actionable
- `nguyenvanduocit/CodeIsland` issue tracker: 0 open issues
- **No new actionable items.** All open tasks (T-016 through T-075) remain as previously documented.

**Scouted (July 15, 2026) — post-v1.0.30 activity:**
- No new commits or releases since v1.0.30 (Jul 10); latest upstream commit remains `3e2aec7` — upstream quiet for 5 days
- **PR #262** (open, Jul 14): "fix(appstate): allow AppState deinit off the main actor" — introduces `ProjectsWatcherBox` (thread-safe weak-ref box, NSLock guard, cancelled flag) so FSEvents callbacks reach AppState without holding a strong reference or calling `assumeIsolated` in deinit; fixes async XCTest teardown trap; this is specifically for the `~/.claude/projects/` watcher introduced by ClaudeUsageScanner (T-073); not yet merged → add to T-073 criteria: port `ProjectsWatcherBox` pattern alongside `ClaudeUsageScanner.swift` to avoid the same trap in our fork's tests
- PR #257 (open): OpenCode v2 events — Codex/OpenCode-specific; skip (unchanged)
- Issue #258 (open): Zcode permission button — non-Claude CLI; skip (unchanged)
- vibeislandapp/vibe-island: `3bb9959` (Jul 11) remains the latest commit — nothing actionable
- `nguyenvanduocit/CodeIsland` issue tracker: 0 open issues
- **No new actionable items.** T-073 criteria updated with `ProjectsWatcherBox` note. All other open tasks (T-016 through T-075) remain as previously documented.

**Scouted (July 16, 2026) — post-v1.0.30 activity:**
- No new commits or releases since v1.0.30 (Jul 10); latest upstream commit remains `3e2aec7` — upstream quiet for 6 days
- **Issue #263** (open, Jul 14): "[Bug] Notch panel detaches from the MacBook notch and moves to the upper-left corner" — MacBook Pro M5 Pro (Mac17,9), macOS 27.0 beta (26A5378j), CodeIsland v1.0.30, 3024×1964 Retina display; panel intermittently shifts from center notch to upper-left area beneath menu bar with no consistent repro trigger; no upstream fix yet → **T-076** (new, investigate, macOS 27.0 beta)
- **Issue #265** (open, Jul 15): "Does not display Cursor question prompts and stays stuck on 'thinking'" — Cursor-specific (user confirmed running Cursor IDE, not Claude Code CLI); skip
- **PR #264** (open, Jul 15): "修复(OMP)：终端原生 Ask 与 CodeIsland 并行回答" — OMP non-Claude CLI; skip
- **PR #262** (open, Jul 14, now shows as): "fix(sessions): fold Cursor Tasks under Agent Sub-Sessions like Codex" — Cursor-specific; skip (note: Jul 14/15 scout referenced this PR number for the AppState deinit PR; T-073 criteria already updated with ProjectsWatcherBox note regardless of PR number)
- PR #257 (open): OpenCode v2 events — Codex/OpenCode-specific; skip (unchanged)
- vibeislandapp/vibe-island: `3bb9959` (Jul 11) remains the latest commit — nothing actionable
- `nguyenvanduocit/CodeIsland` issue tracker: 0 open issues
- **One new watch item (T-076 — macOS 27.0 beta panel detach, no upstream fix yet).** All other open tasks (T-016 through T-075) remain as previously documented.

**Scouted (July 17, 2026) — post-v1.0.30 activity:**
- No new commits or releases since v1.0.30 (Jul 10); latest upstream commit remains `3e2aec7` — upstream quiet for 7 days
- **PR #266** (open, Jul 16): "fix(trae): support Trae CLI Next hooks" — Trae CLI is a non-Claude CLI; skip
- **PR #264** (open, Jul 15, draft): OMP terminal fix — OMP non-Claude CLI; skip (unchanged)
- **PR #262** (open, Jul 14): "fix(sessions): fold Cursor Tasks under Agent Sub-Sessions like Codex" — Cursor-specific; skip (unchanged)
- **Issue #265** (open, Jul 15): Cursor question prompts not displayed — Cursor-specific; skip (unchanged from Jul 16 scout)
- **Issue #261** (open, Jul 14): "Code Island Buddy keeps disconnecting" — Buddy hardware companion; skip
- vibeislandapp/vibe-island: `22c6f31` (Jul 16) "docs: add YouTube demo video link to hero image" — docs only, nothing actionable
- **vibeislandapp/vibe-island issue #166** (open, Jul 16): "Jump silently no-ops for Claude Code sessions hosted by the background daemon (`bg-pty-host`)" — Claude Code now optionally runs the session engine under a per-user daemon; process tree becomes `launchd → bg-pty-host → engine (no TTY)`; ancestry walk in `ProcessScanner.findTerminalBundleId(for:)` stops at ppid=1, returns nil; bridge `getppid()` chain leads to daemon, not terminal; click-to-jump silently fails; confirmed same code pattern in our `ProcessScanner.swift:193` and `CodeIslandBridge/main.swift:75`; no upstream fix yet in wxtsky/CodeIsland → **T-077** (new, high priority, M)
- **vibeislandapp/vibe-island issue #165** (open, Jul 15): "Claude usage quota not displayed when using Claude Code in Claude Desktop" — vibe-island usage footer doesn't recognise Claude Desktop sessions; note for when T-073 and T-070 are implemented: Claude Desktop (`com.anthropic.claudefordesktop`) sessions may need special-casing in `ClaudeUsageScanner` since their transcript paths differ from CLI sessions; no separate task yet
- **One new task (T-077).** All other open tasks (T-016 through T-076) remain as previously documented.

**Scouted (July 18, 2026) — post-v1.0.30 activity:**
- No new commits or releases since v1.0.30 (Jul 10); latest upstream commit remains `3e2aec7` — upstream quiet for 8 days
- PR #266 (open, Jul 16): Trae CLI Next hooks — non-Claude CLI; skip (unchanged)
- PR #264 (open, Jul 15, draft): OMP terminal fix — non-Claude CLI; skip (unchanged)
- PR #262 (open, Jul 14): fold Cursor Tasks — Cursor-specific; skip (unchanged)
- **vibeislandapp/vibe-island issue #170** (open, Jul 17): "Session question doesn't get noticed as done" — user reports pressing Escape on a question prompt in Ghostty doesn't dismiss the panel in vibe-island v1.0.41; resolves after ~5 min; additional confirmation of T-057 pattern (stuck panel after in-terminal action); no upstream code fix yet
- **vibeislandapp/vibe-island issue #168** (open, Jul 17): "Vibe Island on multiple screens" — feature request to show island on all connected screens simultaneously; reinforces T-056 (display picker / multi-display); no upstream code fix yet
- vibeislandapp/vibe-island issue #167 (open, Jul 17): "[Bug]" (limits display, Warp, macOS 26.5.2) — insufficient detail; no upstream fix; skip
- vibeislandapp/vibe-island issue #169 (open, Jul 17): Portuguese L10n — skip (we don't ship L10n)
- **No new actionable items.** All open tasks (T-016 through T-077) remain as previously documented. GitHub issues list in `nguyenvanduocit/CodeIsland` remains empty (0 issues).

**Scouted (July 20, 2026) — post-v1.0.30 activity:**
- No new commits or releases since v1.0.30 (Jul 10); latest upstream commit remains `3e2aec7` — upstream quiet for 10 days
- **PR #270** (open, Jul 19): "fix: honor $CLAUDE_CONFIG_DIR instead of hardcoding ~/.claude" — introduces `ClaudeConfigPaths` resolver with priority order: user pref → `$CLAUDE_CONFIG_DIR` env var → `~/.config/claude-code` XDG probe → `~/.claude` fallback; adds Settings preference field (needed because Login-Item launch doesn't inherit shell env); 17 new tests, 560 passing. Confirmed same bug in our fork at `ConfigInstaller.swift:30-32,40,70`, `SessionTitleStore.swift:20`, `SessionUsageReader.swift:67`, `ProcessScanner.swift:37` → **T-079** (new, high priority, S)
- **Issue #269** (open, Jul 19): "No Claude sessions detected when $CLAUDE_CONFIG_DIR is set" — user report confirming T-079; PR #270 is the upstream fix
- **Issue #271** (open, Jul 19): "Follow-up: remote-host and hook-cleanup gaps around $CLAUDE_CONFIG_DIR" — gaps 1–2 (RemoteInstaller) not applicable (we have no SSH remote); gap 3 (orphaned hooks on config-dir change) is applicable but low priority; no separate task yet
- **Issue #268** (open, Jul 19): "Changing Island Width doesn't do anything" — regression in upstream affecting T-021; we haven't implemented the width slider yet so not directly applicable to our fork
- **PR #267** (open, Jul 19): "fix: support Codex Desktop hosted by ChatGPT" — Codex-specific; skip
- **PR #266** (open, Jul 16): "fix(trae): support Trae CLI Next hooks" — Trae CLI non-Claude CLI; skip
- vibeislandapp/vibe-island: `22c6f31` (Jul 17) remains the latest commit — docs only, nothing actionable
- ⚠️ GitHub Issues API unavailable for wxtsky/CodeIsland (403 from network policy); PRs/issues accessed via GitHub web pages instead
- ⚠️ Attempted to create GitHub issue in nguyenvanduocit/CodeIsland for T-079 but GitHub returned persistent 503; tracked in kanban as T-079 instead

**Scouted (July 19, 2026) — post-v1.0.30 activity:**
- No new commits or releases since v1.0.30 (Jul 10); latest upstream commit remains `3e2aec7` — upstream quiet for 9 days
- PR #266 (open, Jul 16): Trae CLI Next hooks — non-Claude CLI; skip (unchanged)
- PR #264 (open, Jul 15, draft): OMP terminal fix — non-Claude CLI; skip (unchanged)
- PR #262 (open, Jul 14): fold Cursor Tasks — Cursor-specific; skip (unchanged)
- PR #257 (open, Jul 10): OpenCode v2 events — OpenCode-specific; skip (unchanged)
- wxtsky/CodeIsland issue #263 (open, Jul 14): panel detach from notch on macOS 27.0 beta — T-076, no upstream fix yet; unchanged
- wxtsky/CodeIsland issue #265 (open, Jul 15): Cursor question prompts stuck — Cursor-specific; skip
- **vibeislandapp/vibe-island issue #171** (open, Jul 18): "使用Claude code的computer use时vibe island阻止点击" — when Claude Code's `computer_use` tool issues pixel-coordinate clicks, any coordinate landing on the island panel is rejected with "Click at these coordinates would land on 'Vibe Island', which is not in the allowed applications."; root cause: panel window captures mouse events at those coordinates, making the top-of-screen dead zone for AI agents; our `PanelWindowController` has the same behavior; fix is likely `NSWindow.ignoresMouseEvents = true` in collapsed state → **T-078** (new, low priority, XS)
- vibeislandapp/vibe-island issue #172 (open, Jul 18): Remote Connection to Windows — out of scope (macOS only); skip
- vibeislandapp/vibe-island issue #173 (open, Jul 18): Settings sub-option refresh bug for "Show Usage Limit" — vibe-island specific settings feature we don't have; skip
- vibeislandapp/vibe-island: `22c6f31` (Jul 17) remains latest commit — docs only, nothing actionable
- ⚠️ GitHub Issues are **disabled** in `nguyenvanduocit/CodeIsland` (API returns 410) — all tracking via kanban board only
- **One new task added (T-078).** All other open tasks (T-016 through T-077) remain as previously documented.

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
