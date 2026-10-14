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
    let sync: RouteSyncService
    @State private var locationManager = CLLocationManager()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Routes")
                .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            locationManager.requestWhenInUseAuthorization()
            await sync.sync()
        }
    }

    @ViewBuilder
    private var content: some View {
        if sync.allCoordinates.isEmpty && sync.isSyncing {
            ProgressView("Loading routes…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if sync.allCoordinates.isEmpty {
            ContentUnavailableView(
                "No Routes",
                systemImage: "map",
                description: Text("GPS workouts from your Apple Watch will appear here.")
            )
        } else {
            ZStack(alignment: .top) {
                Map(initialPosition: .userLocation(fallback: .automatic)) {
                    ForEach(sync.allCoordinates.indices, id: \.self) { i in
                        MapPolyline(coordinates: sync.allCoordinates[i])
                            .stroke(Color.accentColor.opacity(0.8), lineWidth: 2)
                    }
                    UserAnnotation()
                }
                .ignoresSafeArea(edges: .bottom)
                if sync.isSyncing && !sync.allCoordinates.isEmpty {
                    syncPill
                }
            }
        }
    }

    private var syncPill: some View {
        Text("Syncing \(sync.syncProgress.fetched) / \(sync.syncProgress.total)")
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.top, 8)
    }
}
