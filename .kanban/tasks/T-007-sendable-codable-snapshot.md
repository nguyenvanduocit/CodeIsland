# T-007: SessionSnapshot conform Sendable + Codable

> Thêm Sendable + Codable cho SessionSnapshot, loại bỏ PersistedSession mapping layer.

- **priority**: high
- **effort**: S

## Context

Hiện tại `SessionSnapshot` không conform Sendable hay Codable. Persistence dùng `PersistedSession` riêng làm trung gian.
open-vibe-island's `AgentSession` conform cả `Equatable, Identifiable, Codable, Sendable` với custom CodingKeys exclude transient fields.

## Reference

- `references/open-vibe-island/Sources/OpenIslandCore/AgentSession.swift:261-373` — custom CodingKeys, exclude transient fields
- `Sources/CodeIslandCore/SessionSnapshot.swift` — current model
- `Sources/CodeIsland/SessionPersistence.swift` — PersistedSession mapping

## Approach

- SessionSnapshot conform Codable với custom CodingKeys (exclude transient runtime state)
- SessionSnapshot conform Sendable
- Xóa hoặc simplify PersistedSession layer — encode/decode trực tiếp SessionSnapshot
- TokenUsage đã Sendable, đảm bảo tất cả nested types cũng conform

#### Criteria

- [ ] SessionSnapshot: Codable, Sendable
- [ ] Custom CodingKeys exclude transient fields (timers, process state)
- [ ] PersistedSession mapping layer simplified hoặc removed
- [ ] Persistence round-trip test: encode → decode → equal
- [ ] swift build && swift test pass
