import Foundation
import CodeIslandCore

/// Reads token usage from Claude Code JSONL transcript files.
/// Context window = last turn's (input + cache_read + cache_creation).
/// Cost = sum of costUSD across all turns.
enum SessionUsageReader {

    struct UsageResult {
        var usage: TokenUsage
        var model: String?
    }

    /// Read token usage for a session by scanning its JSONL transcript.
    nonisolated static func readUsage(sessionId: String, cwd: String?) -> UsageResult? {
        guard let path = transcriptPath(sessionId: sessionId, cwd: cwd) else { return nil }
        return readUsage(at: path)
    }

    nonisolated static func readUsage(at path: String) -> UsageResult? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { handle.closeFile() }

        let data = handle.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return nil }

        var usage = TokenUsage()
        var model: String?
        var found = false
        var totalCost: Double = 0

        for line in text.split(whereSeparator: \.isNewline) {
            guard let lineData = String(line).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let message = json["message"] as? [String: Any],
                  let msgUsage = message["usage"] as? [String: Any]
            else { continue }

            // Context window = last turn's values (replace each time, keep last)
            usage.inputTokens = msgUsage["input_tokens"] as? Int ?? 0
            usage.outputTokens = msgUsage["output_tokens"] as? Int ?? 0
            usage.cacheReadTokens = msgUsage["cache_read_input_tokens"] as? Int ?? 0
            usage.cacheCreationTokens = msgUsage["cache_creation_input_tokens"] as? Int ?? 0

            if let cost = json["costUSD"] as? Double {
                totalCost += cost
            }

            // Keep last model seen (tracks model changes mid-session)
            if let m = message["model"] as? String, !m.isEmpty {
                model = m
            }

            found = true
        }

        usage.costUSD = totalCost
        return found ? UsageResult(usage: usage, model: model) : nil
    }

    private static func transcriptPath(sessionId: String, cwd: String?) -> String? {
        guard let cwd = cwd else { return nil }
        let projectDir = cwd.claudeProjectDirEncoded()
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        // Try legacy path first, then XDG
        let legacyPath = "\(home)/.claude/projects/\(projectDir)/\(sessionId).jsonl"
        if FileManager.default.fileExists(atPath: legacyPath) { return legacyPath }

        let xdgPath = "\(home)/.config/claude/projects/\(projectDir)/\(sessionId).jsonl"
        if FileManager.default.fileExists(atPath: xdgPath) { return xdgPath }

        return nil
    }
}
