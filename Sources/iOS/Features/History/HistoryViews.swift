import SwiftUI
import MapKit

struct HistoryView: View {
    @EnvironmentObject var health: HealthStore
    var body: some View {
        List {
            CasePageHeader(eyebrow: "The archive", title: "Every clue counts", subtitle: "Open a day to inspect each original workout.", symbol: "calendar", tint: .teal)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            if health.workouts.isEmpty {
                ContentUnavailableView {
                    Label("No cases yet", systemImage: "figure.run.circle")
                } description: {
                    Text("Your Apple Health runs and walks will appear here after the first sync.")
                }
                CardClue(lines: ["No footprints in the file. Yet.", "The archive is empty; the detective remains employed."])
            }
            ForEach(RunMath.days(health.workouts)) { day in
            NavigationLink { DayView(day: day) } label: {
                HStack(spacing: 13) {
                    DetectiveBadge(symbol: day.workouts.first?.kind.symbol ?? "calendar", tint: .teal)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(day.date.formatted(date: .abbreviated, time: .omitted)).font(.headline)
                        Text("\(Format.distance(day.distance)) · \(day.workouts.count) session\(day.workouts.count == 1 ? "" : "s")")
                        Text("Workout pace \(Format.pace(day.pace)) · HR \(Format.number(day.averageHR, unit: "bpm"))").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 5).caseMotion(tint: .teal)
            }.buttonStyle(AnimatedCardButtonStyle())
            }
        }.scrollContentBackground(.hidden).background(AmbientBackdrop()).navigationTitle("History").refreshable { await health.refresh() }
    }
}

struct DayView: View {
    let day: ActivitySummary
    var body: some View {
        List {
            CasePageHeader(eyebrow: "Daily file", title: day.date.formatted(date: .abbreviated, time: .omitted), subtitle: "\(day.workouts.count) original session\(day.workouts.count == 1 ? "" : "s") · \(Format.distance(day.distance)) total", symbol: "square.stack.3d.up", tint: .mint)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            Section("Daily totals") {
                Label("Combined from \(day.workouts.count) original workout\(day.workouts.count == 1 ? "" : "s")", systemImage: "sum").font(.footnote).foregroundStyle(.secondary)
                detail("Distance", Format.distance(day.distance)); detail("Duration", Format.duration(day.duration)); detail("Workout pace", Format.pace(day.pace)); detail("Average HR", Format.number(day.averageHR, unit: "bpm")); detail("Maximum HR", Format.number(day.maximumHR, unit: "bpm")); detail("Active energy", Format.number(day.energy, unit: "kcal")); detail("Elevation gain", Format.number(day.elevationGain, unit: "m"))
            }
            Section("Workouts") { ForEach(day.workouts) { workout in NavigationLink { WorkoutView(workout: workout) } label: { Label { VStack(alignment: .leading) { Text(workout.kind.title); Text("\(Format.distance(workout.distance)) · \(workout.start.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: workout.kind.symbol) }.caseMotion(tint: .teal, scroll: false) } } }
            Section("Case note") { CardClue(lines: ["Several sessions, one day. None of the originals went missing.", "Daily pace uses total time and distance. The calculator did its homework."]) }
        }.scrollContentBackground(.hidden).background(AmbientBackdrop()).navigationTitle(day.date.formatted(date: .abbreviated, time: .omitted))
    }
}

struct WorkoutView: View {
    @EnvironmentObject var health: HealthStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let workout: RunWorkout
    @State private var route: [CLLocation] = []
    var body: some View {
        List {
            CasePageHeader(eyebrow: "Original workout", title: workout.kind.title, subtitle: workout.start.formatted(date: .complete, time: .shortened), symbol: workout.kind.symbol, tint: .mint)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            if route.count > 1 { Section { Map { MapPolyline(coordinates: route.map(\.coordinate)).stroke(.mint, lineWidth: 5); Marker("Start", coordinate: route.first!.coordinate); Marker("Finish", coordinate: route.last!.coordinate) }.frame(height: 260).caseMotion(tint: .mint, scroll: false).listRowInsets(EdgeInsets()) } }
            Section("Workout") {
                Label("Original Apple Health workout", systemImage: workout.kind.symbol).font(.footnote).foregroundStyle(.secondary)
                detail("Distance · Health", Format.distance(workout.distance)); detail("Duration · Health", Format.duration(workout.duration)); detail("Pace · Calculated", Format.pace(workout.pace)); detail("Speed · Calculated", Format.number(workout.speed.map { $0 * 3.6 }, unit: "km/h", digits: 1)); detail("Active energy · Health", Format.number(workout.energy, unit: "kcal")); detail("Average HR · Calculated", Format.number(workout.averageHR, unit: "bpm")); detail("Maximum HR · Calculated", Format.number(workout.maximumHR, unit: "bpm")); detail("Cadence", Format.number(workout.cadence, unit: "spm")); detail("Running power", Format.number(workout.power, unit: "W")); detail("Elevation gain · Health", Format.number(workout.elevationGain, unit: "m"))
            }
            Section("Timing") { detail("Start", workout.start.formatted(date: .omitted, time: .shortened)); detail("Finish", workout.end.formatted(date: .omitted, time: .shortened)) }
            if let comparable = RunMath.comparable(to: workout, among: health.workouts), let pace = workout.pace, let old = comparable.pace {
                Section("Most comparable") { detail("Date", comparable.start.formatted(date: .abbreviated, time: .omitted)); detail("Distance", Format.distance(comparable.distance)); detail("Pace change", "\(Int(abs(old - pace).rounded())) sec/km \(pace < old ? "faster" : "slower")"); if let hr = workout.averageHR, let previous = comparable.averageHR { detail("HR change", "\(Int(abs(hr - previous).rounded())) bpm \(hr < previous ? "lower" : "higher")") }; Text("Matched by activity, distance and duration. Route and conditions may differ.").font(.footnote).foregroundStyle(.secondary) }
            }
            Section("Detective note") { CardClue(lines: ["Measured values came from Health. Pace did the division.", "An unavailable metric is an honest clue, not a zero."]) }
        }.scrollContentBackground(.hidden).background(AmbientBackdrop()).navigationTitle(workout.kind.title).task {
            let loaded = await health.loadRoute(for: workout)
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.55)) { route = loaded }
        }
    }
}
