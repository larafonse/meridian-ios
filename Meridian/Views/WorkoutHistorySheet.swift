import SwiftUI
import SwiftData

struct WorkoutHistorySheet: View {
    let workoutType: String
    let displayName: String

    @Query private var allSessions: [WorkoutSession]
    @State private var routeWorkoutUUID: UUID?

    private let gpsWorkoutTypes: Set<String> = ["cycling", "running", "walking"]

    private var sessions: [WorkoutSession] {
        allSessions
            .filter { (workoutType == "__all__" || $0.workoutType == workoutType) && $0.endedAt != nil }
            .sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sessions) { session in
                    Section {
                        let sortedExercises = session.exercises.sorted { $0.order < $1.order }
                        if sortedExercises.isEmpty {
                            Text("No exercises logged")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(sortedExercises) { exercise in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(exercise.name)
                                        .font(.system(size: 14, weight: .semibold))
                                    let sortedSets = exercise.sets.sorted { $0.order < $1.order }
                                    ForEach(sortedSets) { set in
                                        Text("\(set.reps) reps · \(set.weight.formatted()) \(set.unit)")
                                            .font(.system(size: 13))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } header: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.startedAt.formatted(date: .abbreviated, time: .omitted))
                                    .font(.system(size: 13, weight: .semibold))
                                if !session.label.isEmpty {
                                    Text(session.label)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if let kcal = session.activeCalories, kcal > 0 {
                                Text("\(Int(kcal)) kcal")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            if gpsWorkoutTypes.contains(session.workoutType),
                               let metres = session.distanceMeters, metres > 0 {
                                Text(String(format: "%.2f km", metres / 1000))
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            if gpsWorkoutTypes.contains(session.workoutType),
                               let uuid = session.healthKitUUID {
                                Button {
                                    routeWorkoutUUID = uuid
                                } label: {
                                    Image(systemName: "map")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            Text(session.durationFormatted)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .sheet(isPresented: Binding(
                get: { routeWorkoutUUID != nil },
                set: { if !$0 { routeWorkoutUUID = nil } }
            )) {
                if let uuid = routeWorkoutUUID {
                    WorkoutRouteMapView(workoutUUID: uuid)
                }
            }
            .navigationTitle(displayName)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
