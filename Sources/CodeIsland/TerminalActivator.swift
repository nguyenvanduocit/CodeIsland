import AppKit
import CodeIslandCore
import os.log

private let log = Logger(subsystem: "com.codeisland", category: "TerminalActivator")

/// Activates the terminal window/tab running a specific Claude Code session.
/// Supports tab-level switching for: Ghostty, iTerm2, Terminal.app, WezTerm, kitty.
/// Falls back to app-level activation for: Alacritty, Warp, Hyper, Tabby, Rio.
struct TerminalActivator {

    private static let knownTerminals: [(name: String, bundleId: String)] = [
        ("cmux", "com.cmuxterm.app"),
        ("Ghostty", "com.mitchellh.ghostty"),
        ("iTerm2", "com.googlecode.iterm2"),
        ("WezTerm", "com.github.wez.wezterm"),
        ("kitty", "net.kovidgoyal.kitty"),
        ("Alacritty", "org.alacritty"),
        ("Warp", "dev.warp.Warp-Stable"),
        ("Terminal", "com.apple.Terminal"),
    ]

    /// Fallback: source-based app jump for CLIs with NO terminal mode.
    /// Most sources should use nativeAppBundles instead (by bundle ID).
    private static let appSources: [String: String] = [:]

    /// Bundle IDs of apps that have native app modes.
    /// When termBundleId matches, bring that app to front;
    /// otherwise fall through to terminal tab-matching.
    private static let nativeAppBundles: [String: String] = [:]

    static func activate(session: SessionSnapshot, sessionId: String? = nil) {
        // Native app by bundle ID (e.g. Codex APP vs Codex CLI)
        if let bundleId = session.termBundleId,
           let appName = nativeAppBundles[bundleId] {
            if let app = NSWorkspace.shared.runningApplications.first(where: {
                $0.bundleIdentifier == bundleId
            }) {
                if app.isHidden { app.unhide() }
                app.activate()
            } else {
                bringToFront(appName)
            }
            return
        }

        // IDE integrated terminal: bring the IDE to front (no tab-level switching)
        if session.isIDETerminal,
           let bundleId = session.termBundleId {
            if let app = NSWorkspace.shared.runningApplications.first(where: {
                $0.bundleIdentifier == bundleId
            }) {
                if app.isHidden { app.unhide() }
                app.activate()
            }
            return
        }

        // IDE sources: just bring the app to front
        if let appName = appSources[session.source] {
            if let app = NSWorkspace.shared.runningApplications.first(where: {
                $0.localizedName == appName
            }) {
                if app.isHidden { app.unhide() }
                app.activate()
            } else {
                bringToFront(appName)
            }
            return
        }

        // Resolve terminal: bundle ID (most accurate) → TERM_PROGRAM → scan running apps
        let termApp: String
        if let bundleId = session.termBundleId,
           let resolved = knownTerminals.first(where: { $0.bundleId == bundleId })?.name {
            termApp = resolved
        } else {
            let raw = session.termApp ?? ""
            // "tmux" / "screen" etc. are not GUI apps — fall back to scanning
            if raw.isEmpty || raw.lowercased() == "tmux" || raw.lowercased() == "screen" {
                termApp = detectRunningTerminal()
            } else {
                termApp = raw
            }
        }
        let lower = termApp.lowercased()

        // --- tmux: switch pane first, then fall through to terminal-specific activation ---
        if let pane = session.tmuxPane, !pane.isEmpty {
            activateTmux(pane: pane)
        }

        // In tmux, use the client TTY (outer terminal) for tab matching,
        // since ttyPath is the inner tmux pty which won't match the terminal's tab.
        let inTmux = session.tmuxPane != nil && !(session.tmuxPane ?? "").isEmpty
        let effectiveTty = inTmux
            ? (session.tmuxClientTty ?? session.ttyPath)
            : session.ttyPath

        // --- Tab-level switching (5 terminals) ---

        if lower.contains("iterm") {
            if let itermId = session.itermSessionId, !itermId.isEmpty {
                activateITerm(sessionId: itermId)
            } else {
                bringToFront("iTerm2")
            }
            return
        }

        if lower == "ghostty" {
            let displayId = session.displaySessionId(sessionId: sessionId ?? "")
            activateGhostty(cwd: session.cwd, sessionId: displayId, source: session.source)
            return
        }

        if lower.contains("terminal") || lower.contains("apple_terminal") {
            activateTerminalApp(ttyPath: effectiveTty)
            return
        }

        if lower.contains("wezterm") || lower.contains("wez") {
            activateWezTerm(ttyPath: effectiveTty, cwd: session.cwd)
            return
        }

        if lower.contains("kitty") {
            activateKitty(windowId: session.kittyWindowId, cwd: session.cwd, source: session.source)
            return
        }

        // --- App-level only (Alacritty, Warp, Hyper, Tabby, Rio, etc.) ---
        bringToFront(termApp)
    }

    // MARK: - Ghostty (AppleScript: match by CWD + session ID in title)

    private static func activateGhostty(cwd: String?, sessionId: String? = nil, source: String = "claude") {
        // Ensure app is unhidden and brought to front (Space switching)
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.mitchellh.ghostty" }) {
            if app.isHidden { app.unhide() }
            app.activate()
        }
        guard let cwd = cwd, !cwd.isEmpty else { return }

        // Strategy 1: match by session ID in terminal title (most precise)
        let idMatch: String
        if let sid = sessionId, !sid.isEmpty {
            let escapedSid = escapeAppleScript(String(sid.prefix(8)))
            idMatch = """
                repeat with t in allTerms
                    if name of t contains "\(escapedSid)" then
                        focus t
                        return
                    end if
                end repeat
            """
        } else {
            idMatch = ""
        }

        // Strategy 2: match by CWD folder name in title
        let folderName = escapeAppleScript((cwd as NSString).lastPathComponent)
        // Strategy 3: exact working directory match
        let escapedCwd = escapeAppleScript(cwd)

        let script = """
        tell application "Ghostty"
            set allTerms to every terminal
            \(idMatch)
            repeat with t in allTerms
                if working directory of t is "\(escapedCwd)" then
                    focus t
                    return
                end if
            end repeat
            repeat with t in allTerms
                if name of t contains "\(folderName)" then
                    focus t
                    return
                end if
            end repeat
        end tell
        """
        runAppleScript(script)
    }

    // MARK: - iTerm2 (AppleScript: match by session ID)

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

    // MARK: - Terminal.app (AppleScript: match by TTY)

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

    // MARK: - WezTerm (CLI: wezterm cli list + activate-tab)

    private static func activateWezTerm(ttyPath: String?, cwd: String?) {
        bringToFront("WezTerm")
        guard let bin = findBinary("wezterm") else { return }
        Task.detached(priority: .userInitiated) {
            guard let json = runProcess(bin, args: ["cli", "list", "--format", "json"]),
                  let panes = try? JSONSerialization.jsonObject(with: json) as? [[String: Any]] else { return }

            // Find tab: prefer TTY match, fallback to CWD
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

    // MARK: - kitty (CLI: kitten @ focus-window/focus-tab)

    private static func activateKitty(windowId: String?, cwd: String?, source: String = "claude") {
        bringToFront("kitty")
        guard let bin = findBinary("kitten") else { return }

        // Prefer window ID for precise switching
        if let windowId = windowId, !windowId.isEmpty {
            Task.detached(priority: .userInitiated) {
                _ = runProcess(bin, args: ["@", "focus-window", "--match", "id:\(windowId)"])
            }
            return
        }

        // Fallback to CWD matching, then title with source keyword
        guard let cwd = cwd, !cwd.isEmpty else { return }
        Task.detached(priority: .userInitiated) {
            if runProcess(bin, args: ["@", "focus-tab", "--match", "cwd:\(cwd)"]) == nil {
                _ = runProcess(bin, args: ["@", "focus-tab", "--match", "title:\(source)"])
            }
        }
    }

    // MARK: - tmux (CLI: tmux select-window/select-pane)

    private static func activateTmux(pane: String) {
        guard let bin = findBinary("tmux") else { return }
        Task.detached(priority: .userInitiated) {
            // Switch to the window containing the pane, then select the pane
            _ = runProcess(bin, args: ["select-window", "-t", pane])
            _ = runProcess(bin, args: ["select-pane", "-t", pane])
        }
    }

    // MARK: - Generic (bring app to front)

    private static func bringToFront(_ termApp: String) {
        let name: String
        let lower = termApp.lowercased()
        if lower.contains("cmux") { name = "cmux" }
        else if lower == "ghostty" { name = "Ghostty" }
        else if lower.contains("iterm") { name = "iTerm2" }
        else if lower.contains("terminal") || lower.contains("apple_terminal") { name = "Terminal" }
        else if lower.contains("wezterm") || lower.contains("wez") { name = "WezTerm" }
        else if lower.contains("alacritty") || lower.contains("lacritty") { name = "Alacritty" }
        else if lower.contains("kitty") { name = "kitty" }
        else if lower.contains("warp") { name = "Warp" }
        else if lower.contains("hyper") { name = "Hyper" }
        else if lower.contains("tabby") { name = "Tabby" }
        else if lower.contains("rio") { name = "Rio" }
        else { name = termApp }

        // Try NSRunningApplication first — handles Space switching and unhide
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName == name || ($0.bundleIdentifier ?? "").localizedCaseInsensitiveContains(name)
        }) {
            if app.isHidden { app.unhide() }
            app.activate()
            return
        }
        // Fallback: open -a (app not running yet)
        Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            proc.arguments = ["-a", name]
            try? proc.run()
        }
    }

    // MARK: - Helpers

    private static func detectRunningTerminal() -> String {
        let running = NSWorkspace.shared.runningApplications
        for (name, bundleId) in knownTerminals {
            if running.contains(where: { $0.bundleIdentifier == bundleId }) {
                return name
            }
        }
        return "Terminal"
    }

    /// Fork a session: open a new tab in the session's terminal and run `claude --resume <id> --fork-session`
    static func forkSession(session: SessionSnapshot, sessionId: String) {
        let dir = session.cwd ?? FileManager.default.homeDirectoryForCurrentUser.path
        let command = "claude --resume \(sessionId) --fork-session"
        log.info("forkSession: sessionId=\(sessionId) cwd=\(dir) termApp=\(session.termApp ?? "nil") termBundle=\(session.termBundleId ?? "nil")")

        // Resolve terminal (same logic as activate)
        let termApp: String
        if let bundleId = session.termBundleId,
           let resolved = knownTerminals.first(where: { $0.bundleId == bundleId })?.name {
            termApp = resolved
        } else {
            let raw = session.termApp ?? ""
            if raw.isEmpty || raw.lowercased() == "tmux" || raw.lowercased() == "screen" {
                termApp = detectRunningTerminal()
            } else {
                termApp = raw
            }
        }
        let lower = termApp.lowercased()

        if lower.contains("iterm") {
            forkInITerm(cwd: dir, command: command)
        } else if lower == "ghostty" {
            forkInGhostty(cwd: dir, command: command)
        } else if lower.contains("terminal") || lower.contains("apple_terminal") {
            forkInTerminalApp(cwd: dir, command: command)
        } else if lower.contains("wezterm") || lower.contains("wez") {
            forkInWezTerm(cwd: dir, command: command)
        } else if lower.contains("kitty") {
            forkInKitty(cwd: dir, command: command)
        } else {
            // Fallback: Ghostty (our primary target)
            forkInGhostty(cwd: dir, command: command)
        }
    }

    private static func forkInGhostty(cwd: String, command: String) {
        let escapedCwd = escapeAppleScript(cwd)
        let escapedCmd = escapeAppleScript(command)
        let script = """
        tell application "Ghostty"
            activate
            set newTab to new tab in front window
            set t to focused terminal of newTab
            delay 0.2
            input text "cd \\"\(escapedCwd)\\" && \(escapedCmd)" to t
            send key "enter" to t
        end tell
        """
        runAppleScript(script)
    }

    private static func forkInITerm(cwd: String, command: String) {
        let escapedCwd = escapeAppleScript(cwd)
        let escapedCmd = escapeAppleScript(command)
        let script = """
        tell application "iTerm2"
            activate
            tell current window
                create tab with default profile
                tell current session
                    write text "cd \\"\(escapedCwd)\\" && \(escapedCmd)"
                end tell
            end tell
        end tell
        """
        runAppleScript(script)
    }

    private static func forkInTerminalApp(cwd: String, command: String) {
        let escapedCwd = escapeAppleScript(cwd)
        let escapedCmd = escapeAppleScript(command)
        let script = """
        tell application "Terminal"
            activate
            do script "cd \\"\(escapedCwd)\\" && \(escapedCmd)"
        end tell
        """
        runAppleScript(script)
    }

    private static func forkInWezTerm(cwd: String, command: String) {
        guard let bin = findBinary("wezterm") else { return }
        bringToFront("WezTerm")
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        Task.detached(priority: .userInitiated) {
            _ = runProcess(bin, args: ["cli", "spawn", "--cwd", cwd, "--", shell, "-ic", command])
        }
    }

    private static func forkInKitty(cwd: String, command: String) {
        guard let bin = findBinary("kitten") else { return }
        bringToFront("kitty")
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        Task.detached(priority: .userInitiated) {
            _ = runProcess(bin, args: ["@", "launch", "--type=tab", "--cwd", cwd, shell, "-ic", command])
        }
    }

    /// Check (and prompt) for Accessibility permission. Returns true if granted.
    @discardableResult
    static func ensureAccessibility() -> Bool {
        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        )
        if !trusted {
            log.warning("Accessibility permission not granted — prompting user")
        }
        return trusted
    }

    private static func runAppleScript(_ source: String) {
        Task.detached(priority: .userInitiated) {
            if let script = NSAppleScript(source: source) {
                var error: NSDictionary?
                script.executeAndReturnError(&error)
                if let error {
                    log.error("AppleScript error: \(error)")
                }
            } else {
                log.error("AppleScript failed to compile")
            }
        }
    }

    /// Escape special characters for AppleScript string interpolation
    private static func escapeAppleScript(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Find a CLI binary in common paths (Homebrew Intel + Apple Silicon, system)
    private static func findBinary(_ name: String) -> String? {
        let paths = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
        ]
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Run a process and return stdout. Returns nil on failure.
    @discardableResult
    private static func runProcess(_ path: String, args: [String]) -> Data? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            // Read BEFORE wait to avoid deadlock (pipe buffer full blocks the process)
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            return proc.terminationStatus == 0 ? data : nil
        } catch {
            return nil
        }
    }
}
