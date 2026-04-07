# T-005: Modernize concurrency patterns

## Hien trang

9x Timer.scheduledTimer, 5x Task.detached, 5x MainActor.run, 1x DispatchSourceProcess, 1x FSEventStream raw C API, 9x DispatchQueue, 2x Unmanaged pointer.

## Plan

### Step 1: Timer.scheduledTimer -> Task loop (9 cho, THAP risk)

**1a. Repeating timers trong AppState** (3 cho):
- `startCleanupTimer()` (dong 53) — 60s interval
- `rotationTimer` (dong 182) — 3s interval  
- `scheduleSave()` (dong 777) — 2s debounce

Pattern moi:
```swift
// Repeating:
private var cleanupTask: Task<Void, Never>?
private func startCleanupLoop() {
    cleanupTask = Task { @MainActor in
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            cleanupIdleSessions()
        }
    }
}

// Debounce:
private var saveTask: Task<Void, Never>?
private func scheduleSave() {
    saveTask?.cancel()
    saveTask = Task { @MainActor in
        try? await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled else { return }
        saveSessions()
    }
}
```

**1b. AppDelegate** (1 cho):
- `hookRecoveryTimer` (dong 36) — 300s interval -> Task loop

**1c. PanelWindowController** (2 cho):
- `autoScreenPoller` (dong 402) — 1s interval -> Task loop
- `fullscreenExitPoller` (dong 441) — 1.5s interval -> Task loop

**1d. NotchPanelView hover timers** (3 cho):
- Hover expand delay (dong 187) — 0.5s one-shot
- Hover collapse delay (dong 201) — 0.15s one-shot
- Session expand hover (dong 1067) — 0.6s one-shot

Pattern moi: Dung `@State private var hoverTask: Task<Void, Never>?` thay vi `@State private var hoverTimer: Timer?`

### Step 2: DispatchQueue.global -> Task.detached (TerminalActivator, 6 cho, THAP risk)

File: `TerminalActivator.swift` dong 237, 268, 276, 287, 321, 342

Pattern cu:
```swift
DispatchQueue.global(qos: .userInitiated).async { ... }
```

Pattern moi:
```swift
Task.detached(priority: .userInitiated) { ... }
```

Fire-and-forget, khong can ket qua. Migration 1:1.

### Step 3: DispatchQueue.main.asyncAfter -> Task.sleep (2 cho, THAP risk)

- `PixelCharacterView.swift:33` — 0.05s delay
- `BuddyView.swift:35` — 0.05s delay

Pattern moi:
```swift
Task { @MainActor in
    try? await Task.sleep(for: .milliseconds(50))
    alive = true
}
```

### Step 4: FSEventStream -> AsyncStream wrapper (TRUNG BINH risk)

File: `AppState.swift` dong 872-900 (setup), 988-994 (teardown), 903-916 (callback)

Tao wrapper:
```swift
struct FSEventWatcher {
    static func watch(path: String, latency: TimeInterval = 2.0) -> AsyncStream<Void> {
        AsyncStream { continuation in
            var ctx = FSEventStreamContext()
            // ... setup, yield on events
            continuation.onTermination = { _ in
                FSEventStreamStop(stream)
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
            }
        }
    }
}
```

Loi ich: loai bo Unmanaged pointer, structured cleanup, declarative.

Dung trong AppState:
```swift
private var watcherTask: Task<Void, Never>?
func startProjectsWatcher() {
    watcherTask = Task { @MainActor in
        for await _ in FSEventWatcher.watch(path: projectsPath) {
            guard Date().timeIntervalSince(lastFSScanTime) > 3 else { continue }
            lastFSScanTime = Date()
            let sessions = await Task.detached { Self.findActiveClaudeSessions() }.value
            integrateDiscovered(sessions)
        }
    }
}
```

### Step 5: KHONG DOI (giu nguyen)

| Pattern | File:Line | Ly do |
|---------|-----------|-------|
| `DispatchSource.makeProcessSource` | AppState.swift:103 | Khong co async equivalent cho process exit monitoring |
| `DispatchQueue.main.async` | PanelWindowController.swift:39,58 | AppKit workaround, can defer chinh xac 1 RunLoop tick |
| `Task.detached` (process scan) | AppState.swift:220,269,830,861,909 | Can dam bao off-MainActor cho syscalls. Giu nguyen an toan hon |

## Thu tu thuc hien

1. Step 1a-1b: Timer -> Task loop trong AppState + AppDelegate (impact lon nhat)
2. Step 1c: Timer -> Task loop trong PanelWindowController
3. Step 2: DispatchQueue.global -> Task.detached (TerminalActivator)
4. Step 3: asyncAfter -> Task.sleep (PixelCharacterView, BuddyView)
5. Step 1d: Hover timers trong NotchPanelView
6. Step 4: FSEventStream wrapper (cuoi cung vi phuc tap nhat)

## Dependencies

- Phu thuoc T-002 (AppState split) vi nhieu Timer/Task.detached nam trong AppState
- Nen lam T-002 truoc de tranh conflicts

## Risk

- Step 1-3: THAP. Timer -> Task.sleep la migration 1:1.
- Step 4: TRUNG BINH. FSEventStream wrapper can test ky lifecycle (setup/teardown).
- Step 5 (KHONG DOI) cases: verified khong nen thay doi.
