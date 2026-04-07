# Terminal Tab Jumping — Implementation Reference

## Overview

When a user clicks a session notification or session card in the Notch panel, CodeIsland activates the correct terminal window, tab, and pane where that Claude Code session is running. This document describes how terminal detection and activation work across different terminals and shell environments.

This capability requires **Accessibility** permission on macOS.

---

## Terminal Metadata Collection

The CodeIsland bridge (native Swift binary) collects terminal metadata from the environment and injects it into events as underscore-prefixed fields:

| Field | Source | Example | Purpose |
|-------|--------|---------|---------|
| `_term_app` | `TERM_PROGRAM` | `"iTerm.app"` | Program name (fallback) |
| `_term_bundle` | `__CFBundleIdentifier` | `"com.googlecode.iterm2"` | Bundle ID (preferred) |
| `_iterm_session` | `ITERM_SESSION_ID` (stripped) | `"SESSION-UUID"` | iTerm2 session ID |
| `_tty` | `/dev/tty` | `"/dev/ttys010"` | Terminal device path |
| `_kitty_window` | `KITTY_WINDOW_ID` | `"1"` | Kitty window ID |
| `_tmux` | `TMUX` | `"/tmp/tmux-501/default,12345,0"` | tmux socket info |
| `_tmux_pane` | `TMUX_PANE` | `"%5"` | tmux pane identifier |
| `_tmux_client_tty` | `tmux display-message` | `"/dev/ttys010"` | Outer terminal TTY in tmux |
| `_source` | `--source` flag | `"claude"` | CLI source |
| `_ppid` | `getppid()` | `12345` | Parent process ID |

See `Sources/CodeIslandBridge/main.swift` for collection logic.

---

## Terminal Detection Resolution

### Bundle ID Priority (Accurate)

TerminalActivator resolves terminal identity in this order:

1. **Bundle ID** (`_term_bundle`) — most accurate, used if present
2. **TERM_PROGRAM** (`_term_app`) — fallback, less reliable
3. **Running application scan** — when neither is available

For tmux/screen, the TERM_PROGRAM value is ignored (these are not GUI apps). The code falls back to detecting the running terminal by scanning `NSRunningApplication`.

Source: `TerminalActivator.swift` lines 76-89

### Known Terminal Bundle IDs

| Terminal | Bundle ID | Tab-Level Jump? | Method |
|----------|-----------|-----------------|--------|
| cmux | `com.cmuxterm.app` | No | Bring to front |
| Ghostty | `com.mitchellh.ghostty` | Yes | AppleScript + CWD/title match |
| iTerm2 | `com.googlecode.iterm2` | Yes | AppleScript + session ID |
| WezTerm | `com.github.wez.wezterm` | Yes | CLI: `wezterm cli activate-tab` |
| kitty | `net.kovidgoyal.kitty` | Yes | CLI: `kitten @ focus-window` |
| Alacritty | `org.alacritty` | No | Bring to front |
| Warp | `dev.warp.Warp-Stable` | No | Bring to front |
| Terminal | `com.apple.Terminal` | Yes | AppleScript + TTY match |

Source: `TerminalActivator.swift` lines 9-18

---

## Jump Implementations

### Resolution Logic

`TerminalActivator.activate(session:)` implements this dispatch:

1. **IDE integrated terminal** — if the terminal is an IDE (VS Code, JetBrains, etc.), activate the IDE app
2. **tmux pane** — if session is inside tmux, switch the tmux pane first (async)
3. **Tab-level switching** — for terminals that support it: iTerm2, Ghostty, Terminal.app, WezTerm, kitty
4. **App-level fallback** — for all other terminals, bring the app to front

Source: `TerminalActivator.swift` lines 36-137

### 1. Ghostty (AppleScript: CWD + Title Matching)

**Method**: AppleScript targeting by working directory and title keywords.

```swift
private static func activateGhostty(cwd: String?, sessionId: String? = nil, source: String = "claude") {
    guard let cwd = cwd, !cwd.isEmpty else { bringToFront("Ghostty"); return }
    
    if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.mitchellh.ghostty" }) {
        if app.isHidden { app.unhide() }
        app.activate()
    }
    
    let escaped = escapeAppleScript(cwd)
    let script = """
    tell application "Ghostty"
        set matches to (every terminal whose working directory is "\(escaped)")
        activate
    end tell
    """
    runAppleScript(script)
}
```

**Matching order**:
1. Exact session ID (8-char prefix) in terminal title
2. Source keyword ("claude") in terminal title
3. First terminal with matching CWD

Source: `TerminalActivator.swift` lines 140-186

### 2. iTerm2 (AppleScript: Session ID)

**Method**: AppleScript with iTerm2 unique session ID.

```swift
private static func activateITerm(sessionId: String) {
    if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.googlecode.iterm2" }) {
        if app.isHidden { app.unhide() }
        app.activate()
    }
    
    let script = """
    try
        tell application "iTerm2"
            repeat with aWindow in windows
                if miniaturized of aWindow then set miniaturized of aWindow to false
                repeat with aTab in tabs of aWindow
                    repeat with aSession in sessions of aTab
                        if unique ID of aSession is "\(escapeAppleScript(sessionId))" then
                            set miniaturized of aWindow to false
                            select aTab
                            select aSession
                            return
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
    end try
    """
    runAppleScript(script)
}
```

**Session ID extraction**: The bridge extracts the session GUID from `ITERM_SESSION_ID` by stripping the `w0t0p0:` prefix.

Source: `TerminalActivator.swift` lines 188-215, `Sources/CodeIslandBridge/main.swift` lines 228-235

### 3. Terminal.app (AppleScript: TTY Matching)

**Method**: AppleScript matching by `/dev/ttyXXX` device path.

```swift
private static func activateTerminalApp(ttyPath: String?) {
    guard let tty = ttyPath, !tty.isEmpty else { bringToFront("Terminal"); return }
    
    let escaped = escapeAppleScript(tty)
    let script = """
    tell application "Terminal"
        repeat with w in windows
            repeat with t in tabs of w
                if tty of t is "\(escaped)" then
                    if miniaturized of w then set miniaturized of w to false
                    set selected tab of w to t
                    set index of w to 1
                end if
            end repeat
        end repeat
        activate
    end tell
    """
    runAppleScript(script)
}
```

Source: `TerminalActivator.swift` lines 217-237

### 4. WezTerm (CLI: wezterm list + activate-tab)

**Method**: Query panes via `wezterm cli list --format json`, then activate by tab ID.

```swift
private static func activateWezTerm(ttyPath: String?, cwd: String?) {
    bringToFront("WezTerm")
    guard let bin = findBinary("wezterm") else { return }
    
    DispatchQueue.global(qos: .userInitiated).async {
        guard let json = runProcess(bin, args: ["cli", "list", "--format", "json"]),
              let panes = try? JSONSerialization.jsonObject(with: json) as? [[String: Any]] else { return }

        var tabId: Int?
        if let tty = ttyPath {
            tabId = panes.first(where: { ($0["tty_name"] as? String) == tty })?["tab_id"] as? Int
        }
        if tabId == nil, let cwd = cwd {
            let cwdUrl = "file://" + cwd
            tabId = panes.first(where: {
                guard let paneCwd = $0["cwd"] as? String else { return false }
                return paneCwd == cwdUrl || paneCwd == cwd
            })?["tab_id"] as? Int
        }

        if let id = tabId {
            _ = runProcess(bin, args: ["cli", "activate-tab", "--tab-id", "\(id)"])
        }
    }
}
```

Source: `TerminalActivator.swift` lines 239-265

### 5. kitty (CLI: kitten @ focus-window/focus-tab)

**Method**: Query windows via `kitten @ ls` JSON, focus by window ID or CWD.

```swift
private static func activateKitty(windowId: String?, cwd: String?, source: String = "claude") {
    bringToFront("kitty")
    guard let bin = findBinary("kitten") else { return }

    if let windowId = windowId, !windowId.isEmpty {
        DispatchQueue.global(qos: .userInitiated).async {
            _ = runProcess(bin, args: ["@", "focus-window", "--match", "id:\(windowId)"])
        }
        return
    }

    guard let cwd = cwd, !cwd.isEmpty else { return }
    DispatchQueue.global(qos: .userInitiated).async {
        if runProcess(bin, args: ["@", "focus-tab", "--match", "cwd:\(cwd)"]) == nil {
            _ = runProcess(bin, args: ["@", "focus-tab", "--match", "title:\(source)"])
        }
    }
}
```

Source: `TerminalActivator.swift` lines 267-288

### 6. tmux (CLI: tmux select-window/select-pane)

**Method**: CLI commands to switch tmux pane, then optionally activate the outer terminal.

```swift
private static func activateTmux(pane: String) {
    guard let bin = findBinary("tmux") else { return }
    DispatchQueue.global(qos: .userInitiated).async {
        _ = runProcess(bin, args: ["select-window", "-t", pane])
        _ = runProcess(bin, args: ["select-pane", "-t", pane])
    }
}
```

**TTY Resolution**: When a session runs in tmux, TerminalActivator uses the *client TTY* (outer terminal) for tab matching instead of the tmux pty:

```swift
let inTmux = session.tmuxPane != nil && !(session.tmuxPane ?? "").isEmpty
let effectiveTty = inTmux
    ? (session.tmuxClientTty ?? session.ttyPath)
    : session.ttyPath
```

This ensures that tab matching works against the real terminal (iTerm2, Ghostty, etc.) rather than tmux's internal pty.

Source: `TerminalActivator.swift` lines 290-299, 92-102

### 7. App-Level Fallback (NSRunningApplication)

**Method**: Bring app to front using NSRunningApplication.

```swift
private static func bringToFront(_ termApp: String) {
    if let app = NSWorkspace.shared.runningApplications.first(where: {
        $0.localizedName == name || ($0.bundleIdentifier ?? "").localizedCaseInsensitiveContains(name)
    }) {
        if app.isHidden { app.unhide() }
        app.activate()
        return
    }
    
    DispatchQueue.global(qos: .userInitiated).async {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = ["-a", name]
        try? proc.run()
    }
}
```

Supported terminals: Alacritty, Warp, Hyper, Tabby, Rio, cmux, and any other terminal not explicitly supported.

Source: `TerminalActivator.swift` lines 301-334

---

## Smart Notification Suppression (TerminalVisibilityDetector)

CodeIsland avoids notifying when the user is already looking at the session by checking if the session's terminal tab/pane is visible.

### Two Detection Levels

#### App-Level Check (Main Thread Safe)

```swift
static func isTerminalFrontmostForSession(_ session: SessionSnapshot) -> Bool {
    guard let frontApp = NSWorkspace.shared.frontmostApplication else { return false }

    if let termBundleId = session.termBundleId?.lowercased(),
       !termBundleId.isEmpty,
       frontApp.bundleIdentifier?.lowercased() == termBundleId {
        return true
    }

    guard let termApp = session.termApp else { return false }
    let frontName = frontApp.localizedName?.lowercased() ?? ""
    let bundleId = frontApp.bundleIdentifier?.lowercased() ?? ""
    let term = termApp.lowercased()
        .replacingOccurrences(of: ".app", with: "")
        .replacingOccurrences(of: "apple_", with: "")
    let normalizedFront = frontName.replacingOccurrences(of: ".app", with: "")

    return normalizedFront.contains(term)
        || term.contains(normalizedFront)
        || bundleId.contains(term)
}
```

**Use case**: Called from the main thread to make a fast decision: is the terminal app even in front? If not, notify immediately.

#### Tab-Level Check (Background Thread Only)

```swift
static func isSessionTabVisible(_ session: SessionSnapshot) -> Bool {
    guard isTerminalFrontmostForSession(session) else { return false }

    // IDE terminals: can't query tab state, assume NOT visible
    if session.isIDETerminal { return false }

    // Terminal-specific checks: iTerm2, Ghostty, Terminal.app, WezTerm, kitty, tmux
    // ...
}
```

**Use case**: Called from a background thread when the app is frontmost. Makes AppleScript/CLI calls to check if the specific tab/pane is active.

**IDE terminals** (VS Code, JetBrains, etc.): Cannot reliably query tab state, so notifications are never suppressed (return `false`).

Source: `TerminalVisibilityDetector.swift` lines 21-100

### Per-Terminal Visibility Checks

- **iTerm2**: Check current session by unique ID or CWD
- **Ghostty**: Check front window title contains CWD directory name
- **Terminal.app**: Check selected tab's TTY
- **WezTerm**: Query active pane by TTY or CWD via CLI
- **kitty**: Query focused window by window ID or CWD via CLI
- **tmux**: Query currently active pane via CLI

Source: `TerminalVisibilityDetector.swift` lines 102-279

---

## SessionSnapshot Terminal Fields

The `SessionSnapshot` struct (CodeIslandCore) holds terminal metadata:

```swift
public var termApp: String?           // "iTerm.app", "Apple_Terminal", etc.
public var itermSessionId: String?    // iTerm2 session ID for direct activation
public var ttyPath: String?           // /dev/ttys00X
public var kittyWindowId: String?     // Kitty window ID for precise focus
public var tmuxPane: String?          // tmux pane identifier (%0, %1, etc.)
public var tmuxClientTty: String?     // tmux client TTY for real terminal detection
public var termBundleId: String?      // __CFBundleIdentifier for precise terminal ID
public var source: String = "claude"  // always "claude"

// Computed properties
public var isIDETerminal: Bool        // IDE integrated terminal (VS Code, JetBrains, etc.)
public var terminalName: String?      // Display name ("iTerm2", "Ghostty", etc.)
```

Source: `Sources/CodeIslandCore/SessionSnapshot.swift`

---

## Architecture

### Flow: User clicks session → activate terminal

1. **UI layer** calls `TerminalActivator.activate(session:)`
2. **TerminalActivator** determines which terminal and jumps:
   - Resolves terminal by bundle ID or TERM_PROGRAM
   - Dispatches to terminal-specific jump function
   - Handles tmux pane switching if needed
3. **Terminal-specific jump** (AppleScript, CLI, or app activation):
   - iTerm2: AppleScript by session ID
   - Ghostty: AppleScript by CWD + title
   - Terminal.app: AppleScript by TTY
   - WezTerm: CLI `wezterm cli activate-tab`
   - kitty: CLI `kitten @ focus-window`
   - tmux: CLI `tmux select-pane`
   - Other: `NSRunningApplication.activate()`

### Flow: Event arrives → check if notification should be suppressed

1. **HookServer** receives event with terminal metadata
2. **AppState** or notification handler calls `TerminalVisibilityDetector.isSessionTabVisible()`
3. **TerminalVisibilityDetector**:
   - Fast app-level check (main thread safe)
   - If terminal is frontmost, do tab-level check (background thread)
   - Return `true` (suppress) if tab is visible, `false` (notify) if not
4. **Notification suppression** triggered only if visible

Source: `TerminalActivator.swift`, `TerminalVisibilityDetector.swift`

---

## macOS Permissions

CodeIsland requires **Accessibility** (aka Universal Access) permission to control terminal apps via AppleScript.

The app's `Info.plist` includes:

```xml
<key>NSAppleEventsUsageDescription</key>
<string>CodeIsland needs to control terminal apps (iTerm2, Terminal) to jump to the correct window, tab, and session when you click a notification.</string>
```

---

## Notes and Limitations

### Limitations

- **Alacritty, Warp, Hyper, Tabby, Rio**: No tab-level switching; only app-level activation. Users must manually select the tab.
- **IDE integrated terminals**: TerminalVisibilityDetector returns `false` (never suppresses) because there's no reliable way to query IDE tab state.
- **Screen and old tmux**: Treated as non-GUI apps; TerminalActivator falls back to terminal scanning and app activation.
- **Binary search**: When both bundle ID and TERM_PROGRAM are unavailable, the code scans running applications to find a matching terminal.

### Process Binary Finding

All CLI-based jumps (WezTerm, kitty, tmux) use `findBinary()` to locate executables in standard Homebrew and system paths:

```
/opt/homebrew/bin/{name}    # Apple Silicon Homebrew
/usr/local/bin/{name}       # Intel Homebrew or legacy
/usr/bin/{name}             # System
```

---

## Testing Terminal Jumping

### Manual Testing

1. Open a terminal (iTerm2, Ghostty, Terminal.app, etc.)
2. Start a Claude Code session: `cd /project && claude`
3. Click the session notification or session card in Notch
4. Verify the correct terminal window/tab/pane activates

### Debugging

Enable logging:

```bash
CODEISLAND_DEBUG=1 codeisland-bridge ...
```

Log output appears in `/tmp/codeisland-bridge.log`.
