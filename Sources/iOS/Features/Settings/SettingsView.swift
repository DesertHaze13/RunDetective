import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var health: HealthStore
    @State private var running = true
    @State private var walking = true
    @State private var hiking = true
    @State private var months = 12
    var body: some View {
        Form {
            Section("Import") { Toggle(isOn: $running) { Label("Running", systemImage: "figure.run") }; Toggle(isOn: $walking) { Label("Walking", systemImage: "figure.walk") }; Toggle(isOn: $hiking) { Label("Hiking", systemImage: "figure.hiking") }; Picker("History", selection: $months) { Text("3 months").tag(3); Text("6 months").tag(6); Text("1 year").tag(12); Text("2 years").tag(24); Text("All available").tag(1200) }; Button { apply(); Task { await health.refresh() } } label: { Label("Re-sync Health", systemImage: "arrow.clockwise") }; if let date = health.lastSync { detail("Last sync", date.formatted(date: .abbreviated, time: .shortened)) } }
            Section("Privacy") { Label("Health and route data stays on this device. Run Detective uses Apple Health as its source of truth and does not require an account.", systemImage: "hand.raised") }
            if let error = health.error { Section("Health") { Text(error); Button("Request access") { Task { await health.authorize() } } } }
        }.scrollContentBackground(.hidden).background(AmbientBackdrop()).navigationTitle("Settings").onAppear { running = health.includeRunning; walking = health.includeWalking; hiking = health.includeHiking; months = health.historyMonths }.onChange(of: running) { applyAndRefresh() }.onChange(of: walking) { applyAndRefresh() }.onChange(of: hiking) { applyAndRefresh() }.onChange(of: months) { applyAndRefresh() }
    }
    private func apply() { health.includeRunning = running; health.includeWalking = walking; health.includeHiking = hiking; health.historyMonths = months }
    private func applyAndRefresh() { apply(); Task { await health.refresh() } }
}
