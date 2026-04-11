# Kanban Board
<!-- Updated: 2026-04-09 -->

## Backlog

## Todo

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

### [T-011: Cherry-pick features từ reference projects](tasks/T-011-reference-sync-apr09.md)
> Replicate 7 features từ upstream, open-vibe-island, notchi — adapt theo kiến trúc mình.
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

### [T-010: Sprite mascot system từ notchi](tasks/T-010-sprite-mascot-system.md)
> 17 sprite PNGs, MascotState/EmotionState models, SpriteSheetView + motion helpers, MascotView wired.
- **priority**: medium
- **effort**: L
- **completed**: 2026-04-08

### [T-001: Tách NotchPanelView thành các file riêng](tasks/T-001-split-notch-panel-view.md)
> 1786 dòng → 368 dòng + 6 file mới. Dead code xóa (PixelText, inlineMarkdown).

- **priority**: critical
- **effort**: L
- **completed**: 2026-04-07

### [T-002: Tách AppState thành 4 services](tasks/T-002-split-appstate.md)
> 1186 dòng → 745 dòng. 4 services: ProcessMonitorService, SessionDiscoveryService, CompletionQueueService, RequestQueueService.

- **priority**: critical
- **effort**: L
- **completed**: 2026-04-07

### [T-003: Modernize L10n sang @Observable](tasks/T-003-modernize-l10n.md)
> @Observable + @Environment(\.l10n) thay ObservableObject + @ObservedObject. 13 views updated. @Bindable cho GeneralPage.

- **priority**: high
- **effort**: M
- **completed**: 2026-04-07

### [T-004: Tách SettingsView thành 9 files](tasks/T-004-split-settings-view.md)
> 1009 dòng → 119 dòng + 9 file mới (AppLogoView + 7 pages + shared). Dead code xóa (PageHeader).

- **priority**: medium
- **effort**: S
- **completed**: 2026-04-07

### [T-005: Modernize concurrency patterns](tasks/T-005-modernize-concurrency.md)
> 9 Timer → Task loop, 6 DispatchQueue.global → Task.detached, 2 asyncAfter → Task.sleep, FSEventStream → AsyncStream wrapper.

- **priority**: medium
- **effort**: M
- **completed**: 2026-04-07

## Blocked
