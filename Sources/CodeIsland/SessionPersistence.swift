import Foundation
import CodeIslandCore

private struct PersistedEntry: Codable {
    let sessionId: String
    let snapshot: SessionSnapshot
}

enum SessionPersistence {
    private static let dirPath = FileManager.default.homeDirectoryForCurrentUser.path + "/.codeisland"
    private static let filePath = dirPath + "/sessions.json"

    static func save(_ sessions: [String: SessionSnapshot]) {
        let entries = sessions.map { PersistedEntry(sessionId: $0.key, snapshot: $0.value) }
        do {
            try FileManager.default.createDirectory(atPath: dirPath, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(entries)
            try data.write(to: URL(fileURLWithPath: filePath), options: .atomic)
        } catch {}
    }

    static func load() -> [String: SessionSnapshot] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let entries = try? decoder.decode([PersistedEntry].self, from: data) else { return [:] }
        return Dictionary(entries.map { ($0.sessionId, $0.snapshot) }, uniquingKeysWith: { _, b in b })
    }

    static func clear() {
        try? FileManager.default.removeItem(atPath: filePath)
    }
}
