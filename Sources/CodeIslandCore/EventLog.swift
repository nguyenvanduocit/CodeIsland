import Foundation
import Darwin

public enum EventLog {
    private static let dirPath = FileManager.default.homeDirectoryForCurrentUser.path + "/.codeisland"
    private static let filePath = dirPath + "/events.jsonl"
    private static let maxFileSize: UInt64 = 1_048_576  // 1MB
    private static let maxAge: TimeInterval = 24 * 60 * 60  // 24h

    /// Append a JSON dictionary to the log. Injects _log_ts automatically.
    /// Called from bridge. Uses O_APPEND for atomic writes.
    public static func append(_ json: [String: Any]) {
        var enriched = json
        enriched["_log_ts"] = ISO8601DateFormatter().string(from: Date())
        guard let data = try? JSONSerialization.data(withJSONObject: enriched) else { return }
        appendRaw(data)
    }

    /// Low-level: append raw bytes (must be a single valid JSON object, no trailing newline).
    /// Uses O_APPEND | O_CREAT | O_WRONLY for atomic appends. Skips if file exceeds size cap.
    private static func appendRaw(_ jsonData: Data) {
        // Ensure directory exists
        mkdir(dirPath, 0o755)

        // Check file size — skip if over cap
        var statBuf = stat()
        if stat(filePath, &statBuf) == 0 && UInt64(statBuf.st_size) > maxFileSize {
            return
        }

        // Open with O_APPEND | O_CREAT | O_WRONLY
        let fd = open(filePath, O_APPEND | O_CREAT | O_WRONLY, 0o644)
        guard fd >= 0 else { return }
        defer { close(fd) }

        // Build line: JSON bytes + newline as a single write() for atomicity
        var line = jsonData
        if line.last != UInt8(ascii: "\n") {
            line.append(UInt8(ascii: "\n"))
        }
        line.withUnsafeBytes { buf in
            guard let base = buf.baseAddress else { return }
            _ = Darwin.write(fd, base, buf.count)
        }
    }

    /// Read all non-stale events and truncate the file.
    /// Uses flock(LOCK_EX) for exclusive access. Called from main app on startup.
    public static func readAndClear() -> [Data] {
        let fd = open(filePath, O_RDWR)
        guard fd >= 0 else { return [] }
        defer { close(fd) }

        // Exclusive lock
        guard flock(fd, LOCK_EX) == 0 else { return [] }
        defer { flock(fd, LOCK_UN) }

        // Get file size
        let fileSize = lseek(fd, 0, SEEK_END)
        guard fileSize > 0 else { return [] }
        lseek(fd, 0, SEEK_SET)

        // Read all content
        var buffer = Data(count: Int(fileSize))
        let bytesRead = buffer.withUnsafeMutableBytes { buf -> Int in
            guard let base = buf.baseAddress else { return 0 }
            return Darwin.read(fd, base, buf.count)
        }
        guard bytesRead > 0 else { return [] }
        buffer = buffer.prefix(bytesRead)

        // Truncate file
        ftruncate(fd, 0)

        // Parse lines, filter stale events
        let cutoff = Date().addingTimeInterval(-maxAge)
        let formatter = ISO8601DateFormatter()
        let lines = buffer.split(separator: UInt8(ascii: "\n"))

        return lines.compactMap { lineSlice in
            let data = Data(lineSlice)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            if let tsString = json["_log_ts"] as? String,
               let ts = formatter.date(from: tsString),
               ts < cutoff {
                return nil  // stale
            }
            return data
        }
    }
}
