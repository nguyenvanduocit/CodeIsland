import XCTest
@testable import CodeIslandCore

final class ClaudeProcessMatcherTests: XCTestCase {
    let home = "/Users/testuser"

    // MARK: - matchesBundledBinary

    func testBundledBinaryOfficialInstall() {
        let path = "/Users/testuser/.local/share/claude/versions/2.1.62/node"
        XCTAssertTrue(ClaudeProcessMatcher.matchesBundledBinary(path, home: home))
    }

    func testBundledBinaryDifferentVersion() {
        let path = "/Users/testuser/.local/share/claude/versions/3.0.0/bin/claude"
        XCTAssertTrue(ClaudeProcessMatcher.matchesBundledBinary(path, home: home))
    }

    func testBundledBinaryWrongHome() {
        let path = "/Users/other/.local/share/claude/versions/2.1.62/node"
        XCTAssertFalse(ClaudeProcessMatcher.matchesBundledBinary(path, home: home))
    }

    func testBundledBinaryRandomPath() {
        let path = "/usr/local/bin/node"
        XCTAssertFalse(ClaudeProcessMatcher.matchesBundledBinary(path, home: home))
    }

    // MARK: - matchesNodeScript

    func testNodeScriptNpmInstall() {
        let args = [
            "/usr/local/bin/node",
            "/usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js",
            "--dangerously-skip-permissions",
        ]
        XCTAssertTrue(ClaudeProcessMatcher.matchesNodeScript(args))
    }

    func testNodeScriptVitePlusInstall() {
        let args = [
            "/Users/firegroup/.vite-plus/js_runtime/node/24.14.1/bin/node",
            "/Users/firegroup/.vite-plus/packages/@anthropic-ai/claude-code/lib/node_modules/@anthropic-ai/claude-code/cli.js",
            "--dangerously-skip-permissions",
        ]
        XCTAssertTrue(ClaudeProcessMatcher.matchesNodeScript(args))
    }

    func testNodeScriptMjsExtension() {
        let args = ["/usr/bin/node", "/some/path/claude-code/cli.mjs"]
        XCTAssertTrue(ClaudeProcessMatcher.matchesNodeScript(args))
    }

    func testNodeScriptUnrelatedProcess() {
        let args = ["/usr/bin/node", "/some/app/server.js"]
        XCTAssertFalse(ClaudeProcessMatcher.matchesNodeScript(args))
    }

    func testNodeScriptEmpty() {
        XCTAssertFalse(ClaudeProcessMatcher.matchesNodeScript([]))
    }

    func testNodeScriptPartialMatch() {
        // "claude-code" in path but not cli.js
        let args = ["/usr/bin/node", "/some/claude-code/other.js"]
        XCTAssertFalse(ClaudeProcessMatcher.matchesNodeScript(args))
    }

    // MARK: - matchesLocalInstall

    func testLocalInstall() {
        let path = "/Users/testuser/.claude/local/node_modules/.bin/claude"
        XCTAssertTrue(ClaudeProcessMatcher.matchesLocalInstall(path, home: home))
    }

    func testLocalInstallWrongHome() {
        let path = "/Users/other/.claude/local/node_modules/.bin/claude"
        XCTAssertFalse(ClaudeProcessMatcher.matchesLocalInstall(path, home: home))
    }

    // MARK: - isClaudeCode (combined)

    func testIsClaudeCodeBundled() {
        let proc = ProcessInfo2(
            pid: 100,
            executablePath: "/Users/testuser/.local/share/claude/versions/2.1.62/node",
            args: ["/Users/testuser/.local/share/claude/versions/2.1.62/node"]
        )
        XCTAssertTrue(ClaudeProcessMatcher.isClaudeCode(proc, home: home))
    }

    func testIsClaudeCodeNodeNpm() {
        let proc = ProcessInfo2(
            pid: 200,
            executablePath: "/usr/local/bin/node",
            args: [
                "/usr/local/bin/node",
                "/usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js",
            ]
        )
        XCTAssertTrue(ClaudeProcessMatcher.isClaudeCode(proc, home: home))
    }

    func testIsClaudeCodeNodeVitePlus() {
        let proc = ProcessInfo2(
            pid: 300,
            executablePath: "/Users/firegroup/.vite-plus/js_runtime/node/24.14.1/bin/node",
            args: [
                "/Users/firegroup/.vite-plus/js_runtime/node/24.14.1/bin/node",
                "/Users/firegroup/.vite-plus/packages/@anthropic-ai/claude-code/lib/node_modules/@anthropic-ai/claude-code/cli.js",
                "--dangerously-skip-permissions",
            ]
        )
        XCTAssertTrue(ClaudeProcessMatcher.isClaudeCode(proc, home: home))
    }

    func testIsClaudeCodeRandomNode() {
        let proc = ProcessInfo2(
            pid: 400,
            executablePath: "/usr/local/bin/node",
            args: ["/usr/local/bin/node", "/app/server.js"]
        )
        XCTAssertFalse(ClaudeProcessMatcher.isClaudeCode(proc, home: home))
    }

    func testIsClaudeCodeBunInstall() {
        let proc = ProcessInfo2(
            pid: 500,
            executablePath: "/opt/homebrew/bin/bun",
            args: [
                "/opt/homebrew/bin/bun",
                "/Users/testuser/.bun/install/global/node_modules/@anthropic-ai/claude-code/cli.js",
            ]
        )
        XCTAssertTrue(ClaudeProcessMatcher.isClaudeCode(proc, home: home))
    }

    // MARK: - findCLIAncestorPid (pure logic)

    func testFindCLIAncestorPidDirectParent() {
        // bridge(pid=300) -> bash(pid=200) -> claude(pid=100)
        let tree: [pid_t: (parent: pid_t, exec: String, args: [String])] = [
            300: (200, "/bin/bash", ["/bin/bash", "hook.sh"]),
            200: (100, "/bin/bash", ["/bin/bash", "hook.sh"]),
            100: (2, "/usr/bin/node", ["/usr/bin/node", "/path/claude-code/cli.js"]),
        ]

        let result = ClaudeProcessMatcher.findCLIAncestorPid(
            startPid: 200,
            home: "/Users/test",
            getParentPid: { tree[$0]?.parent },
            getExecPath: { tree[$0]?.exec },
            getArgs: { tree[$0]?.args }
        )
        XCTAssertEqual(result, 100)
    }

    func testFindCLIAncestorPidBundledBinary() {
        let tree: [pid_t: (parent: pid_t, exec: String, args: [String])] = [
            300: (200, "/bin/bash", []),
            200: (50, "/Users/test/.local/share/claude/versions/2.1/node", []),
        ]

        let result = ClaudeProcessMatcher.findCLIAncestorPid(
            startPid: 200,
            home: "/Users/test",
            getParentPid: { tree[$0]?.parent },
            getExecPath: { tree[$0]?.exec },
            getArgs: { tree[$0]?.args }
        )
        XCTAssertEqual(result, 200)
    }

    func testFindCLIAncestorPidNotFound() {
        let tree: [pid_t: (parent: pid_t, exec: String, args: [String])] = [
            300: (200, "/bin/bash", []),
            200: (100, "/bin/bash", []),
            100: (2, "/sbin/launchd", []),
        ]

        let result = ClaudeProcessMatcher.findCLIAncestorPid(
            startPid: 300,
            home: "/Users/test",
            getParentPid: { tree[$0]?.parent },
            getExecPath: { tree[$0]?.exec },
            getArgs: { tree[$0]?.args }
        )
        XCTAssertNil(result)
    }

    func testFindCLIAncestorPidWithShellIntermediate() {
        // bridge(500) -> bash(400) -> sh -c(300) -> node claude(200)
        let tree: [pid_t: (parent: pid_t, exec: String, args: [String])] = [
            500: (400, "/path/bridge", []),
            400: (300, "/bin/bash", []),
            300: (200, "/bin/sh", ["/bin/sh", "-c", "hook.sh"]),
            200: (50, "/usr/bin/node", ["/usr/bin/node", "/npm/lib/@anthropic-ai/claude-code/cli.js"]),
        ]

        let result = ClaudeProcessMatcher.findCLIAncestorPid(
            startPid: 400,
            home: "/Users/test",
            getParentPid: { tree[$0]?.parent },
            getExecPath: { tree[$0]?.exec },
            getArgs: { tree[$0]?.args }
        )
        XCTAssertEqual(result, 200)
    }
}

// MARK: - Live System Tests (verify actual process scanning works)

final class ProcessScannerLiveTests: XCTestCase {
    func testListAllPidsReturnsNonEmpty() {
        let pids = ProcessScanner.listAllPids()
        XCTAssertFalse(pids.isEmpty, "Should find at least some running processes")
        XCTAssertTrue(pids.count > 10, "macOS typically has many processes")
    }

    func testCanReadOwnExecutablePath() {
        let pid = getpid()
        let path = ProcessScanner.executablePath(for: pid)
        XCTAssertNotNil(path)
        // We're running as xctest
        XCTAssertTrue(path!.contains("xctest") || path!.contains("swift"), "Should be test runner: \(path!)")
    }

    func testCanReadOwnArgs() {
        let pid = getpid()
        let args = ProcessScanner.processArgs(for: pid)
        XCTAssertNotNil(args)
        XCTAssertFalse(args!.isEmpty)
    }

    func testCanReadOwnCwd() {
        let pid = getpid()
        let cwd = ProcessScanner.cwd(for: pid)
        XCTAssertNotNil(cwd)
    }

    func testCanReadOwnParentPid() {
        let pid = getpid()
        let ppid = ProcessScanner.parentPid(for: pid)
        XCTAssertNotNil(ppid)
        XCTAssertTrue(ppid! > 0)
    }

    func testInvalidPidReturnsNil() {
        let fakePid: pid_t = 999999
        XCTAssertNil(ProcessScanner.executablePath(for: fakePid))
        XCTAssertNil(ProcessScanner.processArgs(for: fakePid))
        XCTAssertNil(ProcessScanner.cwd(for: fakePid))
        XCTAssertNil(ProcessScanner.parentPid(for: fakePid))
    }

    /// Verify findClaudePids actually detects running Claude Code sessions.
    /// This test only passes when Claude Code is running (i.e., when run FROM Claude Code).
    func testFindClaudePidsDetectsRunningClaudeProcesses() {
        let pids = ProcessScanner.findClaudePids()
        // We are running inside Claude Code, so at least one process should be found
        XCTAssertFalse(pids.isEmpty, "Should detect at least one Claude Code process (we're running inside one)")

        // Each found PID should have a valid CWD
        for pid in pids {
            let cwd = ProcessScanner.cwd(for: pid)
            XCTAssertNotNil(cwd, "PID \(pid) should have a CWD")

            // Verify args contain claude-code marker
            let args = ProcessScanner.processArgs(for: pid)
            XCTAssertNotNil(args, "PID \(pid) should have readable args")
            let hasClaudeMarker = args?.contains { $0.contains("claude-code/cli") } ?? false
            let execPath = ProcessScanner.executablePath(for: pid) ?? ""
            let isBundled = execPath.contains(".local/share/claude/versions")
            XCTAssertTrue(hasClaudeMarker || isBundled,
                "PID \(pid) should be identifiable as Claude Code. exec=\(execPath) args=\(args?.joined(separator: " ") ?? "nil")")
        }
    }
}
