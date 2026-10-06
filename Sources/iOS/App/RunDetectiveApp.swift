import SwiftUI

@main struct RunDetectiveApp: App {
    @StateObject private var health = HealthStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(health)
                .task { await health.authorize() }
                .onChange(of: scenePhase) {
                    if scenePhase == .active && health.authorized { Task { await health.refresh() } }
                }
        }
    }
}
