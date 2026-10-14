import SwiftUI
import HealthKit
import MapKit
import CoreLocation

extension HKWorkoutActivityType {
    var isGPSTracked: Bool {
        switch self {
        case .cycling, .running, .walking: return true
        default: return false
        }
    }
}

struct RoutesView: View {
    @State private var allCoordinates: [[CLLocationCoordinate2D]] = []
    @State private var isLoading = true

    private let workoutService = HealthKitWorkoutService()
    private let routeService = WorkoutRouteService()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Routes")
                .navigationBarTitleDisplayMode(.inline)
        }
        .task { await loadAllRoutes() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Loading routes…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if allCoordinates.isEmpty {
            ContentUnavailableView(
                "No Routes",
                systemImage: "map",
                description: Text("GPS workouts from your Apple Watch will appear here.")
            )
        } else {
            let flat = allCoordinates.flatMap { $0 }
            Map(initialPosition: .region(routeMapRegion(for: flat))) {
                ForEach(allCoordinates.indices, id: \.self) { i in
                    MapPolyline(coordinates: allCoordinates[i])
                        .stroke(Color.accentColor.opacity(0.8), lineWidth: 2)
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func loadAllRoutes() async {
        defer { isLoading = false }
        let workouts = (try? await workoutService.fetchRecentWorkouts(limit: 50)) ?? []
        let gpsWorkouts = workouts.filter { $0.workoutActivityType.isGPSTracked }

        await withTaskGroup(of: [CLLocationCoordinate2D].self) { group in
            for workout in gpsWorkouts {
                group.addTask { await self.routeService.fetchRoute(for: workout) }
            }
            for await coords in group where !coords.isEmpty {
                allCoordinates.append(coords)
            }
        }
    }
}
