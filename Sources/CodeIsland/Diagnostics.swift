import Foundation
import MetricKit
import os.log
import os.signpost

private let log = Logger(subsystem: "com.codeisland", category: "Diagnostics")

// MARK: - Signpost helpers

/// Shared signposter for startup and event-processing intervals.
/// Use with Instruments → os_signpost to measure real latency.
enum Signposts {
    static let signposter = OSSignposter(subsystem: "com.codeisland", category: .pointsOfInterest)

    /// Begin/end a named interval. Returns a state to pass to `end()`.
    static func beginStartupPhase(_ name: StaticString) -> OSSignpostIntervalState {
        signposter.beginInterval(name)
    }

    static func endStartupPhase(_ name: StaticString, _ state: OSSignpostIntervalState) {
        signposter.endInterval(name, state)
    }
}

// MARK: - MetricKit subscriber

/// Receives daily diagnostic payloads from the OS (hangs, crashes, memory peaks, CPU).
/// Payloads are logged — view via Console.app or `log show --predicate 'category == "Diagnostics"'`.
@MainActor
final class DiagnosticsService: NSObject, MXMetricManagerSubscriber {

    private var memoryTimer: Task<Void, Never>?
    private var peakMemoryBytes: UInt64 = 0

    func start() {
        MXMetricManager.shared.add(self)
        startMemoryMonitor()
        log.info("Diagnostics started (MetricKit + memory monitor)")
    }

    func stop() {
        MXMetricManager.shared.remove(self)
        memoryTimer?.cancel()
        memoryTimer = nil
        logPeakMemory()
    }

    // MARK: MXMetricManagerSubscriber

    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            let json = payload.jsonRepresentation()
            if let data = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
               let str = String(data: data, encoding: .utf8) {
                log.info("MetricKit payload:\n\(str, privacy: .public)")
            }
        }
    }

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let json = payload.jsonRepresentation()
            if let data = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
               let str = String(data: data, encoding: .utf8) {
                log.warning("MetricKit diagnostic:\n\(str, privacy: .public)")
            }
        }
    }

    // MARK: - Memory high-water mark

    private func startMemoryMonitor() {
        peakMemoryBytes = currentResidentMemory()
        memoryTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self else { return }
                let current = currentResidentMemory()
                if current > self.peakMemoryBytes {
                    self.peakMemoryBytes = current
                    log.info("Memory high-water mark: \(Self.formatBytes(current), privacy: .public)")
                }
            }
        }
    }

    private func logPeakMemory() {
        log.info("Session peak memory: \(Self.formatBytes(self.peakMemoryBytes), privacy: .public)")
    }

    /// Read current resident memory (phys_footprint) via task_info.
    private func currentResidentMemory() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        return UInt64(info.phys_footprint)
    }

    private static func formatBytes(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / (1024 * 1024)
        return String(format: "%.1f MB", mb)
    }
}
