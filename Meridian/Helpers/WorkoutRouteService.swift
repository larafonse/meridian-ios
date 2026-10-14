import HealthKit
import CoreLocation

final class WorkoutRouteService: @unchecked Sendable {
    private let store = HKHealthStore()

    /// Looks up an HKWorkout in HealthKit by UUID. Returns nil when unavailable or not found.
    func fetchWorkout(uuid: UUID) async -> HKWorkout? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let predicate = HKQuery.predicateForObject(with: uuid)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: samples?.first as? HKWorkout)
            }
            store.execute(query)
        }
    }

    /// Returns all GPS coordinates from the HKWorkoutRoute associated with the given workout.
    /// Returns an empty array when no route exists or HealthKit is unavailable.
    func fetchRoute(for workout: HKWorkout) async -> [CLLocationCoordinate2D] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let routes = await fetchRoutes(for: workout)
        guard let route = routes.first else { return [] }
        return await fetchCoordinates(from: route)
    }

    private func fetchRoutes(for workout: HKWorkout) async -> [HKWorkoutRoute] {
        let predicate = HKQuery.predicateForObjects(from: workout)
        return await withCheckedContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: HKSeriesType.workoutRoute(),
                predicate: predicate,
                anchor: nil,
                limit: HKObjectQueryNoLimit
            ) { [self] q, samples, _, _, _ in
                // Stop the query immediately to prevent update handler from firing again.
                store.stop(q)
                continuation.resume(returning: samples as? [HKWorkoutRoute] ?? [])
            }
            store.execute(query)
        }
    }

    private func fetchCoordinates(from route: HKWorkoutRoute) async -> [CLLocationCoordinate2D] {
        nonisolated(unsafe) var coordinates: [CLLocationCoordinate2D] = []
        nonisolated(unsafe) var didResume = false
        return await withCheckedContinuation { continuation in
            let query = HKWorkoutRouteQuery(route: route) { [self] q, locations, done, error in
                if let locations {
                    coordinates.append(contentsOf: locations.map(\.coordinate))
                }
                // Resume on completion OR on error (to avoid hanging the caller).
                // Guard ensures the continuation is never resumed a second time even if
                // HealthKit fires an error callback followed by a done=true callback.
                if (done || error != nil) && !didResume {
                    didResume = true
                    store.stop(q)
                    continuation.resume(returning: coordinates)
                }
            }
            store.execute(query)
        }
    }
}
