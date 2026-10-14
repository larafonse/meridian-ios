import SwiftUI
import HealthKit

extension HKWorkoutActivityType {
    var isGPSTracked: Bool {
        switch self {
        case .cycling, .running, .walking: return true
        default: return false
        }
    }
}

struct RoutesView: View {
    @State private var workouts: [HKWorkout] = []
    @State private var isLoading = true
    @State private var selectedWorkout: HKWorkout?

    private let workoutService = HealthKitWorkoutService()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Routes")
                .navigationBarTitleDisplayMode(.inline)
        }
        .task { await loadWorkouts() }
        .sheet(isPresented: Binding(
            get: { selectedWorkout != nil },
            set: { if !$0 { selectedWorkout = nil } }
        )) {
            if let workout = selectedWorkout {
                WorkoutRouteMapView(workoutUUID: workout.uuid)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Loading routes…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if workouts.isEmpty {
            ContentUnavailableView(
                "No Routes",
                systemImage: "map",
                description: Text("GPS workouts from your Apple Watch will appear here.")
            )
        } else {
            List(workouts, id: \.uuid) { workout in
                Button {
                    selectedWorkout = workout
                } label: {
                    WorkoutRouteRow(workout: workout)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.insetGrouped)
        }
    }

    private func loadWorkouts() async {
        defer { isLoading = false }
        let all = (try? await workoutService.fetchRecentWorkouts(limit: 50)) ?? []
        workouts = all.filter { $0.workoutActivityType.isGPSTracked }
    }
}

struct WorkoutRouteRow: View {
    let workout: HKWorkout

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.workoutActivityType.meridianDisplayName)
                    .font(.system(size: 15, weight: .semibold))
                Text(workout.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let distance = workout.totalDistance {
                    let km = distance.doubleValue(for: .meterUnit(with: .kilo))
                    Text(String(format: "%.1f km", km))
                        .font(.system(size: 13, weight: .medium))
                }
                Text(formatRouteDuration(workout.duration))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
