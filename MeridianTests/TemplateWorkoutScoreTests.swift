import Testing
import Foundation
import SwiftData
@testable import Meridian

@Suite("TemplateWorkoutScore model")
struct TemplateWorkoutScoreTests {
    @Test("TemplateWorkoutScore persists all fields")
    func persistsAllFields() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TemplateWorkoutScore.self, configurations: config)
        let ctx = ModelContext(container)

        let templateID = UUID()
        let sessionID = UUID()
        let date = Date(timeIntervalSince1970: 1_000_000)
        let score = TemplateWorkoutScore(
            templateID: templateID,
            templateName: "Push Pull Legs",
            sessionID: sessionID,
            date: date,
            totalVolume: 12450.0
        )
        ctx.insert(score)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<TemplateWorkoutScore>())
        #expect(fetched.count == 1)
        #expect(fetched[0].templateID == templateID)
        #expect(fetched[0].templateName == "Push Pull Legs")
        #expect(fetched[0].sessionID == sessionID)
        #expect(fetched[0].totalVolume == 12450.0)
    }

    @Test("WorkoutSession.templateID defaults to nil")
    func templateIDDefaultsNil() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutSession.self, Exercise.self, WorkoutSet.self, configurations: config)
        let ctx = ModelContext(container)

        let session = WorkoutSession(
            workoutType: "traditionalStrengthTraining",
            workoutTypeDisplayName: "Strength Training",
            label: "",
            startedAt: .now
        )
        ctx.insert(session)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<WorkoutSession>())
        #expect(fetched[0].templateID == nil)
    }

    @Test("totalVolumeInLbs sums weight × reps in lbs")
    func totalVolumeAllLbs() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutSession.self, Exercise.self, WorkoutSet.self, configurations: config)
        let ctx = ModelContext(container)

        let session = WorkoutSession(
            workoutType: "traditionalStrengthTraining",
            workoutTypeDisplayName: "Strength Training",
            label: "",
            startedAt: .now
        )
        let ex = Exercise(name: "Squat", order: 0)
        ex.sets = [
            WorkoutSet(reps: 10, weight: 135.0, unit: "lbs", order: 0),
            WorkoutSet(reps: 8, weight: 155.0, unit: "lbs", order: 1)
        ]
        session.exercises = [ex]
        ctx.insert(session)

        // 10*135 + 8*155 = 1350 + 1240 = 2590
        #expect(totalVolumeInLbs(session: session) == 2590.0)
    }

    @Test("totalVolumeInLbs converts kg sets to lbs")
    func totalVolumeKg() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutSession.self, Exercise.self, WorkoutSet.self, configurations: config)
        let ctx = ModelContext(container)

        let session = WorkoutSession(
            workoutType: "traditionalStrengthTraining",
            workoutTypeDisplayName: "Strength Training",
            label: "",
            startedAt: .now
        )
        let ex = Exercise(name: "Deadlift", order: 0)
        ex.sets = [
            WorkoutSet(reps: 5, weight: 100.0, unit: "kg", order: 0)
        ]
        session.exercises = [ex]
        ctx.insert(session)

        // 5 * 100 * 0.453592 = 226.796
        let result = totalVolumeInLbs(session: session)
        #expect(abs(result - 226.796) < 0.001)
    }

    @Test("totalVolumeInLbs returns 0 for session with no sets")
    func totalVolumeEmpty() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutSession.self, Exercise.self, WorkoutSet.self, configurations: config)
        let ctx = ModelContext(container)

        let session = WorkoutSession(
            workoutType: "other",
            workoutTypeDisplayName: "Other",
            label: "",
            startedAt: .now
        )
        ctx.insert(session)

        #expect(totalVolumeInLbs(session: session) == 0.0)
    }
}
