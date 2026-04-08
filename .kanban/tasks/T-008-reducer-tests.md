# T-008: Test coverage cho reduceEvent()

> Pure reducer chưa có test. Thêm test cho mỗi event type và edge cases.

- **priority**: high
- **effort**: M

## Context

`reduceEvent()` là pure function — dễ test nhất trong codebase. Hiện tại 7 test files nhưng reducer chưa được cover.
open-vibe-island có `SessionStateTests` dùng Swift Testing framework với pattern: tạo state → apply event → verify state + side effects.

## Reference

- `references/open-vibe-island/Tests/OpenIslandCoreTests/SessionStateTests.swift:6-225` — pure reducer tests
- `Sources/CodeIslandCore/SessionSnapshot.swift:287-516` — reducer to test

## Approach

- Dùng Swift Testing (`@Test`, `#expect`) thay XCTest
- Mỗi event type ít nhất 1 test case
- Edge cases: duplicate session, unknown session, state preservation khi actionable

#### Criteria

- [ ] Test mỗi event type trong reduceEvent() (sessionStart, toolUse, prompt, stop, etc.)
- [ ] Test side effects trả về đúng (playSound, tryMonitorSession, etc.)
- [ ] Test edge cases: session không tồn tại, duplicate events
- [ ] Dùng Swift Testing framework
- [ ] swift test pass
