import SwiftUI
import os.log
import CodeIslandCore

private let log = Logger(subsystem: "com.codeisland", category: "AppState")


@MainActor
@Observable
final class AppState {
    var sessions: [String: SessionSnapshot] = [:]
    var activeSessionId: String?
    var lastInputSessionId: String?

    /// Computed: first item in permission queue (backward compat for UI reads)
    var pendingPermission: PermissionRequest? { requestQueue.pendingPermission }
    /// Computed: first item in question queue
    var pendingQuestion: QuestionRequest? { requestQueue.pendingQuestion }
    /// Preview-only: mock question payload for DebugHarness (no continuation needed)
    var previewQuestionPayload: QuestionPayload?
    var surface: IslandSurface = .collapsed

    var justCompletedSessionId: String? { completionQueue.justCompletedSessionId }

    /// Mouse must enter the panel before auto-collapse is allowed (prevents instant dismiss)
    var completionHasBeenEntered: Bool {
        get { completionQueue.completionHasBeenEntered }
        set { completionQueue.completionHasBeenEntered = newValue }
    }

    private var maxHistory: Int { SettingsManager.shared.maxToolHistory }
    private var cleanupTask: Task<Void, Never>?
    let processMonitor = ProcessMonitorService()
    let completionQueue = CompletionQueueService()
    let requestQueue = RequestQueueService()
    /// When true, side effects (sound, completion animation) are suppressed.
    /// Used during startup restoration to avoid noisy replays.
    private var suppressSideEffects = false

    /// Tools auto-approved via "Always" button, keyed by session tracking key
    private var autoApprovedTools: [String: Set<String>] = [:]

    /// Sessions whose process recently exited — prevents race where late socket events
    /// recreate a session that was just removed by the process monitor.
    /// Entries expire after 30 seconds via cleanup loop.
    private var recentlyExitedSessions: [String: Date] = [:]

    /// Check if a PermissionRequest should be auto-approved.
    /// Sources: session's stored permissionMode, event metadata, local "Always" memory.
    func shouldAutoApprovePermission(event: HookEvent, sessionId: String) -> Bool {
        // 1. Check stored session mode (set by previous events like SessionStart)
        if sessions[sessionId]?.permissionMode == "bypassPermissions" { return true }
        // 2. Check event metadata (current event's mode — always up to date)
        if event.metadata.permissionMode == "bypassPermissions" { return true }
        // 3. Check local "Always" memory for this tool
        if let toolName = event.toolName,
           autoApprovedTools[sessionId]?.contains(toolName) == true { return true }
        return false
    }

    func addAutoApprovedTool(_ toolName: String, forSession sessionId: String) {
        autoApprovedTools[sessionId, default: []].insert(toolName)
    }

    // MARK: - Session lifecycle (single source of truth)

    /// Create session if needed, extract metadata, start monitoring, dedup by PID.
    /// Every code path that may introduce a session MUST go through here.
    /// Returns true if a new session was created.
    @discardableResult
    private func ensureSession(for event: HookEvent, sessionId: String) -> Bool {
        let isNew = sessions[sessionId] == nil
        if isNew {
            // Don't recreate sessions whose process just exited — late socket events
            // can arrive after the process monitor already removed the session.
            if recentlyExitedSessions[sessionId] != nil { return false }
            sessions[sessionId] = SessionSnapshot()
        }
        extractMetadata(into: &sessions, sessionId: sessionId, event: event)
        processMonitor.tryMonitor(sessionId: sessionId, cliPid: sessions[sessionId]?.cliPid)
        // Same process, new session_id → remove the stale entry
        if isNew, let pid = sessions[sessionId]?.cliPid, pid > 0 {
            for (key, _) in sessions where key != sessionId && sessions[key]?.cliPid == pid {
                removeSession(key)
            }
        }
        return isNew
    }

    /// Light-weight state update for auto-approved permission requests.
    /// Extracts metadata without the full reducer pipeline (no sound, no status changes).
    func touchSession(event: HookEvent, sessionId: String) {
        ensureSession(for: event, sessionId: sessionId)
        sessions[sessionId]?.lastActivity = Date()
        refreshDerivedState()
    }

    private func clearAutoApproveState(forSession sessionId: String) {
        autoApprovedTools.removeValue(forKey: sessionId)
    }

    var rotatingSessionId: String?
    var rotatingSession: SessionSnapshot? {
        guard let rid = rotatingSessionId else { return nil }
        return sessions[rid]
    }
    private var rotationTask: Task<Void, Never>?

    private func setupServices() {
        completionQueue.appState = self
        requestQueue.appState = self
    }

    func sessionExists(_ sessionId: String) -> Bool {
        sessions[sessionId] != nil
    }

    private func startCleanupLoop() {
        cleanupTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.cleanupIdleSessions()
            }
        }
    }

    private func refreshTokenUsage() {
        for (sessionId, session) in sessions {
            if let result = SessionUsageReader.readUsage(sessionId: sessionId, cwd: session.cwd) {
                if sessions[sessionId]?.tokenUsage != result.usage {
                    sessions[sessionId]?.tokenUsage = result.usage
                }
                if let model = result.model, sessions[sessionId]?.model != model {
                    sessions[sessionId]?.model = model
                }
            }
        }
    }

    private func cleanupIdleSessions() {
        // Expire recently-exited session markers (30s is plenty to absorb late socket events)
        let cutoff = Date().addingTimeInterval(-30)
        recentlyExitedSessions = recentlyExitedSessions.filter { $0.value > cutoff }

        // Refresh transcript file sizes and token usage
        refreshTokenUsage()
        for (sessionId, session) in sessions {
            guard let path = session.transcriptPath, !path.isEmpty else { continue }
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
               let size = attrs[.size] as? Int64 {
                sessions[sessionId]?.transcriptSize = size
            }
        }

        // Cache running Claude PIDs for this cleanup cycle (avoids repeated scans)
        let claudePids = Set(ProcessScanner.findClaudePids())

        // 1. Kill orphaned Claude processes (terminal closed but process survived)
        // Collect first to avoid mutating during iteration
        var orphaned: [(String, pid_t)] = []
        for (sessionId, session) in sessions {
            guard let pid = processMonitor.pid(for: sessionId) else { continue }
            var info = proc_bsdinfo()
            let ret = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
            if ret > 0 && info.pbi_ppid <= 1 {
                orphaned.append((sessionId, pid))
            }
            _ = session // silence unused warning
        }
        for (sessionId, pid) in orphaned {
            kill(pid, SIGTERM)
            removeSession(sessionId)
        }

        // 2. Remove zombie sessions — detached monitors watching reused PIDs
        for (key, _) in sessions {
            guard processMonitor.isMonitoring(key) else { continue }
            guard let pid = processMonitor.pid(for: key) else { continue }
            if !claudePids.contains(pid) {
                // Monitor is watching a PID that's no longer Claude (reused by another process)
                processMonitor.stop(sessionId: key)
                removeSession(key)
            }
        }

        // 3. Remove sessions whose process is dead
        for (key, session) in sessions {
            if processMonitor.isMonitoring(key) { continue }
            guard let pid = session.cliPid, pid > 0 else {
                removeSession(key)
                continue
            }
            if kill(pid, 0) != 0 {
                removeSession(key)
            } else if !claudePids.contains(pid) {
                removeSession(key)
            } else {
                processMonitor.monitor(sessionId: key, pid: pid)
            }
        }
        // refreshDerivedState is called inside removeSession for each removal
    }

    /// Remove a session, clean up its monitor, and resume any pending continuations.
    /// Every removal path (cleanup timer, process exit, reducer effect) goes through here
    /// so leaked continuations / connections are impossible.
    private func removeSession(_ sessionId: String) {
        // Remember this session just exited — prevents late socket events from recreating it
        recentlyExitedSessions[sessionId] = Date()

        // Resume ALL pending continuations for this session
        drainPermissions(forSession: sessionId)
        drainQuestions(forSession: sessionId)
        clearAutoApproveState(forSession: sessionId)

        if surface.sessionId == sessionId {
            showNextPending()
        }
        sessions.removeValue(forKey: sessionId)
        processMonitor.stop(sessionId: sessionId)
        if activeSessionId == sessionId {
            activeSessionId = mostActiveSessionId()
        }
        startRotationIfNeeded()
        refreshDerivedState()
    }

    // MARK: - Compact bar mascot rotation

    /// Cached sorted active session IDs — refreshed by refreshActiveIds()
    private var cachedActiveIds: [String] = []

    private func refreshActiveIds() {
        cachedActiveIds = sessions.filter { $0.value.status != .idle }.keys.sorted()
    }

    private func startRotationIfNeeded() {
        refreshActiveIds()
        if cachedActiveIds.count > 1 {
            if rotatingSessionId == nil || !cachedActiveIds.contains(rotatingSessionId!) {
                rotatingSessionId = cachedActiveIds.first
            }
            if rotationTask == nil {
                rotationTask = Task { [weak self] in
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(3))
                        self?.rotateToNextSession()
                    }
                }
            }
        } else {
            rotationTask?.cancel()
            rotationTask = nil
            rotatingSessionId = nil
        }
    }

    private func rotateToNextSession() {
        guard cachedActiveIds.count > 1 else {
            rotatingSessionId = nil
            return
        }
        if let current = rotatingSessionId, let idx = cachedActiveIds.firstIndex(of: current) {
            rotatingSessionId = cachedActiveIds[(idx + 1) % cachedActiveIds.count]
        } else {
            rotatingSessionId = cachedActiveIds.first
        }
    }

    private func enqueueCompletion(_ sessionId: String) {
        completionQueue.enqueue(sessionId)
    }

    func cancelCompletionQueue() {
        completionQueue.cancel()
    }

    // Cached derived state (refreshed by refreshDerivedState after session mutations)
    private(set) var status: AgentStatus = .idle
    private(set) var primarySource: String = "claude"
    private(set) var activeSessionCount: Int = 0
    private(set) var totalSessionCount: Int = 0

    var currentTool: String? {
        guard let id = activeSessionId, let s = sessions[id] else { return nil }
        return s.currentTool
    }

    var toolDescription: String? {
        guard let id = activeSessionId, let s = sessions[id] else { return nil }
        return s.toolDescription
    }

    var activeDisplayName: String? {
        guard let id = activeSessionId, let s = sessions[id] else { return nil }
        let displaySessionId = s.displaySessionId(sessionId: id)
        return s.displayTitle(sessionId: displaySessionId)
    }

    var activeModel: String? {
        guard let id = activeSessionId, let s = sessions[id] else { return nil }
        return s.model
    }

    /// Recompute cached status/source/counts from sessions in a single O(n) pass.
    /// Call after any mutation to `sessions` or session status.
    private func refreshDerivedState() {
        let summary = deriveSessionSummary(from: sessions)
        // Only assign when changed (avoids unnecessary @Observable notifications)
        if status != summary.status { status = summary.status }
        if primarySource != summary.primarySource { primarySource = summary.primarySource }
        if activeSessionCount != summary.activeSessionCount { activeSessionCount = summary.activeSessionCount }
        if totalSessionCount != summary.totalSessionCount { totalSessionCount = summary.totalSessionCount }
    }

    private func refreshProviderTitle(for trackedSessionId: String, providerSessionId: String? = nil) {
        guard var snap = sessions[trackedSessionId] else { return }

        let lookupSessionId = providerSessionId ?? snap.providerSessionId ?? trackedSessionId
        if let providerSessionId {
            snap.providerSessionId = providerSessionId
        } else if snap.source == "claude" {
            snap.providerSessionId = lookupSessionId
        }

        guard snap.source == "claude" else {
            sessions[trackedSessionId] = snap
            return
        }

        if let resolved = SessionTitleStore.title(for: lookupSessionId, provider: snap.source, cwd: snap.cwd) {
            snap.sessionTitle = resolved.title
            snap.sessionTitleSource = resolved.source
        } else {
            snap.sessionTitle = nil
            snap.sessionTitleSource = nil
        }
        sessions[trackedSessionId] = snap
    }

    func handleEvent(_ event: HookEvent) {
        // Debug: log all incoming events to file
        let agentTag = event.agentId.map { " agent=\($0)" } ?? ""
        log.debug("[Event] \(event.eventName)\(agentTag) session=\(event.sessionId ?? "nil")")

        // Skip events from subagent worktrees — tracked via parent's SubagentStart/Stop
        if let cwd = event.metadata.cwd,
           cwd.contains("/.claude/worktrees/agent-") || cwd.contains("/.git/worktrees/agent-") {
            log.debug("[Event] SKIPPED (worktree): \(event.eventName)\(agentTag)")
            return
        }

        let sessionId = resolveTrackingKey(sessions: sessions, event: event)

        // SessionStart = legitimate new/resumed session — allow even if recently exited
        if event.eventName == "SessionStart" {
            recentlyExitedSessions.removeValue(forKey: sessionId)
        }

        ensureSession(for: event, sessionId: sessionId)

        // Debug: log subagent state before reduce
        if let snap = sessions[sessionId], !snap.subagents.isEmpty {
            let subs = snap.subagents.map { "\($0.key):\($0.value.agentType)(\($0.value.status))" }.joined(separator: ", ")
            log.debug("[Event] subagents BEFORE: [\(subs)]")
        }

        let wasWaiting = sessions[sessionId]?.status == .waitingApproval
            || sessions[sessionId]?.status == .waitingQuestion

        let effects = reduceEvent(sessions: &sessions, event: event, trackingKey: sessionId, maxHistory: maxHistory)

        // Debug: log subagent state after reduce
        if let snap = sessions[sessionId], !snap.subagents.isEmpty {
            let subs = snap.subagents.map { "\($0.key):\($0.value.agentType)(\($0.value.status))" }.joined(separator: ", ")
            log.debug("[Event] subagents AFTER: [\(subs)]")
        } else if event.agentId != nil {
            log.debug("[Event] subagents AFTER: [] (empty)")
        }

        if event.eventName == "UserPromptSubmit" {
            lastInputSessionId = sessionId
        }

        // If session was waiting but received an activity event, the question/permission
        // was answered externally (e.g. user replied in terminal). Clear pending items.
        if wasWaiting {
            let en = event.eventName
            // Events that should NOT clear waiting state
            let keepWaiting: Set<String> = ["Notification", "SessionStart", "SessionEnd", "PreCompact"]
            if !keepWaiting.contains(en) {
                drainPermissions(forSession: sessionId)
                drainQuestions(forSession: sessionId)
                if var snap = sessions[sessionId],
                   snap.status == .waitingApproval || snap.status == .waitingQuestion {
                    snap.status = (en == "Stop") ? .idle : .processing
                    snap.currentTool = nil
                    snap.toolDescription = nil
                    sessions[sessionId] = snap
                }
                showNextPending()
            }
        }

        for effect in effects {
            executeEffect(effect, sessionId: sessionId)
        }

        // Refresh token usage + model on turn boundaries (new JSONL entries written)
        if event.eventName == "Stop" || event.eventName == "SessionStart" {
            if let result = SessionUsageReader.readUsage(sessionId: sessionId, cwd: sessions[sessionId]?.cwd) {
                sessions[sessionId]?.tokenUsage = result.usage
                if let model = result.model {
                    sessions[sessionId]?.model = model
                }
            }
        }

        if sessions[sessionId]?.source == "claude" {
            refreshProviderTitle(for: sessionId)
        }

        // Handle the "else if activeSessionId == sessionId → mostActive" edge case
        // (reducer can't check activeSessionId since it's AppState-local)
        if sessions[sessionId]?.status == .idle && activeSessionId == sessionId {
            if event.eventName != "Stop" {
                activeSessionId = mostActiveSessionId()
            }
        }

        startRotationIfNeeded()
        refreshDerivedState()
    }

    private func executeEffect(_ effect: SideEffect, sessionId: String) {
        switch effect {
        case .playSound(let eventName):
            guard !suppressSideEffects else { break }
            SoundManager.shared.handleEvent(eventName)
        case .tryMonitorSession(let sid):
            processMonitor.tryMonitor(sessionId: sid, cliPid: sessions[sid]?.cliPid)
        case .stopMonitor(let sid):
            processMonitor.stop(sessionId: sid)
        case .removeSession(let sid):
            removeSession(sid)
        case .enqueueCompletion(let sid):
            guard !suppressSideEffects else { break }
            enqueueCompletion(sid)
        case .setActiveSession(let sid):
            activeSessionId = sid
        }
    }

    func handlePermissionRequest(_ event: HookEvent, continuation: CheckedContinuation<Data, Never>) -> String {
        let sessionId = resolveTrackingKey(sessions: sessions, event: event)
        if !ensureSession(for: event, sessionId: sessionId) && sessions[sessionId] == nil {
            // Session recently exited — deny and don't recreate
            continuation.resume(returning: HookResponse.permission(.deny, reason: "Session exited"))
            return sessionId
        }
        sessions[sessionId]?.lastActivity = Date()
        requestQueue.enqueuePermission(request: PermissionRequest(event: event, trackingKey: sessionId, continuation: continuation))
        refreshDerivedState()
        return sessionId
    }

    func approvePermission(always: Bool = false) {
        guard let sessionId = requestQueue.approve(always: always) else { return }
        sessions[sessionId]?.status = .running
        applyShowNextPending()
        refreshDerivedState()
    }

    func denyPermission() {
        guard let sessionId = requestQueue.deny() else { return }
        if var snap = sessions[sessionId] {
            snap.status = .idle
            snap.currentTool = nil
            snap.toolDescription = nil
            sessions[sessionId] = snap
        }
        if activeSessionId == sessionId {
            activeSessionId = mostActiveSessionId()
        }
        applyShowNextPending()
        refreshDerivedState()
    }

    func handleQuestion(_ event: HookEvent, continuation: CheckedContinuation<Data, Never>) -> String {
        let sessionId = resolveTrackingKey(sessions: sessions, event: event)
        if !ensureSession(for: event, sessionId: sessionId) && sessions[sessionId] == nil {
            // Session recently exited — dismiss and don't recreate
            continuation.resume(returning: HookResponse.empty)
            return sessionId
        }
        guard let question = QuestionPayload.from(event: event) else {
            continuation.resume(returning: HookResponse.empty)
            return sessionId
        }
        sessions[sessionId]?.lastActivity = Date()
        withAnimation(NotchAnimation.open) {
            requestQueue.enqueueQuestion(request: QuestionRequest(event: event, trackingKey: sessionId, question: question, continuation: continuation))
        }
        refreshDerivedState()
        return sessionId
    }

    func handleAskUserQuestion(_ event: HookEvent, continuation: CheckedContinuation<Data, Never>) -> String {
        let sessionId = resolveTrackingKey(sessions: sessions, event: event)
        if sessions[sessionId] == nil {
            sessions[sessionId] = SessionSnapshot()
        }
        extractMetadata(into: &sessions, sessionId: sessionId, event: event)
        processMonitor.tryMonitor(sessionId: sessionId, cliPid: sessions[sessionId]?.cliPid)

        let payload = event.askUserPayload ?? QuestionPayload(question: "Question", options: nil)

        sessions[sessionId]?.lastActivity = Date()
        withAnimation(NotchAnimation.open) {
            requestQueue.enqueueQuestion(request: QuestionRequest(event: event, trackingKey: sessionId, question: payload, continuation: continuation, isFromPermission: true))
        }
        refreshDerivedState()
        return sessionId
    }

    func answerQuestion(_ answer: String) {
        guard let sessionId = requestQueue.answer(answer) else { return }
        sessions[sessionId]?.status = .processing
        applyShowNextPending()
        refreshDerivedState()
    }

    func skipQuestion() {
        guard let sessionId = requestQueue.skip() else { return }
        sessions[sessionId]?.status = .processing
        applyShowNextPending()
        refreshDerivedState()
    }

    /// Called when the bridge socket disconnects — the question/permission was answered externally (e.g. user replied in terminal)
    /// `trackingKey` is the resolved key (sessionId or sessionId/pid).
    func handlePeerDisconnect(trackingKey: String) {
        let hadPending = requestQueue.permissionQueue.contains(where: { $0.trackingKey == trackingKey })
            || requestQueue.questionQueue.contains(where: { $0.trackingKey == trackingKey })
        guard hadPending else { return }

        requestQueue.drainAll(forTrackingKey: trackingKey)
        if var snap = sessions[trackingKey],
           snap.status == .waitingApproval || snap.status == .waitingQuestion {
            snap.status = .processing
            snap.currentTool = nil
            snap.toolDescription = nil
            sessions[trackingKey] = snap
        }
        applyShowNextPending()
        refreshDerivedState()
    }

    private func drainPermissions(forSession sessionId: String) {
        requestQueue.drainPermissions(forTrackingKey: sessionId)
    }

    private func drainQuestions(forSession sessionId: String) {
        requestQueue.drainQuestions(forTrackingKey: sessionId)
    }

    /// After dequeuing, show next pending item or collapse
    private func showNextPending() {
        applyShowNextPending()
    }

    private func applyShowNextPending() {
        let next = requestQueue.showNextPending()
        switch next {
        case .approvalCard, .questionCard:
            surface = next
        case .collapsed:
            if case .approvalCard = surface { surface = .collapsed }
            else if case .questionCard = surface { surface = .collapsed }
        default:
            break
        }
    }

    /// Find the most recently active non-idle session
    private func mostActiveSessionId() -> String? {
        // Single-pass: find most recent non-idle, fall back to most recent overall
        var bestNonIdle: (key: String, time: Date)?
        var bestAny: (key: String, time: Date)?
        for (key, session) in sessions {
            if bestAny == nil || session.lastActivity > bestAny!.time {
                bestAny = (key, session.lastActivity)
            }
            if session.status != .idle, bestNonIdle == nil || session.lastActivity > bestNonIdle!.time {
                bestNonIdle = (key, session.lastActivity)
            }
        }
        return (bestNonIdle ?? bestAny)?.key
    }

    // MARK: - Session Discovery

    func startSessionDiscovery() {
        startCleanupLoop()
        setupServices()
        processMonitor.onSessionExpired = { [weak self] sessionId, exitTime in
            guard let self, let session = self.sessions[sessionId] else { return }
            if session.lastActivity > exitTime { return }
            self.removeSession(sessionId)
        }

        // Replay events logged while app was not running
        suppressSideEffects = true
        for eventData in EventLog.readAndClear() {
            if let event = HookEvent(from: eventData) {
                handleEvent(event)
            }
        }
        suppressSideEffects = false

        if activeSessionId == nil {
            activeSessionId = sessions.keys.sorted().first
        }
        refreshDerivedState()
    }

    func stopSessionDiscovery() {
        processMonitor.stopAll()
    }

    deinit {
        MainActor.assumeIsolated {
            rotationTask?.cancel()
            cleanupTask?.cancel()
            processMonitor.stopAll()
        }
    }

}

/// Encode a path the same way Claude Code does for project directory names:
/// "/" → "-", non-ASCII → "-", spaces → "-"
extension String {
    func claudeProjectDirEncoded() -> String {
        var result = ""
        for c in self.unicodeScalars {
            if c == "/" || c == " " || c.value > 127 {
                result.append("-")
            } else {
                result.append(Character(c))
            }
        }
        return result
    }
}
