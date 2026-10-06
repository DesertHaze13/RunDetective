import SwiftUI
import Charts
import MapKit

struct RootView: View {
    @EnvironmentObject var health: HealthStore
    var body: some View {
        TabView {
            NavigationStack { DashboardView() }.tabItem { Label("Today", systemImage: "square.grid.2x2") }
            NavigationStack { HistoryView() }.tabItem { Label("History", systemImage: "calendar") }
            NavigationStack { TrendsView() }.tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }
            NavigationStack { SettingsView() }.tabItem { Label("Settings", systemImage: "gearshape") }
        }.tint(.mint)
    }
}
