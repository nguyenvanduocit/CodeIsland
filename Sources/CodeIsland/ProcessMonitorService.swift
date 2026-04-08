import Foundation
import os.log
import CodeIslandCore

private let log = Logger(subsystem: "com.codeisland", category: "ProcessMonitor")

@MainActor
final class ProcessMonitorService {
    private var monitors: [String: (source: DispatchSourceProcess, pid: pid_t)] = [:]

    /// Called when a process exits and grace period expires without replacement.
    /// Parameters: sessionId, exitTime (so caller can check for fresh activity).
    var onSessionExpired: ((String, Date) -> Void)?

    func isMonitoring(_ sessionId: String) -> Bool { monitors[sessionId] != nil }
    func pid(for sessionId: String) -> pid_t? { monitors[sessionId]?.pid }

    // MARK: - Public API

    func monitor(sessionId: String, pid: pid_t) {
        guard monitors[sessionId] == nil else { return }
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.handleProcessExit(sessionId: sessionId, exitedPid: pid)
            }
        }
        source.resume()
        monitors[sessionId] = (source: source, pid: pid)
        log.debug("Monitoring pid \(pid) for session \(sessionId)")

        // Safety: if process already exited before monitor started
        if kill(pid, 0) != 0 && errno == ESRCH {
            handleProcessExit(sessionId: sessionId, exitedPid: pid)
        }
    }

    /// Start monitoring using a known PID or fall back to scanning by CWD.
    /// `onPidFound` is called (on MainActor) when the async scan resolves a PID,
    /// so the caller can persist it on the session record.
    func tryMonitor(
        sessionId: String,
        cliPid: pid_t?,
        cwd: String?,
        onPidFound: ((String, pid_t) -> Void)? = nil
    ) {
        guard !isMonitoring(sessionId) else { return }

        // Primary: use PID from bridge
        if let pid = cliPid, pid > 0, kill(pid, 0) == 0 {
            monitor(sessionId: sessionId, pid: pid)
            return
        }

        // Fallback: scan for Claude Code processes by CWD
        guard let cwd = cwd else { return }
        Task.detached {
            let pid = Self.findPidForCwd(cwd)
            await MainActor.run { [weak self] in
                guard let self, let pid else { return }
                guard !self.isMonitoring(sessionId) else { return }
                onPidFound?(sessionId, pid)
                self.monitor(sessionId: sessionId, pid: pid)
            }
        }
    }

    func stop(sessionId: String) {
        monitors[sessionId]?.source.cancel()
        monitors.removeValue(forKey: sessionId)
    }

    func stopAll() {
        for key in Array(monitors.keys) { stop(sessionId: key) }
    }

    // MARK: - Static helpers

    nonisolated static func findPidForCwd(_ cwd: String) -> pid_t? {
        for pid in ProcessScanner.findClaudePids() {
            if ProcessScanner.cwd(for: pid) == cwd { return pid }
        }
        return nil
    }

    // MARK: - Private

    private func handleProcessExit(sessionId: String, exitedPid: pid_t) {
        stop(sessionId: sessionId)
        log.debug("Process \(exitedPid) exited for session \(sessionId)")
        onSessionExpired?(sessionId, Date())
    }
}
