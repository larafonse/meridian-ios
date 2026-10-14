import Foundation
import SwiftData

@Model
final class WorkoutSession {
    var id: UUID
    var healthKitUUID: UUID?
    var workoutType: String
    var workoutTypeDisplayName: String
    var label: String
    var startedAt: Date
    var endedAt: Date?
    var distanceMeters: Double?
    var activeCalories: Double?

    @Relationship(deleteRule: .cascade)
    var exercises: [Exercise]

    init(workoutType: String, workoutTypeDisplayName: String, label: String, startedAt: Date) {
        self.id = UUID()
        self.workoutType = workoutType
        self.workoutTypeDisplayName = workoutTypeDisplayName
        self.label = label
        self.startedAt = startedAt
        self.endedAt = nil
        self.distanceMeters = nil
        self.activeCalories = nil
        self.exercises = []
    }

    var durationFormatted: String {
        let end = endedAt ?? Date()
        let seconds = Int(end.timeIntervalSince(startedAt))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

@Model
final class Exercise {
    var id: UUID
    var name: String
    var order: Int

    @Relationship(deleteRule: .cascade)
    var sets: [WorkoutSet]

    init(name: String, order: Int) {
        self.id = UUID()
        self.name = name
        self.order = order
        self.sets = []
    }
}

@Model
final class WorkoutSet {
    var id: UUID
    var reps: Int
    var weight: Double
    var unit: String
    var order: Int

    init(reps: Int, weight: Double, unit: String, order: Int) {
        self.id = UUID()
        self.reps = reps
        self.weight = weight
        self.unit = unit
        self.order = order
    }
}
