# Libraries, Frameworks & Services

## Current Dependencies

### Apple Frameworks

CodeIsland uses **zero third-party dependencies**. All functionality relies exclusively on macOS system frameworks.

| Framework | Usage |
|---|---|
| **SwiftUI** | Main UI (Notch panel, Settings, Views) |
| **AppKit** | NSPanel/NSWindowController for borderless floating windows, menu bar, application control |
| **Foundation** | Networking, file I/O, JSON serialization, process management |
| **Combine** | Reactive data flow between components |
| **Network** | Unix domain socket IPC (NWListener/NWConnection for hook server) |
| **os.log** | Unified logging system for debugging and analytics |
| **Darwin** | POSIX system calls (file descriptors, signals) |
| **CoreServices** | Launch Services integration |
| **ServiceManagement** | Launch at login (SMAppService) |

---

## Planned Dependencies

As CodeIsland evolves, consider these libraries for future features. Currently, interim solutions are implemented:

| Feature | Recommended | Current Approach | Status |
|---|---|---|---|
| **Auto-Update** | Sparkle 2.8.1 | GitHub API + UpdateChecker | [Planned] |
| **Crash Reporting** | Sentry (Cocoa SDK 8.x) | Manual GitHub issues | [Planned] |
| **Global Hotkeys** | HotKey or Carbon.API | Hook system dispatcher | [Planned] |
| **JSON Flexibility** | AnyCodable | Foundation JSONDecoder | [Planned] |
| **Logging (bridge)** | swift-log | Custom bridge logging | [Planned] |
| **Settings UI** | Settings (sindresorhus) | Custom SwiftUI SettingsView | [Planned] |
| **Launch at Login** | LaunchAtLogin-Modern | ServiceManagement | Current |
| **Defaults (type-safe)** | Defaults (sindresorhus) | UserDefaults | [Planned] |

### Why Zero Dependencies Now

1. **Small, focused scope**: Single-file tools don't need heavyweight frameworks.
2. **Faster iteration**: No dependency update churn during early development.
3. **Simpler distribution**: Smaller binary, no linked dylibs, instant GitHub releases.
4. **Full control**: Implement exactly what's needed, nothing more.

---

## Service Integrations

### AI Tool Hook System

CodeIsland installs hooks into Claude Code via `ConfigInstaller.swift`. The hook dispatcher uses a native bridge binary with fallback to shell scripts.

#### Claude Code
- **Config file**: `~/.claude/settings.json` (JSONC format)
- **Hook command**: `~/.claude/hooks/codeisland-hook.sh` (shell wrapper with bridge binary)
- **Bridge binary**: `~/.claude/hooks/codeisland-bridge` (native Swift binary)
- **Events registered**:
  - UserPromptSubmit (timeout: 5s)
  - PreToolUse (timeout: 5s)
  - PostToolUse (timeout: 5s)
  - PostToolUseFailure (timeout: 5s)
  - PermissionRequest (timeout: 86400s)
  - PermissionDenied (timeout: 5s)
  - Stop (timeout: 5s)
  - SubagentStart (timeout: 5s)
  - SubagentStop (timeout: 5s)
  - SessionStart (timeout: 5s)
  - SessionEnd (timeout: 5s)
  - Notification (timeout: 86400s)
  - PreCompact (timeout: 5s)
- **Protocol**: Nested JSON format with matcher + hooks array
- **Docs**: https://docs.anthropic.com/en/docs/claude-code/hooks

---

## External Services

| Service | Purpose | Status |
|---|---|---|
| **GitHub API** | Version checking for updates | Current (UpdateChecker) |
| **GitHub Releases** | Download binaries, appcast distribution | Current |
| **Sentry** (sentry.io) | Crash reporting, breadcrumbs, performance tracing | [Planned] |
| **Sparkle Update Server** | Host appcast.xml for auto-updates | [Planned], interim: GitHub Releases |

**Note**: CodeIsland does not currently use:
- License servers (open-source)
- Centralized analytics (local-only or none)

---

## Build & Distribution

### Build Configuration

**Package.swift** (Swift Package Manager):
- **Swift version**: 5.9+
- **Platforms**: macOS 14.0+
- **Targets**:
  - `CodeIslandCore` (library): Core logic, configuration, utilities
  - `CodeIsland` (executable): Main app with SwiftUI UI and AppKit windows
  - `codeisland-bridge` (executable): Native hook dispatcher binary
  - Test targets: CodeIslandCoreTests, CodeIslandTests

**No XcodeGen or project.yml**: Direct SPM build.

### Build Tools
| Tool | Purpose |
|---|---|
| `swift build` | Standard SPM builds |
| `swift test` | Unit and integration tests |
| Xcode 15+ | IDE and GUI test runner |
| `xcrun notarytool` | Apple code signing and notarization |
| `create-dmg` | DMG packaging for distribution |

### Distribution Channels
| Channel | Method | Status |
|---|---|---|
| **GitHub Releases** | Direct DMG download | Current |
| **Homebrew Cask** | `brew install --cask codeisland` | Current |
| **Build from source** | `swift build -c release` | Current |

### CI/CD Pipeline (Recommended)

```yaml
# GitHub Actions workflow
name: Release

on:
  push:
    tags: ["v*"]

jobs:
  build-and-release:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Build universal binary
        run: |
          swift build -c release --arch arm64 --arch x86_64
      
      - name: Run tests
        run: swift test
      
      - name: Code sign and notarize
        run: |
          codesign --force --verify --verbose --sign "Developer ID Application" CodeIsland.app
          xcrun notarytool submit CodeIsland.dmg \
            --apple-id ${{ secrets.APPLE_ID }} \
            --password ${{ secrets.APPLE_PASSWORD }} \
            --team-id ${{ secrets.APPLE_TEAM_ID }}
      
      - name: Create DMG
        run: create-dmg CodeIsland.app
      
      - name: Create GitHub Release
        uses: softprops/action-gh-release@v1
        with:
          files: CodeIsland.dmg
```

---

## macOS Permissions Required

CodeIsland requests only essential permissions:

| Permission | Purpose | When Requested | How Used |
|---|---|---|---|
| **Accessibility** | Terminal tab switching and global hotkey registration | After onboarding, before first use | TerminalActivator.swift: AppleScript to Ghostty, iTerm2, Terminal, WezTerm, kitty |
| **Automation** (AppleScript) | Control terminal windows (iTerm2, Terminal.app, Ghostty) | On first terminal activation | Activate window, switch tabs, read session metadata |
| **Notifications** | Show AI session completion alerts | On first notification send | NSUserNotification or UserNotification framework |
| **Login Items** | Launch CodeIsland at user login | Settings toggle in preferences | ServiceManagement.SMAppService |

### Terminals Supported

**Tab-level activation** (TerminalActivator.swift, supported list):
- Ghostty (com.mitchellh.ghostty)
- iTerm2 (com.googlecode.iterm2)
- WezTerm (com.github.wez.wezterm)
- kitty (net.kovidgoyal.kitty)
- Terminal.app (com.apple.Terminal)
- cmux (com.cmuxterm.app)

**App-level activation** (no tab switching):
- Alacritty
- Warp
- Hyper
- Tabby
- Rio

**Tmux support**: Automatic pane detection and switching via `tmux select-window` and `tmux select-pane`.

### Permissions NOT Needed

- Full Disk Access
- Screen Recording
- Camera/Microphone
- Location Services
- Contacts/Calendar
- Bluetooth

---

## Update Mechanism

### Current (GitHub API)

`UpdateChecker.swift` polls GitHub API for releases:
1. Checks `https://api.github.com/repos/wxtsky/CodeIsland/releases/latest`
2. Compares version numbers (semantic versioning)
3. Shows alert if newer version available
4. User clicks to open release page in browser

**Silent checks**: Automatic on app launch (if not version 0.0.0)
**Manual checks**: User triggers via menu → About → Check for Updates

### Planned (Sparkle Framework)

Replace UpdateChecker with Sparkle 2.8.1:
- Native app auto-update with progress UI
- Incremental delta updates
- Code signing validation
- Background updates (optional)
- Appcast.xml feed from GitHub Pages
