import Foundation
import HealthKit
import CoreLocation

@MainActor final class HealthStore: ObservableObject {
    @Published private(set) var workouts: [RunWorkout] = []
    @Published private(set) var lastSync: Date?
    @Published private(set) var loading = false
    @Published var error: String?
    @Published var authorized = false
    private let store: HKHealthStore?
    private let defaults = UserDefaults.standard
    private var observers: [HKObserverQuery] = []
    private var refreshPending = false
    var includeRunning: Bool { get { defaults.object(forKey: "running") as? Bool ?? true } set { defaults.set(newValue, forKey: "running") } }
    var includeWalking: Bool { get { defaults.object(forKey: "walking") as? Bool ?? true } set { defaults.set(newValue, forKey: "walking") } }
    var includeHiking: Bool { get { defaults.object(forKey: "hiking") as? Bool ?? true } set { defaults.set(newValue, forKey: "hiking") } }
    var historyMonths: Int { get { defaults.object(forKey: "historyMonths") as? Int ?? 12 } set { defaults.set(newValue, forKey: "historyMonths") } }
    init() {
        store = HKHealthStore.isHealthDataAvailable() ? HKHealthStore() : nil
        lastSync = defaults.object(forKey: "lastSync") as? Date
    }
    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute()]
        for identifier: HKQuantityTypeIdentifier in [.heartRate] { if let type = HKObjectType.quantityType(forIdentifier: identifier) { types.insert(type) } }
        return types
    }
    func authorize() async {
        guard let store else { error = "Apple Health is unavailable on this device."; return }
        do { try await store.requestAuthorization(toShare: [], read: readTypes); authorized = true; observeHealthChanges(); await refresh() }
        catch { self.error = error.localizedDescription }
    }
    func refresh() async {
        guard store != nil else { return }
        if loading { refreshPending = true; return }
        loading = true
        repeat {
            refreshPending = false
            await importSnapshot()
        } while refreshPending
        loading = false
    }
    private func observeHealthChanges() {
        guard let store else { return }
        guard observers.isEmpty else { return }
        let types: [HKSampleType] = [HKObjectType.workoutType(), HKObjectType.quantityType(forIdentifier: .heartRate)].compactMap { $0 }
        for type in types {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, error in
                Task { @MainActor [weak self] in
                    if let error { self?.error = error.localizedDescription }
                    else { await self?.refresh() }
                    completion()
                }
            }
            observers.append(query)
            store.execute(query)
        }
    }
    private func importSnapshot() async {
        guard let store else { return }
        do {
            let start = Calendar.current.date(byAdding: .month, value: -historyMonths, to: Date())!
            let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
            let raw: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: (samples as? [HKWorkout]) ?? []) }
                }; store.execute(query)
            }
            let enabled: Set<ActivityKind> = Set(([includeRunning ? .running : nil, includeWalking ? .walking : nil, includeHiking ? .hiking : nil] as [ActivityKind?]).compactMap { $0 })
            var loaded: [RunWorkout] = []
            for workout in raw where ActivityKind(workout.workoutActivityType).map(enabled.contains) == true {
                var item = RunWorkout(workout)
                let hr = try await heartRates(for: workout)
                if !hr.isEmpty {
                    let summary = RunMath.heartRateSummary(hr, workoutDuration: workout.duration)
                    item.averageHR = summary.average
                    item.maximumHR = summary.maximum
                    item.hrCoverage = summary.coverage
                }
                loaded.append(item)
            }
            workouts = loaded; lastSync = Date(); defaults.set(lastSync, forKey: "lastSync"); error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func heartRates(for workout: HKWorkout) async throws -> [(value: Double, date: Date)] {
        guard let store else { return [] }
        guard let type = HKObjectType.quantityType(forIdentifier: .heartRate) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: [.strictStartDate, .strictEndDate])
        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: (samples as? [HKQuantitySample]) ?? []) }
            }; store.execute(query)
        }
        return samples.map { ($0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())), $0.startDate) }
    }
    func loadRoute(for workout: RunWorkout) async -> [CLLocation] {
        guard let store else { return [] }
        let routes: [HKWorkoutRoute] = await withCheckedContinuation { continuation in
            let query = HKAnchoredObjectQuery(type: HKSeriesType.workoutRoute(), predicate: HKQuery.predicateForObjects(from: workout.healthWorkout), anchor: nil, limit: HKObjectQueryNoLimit) { _, samples, _, _, _ in continuation.resume(returning: samples?.compactMap { $0 as? HKWorkoutRoute } ?? []) }
            store.execute(query)
        }
        var locations: [CLLocation] = []
        for route in routes {
            let segment: [CLLocation] = await withCheckedContinuation { continuation in
                var result: [CLLocation] = []
                let query = HKWorkoutRouteQuery(route: route) { _, points, done, _ in
                    result.append(contentsOf: points ?? [])
                    if done { continuation.resume(returning: result) }
                }; store.execute(query)
            }
            locations.append(contentsOf: segment)
        }
        return locations.sorted { $0.timestamp < $1.timestamp }
    }
}
