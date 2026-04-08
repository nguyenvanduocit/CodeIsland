# T-006: Port sidebar settings row text spacing fix

> Add `.padding(.leading, 2)` to settings sidebar label text to fix icon-text alignment.

- **priority**: low
- **effort**: XS
- **source**: wxtsky/CodeIsland commit 1f64d7f (2026-04-07, v1.0.15)

## Context

Upstream added a 2pt leading padding to the sidebar label text in `SettingsView.swift` to improve visual alignment between the icon and the page name text in the settings window.

Upstream diff in `SidebarRow`:
```swift
Label {
    Text(l10n[page.rawValue])
        .font(.system(size: 13))
+       .padding(.leading, 2)
} icon: {
```

Our current code at `Sources/CodeIsland/SettingsView.swift:100` is missing this padding.

## Criteria

- [ ] `.padding(.leading, 2)` added to `SidebarRow` label text in `Sources/CodeIsland/SettingsView.swift`
- [ ] Visual spacing between icon and text in settings sidebar is consistent with upstream
- [ ] `swift build` passes
