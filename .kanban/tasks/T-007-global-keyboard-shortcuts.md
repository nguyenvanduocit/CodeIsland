# T-007: Global keyboard shortcuts settings page

> Add a Shortcuts settings page with user-configurable key bindings (incl. default ⌘⇧I panel toggle).

- **priority**: medium
- **effort**: M
- **source**: wxtsky/CodeIsland v1.0.7 (noted as unsynced in CLAUDE.md); PR #31 added tests 2026-04-07

## Context

wxtsky/CodeIsland ships a full `Shortcuts` settings page (their 8th page) with:
- `ShortcutAction.allCases` — enumerable shortcut actions  
- Keyboard recording via `NSEvent` monitoring (Cmd/Ctrl/Option required)
- Conflict detection with visual warning
- Clear/reset per binding
- Default `⌘⇧I` binding for toggling the panel without hovering the notch

Our `SettingsPage` enum has 7 cases (`general, behavior, appearance, mascots, sound, hooks, about`) — `shortcuts` is absent. We have no way to open the panel via keyboard.

Already noted in `CLAUDE.md` as "Unsynced from v1.0.7: global shortcuts".

## Criteria

- [ ] `shortcuts` case added to `SettingsPage` enum with icon/color
- [ ] `ShortcutsPage` view implemented in SettingsView (or extracted file) with shortcut recording UI
- [ ] Conflict detection warns when two actions share a binding
- [ ] Default `⌘⇧I` binding wired up in `PanelWindowController.swift` as global event monitor
- [ ] Shortcut bindings persisted via `Settings.swift` / UserDefaults
- [ ] `swift build && swift test` passes
