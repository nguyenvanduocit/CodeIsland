# T-006: Typed HookEvent thay rawJSON

> Thay `rawJSON: [String: Any]` bằng typed structs cho từng event type. Học từ open-vibe-island AgentEvent enum.

- **priority**: high
- **effort**: M

## Context

Hiện tại `HookEvent.rawJSON` là `[String: Any]` — untyped, không Codable, dễ viết sai key.
open-vibe-island dùng `AgentEvent` enum 10 cases với associated values, custom Codable (discriminator pattern).

## Reference

- `references/open-vibe-island/Sources/OpenIslandCore/AgentEvent.swift:196-305` — enum definition
- `references/open-vibe-island/Sources/OpenIslandCore/AgentEvent.swift:208-304` — custom Codable
- `Sources/CodeIsland/Models.swift` — current HookEvent

## Approach

- Tạo typed payload structs cho mỗi hook event type (PreToolUse, PostToolUse, Stop, etc.)
- HookEvent giữ enum pattern tương tự, associated values thay vì rawJSON
- Custom Codable decode từ JSON hook server nhận
- Cập nhật reducer `reduceEvent()` dùng typed payloads thay vì dict access

#### Criteria

- [ ] HookEvent có typed payload cho mỗi event type
- [ ] rawJSON: [String: Any] bị loại bỏ hoàn toàn
- [ ] HookEvent conform Codable + Sendable
- [ ] reduceEvent() dùng typed fields thay vì dict subscript
- [ ] swift build && swift test pass
