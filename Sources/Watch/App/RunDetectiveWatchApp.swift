import SwiftUI
import HealthKit

@main struct RunDetectiveWatchApp: App {
    var body: some Scene { WindowGroup { WatchHome() } }
}

struct WatchHome: View {
    @State private var workouts: [HKWorkout] = []
    @State private var runnerJump = false
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let store = HKHealthStore.isHealthDataAvailable() ? HKHealthStore() : nil
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("RUN DETECTIVE").font(.caption2.weight(.bold)).tracking(1.5).foregroundStyle(.secondary)
                    HStack {
                        Text("Recent activity").font(.title3.weight(.semibold))
                        Spacer()
                        WatchEvidenceOrb()
                    }
                    ForEach(workouts, id: \.uuid) { workout in
                        WatchWorkoutCard(workout: workout)
                    }
                    if workouts.isEmpty {
                        Button {
                            withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.5)) { runnerJump.toggle() }
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Image(systemName: "figure.run")
                                    .font(.largeTitle)
                                    .foregroundStyle(.mint)
                                    .offset(x: runnerJump ? 16 : 0, y: runnerJump ? -5 : 0)
                                Text(runnerJump ? "Still chasing clues." : "Tap the runner")
                                    .font(.headline)
                                Text("Your recent Health workouts will appear here.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(WatchCardButtonStyle())
                        .modifier(WatchCardMotion(trigger: runnerJump ? 1 : 0))
                        .sensoryFeedback(.selection, trigger: runnerJump)
                    }
                }
                .padding()
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared || reduceMotion ? 0 : 12)
                .animation(reduceMotion ? nil : .smooth(duration: 0.55), value: appeared)
                .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: workouts.count)
            }.navigationTitle("Activity")
        }
        .onAppear { appeared = true }
        .task { await load() }
    }
    private func load() async {
        guard let store else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: [HKObjectType.workoutType()])
            let values: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(sampleType: .workoutType(), predicate: nil, limit: 20, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: (samples as? [HKWorkout]) ?? []) }
                }; store.execute(query)
            }
            workouts = values.filter { [.running, .walking, .hiking].contains($0.workoutActivityType) }
        } catch { }
    }
}

private struct WatchEvidenceOrb: View {
    @State private var orbiting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().fill(.mint.opacity(0.12)).frame(width: 42, height: 42)
            Circle().stroke(.mint.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [2, 5]))
                .frame(width: 42, height: 42)
                .rotationEffect(.degrees(orbiting && !reduceMotion ? 360 : 0))
            Image(systemName: "figure.run")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.mint)
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion, !orbiting else { return }
            withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) { orbiting = true }
        }
    }
}


private struct WatchWorkoutCard: View {
    let workout: HKWorkout
    @State private var clueCount = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var title: String {
        workout.workoutActivityType == .running ? "Run" : workout.workoutActivityType == .walking ? "Walk" : "Hike"
    }
    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.7)) { clueCount += 1 }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Image(systemName: workout.workoutActivityType == .running ? "figure.run" : "figure.walk")
                        .font(.title3)
                        .foregroundStyle(.mint)
                        .frame(width: 29, height: 29)
                        .background(.mint.opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
                        .symbolEffect(.bounce, value: clueCount)
                    Text(title).font(.headline)
                    Spacer()
                    Image(systemName: "sparkle").font(.caption2).foregroundStyle(.mint)
                }
                Text(workout.startDate.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(.secondary)
                if let distance = workout.totalDistance {
                    Text(String(format: "%.2f km", distance.doubleValue(for: .meter()) / 1000)).font(.title3.monospacedDigit())
                }
                if clueCount == 0 { Text("Tap for a case note").font(.caption2).foregroundStyle(.mint) }
                if clueCount > 0 {
                    Text(clueCount.isMultiple(of: 2) ? "Case note: the wrist witnessed this." : "Tiny detective, big case file.")
                        .font(.caption2).foregroundStyle(.secondary).transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(WatchCardButtonStyle())
        .modifier(WatchCardMotion(trigger: clueCount))
        .sensoryFeedback(.selection, trigger: clueCount)
        .accessibilityHint("Double tap to reveal a short case note")
    }
}

private struct WatchCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.9 : 1)
            .rotationEffect(.degrees(configuration.isPressed && !reduceMotion ? -2 : 0))
            .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.45), value: configuration.isPressed)
    }
}

private struct WatchCardMotion: ViewModifier {
    let trigger: Int
    @State private var flash = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) {
                Image(systemName: "sparkle")
                    .foregroundStyle(.mint)
                    .font(.title3)
                    .offset(x: flash ? -7 : 0, y: flash ? -8 : 0)
                    .scaleEffect(flash ? 1.2 : 0.1)
                    .opacity(flash ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "plus")
                    .foregroundStyle(.mint)
                    .font(.title3)
                    .offset(x: flash ? 7 : 0, y: flash ? 8 : 0)
                    .scaleEffect(flash ? 1.2 : 0.1)
                    .opacity(flash ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .onChange(of: trigger) {
                guard !reduceMotion else { return }
                flash = false
                withAnimation(.spring(response: 0.35, dampingFraction: 0.48)) { flash = true }
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    withAnimation(.easeOut(duration: 0.3)) { flash = false }
                }
            }
    }
}
