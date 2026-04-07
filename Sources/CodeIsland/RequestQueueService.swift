import SwiftUI
import CodeIslandCore

@MainActor
@Observable
final class RequestQueueService {
    private(set) var permissionQueue: [PermissionRequest] = []
    private(set) var questionQueue: [QuestionRequest] = []

    var pendingPermission: PermissionRequest? { permissionQueue.first }
    var pendingQuestion: QuestionRequest? { questionQueue.first }

    // Callbacks for state mutations
    var onSurfaceChange: ((IslandSurface) -> Void)?
    var onActiveSessionChange: ((String) -> Void)?
    var onSessionStatusChange: ((String, AgentStatus, String?, String?) -> Void)?
    var onPlaySound: ((String) -> Void)?
    var onActiveSessionBestChange: ((String?) -> Void)?

    // MARK: - Permission Queue

    func enqueuePermission(request: PermissionRequest) {
        let sessionId = request.event.sessionId ?? "default"

        // Clear any pending questions for THIS session (mutually exclusive within a session)
        drainQuestions(forSession: sessionId)

        onSessionStatusChange?(sessionId, .waitingApproval, request.event.toolName, request.event.toolDescription)
        permissionQueue.append(request)

        if permissionQueue.count == 1 {
            onActiveSessionChange?(sessionId)
            onSurfaceChange?(.approvalCard(sessionId: sessionId))
            onPlaySound?("PermissionRequest")
        }
    }

    func approve(always: Bool) -> String? {
        guard !permissionQueue.isEmpty else { return nil }
        let pending = permissionQueue.removeFirst()
        let responseData: Data
        if always {
            let toolName = pending.event.toolName ?? ""
            let obj: [String: Any] = [
                "hookSpecificOutput": [
                    "hookEventName": "PermissionRequest",
                    "decision": [
                        "behavior": "allow",
                        "updatedPermissions": [[
                            "type": "addRules",
                            "rules": [["toolName": toolName, "ruleContent": "*"]],
                            "behavior": "allow",
                            "destination": "session"
                        ]]
                    ] as [String: Any]
                ] as [String: Any]
            ]
            responseData = (try? JSONSerialization.data(withJSONObject: obj)) ?? HookResponse.empty
        } else {
            responseData = HookResponse.permission(.allow)
        }
        pending.continuation.resume(returning: responseData)
        return pending.event.sessionId ?? "default"
    }

    func deny() -> String? {
        guard !permissionQueue.isEmpty else { return nil }
        let pending = permissionQueue.removeFirst()
        pending.continuation.resume(returning: HookResponse.permission(.deny))
        return pending.event.sessionId ?? "default"
    }

    // MARK: - Question Queue

    func enqueueQuestion(request: QuestionRequest) {
        let sessionId = request.event.sessionId ?? "default"
        drainPermissions(forSession: sessionId)

        onSessionStatusChange?(sessionId, .waitingQuestion, nil, nil)
        questionQueue.append(request)

        if questionQueue.count == 1 {
            onActiveSessionChange?(sessionId)
            onSurfaceChange?(.questionCard(sessionId: sessionId))
            onPlaySound?("PermissionRequest")
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
        return pending.event.sessionId ?? "default"
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
        return pending.event.sessionId ?? "default"
    }

    // MARK: - Drain

    func drainPermissions(forSession sessionId: String) {
        permissionQueue.removeAll { item in
            guard item.event.sessionId == sessionId else { return false }
            item.continuation.resume(returning: HookResponse.permission(.deny))
            return true
        }
    }

    func drainQuestions(forSession sessionId: String) {
        questionQueue.removeAll { item in
            guard item.event.sessionId == sessionId else { return false }
            item.continuation.resume(returning: HookResponse.empty)
            return true
        }
    }

    func drainAll(forSession sessionId: String) {
        drainQuestions(forSession: sessionId)
        drainPermissions(forSession: sessionId)
    }

    // MARK: - Navigation

    /// Show the next pending item or collapse. Returns the new surface.
    @discardableResult
    func showNextPending() -> IslandSurface {
        if let next = permissionQueue.first {
            let sid = next.event.sessionId ?? "default"
            onActiveSessionChange?(sid)
            let surface = IslandSurface.approvalCard(sessionId: sid)
            onSurfaceChange?(surface)
            return surface
        } else if let next = questionQueue.first {
            let sid = next.event.sessionId ?? "default"
            onActiveSessionChange?(sid)
            let surface = IslandSurface.questionCard(sessionId: sid)
            onSurfaceChange?(surface)
            return surface
        }
        return .collapsed
    }
}
