import HealthKit

final class HealthKitActivityService: @unchecked Sendable {
    private let store = HKHealthStore()

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let readTypes: Set<HKObjectType> = [
            HKObjectType.activitySummaryType(),
            HKQuantityType(.heartRate),
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
            HKQuantityType(.bodyMass)
        ]
        let writeTypes: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.distanceCycling)
        ]
        try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
    }

    func fetchTodaySummary() async throws -> ActivitySummary? {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.era, .year, .month, .day], from: Date())
        components.calendar = calendar
        let predicate = HKQuery.predicateForActivitySummary(with: components)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let hkSummary = summaries?.first else {
                    continuation.resume(returning: nil)
                    return
                }
                let summary = ActivitySummary(
                    moveEnergy: hkSummary.activeEnergyBurned.doubleValue(for: .kilocalorie()),
                    moveGoal: hkSummary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie()),
                    exerciseMinutes: hkSummary.appleExerciseTime.doubleValue(for: .minute()),
                    exerciseGoal: hkSummary.appleExerciseTimeGoal.doubleValue(for: .minute()),
                    standHours: hkSummary.appleStandHours.doubleValue(for: .count()),
                    standGoal: hkSummary.appleStandHoursGoal.doubleValue(for: .count())
                )
                continuation.resume(returning: summary)
            }
            self.store.execute(query)
        }
    }
}
