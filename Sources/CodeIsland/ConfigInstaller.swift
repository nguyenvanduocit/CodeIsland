import Foundation

// MARK: - Hook Identifiers

private enum HookId {
    static let current = "codeisland"
    static let legacy = "vibenotch"
    static func isOurs(_ s: String) -> Bool {
        s.contains(current) || s.contains(legacy)
    }
}

// MARK: - CLI Definitions

/// A CLI tool that supports hooks
struct CLIConfig {
    let name: String           // display name
    let source: String         // --source flag value
    let configPath: String     // path to config file (relative to home)
    let configKey: String      // top-level JSON key containing hooks ("hooks" for most)
    let events: [(String, Int, Bool)]  // (eventName, timeout, async)
    /// Events that require a minimum CLI version (eventName → minVersion like "2.1.89")
    var versionedEvents: [String: String] = [:]

    var fullPath: String { NSHomeDirectory() + "/\(configPath)" }
    var dirPath: String { (fullPath as NSString).deletingLastPathComponent }
}

struct ConfigInstaller {
    private static let bridgePath = NSHomeDirectory() + "/.claude/hooks/codeisland-bridge"
    private static let hookScriptPath = NSHomeDirectory() + "/.claude/hooks/codeisland-hook.sh"
    private static let hookCommand = "~/.claude/hooks/codeisland-hook.sh"

    // MARK: - All supported CLIs

    static let allCLIs: [CLIConfig] = [
        // Claude Code — uses hook script (with bridge dispatcher + nc fallback)
        CLIConfig(
            name: "Claude Code", source: "claude",
            configPath: ".claude/settings.json", configKey: "hooks",
            events: [
                ("UserPromptSubmit", 5, true),
                ("PreToolUse", 5, false),
                ("PostToolUse", 5, true),
                ("PostToolUseFailure", 5, true),
                ("PermissionRequest", 86400, false),
                ("PermissionDenied", 5, true),
                ("Stop", 5, true),
                ("SubagentStart", 5, true),
                ("SubagentStop", 5, true),
                ("SessionStart", 5, false),
                ("SessionEnd", 5, true),
                ("Notification", 86400, false),
                ("PreCompact", 5, true),
            ],
            versionedEvents: [
                "PermissionDenied": "2.1.89",
                "PostToolUseFailure": "2.1.89",
            ]
        ),
    ]

    /// Hook script version — bump this when the script template changes
    private static let hookScriptVersion = 3

    /// Hook script for Claude Code (dispatcher: bridge binary → nc fallback)
    private static let hookScript = """
        #!/bin/bash
        # CodeIsland hook v\(hookScriptVersion) — native bridge with shell fallback
        BRIDGE="$HOME/.claude/hooks/codeisland-bridge"
        if [ -x "$BRIDGE" ]; then
          "$BRIDGE" "$@"
          exit $?
        fi
        # Fallback: original shell approach (no binary installed yet)
        SOCK="/tmp/codeisland-$(id -u).sock"
        [ -S "$SOCK" ] || exit 0
        INPUT=$(cat)
        _ITERM_GUID="${ITERM_SESSION_ID##*:}"
        TERM_INFO="\\"_term_app\\":\\"${TERM_PROGRAM:-}\\",\\"_iterm_session\\":\\"${_ITERM_GUID:-}\\",\\"_tty\\":\\"$(tty 2>/dev/null || true)\\",\\"_ppid\\":$PPID"
        PATCHED="${INPUT%\\}},${TERM_INFO}}"
        if echo "$INPUT" | grep -q '"PermissionRequest"'; then
          echo "$PATCHED" | nc -U -w 120 "$SOCK" 2>/dev/null || true
        else
          echo "$PATCHED" | nc -U -w 2 "$SOCK" 2>/dev/null || true
        fi
        """

    // MARK: - Install / Uninstall

    static func install() -> Bool {
        let fm = FileManager.default

        // Ensure hooks directory
        let hookDir = (hookScriptPath as NSString).deletingLastPathComponent
        try? fm.createDirectory(atPath: hookDir, withIntermediateDirectories: true)

        // Install hook script + bridge binary
        installHookScript(fm: fm)
        installBridgeBinary(fm: fm)

        // Install hooks for Claude Code
        let cli = allCLIs[0]
        guard isEnabled(source: cli.source) else { return true }
        return installClaudeHooks(cli: cli, fm: fm)
    }

    static func uninstall() {
        let fm = FileManager.default
        try? fm.removeItem(atPath: hookScriptPath)
        try? fm.removeItem(atPath: bridgePath)
        uninstallHooks(cli: allCLIs[0], fm: fm)
    }

    /// Check if Claude Code hooks are installed
    static func isInstalled() -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: hookScriptPath) else { return false }
        return isHooksInstalled(for: allCLIs[0], fm: fm)
    }

    /// Check if a specific CLI's hooks are installed
    static func isInstalled(source: String) -> Bool {
        guard let cli = allCLIs.first(where: { $0.source == source }) else { return false }
        return isHooksInstalled(for: cli, fm: FileManager.default)
    }

    /// Check if CLI directory exists (tool is installed on this machine)
    static func cliExists(source: String) -> Bool {
        guard let cli = allCLIs.first(where: { $0.source == source }) else { return false }
        return FileManager.default.fileExists(atPath: cli.dirPath)
    }

    /// Whether a CLI is enabled by user (UserDefaults). Default: true.
    static func isEnabled(source: String) -> Bool {
        let key = "cli_enabled_\(source)"
        if UserDefaults.standard.object(forKey: key) == nil { return true }
        return UserDefaults.standard.bool(forKey: key)
    }

    /// Toggle a single CLI on/off: installs or uninstalls its hooks.
    @discardableResult
    static func setEnabled(source: String, enabled: Bool) -> Bool {
        UserDefaults.standard.set(enabled, forKey: "cli_enabled_\(source)")
        let fm = FileManager.default
        if enabled {
            installHookScript(fm: fm)
            installBridgeBinary(fm: fm)
            guard let cli = allCLIs.first(where: { $0.source == source }) else { return false }
            return installClaudeHooks(cli: cli, fm: fm)
        } else {
            if let cli = allCLIs.first(where: { $0.source == source }) {
                uninstallHooks(cli: cli, fm: fm)
            }
            return true
        }
    }

    /// Check all installed CLIs and repair missing hooks. Returns names of repaired CLIs.
    static func verifyAndRepair() -> [String] {
        let fm = FileManager.default
        // Ensure bridge binary and hook script are current
        installBridgeBinary(fm: fm)
        installHookScript(fm: fm)

        var repaired: [String] = []
        let cli = allCLIs[0]
        guard isEnabled(source: cli.source) else { return repaired }
        guard fm.fileExists(atPath: cli.dirPath) else { return repaired }
        if !isHooksInstalled(for: cli, fm: fm) {
            if installClaudeHooks(cli: cli, fm: fm) {
                repaired.append(cli.name)
            }
        }
        return repaired
    }

    // MARK: - JSONC Support

    /// Strip // and /* */ comments from JSONC, preserving strings
    static func stripJSONComments(_ input: String) -> String {
        var result = ""
        result.reserveCapacity(input.count)
        var i = input.startIndex
        let end = input.endIndex

        while i < end {
            let c = input[i]
            if c == "\"" {
                result.append(c)
                i = input.index(after: i)
                while i < end {
                    let sc = input[i]
                    result.append(sc)
                    if sc == "\\" {
                        i = input.index(after: i)
                        if i < end { result.append(input[i]) }
                    } else if sc == "\"" {
                        break
                    }
                    i = input.index(after: i)
                }
                if i < end { i = input.index(after: i) }
                continue
            }
            let next = input.index(after: i)
            if c == "/" && next < end {
                let nc = input[next]
                if nc == "/" {
                    i = input.index(after: next)
                    while i < end && input[i] != "\n" { i = input.index(after: i) }
                    continue
                } else if nc == "*" {
                    i = input.index(after: next)
                    while i < end {
                        let bi = input.index(after: i)
                        if input[i] == "*" && bi < end && input[bi] == "/" {
                            i = input.index(after: bi)
                            break
                        }
                        i = input.index(after: i)
                    }
                    continue
                }
            }
            result.append(c)
            i = input.index(after: i)
        }
        return result
    }

    /// Parse a JSON file, stripping JSONC comments first
    private static func parseJSONFile(at path: String, fm: FileManager) -> [String: Any]? {
        guard fm.fileExists(atPath: path),
              let data = fm.contents(atPath: path),
              let str = String(data: data, encoding: .utf8) else { return nil }
        let stripped = stripJSONComments(str)
        guard let strippedData = stripped.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: strippedData) as? [String: Any] else { return nil }
        return json
    }

    // MARK: - CLI Version Detection

    /// Detect installed Claude Code version by running `claude --version`
    private static var cachedClaudeVersion: String?
    private static func detectClaudeVersion() -> String? {
        if let cached = cachedClaudeVersion { return cached }
        let candidates = [
            NSHomeDirectory() + "/.local/bin/claude",
            "/usr/local/bin/claude",
        ]
        guard let claudePath = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return nil
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: claudePath)
        proc.arguments = ["--version"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                // Parse "2.1.92 (Claude Code)" → "2.1.92"
                let version = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    .components(separatedBy: " ").first ?? ""
                if !version.isEmpty { cachedClaudeVersion = version }
                return cachedClaudeVersion
            }
        } catch {}
        return nil
    }

    /// Compare semver strings: returns true if `installed` >= `required`
    static func versionAtLeast(_ installed: String, _ required: String) -> Bool {
        let i = installed.split(separator: ".").compactMap { Int($0) }
        let r = required.split(separator: ".").compactMap { Int($0) }
        for idx in 0..<max(i.count, r.count) {
            let iv = idx < i.count ? i[idx] : 0
            let rv = idx < r.count ? r[idx] : 0
            if iv > rv { return true }
            if iv < rv { return false }
        }
        return true // equal
    }

    /// Filter events based on installed CLI version
    private static func compatibleEvents(for cli: CLIConfig) -> [(String, Int, Bool)] {
        guard !cli.versionedEvents.isEmpty else { return cli.events }
        let version = detectClaudeVersion()
        return cli.events.filter { (event, _, _) in
            guard let minVer = cli.versionedEvents[event] else { return true }
            guard let version else { return false } // can't detect version → skip risky events
            return versionAtLeast(version, minVer)
        }
    }

    // MARK: - Claude Code (uses hook script)

    private static func installClaudeHooks(cli: CLIConfig, fm: FileManager) -> Bool {
        let dir = cli.dirPath
        if !fm.fileExists(atPath: dir) {
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        var settings: [String: Any] = [:]
        if let json = parseJSONFile(at: cli.fullPath, fm: fm) {
            settings = json
        }

        var hooks = settings[cli.configKey] as? [String: Any] ?? [:]
        let events = compatibleEvents(for: cli)

        let alreadyInstalled = events.allSatisfy { (event, _, _) in
            guard let entries = hooks[event] as? [[String: Any]] else { return false }
            return entries.contains { entry in
                guard let hookList = entry["hooks"] as? [[String: Any]] else { return false }
                return hookList.contains { ($0["command"] as? String) == hookCommand }
            }
        }
        if alreadyInstalled && !hasStaleAsyncKey(hooks) { return true }

        // Remove all our hooks first (including any versioned events from a previous install)
        for key in hooks.keys {
            if var entries = hooks[key] as? [[String: Any]] {
                entries.removeAll { containsOurHook($0) }
                hooks[key] = entries.isEmpty ? nil : entries
            }
        }

        // Re-install only compatible events
        for (event, timeout, _) in events {
            var eventHooks = hooks[event] as? [[String: Any]] ?? []
            let hookEntry: [String: Any] = [
                "type": "command", "command": hookCommand, "timeout": timeout,
            ]
            eventHooks.append(["matcher": "", "hooks": [hookEntry]])
            hooks[event] = eventHooks
        }
        settings[cli.configKey] = hooks

        guard let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) else {
            return false
        }
        return fm.createFile(atPath: cli.fullPath, contents: data)
    }

    // MARK: - Uninstall (generic)

    private static func uninstallHooks(cli: CLIConfig, fm: FileManager) {
        guard var root = parseJSONFile(at: cli.fullPath, fm: fm),
              var hooks = root[cli.configKey] as? [String: Any] else { return }

        for (event, value) in hooks {
            guard var entries = value as? [[String: Any]] else { continue }
            entries.removeAll { containsOurHook($0) }
            if entries.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = entries
            }
        }

        root[cli.configKey] = hooks.isEmpty ? nil : hooks
        if let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) {
            fm.createFile(atPath: cli.fullPath, contents: data)
        }
    }

    // MARK: - Detection helpers

    private static func isHooksInstalled(for cli: CLIConfig, fm: FileManager) -> Bool {
        guard let root = parseJSONFile(at: cli.fullPath, fm: fm),
              let hooks = root[cli.configKey] as? [String: Any] else { return false }
        // Check that ALL compatible events have our hook installed, not just any one
        let events = compatibleEvents(for: cli)
        let allPresent = events.allSatisfy { (event, _, _) in
            guard let entries = hooks[event] as? [[String: Any]] else { return false }
            return entries.contains { containsOurHook($0) }
        }
        guard allPresent else { return false }
        // Also check for stale "async" keys that need cleanup
        if hasStaleAsyncKey(hooks) { return false }
        return true
    }

    /// Detect legacy hook entries with invalid "async" key
    private static func hasStaleAsyncKey(_ hooks: [String: Any]) -> Bool {
        for (_, value) in hooks {
            guard let entries = value as? [[String: Any]] else { continue }
            for entry in entries where containsOurHook(entry) {
                if let hookList = entry["hooks"] as? [[String: Any]] {
                    if hookList.contains(where: { $0["async"] != nil }) { return true }
                }
            }
        }
        return false
    }

    /// Check if a hook entry contains our hook command
    private static func containsOurHook(_ entry: [String: Any]) -> Bool {
        // Claude format: entry.hooks[].command
        if let hookList = entry["hooks"] as? [[String: Any]] {
            return hookList.contains {
                let cmd = $0["command"] as? String ?? ""
                return HookId.isOurs(cmd)
            }
        }
        // Flat format: entry.command
        if let cmd = entry["command"] as? String, HookId.isOurs(cmd) { return true }
        return false
    }

    // MARK: - Bridge & Hook Script

    private static func installHookScript(fm: FileManager) {
        let needsUpdate: Bool
        if fm.fileExists(atPath: hookScriptPath) {
            if let existing = fm.contents(atPath: hookScriptPath),
               let str = String(data: existing, encoding: .utf8) {
                // Update if script doesn't contain bridge dispatcher OR version is outdated
                let hasCurrentVersion = str.contains("# CodeIsland hook v\(hookScriptVersion)")
                needsUpdate = !hasCurrentVersion
            } else {
                needsUpdate = true
            }
        } else {
            needsUpdate = true
        }
        if needsUpdate {
            fm.createFile(atPath: hookScriptPath, contents: Data(hookScript.utf8))
            chmod(hookScriptPath, 0o755)
        }
    }

    private static func installBridgeBinary(fm: FileManager) {
        guard let execPath = Bundle.main.executablePath else { return }
        let execDir = (execPath as NSString).deletingLastPathComponent
        let contentsDir = (execDir as NSString).deletingLastPathComponent
        var srcPath = contentsDir + "/Helpers/codeisland-bridge"
        if !fm.fileExists(atPath: srcPath) { srcPath = execDir + "/codeisland-bridge" }
        guard fm.fileExists(atPath: srcPath) else { return }

        // Atomic replace: copy to temp file first, then rename (overwrites atomically)
        let tmpPath = bridgePath + ".tmp.\(ProcessInfo.processInfo.processIdentifier)"
        do {
            try? fm.removeItem(atPath: tmpPath)
            try fm.copyItem(atPath: srcPath, toPath: tmpPath)
            chmod(tmpPath, 0o755)
            // Strip quarantine xattr so Gatekeeper won't block the binary
            stripQuarantine(tmpPath)
            _ = try fm.replaceItemAt(URL(fileURLWithPath: bridgePath), withItemAt: URL(fileURLWithPath: tmpPath))
        } catch {
            // replaceItemAt fails if destination doesn't exist yet — fall back to rename
            try? fm.moveItem(atPath: tmpPath, toPath: bridgePath)
            chmod(bridgePath, 0o755)
        }
        // Ensure final binary is free of quarantine (covers both paths above)
        stripQuarantine(bridgePath)
    }

    /// Remove com.apple.quarantine xattr so Gatekeeper won't block the binary.
    /// Copied binaries inherit quarantine from the source app bundle.
    private static func stripQuarantine(_ path: String) {
        removexattr(path, "com.apple.quarantine", 0)
    }
}
