# T-009: Event-driven wiring thay callbacks trong setupServices()

> Thay closure callbacks (onSurfaceChange, onActiveSessionChange, sessionExists...) bằng event enum hoặc direct method calls.

- **priority**: medium
- **effort**: M

## Context

`AppState.setupServices()` wire services bằng closures — dễ retain cycle, khó trace.
open-vibe-island dùng async stream + event enum, không có callback hell.

## Reference

- `references/open-vibe-island/Sources/OpenIslandApp/AppModel.swift:466-480` — async stream subscription
- `Sources/CodeIsland/AppState.swift:46-69` — current callback wiring

## Approach

- Services gọi method trực tiếp trên AppState thay vì qua closures
- Hoặc dùng pattern đơn giản: services nhận weak reference tới AppState protocol
- Không over-engineer — avoid coordinator forwarding explosion của open-vibe-island

#### Criteria

- [ ] setupServices() không còn closure callbacks
- [ ] Services giao tiếp qua direct method calls hoặc protocol
- [ ] Không có retain cycle risks
- [ ] swift build && swift test pass
