import SwiftUI

@main
struct CodeIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.l10n) private var l10n

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
