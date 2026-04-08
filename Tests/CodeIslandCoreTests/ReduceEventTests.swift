import Testing
import Foundation
@testable import CodeIslandCore

@Suite struct ReduceEventTests {

    // MARK: - Helper

    private func makeEvent(_ json: [String: Any]) -> HookEvent {
        let data = try! JSONSerialization.data(withJSONObject: json)
        return HookEvent(from: data)!
    }

    // MARK: - Session auto-creation

    @Test func sessionIsCreatedAutomaticallyForUnknownSessionId() {
        var sessions: [String: SessionSnapshot] = [:]
        let event = makeEvent(["hook_event_name": "Notification", "session_id": "new-session"])
        _ = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)
        #expect(sessions["new-session"] != nil)
    }

    @Test func missingSessionIdUsesDefaultKey() {
        var sessions: [String: SessionSnapshot] = [:]
        let event = makeEvent(["hook_event_name": "Notification"])
        _ = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)
        #expect(sessions["default"] != nil)
    }

    // MARK: - Metadata extraction

    @Test func metadataExtractsCwdModelAndTermInfo() {
        var sessions: [String: SessionSnapshot] = [:]
        let event = makeEvent([
            "hook_event_name": "Notification",
            "session_id": "s1",
            "cwd": "/home/user/project",
            "model": "claude-sonnet-4-6",
            "permission_mode": "default",
            "_term_app": "iTerm2",
            "_iterm_session": "iterm-abc",
            "_tty": "/dev/ttys001",
            "_term_bundle": "com.googlecode.iterm2",
            "_ppid": 12345,
        ])
        _ = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)
        let s = sessions["s1"]!
        #expect(s.cwd == "/home/user/project")
        #expect(s.model == "claude-sonnet-4-6")
        #expect(s.permissionMode == "default")
        #expect(s.termApp == "iTerm2")
        #expect(s.itermSessionId == "iterm-abc")
        #expect(s.ttyPath == "/dev/ttys001")
        #expect(s.termBundleId == "com.googlecode.iterm2")
        #expect(s.cliPid == 12345)
    }

    @Test func metadataFallsBackToWorkspaceRootsWhenNoCwd() {
        var sessions: [String: SessionSnapshot] = [:]
        let event = makeEvent([
            "hook_event_name": "Notification",
            "session_id": "s1",
            "workspace_roots": ["/workspace/root"],
        ])
        _ = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)
        #expect(sessions["s1"]?.cwd == "/workspace/root")
    }

    // MARK: - UserPromptSubmit

    @Test func userPromptSubmitSetsProcessingAndStoresPrompt() {
        var sessions: [String: SessionSnapshot] = [:]
        let event = makeEvent([
            "hook_event_name": "UserPromptSubmit",
            "session_id": "s1",
            "prompt": "hello world",
        ])
        let effects = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)
        #expect(sessions["s1"]?.status == .processing)
        #expect(sessions["s1"]?.lastUserPrompt == "hello world")
        #expect(sessions["s1"]?.currentTool == nil)
        #expect(sessions["s1"]?.lastAssistantMessage == nil)
        #expect(sessions["s1"]?.interrupted == false)
        #expect(effects.contains(.playSound("UserPromptSubmit")))
    }

    @Test func userPromptSubmitAddsUserMessageToRecentMessages() {
        var sessions: [String: SessionSnapshot] = [:]
        let event = makeEvent([
            "hook_event_name": "UserPromptSubmit",
            "session_id": "s1",
            "prompt": "what is 2+2",
        ])
        _ = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)
        let messages = sessions["s1"]?.recentMessages ?? []
        #expect(messages.count == 1)
        #expect(messages.last?.isUser == true)
        #expect(messages.last?.text == "what is 2+2")
    }

    @Test func userPromptSubmitReplacesTrailingUserMessage() {
        var sessions: [String: SessionSnapshot] = [:]
        // Seed an existing user message
        sessions["s1"] = SessionSnapshot()
        sessions["s1"]?.recentMessages = [ChatMessage(isUser: true, text: "old prompt")]

        let event = makeEvent([
            "hook_event_name": "UserPromptSubmit",
            "session_id": "s1",
            "prompt": "new prompt",
        ])
        _ = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)
        let messages = sessions["s1"]?.recentMessages ?? []
        // Old trailing user message should be replaced, not appended
        #expect(messages.count == 1)
        #expect(messages.last?.text == "new prompt")
    }

    @Test func userPromptSubmitParsesTaskNotification() {
        var sessions: [String: SessionSnapshot] = [:]
        let xml = "<task-notification><task-id>t1</task-id><status>completed</status><summary>Build done</summary></task-notification>"
        let event = makeEvent([
            "hook_event_name": "UserPromptSubmit",
            "session_id": "s1",
            "prompt": xml,
        ])
        _ = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)
        #expect(sessions["s1"]?.lastUserPrompt == "Build done")
        let msgs = sessions["s1"]?.recentMessages ?? []
        #expect(msgs.last?.isTaskNotification == true)
    }

    // MARK: - Stop

    @Test func stopSetsIdleAndEnqueuesCompletion() {
        var sessions: [String: SessionSnapshot] = [:]
        sessions["s1"] = SessionSnapshot()
        sessions["s1"]?.status = .running
        sessions["s1"]?.currentTool = "Bash"

        let event = makeEvent([
            "hook_event_name": "Stop",
            "session_id": "s1",
        ])
        let effects = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)
        #expect(sessions["s1"]?.status == .idle)
        #expect(sessions["s1"]?.currentTool == nil)
        #expect(effects.contains(.enqueueCompletion(sessionId: "s1")))
    }

    @Test func stopStoresLastAssistantMessage() {
        var sessions: [String: SessionSnapshot] = [:]
        let event = makeEvent([
            "hook_event_name": "Stop",
            "session_id": "s1",
            "last_assistant_message": "Here is the result",
        ])
        _ = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)
        #expect(sessions["s1"]?.lastAssistantMessage == "Here is the result")
        let msgs = sessions["s1"]?.recentMessages ?? []
        #expect(msgs.last?.isUser == false)
        #expect(msgs.last?.text == "Here is the result")
    }

    @Test func stopClearsSubagents() {
        var sessions: [String: SessionSnapshot] = [:]
        sessions["s1"] = SessionSnapshot()
        sessions["s1"]?.subagents["agent-1"] = SubagentState(agentId: "agent-1", agentType: "researcher")

        let event = makeEvent(["hook_event_name": "Stop", "session_id": "s1"])
        _ = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)
        #expect(sessions["s1"]?.subagents.isEmpty == true)
    }

    // MARK: - StopFailure

    @Test func stopFailureSetsIdleAndEnqueuesCompletion() {
        var sessions: [String: SessionSnapshot] = [:]
        sessions["s1"] = SessionSnapshot()
        sessions["s1"]?.status = .running

        let event = makeEvent([
            "hook_event_name": "StopFailure",
            "session_id": "s1",
            "error_details": "Rate limit exceeded",
        ])
        let effects = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)
        #expect(sessions["s1"]?.status == .idle)
        #expect(sessions["s1"]?.toolDescription == "Rate limit exceeded")
        #expect(effects.contains(.enqueueCompletion(sessionId: "s1")))
    }

    @Test func stopFailureStoresLastAssistantMessage() {
        var sessions: [String: SessionSnapshot] = [:]
        let event = makeEvent([
            "hook_event_name": "StopFailure",
            "session_id": "s1",
            "last_assistant_message": "Partial response",
        ])
        _ = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)
        #expect(sessions["s1"]?.lastAssistantMessage == "Partial response")
    }

    // MARK: - PreToolUse

    @Test func preToolUseSetsRunningAndStoresTool() {
        var sessions: [String: SessionSnapshot] = [:]
        let event = makeEvent([
            "hook_event_name": "PreToolUse",
            "session_id": "s1",
            "tool_name": "Bash",
            "tool_input": ["command": "ls -la"],
        ])
        let effects = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)
        #expect(sessions["s1"]?.status == .running)
        #expect(sessions["s1"]?.currentTool == "Bash")
        #expect(effects.contains(.playSound("PreToolUse")))
    }

    @Test func preToolUsePreservesWaitingApprovalState() {
        var sessions: [String: SessionSnapshot] = [:]
        sessions["s1"] = SessionSnapshot()
        sessions["s1"]?.status = .waitingApproval

        let event = makeEvent([
            "hook_event_name": "PreToolUse",
            "session_id": "s1",
            "tool_name": "Bash",
        ])
        _ = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)
        #expect(sessions["s1"]?.status == .waitingApproval)
    }

    @Test func preToolUsePreservesWaitingQuestionState() {
        var sessions: [String: SessionSnapshot] = [:]
        sessions["s1"] = SessionSnapshot()
        sessions["s1"]?.status = .waitingQuestion

        let event = makeEvent([
            "hook_event_name": "PreToolUse",
            "session_id": "s1",
            "tool_name": "Read",
        ])
        _ = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)
        #expect(sessions["s1"]?.status == .waitingQuestion)
    }

    // MARK: - PostToolUse

    @Test func postToolUseRecordsHistoryAndClearsTool() {
        var sessions: [String: SessionSnapshot] = [:]
        sessions["s1"] = SessionSnapshot()
        sessions["s1"]?.status = .running
        sessions["s1"]?.currentTool = "Bash"
        sessions["s1"]?.errorStreak = 3

        let event = makeEvent([
            "hook_event_name": "PostToolUse",
            "session_id": "s1",
            "tool_name": "Bash",
        ])
        _ = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)
        #expect(sessions["s1"]?.status == .processing)
        #expect(sessions["s1"]?.currentTool == nil)
        #expect(sessions["s1"]?.errorStreak == 0)
        #expect(sessions["s1"]?.toolHistory.count == 1)
        #expect(sessions["s1"]?.toolHistory.first?.tool == "Bash")
        #expect(sessions["s1"]?.toolHistory.first?.success == true)
    }

    @Test func postToolUsePreservesWaitingState() {
        var sessions: [String: SessionSnapshot] = [:]
        sessions["s1"] = SessionSnapshot()
        sessions["s1"]?.status = .waitingApproval
        sessions["s1"]?.currentTool = "Write"

        let event = makeEvent([
            "hook_event_name": "PostToolUse",
            "session_id": "s1",
            "tool_name": "Write",
        ])
        _ = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)
        #expect(sessions["s1"]?.status == .waitingApproval)
    }

    // MARK: - PostToolUseFailure

    @Test func postToolUseFailureIncrementsErrorStreak() {
        var sessions: [String: SessionSnapshot] = [:]
        sessions["s1"] = SessionSnapshot()
        sessions["s1"]?.currentTool = "Bash"
        sessions["s1"]?.errorStreak = 1

        let event = makeEvent([
            "hook_event_name": "PostToolUseFailure",
            "session_id": "s1",
            "tool_name": "Bash",
        ])
        _ = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)
        #expect(sessions["s1"]?.errorStreak == 2)
        #expect(sessions["s1"]?.status == .processing)
        #expect(sessions["s1"]?.toolHistory.first?.success == false)
    }

    @Test func postToolUseFailureWithIsInterruptSetsInterrupted() {
        var sessions: [String: SessionSnapshot] = [:]
        sessions["s1"] = SessionSnapshot()
        sessions["s1"]?.currentTool = "Bash"

        let event = makeEvent([
            "hook_event_name": "PostToolUseFailure",
            "session_id": "s1",
            "tool_name": "Bash",
            "is_interrupt": true,
        ])
        _ = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)
        #expect(sessions["s1"]?.interrupted == true)
    }

    @Test func postToolUseFailurePreservesWaitingState() {
        var sessions: [String: SessionSnapshot] = [:]
        sessions["s1"] = SessionSnapshot()
        sessions["s1"]?.status = .waitingApproval

        let event = makeEvent([
            "hook_event_name": "PostToolUseFailure",
            "session_id": "s1",
            "tool_name": "Bash",
        ])
        _ = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)
        #expect(sessions["s1"]?.status == .waitingApproval)
    }

    // MARK: - PermissionDenied

    @Test func permissionDeniedClearsToolAndSetsProcessing() {
        var sessions: [String: SessionSnapshot] = [:]
        sessions["s1"] = SessionSnapshot()
        sessions["s1"]?.status = .running
        sessions["s1"]?.currentTool = "Bash"

        let event = makeEvent([
            "hook_event_name": "PermissionDenied",
            "session_id": "s1",
            "tool_name": "Bash",
        ])
        _ = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)
        #expect(sessions["s1"]?.status == .processing)
        #expect(sessions["s1"]?.currentTool == nil)
    }

    @Test func permissionDeniedPreservesWaitingApprovalState() {
        var sessions: [String: SessionSnapshot] = [:]
        sessions["s1"] = SessionSnapshot()
        sessions["s1"]?.status = .waitingApproval

        let event = makeEvent([
            "hook_event_name": "PermissionDenied",
            "session_id": "s1",
            "tool_name": "Bash",
        ])
        _ = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)
        #expect(sessions["s1"]?.status == .waitingApproval)
    }

    // MARK: - SubagentStart

    @Test func subagentStartWithAgentIdCreatesSubagentEntry() {
        var sessions: [String: SessionSnapshot] = [:]
        // agent_id is present: goes through handleSubagentEvent
        let event = makeEvent([
            "hook_event_name": "SubagentStart",
            "session_id": "s1",
            "agent_id": "agent-42",
            "agent_type": "researcher",
        ])
        _ = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)
        let subagent = sessions["s1"]?.subagents["agent-42"]
        #expect(subagent != nil)
        #expect(subagent?.agentType == "researcher")
        #expect(subagent?.status == .running)
    }

    @Test func subagentStartWithoutAgentIdSetsRunningAndAgentTool() {
        var sessions: [String: SessionSnapshot] = [:]
        let event = makeEvent([
            "hook_event_name": "SubagentStart",
            "session_id": "s1",
            "agent_type": "executor",
            // no agent_id — falls through to main session handling
        ])
        _ = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)
        #expect(sessions["s1"]?.status == .running)
        #expect(sessions["s1"]?.currentTool == "Agent")
    }

    // MARK: - SubagentStop

    @Test func subagentStopWithAgentIdRemovesSubagentEntry() {
        var sessions: [String: SessionSnapshot] = [:]
        sessions["s1"] = SessionSnapshot()
        sessions["s1"]?.subagents["agent-42"] = SubagentState(agentId: "agent-42", agentType: "researcher")

        let event = makeEvent([
            "hook_event_name": "SubagentStop",
            "session_id": "s1",
            "agent_id": "agent-42",
        ])
        _ = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)
        #expect(sessions["s1"]?.subagents["agent-42"] == nil)
    }

    @Test func subagentStopWithoutAgentIdSetsProcessingAndClearsTool() {
        var sessions: [String: SessionSnapshot] = [:]
        sessions["s1"] = SessionSnapshot()
        sessions["s1"]?.status = .running
        sessions["s1"]?.currentTool = "Agent"

        let event = makeEvent([
            "hook_event_name": "SubagentStop",
            "session_id": "s1",
            // no agent_id
        ])
        _ = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)
        #expect(sessions["s1"]?.status == .processing)
        #expect(sessions["s1"]?.currentTool == nil)
    }

    // MARK: - SessionStart

    @Test func sessionStartResetsSessionAndReturnsExpectedEffects() {
        var sessions: [String: SessionSnapshot] = [:]
        sessions["s1"] = SessionSnapshot()
        sessions["s1"]?.status = .running
        sessions["s1"]?.currentTool = "Bash"
        sessions["s1"]?.lastUserPrompt = "old prompt"

        let event = makeEvent([
            "hook_event_name": "SessionStart",
            "session_id": "s1",
            "cwd": "/new/project",
        ])
        let effects = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)
        // Session is reset
        #expect(sessions["s1"]?.status == .idle)
        #expect(sessions["s1"]?.currentTool == nil)
        #expect(sessions["s1"]?.lastUserPrompt == nil)
        // Effects include stopMonitor and tryMonitorSession
        #expect(effects.contains(.stopMonitor(sessionId: "s1")))
        #expect(effects.contains(.tryMonitorSession(sessionId: "s1")))
    }

    @Test func sessionStartRemovesStaleSessionsWithSamePid() {
        var sessions: [String: SessionSnapshot] = [:]
        sessions["old-session"] = SessionSnapshot()
        sessions["old-session"]?.cliPid = 9999

        let event = makeEvent([
            "hook_event_name": "SessionStart",
            "session_id": "new-session",
            "_ppid": 9999,
        ])
        let effects = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)
        #expect(effects.contains(.removeSession(sessionId: "old-session")))
    }

    // MARK: - SessionEnd

    @Test func sessionEndReturnsRemoveSessionEffect() {
        var sessions: [String: SessionSnapshot] = [:]
        sessions["s1"] = SessionSnapshot()

        let event = makeEvent([
            "hook_event_name": "SessionEnd",
            "session_id": "s1",
        ])
        let effects = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)
        #expect(effects.contains(.removeSession(sessionId: "s1")))
        // Should only return removeSession, nothing else
        #expect(effects.count == 1)
    }

    // MARK: - PreCompact

    @Test func preCompactSetsProcessingWithCompactingDescription() {
        var sessions: [String: SessionSnapshot] = [:]
        let event = makeEvent([
            "hook_event_name": "PreCompact",
            "session_id": "s1",
        ])
        _ = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)
        #expect(sessions["s1"]?.status == .processing)
        #expect(sessions["s1"]?.toolDescription == "Compacting context\u{2026}")
    }

    // MARK: - PostCompact

    @Test func postCompactSetsProcessingAndClearsDescription() {
        var sessions: [String: SessionSnapshot] = [:]
        sessions["s1"] = SessionSnapshot()
        sessions["s1"]?.toolDescription = "Compacting context\u{2026}"

        let event = makeEvent([
            "hook_event_name": "PostCompact",
            "session_id": "s1",
        ])
        _ = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)
        #expect(sessions["s1"]?.status == .processing)
        #expect(sessions["s1"]?.toolDescription == nil)
    }

    @Test func postCompactPreservesWaitingState() {
        var sessions: [String: SessionSnapshot] = [:]
        sessions["s1"] = SessionSnapshot()
        sessions["s1"]?.status = .waitingQuestion

        let event = makeEvent([
            "hook_event_name": "PostCompact",
            "session_id": "s1",
        ])
        _ = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)
        #expect(sessions["s1"]?.status == .waitingQuestion)
    }

    // MARK: - CwdChanged

    @Test func cwdChangedUpdatesCwd() {
        var sessions: [String: SessionSnapshot] = [:]
        sessions["s1"] = SessionSnapshot()
        sessions["s1"]?.cwd = "/old/path"

        let event = makeEvent([
            "hook_event_name": "CwdChanged",
            "session_id": "s1",
            "new_cwd": "/new/path",
        ])
        _ = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)
        #expect(sessions["s1"]?.cwd == "/new/path")
    }

    @Test func cwdChangedIgnoresEmptyNewCwd() {
        var sessions: [String: SessionSnapshot] = [:]
        sessions["s1"] = SessionSnapshot()
        sessions["s1"]?.cwd = "/existing/path"

        let event = makeEvent([
            "hook_event_name": "CwdChanged",
            "session_id": "s1",
            "new_cwd": "",
        ])
        _ = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)
        #expect(sessions["s1"]?.cwd == "/existing/path")
    }

    // MARK: - Notification

    @Test func notificationIsNoOpOnStatus() {
        var sessions: [String: SessionSnapshot] = [:]
        sessions["s1"] = SessionSnapshot()
        sessions["s1"]?.status = .idle

        let event = makeEvent([
            "hook_event_name": "Notification",
            "session_id": "s1",
            "message": "Agent needs attention",
        ])
        _ = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)
        #expect(sessions["s1"]?.status == .idle)
    }

    // MARK: - Subagent tool routing

    @Test func preToolUseWithAgentIdUpdatesSubagentNotMainSession() {
        var sessions: [String: SessionSnapshot] = [:]
        sessions["s1"] = SessionSnapshot()
        sessions["s1"]?.status = .processing
        sessions["s1"]?.subagents["agent-1"] = SubagentState(agentId: "agent-1", agentType: "worker")

        let event = makeEvent([
            "hook_event_name": "PreToolUse",
            "session_id": "s1",
            "agent_id": "agent-1",
            "tool_name": "Read",
            "tool_input": ["file_path": "/some/file.txt"],
        ])
        _ = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)
        // Main session status unchanged
        #expect(sessions["s1"]?.status == .processing)
        // Subagent updated
        #expect(sessions["s1"]?.subagents["agent-1"]?.status == .running)
        #expect(sessions["s1"]?.subagents["agent-1"]?.currentTool == "Read")
    }

    @Test func postToolUseWithAgentIdRecordsToolInMainHistory() {
        var sessions: [String: SessionSnapshot] = [:]
        sessions["s1"] = SessionSnapshot()
        sessions["s1"]?.subagents["agent-1"] = SubagentState(agentId: "agent-1", agentType: "worker")
        sessions["s1"]?.subagents["agent-1"]?.currentTool = "Bash"
        sessions["s1"]?.subagents["agent-1"]?.status = .running

        let event = makeEvent([
            "hook_event_name": "PostToolUse",
            "session_id": "s1",
            "agent_id": "agent-1",
            "tool_name": "Bash",
        ])
        _ = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)
        // Tool recorded in main session's tool history with agentType
        #expect(sessions["s1"]?.toolHistory.count == 1)
        #expect(sessions["s1"]?.toolHistory.first?.agentType == "worker")
        #expect(sessions["s1"]?.toolHistory.first?.success == true)
        // Subagent moves to processing
        #expect(sessions["s1"]?.subagents["agent-1"]?.status == .processing)
    }

    // MARK: - Tool history max limit

    @Test func toolHistoryRespectsMaxHistory() {
        var sessions: [String: SessionSnapshot] = [:]
        sessions["s1"] = SessionSnapshot()

        for i in 0..<5 {
            sessions["s1"]?.currentTool = "Tool\(i)"
            let event = makeEvent([
                "hook_event_name": "PostToolUse",
                "session_id": "s1",
                "tool_name": "Tool\(i)",
            ])
            _ = reduceEvent(sessions: &sessions, event: event, maxHistory: 3)
        }
        #expect(sessions["s1"]?.toolHistory.count == 3)
    }

    // MARK: - Tracking key resolution (same session_id, different PIDs)

    @Test func resolveTrackingKeyReturnsRawSessionIdWhenNoPidConflict() {
        let sessions: [String: SessionSnapshot] = [:]
        let event = makeEvent([
            "hook_event_name": "PreToolUse",
            "session_id": "s1",
            "_ppid": 100,
            "tool_name": "Bash",
        ])
        let key = resolveTrackingKey(sessions: sessions, event: event)
        #expect(key == "s1")
    }

    @Test func resolveTrackingKeyForkWhenDifferentPid() {
        var sessions: [String: SessionSnapshot] = [:]
        sessions["s1"] = SessionSnapshot()
        sessions["s1"]?.cliPid = 100

        let event = makeEvent([
            "hook_event_name": "PreToolUse",
            "session_id": "s1",
            "_ppid": 200,
            "tool_name": "Bash",
        ])
        let key = resolveTrackingKey(sessions: sessions, event: event)
        #expect(key == "s1/200")
    }

    @Test func resolveTrackingKeyReusesExistingPidKey() {
        var sessions: [String: SessionSnapshot] = [:]
        sessions["s1"] = SessionSnapshot()
        sessions["s1"]?.cliPid = 100
        sessions["s1/200"] = SessionSnapshot()
        sessions["s1/200"]?.cliPid = 200

        let event = makeEvent([
            "hook_event_name": "PreToolUse",
            "session_id": "s1",
            "_ppid": 200,
            "tool_name": "Bash",
        ])
        let key = resolveTrackingKey(sessions: sessions, event: event)
        #expect(key == "s1/200")
    }

    @Test func twoProcessesSameSessionIdCreateSeparateEntries() {
        var sessions: [String: SessionSnapshot] = [:]

        // Process A (PID 100) sends first event
        let eventA = makeEvent([
            "hook_event_name": "UserPromptSubmit",
            "session_id": "shared",
            "_ppid": 100,
            "prompt": "from A",
        ])
        let keyA = resolveTrackingKey(sessions: sessions, event: eventA)
        _ = reduceEvent(sessions: &sessions, event: eventA, trackingKey: keyA, maxHistory: 10)

        // Process B (PID 200) sends event with same session_id
        let eventB = makeEvent([
            "hook_event_name": "UserPromptSubmit",
            "session_id": "shared",
            "_ppid": 200,
            "prompt": "from B",
        ])
        let keyB = resolveTrackingKey(sessions: sessions, event: eventB)
        _ = reduceEvent(sessions: &sessions, event: eventB, trackingKey: keyB, maxHistory: 10)

        // Two separate entries
        #expect(keyA == "shared")
        #expect(keyB == "shared/200")
        #expect(sessions.count == 2)
        #expect(sessions["shared"]?.lastUserPrompt == "from A")
        #expect(sessions["shared/200"]?.lastUserPrompt == "from B")
        #expect(sessions["shared"]?.cliPid == 100)
        #expect(sessions["shared/200"]?.cliPid == 200)
    }

    @Test func samePidSameSessionIdDoesNotFork() {
        var sessions: [String: SessionSnapshot] = [:]

        let event1 = makeEvent([
            "hook_event_name": "UserPromptSubmit",
            "session_id": "s1",
            "_ppid": 100,
            "prompt": "first",
        ])
        let key1 = resolveTrackingKey(sessions: sessions, event: event1)
        _ = reduceEvent(sessions: &sessions, event: event1, trackingKey: key1, maxHistory: 10)

        let event2 = makeEvent([
            "hook_event_name": "PreToolUse",
            "session_id": "s1",
            "_ppid": 100,
            "tool_name": "Bash",
        ])
        let key2 = resolveTrackingKey(sessions: sessions, event: event2)
        _ = reduceEvent(sessions: &sessions, event: event2, trackingKey: key2, maxHistory: 10)

        #expect(key1 == "s1")
        #expect(key2 == "s1")
        #expect(sessions.count == 1)
    }

    // MARK: - Effects structure for common events

    @Test func eventWithCwdAppendsTryMonitorSessionEffect() {
        var sessions: [String: SessionSnapshot] = [:]
        let event = makeEvent([
            "hook_event_name": "PreToolUse",
            "session_id": "s1",
            "tool_name": "Bash",
            "cwd": "/my/project",
        ])
        let effects = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)
        #expect(effects.contains(.tryMonitorSession(sessionId: "s1")))
    }

    @Test func eventWithoutCwdDoesNotAppendTryMonitorSessionEffect() {
        var sessions: [String: SessionSnapshot] = [:]
        // No cwd in event, session starts with no cwd
        let event = makeEvent([
            "hook_event_name": "Notification",
            "session_id": "s1",
        ])
        let effects = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)
        #expect(!effects.contains(.tryMonitorSession(sessionId: "s1")))
    }
}
