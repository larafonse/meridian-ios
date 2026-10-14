import Foundation
import CoreLocation
import HealthKit

@MainActor
final class WorkoutMetricsAccumulator: ObservableObject {
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var activeCalories: Double = 0

    private let activityType: HKWorkoutActivityType
    private let bodyMassKg: Double?
    private let ageYears: Int?
    private let isMale: Bool?

    private var lastLocation: CLLocation?
    private var lastCalorieDate: Date?

    init(activityType: HKWorkoutActivityType, bodyMassKg: Double?, ageYears: Int?, isMale: Bool?) {
        self.activityType = activityType
        self.bodyMassKg = bodyMassKg
        self.ageYears = ageYears
        self.isMale = isMale
    }

    func addLocations(_ locations: [CLLocation]) {
        guard activityType.isGPSTracked else { return }
        for location in locations {
            if let last = lastLocation {
                distanceMeters += location.distance(from: last)
            }
            lastLocation = location
        }
    }

    func addHeartRateSample(bpm: Int, at date: Date) {
        guard let lastDate = lastCalorieDate else {
            lastCalorieDate = date
            return
        }
        let minutes = date.timeIntervalSince(lastDate) / 60.0
        guard minutes > 0 else { return }
        activeCalories += max(0, caloriesPerMinute(bpm: bpm) * minutes)
        lastCalorieDate = date
    }

    func reset() {
        distanceMeters = 0
        activeCalories = 0
        lastLocation = nil
        lastCalorieDate = nil
    }

    // MARK: - Calorie calculation

    private func caloriesPerMinute(bpm: Int) -> Double {
        let kg = bodyMassKg ?? 70.0
        if let age = ageYears, let male = isMale, bodyMassKg != nil {
            return male
                ? (-55.0969 + 0.6309 * Double(bpm) + 0.1988 * kg + 0.2017 * Double(age)) / 4.184
                : (-20.4022 + 0.4472 * Double(bpm) - 0.1263 * kg + 0.074  * Double(age)) / 4.184
        }
        return Self.met(for: activityType) * kg / 60.0
    }

    nonisolated static func met(for type: HKWorkoutActivityType) -> Double {
        switch type {
        case .walking:                          return 3.5
        case .running:                          return 8.0
        case .cycling:                          return 6.0
        case .traditionalStrengthTraining,
             .functionalStrengthTraining:       return 5.0
        case .highIntensityIntervalTraining:    return 8.0
        case .yoga:                             return 2.5
        case .pilates:                          return 3.0
        case .rowing:                           return 6.0
        case .elliptical:                       return 5.0
        case .swimming:                         return 6.0
        default:                                return 4.0
        }
    }
}
