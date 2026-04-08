# T-008: Silent Dynamic Island mode during active work

> Add a behavior toggle to suppress mascot animation while working, keeping alerts for approvals/completions.

- **priority**: medium
- **effort**: M
- **source**: wxtsky/CodeIsland PR #30 (open, 2026-04-07) — watch for merge before implementing

## Context

An open upstream PR proposes a `silentWorkMode` setting that suppresses the animated mascot (running/processing → idle) during active agent work, while preserving critical states (approvals, questions, completions).

Key design:
- `silentWorkMode: Bool` setting (default `false`) in `Settings.swift`
- `effectiveMascotStatus()` helper: maps `.running`/`.processing` → `.idle` when mode is on
- Applied in `NotchPanelView.swift` for both compact bar and session card views
- Toggle in Behavior settings page with an animated before/after preview
- `MascotViewTests.swift` covers the state-conversion logic

**Status**: Not yet merged upstream. Monitor wxtsky/CodeIsland PR #30 before implementing.

## Criteria

- [ ] `silentWorkMode` boolean setting registered in `Sources/CodeIsland/Settings.swift`
- [ ] `effectiveMascotStatus()` helper added to `MascotView.swift` (or similar)
- [ ] Compact bar and session card views use `effectiveMascotStatus()` for mascot display
- [ ] Approval/question/completion states are NOT suppressed by silent mode
- [ ] Toggle added to BehaviorPage in `SettingsView.swift` with preview animation
- [ ] Unit tests cover: running→idle (on), approval unchanged (on), mode off (no-op)
- [ ] `swift build && swift test` passes
