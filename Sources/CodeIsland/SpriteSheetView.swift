import SwiftUI
import AppKit

struct SpriteSheetView: View {
    let spriteSheet: String
    var frameCount: Int = 6
    var columns: Int = 6
    var fps: Double = 10
    var isAnimating: Bool = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / fps, paused: !isAnimating)) { timeline in
            SpriteFrameView(
                spriteSheet: spriteSheet,
                frameCount: frameCount,
                columns: columns,
                currentFrame: currentFrame(at: timeline.date)
            )
        }
    }

    private func currentFrame(at date: Date) -> Int {
        guard isAnimating else { return 0 }
        let elapsed = date.timeIntervalSinceReferenceDate
        return Int(elapsed * fps) % frameCount
    }
}

private struct SpriteFrameView: View {
    let spriteSheet: String
    let frameCount: Int
    let columns: Int
    let currentFrame: Int

    var body: some View {
        GeometryReader { geometry in
            let frameWidth = geometry.size.width
            let frameHeight = geometry.size.height
            let rows = (frameCount + columns - 1) / columns

            let col = currentFrame % columns
            let row = currentFrame / columns

            if let nsImage = loadSpriteImage(named: spriteSheet) {
                Image(nsImage: nsImage)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: frameWidth * CGFloat(columns),
                           height: frameHeight * CGFloat(rows))
                    .offset(x: -frameWidth * CGFloat(col),
                            y: -frameHeight * CGFloat(row))
            }
        }
        .clipped()
    }

    private func loadSpriteImage(named name: String) -> NSImage? {
        if let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "sprites") {
            return NSImage(contentsOf: url)
        }
        // Fallback: try without subdirectory
        if let url = Bundle.module.url(forResource: name, withExtension: "png") {
            return NSImage(contentsOf: url)
        }
        return nil
    }
}
