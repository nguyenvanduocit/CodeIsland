import Foundation

public enum SessionTitleSource: String, Sendable, Codable {
    case claudeCustomTitle
    case claudeAiTitle
}

public struct SessionSnapshot: Sendable, Codable {
    public static let supportedSources: Set<String> = [
        "claude",
    ]

    public var status: AgentStatus = .idle
    public var currentTool: String?
    public var toolDescription: String?
    public var lastActivity: Date = Date()
    public var cwd: String?
    public var model: String?
    public var permissionMode: String?
    public var toolHistory: [ToolHistoryEntry] = []
    public var errorStreak: Int = 0
    public var transcriptSize: Int64 = 0
    public var subagents: [String: SubagentState] = [:]
    public var startTime: Date = Date()
    public var lastUserPrompt: String?
    public var lastAssistantMessage: String?
    /// Recent chat messages (max 3) for preview
    public var recentMessages: [ChatMessage] = []
    // Terminal info for window activation
    public var termApp: String?        // "iTerm.app", "Apple_Terminal", etc.
    public var itermSessionId: String?  // iTerm2 session ID for direct activation
    public var ttyPath: String?         // /dev/ttys00X
    public var kittyWindowId: String?   // Kitty window ID for precise focus
    public var tmuxPane: String?        // tmux pane identifier (%0, %1, etc.)
    public var tmuxClientTty: String?   // tmux client TTY for real terminal detection
    public var termBundleId: String?    // __CFBundleIdentifier for precise terminal ID
    public var cliPid: pid_t?            // CLI process PID (from bridge _ppid)
    public var transcriptPath: String?   // Path to the JSONL transcript file
    public var source: String = "claude"
    public var interrupted: Bool = false
    public var sessionTitle: String?
    public var sessionTitleSource: SessionTitleSource?
    public var providerSessionId: String?
    public var tokenUsage: TokenUsage?

    // CodingKeys excludes transient runtime fields: toolHistory, subagents
    private enum CodingKeys: String, CodingKey {
        case status, currentTool, toolDescription, lastActivity, cwd, model, permissionMode
        case errorStreak, transcriptSize, startTime, lastUserPrompt, lastAssistantMessage
        case recentMessages, termApp, itermSessionId, ttyPath, kittyWindowId, tmuxPane
        case tmuxClientTty, termBundleId, cliPid, transcriptPath, source, interrupted
        case sessionTitle, sessionTitleSource, providerSessionId, tokenUsage
    }

    public init(startTime: Date = Date()) {
        self.startTime = startTime
    }

    public static func normalizedSupportedSource(_ source: String?) -> String? {
        guard let source else { return nil }
        let normalized = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty, supportedSources.contains(normalized) else { return nil }
        return normalized
    }

    public var activeSubagentCount: Int {
        subagents.values.filter { $0.status != .idle }.count
    }

    public mutating func addRecentMessage(_ msg: ChatMessage, maxCount: Int = 3) {
        recentMessages.append(msg)
        if recentMessages.count > maxCount {
            recentMessages.removeFirst(recentMessages.count - maxCount)
        }
    }

    public mutating func recordTool(_ tool: String, description: String?, success: Bool, agentType: String?, maxHistory: Int) {
        let entry = ToolHistoryEntry(tool: tool, description: description, timestamp: Date(), success: success, agentType: agentType)
        toolHistory.append(entry)
        if toolHistory.count > maxHistory {
            toolHistory.removeFirst()
        }
    }

    /// Display name: project folder, or short session ID
    public var displayName: String {
        if let cwd = cwd {
            return (cwd as NSString).lastPathComponent
        }
        return "Session"
    }

    public func displayTitle(sessionId: String) -> String {
        sessionLabel ?? sessionId
    }

    public func displaySessionId(sessionId: String) -> String {
        if let providerSessionId {
            let trimmed = providerSessionId.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return sessionId
    }

    public var projectDisplayName: String {
        displayName
    }

    public var sessionLabel: String? {
        guard let sessionTitle else { return nil }
        let trimmed = sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Shortened model name: "claude-opus-4-6" → "opus"
    public var shortModelName: String? {
        guard let model = model else { return nil }
        let lower = model.lowercased()
        if lower.contains("opus") { return "opus" }
        if lower.contains("sonnet") { return "sonnet" }
        if lower.contains("haiku") { return "haiku" }
        if let last = model.split(separator: "-").last, last.count <= 8 {
            return String(last)
        }
        return String(model.prefix(8))
    }

    /// Source label for display
    public var sourceLabel: String {
        return "Claude"
    }

    public var isClaude: Bool { source == "claude" }

    /// Always false — Claude Code is CLI-only, no native app mode.
    /// True when the session runs inside an IDE's integrated terminal.
    /// We can't query IDE tab/pane state, so notification suppression should be skipped.
    public var isIDETerminal: Bool {
        guard let bid = termBundleId else { return false }
        let lower = bid.lowercased()
        return lower.contains("vscode") || lower.contains("vscodium")
            || lower == "com.trae.app"
            || lower.contains("windsurf") || lower.contains("codeium")
            || lower.contains("jetbrains")
            || lower.contains("zed")
            || lower.contains("xcode") || lower == "com.apple.dt.xcode"
            || lower.contains("panic.nova")
            || lower.contains("android.studio")
            || lower.contains("antigravity")
            || lower.contains("todesktop")
            || lower.contains("qoder")
            || lower.contains("factory.app")
            || lower.contains("codebuddy")
    }

    /// Short terminal/app name for display tag
    public var terminalName: String? {
        // Check bundle ID for terminal identification (more reliable than TERM_PROGRAM)
        if let bid = termBundleId {
            let lower = bid.lowercased()
            if lower.contains("cmux") { return "cmux" }
            if lower.contains("warp") { return "Warp" }
            if lower == "com.mitchellh.ghostty" { return "Ghostty" }
            if lower.contains("iterm2") { return "iTerm2" }
            if lower.contains("kitty") { return "Kitty" }
            if lower.contains("alacritty") { return "Alacritty" }
            if lower.contains("wezterm") { return "WezTerm" }
            // IDE integrated terminals
            if lower.contains("vscode") || lower.contains("vscodium") { return "VS Code" }
            if lower == "com.trae.app" { return "Trae" }
            if lower.contains("windsurf") { return "Windsurf" }
            if lower.contains("jetbrains") {
                if lower.contains("intellij") { return "IDEA" }
                if lower.contains("pycharm") { return "PyCharm" }
                if lower.contains("webstorm") { return "WebStorm" }
                if lower.contains("goland") { return "GoLand" }
                if lower.contains("clion") { return "CLion" }
                if lower.contains("rider") { return "Rider" }
                if lower.contains("rubymine") { return "RubyMine" }
                if lower.contains("phpstorm") { return "PhpStorm" }
                if lower.contains("datagrip") { return "DataGrip" }
                return "JetBrains"
            }
            if lower.contains("zed") { return "Zed" }
            if lower.contains("xcode") || lower == "com.apple.dt.xcode" { return "Xcode" }
            if lower.contains("panic.nova") { return "Nova" }
            if lower.contains("android.studio") { return "Android Studio" }
            if lower.contains("antigravity") { return "Antigravity" }
        }
        // Fallback to TERM_PROGRAM
        guard let app = termApp else { return nil }
        let lower = app.lowercased()
        if lower.contains("cmux") { return "cmux" }
        if lower == "ghostty" { return "Ghostty" }
        if lower.contains("iterm") { return "iTerm2" }
        if lower.contains("warp") { return "Warp" }
        if lower.contains("alacritty") { return "Alacritty" }
        if lower.contains("kitty") { return "Kitty" }
        if lower.contains("terminal") { return "Terminal" }
        return app
    }

    /// Subtitle: cwd path or model info
    public var subtitle: String? {
        if let cwd = cwd {
            // Show parent/folder instead of just folder
            let parts = cwd.split(separator: "/")
            if parts.count >= 2 {
                return "\(parts[parts.count - 2])/\(parts[parts.count - 1])"
            }
            return cwd
        }
        return model
    }
}

public struct SessionSummary: Sendable, Codable {
    public let status: AgentStatus
    public let primarySource: String
    public let activeSessionCount: Int
    public let totalSessionCount: Int

    public init(status: AgentStatus, primarySource: String, activeSessionCount: Int, totalSessionCount: Int) {
        self.status = status
        self.primarySource = primarySource
        self.activeSessionCount = activeSessionCount
        self.totalSessionCount = totalSessionCount
    }
}

public func deriveSessionSummary(from sessions: [String: SessionSnapshot]) -> SessionSummary {
    var highestStatus: AgentStatus = .idle
    var source = "claude"
    var active = 0
    var mostRecentIdleSource: (source: String, time: Date)?

    for session in sessions.values {
        if session.status != .idle {
            active += 1
        } else if mostRecentIdleSource == nil || session.lastActivity > mostRecentIdleSource!.time {
            mostRecentIdleSource = (session.source, session.lastActivity)
        }

        switch session.status {
        case .waitingApproval:
            highestStatus = .waitingApproval
            source = session.source
        case .waitingQuestion:
            if highestStatus != .waitingApproval {
                highestStatus = .waitingQuestion
                source = session.source
            }
        case .running:
            if highestStatus == .idle || highestStatus == .processing {
                highestStatus = .running
                source = session.source
            }
        case .processing:
            if highestStatus == .idle {
                highestStatus = .processing
                source = session.source
            }
        case .idle:
            break
        }
    }

    if highestStatus == .idle, let idleSource = mostRecentIdleSource?.source {
        source = idleSource
    }

    return SessionSummary(
        status: highestStatus,
        primarySource: source,
        activeSessionCount: active,
        totalSessionCount: sessions.count
    )
}

// MARK: - Side Effects

public enum SideEffect: Equatable {
    case playSound(String)
    case tryMonitorSession(sessionId: String)
    case stopMonitor(sessionId: String)
    case removeSession(sessionId: String)
    case enqueueCompletion(sessionId: String)
    case setActiveSession(sessionId: String?)
}

// MARK: - Tracking Key Resolution

/// Resolve a unique tracking key for a session event.
/// When two processes resume the same session_id, each gets a distinct key (`sessionId/pid`).
public func resolveTrackingKey(
    sessions: [String: SessionSnapshot],
    event: HookEvent
) -> String {
    let rawSessionId = event.sessionId ?? "default"
    guard let pid = event.metadata.ppid, pid > 0 else { return rawSessionId }

    let pidKey = "\(rawSessionId)/\(pid)"

    // Already have a PID-specific entry → use it
    if sessions[pidKey] != nil { return pidKey }

    // Base entry exists with a different PID → fork into PID-specific key
    if let existing = sessions[rawSessionId],
       let existingPid = existing.cliPid, existingPid > 0, existingPid != pid_t(pid) {
        return pidKey
    }

    // No collision → use raw session ID
    return rawSessionId
}

// MARK: - Pure Reducer

/// Pure reducer: mutates sessions, returns side effects for the caller to execute.
/// `trackingKey` overrides the dictionary key (use `resolveTrackingKey` to compute it).
public func reduceEvent(
    sessions: inout [String: SessionSnapshot],
    event: HookEvent,
    trackingKey: String? = nil,
    maxHistory: Int
) -> [SideEffect] {
    let sessionId = trackingKey ?? event.sessionId ?? "default"
    let eventName = event.eventName
    var effects: [SideEffect] = []

    // Ensure session exists
    if sessions[sessionId] == nil {
        sessions[sessionId] = SessionSnapshot()
    }

    // Always update metadata from every event
    extractMetadata(into: &sessions, sessionId: sessionId, event: event)

    // Route subagent-specific events
    if let agentId = event.agentId {
        let handled = handleSubagentEvent(
            sessions: &sessions,
            sessionId: sessionId,
            agentId: agentId,
            eventName: eventName,
            event: event,
            maxHistory: maxHistory,
            effects: &effects
        )
        if handled { return effects }
    }

    // Preserve actionable states: don't let activity updates overwrite waiting states
    let isWaiting = sessions[sessionId]?.status == .waitingApproval
        || sessions[sessionId]?.status == .waitingQuestion

    // Update this session's state based on Claude Code hook events.
    // Schema reference: claude-code/src/entrypoints/sdk/coreSchemas.ts
    switch eventName {

    // ── Turn lifecycle ─────────────────────────────────────────────
    case "UserPromptSubmit":
        // Schema: { prompt: string }
        sessions[sessionId]?.interrupted = false
        sessions[sessionId]?.status = .processing
        sessions[sessionId]?.currentTool = nil
        sessions[sessionId]?.toolDescription = nil
        sessions[sessionId]?.lastAssistantMessage = nil  // clear so collapsed bar shows user prompt
        if let prompt = event.prompt, !prompt.isEmpty {
            // Detect <task-notification> — system-injected when background agent completes
            if let info = TaskNotificationInfo.parse(prompt) {
                let displayText = info.summary ?? "Task \(info.status)"
                sessions[sessionId]?.lastUserPrompt = displayText
                sessions[sessionId]?.addRecentMessage(
                    ChatMessage(kind: .taskNotification(info), text: displayText)
                )
            } else {
                sessions[sessionId]?.lastUserPrompt = prompt
                // Replace trailing duplicate user message
                if sessions[sessionId]?.recentMessages.last?.isUser == true {
                    sessions[sessionId]?.recentMessages.removeLast()
                }
                sessions[sessionId]?.addRecentMessage(ChatMessage(isUser: true, text: prompt))
            }
        }

    case "Stop":
        // Schema: { stop_hook_active: bool, last_assistant_message?: string }
        // Agent finished its turn — session is now idle, waiting for user input.
        // Only clear subagents that belong to the main agent (agentId == nil).
        // Background subagents may still be running.
        sessions[sessionId]?.currentTool = nil
        sessions[sessionId]?.toolDescription = nil
        sessions[sessionId]?.subagents.removeAll()
        if let msg = event.lastAssistantMessage, !msg.isEmpty {
            sessions[sessionId]?.lastAssistantMessage = msg
            sessions[sessionId]?.addRecentMessage(ChatMessage(isUser: false, text: msg))
        }
        sessions[sessionId]?.status = .idle
        effects.append(.enqueueCompletion(sessionId: sessionId))

    case "StopFailure":
        // Schema: { error: object, error_details?: string, last_assistant_message?: string }
        // API error (rate limit, auth, prompt too long). Session goes idle with error context.
        sessions[sessionId]?.status = .idle
        sessions[sessionId]?.currentTool = nil
        sessions[sessionId]?.toolDescription = event.errorDetails
        sessions[sessionId]?.subagents.removeAll()
        if let msg = event.lastAssistantMessage, !msg.isEmpty {
            sessions[sessionId]?.lastAssistantMessage = msg
            sessions[sessionId]?.addRecentMessage(ChatMessage(isUser: false, text: msg))
        }
        effects.append(.enqueueCompletion(sessionId: sessionId))

    // ── Tool lifecycle ─────────────────────────────────────────────
    case "PreToolUse":
        // Schema: { tool_name: string, tool_input: any, tool_use_id: string }
        if !isWaiting {
            sessions[sessionId]?.status = .running
            sessions[sessionId]?.currentTool = event.toolName
            sessions[sessionId]?.toolDescription = event.toolDescription
        }

    case "PostToolUse":
        // Schema: { tool_name: string, tool_input: any, tool_response: any, tool_use_id: string }
        if let tool = sessions[sessionId]?.currentTool {
            let desc = sessions[sessionId]?.toolDescription
            sessions[sessionId]?.recordTool(tool, description: desc, success: true, agentType: nil, maxHistory: maxHistory)
        }
        sessions[sessionId]?.errorStreak = 0
        if !isWaiting {
            sessions[sessionId]?.status = .processing
            sessions[sessionId]?.currentTool = nil
            sessions[sessionId]?.toolDescription = nil
        }

    case "PostToolUseFailure":
        // Schema: { tool_name: string, tool_input: any, error: string, is_interrupt?: bool, tool_use_id: string }
        if let tool = sessions[sessionId]?.currentTool {
            let desc = sessions[sessionId]?.toolDescription
            sessions[sessionId]?.recordTool(tool, description: desc, success: false, agentType: nil, maxHistory: maxHistory)
        }
        let currentStreak = sessions[sessionId]?.errorStreak ?? 0
        sessions[sessionId]?.errorStreak = currentStreak + 1
        // is_interrupt = user pressed Ctrl+C during tool execution
        if event.isInterrupt {
            sessions[sessionId]?.interrupted = true
        }
        if !isWaiting {
            sessions[sessionId]?.status = .processing
            sessions[sessionId]?.currentTool = nil
            sessions[sessionId]?.toolDescription = nil
        }

    case "PermissionDenied":
        // Schema: { tool_name: string, tool_input: any, reason: string, tool_use_id: string }
        if !isWaiting {
            sessions[sessionId]?.status = .processing
            sessions[sessionId]?.currentTool = nil
            sessions[sessionId]?.toolDescription = nil
        }

    // ── Subagent lifecycle ─────────────────────────────────────────
    case "SubagentStart":
        // Schema: { agent_id: string, agent_type: string }
        if !isWaiting {
            sessions[sessionId]?.status = .running
            sessions[sessionId]?.currentTool = "Agent"
            sessions[sessionId]?.toolDescription = event.agentType
        }

    case "SubagentStop":
        // Schema: { agent_id: string, agent_type: string, last_assistant_message?: string }
        if !isWaiting {
            sessions[sessionId]?.status = .processing
            sessions[sessionId]?.currentTool = nil
            sessions[sessionId]?.toolDescription = nil
        }

    // ── Session lifecycle ──────────────────────────────────────────
    case "SessionStart":
        // Schema: { source: 'startup'|'resume'|'clear'|'compact', model?: string }
        // Reset session — new conversation started.
        effects.append(.stopMonitor(sessionId: sessionId))
        let oldPid = sessions[sessionId]?.cliPid
        sessions[sessionId] = SessionSnapshot(startTime: Date())
        // Re-apply metadata (extractMetadata above wrote to the old snapshot)
        extractMetadata(into: &sessions, sessionId: sessionId, event: event)
        // Carry forward PID if bridge provided it via extractMetadata, else restore old
        if sessions[sessionId]?.cliPid == nil, let pid = oldPid {
            sessions[sessionId]?.cliPid = pid
        }
        // Remove stale sessions sharing the same PID (process started new conversation)
        if let pid = sessions[sessionId]?.cliPid, pid > 0 {
            for (key, existing) in sessions where key != sessionId && existing.cliPid == pid {
                effects.append(.removeSession(sessionId: key))
            }
        }
        effects.append(.tryMonitorSession(sessionId: sessionId))

    case "SessionEnd":
        // Schema: { reason: 'clear'|'resume'|'logout'|'prompt_input_exit'|'other' }
        effects.append(.removeSession(sessionId: sessionId))
        return effects

    // ── Context management ─────────────────────────────────────────
    case "PreCompact":
        // Schema: { trigger: 'manual'|'auto', custom_instructions?: string }
        sessions[sessionId]?.status = .processing
        sessions[sessionId]?.toolDescription = "Compacting context\u{2026}"

    case "PostCompact":
        // Schema: { trigger: 'manual'|'auto', compact_summary: string }
        if !isWaiting {
            sessions[sessionId]?.status = .processing
            sessions[sessionId]?.toolDescription = nil
        }

    // ── Environment changes ────────────────────────────────────────
    case "CwdChanged":
        // Schema: { old_cwd: string, new_cwd: string }
        if let newCwd = event.newCwd, !newCwd.isEmpty {
            sessions[sessionId]?.cwd = newCwd
        }

    case "Notification":
        // Schema: { message: string, title?: string, notification_type: string }
        // Desktop notification — agent wants user attention. Fires AFTER Stop.
        // Don't change session status; session is already idle by this point.
        break

    default:
        break
    }

    sessions[sessionId]?.lastActivity = Date()

    // Ensure process monitor is set up (covers sessions created implicitly)
    if sessions[sessionId]?.cwd != nil {
        effects.append(.tryMonitorSession(sessionId: sessionId))
    }

    // Trigger sound for this event
    effects.append(.playSound(eventName))

    // Note: we no longer auto-switch activeSessionId on every activity event.
    // The active session is only changed by explicit user interaction,
    // permission/question requests, or session start/end.

    return effects
}

// MARK: - Private Helpers

public func extractMetadata(into sessions: inout [String: SessionSnapshot], sessionId: String, event: HookEvent) {
    let m = event.metadata
    if let cwd = m.cwd, !cwd.isEmpty {
        sessions[sessionId]?.cwd = cwd
    } else if sessions[sessionId]?.cwd == nil,
              let roots = m.workspaceRoots,
              let first = roots.first, !first.isEmpty {
        sessions[sessionId]?.cwd = first
    }
    if let model = m.model, !model.isEmpty {
        sessions[sessionId]?.model = model
    }
    if let mode = m.permissionMode {
        sessions[sessionId]?.permissionMode = mode
    }
    // Terminal info (injected by hook script)
    if let app = m.termApp, !app.isEmpty, app != "unknown" {
        sessions[sessionId]?.termApp = app
    }
    if let ses = m.itermSession, !ses.isEmpty {
        sessions[sessionId]?.itermSessionId = ses
    }
    if let tty = m.tty, !tty.isEmpty {
        sessions[sessionId]?.ttyPath = tty
    }
    // Extended terminal info (from native bridge binary)
    if let kitty = m.kittyWindow, !kitty.isEmpty {
        sessions[sessionId]?.kittyWindowId = kitty
    }
    if let pane = m.tmuxPane, !pane.isEmpty {
        sessions[sessionId]?.tmuxPane = pane
    }
    if let tmuxTty = m.tmuxClientTty, !tmuxTty.isEmpty {
        sessions[sessionId]?.tmuxClientTty = tmuxTty
    }
    if let bundle = m.termBundle, !bundle.isEmpty {
        sessions[sessionId]?.termBundleId = bundle
    }
    if let ppid = m.ppid, ppid > 0 {
        sessions[sessionId]?.cliPid = pid_t(ppid)
    }
    if let source = SessionSnapshot.normalizedSupportedSource(m.source) {
        sessions[sessionId]?.source = source
    }
    if let tp = m.transcriptPath, !tp.isEmpty {
        sessions[sessionId]?.transcriptPath = tp
    }
}

/// Handle subagent events. Returns true if the event was consumed.
private func handleSubagentEvent(
    sessions: inout [String: SessionSnapshot],
    sessionId: String,
    agentId: String,
    eventName: String,
    event: HookEvent,
    maxHistory: Int,
    effects: inout [SideEffect]
) -> Bool {
    switch eventName {
    case "SubagentStart":
        let agentType = event.agentType ?? "Agent"
        sessions[sessionId]?.subagents[agentId] = SubagentState(
            agentId: agentId,
            agentType: agentType
        )
        sessions[sessionId]?.lastActivity = Date()
        return true

    case "SubagentStop":
        sessions[sessionId]?.subagents.removeValue(forKey: agentId)
        sessions[sessionId]?.lastActivity = Date()
        return true

    case "PreToolUse":
        sessions[sessionId]?.subagents[agentId]?.status = .running
        sessions[sessionId]?.subagents[agentId]?.currentTool = event.toolName
        sessions[sessionId]?.subagents[agentId]?.toolDescription = event.toolDescription
        sessions[sessionId]?.subagents[agentId]?.lastActivity = Date()
        sessions[sessionId]?.lastActivity = Date()
        return true

    case "PostToolUse":
        if let tool = sessions[sessionId]?.subagents[agentId]?.currentTool {
            let agentType = sessions[sessionId]?.subagents[agentId]?.agentType
            let desc = sessions[sessionId]?.subagents[agentId]?.toolDescription
            sessions[sessionId]?.recordTool(tool, description: desc, success: true, agentType: agentType, maxHistory: maxHistory)
        }
        sessions[sessionId]?.subagents[agentId]?.status = .processing
        sessions[sessionId]?.subagents[agentId]?.currentTool = nil
        sessions[sessionId]?.subagents[agentId]?.toolDescription = nil
        sessions[sessionId]?.subagents[agentId]?.lastActivity = Date()
        sessions[sessionId]?.lastActivity = Date()
        return true

    case "PostToolUseFailure":
        if let tool = sessions[sessionId]?.subagents[agentId]?.currentTool {
            let agentType = sessions[sessionId]?.subagents[agentId]?.agentType
            let desc = sessions[sessionId]?.subagents[agentId]?.toolDescription
            sessions[sessionId]?.recordTool(tool, description: desc, success: false, agentType: agentType, maxHistory: maxHistory)
        }
        sessions[sessionId]?.subagents[agentId]?.status = .processing
        sessions[sessionId]?.subagents[agentId]?.currentTool = nil
        sessions[sessionId]?.subagents[agentId]?.toolDescription = nil
        sessions[sessionId]?.lastActivity = Date()
        return true

    default:
        return false  // Fall through to normal session handling
    }
}

// MARK: - Token Usage

public struct TokenUsage: Sendable, Codable, Equatable {
    public var inputTokens: Int = 0
    public var outputTokens: Int = 0
    public var cacheReadTokens: Int = 0
    public var cacheCreationTokens: Int = 0
    public var costUSD: Double = 0

    /// Context window usage = input + cache (matches CC's context percentage calculation)
    public var totalTokens: Int { inputTokens + cacheReadTokens + cacheCreationTokens }

    public var formattedTotal: String {
        formatTokenCount(totalTokens)
    }

    public var formattedInput: String { formatTokenCount(inputTokens) }
    public var formattedOutput: String { formatTokenCount(outputTokens) }
    public var formattedCache: String { formatTokenCount(cacheReadTokens) }

    public var formattedCost: String? {
        guard costUSD > 0 else { return nil }
        if costUSD < 0.01 { return String(format: "<$0.01") }
        return String(format: "$%.2f", costUSD)
    }

    public init() {}
}

private func formatTokenCount(_ count: Int) -> String {
    if count < 1_000 { return "\(count)" }
    if count < 1_000_000 {
        let k = Double(count) / 1_000
        return k < 10 ? String(format: "%.1fk", k) : String(format: "%.0fk", k)
    }
    let m = Double(count) / 1_000_000
    return m < 10 ? String(format: "%.1fM", m) : String(format: "%.0fM", m)
}
