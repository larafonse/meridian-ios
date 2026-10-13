import Foundation
import SwiftData

@Model
final class WorkoutTemplate {
    var id: UUID
    var name: String
    var workoutType: String
    var workoutTypeDisplayName: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade)
    var exercises: [TemplateExercise]

    init(name: String, workoutType: String, workoutTypeDisplayName: String) {
        self.id = UUID()
        self.name = name
        self.workoutType = workoutType
        self.workoutTypeDisplayName = workoutTypeDisplayName
        self.createdAt = .now
        self.exercises = []
    }
}

@Model
final class TemplateExercise {
    var id: UUID
    var name: String
    var order: Int
    var defaultReps: Int?
    var defaultWeight: Double?
    var defaultWeightUnit: String

    init(name: String, order: Int, defaultReps: Int?, defaultWeight: Double?, defaultWeightUnit: String) {
        self.id = UUID()
        self.name = name
        self.order = order
        self.defaultReps = defaultReps
        self.defaultWeight = defaultWeight
        self.defaultWeightUnit = defaultWeightUnit
    }
}
