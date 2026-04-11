import AppKit
import CodeIslandCore
import os.log

private let log = Logger(subsystem: "com.codeisland", category: "TerminalActivator")

/// Activates the terminal window/tab running a specific Claude Code session.
/// Supports Ghostty only. Falls back to app-level activation for anything else.
struct TerminalActivator {

    private static let knownTerminals: [(name: String, bundleId: String)] = [
        ("Ghostty", "com.mitchellh.ghostty"),
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

        // --- tmux: switch pane first, then fall through to terminal activation ---
        if let pane = session.tmuxPane, !pane.isEmpty {
            activateTmux(pane: pane)
        }

        if termApp.lowercased() == "ghostty" {
            let displayId = session.displaySessionId(sessionId: sessionId ?? "")
            activateGhostty(cwd: session.cwd, sessionId: displayId, source: session.source)
        } else {
            bringToFront(termApp)
        }
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
        if termApp.lowercased() == "ghostty" { name = "Ghostty" }
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
        return "Ghostty"
    }

    /// Fork a session: open a new tab in Ghostty and run `claude --resume <id> --fork-session`
    static func forkSession(session: SessionSnapshot, sessionId: String) {
        let dir = session.cwd ?? FileManager.default.homeDirectoryForCurrentUser.path
        let command = "claude --resume \(sessionId) --fork-session"
        log.info("forkSession: sessionId=\(sessionId) cwd=\(dir) termApp=\(session.termApp ?? "nil") termBundle=\(session.termBundleId ?? "nil")")
        forkInGhostty(cwd: dir, command: command)
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
