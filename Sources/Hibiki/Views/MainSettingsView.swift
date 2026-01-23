import SwiftUI

enum SettingsTab: Int, CaseIterable {
    case configuration = 0
    case debug = 1
    case history = 2
    case statistics = 3

    var title: String {
        switch self {
        case .configuration: return "Configuration"
        case .debug: return "Debug"
        case .history: return "History"
        case .statistics: return "Statistics"
        }
    }

    var icon: String {
        switch self {
        case .configuration: return "gearshape"
        case .debug: return "ladybug"
        case .history: return "clock.arrow.circlepath"
        case .statistics: return "chart.line.uptrend.xyaxis"
        }
    }
}

struct MainSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: SettingsTab = .configuration

    var body: some View {
        TabView(selection: $selectedTab) {
            ConfigurationTab()
                .tabItem {
                    Label(SettingsTab.configuration.title, systemImage: SettingsTab.configuration.icon)
                }
                .tag(SettingsTab.configuration)

            DebugTab()
                .tabItem {
                    Label(SettingsTab.debug.title, systemImage: SettingsTab.debug.icon)
                }
                .tag(SettingsTab.debug)

            HistoryTab()
                .tabItem {
                    Label(SettingsTab.history.title, systemImage: SettingsTab.history.icon)
                }
                .tag(SettingsTab.history)

            StatisticsTab()
                .tabItem {
                    Label(SettingsTab.statistics.title, systemImage: SettingsTab.statistics.icon)
                }
                .tag(SettingsTab.statistics)
        }
        .frame(minWidth: 700, minHeight: 550)
    }
}
