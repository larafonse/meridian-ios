import Testing
import Foundation
import SwiftData
@testable import Meridian

@Suite("WorkoutSession model")
struct WorkoutSessionTests {
    @Test("WorkoutSet stores reps and weight")
    func workoutSetStoresData() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutSession.self, Exercise.self, WorkoutSet.self, configurations: config)
        let ctx = ModelContext(container)

        let session = WorkoutSession(
            workoutType: "traditionalStrengthTraining",
            workoutTypeDisplayName: "Strength Training",
            label: "Leg Day",
            startedAt: .now
        )
        let exercise = Exercise(name: "Squat", order: 0)
        let set = WorkoutSet(reps: 10, weight: 135.0, unit: "lbs", order: 0)
        exercise.sets = [set]
        session.exercises = [exercise]
        ctx.insert(session)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<WorkoutSession>())
        #expect(fetched.count == 1)
        #expect(fetched[0].exercises[0].sets[0].reps == 10)
        #expect(fetched[0].exercises[0].sets[0].weight == 135.0)
    }

    @Test("Cascade delete removes exercises and sets")
    func cascadeDelete() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutSession.self, Exercise.self, WorkoutSet.self, configurations: config)
        let ctx = ModelContext(container)

        let session = WorkoutSession(
            workoutType: "running",
            workoutTypeDisplayName: "Running",
            label: "",
            startedAt: .now
        )
        let exercise = Exercise(name: "Sprint", order: 0)
        exercise.sets = [WorkoutSet(reps: 1, weight: 0, unit: "lbs", order: 0)]
        session.exercises = [exercise]
        ctx.insert(session)
        try ctx.save()

        ctx.delete(session)
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<Exercise>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<WorkoutSet>()).isEmpty)
    }

    @Test("durationFormatted returns MM:SS when endedAt is set")
    func durationFormatted() {
        let start = Date(timeIntervalSince1970: 0)
        let end = Date(timeIntervalSince1970: 2732) // 45m 32s
        let session = WorkoutSession(
            workoutType: "running",
            workoutTypeDisplayName: "Running",
            label: "",
            startedAt: start
        )
        session.endedAt = end
        #expect(session.durationFormatted == "45:32")
    }
}
