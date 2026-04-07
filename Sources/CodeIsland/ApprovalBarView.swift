import SwiftUI
import CodeIslandCore

struct ApprovalBar: View {
    let tool: String
    let toolInput: [String: Any]?
    let queuePosition: Int
    let queueTotal: Int
    let onAllow: () -> Void
    let onAlwaysAllow: () -> Void
    let onDeny: () -> Void

    private var fileName: String? {
        guard let fp = toolInput?["file_path"] as? String else { return nil }
        return (fp as NSString).lastPathComponent
    }

    private var filePath: String? {
        toolInput?["file_path"] as? String
    }

    private var serverName: String? {
        toolInput?["server_name"] as? String
    }

    var body: some View {
        VStack(spacing: 8) {
            // Tool name + file context
            HStack(spacing: 6) {
                Text("!")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(red: 1.0, green: 0.7, blue: 0.28))
                Text(tool)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(red: 1.0, green: 0.7, blue: 0.28))
                if let server = serverName {
                    Text("(\(server))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Color(red: 0.6, green: 0.7, blue: 0.9))
                }
                if let name = fileName {
                    Text(name)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                }
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

            // Tool-specific detail view
            if toolInput != nil {
                toolDetailView
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.04))
            }

            // Pixel-style buttons
            HStack(spacing: 6) {
                PixelButton(label: L10n.shared["deny"], fg: .white.opacity(0.95), bg: Color(red: 0.45, green: 0.12, blue: 0.12), border: Color(red: 0.7, green: 0.25, blue: 0.25), action: onDeny)
                PixelButton(label: L10n.shared["allow_once"], fg: .white.opacity(0.95), bg: Color(red: 0.16, green: 0.38, blue: 0.18), border: Color(red: 0.28, green: 0.62, blue: 0.32), action: onAllow)
                PixelButton(label: L10n.shared["always"], fg: .white.opacity(0.95), bg: Color(red: 0.14, green: 0.28, blue: 0.52), border: Color(red: 0.28, green: 0.48, blue: 0.82), action: onAlwaysAllow)
            }
            .padding(.horizontal, 14)
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var toolDetailView: some View {
        switch tool {
        case "Bash":
            VStack(alignment: .leading, spacing: 2) {
                if let cmd = toolInput?["command"] as? String {
                    HStack(alignment: .top, spacing: 4) {
                        Text("$")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(red: 0.3, green: 0.85, blue: 0.4))
                        Text(cmd)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(3)
                    }
                }
            }

        case "Edit":
            VStack(alignment: .leading, spacing: 3) {
                if let fp = filePath {
                    Text(fp)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                if let old = toolInput?["old_string"] as? String {
                    HStack(alignment: .top, spacing: 4) {
                        Text("−")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(red: 1.0, green: 0.4, blue: 0.4))
                        Text(old.prefix(120))
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.7))
                            .lineLimit(2)
                    }
                }
                if let new = toolInput?["new_string"] as? String {
                    HStack(alignment: .top, spacing: 4) {
                        Text("+")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(red: 0.3, green: 0.85, blue: 0.4))
                        Text(new.prefix(120))
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(Color(red: 0.3, green: 0.85, blue: 0.4).opacity(0.7))
                            .lineLimit(2)
                    }
                }
            }

        case "Write":
            VStack(alignment: .leading, spacing: 3) {
                if let fp = filePath {
                    Text(fp)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                if let content = toolInput?["content"] as? String {
                    Text(content.prefix(200))
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(4)
                }
            }

        case "Read":
            VStack(alignment: .leading, spacing: 2) {
                if let fp = filePath {
                    Text(fp)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                if let offset = toolInput?["offset"] as? Int,
                   let limit = toolInput?["limit"] as? Int {
                    Text("\(L10n.shared["lines"]) \(offset + 1)–\(offset + limit)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

        case "Grep":
            VStack(alignment: .leading, spacing: 2) {
                if let pattern = toolInput?["pattern"] as? String {
                    HStack(alignment: .top, spacing: 4) {
                        Text("/")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(red: 0.9, green: 0.6, blue: 0.9))
                        Text(pattern)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color(red: 0.9, green: 0.6, blue: 0.9).opacity(0.8))
                            .lineLimit(2)
                    }
                }
                if let path = toolInput?["path"] as? String {
                    Text(path)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

        case "Glob":
            VStack(alignment: .leading, spacing: 2) {
                if let pattern = toolInput?["pattern"] as? String {
                    Text(pattern)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color(red: 0.6, green: 0.8, blue: 1.0))
                        .lineLimit(2)
                }
                if let path = toolInput?["path"] as? String {
                    Text(path)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

        default:
            VStack(alignment: .leading, spacing: 2) {
                if let input = toolInput {
                    ForEach(Array(input.keys.sorted().prefix(4)), id: \.self) { key in
                        let val = input[key].map { "\($0)" } ?? ""
                        HStack(alignment: .top, spacing: 4) {
                            Text(key)
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color(red: 0.6, green: 0.7, blue: 0.9))
                            Text(String(val.prefix(100)))
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Pixel Button

struct PixelButton: View {
    let label: String
    let fg: Color
    let bg: Color
    let border: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(fg)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(hovering ? bg.opacity(1.5) : bg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(hovering ? border : border.opacity(0.4), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(NotchAnimation.micro) { hovering = h } }
    }
}
