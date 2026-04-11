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

    weak var appState: AppState?

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

    /// Start monitoring using a known PID from the bridge.
    func tryMonitor(sessionId: String, cliPid: pid_t?) {
        guard !isMonitoring(sessionId) else { return }
        guard let pid = cliPid, pid > 0, kill(pid, 0) == 0 else { return }
        monitor(sessionId: sessionId, pid: pid)
    }

    func stop(sessionId: String) {
        monitors[sessionId]?.source.cancel()
        monitors.removeValue(forKey: sessionId)
    }

    func stopAll() {
        for key in Array(monitors.keys) { stop(sessionId: key) }
    }

    // MARK: - Private

    private func handleProcessExit(sessionId: String, exitedPid: pid_t) {
        stop(sessionId: sessionId)
        log.debug("Process \(exitedPid) exited for session \(sessionId)")
        // Check if the PID was already replaced by a new alive process
        // (e.g. auto-update restarted Claude Code). If so, re-attach monitor.
        if let checkPid = appState?.sessions[sessionId]?.cliPid,
           checkPid > 0, checkPid != exitedPid,
           kill(checkPid, 0) == 0 {
            log.debug("Session \(sessionId) taken over by new PID \(checkPid), re-attaching monitor")
            monitor(sessionId: sessionId, pid: checkPid)
            return
        }
        onSessionExpired?(sessionId, Date())
    }
}
