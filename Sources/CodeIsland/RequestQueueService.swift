import SwiftUI
import CodeIslandCore

@MainActor
@Observable
final class RequestQueueService {
    private(set) var permissionQueue: [PermissionRequest] = []
    private(set) var questionQueue: [QuestionRequest] = []

    var pendingPermission: PermissionRequest? { permissionQueue.first }
    var pendingQuestion: QuestionRequest? { questionQueue.first }

    weak var appState: AppState?

    // MARK: - Permission Queue

    func enqueuePermission(request: PermissionRequest) {
        let key = request.trackingKey

        // Clear any pending questions for THIS session (mutually exclusive within a session)
        drainQuestions(forTrackingKey: key)

        if var snap = appState?.sessions[key] {
            snap.status = .waitingApproval
            snap.currentTool = request.event.toolName
            snap.toolDescription = request.event.toolDescription
            appState?.sessions[key] = snap
        }
        permissionQueue.append(request)

        if permissionQueue.count == 1 {
            appState?.activeSessionId = key
            appState?.surface = .approvalCard(sessionId: key)
            SoundManager.shared.handleEvent("PermissionRequest")
        }
    }

    func approve(always: Bool, suggestionIndex: Int? = nil) -> String? {
        guard !permissionQueue.isEmpty else { return nil }
        let pending = permissionQueue.removeFirst()
        let responseData: Data
        if always {
            // Use permission_suggestions from Claude Code if available
            let updatedPermissions: [[String: Any]]
            if let suggestions = pending.event.permissionSuggestions,
               let idx = suggestionIndex, idx < suggestions.count {
                updatedPermissions = [suggestions[idx]]
            } else if let suggestions = pending.event.permissionSuggestions, !suggestions.isEmpty {
                updatedPermissions = [suggestions[0]]
            } else {
                // Fallback: construct addRules for this tool
                let toolName = pending.event.toolName ?? ""
                updatedPermissions = [[
                    "type": "addRules",
                    "rules": [["toolName": toolName, "ruleContent": "*"]],
                    "behavior": "allow",
                    "destination": "session"
                ]]
            }
            let obj: [String: Any] = [
                "hookSpecificOutput": [
                    "hookEventName": "PermissionRequest",
                    "decision": [
                        "behavior": "allow",
                        "updatedPermissions": updatedPermissions
                    ] as [String: Any]
                ] as [String: Any]
            ]
            responseData = (try? JSONSerialization.data(withJSONObject: obj)) ?? HookResponse.empty
        } else {
            responseData = HookResponse.permission(.allow)
        }
        if always, let toolName = pending.event.toolName {
            appState?.addAutoApprovedTool(toolName, forSession: pending.trackingKey)
        }
        pending.continuation.resume(returning: responseData)
        return pending.trackingKey
    }

    func deny() -> String? {
        guard !permissionQueue.isEmpty else { return nil }
        let pending = permissionQueue.removeFirst()
        pending.continuation.resume(returning: HookResponse.permission(.deny))
        return pending.trackingKey
    }

    // MARK: - Question Queue

    func enqueueQuestion(request: QuestionRequest) {
        let key = request.trackingKey
        drainPermissions(forTrackingKey: key)

        if var snap = appState?.sessions[key] {
            snap.status = .waitingQuestion
            appState?.sessions[key] = snap
        }
        questionQueue.append(request)

        if questionQueue.count == 1 {
            appState?.activeSessionId = key
            appState?.surface = .questionCard(sessionId: key)
            SoundManager.shared.handleEvent("PermissionRequest")
        }
    }

    func answer(_ answer: String) -> String? {
        guard !questionQueue.isEmpty else { return nil }
        let pending = questionQueue.removeFirst()
        let responseData: Data
        if pending.isFromPermission {
            let answerKey = pending.question.header ?? "answer"
            let obj: [String: Any] = [
                "hookSpecificOutput": [
                    "hookEventName": "PermissionRequest",
                    "decision": [
                        "behavior": "allow",
                        "updatedInput": [
                            "answers": [answerKey: answer]
                        ]
                    ] as [String: Any]
                ] as [String: Any]
            ]
            responseData = (try? JSONSerialization.data(withJSONObject: obj)) ?? HookResponse.empty
        } else {
            let obj: [String: Any] = [
                "hookSpecificOutput": [
                    "hookEventName": "Notification",
                    "answer": answer
                ] as [String: Any]
            ]
            responseData = (try? JSONSerialization.data(withJSONObject: obj)) ?? HookResponse.empty
        }
        pending.continuation.resume(returning: responseData)
        return pending.trackingKey
    }

    func skip() -> String? {
        guard !questionQueue.isEmpty else { return nil }
        let pending = questionQueue.removeFirst()
        let responseData: Data
        if pending.isFromPermission {
            responseData = HookResponse.permission(.deny)
        } else {
            let obj: [String: Any] = ["hookSpecificOutput": ["hookEventName": "Notification"]]
            responseData = (try? JSONSerialization.data(withJSONObject: obj)) ?? HookResponse.empty
        }
        pending.continuation.resume(returning: responseData)
        return pending.trackingKey
    }

    // MARK: - Drain

    func drainPermissions(forTrackingKey key: String) {
        permissionQueue.removeAll { item in
            guard item.trackingKey == key else { return false }
            item.continuation.resume(returning: HookResponse.permission(.deny))
            return true
        }
    }

    func drainQuestions(forTrackingKey key: String) {
        questionQueue.removeAll { item in
            guard item.trackingKey == key else { return false }
            item.continuation.resume(returning: HookResponse.empty)
            return true
        }
    }

    func drainAll(forTrackingKey key: String) {
        drainQuestions(forTrackingKey: key)
        drainPermissions(forTrackingKey: key)
    }

    // MARK: - Navigation

    /// Show the next pending item or collapse. Returns the new surface.
    @discardableResult
    func showNextPending() -> IslandSurface {
        if let next = permissionQueue.first {
            let key = next.trackingKey
            appState?.activeSessionId = key
            let surface = IslandSurface.approvalCard(sessionId: key)
            appState?.surface = surface
            return surface
        } else if let next = questionQueue.first {
            let key = next.trackingKey
            appState?.activeSessionId = key
            let surface = IslandSurface.questionCard(sessionId: key)
            appState?.surface = surface
            return surface
        }
        return .collapsed
    }
}
