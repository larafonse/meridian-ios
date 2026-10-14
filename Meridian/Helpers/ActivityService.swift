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
            HKQuantityType(.bodyMass),
            HKQuantityType(.stepCount),
            HKQuantityType(.distanceWalkingRunning)
        ]
        let writeTypes: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.distanceCycling),
            HKQuantityType(.heartRate)
        ]
        try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
    }

    func fetchTodayStepsAndDistance() async throws -> (steps: Int, distanceMeters: Double) {
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)

        async let steps = fetchTodayQuantitySum(type: HKQuantityType(.stepCount), unit: .count(), start: startOfDay, end: now)
        async let distance = fetchTodayQuantitySum(type: HKQuantityType(.distanceWalkingRunning), unit: .meter(), start: startOfDay, end: now)

        return (steps: Int(try await steps), distanceMeters: try await distance)
    }

    private func fetchTodayQuantitySum(type: HKQuantityType, unit: HKUnit, start: Date, end: Date) async throws -> Double {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let value = stats?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: value)
            }
            self.store.execute(query)
        }
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
