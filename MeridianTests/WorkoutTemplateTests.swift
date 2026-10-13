import Testing
import Foundation
import SwiftData
@testable import Meridian

@Suite("WorkoutTemplate model")
struct WorkoutTemplateTests {

    @Test("Template stores name and exercises")
    func templateStoresData() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: WorkoutTemplate.self, TemplateExercise.self,
            configurations: config
        )
        let ctx = ModelContext(container)

        let template = WorkoutTemplate(
            name: "Leg Day",
            workoutType: "traditionalStrengthTraining",
            workoutTypeDisplayName: "Strength Training"
        )
        let ex = TemplateExercise(name: "Squat", order: 0, defaultReps: 5, defaultWeight: 135.0, defaultWeightUnit: "lbs")
        template.exercises = [ex]
        ctx.insert(template)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<WorkoutTemplate>())
        #expect(fetched.count == 1)
        #expect(fetched[0].name == "Leg Day")
        #expect(fetched[0].exercises[0].defaultWeight == 135.0)
    }

    @Test("Cascade delete removes template exercises")
    func cascadeDeleteTemplate() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: WorkoutTemplate.self, TemplateExercise.self,
            configurations: config
        )
        let ctx = ModelContext(container)

        let template = WorkoutTemplate(
            name: "Chest",
            workoutType: "traditionalStrengthTraining",
            workoutTypeDisplayName: "Strength Training"
        )
        template.exercises = [TemplateExercise(name: "Bench Press", order: 0, defaultReps: nil, defaultWeight: nil, defaultWeightUnit: "lbs")]
        ctx.insert(template)
        try ctx.save()

        ctx.delete(template)
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<TemplateExercise>()).isEmpty)
    }

    // MARK: - Pre-fill logic tests

    @Test("Pre-fill uses last session history over template defaults")
    func preFillUsesHistory() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: WorkoutTemplate.self, TemplateExercise.self,
            WorkoutSession.self, Exercise.self, WorkoutSet.self,
            configurations: config
        )
        let ctx = ModelContext(container)

        let lastSession = WorkoutSession(
            workoutType: "traditionalStrengthTraining",
            workoutTypeDisplayName: "Strength Training",
            label: "Leg Day",
            startedAt: Date(timeIntervalSince1970: 0)
        )
        lastSession.endedAt = Date(timeIntervalSince1970: 3600)
        let historyExercise = Exercise(name: "Squat", order: 0)
        let historySet = WorkoutSet(reps: 8, weight: 185.0, unit: "lbs", order: 0)
        historyExercise.sets = [historySet]
        lastSession.exercises = [historyExercise]
        ctx.insert(lastSession)
        try ctx.save()

        let templateEx = TemplateExercise(name: "Squat", order: 0, defaultReps: 5, defaultWeight: 135.0, defaultWeightUnit: "lbs")

        let result = prefillSets(for: templateEx, lastSession: lastSession)
        #expect(result.count == 1)
        #expect(result[0].reps == 8)
        #expect(result[0].weight == 185.0)
    }

    @Test("Pre-fill falls back to template defaults when no history")
    func preFillFallsBackToDefaults() {
        let templateEx = TemplateExercise(name: "Bench Press", order: 0, defaultReps: 10, defaultWeight: 135.0, defaultWeightUnit: "lbs")
        let result = prefillSets(for: templateEx, lastSession: nil)
        #expect(result.count == 1)
        #expect(result[0].reps == 10)
        #expect(result[0].weight == 135.0)
    }

    @Test("Pre-fill creates empty set when no history and no defaults")
    func preFillCreatesEmptySetWhenNoData() {
        let templateEx = TemplateExercise(name: "New Exercise", order: 0, defaultReps: nil, defaultWeight: nil, defaultWeightUnit: "lbs")
        let result = prefillSets(for: templateEx, lastSession: nil)
        #expect(result.count == 1)
        #expect(result[0].reps == 0)
        #expect(result[0].weight == 0)
    }
}

/// Pure pre-fill function — extracted for testability, mirrored in StartWorkoutSheet.
func prefillSets(for templateExercise: TemplateExercise, lastSession: WorkoutSession?) -> [(reps: Int, weight: Double, unit: String)] {
    if let last = lastSession,
       let match = last.exercises.first(where: { $0.name.lowercased() == templateExercise.name.lowercased() }) {
        let sorted = match.sets.sorted { $0.order < $1.order }
        return sorted.map { (reps: $0.reps, weight: $0.weight, unit: $0.unit) }
    } else if templateExercise.defaultReps != nil || templateExercise.defaultWeight != nil {
        return [(reps: templateExercise.defaultReps ?? 0, weight: templateExercise.defaultWeight ?? 0, unit: templateExercise.defaultWeightUnit)]
    } else {
        return [(reps: 0, weight: 0, unit: "lbs")]
    }
}
