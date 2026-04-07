import SwiftUI
import CodeIslandCore

// MARK: - Navigation Model

enum SettingsPage: String, Identifiable, Hashable {
    case general
    case behavior
    case appearance
    case mascots
    case sound
    case hooks
    case about

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .behavior: return "slider.horizontal.3"
        case .appearance: return "paintbrush.fill"
        case .mascots: return "person.2.fill"
        case .sound: return "speaker.wave.2.fill"
        case .hooks: return "link.circle.fill"
        case .about: return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .general: return .gray
        case .behavior: return .orange
        case .appearance: return .blue
        case .mascots: return .pink
        case .sound: return .green
        case .hooks: return .purple
        case .about: return .cyan
        }
    }
}

private struct SidebarGroup: Hashable {
    let title: String?
    let pages: [SettingsPage]
}

private let sidebarGroups: [SidebarGroup] = [
    SidebarGroup(title: nil, pages: [.general, .behavior, .appearance, .mascots, .sound]),
    SidebarGroup(title: "CodeIsland", pages: [.hooks, .about]),
]

// MARK: - Main View

struct SettingsView: View {
    @Environment(\.l10n) private var l10n
    @State private var selectedPage: SettingsPage = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedPage) {
                ForEach(sidebarGroups, id: \.title) { group in
                    Section {
                        ForEach(group.pages) { page in
                            SidebarRow(page: page)
                                .tag(page)
                        }
                    } header: {
                        if let title = group.title {
                            Text(title)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(200)
        } detail: {
            Group {
                switch selectedPage {
                case .general: GeneralPage()
                case .behavior: BehaviorPage()
                case .appearance: AppearancePage()
                case .mascots: MascotsPage()
                case .sound: SoundPage()
                case .hooks: HooksPage()
                case .about: AboutPage()
                }
            }
        }
        .toolbar(removing: .sidebarToggle)
    }
}

private struct SidebarRow: View {
    @Environment(\.l10n) private var l10n
    let page: SettingsPage

    var body: some View {
        Label {
            Text(l10n[page.rawValue])
                .font(.system(size: 13))
        } icon: {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(page.color.gradient)
                    .frame(width: 24, height: 24)
                Image(systemName: page.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
    }
}
