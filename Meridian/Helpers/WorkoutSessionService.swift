import Foundation
import HealthKit
import Combine

@MainActor
final class WorkoutSessionService: ObservableObject {
    @Published var currentBPM: Int? = nil

    private let store = HKHealthStore()
    private var builder: HKWorkoutBuilder?
    private var hrQuery: HKAnchoredObjectQuery?
    private var workoutStartDate: Date?

    func reset() {
        stopHeartRateObserver()
        builder = nil
        workoutStartDate = nil
        currentBPM = nil
    }

    func start(configuration: HKWorkoutConfiguration) async throws {
        let startDate = Date()
        workoutStartDate = startDate
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        self.builder = builder
        try await builder.beginCollection(at: startDate)
        startHeartRateObserver(from: startDate)
    }

    /// Returns the saved HKWorkout UUID, or nil if HealthKit write fails.
    func finish() async throws -> UUID? {
        let endDate = Date()
        guard let builder else { return nil }

        stopHeartRateObserver()

        if let start = workoutStartDate {
            let hrSamples = await fetchHeartRateSamples(from: start, to: endDate)
            if !hrSamples.isEmpty {
                try? await builder.addSamples(hrSamples)
            }
        }

        do {
            try await builder.endCollection(at: endDate)
            let workout = try await builder.finishWorkout()
            self.builder = nil
            workoutStartDate = nil
            return workout?.uuid
        } catch {
            self.builder = nil
            workoutStartDate = nil
            return nil
        }
    }

    // MARK: - Heart Rate

    private func startHeartRateObserver(from startDate: Date) {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let hrType = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: nil, options: .strictStartDate)
        let query = HKAnchoredObjectQuery(
            type: hrType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, _ in
            Task { @MainActor [weak self] in self?.handleHeartRateSamples(samples) }
        }
        query.updateHandler = { [weak self] _, samples, _, _, _ in
            Task { @MainActor [weak self] in self?.handleHeartRateSamples(samples) }
        }
        store.execute(query)
        hrQuery = query
    }

    private func stopHeartRateObserver() {
        if let q = hrQuery { store.stop(q) }
        hrQuery = nil
    }

    private func handleHeartRateSamples(_ samples: [HKSample]?) {
        guard let samples = samples as? [HKQuantitySample], !samples.isEmpty else { return }
        let latest = samples.max(by: { $0.endDate < $1.endDate })
        currentBPM = latest.map { Int($0.quantity.doubleValue(for: HKUnit(from: "count/min"))) }
    }

    private func fetchHeartRateSamples(from start: Date, to end: Date) async -> [HKSample] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let hrType = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: hrType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                continuation.resume(returning: samples ?? [])
            }
            store.execute(query)
        }
    }
}

// MARK: - WorkoutType catalogue

struct WorkoutType: Identifiable {
    let id: String
    let displayName: String
    let symbol: String
    let hkType: HKWorkoutActivityType

    static let all: [WorkoutType] = [
        WorkoutType(id: "traditionalStrengthTraining",   displayName: "Strength Training",   symbol: "dumbbell",                           hkType: .traditionalStrengthTraining),
        WorkoutType(id: "functionalStrengthTraining",    displayName: "Functional Training",  symbol: "figure.strengthtraining.functional", hkType: .functionalStrengthTraining),
        WorkoutType(id: "running",                       displayName: "Running",              symbol: "figure.run",                         hkType: .running),
        WorkoutType(id: "cycling",                       displayName: "Cycling",              symbol: "figure.outdoor.cycle",               hkType: .cycling),
        WorkoutType(id: "highIntensityIntervalTraining", displayName: "HIIT",                 symbol: "bolt.heart",                         hkType: .highIntensityIntervalTraining),
        WorkoutType(id: "walking",                       displayName: "Walking",              symbol: "figure.walk",                        hkType: .walking),
        WorkoutType(id: "swimming",                      displayName: "Swimming",             symbol: "figure.pool.swim",                   hkType: .swimming),
        WorkoutType(id: "yoga",                          displayName: "Yoga",                 symbol: "figure.yoga",                        hkType: .yoga),
        WorkoutType(id: "pilates",                       displayName: "Pilates",              symbol: "figure.pilates",                     hkType: .pilates),
        WorkoutType(id: "rowing",                        displayName: "Rowing",               symbol: "figure.rower",                       hkType: .rowing),
        WorkoutType(id: "elliptical",                    displayName: "Elliptical",           symbol: "figure.elliptical",                  hkType: .elliptical),
        WorkoutType(id: "other",                         displayName: "Other",                symbol: "figure.mixed.cardio",                hkType: .other),
    ]
}
