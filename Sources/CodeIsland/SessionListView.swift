import SwiftUI
import AppKit
import CodeIslandCore

// MARK: - Session List

struct SessionListView: View {
    var appState: AppState
    /// When set, only show this session (auto-expand on completion)
    var onlySessionId: String? = nil
    @AppStorage(SettingsKey.maxVisibleSessions) private var maxVisibleSessions = SettingsDefaults.maxVisibleSessions

    private var sessionIds: [String] {
        if let only = onlySessionId, appState.sessions[only] != nil {
            return [only]
        }
        return appState.sortedSessionIds
    }

    var body: some View {
        let ids = sessionIds
        let needsScroll = onlySessionId == nil && ids.count > maxVisibleSessions
        let content = VStack(spacing: 6) {
            ForEach(ids, id: \.self) { sessionId in
                if let session = appState.sessions[sessionId] {
                    SessionCard(
                        sessionId: sessionId,
                        session: session,
                        isCompletion: onlySessionId != nil
                    )
                }
            }

            // "Show all sessions" — hover with delay to expand
            if onlySessionId != nil && appState.sessions.count > 1 {
                SessionsExpandLink(count: appState.sessions.count) {
                    withAnimation(NotchAnimation.open) {
                        appState.surface = .sessionList
                        appState.cancelCompletionQueue()
                    }
                }
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 6)

        if needsScroll {
            ThinScrollView(maxHeight: CGFloat(maxVisibleSessions) * 90) {
                content
            }
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0, bottomLeadingRadius: 20,
                    bottomTrailingRadius: 20, topTrailingRadius: 0,
                    style: .continuous
                )
            )
        } else {
            content
        }
    }
}

/// Thin overlay scrollbar via NSScrollView — ignores system "show scrollbar" preference.
private struct ThinScrollView<Content: View>: NSViewRepresentable {
    let maxHeight: CGFloat
    @ViewBuilder let content: Content

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller?.controlSize = .mini
        scrollView.drawsBackground = false
        scrollView.scrollerKnobStyle = .light

        let hosting = NSHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = hosting

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            scrollView.heightAnchor.constraint(lessThanOrEqualToConstant: maxHeight),
        ])

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        if let hosting = scrollView.documentView as? NSHostingView<Content> {
            hosting.rootView = content
        }
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller?.controlSize = .mini
    }
}

private struct SessionIdCopyButton: View {
    let session: SessionSnapshot
    let sessionId: String
    var fontSize: CGFloat = 10

    @State private var hovering = false
    @State private var copied = false
    @State private var resetTask: Task<Void, Never>?

    private var compactLabel: String {
        "#\(shortSessionId(sessionId))"
    }

    var body: some View {
        Button(action: copySessionId) {
            HStack(spacing: 4) {
                Text(compactLabel)
                    .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: max(8, fontSize - 1), weight: .semibold))
            }
            .foregroundStyle(copied ? Color(red: 0.3, green: 0.85, blue: 0.4) : .white.opacity(hovering ? 0.68 : 0.42))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(hovering || copied ? 0.08 : 0.001))
            )
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(NotchAnimation.micro) { hovering = h }
        }
        .onDisappear {
            resetTask?.cancel()
        }
        .help("Copy session ID")
    }

    private func copySessionId() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sessionId, forType: .string)
        copied = true
        resetTask?.cancel()
        resetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            copied = false
        }
    }
}

private struct SessionCardMenu: View {
    let session: SessionSnapshot
    let sessionId: String
    let fontSize: CGFloat

    @State private var hovering = false

    var body: some View {
        Menu {
            Button {
                TerminalActivator.forkSession(session: session, sessionId: sessionId)
            } label: {
                Label("Fork Session", systemImage: "arrow.branch")
            }

            Button(role: .destructive) {
                if let pid = session.cliPid, pid > 0 {
                    kill(pid, SIGTERM)
                }
            } label: {
                Label("Kill Process", systemImage: "xmark.circle")
            }
            .disabled(session.cliPid == nil || session.cliPid == 0)

            Divider()

            Button {
                let text = session.recentMessages.map { msg in
                    switch msg.kind {
                    case .user: return "> \(msg.text)"
                    case .assistant: return "$ \(msg.text)"
                    case .taskNotification: return "• \(msg.text)"
                    }
                }.joined(separator: "\n\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } label: {
                Label("Export Chat", systemImage: "square.and.arrow.up")
            }
            .disabled(session.recentMessages.isEmpty)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(.white.opacity(hovering ? 0.68 : 0.42))
                .frame(width: 20, height: 20)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { h in
            withAnimation(NotchAnimation.micro) { hovering = h }
        }
    }
}

private struct SessionIdentityLine: View {
    let session: SessionSnapshot
    let sessionId: String
    let projectFontSize: CGFloat
    let projectColor: Color
    let sessionFontSize: CGFloat
    let sessionColor: Color
    let dividerColor: Color
    let cardHovering: Bool

    private var displaySessionId: String { session.displaySessionId(sessionId: sessionId) }

    var body: some View {
        HStack(spacing: 4) {
            ProjectNameLink(
                name: session.projectDisplayName,
                cwd: session.cwd,
                fontSize: projectFontSize,
                color: projectColor,
                cardHovering: cardHovering
            )
            .layoutPriority(2)

            if let sessionLabel = session.sessionLabel {
                Text("#\(sessionLabel)")
                    .font(.system(size: sessionFontSize, weight: .medium, design: .monospaced))
                    .foregroundStyle(sessionColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)

                Text("·")
                    .font(.system(size: sessionFontSize, weight: .semibold, design: .monospaced))
                    .foregroundStyle(dividerColor)

                SessionIdCopyButton(
                    session: session,
                    sessionId: displaySessionId,
                    fontSize: sessionFontSize
                )
                .fixedSize()
            } else {
                SessionIdCopyButton(
                    session: session,
                    sessionId: displaySessionId,
                    fontSize: sessionFontSize
                )
                .fixedSize()
            }

        }
    }
}

private struct ProjectNameLink: View {
    let name: String
    let cwd: String?
    let fontSize: CGFloat
    let color: Color
    let cardHovering: Bool

    var body: some View {
        Button {
            if let cwd { NSWorkspace.shared.open(URL(fileURLWithPath: cwd)) }
        } label: {
            Text(name)
                .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .truncationMode(.tail)
                .overlay(alignment: .bottom) {
                    if cwd != nil {
                        GeometryReader { geo in
                            Path { path in
                                path.move(to: CGPoint(x: 0, y: geo.size.height))
                                path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                            }
                            .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                            .foregroundStyle(color.opacity(cardHovering ? 0.5 : 0.2))
                        }
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(cwd == nil)
        .help(cwd != nil ? "\(L10n.shared["open_path"]) \(cwd!)" : "")
    }
}

private struct SessionsExpandLink: View {
    let count: Int
    let action: () -> Void
    @State private var hovering = false
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Rectangle().fill(.white.opacity(0.15)).frame(height: 1)
                Text("\(count) \(L10n.shared["n_sessions"])")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(hovering ? 0.7 : 0.45))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(hovering ? 0.5 : 0.3))
                Rectangle().fill(.white.opacity(0.15)).frame(height: 1)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(NotchAnimation.micro) { hovering = h }
            hoverTask?.cancel()
            hoverTask = nil
            if h {
                hoverTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.6))
                    guard !Task.isCancelled else { return }
                    action()
                }
            }
        }
    }
}

// MARK: - Session Status Bar

private struct SessionStatusBar: View {
    let session: SessionSnapshot
    let fontSize: CGFloat
    private let dimColor = Color.white.opacity(0.35)
    private let sepColor = Color.white.opacity(0.15)

    var body: some View {
        HStack(spacing: 0) {
            // Elapsed time since user sent message
            if let startedAt = session.processingStartedAt, session.status != .idle {
                ElapsedTimerView(startedAt: startedAt, fontSize: fontSize)
            }

            // Active subagents
            if !session.subagents.isEmpty {
                StatusDot()
                let activeCount = session.activeSubagentCount
                HStack(spacing: 2) {
                    Image(systemName: "person.2")
                        .font(.system(size: max(7, fontSize - 3), weight: .medium))
                        .foregroundStyle(activeCount > 0 ? Color(red: 0.3, green: 0.85, blue: 0.4) : dimColor)
                    Text("\(session.subagents.count)")
                        .foregroundStyle(activeCount > 0 ? Color(red: 0.3, green: 0.85, blue: 0.4) : dimColor)
                }
                .font(.system(size: max(8, fontSize - 1), weight: .medium, design: .monospaced))
            }

            // Current tool (when running)
            if session.status == .running, let tool = session.currentTool {
                StatusDot()
                HStack(spacing: 2) {
                    Circle()
                        .fill(Color(red: 0.3, green: 0.85, blue: 0.4))
                        .frame(width: 4, height: 4)
                    Text(tool)
                        .foregroundStyle(Color(red: 0.3, green: 0.85, blue: 0.4).opacity(0.8))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.system(size: max(8, fontSize - 1), weight: .medium, design: .monospaced))
            }

            Spacer(minLength: 0)
        }
    }

}

private struct ElapsedTimerView: View {
    let startedAt: Date
    let fontSize: CGFloat

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 1)) { context in
            let elapsed = Int(context.date.timeIntervalSince(startedAt))
            let minutes = elapsed / 60
            let seconds = elapsed % 60
            HStack(spacing: 3) {
                Image(systemName: "clock")
                    .font(.system(size: max(7, fontSize - 2), weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.4))
                Text(minutes > 0 ? "\(minutes)m\(String(format: "%02d", seconds))s" : "\(seconds)s")
                    .font(.system(size: max(8, fontSize - 1), weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }
    }
}

private struct StatusDot: View {
    var body: some View {
        Text("·")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.2))
            .padding(.horizontal, 4)
    }
}

private struct SessionCard: View {
    let sessionId: String
    let session: SessionSnapshot
    var isCompletion: Bool = false
    @State private var hovering = false
    @AppStorage(SettingsKey.contentFontSize) private var contentFontSize = SettingsDefaults.contentFontSize
    @AppStorage(SettingsKey.aiMessageLines) private var aiMessageLines = SettingsDefaults.aiMessageLines
    private var fontSize: CGFloat { CGFloat(contentFontSize) }
    private var aiLineLimit: Int? { aiMessageLines > 0 ? aiMessageLines : nil }
    private var statusNameColor: Color {
        if session.status == .idle && session.interrupted {
            return Color(red: 1.0, green: 0.45, blue: 0.35)
        }
        switch session.status {
        case .processing, .running:              return Color(red: 0.3, green: 0.85, blue: 0.4)
        case .waitingApproval, .waitingQuestion:  return Color(red: 1.0, green: 0.6, blue: 0.2)
        case .idle:                               return .white
        }
    }

    var body: some View {
        Button {
            TerminalActivator.activate(session: session, sessionId: sessionId)
        } label: {
        VStack(alignment: .leading, spacing: 6) {
            // Header: mascot + project name + session info + status
            HStack(alignment: .center, spacing: 6) {
                MascotView(source: session.source, status: session.status, size: 18)

                SessionIdentityLine(
                    session: session,
                    sessionId: sessionId,
                    projectFontSize: fontSize + 2,
                    projectColor: statusNameColor,
                    sessionFontSize: fontSize,
                    sessionColor: .white.opacity(0.76),
                    dividerColor: .white.opacity(0.28),
                    cardHovering: hovering
                )

                SessionStatusBar(session: session, fontSize: fontSize)

                Spacer(minLength: 4)

                HStack(spacing: 4) {
                    if session.interrupted {
                        SessionTag("INT", color: Color(red: 1.0, green: 0.6, blue: 0.2))
                    }
                    if let usage = session.tokenUsage, usage.totalTokens > 0 {
                        SessionTag("✦ \(usage.formattedTotal)", color: tokenColor(usage))
                            .help(tokenTooltip(usage))
                    }
                }

                SessionCardMenu(session: session, sessionId: sessionId, fontSize: fontSize)
            }

            // Chat history + live status
            if !session.recentMessages.isEmpty || session.status != .idle {
                VStack(alignment: .leading, spacing: 3) {
                    // Show last 2 messages when active, all (max 3) when idle
                    let visibleMessages = session.status != .idle
                        ? Array(session.recentMessages.suffix(2))
                        : session.recentMessages
                    ForEach(visibleMessages) { msg in
                        switch msg.kind {
                        case .user:
                            HStack(alignment: .top, spacing: 4) {
                                Text(">")
                                    .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color(red: 0.3, green: 0.85, blue: 0.4))
                                Text(renderUserText(msg.text))
                                    .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        case .taskNotification(let info):
                            TaskNotificationRow(info: info, text: msg.text, fontSize: fontSize)
                        case .assistant:
                            HStack(alignment: .top, spacing: 4) {
                                Text("$")
                                    .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color(red: 0.85, green: 0.47, blue: 0.34))
                                Text(renderMarkdown(compactText(stripDirectives(msg.text))))
                                    .font(.system(size: fontSize, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .lineLimit(aiLineLimit)
                                    .truncationMode(.tail)
                            }
                        }
                    }

                    // Working indicator: show what AI is doing right now
                    if session.status != .idle {
                        WorkingIndicator(session: session, fontSize: fontSize, aiLineLimit: aiLineLimit)
                    }
                }
                .padding(.leading, 4)
            }
        } // end VStack
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(hovering ? Color(white: 1, opacity: 0.10) : Color(white: 1, opacity: 0.05))
        )
        .padding(.horizontal, 6)
        } // end Button label
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(NotchAnimation.micro) { hovering = h } }
    }

    /// Collapse consecutive blank lines and trim leading/trailing whitespace
    private func compactText(_ text: String) -> String {
        text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .reduce(into: [String]()) { result, line in
                // Skip consecutive empty lines
                if line.isEmpty && (result.last?.isEmpty ?? true) { return }
                result.append(line)
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func renderMarkdown(_ text: String) -> AttributedString {
        ChatMessageTextFormatter.inlineMarkdown(text)
    }

    private func renderUserText(_ text: String) -> AttributedString {
        ChatMessageTextFormatter.literalText(text)
    }

    private func tokenColor(_ usage: TokenUsage) -> Color {
        let total = usage.totalTokens
        if total > 800_000 { return Color(red: 1.0, green: 0.3, blue: 0.3) }
        if total > 500_000 { return Color(red: 1.0, green: 0.6, blue: 0.2) }
        if total > 200_000 { return Color(red: 1.0, green: 0.85, blue: 0.3) }
        return .white.opacity(0.7)
    }

    private func tokenTooltip(_ usage: TokenUsage) -> String {
        var lines = [
            "↑ \(usage.formattedInput) input",
            "↓ \(usage.formattedOutput) output",
        ]
        if usage.cacheReadTokens > 0 {
            lines.append("⟳ \(usage.formattedCache) cache")
        }
        if let cost = usage.formattedCost {
            lines.append(cost)
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Working Indicator

/// Shows what the AI is doing right now: tool activity, subagent details, or last message preview.
private struct WorkingIndicator: View {
    let session: SessionSnapshot
    let fontSize: CGFloat
    let aiLineLimit: Int?
    @State private var toolDecay = DecayState(minDuration: .seconds(2))

    private let toolColor = Color(red: 0.3, green: 0.85, blue: 0.4)
    private let agentColor = Color(red: 0.5, green: 0.8, blue: 1.0)
    private let dimColor = Color.white.opacity(0.5)
    private let prefixColor = Color(red: 0.85, green: 0.47, blue: 0.34)

    /// Live tool text from session — nil when no tool running
    private var liveToolText: String? {
        guard let tool = session.currentTool else { return nil }
        return session.toolDescription ?? tool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Active subagents detail
            let activeSubagents = session.subagents.values
                .filter { $0.status != .idle }
                .sorted { $0.startTime < $1.startTime }
            if !activeSubagents.isEmpty {
                ForEach(activeSubagents, id: \.agentId) { sub in
                    SubagentRow(sub: sub, fontSize: fontSize, agentColor: agentColor, dimColor: dimColor)
                }
            }

            // Main thread: current tool or decayed last tool
            if let displayed = toolDecay.displayedText {
                HStack(spacing: 4) {
                    Text("$")
                        .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                        .foregroundStyle(prefixColor)
                    Text(displayed)
                        .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                        .foregroundStyle(toolColor.opacity(session.currentTool != nil ? 0.8 : 0.5))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            // No "thinking" — mascot icon already indicates active status
        }
        .onChange(of: liveToolText) { _, newValue in
            toolDecay.update(newValue)
        }
    }

}

// MARK: - Subagent Row

private struct SubagentRow: View {
    let sub: SubagentState
    let fontSize: CGFloat
    let agentColor: Color
    let dimColor: Color
    @State private var toolDecay = DecayState(minDuration: .seconds(2))

    private var liveToolText: String? {
        guard let tool = sub.currentTool else { return nil }
        return sub.toolDescription ?? tool
    }

    var body: some View {
        HStack(spacing: 4) {
            Text("├")
                .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                .foregroundStyle(agentColor.opacity(0.4))
            Text(sub.agentType)
                .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                .foregroundStyle(agentColor.opacity(0.8))
            if let displayed = toolDecay.displayedText {
                Text("→")
                    .font(.system(size: fontSize - 1, design: .monospaced))
                    .foregroundStyle(dimColor)
                Text(displayed)
                    .font(.system(size: fontSize, design: .monospaced))
                    .foregroundStyle(.white.opacity(sub.currentTool != nil ? 0.65 : 0.4))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .onChange(of: liveToolText) { _, newValue in
            toolDecay.update(newValue)
        }
    }
}

// MARK: - Task Notification Row

private struct TaskNotificationRow: View {
    let info: TaskNotificationInfo
    let text: String
    let fontSize: CGFloat

    private var statusIcon: String {
        switch info.status {
        case "completed": return "shield.checkered"
        case "failed": return "shield.slash"
        case "killed": return "shield.slash"
        default: return "shield"
        }
    }

    private var statusColor: Color {
        switch info.status {
        case "completed": return Color(red: 0.3, green: 0.85, blue: 0.4)
        case "failed": return Color(red: 1.0, green: 0.4, blue: 0.35)
        case "killed": return Color(red: 1.0, green: 0.6, blue: 0.2)
        default: return .white.opacity(0.5)
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon)
                .font(.system(size: fontSize - 1))
                .foregroundStyle(statusColor)
            Text(text)
                .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                .foregroundStyle(statusColor.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}
