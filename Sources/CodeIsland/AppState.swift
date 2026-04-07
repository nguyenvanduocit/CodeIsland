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
    let discoveryService = SessionDiscoveryService()
    let completionQueue = CompletionQueueService()
    let requestQueue = RequestQueueService()
    private var saveTask: Task<Void, Never>?
    private var modelReadAttempted: Set<String> = []

    var rotatingSessionId: String?
    var rotatingSession: SessionSnapshot? {
        guard let rid = rotatingSessionId else { return nil }
        return sessions[rid]
    }
    private var rotationTask: Task<Void, Never>?

    private func setupServices() {
        // Wire CompletionQueueService callbacks
        completionQueue.onSurfaceChange = { [weak self] newSurface in self?.surface = newSurface }
        completionQueue.onActiveSessionChange = { [weak self] sid in self?.activeSessionId = sid }
        completionQueue.sessionExists = { [weak self] sid in self?.sessions[sid] != nil }
        completionQueue.getSession = { [weak self] sid in self?.sessions[sid] }
        completionQueue.currentSurface = { [weak self] in self?.surface ?? .collapsed }

        // Wire RequestQueueService callbacks
        // Note: animation is applied at the call site (handleQuestion/handlePermission),
        // not inside the callback, to avoid re-entrancy during service mutations.
        requestQueue.onSurfaceChange = { [weak self] newSurface in self?.surface = newSurface }
        requestQueue.onActiveSessionChange = { [weak self] sid in self?.activeSessionId = sid }
        requestQueue.onSessionStatusChange = { [weak self] sid, status, tool, desc in
            guard let self, var snap = self.sessions[sid] else { return }
            snap.status = status
            if status == .waitingApproval {
                snap.currentTool = tool
                snap.toolDescription = desc
            }
            self.sessions[sid] = snap
        }
        requestQueue.onPlaySound = { SoundManager.shared.handleEvent($0) }
    }

    private func startCleanupLoop() {
        cleanupTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.cleanupIdleSessions()
            }
        }
    }

    private func cleanupIdleSessions() {
        // Refresh transcript file sizes for context usage tracking
        for (sessionId, session) in sessions {
            guard let path = session.transcriptPath, !path.isEmpty else { continue }
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
               let size = attrs[.size] as? Int64 {
                sessions[sessionId]?.transcriptSize = size
            }
        }

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

        // 2. Remove sessions whose process is dead (any status — prevents phantom counts)
        for (key, session) in sessions {
            if processMonitor.isMonitoring(key) { continue }

            // Known PID is dead — remove after brief grace (10s)
            if let pid = session.cliPid, pid > 0, kill(pid, 0) != 0 {
                let inactiveSeconds = -session.lastActivity.timeIntervalSinceNow
                if inactiveSeconds > 10 { removeSession(key) }
                continue
            }

            // No PID at all — safety net: remove after 5 min inactive
            if session.cliPid == nil || session.cliPid == 0 {
                let inactiveMinutes = Int(-session.lastActivity.timeIntervalSinceNow / 60)
                if inactiveMinutes >= 5 { removeSession(key) }
            }
        }
        // refreshDerivedState is called inside removeSession for each removal
    }

    /// Remove a session, clean up its monitor, and resume any pending continuations.
    /// Every removal path (cleanup timer, process exit, reducer effect) goes through here
    /// so leaked continuations / connections are impossible.
    private func removeSession(_ sessionId: String) {
        // Resume ALL pending continuations for this session
        drainPermissions(forSession: sessionId)
        drainQuestions(forSession: sessionId)

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
        // Skip events from subagent worktrees — tracked via parent's SubagentStart/Stop
        if let cwd = event.rawJSON["cwd"] as? String,
           cwd.contains("/.claude/worktrees/agent-") || cwd.contains("/.git/worktrees/agent-") {
            return
        }

        let sessionId = event.sessionId ?? "default"

        if sessions[sessionId] == nil {
            sessions[sessionId] = SessionSnapshot()
        }

        let wasWaiting = sessions[sessionId]?.status == .waitingApproval
            || sessions[sessionId]?.status == .waitingQuestion

        let effects = reduceEvent(sessions: &sessions, event: event, maxHistory: maxHistory)

        if event.eventName == "UserPromptSubmit" {
            lastInputSessionId = sessionId
        }

        // Model transcript read: done AFTER reduceEvent so extractMetadata has filled in cwd
        if sessions[sessionId]?.model == nil && !modelReadAttempted.contains(sessionId) {
            modelReadAttempted.insert(sessionId)
            let cwd = sessions[sessionId]?.cwd
            if let model = SessionDiscoveryService.readModelFromTranscript(sessionId: sessionId, cwd: cwd) {
                sessions[sessionId]?.model = model
            }
        }

        // Messages are managed by the reducer (UserPromptSubmit → user msg, Stop → assistant msg).
        // Transcript reads are only used at discovery/restore time for initial population.

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

        scheduleSave()
        startRotationIfNeeded()
        refreshDerivedState()
    }

    private func executeEffect(_ effect: SideEffect, sessionId: String) {
        switch effect {
        case .playSound(let eventName):
            SoundManager.shared.handleEvent(eventName)
        case .tryMonitorSession(let sid):
            processMonitor.tryMonitor(
                sessionId: sid,
                cliPid: sessions[sid]?.cliPid,
                cwd: sessions[sid]?.cwd,
                onPidFound: { [weak self] sessionId, pid in
                    self?.sessions[sessionId]?.cliPid = pid
                }
            )
        case .stopMonitor(let sid):
            processMonitor.stop(sessionId: sid)
        case .removeSession(let sid):
            removeSession(sid)
        case .enqueueCompletion(let sid):
            enqueueCompletion(sid)
        case .setActiveSession(let sid):
            activeSessionId = sid
        }
    }

    func handlePermissionRequest(_ event: HookEvent, continuation: CheckedContinuation<Data, Never>) {
        let sessionId = event.sessionId ?? "default"
        if sessions[sessionId] == nil {
            sessions[sessionId] = SessionSnapshot()
        }
        // Extract metadata so blocking-first sessions have cwd, source, cliPid, terminal info
        extractMetadata(into: &sessions, sessionId: sessionId, event: event)
        processMonitor.tryMonitor(
            sessionId: sessionId,
            cliPid: sessions[sessionId]?.cliPid,
            cwd: sessions[sessionId]?.cwd,
            onPidFound: { [weak self] sid, pid in self?.sessions[sid]?.cliPid = pid }
        )
        sessions[sessionId]?.lastActivity = Date()
        requestQueue.enqueuePermission(request: PermissionRequest(event: event, continuation: continuation))
        refreshDerivedState()
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

    func handleQuestion(_ event: HookEvent, continuation: CheckedContinuation<Data, Never>) {
        let sessionId = event.sessionId ?? "default"
        if sessions[sessionId] == nil {
            sessions[sessionId] = SessionSnapshot()
        }
        extractMetadata(into: &sessions, sessionId: sessionId, event: event)
        processMonitor.tryMonitor(
            sessionId: sessionId,
            cliPid: sessions[sessionId]?.cliPid,
            cwd: sessions[sessionId]?.cwd,
            onPidFound: { [weak self] sid, pid in self?.sessions[sid]?.cliPid = pid }
        )
        guard let question = QuestionPayload.from(event: event) else {
            continuation.resume(returning: HookResponse.empty)
            return
        }
        sessions[sessionId]?.lastActivity = Date()
        withAnimation(NotchAnimation.open) {
            requestQueue.enqueueQuestion(request: QuestionRequest(event: event, question: question, continuation: continuation))
        }
        refreshDerivedState()
    }

    func handleAskUserQuestion(_ event: HookEvent, continuation: CheckedContinuation<Data, Never>) {
        let sessionId = event.sessionId ?? "default"
        if sessions[sessionId] == nil {
            sessions[sessionId] = SessionSnapshot()
        }
        extractMetadata(into: &sessions, sessionId: sessionId, event: event)
        processMonitor.tryMonitor(
            sessionId: sessionId,
            cliPid: sessions[sessionId]?.cliPid,
            cwd: sessions[sessionId]?.cwd,
            onPidFound: { [weak self] sid, pid in self?.sessions[sid]?.cliPid = pid }
        )

        let payload: QuestionPayload
        if let questions = event.toolInput?["questions"] as? [[String: Any]],
           let first = questions.first {
            let questionText = first["question"] as? String ?? "Question"
            let header = first["header"] as? String
            var optionLabels: [String]?
            var optionDescs: [String]?
            if let opts = first["options"] as? [[String: Any]] {
                optionLabels = opts.compactMap { $0["label"] as? String }
                optionDescs = opts.compactMap { $0["description"] as? String }
            }
            payload = QuestionPayload(question: questionText, options: optionLabels, descriptions: optionDescs, header: header)
        } else {
            let questionText = event.toolInput?["question"] as? String ?? "Question"
            var options: [String]?
            if let stringOpts = event.toolInput?["options"] as? [String] {
                options = stringOpts
            } else if let dictOpts = event.toolInput?["options"] as? [[String: Any]] {
                options = dictOpts.compactMap { $0["label"] as? String }
            }
            payload = QuestionPayload(question: questionText, options: options)
        }

        sessions[sessionId]?.lastActivity = Date()
        withAnimation(NotchAnimation.open) {
            requestQueue.enqueueQuestion(request: QuestionRequest(event: event, question: payload, continuation: continuation, isFromPermission: true))
        }
        refreshDerivedState()
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
    func handlePeerDisconnect(sessionId: String) {
        let hadPending = requestQueue.permissionQueue.contains(where: { $0.event.sessionId == sessionId })
            || requestQueue.questionQueue.contains(where: { $0.event.sessionId == sessionId })
        guard hadPending else { return }

        requestQueue.drainAll(forSession: sessionId)
        if var snap = sessions[sessionId],
           snap.status == .waitingApproval || snap.status == .waitingQuestion {
            snap.status = .processing
            snap.currentTool = nil
            snap.toolDescription = nil
            sessions[sessionId] = snap
        }
        applyShowNextPending()
        refreshDerivedState()
    }

    private func drainPermissions(forSession sessionId: String) {
        requestQueue.drainPermissions(forSession: sessionId)
    }

    private func drainQuestions(forSession sessionId: String) {
        requestQueue.drainQuestions(forSession: sessionId)
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

    // MARK: - Session Discovery (FSEventStream + process scan)

    /// Start continuous monitoring: initial process scan + FSEventStream on ~/.claude/projects/
    // MARK: - Session Persistence

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.saveSessions()
        }
    }

    func saveSessions() {
        SessionPersistence.save(sessions)
    }

    private func restoreSessions() {
        let persisted = SessionPersistence.load()
        let cutoff = Date().addingTimeInterval(-30 * 60) // 30 minutes

        // Deduplicate by PID: when multiple sessions share the same cliPid,
        // keep only the one with the most recent lastActivity.
        var bestByPid: [Int32: PersistedSession] = [:]
        var noPidSessions: [PersistedSession] = []
        for p in persisted where p.lastActivity > cutoff {
            guard SessionSnapshot.normalizedSupportedSource(p.source) != nil else { continue }
            if let pid = p.cliPid, pid > 0 {
                if let existing = bestByPid[pid] {
                    if p.lastActivity > existing.lastActivity { bestByPid[pid] = p }
                } else {
                    bestByPid[pid] = p
                }
            } else {
                noPidSessions.append(p)
            }
        }
        let deduped = Array(bestByPid.values) + noPidSessions

        for p in deduped {
            guard sessions[p.sessionId] == nil else { continue }
            guard let source = SessionSnapshot.normalizedSupportedSource(p.source) else { continue }
            var snapshot = SessionSnapshot(startTime: p.startTime)
            snapshot.cwd = p.cwd
            snapshot.source = source
            snapshot.model = p.model
            snapshot.sessionTitle = p.sessionTitle
            snapshot.sessionTitleSource = p.sessionTitleSource
            snapshot.providerSessionId = p.providerSessionId
            snapshot.lastAssistantMessage = p.lastAssistantMessage
            if let prompt = p.lastUserPrompt {
                if let info = TaskNotificationInfo.parse(prompt) {
                    let display = info.summary ?? "Task \(info.status)"
                    snapshot.lastUserPrompt = display
                    snapshot.addRecentMessage(ChatMessage(kind: .taskNotification(info), text: display))
                } else {
                    snapshot.lastUserPrompt = prompt
                    snapshot.addRecentMessage(ChatMessage(isUser: true, text: prompt))
                }
            }
            if let reply = p.lastAssistantMessage {
                snapshot.addRecentMessage(ChatMessage(isUser: false, text: reply))
            }
            snapshot.termApp = p.termApp
            snapshot.itermSessionId = p.itermSessionId
            snapshot.ttyPath = p.ttyPath
            snapshot.kittyWindowId = p.kittyWindowId
            snapshot.tmuxPane = p.tmuxPane
            snapshot.tmuxClientTty = p.tmuxClientTty
            snapshot.termBundleId = p.termBundleId
            snapshot.lastActivity = p.lastActivity
            // Restore persisted cliPid — enables immediate process monitoring for all CLIs
            if let pid = p.cliPid, pid > 0 {
                snapshot.cliPid = pid
            }
            sessions[p.sessionId] = snapshot
            refreshProviderTitle(for: p.sessionId)
            // Attach process monitor if alive — but don't override status.
            // The process stays alive while waiting for user input (idle).
            // Status will be set correctly by hook events (Stop → idle, UserPromptSubmit → processing).
            if let pid = snapshot.cliPid, pid > 0, kill(pid, 0) == 0 {
                processMonitor.monitor(sessionId: p.sessionId, pid: pid)
            } else {
                // Async fallback: scan for Claude processes by CWD
                let sid = p.sessionId
                processMonitor.tryMonitor(
                    sessionId: sid,
                    cliPid: snapshot.cliPid,
                    cwd: snapshot.cwd,
                    onPidFound: { [weak self] sessionId, pid in
                        guard let self, self.sessions[sessionId] != nil else { return }
                        self.sessions[sessionId]?.cliPid = pid
                        self.refreshDerivedState()
                    }
                )
            }
        }
        SessionPersistence.clear()

        // Replay events logged while app was not running
        for eventData in EventLog.readAndClear() {
            if let event = HookEvent(from: eventData) {
                handleEvent(event)
            }
        }

        if activeSessionId == nil {
            activeSessionId = sessions.keys.sorted().first
        }
        refreshDerivedState()
    }

    func startSessionDiscovery() {
        startCleanupLoop()
        setupServices()
        processMonitor.onSessionExpired = { [weak self] sessionId, exitTime in
            guard let self, let session = self.sessions[sessionId] else { return }
            if session.lastActivity > exitTime { return }  // fresh activity during grace
            self.removeSession(sessionId)
        }
        // Restore persisted sessions before process scan (deduped by scan)
        restoreSessions()

        discoveryService.onDiscovered = { [weak self] in self?.integrateDiscovered($0) }

        // Initial scan for already-running Claude sessions
        Task.detached {
            let claudeSessions = SessionDiscoveryService.findActiveClaudeSessions()
            await MainActor.run { [weak self] in
                self?.integrateDiscovered(claudeSessions)
            }
        }
        // Start watching ~/.claude/projects/ for new session files
        discoveryService.startWatching()
    }

    /// Merge discovered sessions into current state (skip already-known ones)
    private func integrateDiscovered(_ discovered: [DiscoveredSession]) {
        var didAdd = false
        for info in discovered {
            // Session already known — try to attach PID monitor if missing
            if sessions[info.sessionId] != nil {
                if !processMonitor.isMonitoring(info.sessionId), let pid = info.pid {
                    processMonitor.monitor(sessionId: info.sessionId, pid: pid)
                    // Don't override status — process stays alive while waiting for user input.
                    // Hook events (Stop/UserPromptSubmit) are the source of truth for status.
                }
                refreshProviderTitle(for: info.sessionId, providerSessionId: info.sessionId)
                continue
            }

            // Dedup: if a hook-created session already exists with same source + cwd + pid,
            // skip the discovered one to avoid duplicate entries (e.g. Codex hooks vs
            // file-based discovery produce different session IDs for the same process).
            // Only reject match when both PIDs are alive and different — stale PIDs
            // from restored sessions should not prevent dedup.
            let duplicateKey = sessions.first(where: { (_, existing) in
                guard existing.source == info.source,
                      existing.cwd != nil, existing.cwd == info.cwd else { return false }
                if let discoveredPid = info.pid, let existingPid = existing.cliPid,
                   discoveredPid != existingPid {
                    // Only reject if the existing PID is still alive (not stale from persistence)
                    return kill(existingPid, 0) != 0
                }
                return true
            })?.key

            if let existingKey = duplicateKey {
                // Attach PID monitor and update stale cliPid on the existing session
                if let pid = info.pid {
                    if sessions[existingKey]?.cliPid != pid {
                        sessions[existingKey]?.cliPid = pid
                    }
                    if !processMonitor.isMonitoring(existingKey) {
                        processMonitor.monitor(sessionId: existingKey, pid: pid)
                    }
                }
                refreshProviderTitle(for: existingKey, providerSessionId: info.sessionId)
                continue
            }

            var session = SessionSnapshot(startTime: info.modifiedAt)
            session.cwd = info.cwd
            session.model = info.model
            session.ttyPath = info.tty
            session.termBundleId = info.termBundleId
            session.recentMessages = info.recentMessages
            session.source = info.source
            session.cliPid = info.pid
            session.providerSessionId = info.source == "claude" ? info.sessionId : nil
            if let last = info.recentMessages.last(where: { $0.isUser }) {
                session.lastUserPrompt = last.text
            }
            if let last = info.recentMessages.last(where: { !$0.isUser }) {
                session.lastAssistantMessage = last.text
            }
            sessions[info.sessionId] = session
            refreshProviderTitle(for: info.sessionId, providerSessionId: info.sessionId)
            if let pid = info.pid {
                processMonitor.monitor(sessionId: info.sessionId, pid: pid)
            }
            didAdd = true
        }
        if didAdd && activeSessionId == nil {
            activeSessionId = sessions.keys.sorted().first
        }
        refreshDerivedState()
    }

    func stopSessionDiscovery() {
        discoveryService.stopWatching()
        processMonitor.stopAll()
    }

    deinit {
        MainActor.assumeIsolated {
            rotationTask?.cancel()
            cleanupTask?.cancel()
            saveTask?.cancel()
            discoveryService.stopWatching()
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
