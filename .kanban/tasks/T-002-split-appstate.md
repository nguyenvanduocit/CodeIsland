# T-002: Tach AppState thanh services

## Hien trang

`AppState.swift` = **1186 dong**, la God Object chua 8+ concerns. Giao tiep voi 5 external services. Toan bo 45+ methods va 20+ stored properties.

## Plan

### Step 1: Extract `ProcessMonitorService` (~80 dong)

**Di chuyen:**
- Property: `processMonitors: [String: (source: DispatchSourceProcess, pid: pid_t)]`
- `monitorProcess(sessionId:pid:)` (dong 100-116)
- `handleProcessExit(sessionId:exitedPid:)` (dong 120-138)
- `stopMonitor(_:)` (dong 140-143)
- `tryMonitorSession(_:)` (dong 209-228)
- `findPidForCwd(_:)` (dong 231-236) static

**Interface:**
```swift
@MainActor
final class ProcessMonitorService {
    private var monitors: [String: (source: DispatchSourceProcess, pid: pid_t)] = []
    
    var onProcessExit: ((String) -> Void)?  // callback voi sessionId
    
    func monitor(sessionId: String, pid: pid_t)
    func tryMonitor(sessionId: String, cliPid: pid_t?, cwd: String?)
    func stop(sessionId: String)
    func stopAll()
    func isMonitoring(_ sessionId: String) -> Bool
    nonisolated static func findPidForCwd(_ cwd: String) -> pid_t?
}
```

**AppState thay doi:** Tao property `let processMonitor = ProcessMonitorService()`, thay `processMonitors[...]` thanh `processMonitor.isMonitoring(...)`, set `processMonitor.onProcessExit = { [weak self] in self?.handleProcessExit($0) }`.

### Step 2: Extract `CompletionQueueService` (~80 dong)

**Di chuyen:**
- Properties: `completionQueue`, `completionHasBeenEntered`, `autoCollapseTask`
- `enqueueCompletion(_:)` (dong 238-249)
- `shouldSuppressAppLevel(for:)` (dong 252-257)
- `showCompletion(_:)` (dong 259-287)
- `doShowCompletion(_:)` (dong 289-300)
- `cancelCompletionQueue()` (dong 302-305)
- `showNextCompletionOrCollapse()` (dong 307-320)

**Interface:**
```swift
@MainActor
final class CompletionQueueService {
    var completionHasBeenEntered = false
    
    var onSurfaceChange: ((IslandSurface) -> Void)?
    var onActiveSessionChange: ((String) -> Void)?
    
    func enqueue(_ sessionId: String, sessions: [String: SessionSnapshot], currentSurface: IslandSurface)
    func cancel()
}
```

**Phuc tap:** `showCompletion` goi `TerminalVisibilityDetector` va mutate `surface`, `activeSessionId`. Can callback mechanism.

### Step 3: Extract `RequestQueueService` (~250 dong, lon nhat)

**Di chuyen:**
- Properties: `permissionQueue`, `questionQueue`
- `handlePermissionRequest(_:continuation:)` (dong 466-493)
- `approvePermission(always:)` (dong 495-526)
- `denyPermission()` (dong 528-544)
- `handleQuestion(_:continuation:)` (dong 546-574)
- `handleAskUserQuestion(_:continuation:)` (dong 576-624)
- `answerQuestion(_:)` (dong 626-659)
- `skipQuestion()` (dong 661-676)
- `drainPermissions(forSession:)` (dong 679-686)
- `drainQuestions(forSession:)` (dong 707-713)
- `handlePeerDisconnect(sessionId:)` (dong 689-704)
- `showNextPending()` (dong 716-730)

**Interface:**
```swift
@MainActor
final class RequestQueueService {
    private(set) var permissionQueue: [PermissionRequest] = []
    private(set) var questionQueue: [QuestionRequest] = []
    
    var pendingPermission: PermissionRequest? { permissionQueue.first }
    var pendingQuestion: QuestionRequest? { questionQueue.first }
    
    var onSurfaceChange: ((IslandSurface) -> Void)?
    var onSessionStatusChange: ((String, AgentStatus) -> Void)?
    
    func enqueuePermission(event:continuation:)
    func approve(always:)
    func deny()
    func enqueueQuestion(event:continuation:)
    func answer(_:)
    func skip()
    func drainAll(forSession:)
    func nextPending() -> IslandSurface?
}
```

**Phuc tap:** Cac method nay truc tiep mutate `sessions[sid].status`, `.currentTool`, `.toolDescription`. Can delegate nguoc qua callback hoac AppState wrap lai.

### Step 4: Extract `SessionDiscoveryService` (~200 dong)

**Di chuyen:**
- Properties: `fsEventStream`, `lastFSScanTime`, `modelReadAttempted`
- `startProjectsWatcher()` (dong 872-900)
- `handleProjectsDirChange()` (dong 903-916)
- `stopSessionDiscovery()` (dong 988-996) — phan FS
- `findActiveClaudeSessions()` (dong 1024-1090) static
- `findClaudePids()` (dong 1092-1094) static
- `getCwd(for:)` (dong 1096-1098) static
- `getProcessStartTime(_:)` (dong 1100-1102) static
- `readRecentFromTranscript(path:)` (dong 1105-1169) static
- `readModelFromTranscript(sessionId:cwd:)` (dong 749-768) static
- `DiscoveredSession` struct (dong 1012-1021)

**Interface:**
```swift
@MainActor
final class SessionDiscoveryService {
    var onDiscovered: (([DiscoveredSession]) -> Void)?
    
    func startWatching()
    func stopWatching()
    nonisolated static func findActiveClaudeSessions() -> [DiscoveredSession]
    nonisolated static func readModelFromTranscript(sessionId:cwd:) -> String?
}
```

**Ghi chu:** `integrateDiscovered(_:)` (dong 919-986) GIU o AppState vi no heavily mutate `sessions` va goi `monitorProcess`, `refreshProviderTitle`.

### Step 5: Cap nhat AppState.swift (con lai ~400 dong)

Giu lai:
- Core state: `sessions`, `activeSessionId`, `surface`
- Service instances: `processMonitor`, `completionQueue`, `requestQueue`, `discoveryService`
- `handleEvent()` + `executeEffect()` (event routing)
- `removeSession()` (central hub, goi nhieu services)
- `integrateDiscovered()` (mutate sessions)
- Rotation logic (~40 dong, qua nho de tach)
- Derived state: `refreshDerivedState()`, computed properties
- Persistence: `scheduleSave()`, `saveSessions()`, `restoreSessions()`
- `startSessionDiscovery()` (orchestration)

### Step 6: Build + test

```bash
swift build
swift test
```

## Thua tu phu thuoc

Cac services can tu AppState:
| Service | Can READ | Can WRITE |
|---------|----------|-----------|
| ProcessMonitorService | sessions[sid].cliPid, cwd | Khong (callback onExit) |
| CompletionQueueService | sessions (check exists), surface | surface, activeSessionId (qua callback) |
| RequestQueueService | Khong | sessions[sid].status/tool (qua callback) |
| SessionDiscoveryService | Khong | Khong (callback onDiscovered) |

## Thu tu thuc hien

1. ProcessMonitorService (it phu thuoc nhat, clean boundary)
2. SessionDiscoveryService (static methods nhieu, de tach)
3. CompletionQueueService (trung binh)
4. RequestQueueService (phuc tap nhat, nhieu mutation)
5. Final cleanup + verify

## Risk

- **RequestQueueService** co CheckedContinuation — can dam bao moi continuation duoc resume dung 1 lan. Tach ra co the introduce bugs neu lifecycle khong dung.
- **removeSession** la central hub goi 6 services — sau khi tach, no se goi qua service interfaces, can verify khong bo sot.
