import SwiftUI
import SwiftData

struct WorkoutHistorySheet: View {
    let workoutType: String
    let displayName: String

    @Query private var allSessions: [WorkoutSession]

    private var sessions: [WorkoutSession] {
        allSessions
            .filter { $0.workoutType == workoutType && $0.endedAt != nil }
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
                            Text(session.durationFormatted)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(displayName)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
