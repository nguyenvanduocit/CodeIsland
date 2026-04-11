import Foundation

// Support both snake_case and camelCase field names (Claude Code isn't consistent across versions)
private func jsonField<T>(_ json: [String: Any], _ snakeCase: String, _ camelCase: String) -> T? {
    (json[snakeCase] as? T) ?? (json[camelCase] as? T)
}

public enum AgentStatus: String, Sendable, Codable {
    case idle
    case processing
    case running
    case waitingApproval
    case waitingQuestion
}

/// Shared metadata fields present in all hook events
public struct EventMetadata {
    public let cwd: String?
    public let workspaceRoots: [String]?
    public let model: String?
    public let permissionMode: String?
    public let termApp: String?
    public let tty: String?
    public let tmuxPane: String?
    public let tmuxClientTty: String?
    public let termBundle: String?
    public let ppid: Int?
    public let source: String?
    public let transcriptPath: String?
    public let interactive: Bool?

    init(from json: [String: Any]) {
        cwd = json["cwd"] as? String
        workspaceRoots = json["workspace_roots"] as? [String]
        model = json["model"] as? String
        permissionMode = json["permission_mode"] as? String
        termApp = json["_term_app"] as? String
        tty = json["_tty"] as? String
        tmuxPane = json["_tmux_pane"] as? String
        tmuxClientTty = json["_tmux_client_tty"] as? String
        termBundle = json["_term_bundle"] as? String
        ppid = json["_ppid"] as? Int
        source = json["_source"] as? String
        transcriptPath = json["transcript_path"] as? String
        interactive = json["_interactive"] as? Bool
    }
}

public struct HookEvent {
    public let eventName: String
    public let sessionId: String?
    public let toolName: String?
    public let agentId: String?
    public let metadata: EventMetadata
    public let toolInput: [String: Any]?

    // Event-specific typed fields
    public let prompt: String?
    public let lastAssistantMessage: String?
    public let errorDetails: String?
    public let isInterrupt: Bool
    public let agentType: String?
    public let newCwd: String?
    public let question: String?
    public let notificationOptions: [String]?
    public let askUserPayload: QuestionPayload?
    public let toolDescription: String?
    public let permissionSuggestions: [[String: Any]]?

    public init?(from data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        guard let eventName: String = jsonField(json, "hook_event_name", "hookEventName") else {
            return nil
        }
        self.eventName = eventName
        self.sessionId = HookEvent.sanitizeSessionId(jsonField(json, "session_id", "sessionId"))
        self.toolName = jsonField(json, "tool_name", "toolName")
        self.agentId = jsonField(json, "agent_id", "agentId")
        self.metadata = EventMetadata(from: json)

        self.prompt = json["prompt"] as? String
        self.lastAssistantMessage = jsonField(json, "last_assistant_message", "lastAssistantMessage")
        self.errorDetails = jsonField(json, "error_details", "errorDetails")
        self.isInterrupt = jsonField(json, "is_interrupt", "isInterrupt") ?? false
        self.agentType = jsonField(json, "agent_type", "agentType")
        self.newCwd = jsonField(json, "new_cwd", "newCwd")
        self.question = json["question"] as? String
        self.notificationOptions = json["options"] as? [String]

        let toolInput: [String: Any]? = jsonField(json, "tool_input", "toolInput")
        self.toolInput = toolInput

        // Parse permission suggestions (PermissionRequest events)
        self.permissionSuggestions = jsonField(json, "permission_suggestions", "permissionSuggestions")

        // Derive toolDescription — tool-specific extraction for useful context
        self.toolDescription = Self.deriveToolDescription(
            toolName: self.toolName, toolInput: toolInput, json: json
        )

        // Parse AskUserQuestion payload from tool_input
        if let input = toolInput {
            if let questions = input["questions"] as? [[String: Any]], let first = questions.first {
                let questionText = first["question"] as? String ?? "Question"
                let header = first["header"] as? String
                var optionLabels: [String]?
                var optionDescs: [String]?
                if let opts = first["options"] as? [[String: Any]] {
                    optionLabels = opts.compactMap { $0["label"] as? String }
                    optionDescs = opts.compactMap { $0["description"] as? String }
                }
                self.askUserPayload = QuestionPayload(question: questionText, options: optionLabels, descriptions: optionDescs, header: header)
            } else if let questionText = input["question"] as? String {
                var options: [String]?
                if let stringOpts = input["options"] as? [String] { options = stringOpts }
                else if let dictOpts = input["options"] as? [[String: Any]] { options = dictOpts.compactMap { $0["label"] as? String } }
                self.askUserPayload = QuestionPayload(question: questionText, options: options)
            } else {
                self.askUserPayload = nil
            }
        } else {
            self.askUserPayload = nil
        }
    }

    /// Derive a human-readable tool description from tool input, tailored per tool type.
    private static func deriveToolDescription(
        toolName: String?, toolInput: [String: Any]?, json: [String: Any]
    ) -> String? {
        if let input = toolInput, let tool = toolName {
            switch tool {
            case "Bash":
                if let desc = input["description"] as? String, !desc.isEmpty { return desc }
                if let cmd = input["command"] as? String {
                    let line = cmd.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? cmd
                    return String(line.prefix(60))
                }
            case "Read":
                if let fp = input["file_path"] as? String {
                    let name = (fp as NSString).lastPathComponent
                    if let offset = input["offset"] as? Int { return "\(name):\(offset)" }
                    return name
                }
            case "Edit", "Write":
                if let fp = input["file_path"] as? String {
                    return (fp as NSString).lastPathComponent
                }
            case "Grep":
                if let pattern = input["pattern"] as? String {
                    let dir = (input["path"] as? String).map { " in \(($0 as NSString).lastPathComponent)" } ?? ""
                    return "\(pattern)\(dir)"
                }
            case "Glob":
                if let pattern = input["pattern"] as? String { return pattern }
            case "WebSearch":
                if let query = input["query"] as? String { return query }
            case "WebFetch":
                if let url = input["url"] as? String {
                    if let host = URL(string: url)?.host { return host }
                    return String(url.prefix(40))
                }
            case "Agent", "Task":
                if let desc = input["description"] as? String, !desc.isEmpty { return desc }
                if let prompt = input["prompt"] as? String { return String(prompt.prefix(40)) }
            case "TodoWrite":
                return "Updating tasks"
            default:
                // Generic: try common fields
                if let fp = input["file_path"] as? String { return (fp as NSString).lastPathComponent }
                if let pattern = input["pattern"] as? String { return pattern }
                if let cmd = input["command"] as? String { return String(cmd.prefix(60)) }
                if let prompt = input["prompt"] as? String { return String(prompt.prefix(40)) }
            }
        }
        // Fallback for events without toolInput
        if let msg = json["message"] as? String { return msg }
        if let at = json["agent_type"] as? String { return at }
        if let p = json["prompt"] as? String { return String(p.prefix(40)) }
        return nil
    }

    /// Validate and sanitize session ID (alphanumeric, hyphens, underscores, max 256 chars)
    public static func sanitizeSessionId(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty, raw.count <= 256 else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard raw.unicodeScalars.first.map({ CharacterSet.alphanumerics.contains($0) }) == true else { return nil }
        return raw.unicodeScalars.allSatisfy({ allowed.contains($0) }) ? raw : nil
    }
}

public struct SubagentState: Sendable, Codable {
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

public struct ChatMessage: Identifiable, Sendable, Codable {
    public enum Kind: Sendable, Codable {
        case user
        case assistant
        case taskNotification(TaskNotificationInfo)

        private enum CodingKeys: String, CodingKey { case type, info }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let type_ = try c.decode(String.self, forKey: .type)
            switch type_ {
            case "user": self = .user
            case "assistant": self = .assistant
            case "taskNotification":
                let info = try c.decode(TaskNotificationInfo.self, forKey: .info)
                self = .taskNotification(info)
            default: self = .assistant
            }
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .user: try c.encode("user", forKey: .type)
            case .assistant: try c.encode("assistant", forKey: .type)
            case .taskNotification(let info):
                try c.encode("taskNotification", forKey: .type)
                try c.encode(info, forKey: .info)
            }
        }
    }

    public let id: UUID
    public let kind: Kind
    public let text: String

    public var isUser: Bool { if case .user = kind { return true } else { return false } }
    public var isTaskNotification: Bool { if case .taskNotification = kind { return true } else { return false } }

    public init(isUser: Bool, text: String) {
        self.id = UUID()
        self.kind = isUser ? .user : .assistant
        self.text = text
    }

    public init(kind: Kind, text: String) {
        self.id = UUID()
        self.kind = kind
        self.text = text
    }

    private enum CodingKeys: String, CodingKey { case kind, text }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.kind = try c.decode(Kind.self, forKey: .kind)
        self.text = try c.decode(String.self, forKey: .text)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(text, forKey: .text)
    }
}

public struct TaskNotificationInfo: Sendable, Codable {
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

public struct QuestionPayload: Sendable, Codable {
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
        if let question = event.question {
            return QuestionPayload(question: question, options: event.notificationOptions)
        }
        // Don't use "?" heuristic — normal status text like "Should I update tests?"
        // would be misclassified as a blocking question, stalling the hook.
        return nil
    }
}
