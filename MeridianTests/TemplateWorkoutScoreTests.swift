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
}
