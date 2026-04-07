import Foundation

// Support both snake_case and camelCase field names (Claude Code isn't consistent across versions)
private func jsonField<T>(_ json: [String: Any], _ snakeCase: String, _ camelCase: String) -> T? {
    (json[snakeCase] as? T) ?? (json[camelCase] as? T)
}

public enum AgentStatus {
    case idle
    case processing
    case running
    case waitingApproval
    case waitingQuestion
}

public struct HookEvent {
    public let eventName: String
    public let sessionId: String?
    public let toolName: String?
    public let agentId: String?
    public let toolInput: [String: Any]?
    public let rawJSON: [String: Any]  // Full payload for event-specific fields

    public init?(from data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        // Support both snake_case and camelCase (Claude Code isn't consistent across versions)
        guard let eventName: String = jsonField(json, "hook_event_name", "hookEventName") else {
            return nil
        }
        self.eventName = eventName
        self.sessionId = HookEvent.sanitizeSessionId(jsonField(json, "session_id", "sessionId"))
        self.toolName = jsonField(json, "tool_name", "toolName")
        self.toolInput = jsonField(json, "tool_input", "toolInput")
        self.agentId = jsonField(json, "agent_id", "agentId")
        self.rawJSON = json
    }

    /// Validate and sanitize session ID (alphanumeric, hyphens, underscores, max 256 chars)
    public static func sanitizeSessionId(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty, raw.count <= 256 else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard raw.unicodeScalars.first.map({ CharacterSet.alphanumerics.contains($0) }) == true else { return nil }
        return raw.unicodeScalars.allSatisfy({ allowed.contains($0) }) ? raw : nil
    }

    public var toolDescription: String? {
        // Try tool_input fields first
        if let input = toolInput {
            if let command = input["command"] as? String { return command }
            if let filePath = input["file_path"] as? String { return (filePath as NSString).lastPathComponent }
            if let pattern = input["pattern"] as? String { return pattern }
            if let prompt = input["prompt"] as? String { return String(prompt.prefix(40)) }
        }
        // Fall back to top-level fields
        if let msg = rawJSON["message"] as? String { return msg }
        if let agentType = rawJSON["agent_type"] as? String { return agentType }
        if let prompt = rawJSON["prompt"] as? String { return String(prompt.prefix(40)) }
        return nil
    }
}

public struct SubagentState {
    public let agentId: String
    public let agentType: String
    public var status: AgentStatus = .running
    public var currentTool: String?
    public var toolDescription: String?
    public var startTime: Date = Date()
    public var lastActivity: Date = Date()

    public init(agentId: String, agentType: String) {
        self.agentId = agentId
        self.agentType = agentType
    }
}

public struct ToolHistoryEntry: Identifiable {
    public let id = UUID()
    public let tool: String
    public let description: String?
    public let timestamp: Date
    public let success: Bool
    public let agentType: String?  // nil = main thread

    public init(tool: String, description: String?, timestamp: Date, success: Bool, agentType: String?) {
        self.tool = tool
        self.description = description
        self.timestamp = timestamp
        self.success = success
        self.agentType = agentType
    }
}

public struct ChatMessage: Identifiable {
    public enum Kind {
        case user
        case assistant
        case taskNotification(TaskNotificationInfo)
    }

    public let id = UUID()
    public let kind: Kind
    public let text: String

    public var isUser: Bool { if case .user = kind { return true } else { return false } }
    public var isTaskNotification: Bool { if case .taskNotification = kind { return true } else { return false } }

    public init(isUser: Bool, text: String) {
        self.kind = isUser ? .user : .assistant
        self.text = text
    }

    public init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }
}

public struct TaskNotificationInfo {
    public let taskId: String?
    public let status: String   // "completed", "failed", "killed"
    public let summary: String?

    public init(taskId: String?, status: String, summary: String?) {
        self.taskId = taskId
        self.status = status
        self.summary = summary
    }

    /// Parse a `<task-notification>...</task-notification>` XML string.
    public static func parse(_ text: String) -> TaskNotificationInfo? {
        guard text.contains("<task-notification") else { return nil }
        let taskId = extractTag("task-id", from: text)
        let status = extractTag("status", from: text) ?? "completed"
        let summary = extractTag("summary", from: text)
        return TaskNotificationInfo(taskId: taskId, status: status, summary: summary)
    }

    private static func extractTag(_ tag: String, from text: String) -> String? {
        guard let startRange = text.range(of: "<\(tag)>"),
              let endRange = text.range(of: "</\(tag)>") else { return nil }
        let content = String(text[startRange.upperBound..<endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return content.isEmpty ? nil : content
    }
}

// MARK: - Hook Responses

/// Typed builder for hook responses — replaces inline JSON string construction.
/// Each static method returns serialized Data ready to send over the socket.
public enum HookResponse {
    /// Empty response (non-blocking events)
    public static let empty = Data("{}".utf8)

    /// Parse error response
    public static let parseError = Data("{\"error\":\"parse_failed\"}".utf8)

    /// Permission decision: allow, deny, or ask
    public static func permission(_ behavior: PermissionBehavior, reason: String? = nil) -> Data {
        var decision: [String: Any] = ["behavior": behavior.rawValue]
        if let reason { decision["reason"] = reason }
        let output: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": decision,
            ]
        ]
        return (try? JSONSerialization.data(withJSONObject: output)) ?? empty
    }

    /// Question/AskUserQuestion answer
    public static func answer(_ text: String) -> Data {
        let output: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": [
                    "behavior": "allow",
                    "userResponse": text,
                ],
            ]
        ]
        return (try? JSONSerialization.data(withJSONObject: output)) ?? empty
    }

    /// Skip/deny a question
    public static func skipQuestion() -> Data {
        permission(.deny, reason: "User skipped")
    }

    public enum PermissionBehavior: String {
        case allow
        case deny
        case ask
    }
}

public struct QuestionPayload {
    public let question: String
    public let options: [String]?
    public let descriptions: [String]?
    public let header: String?

    public init(question: String, options: [String]?, descriptions: [String]? = nil, header: String? = nil) {
        self.question = question
        self.options = options
        self.descriptions = descriptions
        self.header = header
    }

    /// Try to extract question from a Notification hook event
    public static func from(event: HookEvent) -> QuestionPayload? {
        if let question = event.rawJSON["question"] as? String {
            let options = event.rawJSON["options"] as? [String]
            return QuestionPayload(question: question, options: options)
        }
        // Don't use "?" heuristic — normal status text like "Should I update tests?"
        // would be misclassified as a blocking question, stalling the hook.
        return nil
    }
}
