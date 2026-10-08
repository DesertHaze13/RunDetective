import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var health: HealthStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var running = true
    @State private var walking = true
    @State private var hiking = true
    @State private var months = 12
    @State private var syncTrigger = 0

    var body: some View {
        Form {
            CasePageHeader(eyebrow: "Your case, your rules", title: "Tune the evidence", subtitle: "Choose which Health workouts belong in your case file.", symbol: "slider.horizontal.3", tint: .indigo)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)

            Section("Import") {
                importToggle("Running", symbol: "figure.run", value: $running)
                importToggle("Walking", symbol: "figure.walk", value: $walking)
                importToggle("Hiking", symbol: "figure.hiking", value: $hiking)
                Picker("History", selection: $months) {
                    Text("3 months").tag(3)
                    Text("6 months").tag(6)
                    Text("1 year").tag(12)
                    Text("2 years").tag(24)
                    Text("All available").tag(1200)
                }
                .sensoryFeedback(.selection, trigger: months)
                Button {
                    syncTrigger += 1
                    apply()
                    Task { await health.refresh() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.clockwise")
                            .rotationEffect(.degrees(reduceMotion ? 0 : Double(syncTrigger) * 360))
                            .animation(reduceMotion ? nil : .smooth(duration: 0.65), value: syncTrigger)
                        Text("Re-sync Health")
                    }
                }
                .buttonStyle(AnimatedCardButtonStyle())
                .sensoryFeedback(.selection, trigger: syncTrigger)
                if let date = health.lastSync {
                    detail("Last sync", date.formatted(date: .abbreviated, time: .shortened))
                }
            }

            Section("Privacy") {
                Label("Health and route data stays on this device. Run Detective uses Apple Health as its source of truth and does not require an account.", systemImage: "hand.raised")
                    .caseMotion(tint: .teal, scroll: false)
            }
            if let error = health.error {
                Section("Health") {
                    Text(error)
                    Button("Request access") { Task { await health.authorize() } }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AmbientBackdrop())
        .navigationTitle("Settings")
        .onAppear {
            running = health.includeRunning
            walking = health.includeWalking
            hiking = health.includeHiking
            months = health.historyMonths
        }
        .onChange(of: running) { applyAndRefresh() }
        .onChange(of: walking) { applyAndRefresh() }
        .onChange(of: hiking) { applyAndRefresh() }
        .onChange(of: months) { applyAndRefresh() }
    }

    private func importToggle(_ title: String, symbol: String, value: Binding<Bool>) -> some View {
        Toggle(isOn: value) {
            Label(title, systemImage: symbol)
                .symbolEffect(.bounce, value: value.wrappedValue)
        }
        .sensoryFeedback(.selection, trigger: value.wrappedValue)
        .caseMotion(tint: .mint, scroll: false)
    }

    private func apply() {
        health.includeRunning = running
        health.includeWalking = walking
        health.includeHiking = hiking
        health.historyMonths = months
    }

    private func applyAndRefresh() {
        apply()
        Task { await health.refresh() }
    }
}
