import SwiftUI
import CodeIslandCore

/// Sprite-sheet based mascot that animates based on MascotState.
struct SpriteMascotView: View {
    let state: MascotState
    var size: CGFloat = 27

    @Environment(\.mascotSpeed) private var speed

    var body: some View {
        TimelineView(.animation) { timeline in
            let date = timeline.date
            let effectiveFPS = state.animationFPS * speed
            let effectiveBobDuration = state.bobDuration / max(speed, 0.01)

            SpriteSheetView(
                spriteSheet: resolvedSpriteName,
                frameCount: state.frameCount,
                columns: state.columns,
                fps: effectiveFPS,
                isAnimating: speed > 0
            )
            .frame(width: size, height: size)
            .offset(
                x: trembleOffset(at: date, amplitude: state.emotion == .sob ? 2 : 0),
                y: bobOffset(at: date, duration: effectiveBobDuration, amplitude: state.bobAmplitude)
            )
        }
    }

    /// Resolves the sprite image name using the fallback chain.
    private var resolvedSpriteName: String {
        for name in state.spriteSheetFallbackNames {
            if spriteExists(name) { return name }
        }
        return state.spriteSheetFallbackNames.last ?? "idle_neutral"
    }

    private func spriteExists(_ name: String) -> Bool {
        Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "sprites") != nil
    }
}

/// Convenience initializer that maps AgentStatus + EmotionState to SpriteMascotView.
struct AgentSpriteMascotView: View {
    let status: AgentStatus
    let emotion: MascotEmotion
    var size: CGFloat = 27

    var body: some View {
        SpriteMascotView(
            state: MascotState.from(status: status, emotion: emotion),
            size: size
        )
    }
}
