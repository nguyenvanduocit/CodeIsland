import SwiftUI
import CodeIslandCore

struct QuestionBar: View {
    let question: String
    let options: [String]?
    let descriptions: [String]?
    let sessionSource: String?
    let sessionContext: String?
    let queuePosition: Int
    let queueTotal: Int
    let onAnswer: (String) -> Void
    let onSkip: () -> Void

    @State private var textInput = ""
    @FocusState private var isFocused: Bool
    @State private var selectedIndex: Int? = nil

    private let cyan = Color(red: 0.4, green: 0.7, blue: 1.0)

    var body: some View {
        VStack(spacing: 8) {
            // Session context
            if sessionSource != nil || sessionContext != nil {
                HStack(spacing: 5) {
                    if let src = sessionSource, let icon = cliIcon(source: src, size: 12) {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 12, height: 12)
                    }
                    if let cwd = sessionContext {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.white.opacity(0.5))
                        Text((cwd as NSString).lastPathComponent)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
            }

            // Header
            HStack(spacing: 6) {
                Text("?")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(cyan)
                Text(question)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(3)
                if queueTotal > 1 {
                    Text("\(queuePosition)/\(queueTotal)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                Spacer()
            }
            .padding(.horizontal, 14)

            // Options
            if let options = options, !options.isEmpty {
                VStack(spacing: 4) {
                    ForEach(Array(options.enumerated()), id: \.offset) { idx, option in
                        let desc = descriptions?.indices.contains(idx) == true ? descriptions?[idx] : nil
                        OptionRow(index: idx + 1, label: option, description: desc, isSelected: selectedIndex == idx, accent: cyan) {
                            selectedIndex = idx
                            onAnswer(option)
                        }
                    }
                }
                .padding(.horizontal, 14)
            } else {
                // Text input
                HStack(spacing: 6) {
                    Text(">")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.3, green: 0.85, blue: 0.4))
                    TextField(L10n.shared["type_answer"], text: $textInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.white)
                        .focused($isFocused)
                        .onSubmit {
                            if !textInput.isEmpty { onAnswer(textInput) }
                        }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
                .padding(.horizontal, 14)
            }

            // Skip button
            HStack(spacing: 6) {
                PixelButton(
                    label: L10n.shared["skip"],
                    fg: .white.opacity(0.6),
                    bg: Color.white.opacity(0.06),
                    border: Color.white.opacity(0.12),
                    action: onSkip
                )
                if options == nil || options?.isEmpty == true {
                    PixelButton(
                        label: L10n.shared["submit"],
                        fg: .white.opacity(0.95),
                        bg: Color(red: 0.16, green: 0.38, blue: 0.18),
                        border: Color(red: 0.28, green: 0.62, blue: 0.32),
                        action: { if !textInput.isEmpty { onAnswer(textInput) } }
                    )
                }
            }
            .padding(.horizontal, 14)
        }
        .padding(.vertical, 10)
        .onAppear { isFocused = true }
    }
}

// MARK: - Option Row

private struct OptionRow: View {
    let index: Int
    let label: String
    let description: String?
    let isSelected: Bool
    let accent: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(hovering ? "▸" : " ")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent)
                    .frame(width: 10)
                Text("\(index).")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(accent.opacity(hovering ? 1 : 0.6))
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 10.5, weight: hovering ? .semibold : .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(hovering ? 1 : 0.75))
                    if let description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(2)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(hovering ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(hovering ? accent.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(NotchAnimation.micro) { hovering = h } }
    }
}
