import Foundation
import os.log

private let logger = Logger(subsystem: "com.codeisland", category: "EmotionState")

@MainActor
@Observable
public final class EmotionState {
    public private(set) var currentEmotion: MascotEmotion = .neutral
    public private(set) var scores: [MascotEmotion: Double] = [
        .happy: 0.0,
        .sad: 0.0
    ]

    public static let sadThreshold = 0.45
    public static let happyThreshold = 0.6
    public static let sobEscalationThreshold = 0.9
    public static let intensityDampen = 0.5
    public static let decayRate = 0.92
    public static let interEmotionDecay = 0.9
    public static let neutralCounterDecay = 0.85
    public static let decayInterval: Duration = .seconds(60)

    public init() {}

    public func recordEmotion(_ rawEmotion: String, intensity: Double, prompt: String) {
        let emotion = MascotEmotion(rawValue: rawEmotion)

        if let emotion, emotion != .neutral {
            let dampened = intensity * Self.intensityDampen
            scores[emotion, default: 0.0] = min(scores[emotion, default: 0.0] + dampened, 1.0)
            for key in scores.keys where key != emotion {
                scores[key, default: 0.0] *= Self.interEmotionDecay
            }
        } else {
            for key in scores.keys {
                scores[key, default: 0.0] *= Self.neutralCounterDecay
            }
        }

        updateCurrentEmotion()

        let truncatedPrompt = String(prompt.prefix(60))
        logger.info("[Emotion] \"\(truncatedPrompt, privacy: .public)\" → detected: \(rawEmotion, privacy: .public) (\(String(format: "%.2f", intensity), privacy: .public))")
    }

    public func decayAll() {
        var anyChanged = false
        for key in scores.keys {
            let old = scores[key, default: 0.0]
            let new = old * Self.decayRate
            scores[key] = new < 0.01 ? 0.0 : new
            if scores[key] != old { anyChanged = true }
        }
        if anyChanged {
            updateCurrentEmotion()
        }
    }

    private func updateCurrentEmotion() {
        let best = scores.max(by: { $0.value < $1.value })
        if let best {
            let threshold = best.key == .sad ? Self.sadThreshold : Self.happyThreshold
            if best.value >= threshold {
                if best.key == .sad && best.value >= Self.sobEscalationThreshold {
                    currentEmotion = .sob
                } else {
                    currentEmotion = best.key
                }
            } else {
                currentEmotion = .neutral
            }
        } else {
            currentEmotion = .neutral
        }
    }
}
