import HealthKit

struct WorkoutType: Identifiable, Hashable {
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
