import Testing
import Foundation
import SwiftData
import HealthKit
@testable import Meridian

@Suite("WorkoutLinkerService")
@MainActor
struct WorkoutLinkerTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: WorkoutSession.self, Exercise.self, WorkoutSet.self, configurations: config)
    }

    private func makeSession(
        start: Date,
        end: Date?,
        in ctx: ModelContext
    ) -> WorkoutSession {
        let s = WorkoutSession(
            workoutType: "traditionalStrengthTraining",
            workoutTypeDisplayName: "Strength Training",
            label: "",
            startedAt: start
        )
        s.endedAt = end
        ctx.insert(s)
        return s
    }

    private func makeHKWorkout(start: Date, end: Date) -> HKWorkout {
        HKWorkout(activityType: .traditionalStrengthTraining, start: start, end: end)
    }

    @Test("returns nil when sessions list is empty")
    func noSessions() throws {
        let c = try makeContainer()
        let linker = WorkoutLinkerService(modelContainer: c)
        let hk = makeHKWorkout(start: .now, end: .now.addingTimeInterval(3600))
        #expect(linker.findBestOverlap(hkWorkout: hk, sessions: []) == nil)
    }

    @Test("returns nil when no session overlaps the HK workout")
    func noOverlap() throws {
        let c = try makeContainer()
        let linker = WorkoutLinkerService(modelContainer: c)
        let ctx = ModelContext(c)
        let base = Date(timeIntervalSince1970: 0)
        // Session ends at t=1800; HK starts at t=3600
        let session = makeSession(start: base, end: base.addingTimeInterval(1800), in: ctx)
        let hk = makeHKWorkout(start: base.addingTimeInterval(3600), end: base.addingTimeInterval(5400))
        #expect(linker.findBestOverlap(hkWorkout: hk, sessions: [session]) == nil)
    }

    @Test("returns the single overlapping session")
    func singleOverlap() throws {
        let c = try makeContainer()
        let linker = WorkoutLinkerService(modelContainer: c)
        let ctx = ModelContext(c)
        let base = Date(timeIntervalSince1970: 0)
        // Session: 0..3600, HK: 1800..5400 — overlap 1800..3600
        let session = makeSession(start: base, end: base.addingTimeInterval(3600), in: ctx)
        let hk = makeHKWorkout(start: base.addingTimeInterval(1800), end: base.addingTimeInterval(5400))
        #expect(linker.findBestOverlap(hkWorkout: hk, sessions: [session])?.id == session.id)
    }

    @Test("picks the session with greater overlap when two candidates exist")
    func picksGreaterOverlap() throws {
        let c = try makeContainer()
        let linker = WorkoutLinkerService(modelContainer: c)
        let ctx = ModelContext(c)
        let base = Date(timeIntervalSince1970: 0)
        // HK: 1000..5000
        // Session A: 0..2000   → overlap 1000..2000 = 1000 s
        // Session B: 500..4500 → overlap 1000..4500 = 3500 s ← better
        let sessionA = makeSession(start: base, end: base.addingTimeInterval(2000), in: ctx)
        let sessionB = makeSession(start: base.addingTimeInterval(500), end: base.addingTimeInterval(4500), in: ctx)
        let hk = makeHKWorkout(start: base.addingTimeInterval(1000), end: base.addingTimeInterval(5000))
        #expect(linker.findBestOverlap(hkWorkout: hk, sessions: [sessionA, sessionB])?.id == sessionB.id)
    }

    @Test("matches an in-progress session (endedAt == nil)")
    func inProgressSession() throws {
        let c = try makeContainer()
        let linker = WorkoutLinkerService(modelContainer: c)
        let ctx = ModelContext(c)
        // HK workout finished 30 minutes ago; session started 1 hour ago and is still open
        let now = Date()
        let session = makeSession(start: now.addingTimeInterval(-3600), end: nil, in: ctx)
        let hk = makeHKWorkout(
            start: now.addingTimeInterval(-3600),
            end: now.addingTimeInterval(-1800)
        )
        #expect(linker.findBestOverlap(hkWorkout: hk, sessions: [session])?.id == session.id)
    }

    @Test("does not match a session that ends before the HK workout starts")
    func sessionEndsBeforeHKStarts() throws {
        let c = try makeContainer()
        let linker = WorkoutLinkerService(modelContainer: c)
        let ctx = ModelContext(c)
        let base = Date(timeIntervalSince1970: 0)
        // Session: 0..1000, HK: 2000..3000
        let session = makeSession(start: base, end: base.addingTimeInterval(1000), in: ctx)
        let hk = makeHKWorkout(start: base.addingTimeInterval(2000), end: base.addingTimeInterval(3000))
        #expect(linker.findBestOverlap(hkWorkout: hk, sessions: [session]) == nil)
    }

    @Test("does not match a session starting after the HK workout ends")
    func sessionStartsAfterHKEnds() throws {
        let c = try makeContainer()
        let linker = WorkoutLinkerService(modelContainer: c)
        let ctx = ModelContext(c)
        let base = Date(timeIntervalSince1970: 0)
        // HK: 0..1000, Session: 2000..3000
        let session = makeSession(start: base.addingTimeInterval(2000), end: base.addingTimeInterval(3000), in: ctx)
        let hk = makeHKWorkout(start: base, end: base.addingTimeInterval(1000))
        #expect(linker.findBestOverlap(hkWorkout: hk, sessions: [session]) == nil)
    }
}
