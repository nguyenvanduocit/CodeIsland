# Kanban Board
<!-- Updated: 2026-04-08 -->

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

## Done

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
