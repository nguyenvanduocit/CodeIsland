# T-003: Modernize L10n sang @Observable

## Hien trang

`L10n.swift` dung `ObservableObject` + `@Published` (Combine-based). 13 views dung `@ObservedObject private var l10n = L10n.shared`. Project da dung `@Observable` cho AppState (macOS 14+).

## Plan

### Step 1: Chuyen L10n class sang @Observable

File: `Sources/CodeIsland/L10n.swift`

```swift
// TRUOC:
import Combine
final class L10n: ObservableObject {
    static let shared = L10n()
    @Published var language: String { didSet { ... } }
}

// SAU:
import Observation
@Observable
@MainActor
final class L10n {
    static let shared = L10n()
    var language: String { didSet { ... } }  // xoa @Published
}
```

Thay doi:
- Xoa `import Combine`, them `import Observation` (hoac chi can SwiftUI)
- Xoa `: ObservableObject`
- Them `@Observable` macro
- Them `@MainActor` (nhat quan voi AppState)
- Xoa `@Published` truoc `var language`
- Giu nguyen `didSet`, `subscript`, `effectiveLanguage`, static data

### Step 2: Tao EnvironmentKey

Them vao cuoi `L10n.swift`:

```swift
extension EnvironmentValues {
    @Entry var l10n: L10n = .shared
}
```

Dung `@Entry` macro (Xcode 16, back-deploys to all OS) thay vi manual `EnvironmentKey`.

### Step 3: Inject L10n vao view hierarchy

File: `Sources/CodeIsland/CodeIslandApp.swift`

```swift
// TRUOC:
@ObservedObject private var l10n = L10n.shared

// SAU: xoa @ObservedObject, them .environment
WindowGroup {
    ContentView()
        .environment(\.l10n, L10n.shared)
}
```

### Step 4: Cap nhat tat ca Views (13 cho)

Pattern cu -> moi:
```swift
// CU:
@ObservedObject private var l10n = L10n.shared

// MOI:
@Environment(\.l10n) private var l10n
```

**Files can thay doi:**

| # | File | Dong | Struct |
|---|------|------|--------|
| 1 | `CodeIslandApp.swift` | 6 | `CodeIslandApp` |
| 2 | `SettingsView.swift` | 55 | `SettingsView` |
| 3 | `SettingsView.swift` | 101 | `SidebarRow` |
| 4 | `SettingsView.swift` | 124 | `GeneralPage` |
| 5 | `SettingsView.swift` | 162 | `BehaviorPage` |
| 6 | `SettingsView.swift` | 217 | `HooksPage` |
| 7 | `SettingsView.swift` | 306 | (page struct) |
| 8 | `SettingsView.swift` | 376 | `AppearancePage` |
| 9 | `SettingsView.swift` | 518 | `MascotsPage` |
| 10 | `SettingsView.swift` | 607 | `SoundPage` |
| 11 | `SettingsView.swift` | 701 | `AboutPage` |
| 12 | `NotchPanelView.swift` | 250 | `CompactRightWing` |
| 13 | `NotchPanelView.swift` | 328 | `IdleIndicatorBar` |

### Step 5: Xu ly Binding `$l10n.language` (edge case)

File: `SettingsView.swift` dong 135 — `Picker(l10n["language"], selection: $l10n.language)`

Voi `@Environment`, khong co `$l10n` binding truc tiep. Dung `@Bindable`:

```swift
// Trong GeneralPage:
@Environment(\.l10n) private var l10n

var body: some View {
    @Bindable var l10n = l10n  // tao Bindable local
    Form {
        Picker(l10n["language"], selection: $l10n.language) { ... }
    }
}
```

Chi can `@Bindable` trong `GeneralPage` — noi DUY NHAT dung `$l10n.language`.

### Step 6: Fix inline L10n.shared[key] trong View body

Cac dong dung `L10n.shared["key"]` truc tiep trong SwiftUI body (thay vi qua local `l10n` var) se KHONG reactive khi doi ngon ngu. Thay bang `l10n["key"]`.

Files:
- `NotchPanelView.swift` dong 438-440, 530, 681, 704, 712, 938, 1035, 1049

### Step 7: Non-View contexts — KHONG thay doi

- `UpdateChecker.swift` (dong 65-69, 93-96): Doc `L10n.shared["key"]` de tao NSAlert. Imperative AppKit, khong can observation.
- `SettingsWindowController.swift` (dong 39): Doc `L10n.shared["settings_title"]` 1 lan. Khong can observation.

### Step 8: Build + verify

```bash
swift build
swift test
```

Verify: doi ngon ngu trong Settings, tat ca UI cap nhat dung.

## Risk

- THAP. Migration `ObservableObject` -> `@Observable` la well-documented path.
- `@Bindable` can Swift 5.9+ macOS 14+ — da target dung.
- SettingsWindowController.swift dong 39: window title van khong reactive khi doi ngon ngu (bug hien tai, khong lien quan migration).
