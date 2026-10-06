import Foundation
import HealthKit
import CoreLocation

enum ActivityKind: String, CaseIterable, Identifiable, Codable {
    case running, walking, hiking
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String { self == .running ? "figure.run" : self == .walking ? "figure.walk" : "figure.hiking" }
    init?(_ type: HKWorkoutActivityType) {
        switch type { case .running: self = .running; case .walking: self = .walking; case .hiking: self = .hiking; default: return nil }
    }
}

struct RunWorkout: Identifiable {
    let id: UUID
    let healthWorkout: HKWorkout
    let kind: ActivityKind
    let start: Date
    let end: Date
    let duration: TimeInterval
    let distance: Double?
    let energy: Double?
    var averageHR: Double?
    var maximumHR: Double?
    var hrCoverage: TimeInterval = 0
    var cadence: Double?
    var power: Double?
    var elevationGain: Double?
    var route: [CLLocation] = []
    var pace: Double? { guard let distance, distance > 0, duration > 0 else { return nil }; return duration / distance * 1000 }
    var speed: Double? { guard duration > 0, let distance else { return nil }; return distance / duration }
    init(_ workout: HKWorkout) {
        id = workout.uuid; healthWorkout = workout
        kind = ActivityKind(workout.workoutActivityType) ?? .walking
        start = workout.startDate; end = workout.endDate; duration = workout.duration
        distance = workout.totalDistance?.doubleValue(for: .meter())
        energy = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
        elevationGain = (workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity)?.doubleValue(for: .meter())
    }
}

struct ActivitySummary: Identifiable {
    let date: Date
    let workouts: [RunWorkout]
    var id: Date { date }
    var distance: Double { workouts.compactMap(\.distance).reduce(0,+) }
    var duration: Double { workouts.reduce(0) { $0 + $1.duration } }
    var energy: Double? { let values = workouts.compactMap(\.energy); return values.isEmpty ? nil : values.reduce(0,+) }
    var pace: Double? { let eligible = workouts.filter { ($0.distance ?? 0) > 0 }; let d = eligible.compactMap(\.distance).reduce(0,+); return d > 0 ? eligible.reduce(0) { $0 + $1.duration } / d * 1000 : nil }
    var averageHR: Double? { let valid = workouts.filter { $0.averageHR != nil && $0.hrCoverage > 0 }; let weight = valid.reduce(0) { $0 + $1.hrCoverage }; return weight > 0 ? valid.reduce(0) { $0 + ($1.averageHR ?? 0) * $1.hrCoverage } / weight : nil }
    var heartRateCoverage: Double { workouts.reduce(0) { $0 + $1.hrCoverage } }
    var energyCount: Int { workouts.filter { $0.energy != nil }.count }
    var maximumHR: Double? { workouts.compactMap(\.maximumHR).max() }
    var elevationGain: Double? { let values = workouts.compactMap(\.elevationGain); return values.isEmpty ? nil : values.reduce(0,+) }
}

struct WeekSummary: Identifiable {
    let start: Date
    let workouts: [RunWorkout]
    var id: Date { start }
    var all: ActivitySummary { ActivitySummary(date: start, workouts: workouts) }
    func distance(_ kind: ActivityKind) -> Double { workouts.filter { $0.kind == kind }.compactMap(\.distance).reduce(0,+) }
    func pace(_ kind: ActivityKind) -> Double? { ActivitySummary(date: start, workouts: workouts.filter { $0.kind == kind }).pace }
    func heartRate(_ kind: ActivityKind) -> Double? { ActivitySummary(date: start, workouts: workouts.filter { $0.kind == kind }).averageHR }
}

enum RunMath {
    static func days(_ workouts: [RunWorkout], calendar: Calendar = .current) -> [ActivitySummary] {
        Dictionary(grouping: workouts) { calendar.startOfDay(for: $0.start) }.map { ActivitySummary(date: $0.key, workouts: $0.value.sorted { $0.start < $1.start }) }.sorted { $0.date > $1.date }
    }
    static func weeks(_ workouts: [RunWorkout], calendar: Calendar = .current) -> [WeekSummary] {
        Dictionary(grouping: workouts) { calendar.dateInterval(of: .weekOfYear, for: $0.start)!.start }.map { WeekSummary(start: $0.key, workouts: $0.value) }.sorted { $0.start > $1.start }
    }
    static func percent(_ current: Double, _ previous: Double) -> Double? { previous > 0 ? (current - previous) / previous * 100 : nil }
    static func heartRateSummary(_ readings: [(value: Double, date: Date)], workoutDuration: Double) -> (average: Double?, maximum: Double?, coverage: Double) {
        let sorted = readings.filter { $0.value.isFinite && $0.value > 0 }.sorted { $0.date < $1.date }
        guard !sorted.isEmpty else { return (nil, nil, 0) }
        var weightedSum = 0.0
        var coverage = 0.0
        for index in sorted.indices {
            let interval = index + 1 < sorted.count ? sorted[index + 1].date.timeIntervalSince(sorted[index].date) : 5
            let weight = min(max(interval, 1), 30)
            weightedSum += sorted[index].value * weight
            coverage += weight
        }
        return (weightedSum / coverage, sorted.map(\.value).max(), min(coverage, workoutDuration))
    }
    static func comparable(to target: RunWorkout, among workouts: [RunWorkout]) -> RunWorkout? {
        guard let distance = target.distance, distance > 0 else { return nil }
        return workouts.filter { candidate in
            guard candidate.start < target.start, candidate.kind == target.kind, let other = candidate.distance, other > 0 else { return false }
            let ratio = other / distance
            return ratio >= 0.8 && ratio <= 1.25 && candidate.duration / max(target.duration, 1) >= 0.7 && candidate.duration / max(target.duration, 1) <= 1.4
        }.min { score($0, target) < score($1, target) }
    }
    private static func score(_ a: RunWorkout, _ b: RunWorkout) -> Double {
        let distance = abs(log((a.distance ?? 1) / (b.distance ?? 1)))
        let duration = abs(log(a.duration / max(b.duration, 1)))
        let elevation = a.elevationGain.flatMap { x in b.elevationGain.map { abs(x - $0) / 100 } } ?? 0.15
        return distance * 3 + duration + elevation
    }
}

struct AnalysisFinding: Identifiable {
    enum Tone { case improved, caution, observation, insufficient }
    let title: String
    let detail: String
    let why: String
    let tone: Tone
    var id: String { title }
}

struct RunningWeekComparison {
    let recent: WeekSummary
    let previous: WeekSummary
    let skippedWeeks: Int
    let isCurrentWeekPartial: Bool

    var recentRuns: [RunWorkout] { recent.workouts.filter { $0.kind == .running } }
    var previousRuns: [RunWorkout] { previous.workouts.filter { $0.kind == .running } }
    var recentDistance: Double { recent.distance(.running) }
    var previousDistance: Double { previous.distance(.running) }
    var recentDays: Int { activeDays(recentRuns) }
    var previousDays: Int { activeDays(previousRuns) }
    // Each run is evaluated separately. A baseline may be reused when the earlier week
    // contains fewer similar-distance runs; that reuse is disclosed in the UI.
    var sessionMatches: [(recent: RunWorkout, previous: RunWorkout?)] {
        recentRuns.sorted { $0.start > $1.start }.map { run in
            let candidates = previousRuns.filter { candidate in
                guard let distance = run.distance, distance > 0, let old = candidate.distance, old > 0 else { return false }
                return old / distance >= 0.8 && old / distance <= 1.25
            }
            let closest = candidates.min { first, second in
                let firstGap = abs(log((first.distance ?? 1) / max(run.distance ?? 1, 1)))
                let secondGap = abs(log((second.distance ?? 1) / max(run.distance ?? 1, 1)))
                return firstGap < secondGap
            }
            return (run, closest)
        }
    }
    var runLengthsSimilar: Bool {
        guard !recentRuns.isEmpty, !previousRuns.isEmpty else { return false }
        let ratio = (recentDistance / Double(recentRuns.count)) / max(previousDistance / Double(previousRuns.count), 1)
        return ratio >= 0.75 && ratio <= 1.25
    }
    var confidence: String {
        guard !recentRuns.isEmpty, !previousRuns.isEmpty else { return "LOW" }
        return recentRuns.count >= 2 && previousRuns.count >= 2 && sessionMatches.allSatisfy { $0.previous != nil } && skippedWeeks == 0 ? "MEDIUM" : "LOW"
    }
    var caveat: String {
        var parts = ["Workout pace includes any pauses. Routes, elevation, weather, and intent were not matched."]
        if isCurrentWeekPartial { parts.append("The current and comparison weeks include only the same elapsed portion of their calendar weeks.") }
        if !runLengthsSimilar { parts.append("Typical run lengths differed by more than 25%; use individual sessions for pace.") }
        if skippedWeeks > 0 { parts.append("There \(skippedWeeks == 1 ? "was" : "were") \(skippedWeeks) inactive calendar week\(skippedWeeks == 1 ? "" : "s") between these running weeks.") }
        parts.append("Weekly totals do not establish a pace or heart-rate efficiency verdict; inspect individual runs.")
        return parts.joined(separator: " ")
    }
    var findings: [AnalysisFinding] {
        guard !recentRuns.isEmpty, !previousRuns.isEmpty else {
            return [AnalysisFinding(title: "Not enough running data", detail: "One or both selected weeks have no recorded runs.", why: "A running pace or effort change needs runs in both selected calendar weeks. Walking remains visible as workload context.", tone: .insufficient)]
        }
        var result: [AnalysisFinding] = []
        if let percent = RunMath.percent(recentDistance, previousDistance) {
            if percent > 30 {
                result.append(AnalysisFinding(title: "Volume jumped \(Int(percent.rounded()))%", detail: "Running distance rose from \(Format.distance(previousDistance)) to \(Format.distance(recentDistance)).", why: "A jump above 30% changes training load; it is not a medical warning.", tone: .caution))
            } else if percent <= -5 {
                result.append(AnalysisFinding(title: "Running volume was \(Int(abs(percent).rounded()))% lower", detail: "Running distance fell from \(Format.distance(previousDistance)) to \(Format.distance(recentDistance)).", why: "This describes the selected weeks' recorded distance. A lighter week can be intentional; it does not prove fitness declined.", tone: .observation))
            }
        }
        let paces = recentRuns.compactMap(\.pace)
        if paces.count > 1, let fastest = paces.min(), let slowest = paces.max(), slowest - fastest >= 30 {
            result.insert(AnalysisFinding(title: "Selected week's runs had different paces", detail: "Individual running paces ranged from \(Format.pace(fastest)) to \(Format.pace(slowest)). Review each run below.", why: "A combined pace would hide these different sessions. We do not use it for a performance verdict.", tone: .observation), at: 0)
        }
        for match in sessionMatches.prefix(3) {
            guard let earlier = match.previous else { continue }
            let readout = RunReadout.make(latest: match.recent, previous: earlier)
            result.append(AnalysisFinding(title: "\(match.recent.start.formatted(date: .abbreviated, time: .omitted)): \(readout.title)", detail: "\(Format.pace(match.recent.pace)) and \(Format.number(match.recent.averageHR, unit: "bpm")) vs \(earlier.start.formatted(date: .abbreviated, time: .omitted)): \(Format.pace(earlier.pace)) and \(Format.number(earlier.averageHR, unit: "bpm")).", why: readout.caveat, tone: readout.tone == .improved ? .improved : readout.tone == .caution ? .caution : .observation))
        }
        if recentDays > previousDays {
            result.append(AnalysisFinding(title: "More running days", detail: "You ran on \(recentDays) day\(recentDays == 1 ? "" : "s") versus \(previousDays) before.", why: "This describes consistency, not performance quality.", tone: .observation))
        }
        if recentRuns.contains(where: { $0.averageHR == nil }) || previousRuns.contains(where: { $0.averageHR == nil }) {
            result.append(AnalysisFinding(title: "Heart-rate evidence is incomplete", detail: "At least one running workout lacks usable HR samples.", why: "Missing Health data is never treated as a zero or estimated from pace.", tone: .insufficient))
        }
        if result.isEmpty {
            result.append(AnalysisFinding(title: "No clear change yet", detail: "These running weeks were broadly steady on the measures available.", why: caveat, tone: .observation))
        }
        return Array(result.prefix(5))
    }

    private func activeDays(_ runs: [RunWorkout]) -> Int { Set(runs.map { Calendar.current.startOfDay(for: $0.start) }).count }
}

enum RunAnalytics {
    static func week(_ offset: Int, workouts: [RunWorkout], now: Date = Date(), calendar: Calendar = .current) -> WeekSummary? {
        guard offset >= 0, let currentStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
              let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: currentStart),
              let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
        return WeekSummary(start: start, workouts: workouts.filter { $0.start >= start && $0.start < end && $0.start <= now })
    }
    static func compareWeeks(_ recentOffset: Int, _ previousOffset: Int, workouts: [RunWorkout], now: Date = Date(), calendar: Calendar = .current) -> RunningWeekComparison? {
        guard recentOffset < previousOffset,
              let recent = week(recentOffset, workouts: workouts, now: now, calendar: calendar),
              let fullPrevious = week(previousOffset, workouts: workouts, now: now, calendar: calendar) else { return nil }
        // A partial current week is compared with the same elapsed part of its baseline week.
        let previous: WeekSummary
        if recentOffset == 0 {
            let elapsed = now.timeIntervalSince(recent.start)
            previous = WeekSummary(start: fullPrevious.start, workouts: fullPrevious.workouts.filter { $0.start < fullPrevious.start.addingTimeInterval(elapsed) })
        } else {
            previous = fullPrevious
        }
        return RunningWeekComparison(recent: recent, previous: previous, skippedWeeks: previousOffset - recentOffset - 1, isCurrentWeekPartial: recentOffset == 0)
    }
    static func latestCompletedRunningWeeks(_ workouts: [RunWorkout], now: Date = Date(), calendar: Calendar = .current) -> RunningWeekComparison? {
        guard let currentStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return nil }
        let weeks = RunMath.weeks(workouts, calendar: calendar)
            .filter { $0.start < currentStart && $0.workouts.contains { $0.kind == .running } }
        guard weeks.count >= 2 else { return nil }
        let daysApart = calendar.dateComponents([.day], from: weeks[1].start, to: weeks[0].start).day ?? 7
        return RunningWeekComparison(recent: weeks[0], previous: weeks[1], skippedWeeks: max(0, daysApart / 7 - 1), isCurrentWeekPartial: false)
    }
    static func rollingSevenDays(_ workouts: [RunWorkout], now: Date = Date(), calendar: Calendar = .current) -> (recent: ActivitySummary, previous: ActivitySummary) {
        let recentStart = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let previousStart = calendar.date(byAdding: .day, value: -7, to: recentStart) ?? recentStart
        return (ActivitySummary(date: recentStart, workouts: workouts.filter { $0.start >= recentStart && $0.start <= now }),
                ActivitySummary(date: previousStart, workouts: workouts.filter { $0.start >= previousStart && $0.start < recentStart }))
    }
}

enum Format {
    static func distance(_ meters: Double?) -> String { guard let meters else { return "Unavailable" }; return String(format: "%.2f km", meters / 1000) }
    static func pace(_ seconds: Double?) -> String { guard let seconds, seconds.isFinite, seconds > 0 else { return "Unavailable" }; let rounded = Int(seconds.rounded()); return "\(rounded / 60):\(String(format: "%02d", rounded % 60)) /km" }
    static func number(_ value: Double?, unit: String, digits: Int = 0) -> String { guard let value else { return "Unavailable" }; return String(format: "%.*f", digits, value) + " " + unit }
    static func duration(_ seconds: Double) -> String { let n = Int(seconds); return n >= 3600 ? "\(n/3600)h \((n%3600)/60)m" : "\(n/60)m \(n%60)s" }
}

// A deliberately conservative, local explanation for one comparable pair.
struct RunReadout {
    enum Tone { case improved, caution, neutral }
    let title: String
    let detail: String
    let suggestion: String
    let caveat: String
    let tone: Tone
    let confidence: String
    static func make(latest: RunWorkout, previous: RunWorkout) -> RunReadout {
        guard let pace = latest.pace, let oldPace = previous.pace else {
            return RunReadout(title: "Pace data is missing", detail: "These runs cannot be compared for speed.", suggestion: "Check that both workouts recorded distance.", caveat: "Workout pace needs duration and distance.", tone: .neutral, confidence: "LOW")
        }
        let seconds = oldPace - pace
        let magnitude = Int(abs(seconds).rounded())
        let distanceDifference = abs((latest.distance ?? 0) - (previous.distance ?? 0)) / max(previous.distance ?? 1, 1)
        var detail = abs(seconds) < 5 ? "The selected runs had similar workout pace (within 5 sec/km). Distance differed by \(Int((distanceDifference * 100).rounded()))%." : "The selected run was \(magnitude) sec/km \(seconds > 0 ? "faster" : "slower"). Distance differed by \(Int((distanceDifference * 100).rounded()))%."
        let hrChange: Double? = latest.averageHR.flatMap { hr in previous.averageHR.map { hr - $0 } }
        if let hrChange { detail += abs(hrChange) < 1 ? " Average heart rate was effectively unchanged." : " Average heart rate was \(Int(abs(hrChange).rounded())) bpm \(hrChange < 0 ? "lower" : "higher")." }
        let hrCovered = latest.hrCoverage >= latest.duration * 0.5 && previous.hrCoverage >= previous.duration * 0.5
        let tone: Tone
        let title: String
        let suggestion: String
        if distanceDifference > 0.25 {
            title = "Different distances, no pace verdict"; tone = .neutral; suggestion = "Try the same distance again for a fairer pace comparison."
        } else if abs(seconds) < 5 {
            if let hrChange, hrChange <= -4 { title = "Similar pace, lower heart rate"; tone = hrCovered ? .improved : .neutral; suggestion = "Repeat a similar run to see whether the pattern holds." }
            else if let hrChange, hrChange >= 6 { title = "Same pace, higher heart rate"; tone = hrCovered ? .caution : .neutral; suggestion = "Check route, recovery, and conditions before judging the trend." }
            else { title = "Mostly steady"; tone = .neutral; suggestion = "Another comparable run will make the direction clearer." }
        } else if seconds >= 5 {
            if let hrChange, hrChange >= 7 { title = "Faster, with higher heart rate"; tone = .neutral; suggestion = "This may be a harder effort. Repeat on a similar route before calling it progress." }
            else if let hrChange, hrChange <= -4 { title = "Faster at lower heart rate"; tone = hrCovered ? .improved : .neutral; suggestion = "Repeat the distance and route to see whether this efficiency clue holds." }
            else { title = "Faster; efficiency is unproven"; tone = .neutral; suggestion = "A similar run with good heart-rate coverage can test the efficiency change." }
        } else {
            if let hrChange, hrChange <= -4 { title = "Slower at lower heart rate"; tone = .neutral; suggestion = "This may have been an easier effort. Compare intent, route, and recovery before judging it." }
            else if let hrChange, hrChange >= 6 { title = "Slower at higher heart rate"; tone = hrCovered ? .caution : .neutral; suggestion = "Check conditions, route, and recovery. One run is not a fitness diagnosis." }
            else { title = "Slower; cause is unclear"; tone = .neutral; suggestion = "Check the route, pauses, and intended effort before judging the run." }
        }
        let missingHR = hrChange == nil
        let caveat = "These are recorded runs in date order. \(distanceDifference > 0.25 ? "Distances differ by more than 25%, so pace does not establish performance change. " : "Distances are within 25%. ")Route, elevation, weather, pauses, and workout intent may differ. \(missingHR ? "Heart-rate comparison is unavailable." : hrCovered ? "Both runs have at least 50% heart-rate sample coverage." : "Heart-rate sample coverage is incomplete; no efficiency verdict is given.") A single pair is only a clue."
        return RunReadout(title: title, detail: detail, suggestion: suggestion, caveat: caveat, tone: tone, confidence: "LOW · one pair")
    }
}
