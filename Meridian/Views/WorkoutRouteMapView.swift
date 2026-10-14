import SwiftUI
import MapKit
import HealthKit
import CoreLocation

// MARK: - Pure helpers (internal for testability)

func routeMapRegion(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
    guard !coordinates.isEmpty else {
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
    }
    let lats = coordinates.map(\.latitude)
    let lons = coordinates.map(\.longitude)
    let minLat = lats.min()!
    let maxLat = lats.max()!
    let minLon = lons.min()!
    let maxLon = lons.max()!
    let center = CLLocationCoordinate2D(
        latitude: (minLat + maxLat) / 2,
        longitude: (minLon + maxLon) / 2
    )
    let latDelta = max((maxLat - minLat) * 1.3, 0.005)
    let lonDelta = max((maxLon - minLon) * 1.3, 0.005)
    return MKCoordinateRegion(
        center: center,
        span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
    )
}

func formatRouteDuration(_ seconds: TimeInterval) -> String {
    let total = Int(seconds)
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if h > 0 {
        return String(format: "%d:%02d:%02d", h, m, s)
    } else {
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - View

struct WorkoutRouteMapView: View {
    let workoutUUID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var coordinates: [CLLocationCoordinate2D] = []
    @State private var workout: HKWorkout?
    @State private var isLoading = true

    private let routeService = WorkoutRouteService()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Route")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .task { await loadRoute() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Loading route…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if coordinates.isEmpty {
            ContentUnavailableView(
                "No Route Data",
                systemImage: "map",
                description: Text("No GPS route was recorded for this workout.")
            )
        } else {
            ZStack(alignment: .bottom) {
                Map(initialPosition: .region(routeMapRegion(for: coordinates))) {
                    MapPolyline(coordinates: coordinates)
                        .stroke(Color.accentColor, lineWidth: 3)
                    if let first = coordinates.first {
                        Annotation("Start", coordinate: first, anchor: .center) {
                            Circle()
                                .fill(.green)
                                .frame(width: 12, height: 12)
                        }
                    }
                    if coordinates.count > 1, let last = coordinates.last {
                        Annotation("End", coordinate: last, anchor: .center) {
                            Circle()
                                .fill(.red)
                                .frame(width: 12, height: 12)
                        }
                    }
                }
                statsBar
            }
        }
    }

    private var statsBar: some View {
        HStack(spacing: 24) {
            if let distance = workout?.totalDistance {
                let km = distance.doubleValue(for: .meterUnit(with: .kilo))
                Label(String(format: "%.1f km", km), systemImage: "arrow.left.and.right")
            }
            if let workout {
                Label(formatRouteDuration(workout.duration), systemImage: "clock")
            }
        }
        .font(.system(size: 14, weight: .medium))
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    private func loadRoute() async {
        defer { isLoading = false }
        let hkWorkout = await routeService.fetchWorkout(uuid: workoutUUID)
        workout = hkWorkout
        guard let hkWorkout else { return }
        coordinates = await routeService.fetchRoute(for: hkWorkout)
    }
}
