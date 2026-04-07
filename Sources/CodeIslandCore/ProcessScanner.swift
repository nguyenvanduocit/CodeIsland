import Foundation
import Darwin

// MARK: - Process Info (testable abstraction)

public struct ProcessInfo2 {
    public let pid: pid_t
    public let executablePath: String
    public let args: [String]

    public init(pid: pid_t, executablePath: String, args: [String]) {
        self.pid = pid
        self.executablePath = executablePath
        self.args = args
    }
}

// MARK: - Claude Code Detection (pure logic, no syscalls)

/// Markers that identify a Claude Code process regardless of install method.
public enum ClaudeProcessMatcher {
    /// Official bundled binary: executable lives under ~/.local/share/claude/versions/
    public static func matchesBundledBinary(_ executablePath: String, home: String) -> Bool {
        let versionsDir = "\(home)/.local/share/claude/versions/"
        return executablePath.hasPrefix(versionsDir)
    }

    /// npm/vite-plus/local install: node running claude-code/cli.js
    public static func matchesNodeScript(_ args: [String]) -> Bool {
        return args.contains { arg in
            arg.hasSuffix("claude-code/cli.js") || arg.hasSuffix("claude-code/cli.mjs")
        }
    }

    /// Local install: ~/.claude/local/node_modules/.bin/claude
    public static func matchesLocalInstall(_ executablePath: String, home: String) -> Bool {
        return executablePath.hasPrefix("\(home)/.claude/local/")
    }

    /// Combined check: is this process a Claude Code instance?
    public static func isClaudeCode(_ process: ProcessInfo2, home: String) -> Bool {
        return matchesBundledBinary(process.executablePath, home: home)
            || matchesNodeScript(process.args)
            || matchesLocalInstall(process.executablePath, home: home)
    }

    /// Walk up process tree to find the Claude Code ancestor (for bridge PID resolution).
    /// Returns the PID of the first ancestor that is a Claude Code process.
    public static func findCLIAncestorPid(
        startPid: pid_t,
        home: String,
        getParentPid: (pid_t) -> pid_t?,
        getExecPath: (pid_t) -> String?,
        getArgs: (pid_t) -> [String]?
    ) -> pid_t? {
        var pid = startPid
        for _ in 0..<5 {
            guard pid > 1 else { break }
            let execPath = getExecPath(pid) ?? ""
            let args = getArgs(pid) ?? []
            let info = ProcessInfo2(pid: pid, executablePath: execPath, args: args)
            if isClaudeCode(info, home: home) { return pid }
            guard let parentPid = getParentPid(pid) else { break }
            pid = parentPid
        }
        return nil
    }
}

// MARK: - System-level process scanning (macOS)

public enum ProcessScanner {
    /// List all running PIDs on the system.
    public static func listAllPids() -> [pid_t] {
        var bufferSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bufferSize > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(bufferSize) / MemoryLayout<pid_t>.size + 10)
        bufferSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, bufferSize)
        let count = Int(bufferSize) / MemoryLayout<pid_t>.size
        return Array(pids.prefix(count).filter { $0 > 0 })
    }

    /// Get executable path for a PID.
    public static func executablePath(for pid: pid_t) -> String? {
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let len = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        guard len > 0 else { return nil }
        return String(cString: pathBuffer)
    }

    /// Get command-line arguments for a PID via sysctl KERN_PROCARGS2.
    public static func processArgs(for pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, Int32(pid)]
        var size: Int = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size >= 4 else { return nil }

        // First 4 bytes = argc
        let argc: Int32 = buffer.withUnsafeBytes { $0.load(as: Int32.self) }

        // Skip argc (4 bytes), then exec path (null-terminated), then padding nulls
        var pos = 4
        while pos < size && buffer[pos] != 0 { pos += 1 }  // skip exec path
        while pos < size && buffer[pos] == 0 { pos += 1 }   // skip padding

        // Read argc null-terminated strings
        var args: [String] = []
        for _ in 0..<argc {
            guard pos < size else { break }
            var end = pos
            while end < size && buffer[end] != 0 { end += 1 }
            if let str = String(bytes: buffer[pos..<end], encoding: .utf8) {
                args.append(str)
            }
            pos = end + 1
        }
        return args.isEmpty ? nil : args
    }

    /// Get parent PID for a process.
    public static func parentPid(for pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let ret = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        guard ret > 0 else { return nil }
        let ppid = pid_t(info.pbi_ppid)
        return ppid > 0 ? ppid : nil
    }

    /// Get CWD for a process.
    public static func cwd(for pid: pid_t) -> String? {
        var pathInfo = proc_vnodepathinfo()
        let ret = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &pathInfo, Int32(MemoryLayout<proc_vnodepathinfo>.size))
        guard ret > 0 else { return nil }
        return withUnsafePointer(to: pathInfo.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                String(cString: $0)
            }
        }
    }

    /// Get process start time.
    public static func startTime(for pid: pid_t) -> Date? {
        var info = proc_bsdinfo()
        let ret = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        guard ret > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec))
    }

    /// Find all running Claude Code PIDs.
    public static func findClaudePids() -> [pid_t] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var result: [pid_t] = []

        for pid in listAllPids() {
            guard let execPath = executablePath(for: pid) else { continue }

            // Fast path: bundled binary (no need to read args)
            if ClaudeProcessMatcher.matchesBundledBinary(execPath, home: home)
                || ClaudeProcessMatcher.matchesLocalInstall(execPath, home: home) {
                result.append(pid)
                continue
            }

            // Slow path: node process — check args for claude-code/cli.js
            let execName = (execPath as NSString).lastPathComponent
            if execName == "node" || execName == "bun" {
                if let args = processArgs(for: pid),
                   ClaudeProcessMatcher.matchesNodeScript(args) {
                    result.append(pid)
                }
            }
        }
        return result
    }

    /// Find the Claude Code ancestor PID from a given starting PID (for bridge).
    public static func findCLIAncestorPid(from startPid: pid_t) -> pid_t? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ClaudeProcessMatcher.findCLIAncestorPid(
            startPid: startPid,
            home: home,
            getParentPid: { parentPid(for: $0) },
            getExecPath: { executablePath(for: $0) },
            getArgs: { processArgs(for: $0) }
        )
    }
}
