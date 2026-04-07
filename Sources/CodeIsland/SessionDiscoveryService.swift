import Foundation
import CoreServices
import os.log
import CodeIslandCore

private let log = Logger(subsystem: "com.codeisland", category: "SessionDiscovery")

struct DiscoveredSession {
    let sessionId: String
    let cwd: String
    let tty: String?
    let model: String?
    let pid: pid_t?
    let termBundleId: String?
    let modifiedAt: Date
    let recentMessages: [ChatMessage]
    var source: String = "claude"
}

@MainActor
final class SessionDiscoveryService {
    private var watcherTask: Task<Void, Never>?
    private var lastFSScanTime: Date = .distantPast

    var onDiscovered: (([DiscoveredSession]) -> Void)?

    func startWatching() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let projectsPath = "\(home)/.claude/projects"
        guard FileManager.default.fileExists(atPath: projectsPath) else { return }

        watcherTask = Task { [weak self] in
            for await _ in Self.directoryEvents(path: projectsPath) {
                guard let self else { break }
                guard Date().timeIntervalSince(self.lastFSScanTime) > 3 else { continue }
                self.lastFSScanTime = Date()
                self.scanAndNotify()
            }
        }
        log.info("Projects watcher started on \(projectsPath)")
    }

    func stopWatching() {
        watcherTask?.cancel()
        watcherTask = nil
    }

    private func scanAndNotify() {
        Task.detached {
            let sessions = Self.findActiveClaudeSessions()
            await MainActor.run { [weak self] in
                self?.onDiscovered?(sessions)
            }
        }
    }

    private static func directoryEvents(path: String, latency: TimeInterval = 2.0) -> AsyncStream<Void> {
        AsyncStream { continuation in
            var context = FSEventStreamContext()
            let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(ContinuationBox(continuation)).toOpaque())
            context.info = ptr

            let stream = FSEventStreamCreate(
                nil,
                { (_, info, _, _, _, _) in
                    guard let info else { return }
                    let box = Unmanaged<ContinuationBox>.fromOpaque(info).takeUnretainedValue()
                    box.continuation.yield()
                },
                &context,
                [path] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                latency,
                FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes)
            )

            guard let stream else {
                continuation.finish()
                return
            }

            FSEventStreamSetDispatchQueue(stream, .main)
            FSEventStreamStart(stream)

            let cleanup = StreamCleanup(stream: stream, ptr: ptr)
            continuation.onTermination = { _ in
                cleanup.teardown()
            }
        }
    }

    private final class StreamCleanup: @unchecked Sendable {
        private let stream: FSEventStreamRef
        private let ptr: UnsafeMutableRawPointer
        init(stream: FSEventStreamRef, ptr: UnsafeMutableRawPointer) {
            self.stream = stream
            self.ptr = ptr
        }
        func teardown() {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            let _ = Unmanaged<ContinuationBox>.fromOpaque(ptr).takeRetainedValue()
        }
    }

    private final class ContinuationBox: @unchecked Sendable {
        let continuation: AsyncStream<Void>.Continuation
        init(_ continuation: AsyncStream<Void>.Continuation) { self.continuation = continuation }
    }

    // MARK: - Static discovery utilities

    nonisolated static func findActiveClaudeSessions() -> [DiscoveredSession] {
        let claudePids = ProcessScanner.findClaudePids()
        guard !claudePids.isEmpty else { return [] }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fm = FileManager.default
        var results: [DiscoveredSession] = []
        var seenSessionIds: Set<String> = []

        for pid in claudePids {
            guard let cwd = ProcessScanner.cwd(for: pid), !cwd.isEmpty else { continue }

            // Skip subagent worktrees — they are child tasks, not independent sessions
            if cwd.contains("/.claude/worktrees/agent-") || cwd.contains("/.git/worktrees/agent-") {
                continue
            }

            let processStart = ProcessScanner.startTime(for: pid)

            let projectDir = cwd.claudeProjectDirEncoded()
            let projectPath = "\(home)/.claude/projects/\(projectDir)"
            guard let files = try? fm.contentsOfDirectory(atPath: projectPath) else { continue }

            var bestFile: String?
            var bestDate = Date.distantPast
            for file in files where file.hasSuffix(".jsonl") {
                let fullPath = "\(projectPath)/\(file)"
                if let attrs = try? fm.attributesOfItem(atPath: fullPath),
                   let modified = attrs[.modificationDate] as? Date,
                   modified > bestDate {
                    if let start = processStart, modified < start.addingTimeInterval(-10) {
                        continue
                    }
                    bestDate = modified
                    bestFile = file
                }
            }

            guard let file = bestFile else { continue }

            // Skip stale transcripts: only show sessions active within last 5 minutes
            if bestDate.timeIntervalSinceNow < -300 { continue }

            let sessionId = String(file.dropLast(6))
            guard !seenSessionIds.contains(sessionId) else { continue }
            seenSessionIds.insert(sessionId)

            let (model, messages) = readRecentFromTranscript(path: "\(projectPath)/\(file)")
            let tty = ProcessScanner.ttyPath(for: pid)
            let termBundle = ProcessScanner.findTerminalBundleId(for: pid)

            results.append(DiscoveredSession(
                sessionId: sessionId,
                cwd: cwd,
                tty: tty,
                model: model,
                pid: pid,
                termBundleId: termBundle,
                modifiedAt: bestDate,
                recentMessages: messages
            ))
        }
        return results
    }

    nonisolated static func readModelFromTranscript(sessionId: String, cwd: String?) -> String? {
        guard let cwd = cwd else { return nil }
        let projectDir = cwd.claudeProjectDirEncoded()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = "\(home)/.claude/projects/\(projectDir)/\(sessionId).jsonl"
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { handle.closeFile() }
        let chunk = handle.readData(ofLength: 32768)
        guard let text = String(data: chunk, encoding: .utf8) else { return nil }
        for line in text.components(separatedBy: "\n") {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = json["message"] as? [String: Any],
                  let model = message["model"] as? String, !model.isEmpty
            else { continue }
            return model
        }
        return nil
    }

    // MARK: - Private transcript helpers

    nonisolated static func readRecentFromTranscript(path: String) -> (String?, [ChatMessage]) {
        guard let handle = FileHandle(forReadingAtPath: path) else { return (nil, []) }
        defer { handle.closeFile() }

        let fileSize = handle.seekToEndOfFile()
        let readSize: UInt64 = min(fileSize, 65536)
        handle.seek(toFileOffset: fileSize - readSize)
        let data = handle.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return (nil, []) }

        var model: String?
        var userMessages: [(Int, String)] = []
        var assistantMessages: [(Int, String)] = []
        var index = 0

        for line in text.components(separatedBy: "\n") {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let message = json["message"] as? [String: Any],
                  let role = message["role"] as? String
            else { continue }

            if model == nil, let m = message["model"] as? String, !m.isEmpty {
                model = m
            }

            var textContent: String?
            if let content = message["content"] as? String, !content.isEmpty {
                textContent = content
            } else if let contentArray = message["content"] as? [[String: Any]] {
                for item in contentArray {
                    if item["type"] as? String == "text",
                       let t = item["text"] as? String, !t.isEmpty {
                        textContent = t
                        break
                    }
                }
            }

            if let text = textContent {
                if role == "user" {
                    userMessages.append((index, text))
                } else if role == "assistant" {
                    assistantMessages.append((index, text))
                }
            }
            index += 1
        }

        var combined: [(Int, ChatMessage)] = []
        for (i, text) in userMessages.suffix(3) {
            if let info = TaskNotificationInfo.parse(text) {
                let display = info.summary ?? "Task \(info.status)"
                combined.append((i, ChatMessage(kind: .taskNotification(info), text: display)))
            } else {
                combined.append((i, ChatMessage(isUser: true, text: text)))
            }
        }
        for (i, text) in assistantMessages.suffix(3) {
            combined.append((i, ChatMessage(isUser: false, text: text)))
        }
        combined.sort { $0.0 < $1.0 }
        let recent = Array(combined.suffix(3).map { $0.1 })

        return (model, recent)
    }
}
