import Foundation

public enum MascotTask: String, Sendable, CaseIterable {
    case idle       // AgentStatus.idle
    case working    // AgentStatus.running
    case sleeping   // After idle timeout
    case compacting // AgentStatus.processing (during compact)
    case waiting    // AgentStatus.waitingApproval, .waitingQuestion

    public var animationFPS: Double {
        switch self {
        case .compacting: return 6.0
        case .sleeping: return 2.0
        case .idle, .waiting: return 3.0
        case .working: return 4.0
        }
    }

    public var bobDuration: Double {
        switch self {
        case .sleeping:        return 4.0
        case .idle, .waiting:  return 1.5
        case .working:         return 0.4
        case .compacting:      return 0.5
        }
    }

    public var bobAmplitude: CGFloat {
        switch self {
        case .sleeping, .compacting: return 0
        case .idle:                  return 1.5
        case .waiting:               return 0.5
        case .working:               return 0.5
        }
    }

    public var frameCount: Int {
        switch self {
        case .compacting: return 5
        default:          return 6
        }
    }

    public var columns: Int {
        switch self {
        case .compacting: return 5
        default:          return 6
        }
    }
}

public enum MascotEmotion: String, Sendable, CaseIterable {
    case neutral, happy, sad, sob

    public var swayAmplitude: Double {
        switch self {
        case .neutral: return 0.5
        case .happy:   return 1.0
        case .sad:     return 0.25
        case .sob:     return 0.15
        }
    }
}

public struct MascotState: Sendable, Equatable {
    public let task: MascotTask
    public let emotion: MascotEmotion

    public init(task: MascotTask, emotion: MascotEmotion = .neutral) {
        self.task = task
        self.emotion = emotion
    }

    /// Sprite sheet name with fallback chain: exact → sad (for sob) → neutral.
    public var spriteSheetName: String {
        let exact = "\(task.rawValue)_\(emotion.rawValue)"
        // Fallback logic is handled at load time by the view layer which checks Bundle.module
        return exact
    }

    /// Ordered fallback names to try when loading the sprite image.
    public var spriteSheetFallbackNames: [String] {
        var names: [String] = ["\(task.rawValue)_\(emotion.rawValue)"]
        if emotion == .sob {
            names.append("\(task.rawValue)_sad")
        }
        names.append("\(task.rawValue)_neutral")
        return names
    }

    public var animationFPS: Double { task.animationFPS }
    public var bobDuration: Double { task.bobDuration }

    public var bobAmplitude: CGFloat {
        switch emotion {
        case .sob: return 0
        case .sad: return task.bobAmplitude * 0.5
        default:   return task.bobAmplitude
        }
    }

    public var swayAmplitude: Double { emotion.swayAmplitude }
    public var frameCount: Int { task.frameCount }
    public var columns: Int { task.columns }

    // MARK: - AgentStatus mapping

    public static func from(status: AgentStatus, emotion: MascotEmotion = .neutral) -> MascotState {
        let task: MascotTask
        switch status {
        case .idle:             task = .idle
        case .processing:       task = .working
        case .running:          task = .working
        case .waitingApproval:  task = .waiting
        case .waitingQuestion:  task = .waiting
        }
        return MascotState(task: task, emotion: emotion)
    }

    // MARK: - Convenience

    public static let idle      = MascotState(task: .idle)
    public static let working   = MascotState(task: .working)
    public static let sleeping  = MascotState(task: .sleeping)
    public static let compacting = MascotState(task: .compacting)
    public static let waiting   = MascotState(task: .waiting)
}
