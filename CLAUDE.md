# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# CodeIsland

macOS notch-panel app for monitoring Claude Code AI agent sessions.

## Build & Test

```bash
swift build                # Debug build
swift test                 # Run all tests
./restart.sh               # Dev cycle: kill → rebuild → launch
./build.sh                 # Release universal binary (arm64 + x86_64) + app bundle
./install.sh               # Install to /Applications
./install-skills.sh        # Install Claude Code skills
```

- SPM-only, no Xcode project. No external dependencies.
- No CI — always run `swift build && swift test` before committing.

## Architecture

- **CodeIslandCore**: Pure models + logic (SessionSnapshot, HookEvent, ProcessScanner)
- **CodeIsland**: Main macOS app (AppState, views, services)
- **CodeIslandBridge**: Native hook event forwarder (compiled binary, forwards to Unix socket `/tmp/codeisland-<uid>.sock`)

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

- Swift 5.9+, macOS 14+ target
- `@Observable` + `@MainActor` for state management
- Pure reducer pattern: `reduceEvent()` returns `[SideEffect]`
- Monospaced pixel aesthetic for UI
- Services are injected dependencies (not singletons)

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
