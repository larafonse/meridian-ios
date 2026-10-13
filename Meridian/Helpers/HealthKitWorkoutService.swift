import HealthKit

final class HealthKitWorkoutService: @unchecked Sendable {
    private let store = HKHealthStore()

    func fetchRecentWorkouts(limit: Int = 30) async throws -> [HKWorkout] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let workoutType = HKObjectType.workoutType()
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: thirtyDaysAgo, end: nil, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: limit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }
    }
}

extension HKWorkoutActivityType {
    /// Human-readable display name matching Meridian's WorkoutType catalogue.
    var meridianDisplayName: String {
        switch self {
        case .traditionalStrengthTraining: return "Strength Training"
        case .functionalStrengthTraining:  return "Functional Training"
        case .running:                     return "Running"
        case .cycling:                     return "Cycling"
        case .highIntensityIntervalTraining: return "HIIT"
        case .walking:                     return "Walking"
        case .swimming:                    return "Swimming"
        case .yoga:                        return "Yoga"
        case .pilates:                     return "Pilates"
        case .rowing:                      return "Rowing"
        case .elliptical:                  return "Elliptical"
        default:                           return "Workout"
        }
    }
}
