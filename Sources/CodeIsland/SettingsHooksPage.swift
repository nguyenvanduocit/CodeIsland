import SwiftUI
import AppKit

// MARK: - Hooks Page

struct HooksPage: View {
    @Environment(\.l10n) private var l10n
    @State private var cliStatuses: [String: Bool] = [:]
    @State private var statusMessage = ""
    @State private var statusIsError = false
    @State private var refreshKey = 0

    private func refreshCLIStatuses() {
        for cli in ConfigInstaller.allCLIs {
            cliStatuses[cli.source] = ConfigInstaller.isInstalled(source: cli.source)
        }
    }

    private func statusText(installed: Bool, exists: Bool) -> String {
        installed ? l10n["activated"] : (exists ? l10n["not_installed"] : l10n["not_detected"])
    }

    var body: some View {
        Form {
            Section(l10n["cli_status"]) {
                let cli = ConfigInstaller.allCLIs[0]
                let installed = cliStatuses[cli.source] ?? false
                let exists = ConfigInstaller.cliExists(source: cli.source)
                CLIStatusRow(
                    name: cli.name,
                    source: cli.source,
                    configPath: "~/\(cli.configPath)",
                    fullPath: cli.fullPath,
                    installed: installed,
                    exists: exists
                ) { _ in refreshCLIStatuses() }
                .id("\(cli.source)-\(refreshKey)")
            }

            Section(l10n["management"]) {
                HStack(spacing: 8) {
                    Button {
                        // Enable all detected CLIs before reinstalling
                        for cli in ConfigInstaller.allCLIs where ConfigInstaller.cliExists(source: cli.source) {
                            UserDefaults.standard.set(true, forKey: "cli_enabled_\(cli.source)")
                        }
                        if ConfigInstaller.install() {
                            refreshCLIStatuses()
                            refreshKey += 1
                            statusMessage = l10n["hooks_installed"]
                            statusIsError = false
                        } else {
                            statusMessage = l10n["install_failed"]
                            statusIsError = true
                        }
                    } label: {
                        Text(l10n["reinstall"])
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        // Disable all CLIs before uninstalling
                        for cli in ConfigInstaller.allCLIs {
                            UserDefaults.standard.set(false, forKey: "cli_enabled_\(cli.source)")
                        }
                        ConfigInstaller.uninstall()
                        refreshCLIStatuses()
                        refreshKey += 1
                        statusMessage = l10n["hooks_uninstalled"]
                        statusIsError = false
                    } label: {
                        Text(l10n["uninstall"])
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }

                if !statusMessage.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: statusIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(statusIsError ? .red : .green)
                        Text(statusMessage)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshCLIStatuses() }
    }
}

private struct CLIStatusRow: View {
    @Environment(\.l10n) private var l10n
    let name: String
    let source: String
    let configPath: String
    let fullPath: String
    let installed: Bool
    let exists: Bool
    var onToggle: ((Bool) -> Void)?

    @State private var enabled: Bool

    init(name: String, source: String, configPath: String, fullPath: String,
         installed: Bool, exists: Bool, onToggle: ((Bool) -> Void)? = nil) {
        self.name = name
        self.source = source
        self.configPath = configPath
        self.fullPath = fullPath
        self.installed = installed
        self.exists = exists
        self.onToggle = onToggle
        _enabled = State(initialValue: ConfigInstaller.isEnabled(source: source))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if let icon = cliIcon(source: source, size: 20) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                    if !exists {
                        Text(l10n["not_detected"])
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    } else if installed {
                        HStack(spacing: 2) {
                            Text(configPath)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.tertiary)
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: fullPath)])
                            } label: {
                                Image(systemName: "arrow.right.circle")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Spacer()
                if exists {
                    Toggle("", isOn: $enabled)
                        .labelsHidden()
                        .onChange(of: enabled) { _, newValue in
                            ConfigInstaller.setEnabled(source: source, enabled: newValue)
                            onToggle?(newValue)
                        }
                }
            }
        }
    }
}
