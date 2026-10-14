import Testing
import Foundation
import SwiftData
import HealthKit
import CoreLocation
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

    @Test("WorkoutSession with no exercises saves endedAt correctly")
    func emptySessionEnds() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutSession.self, Exercise.self, WorkoutSet.self, configurations: config)
        let ctx = ModelContext(container)

        let session = WorkoutSession(
            workoutType: "other",
            workoutTypeDisplayName: "Other",
            label: "",
            startedAt: Date(timeIntervalSince1970: 0)
        )
        ctx.insert(session)

        session.endedAt = Date(timeIntervalSince1970: 300)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<WorkoutSession>())
        #expect(fetched[0].exercises.isEmpty)
        #expect(fetched[0].endedAt != nil)
        #expect(fetched[0].durationFormatted == "05:00")
    }

    @Test("handleHeartRateSamples picks most-recent sample")
    func heartRateTakesMostRecent() {
        let now = Date()
        let earlier = now.addingTimeInterval(-30)

        let hrType = HKQuantityType(.heartRate)
        let unit = HKUnit(from: "count/min")

        let oldSample = HKQuantitySample(type: hrType, quantity: HKQuantity(unit: unit, doubleValue: 60), start: earlier, end: earlier)
        let newSample = HKQuantitySample(type: hrType, quantity: HKQuantity(unit: unit, doubleValue: 90), start: now, end: now)

        let samples: [HKQuantitySample] = [oldSample, newSample]
        let latest = samples.max(by: { $0.endDate < $1.endDate })
        #expect(Int(latest!.quantity.doubleValue(for: unit)) == 90)
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

    @Test("validLocations filters out readings with non-positive horizontal accuracy")
    func validLocationsFiltersInaccurateReadings() {
        let coord = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        let good = CLLocation(coordinate: coord, altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date())
        let invalid = CLLocation(coordinate: coord, altitude: 0, horizontalAccuracy: -1, verticalAccuracy: 5, timestamp: Date())
        let zero = CLLocation(coordinate: coord, altitude: 0, horizontalAccuracy: 0, verticalAccuracy: 5, timestamp: Date())

        let result = WorkoutSessionService.validLocations([good, invalid, zero])

        #expect(result.count == 1)
        #expect(result[0].horizontalAccuracy == 5)
    }
}
