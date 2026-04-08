import AppKit
import SwiftUI
import os.log

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private static let log = Logger(subsystem: "com.codeisland", category: "AppDelegate")

    var panelController: PanelWindowController?
    private var hookServer: HookServer?
    private var hookRecoveryTask: Task<Void, Never>?
    private var lastHookCheck: Date = .distantPast
    private let diagnostics = DiagnosticsService()

    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let startupState = Signposts.beginStartupPhase("AppStartup")

        ProcessInfo.processInfo.disableAutomaticTermination("CodeIsland must stay running")
        ProcessInfo.processInfo.disableSuddenTermination()
        // Pre-set app icon so Dock/menu bar use the packaged bundle icon.
        NSApp.applicationIconImage = SettingsWindowController.bundleAppIcon()

        // Start HookServer BEFORE installing hooks into CLI configs.
        // If we write settings.json first, Claude Code picks up the new hooks
        // immediately but the socket isn't listening yet — PermissionRequest
        // hooks get no response and Claude Code denies them.
        let hookState = Signposts.beginStartupPhase("HookServerStart")
        hookServer = HookServer(appState: appState)
        hookServer?.start()
        Signposts.endStartupPhase("HookServerStart", hookState)

        if ConfigInstaller.install() {
            Self.log.info("Hooks installed")
        } else {
            Self.log.warning("Failed to install hooks")
        }

        let panelState = Signposts.beginStartupPhase("PanelSetup")
        panelController = PanelWindowController(appState: appState)
        panelController?.showPanel()
        Signposts.endStartupPhase("PanelSetup", panelState)

        let discoveryState = Signposts.beginStartupPhase("SessionDiscovery")
        appState.startSessionDiscovery()
        Signposts.endStartupPhase("SessionDiscovery", discoveryState)

        diagnostics.start()
        Signposts.endStartupPhase("AppStartup", startupState)

        // Hooks auto-recovery: periodic + app activation trigger
        hookRecoveryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                self?.checkAndRepairHooks()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.checkAndRepairHooks()
            }
        }

        #if DEBUG
        // Preview mode: inject mock data if --preview flag is present
        if let scenario = DebugHarness.requestedScenario() {
            Self.log.debug("Loading scenario: \(scenario.rawValue)")
            DebugHarness.apply(scenario, to: appState)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                if appState.surface == .collapsed {
                    withAnimation(NotchAnimation.pop) {
                        appState.surface = .sessionList
                    }
                }
            }
            return
        }
        #endif

        // Check for updates silently after a short delay
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            UpdateChecker.shared.checkForUpdates(silent: true)
        }

        SoundManager.shared.playBoot()

        // Boot animation: brief expand to confirm app is running
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard appState.surface == .collapsed else { return }
            withAnimation(NotchAnimation.pop) {
                appState.surface = .sessionList
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if case .sessionList = appState.surface {
                withAnimation(NotchAnimation.close) {
                    appState.surface = .collapsed
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hookRecoveryTask?.cancel()
        diagnostics.stop()
        appState.saveSessions()
        hookServer?.stop()
        appState.stopSessionDiscovery()
    }

    private func checkAndRepairHooks() {
        guard Date().timeIntervalSince(lastHookCheck) > 60 else { return }
        lastHookCheck = Date()
        let repaired = ConfigInstaller.verifyAndRepair()
        if !repaired.isEmpty {
            Self.log.info("Auto-repaired hooks for: \(repaired.joined(separator: ", "))")
        }
    }
}
