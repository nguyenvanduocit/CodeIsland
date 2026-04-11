import SwiftUI
import AppKit
import CodeIslandCore

// MARK: - Line Shape

struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

// MARK: - CLI Icon

private let cliIconFiles: [String: String] = [
    "claude": "claude",
]

private var cliIconCache: [String: NSImage] = [:]

func cliIcon(source: String, size: CGFloat = 16) -> NSImage? {
    let key = "\(source)_\(Int(size))"
    if let cached = cliIconCache[key] { return cached }
    guard let filename = cliIconFiles[source],
          let url = Bundle.module.url(forResource: filename, withExtension: "png", subdirectory: "Resources/cli-icons"),
          let image = NSImage(contentsOf: url)
    else { return nil }
    image.size = NSSize(width: size, height: size)
    cliIconCache[key] = image
    return image
}

// MARK: - Session Tag

struct SessionTag: View {
    let text: String
    var color: Color = .white.opacity(0.7)

    init(_ text: String, color: Color = .white.opacity(0.7)) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(color.opacity(0.12))
            )
    }
}

// MARK: - Typing Indicator (three bouncing dots)

struct TypingIndicator: View {
    let fontSize: CGFloat
    var label: String? = nil
    @State private var phase: CGFloat = -60

    var body: some View {
        if let label {
            Text(label)
                .font(.system(size: fontSize, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
                .overlay(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white.opacity(0.3), location: 0.4),
                            .init(color: .white.opacity(0.5), location: 0.5),
                            .init(color: .white.opacity(0.3), location: 0.6),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 60)
                    .offset(x: phase)
                    .mask(
                        Text(label)
                            .font(.system(size: fontSize, design: .monospaced))
                    )
                )
                .onAppear {
                    withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: false)) {
                        phase = 80
                    }
                }
                .onDisappear { phase = -60 }
        }
    }
}


// MARK: - Short Session ID

func shortSessionId(_ id: String) -> String {
    let clean = id.replacingOccurrences(of: "-", with: "")
    if clean.count >= 8 {
        return String(clean.suffix(4))
    }
    return String(id.prefix(4))
}

// MARK: - Strip Directives

/// Strip internal directives (::code-comment{}, ::git-*{}, etc.) from message text
/// so they don't leak into the UI preview.
func stripDirectives(_ text: String) -> String {
    var result: [String] = []
    var inDirective = false
    var braceDepth = 0

    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
        if inDirective {
            for ch in line {
                if ch == "{" { braceDepth += 1 }
                if ch == "}" { braceDepth -= 1 }
            }
            if braceDepth <= 0 {
                inDirective = false
                braceDepth = 0
            }
            continue
        }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("::") && trimmed.contains("{") {
            braceDepth = 0
            for ch in line {
                if ch == "{" { braceDepth += 1 }
                if ch == "}" { braceDepth -= 1 }
            }
            if braceDepth > 0 {
                inDirective = true
            }
            continue
        }
        result.append(String(line))
    }

    let cleaned = result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned
}

// MARK: - Decay Text

/// Holds a text value visible for at least `minDuration` seconds after the source goes nil.
/// New non-nil values replace immediately; nil triggers a delayed fade-out.
@Observable
@MainActor
final class DecayState {
    private(set) var displayedText: String?
    private var decayTask: Task<Void, Never>?
    private let minDuration: Duration

    init(minDuration: Duration = .seconds(2)) {
        self.minDuration = minDuration
    }

    func update(_ newValue: String?) {
        if let text = newValue {
            decayTask?.cancel()
            decayTask = nil
            displayedText = text
        } else if displayedText != nil && decayTask == nil {
            let duration = minDuration
            decayTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: duration)
                guard !Task.isCancelled, let self else { return }
                withAnimation(.easeOut(duration: 0.3)) {
                    self.displayedText = nil
                }
                self.decayTask = nil
            }
        }
    }
}
