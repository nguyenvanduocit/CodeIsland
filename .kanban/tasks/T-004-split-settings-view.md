# T-004: Tach SettingsView thanh file/page

## Hien trang

`SettingsView.swift` = **1009 dong**, chua 1 enum, 1 main view, 7 pages, va nhieu helper views.

## Plan

### Step 1: Tao `AppLogoView.swift` (30 dong, standalone)

Di chuyen:
- `AppLogoView` (dong 979-1008) -> da `internal`

Import: `SwiftUI`
Ly do tach rieng: dung o ca SettingsView (About) va NotchPanelView.

### Step 2: Tao `SettingsGeneralPage.swift` (~35 dong)

Di chuyen:
- `GeneralPage` (dong 123-157) -> bo `private`

Import: `SwiftUI`
Dependencies: `L10n` (via @Environment), `SettingsKey`, `SettingsDefaults`, `SettingsManager`

### Step 3: Tao `SettingsBehaviorPage.swift` (~260 dong)

Di chuyen (gom chung — colocation):
- `BehaviorPage` (dong 161-212) -> bo `private`
- `BehaviorAnim` enum (dong 765-767) -> giu `private`
- `BehaviorToggleRow` (dong 769-786) -> giu `private`
- `NotchMiniAnim` (dong 789-975, 187 dong Canvas animations) -> giu `private`

Import: `SwiftUI`
Dependencies: `L10n`, `SettingsKey`, `SettingsDefaults`

### Step 4: Tao `SettingsAppearancePage.swift` (~140 dong)

Di chuyen:
- `AppearancePage` (dong 375-424) -> bo `private`
- `AppearancePreview` (dong 427-513) -> giu `private`

Import: `SwiftUI`, `CodeIslandCore`
Dependencies: `L10n`, `SettingsKey`, `SettingsDefaults`, `MascotView`, `MiniAgentIcon`

### Step 5: Tao `SettingsMascotsPage.swift` (~85 dong)

Di chuyen:
- `MascotsPage` (dong 517-565) -> bo `private`
- `MascotRow` (dong 567-602) -> giu `private`

Import: `SwiftUI`, `CodeIslandCore`
Dependencies: `L10n`, `SettingsKey`, `SettingsDefaults`, `AgentStatus`, `MascotView`, `cliIcon()`

### Step 6: Tao `SettingsSoundPage.swift` (~90 dong)

Di chuyen:
- `SoundPage` (dong 606-665) -> bo `private`
- `SoundEventRow` (dong 667-696) -> giu `private`

Import: `SwiftUI`
Dependencies: `L10n`, `SettingsKey`, `SettingsDefaults`, `SoundManager`

### Step 7: Tao `SettingsHooksPage.swift` (~155 dong)

Di chuyen:
- `HooksPage` (dong 216-303) -> bo `private`
- `CLIStatusRow` (dong 305-371) -> giu `private`

Import: `SwiftUI`, `AppKit`
Dependencies: `L10n`, `ConfigInstaller`, `cliIcon()`

### Step 8: Tao `SettingsAboutPage.swift` (~62 dong)

Di chuyen:
- `AboutPage` (dong 700-761) -> bo `private`

Import: `SwiftUI`, `AppKit`
Dependencies: `L10n`, `AppLogoView`

### Step 9: Cleanup SettingsView.swift (con lai ~100 dong)

Giu lai:
- `SettingsPage` enum (dong 6-40) -> giu `internal`
- `SidebarGroup` (dong 42-45) -> giu `private`
- `sidebarGroups` (dong 47-50) -> giu `private`
- `SettingsView` (dong 54-91) -> giu `internal`
- `SidebarRow` (dong 100-119) -> giu `private`
- Xoa `PageHeader` (dong 93-98) — chi la EmptyView, dead code

### Step 10: Build + verify

```bash
swift build
swift test
```

## Files moi tong ket

| File | Dong | Main struct | Access |
|------|------|-------------|--------|
| `SettingsView.swift` | ~100 | `SettingsView` | internal |
| `AppLogoView.swift` | ~30 | `AppLogoView` | internal |
| `SettingsGeneralPage.swift` | ~35 | `GeneralPage` | internal |
| `SettingsBehaviorPage.swift` | ~260 | `BehaviorPage` | internal |
| `SettingsAppearancePage.swift` | ~140 | `AppearancePage` | internal |
| `SettingsMascotsPage.swift` | ~85 | `MascotsPage` | internal |
| `SettingsSoundPage.swift` | ~90 | `SoundPage` | internal |
| `SettingsHooksPage.swift` | ~155 | `HooksPage` | internal |
| `SettingsAboutPage.swift` | ~62 | `AboutPage` | internal |

## Risk

- THAP. Chi la di chuyen code + doi access modifiers. Khong thay doi logic.
- Phu thuoc T-003 (L10n migration) de tranh doi `@ObservedObject` 2 lan.
