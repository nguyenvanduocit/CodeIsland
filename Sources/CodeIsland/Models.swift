import Foundation
import CodeIslandCore

struct PermissionRequest {
    let event: HookEvent
    let trackingKey: String
    let continuation: CheckedContinuation<Data, Never>
}

struct QuestionRequest {
    let event: HookEvent
    let trackingKey: String
    let question: QuestionPayload
    let continuation: CheckedContinuation<Data, Never>
    /// true when converted from AskUserQuestion PermissionRequest
    let isFromPermission: Bool

    init(event: HookEvent, trackingKey: String, question: QuestionPayload, continuation: CheckedContinuation<Data, Never>, isFromPermission: Bool = false) {
        self.event = event
        self.trackingKey = trackingKey
        self.question = question
        self.continuation = continuation
        self.isFromPermission = isFromPermission
    }
}
