import AppKit
import CodeIslandCore

/// Detects whether a session's terminal tab/pane is currently the active (visible) one.
/// Used by smart-suppress to avoid notifying when the user is already looking at the session.
///
/// Two detection levels:
/// - **App-level** (`isTerminalFrontmostForSession`): fast, main-thread safe, checks if the
///   terminal app is the frontmost application. No AppleScript or subprocess calls.
/// - **Tab-level** (`isSessionTabVisible`): precise, checks the specific tab/session/pane.
///   Uses AppleScript or CLI calls that may block 50-200ms. Call from background thread only.
///
/// Supported tab-level detection:
/// - Ghostty: CWD match via System Events window title
/// - tmux: active pane match (works inside any terminal, including Ghostty)
/// - Others: falls back to app-level only
struct TerminalVisibilityDetector {

    // MARK: - App-level check (main-thread safe, no blocking)

    /// Fast check: is the session's terminal app the frontmost application?
    /// Safe to call from the main thread — no AppleScript or subprocess calls.
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

    // MARK: - Tab-level check (background thread only)

    /// Full check: is the session's specific tab/pane currently visible?
    /// **Call from a background thread only** — AppleScript/CLI calls may block 50-200ms.
    ///
    /// Supports Ghostty (CWD match) and tmux (active pane match).
    /// Unknown terminals return `true` — app-level is the best we can do.
    static func isSessionTabVisible(_ session: SessionSnapshot) -> Bool {
        // Fast path: terminal not even frontmost
        guard isTerminalFrontmostForSession(session) else { return false }

        // IDE integrated terminals: can't query tab state, assume NOT visible
        // (show notification — safer than suppressing when user may be editing code)
        if session.isIDETerminal {
            return false
        }

        // tmux takes priority: if session runs in a tmux pane, check that pane
        // regardless of which terminal app wraps tmux
        if let pane = session.tmuxPane, !pane.isEmpty {
            return isTmuxPaneActive(pane)
        }

        guard let termApp = session.termApp else { return true }
        let term = termApp.lowercased()
            .replacingOccurrences(of: ".app", with: "")
            .replacingOccurrences(of: "apple_", with: "")

        if term == "ghostty" {
            return isGhosttyTabActive(session)
        }

        // Unknown terminal — app-level is the best we can do
        return true
    }

    // MARK: - Ghostty

    /// Check if Ghostty's front window matches this session's CWD.
    /// Uses System Events to read the front window title (Ghostty's native scripting
    /// doesn't expose a "focused terminal" property).
    private static func isGhosttyTabActive(_ session: SessionSnapshot) -> Bool {
        guard let cwd = session.cwd, !cwd.isEmpty else { return true }
        let dirName = escapeAppleScript((cwd as NSString).lastPathComponent)
        let script = """
        tell application "System Events"
            tell process "Ghostty"
                try
                    set winTitle to name of front window
                    if winTitle contains "\(dirName)" then return "true"
                end try
            end tell
        end tell
        return "false"
        """
        return runAppleScriptSync(script)?.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    // MARK: - tmux

    /// Check if the tmux pane is the currently active one.
    private static func isTmuxPaneActive(_ pane: String) -> Bool {
        guard let bin = findBinary("tmux") else { return true }

        // Get the currently active pane
        guard let data = runProcess(bin, args: ["display-message", "-p", "#{session_name}:#{window_index}.#{pane_index}"]),
              let activePaneId = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !activePaneId.isEmpty else { return true }

        // The stored pane might be %N format; convert via list-panes
        guard let listData = runProcess(bin, args: ["list-panes", "-a", "-F", "#{pane_id} #{session_name}:#{window_index}.#{pane_index}"]),
              let listStr = String(data: listData, encoding: .utf8) else { return pane == activePaneId }

        for line in listStr.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1)
            if parts.count == 2, String(parts[0]) == pane {
                return String(parts[1]) == activePaneId
            }
        }

        return pane == activePaneId
    }

    // MARK: - Helpers

    private static func escapeAppleScript(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Run AppleScript synchronously and return the string result.
    private static func runAppleScriptSync(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        return result.stringValue
    }

    private static func findBinary(_ name: String) -> String? {
        let paths = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
        ]
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

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
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            return proc.terminationStatus == 0 ? data : nil
        } catch {
            return nil
        }
    }
}
