import Foundation
import CoreLocation
import Observation
import HealthKit

@Observable
@MainActor
final class RouteSyncService {
    private(set) var allCoordinates: [[CLLocationCoordinate2D]] = []
    private(set) var isSyncing = false
    private(set) var syncProgress: (fetched: Int, total: Int) = (0, 0)

    private let cache = RouteCache()
    private let workoutService = HealthKitWorkoutService()
    private let routeService = WorkoutRouteService()

    func sync() async {
        guard !isSyncing else { return }

        // 1. Load from cache immediately so the map renders before any HealthKit call.
        let cachedUUIDs = cache.cachedUUIDs()
        allCoordinates = cachedUUIDs.compactMap { cache.coordinates(for: $0) }

        isSyncing = true
        defer { isSyncing = false }

        // 2. Fetch all GPS workouts; swallow errors (returns [] on failure).
        let workouts = (try? await workoutService.fetchAllGPSWorkouts()) ?? []
        let newWorkouts = workouts.filter { !cachedUUIDs.contains($0.uuid) }
        syncProgress = (fetched: 0, total: newWorkouts.count)

        guard !newWorkouts.isEmpty else { return }

        // Capture services as locals — they are @unchecked Sendable and safe to
        // use from concurrent task closures without hopping back to the main actor.
        let taskRouteService = self.routeService
        let taskCache = self.cache

        // 3. Fetch new routes concurrently; append each as it arrives.
        await withTaskGroup(of: (UUID, [CLLocationCoordinate2D]).self) { group in
            for workout in newWorkouts {
                group.addTask {
                    let coords = await taskRouteService.fetchRoute(for: workout)
                    return (workout.uuid, coords)
                }
            }
            for await (uuid, coords) in group {
                syncProgress.fetched += 1
                guard !coords.isEmpty else { continue }
                taskCache.store(coords, for: uuid)
                allCoordinates.append(coords)
            }
        }
    }
}
