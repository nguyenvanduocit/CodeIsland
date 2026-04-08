import SwiftUI
import CodeIslandCore

struct NotchPanelView: View {
    var appState: AppState
    let hasNotch: Bool
    let notchHeight: CGFloat
    let notchW: CGFloat
    let screenWidth: CGFloat

    @AppStorage(SettingsKey.contentFontSize) private var contentFontSize = SettingsDefaults.contentFontSize
    @AppStorage(SettingsKey.smartSuppress) private var smartSuppress = SettingsDefaults.smartSuppress
    @AppStorage(SettingsKey.hideWhenNoSession) private var hideWhenNoSession = SettingsDefaults.hideWhenNoSession

    /// Delayed hover: prevents accidental expansion when mouse passes through
    @State private var hoverTask: Task<Void, Never>?
    @State private var idleHovered = false

    private var isActive: Bool { !appState.sessions.isEmpty }
    /// First launch / no-session state should still render a visible marker so the app
    /// doesn't disappear completely behind the physical notch.
    private var showIdleIndicator: Bool {
        !isActive && !hideWhenNoSession
    }
    /// Whether the bar content should be visible (respects hideWhenNoSession)
    private var showBar: Bool {
        isActive && !(hideWhenNoSession && appState.sessions.isEmpty)
    }
    private var shouldShowExpanded: Bool {
        showBar && appState.surface.isExpanded
    }

    /// Mascot size — fits within the menu bar height
    private var mascotSize: CGFloat { min(27, notchHeight - 6) }

    /// Minimum wing width needed to display compact bar content
    private var compactWingWidth: CGFloat { mascotSize + 14 }

    /// Total panel width — adapts based on state and screen geometry
    private var panelWidth: CGFloat {
        let maxWidth = min(620, screenWidth - 40)
        if showIdleIndicator { return idleHovered ? notchW + compactWingWidth * 2 + 80 : notchW + compactWingWidth * 2 }
        if !isActive { return hasNotch ? notchW - 20 : notchW }
        if shouldShowExpanded { return min(max(notchW + 200, 580), maxWidth) }
        let wing = compactWingWidth
        let extra: CGFloat = appState.status == .idle ? 0 : 20
        return notchW + wing * 2 + extra
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                if showBar {
                    // Active: compact bar — wider version when expanded
                    HStack(spacing: 0) {
                        CompactLeftWing(appState: appState, expanded: shouldShowExpanded, mascotSize: mascotSize)
                        if shouldShowExpanded {
                            Spacer(minLength: 0)
                        } else if let sid = appState.lastInputSessionId,
                                  let session = appState.sessions[sid],
                                  let msg = session.toolDescription
                                            ?? session.currentTool
                                            ?? session.lastAssistantMessage
                                            ?? session.lastUserPrompt {
                            Text(msg.replacingOccurrences(of: "\n", with: " "))
                                .font(.system(size: 12, weight: .regular, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, hasNotch ? notchW / 2 : 4)
                        } else {
                            Spacer(minLength: hasNotch ? notchW : 0)
                        }
                        CompactRightWing(appState: appState, expanded: shouldShowExpanded)
                    }
                    .frame(height: notchHeight)
                } else if showIdleIndicator {
                    IdleIndicatorBar(
                        mascotSize: mascotSize,
                        compactWingWidth: compactWingWidth,
                        notchW: notchW,
                        notchHeight: notchHeight,
                        hasNotch: hasNotch,
                        hovered: idleHovered
                    )
                } else {
                    // Idle: just the notch shell
                    Spacer()
                        .frame(height: notchHeight)
                }

                // Below-notch expanded content
                if shouldShowExpanded {
                    Line()
                        .stroke(.white.opacity(0.15), style: StrokeStyle(lineWidth: 0.5, dash: [4, 3]))
                        .frame(height: 0.5)
                        .padding(.horizontal, 12)

                    switch appState.surface {
                    case .approvalCard:
                        if let pending = appState.pendingPermission {
                            ApprovalBar(
                                tool: pending.event.toolName ?? "Unknown",
                                toolInput: pending.event.toolInput,
                                queuePosition: 1,
                                queueTotal: appState.requestQueue.permissionQueue.count,
                                onAllow: { appState.approvePermission(always: false) },
                                onAlwaysAllow: { appState.approvePermission(always: true) },
                                onDeny: { appState.denyPermission() }
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                        }
                    case .questionCard(let sid):
                        let session = appState.sessions[sid]
                        if let q = appState.pendingQuestion {
                            QuestionBar(
                                question: q.question.question,
                                options: q.question.options,
                                descriptions: q.question.descriptions,
                                sessionSource: session?.source,
                                sessionContext: session?.cwd,
                                queuePosition: 1,
                                queueTotal: appState.requestQueue.questionQueue.count,
                                onAnswer: { appState.answerQuestion($0) },
                                onSkip: { appState.skipQuestion() }
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                        } else if let preview = appState.previewQuestionPayload {
                            QuestionBar(
                                question: preview.question,
                                options: preview.options,
                                descriptions: preview.descriptions,
                                sessionSource: session?.source,
                                sessionContext: session?.cwd,
                                queuePosition: 1,
                                queueTotal: 1,
                                onAnswer: { _ in },
                                onSkip: { }
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                        }
                    case .completionCard:
                        SessionListView(appState: appState, onlySessionId: appState.justCompletedSessionId)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    case .sessionList:
                        SessionListView(appState: appState, onlySessionId: nil)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    case .collapsed:
                        EmptyView()
                    }
                }
            }
            .frame(width: panelWidth)
            .clipped()
            .background(
                NotchPanelShape(
                    topExtension: shouldShowExpanded ? 14 : 3,
                    bottomRadius: shouldShowExpanded ? 14 : 12,
                    minHeight: notchHeight
                )
                .fill(.black)
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                // Idle indicator hover
                if showIdleIndicator {
                    withAnimation(NotchAnimation.micro) { idleHovered = hovering }
                    return
                }
                switch appState.surface {
                case .approvalCard, .questionCard: return
                case .completionCard:
                    // Completion card: mark entered on hover-in, block collapse until entered
                    if hovering {
                        appState.completionHasBeenEntered = true
                    } else if appState.completionHasBeenEntered {
                        // Mouse entered then left — collapse after minimum display time
                        hoverTask?.cancel()
                        let remaining = appState.completionQueue.remainingMinimumDisplayTime
                        if remaining > 0 {
                            hoverTask = Task { @MainActor in
                                try? await Task.sleep(for: .seconds(remaining))
                                guard !Task.isCancelled, case .completionCard = appState.surface else { return }
                                withAnimation(NotchAnimation.close) {
                                    appState.surface = .collapsed
                                    appState.cancelCompletionQueue()
                                }
                            }
                        } else {
                            hoverTask = nil
                            withAnimation(NotchAnimation.close) {
                                appState.surface = .collapsed
                                appState.cancelCompletionQueue()
                            }
                        }
                    }
                    return
                default: break
                }
                // Respect collapseOnMouseLeave setting
                if !hovering && !SettingsManager.shared.collapseOnMouseLeave { return }
                // Smart suppress: don't auto-expand when active session's terminal is foreground
                if hovering && smartSuppress {
                    if let delegate = NSApp.delegate as? AppDelegate,
                       let pc = delegate.panelController,
                       pc.isActiveTerminalForeground() {
                        return
                    }
                }

                if hovering {
                    // Delay expansion to avoid accidental triggers
                    hoverTask?.cancel()
                    hoverTask = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(0.2))
                        guard !Task.isCancelled else { return }
                        withAnimation(NotchAnimation.open) {
                            appState.surface = .sessionList
                            appState.cancelCompletionQueue()
                            if appState.activeSessionId == nil {
                                appState.activeSessionId = appState.sessions.keys.sorted().first
                            }
                        }
                    }
                } else {
                    // Collapse with brief delay to prevent flicker on accidental mouse-out
                    hoverTask?.cancel()
                    hoverTask = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(0.15))
                        guard !Task.isCancelled else { return }
                        withAnimation(NotchAnimation.close) {
                            appState.surface = .collapsed
                        }
                        // Show queued completions that arrived while user was hovering
                        appState.completionQueue.flushIfNeeded()
                    }
                }
            }

            Spacer()
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(NotchAnimation.open, value: appState.surface)
    }
}


// MARK: - Compact Wings (notch-level, 32px height)

/// Left side: pixel character + status info
private struct CompactLeftWing: View {
    var appState: AppState
    let expanded: Bool
    let mascotSize: CGFloat

    private var displaySession: SessionSnapshot? {
        let sid = appState.rotatingSessionId ?? appState.activeSessionId ?? appState.sessions.keys.sorted().first
        guard let sid else { return nil }
        return appState.sessions[sid]
    }
    private var displaySource: String { displaySession?.source ?? appState.primarySource }
    private var displayStatus: AgentStatus { displaySession?.status ?? .idle }

    var body: some View {
        HStack(spacing: 6) {
            if expanded {
                AppLogoView(size: 36, showBackground: false)
            } else {
                MascotView(source: displaySource, status: displayStatus, size: mascotSize)
                    .id(displaySource)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: displaySource)
            }
        }
        .padding(.leading, 6)
        .clipped()
    }
}

/// Right side: model + session count
private struct CompactRightWing: View {
    var appState: AppState
    let expanded: Bool
    @Environment(\.l10n) private var l10n
    @AppStorage(SettingsKey.soundEnabled) private var soundEnabled = SettingsDefaults.soundEnabled

    var body: some View {
        HStack(spacing: 6) {
            if expanded {
                NotchIconButton(icon: soundEnabled ? "speaker.wave.2" : "speaker.slash", tooltip: soundEnabled ? l10n["mute"] : l10n["enable_sound_tooltip"]) {
                    soundEnabled.toggle()
                }
                NotchIconButton(icon: "gearshape", tooltip: l10n["settings"]) {
                    SettingsWindowController.shared.show()
                }
                NotchIconButton(icon: "power", tint: Color(red: 1.0, green: 0.4, blue: 0.4), tooltip: l10n["quit"]) {
                    NSApplication.shared.terminate(nil)
                }
            } else {
                // Pending approval/question badge
                if appState.status == .waitingApproval || appState.status == .waitingQuestion {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(red: 1.0, green: 0.7, blue: 0.28))
                        .symbolEffect(.pulse, options: .repeating)
                }

                HStack(spacing: 1) {
                    let active = appState.activeSessionCount
                    let total = appState.totalSessionCount
                    if active > 0 {
                        Text("\(active)")
                            .foregroundStyle(Color(red: 0.4, green: 1.0, blue: 0.5))
                        Text("/")
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    Text("\(total)")
                        .foregroundStyle(.white.opacity(0.9))
                }
                .font(.system(size: 13, weight: .bold, design: .monospaced))
            }
        }
        .padding(.trailing, 6)
    }
}

private struct NotchIconButton: View {
    let icon: String
    var tint: Color = .white
    var tooltip: String? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint.opacity(hovering ? 1.0 : 0.85))
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(tint.opacity(hovering ? 0.2 : 0.08))
                )
                .scaleEffect(hovering ? 1.1 : 1.0)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(NotchAnimation.micro) { hovering = h } }
        .help(tooltip ?? "")
    }
}

// MARK: - Idle Indicator Bar

private struct IdleIndicatorBar: View {
    let mascotSize: CGFloat
    let compactWingWidth: CGFloat
    let notchW: CGFloat
    let notchHeight: CGFloat
    let hasNotch: Bool
    let hovered: Bool
    @Environment(\.l10n) private var l10n
    @AppStorage(SettingsKey.soundEnabled) private var soundEnabled = SettingsDefaults.soundEnabled

    var body: some View {
        HStack(spacing: 0) {
            // Left: mascot
            HStack(spacing: 6) {
                MascotView(source: "claude", status: .idle, size: mascotSize)
                    .opacity(hovered ? 0.9 : 0.5)
            }
            .padding(.leading, 6)

            Spacer(minLength: hasNotch ? notchW : 0)

            // Right: expanded shows text + buttons, collapsed shows nothing
            if hovered {
                HStack(spacing: 8) {
                    Text("0")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))

                    HStack(spacing: 4) {
                        NotchIconButton(icon: soundEnabled ? "speaker.wave.2" : "speaker.slash", tooltip: soundEnabled ? l10n["mute"] : l10n["enable_sound_tooltip"]) {
                            soundEnabled.toggle()
                        }
                        NotchIconButton(icon: "gearshape", tooltip: l10n["settings"]) {
                            SettingsWindowController.shared.show()
                        }
                        NotchIconButton(icon: "power", tint: Color(red: 1.0, green: 0.4, blue: 0.4), tooltip: l10n["quit"]) {
                            NSApplication.shared.terminate(nil)
                        }
                    }
                }
                .padding(.trailing, 6)
                .transition(.opacity)
            }
        }
        .frame(height: notchHeight)
        .animation(NotchAnimation.micro, value: hovered)
    }
}
