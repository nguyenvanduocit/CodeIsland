import SwiftUI

// MARK: - General Page

struct GeneralPage: View {
    @Environment(\.l10n) private var l10n
    @AppStorage(SettingsKey.displayChoice) private var displayChoice = SettingsDefaults.displayChoice
    @State private var launchAtLogin: Bool

    init() {
        _launchAtLogin = State(initialValue: SettingsManager.shared.launchAtLogin)
    }

    var body: some View {
        @Bindable var l10n = l10n
        Form {
            Section {
                Picker(l10n["language"], selection: $l10n.language) {
                    Text(l10n["system_language"]).tag("system")
                    Text("English").tag("en")
                    Text("中文").tag("zh")
                }
                Toggle(l10n["launch_at_login"], isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, v in
                        SettingsManager.shared.launchAtLogin = v
                    }
                Picker(l10n["display"], selection: $displayChoice) {
                    Text(l10n["auto"]).tag("auto")
                    ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
                        let name = screen.localizedName
                        let isBuiltin = name.contains("Built-in") || name.contains("内置")
                        let label = isBuiltin ? l10n["builtin_display"] : name
                        Text(label).tag("screen_\(index)")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
