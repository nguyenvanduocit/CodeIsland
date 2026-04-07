# T-001: Tach NotchPanelView thanh cac file rieng

## Hien trang

`NotchPanelView.swift` = **1786 dong**, chua **22 struct/view** + **6 free function/variable**. Tat ca deu `private` ngoai tru `NotchPanelView`, `MiniAgentIcon`, va `cliIcon()`.

## Plan

### Step 1: Tao `NotchSharedHelpers.swift` (leaf node, khong dependency vao file khac)

Di chuyen tu `NotchPanelView.swift`:
- `SessionTag` (dong 1603-1623, 21 dong) -> `private` thanh `internal`
- `TypingIndicator` (dong 1627-1664, 38 dong) -> `private` thanh `internal`
- `MiniAgentIcon` (dong 1668-1713, 46 dong) -> da `internal`
- `Line` shape (dong 1574-1581, 8 dong) -> `private` thanh `internal`
- `cliIconFiles`, `cliIconCache`, `cliIcon()` (dong 1585-1601) -> `cliIcon()` da `internal`
- `shortSessionId()` (dong 1737-1743) -> `private` thanh `internal`
- `stripDirectives()` (dong 1747-1785) -> `private` thanh `internal`

Import: `SwiftUI`, `AppKit`

### Step 2: Tao `NotchPanelShape.swift`

Di chuyen:
- `NotchPanelShape` (dong 1375-1434, 60 dong) -> `private` thanh `internal`

Import: `SwiftUI`

### Step 3: Tao `ClaudeLogoView.swift`

Di chuyen:
- `ClaudeLogo` (dong 1256-1268, 13 dong) -> `private` thanh `internal`
- `ClaudeLogoShape` (dong 1270-1371, 102 dong) -> giu `private` (cung file)
- `ClaudeLogo.svgPath`: doi tu `fileprivate static` thanh `static` (de ClaudeLogoShape truy cap trong cung file)

Import: `SwiftUI`

### Step 4: Tao `ApprovalBarView.swift`

Di chuyen:
- `ApprovalBar` (dong 372-597, 226 dong) -> `private` thanh `internal`
- `PixelButton` (dong 780-807, 28 dong) -> `private` thanh `internal` (dung boi ca QuestionBar)

Import: `SwiftUI`, `CodeIslandCore`

### Step 5: Tao `QuestionBarView.swift`

Di chuyen:
- `QuestionBar` (dong 601-725, 125 dong) -> `private` thanh `internal`
- `OptionRow` (dong 729-778, 50 dong) -> giu `private` (chi dung boi QuestionBar)

Dependency: `PixelButton` (tu ApprovalBarView), `cliIcon()` (tu NotchSharedHelpers)
Import: `SwiftUI`, `CodeIslandCore`

### Step 6: Tao `SessionListView.swift`

Di chuyen:
- `SessionListView` (dong 811-865, 55 dong) -> `private` thanh `internal`
- `ThinScrollView` (dong 868-901, 34 dong) -> giu `private`
- `SessionCard` (dong 1075-1252, 178 dong) -> giu `private`
- `SessionIdCopyButton` (dong 903-952, 50 dong) -> giu `private`
- `SessionIdentityLine` (dong 954-1003, 50 dong) -> giu `private`
- `ProjectNameLink` (dong 1005-1037, 33 dong) -> giu `private`
- `SessionsExpandLink` (dong 1039-1073, 35 dong) -> giu `private`
- `TerminalJumpButton` (dong 1437-1492, 56 dong) -> giu `private`

Dependency: `SessionTag`, `TypingIndicator`, `MiniAgentIcon`, `shortSessionId()`, `stripDirectives()` (tu NotchSharedHelpers)
Import: `SwiftUI`, `CodeIslandCore`

### Step 7: Xoa dead code

- `PixelText` (dong 1496-1572, 77 dong) -> verify khong ai dung, xoa
- `inlineMarkdown()` free function (dong 1721-1734) + `markdownCache` + `markdownCacheLimit` -> verify dead code (SessionCard dung `ChatMessageTextFormatter.inlineMarkdown` thay the), xoa

### Step 8: Cap nhat NotchPanelView.swift (con lai ~280 dong)

Giu lai:
- `NotchPanelView` (dong 4-217, 214 dong)
- `CompactLeftWing` (dong 223-244, 22 dong) -> giu `private`
- `CompactRightWing` (dong 247-291, 45 dong) -> giu `private`
- `IdleIndicatorBar` (dong 321-368, 48 dong) -> giu `private`
- `NotchIconButton` (dong 293-317, 25 dong) -> giu `private`

### Step 9: Build + verify

```bash
swift build
swift test
```

## Dependency graph (file moi)

```
NotchPanelView.swift
  ├── NotchSharedHelpers.swift (Line)
  ├── NotchPanelShape.swift (NotchPanelShape)
  ├── ApprovalBarView.swift (ApprovalBar)
  ├── QuestionBarView.swift (QuestionBar)
  └── SessionListView.swift (SessionListView)

QuestionBarView.swift
  ├── ApprovalBarView.swift (PixelButton)
  └── NotchSharedHelpers.swift (cliIcon)

SessionListView.swift
  └── NotchSharedHelpers.swift (SessionTag, TypingIndicator, MiniAgentIcon, shortSessionId, stripDirectives)

ClaudeLogoView.swift (standalone)
NotchPanelShape.swift (standalone)
NotchSharedHelpers.swift (standalone, leaf)
```

## Access modifier changes tong ket

| Symbol | Cu | Moi | File moi |
|--------|-----|-----|----------|
| `ApprovalBar` | private | internal | ApprovalBarView.swift |
| `PixelButton` | private | internal | ApprovalBarView.swift |
| `QuestionBar` | private | internal | QuestionBarView.swift |
| `SessionListView` | private | internal | SessionListView.swift |
| `NotchPanelShape` | private | internal | NotchPanelShape.swift |
| `ClaudeLogo` | private | internal | ClaudeLogoView.swift |
| `SessionTag` | private | internal | NotchSharedHelpers.swift |
| `TypingIndicator` | private | internal | NotchSharedHelpers.swift |
| `Line` | private | internal | NotchSharedHelpers.swift |
| `shortSessionId()` | private | internal | NotchSharedHelpers.swift |
| `stripDirectives()` | private | internal | NotchSharedHelpers.swift |
| `ClaudeLogo.svgPath` | fileprivate | internal/static | ClaudeLogoView.swift |
