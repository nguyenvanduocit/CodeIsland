import SwiftUI
import CodeIslandCore

@MainActor
@Observable
final class CompletionQueueService {
    var completionHasBeenEntered = false
    private var queue: [String] = []
    private var autoCollapseTask: Task<Void, Never>?
    /// When the current completion card was first shown — used to enforce minimum display time
    private var completionShownAt: Date?
    private static let minimumDisplayDuration: TimeInterval = 2.0

    // Callbacks for state mutations
    var onSurfaceChange: ((IslandSurface) -> Void)?
    var onActiveSessionChange: ((String) -> Void)?

    // Query callbacks
    var sessionExists: ((String) -> Bool)?
    var getSession: ((String) -> SessionSnapshot?)?
    var currentSurface: (() -> IslandSurface)?

    private var isShowingCompletion: Bool {
        if case .completionCard = currentSurface?() { return true }
        return false
    }

    var justCompletedSessionId: String? {
        if case .completionCard(let id) = currentSurface?() { return id }
        return nil
    }

    func enqueue(_ sessionId: String) {
        // Don't queue duplicates
        if queue.contains(sessionId) || justCompletedSessionId == sessionId { return }

        // If already expanded (user hovering session list, or showing approval/question/completion),
        // just queue — don't interrupt the current view
        if currentSurface?().isExpanded == true {
            queue.append(sessionId)
        } else {
            showCompletion(sessionId)
        }
    }

    func cancel() {
        autoCollapseTask?.cancel()
        queue.removeAll()
        completionShownAt = nil
    }

    /// Whether the completion card has been visible long enough to allow immediate dismiss.
    var hasMetMinimumDisplayTime: Bool {
        guard let shownAt = completionShownAt else { return true }
        return -shownAt.timeIntervalSinceNow >= Self.minimumDisplayDuration
    }

    /// Remaining seconds before minimum display time is met (0 if already met).
    var remainingMinimumDisplayTime: TimeInterval {
        guard let shownAt = completionShownAt else { return 0 }
        return max(0, Self.minimumDisplayDuration + shownAt.timeIntervalSinceNow)
    }

    private func shouldSuppressAppLevel(for sessionId: String) -> Bool {
        guard UserDefaults.standard.bool(forKey: SettingsKey.smartSuppress) else { return false }
        guard let session = getSession?(sessionId),
              (session.termApp != nil || session.termBundleId != nil) else { return false }
        return TerminalVisibilityDetector.isTerminalFrontmostForSession(session)
    }

    private func showCompletion(_ sessionId: String) {
        // Fast path: terminal not even frontmost — show immediately
        guard shouldSuppressAppLevel(for: sessionId) else {
            doShowCompletion(sessionId)
            return
        }

        // Terminal IS frontmost — check tab-level on background thread
        guard let session = getSession?(sessionId) else { return }
        let sessionCopy = session
        Task.detached {
            let tabVisible = TerminalVisibilityDetector.isSessionTabVisible(sessionCopy)
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard self.sessionExists?(sessionId) == true else { return }
                switch self.currentSurface?() {
                case .approvalCard, .questionCard: return
                default: break
                }
                if !tabVisible {
                    withAnimation(NotchAnimation.pop) {
                        self.doShowCompletion(sessionId)
                    }
                }
            }
        }
    }

    private func doShowCompletion(_ sessionId: String) {
        onActiveSessionChange?(sessionId)
        onSurfaceChange?(.completionCard(sessionId: sessionId))
        completionHasBeenEntered = false
        completionShownAt = Date()

        autoCollapseTask?.cancel()
        autoCollapseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            showNextOrCollapse()
        }
    }

    /// Called when user interaction ends (e.g. mouse leaves panel) — show queued completions if any
    func flushIfNeeded() {
        guard !queue.isEmpty else { return }
        if let next = queue.first {
            queue.removeFirst()
            if sessionExists?(next) == true {
                showCompletion(next)
                return
            }
        }
        // If first was invalid, try the rest
        showNextOrCollapse()
    }

    func showNextOrCollapse() {
        while let next = queue.first {
            queue.removeFirst()
            if sessionExists?(next) == true {
                withAnimation(NotchAnimation.pop) {
                    showCompletion(next)
                }
                return
            }
        }
        withAnimation(NotchAnimation.close) {
            onSurfaceChange?(.collapsed)
        }
    }
}
