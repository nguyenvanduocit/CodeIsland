# Kanban Board
<!-- Updated: 2026-04-07 -->

## Backlog

## Todo

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
