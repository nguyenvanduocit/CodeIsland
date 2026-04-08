# T-010: Sprite mascot system từ notchi

> Port sprite animation system: task states + emotions + sprite sheets + bob/tremble motion.

- **priority**: medium
- **effort**: L

## Context

notchi có hệ thống mascot pixel art với:
- NotchiTask enum (idle/working/sleeping/compacting/waiting) — mỗi task có FPS, bob amplitude, walk frequency riêng
- NotchiEmotion enum (neutral/happy/sad/sob) — emotion decay theo thời gian
- Sprite sheet rendering (6 frames, TimelineView animation)
- Bob + tremble + sway motion helpers
- SpriteHandoff cho transitions collapsed ↔ expanded
- 17 sprite sheet assets (task_emotion combinations với fallback chain)

CodeIsland đã có `MascotView`, `BuddyView`, `PixelCharacterView` — cần evaluate và integrate.

## Reference

- `references/notchi/notchi/notchi/Models/NotchiState.swift:1-127` — task + emotion state
- `references/notchi/notchi/notchi/Models/EmotionState.swift:1-89` — emotion scoring + decay
- `references/notchi/notchi/notchi/Views/Components/SpriteSheetView.swift:1-53` — sprite rendering
- `references/notchi/notchi/notchi/Views/Components/BobAnimation.swift:1-24` — motion math
- `references/notchi/notchi/notchi/Views/SpriteHandoffVisuals.swift:1-53` — transition effects

## Approach

- Port NotchiState (task + emotion) vào CodeIslandCore — adapt cho SessionSnapshot state
- Port sprite sheet renderer + animation helpers
- Port bob/tremble motion — giữ pixel aesthetic hiện tại
- Assets: cần tạo hoặc port sprite sheets (17 variants)
- Integrate với existing MascotView/BuddyView — replace hoặc enhance
- Emotion detection từ hook events (user prompt sentiment, tool failures)

#### Criteria

- [ ] MascotState model (task + emotion) trong CodeIslandCore
- [ ] Sprite sheet renderer với TimelineView animation
- [ ] Bob + tremble motion helpers
- [ ] Emotion decay system (60s interval, 0.92x rate)
- [ ] Sprite fallback chain (exact → fallback emotion → neutral)
- [ ] Integrate với notch panel (collapsed + expanded states)
- [ ] Sprite assets included (ít nhất idle/working/sleeping × neutral/happy/sad)
- [ ] swift build && swift test pass
