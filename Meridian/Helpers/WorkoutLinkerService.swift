import Foundation
import HealthKit
import SwiftData

@MainActor
final class WorkoutLinkerService: ObservableObject {
    private let store = HKHealthStore()
    private let modelContainer: ModelContainer
    private var observerQuery: HKObserverQuery?

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        startObserving()
    }

    // MARK: - Observer

    private func startObserving() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let workoutType = HKObjectType.workoutType()
        let query = HKObserverQuery(sampleType: workoutType, predicate: nil) { [weak self] _, completionHandler, error in
            // Call immediately so HealthKit knows delivery was received
            completionHandler()
            guard error == nil else { return }
            Task { @MainActor [weak self] in
                await self?.linkPendingSessions()
            }
        }
        store.execute(query)
        observerQuery = query
        store.enableBackgroundDelivery(for: workoutType, frequency: .immediate) { _, _ in }
    }

    func stopObserving() {
        if let q = observerQuery { store.stop(q) }
        observerQuery = nil
    }

    // MARK: - Auto-linking

    /// Scans all unlinked WorkoutSessions and matches them against recent HK workouts by time overlap.
    /// Safe to call on every app foreground / dashboard refresh.
    func linkPendingSessions() async {
        let ctx = ModelContext(modelContainer)
        let predicate = #Predicate<WorkoutSession> { $0.healthKitUUID == nil }
        guard let unlinked = try? ctx.fetch(FetchDescriptor<WorkoutSession>(predicate: predicate)),
              !unlinked.isEmpty else { return }

        let earliest = unlinked.map(\.startedAt).min() ?? Date().addingTimeInterval(-86400)
        let hkWorkouts = await fetchHKWorkouts(from: earliest.addingTimeInterval(-3600))
        guard !hkWorkouts.isEmpty else { return }

        var remaining = unlinked
        for hkWorkout in hkWorkouts {
            guard let match = findBestOverlap(hkWorkout: hkWorkout, sessions: remaining) else { continue }
            link(session: match, to: hkWorkout)
            remaining.removeAll { $0.id == match.id }
        }

        try? ctx.save()
    }

    // MARK: - Linking helpers (internal for testability)

    func findBestOverlap(hkWorkout: HKWorkout, sessions: [WorkoutSession]) -> WorkoutSession? {
        let overlapping = sessions.filter { session in
            let sessionEnd = session.endedAt ?? Date()
            return session.startedAt <= hkWorkout.endDate && sessionEnd >= hkWorkout.startDate
        }
        return overlapping.max {
            overlapDuration(session: $0, hkWorkout: hkWorkout) <
            overlapDuration(session: $1, hkWorkout: hkWorkout)
        }
    }

    private func overlapDuration(session: WorkoutSession, hkWorkout: HKWorkout) -> TimeInterval {
        let sessionEnd = session.endedAt ?? Date()
        let overlapStart = max(session.startedAt, hkWorkout.startDate)
        let overlapEnd = min(sessionEnd, hkWorkout.endDate)
        return max(0, overlapEnd.timeIntervalSince(overlapStart))
    }

    private func link(session: WorkoutSession, to hkWorkout: HKWorkout) {
        session.healthKitUUID = hkWorkout.uuid
        if session.endedAt == nil {
            session.endedAt = hkWorkout.endDate
        }
        session.activeCalories = hkWorkout.statistics(for: HKQuantityType(.activeEnergyBurned))?
            .sumQuantity()?.doubleValue(for: .kilocalorie())
        session.distanceMeters = hkWorkout.statistics(for: HKQuantityType(.distanceWalkingRunning))?
            .sumQuantity()?.doubleValue(for: .meter())
    }

    // MARK: - HK fetch

    private func fetchHKWorkouts(from startDate: Date) async -> [HKWorkout] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: nil, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: 50,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            self.store.execute(query)
        }
    }
}
