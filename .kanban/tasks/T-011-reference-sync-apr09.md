# T-011: Cherry-pick features từ reference projects (Apr 2026)

> Đọc, hiểu, và replicate các feature hay từ upstream CodeIsland, open-vibe-island, và notchi — adapt theo kiến trúc của mình (pure reducer, typed events, weak appState services).

## Nguyên tắc

- **KHÔNG copy-paste** — đọc code nguồn, hiểu intent, implement lại theo pattern của mình
- Follow pure reducer + SideEffect pattern
- Typed events, không raw JSON
- Services giữ weak appState, không callbacks
- Test mọi logic change qua reducer tests

## Subtasks

### T-011a: Hook exec PID fix (from upstream b18e5b9)
**Effort:** XS | **Priority:** high | **Status:** RESEARCHED

**Vấn đề:** Hook script v3 chạy `"$BRIDGE" "$@"` rồi `exit $?`. Bash vẫn là parent → bridge gọi `getppid()` → nhận PID của bash (short-lived, ~ms) → `findCLIAncestorPid()` walk process tree nhưng bash đã exit → PID stale → mascot flicker mỗi ~2s giữa working/idle.

**Root cause:** `getppid()` trong bridge trả PID bash thay vì CLI. Process tree walker cần parent còn sống để traverse.

**Giải pháp:** `exec "$BRIDGE" "$@"` — `exec` replace bash process image bằng bridge binary. Bridge inherit bash's PID, trở thành direct child của CLI. `getppid()` trả đúng CLI PID.

**Thay đổi cụ thể (2 dòng trong ConfigInstaller.swift):**
1. `hookScriptVersion: 3 → 4` (trigger re-install cho existing users)
2. Hook script body: `"$BRIDGE" "$@"\n  exit $?` → `exec "$BRIDGE" "$@"`

**Verification:**
- `swift build` passes
- Hook script file tại `~/.claude/hooks/codeisland-hook.sh` sẽ được overwrite khi app launch (version check)

**Criteria:**
- [x] Hook script template dùng `exec` trước bridge binary
- [x] Existing installs sẽ được update khi ConfigInstaller chạy lại (version bump 3→4)
- [ ] `swift build` passes

---

### T-011b: Structured tool status display (from upstream b995a58)
**Effort:** M | **Priority:** high | **Status:** RESEARCHED

**Vấn đề:** toolDescription hiện tại derive quá đơn giản — lấy raw value, không phân biệt tool type. Bash hiện raw command (dài), Read chỉ filename, Grep chỉ pattern.

**Giải pháp:** Switch theo toolName để derive context phù hợp:
- Bash → `description` field (preferred) hoặc first line of `command` (max 60 chars)
- Read → filename + `:offset` nếu có
- Edit/Write → filename
- Grep → pattern + ` in {dir}`
- Glob → pattern
- WebSearch → query
- WebFetch → domain only (URL.host)
- Agent/Task → description hoặc prompt prefix (40 chars)
- TodoWrite → "Updating tasks"
- Default → try common fields in order

**Thay đổi:**
- `Models.swift` lines 92-107: Replace flat if-else chain với switch(toolName) { case ... }
- Giữ nguyên fallback chain cho events không có toolInput
- Không cần thay đổi views — đã hiển thị toolDescription rồi

**Criteria:**
- [ ] toolDescription switch theo toolName cho 10+ tool types
- [ ] Bash prefer `description` over raw command
- [ ] Read show offset
- [ ] Grep show search dir
- [ ] WebSearch/WebFetch handled
- [ ] Tests cho toolDescription extraction
- [ ] `swift build && swift test` passes

---

### T-011c: PID liveness check (from upstream b995a58)
**Effort:** S | **Priority:** high | **Status:** RESEARCHED

**Current state:**
- DispatchSourceProcess monitors PID exit — but can miss events (system sleep, race)
- `onSessionExpired` calls `removeSession()` — removes entirely instead of resetting to idle
- Cleanup loop at 60s — orphan check + zombie PID check + dead process removal
- No explicit `kill(pid, 0)` liveness check for monitored sessions
- No stuck detection (sessions without monitor stuck in running forever)

**Changes needed:**
1. **cleanupIdleSessions()** — add explicit liveness check for monitored PIDs:
   - `kill(pid, 0) != 0 && errno == ESRCH` → stop monitor, reset to idle
2. **Stuck detection** — for unmonitored sessions:
   - No tool + no monitor: 60s → idle
   - Has tool + no monitor: 180s → idle
   - (Skip monitored sessions — trust the monitor + liveness check above)
3. **Reduce cleanup interval** from 60s to 30s
4. **onSessionExpired** — reset to idle instead of remove (give time for reconnect)

**Criteria:**
- [ ] `kill(pid, 0)` liveness check for monitored sessions in cleanup
- [ ] Stuck detection with tiered thresholds
- [ ] Cleanup interval reduced to 30s
- [ ] Process exit resets to idle, not removes
- [ ] `swift build && swift test` passes

---

### T-011d: Click session card → jump terminal (from upstream 668b889)
**Effort:** S | **Priority:** medium

**Vấn đề:** Phải click arrow button nhỏ để jump terminal. UX kém.

**Giải pháp:** Wrap entire session card trong Button. Remove TerminalJumpButton arrow. Keep terminal icon as badge.

**Files cần đọc:**
- Upstream: `SessionListView.swift` hoặc session card view — xem Button wrap
- Ours: `Sources/CodeIsland/SessionListView.swift`, related views

**Criteria:**
- [ ] Entire session card clickable → jump to terminal
- [ ] Button style (not onTapGesture — NSPanel issue)
- [ ] TerminalJumpButton arrow removed, terminal badge giữ lại
- [ ] Không break existing card interactions (approve, question)
- [ ] `swift build` passes

---

### T-011e: Stale subagent cleanup (from open-vibe-island a9229c7, 74e21ce)
**Effort:** S | **Priority:** medium

**Vấn đề:** Khi SubagentStop event bị miss, subagent indicators mắc kẹt forever.

**Giải pháp:** Timeout-based cleanup + turn-end detection. Khi parent nhận prompt mới → clear stale subagent state.

**Files cần đọc:**
- open-vibe-island: tìm subagent cleanup logic
- Ours: `Sources/CodeIslandCore/SessionSnapshot.swift` — SubagentState
- Ours: `Sources/CodeIslandCore/Models.swift` — subagent fields

**Criteria:**
- [ ] Subagent state cleanup khi parent nhận Prompt event (new turn)
- [ ] Timeout (60s?) cho subagents không có activity
- [ ] Cleanup logic trong reducer (pure function)
- [ ] Tests cho stale subagent scenarios
- [ ] `swift build && swift test` passes

---

### T-011f: Dynamic approval buttons (from open-vibe-island da2b129, e5e84fa)
**Effort:** M | **Priority:** medium

**Vấn đề:** Approval buttons hardcode "Allow"/"Deny". Claude Code gửi actual options trong event.

**Giải pháp:** Parse permission_suggestions từ hook event, hiển thị actual button labels.

**Files cần đọc:**
- open-vibe-island: tìm dynamic approval button logic
- Ours: `Sources/CodeIsland/ApprovalBarView.swift`
- Ours: `Sources/CodeIslandCore/Models.swift` — HookEvent fields

**Criteria:**
- [ ] Parse permission options từ hook event
- [ ] ApprovalBarView render dynamic buttons
- [ ] Fallback về Allow/Deny nếu không có options
- [ ] `swift build` passes

---

### T-011g: Auto-scroll activity feed (from notchi 265b2ce)
**Effort:** XS | **Priority:** low

**Vấn đề:** Khi expand/collapse assistant message, scroll position không update.

**Giải pháp:** ScrollViewReader + scrollTo khi expand/collapse state thay đổi.

**Files cần đọc:**
- notchi: `ExpandedPanelView.swift` — xem auto-scroll logic
- Ours: views hiển thị activity/chat feed

**Criteria:**
- [ ] Auto-scroll to bottom/expanded item khi expand
- [ ] Không scroll khi user đang manually scroll up
- [ ] `swift build` passes
