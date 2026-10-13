import SwiftUI
import SwiftData

struct ActivitiesCard: View {
    @Binding var activeWorkout: WorkoutSession?
    let onStart: () -> Void
    let onResume: () -> Void

    @Query(
        filter: #Predicate<WorkoutSession> { $0.endedAt != nil },
        sort: \WorkoutSession.startedAt,
        order: .reverse
    ) private var recentSessions: [WorkoutSession]

    @State private var historyWorkoutType: String? = nil
    @State private var historyDisplayName: String = ""

    private var displaySessions: [WorkoutSession] {
        Array(recentSessions.prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activities")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))

            if let active = activeWorkout {
                Button(action: onResume) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .overlay(
                                Circle()
                                    .stroke(Color.red.opacity(0.4), lineWidth: 4)
                                    .scaleEffect(1.6)
                                    .opacity(0.8)
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(active.label.isEmpty ? active.workoutTypeDisplayName : active.label)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                            Text("Active · Resume")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(Color(red: 0.961, green: 0.941, blue: 0.922))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            } else {
                Button(action: onStart) {
                    Label("Start Workout", systemImage: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color(red: 0.04, green: 0.04, blue: 0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }

            if !displaySessions.isEmpty {
                Divider()

                VStack(spacing: 0) {
                    ForEach(Array(displaySessions.enumerated()), id: \.element.id) { index, session in
                        Button {
                            historyWorkoutType = session.workoutType
                            historyDisplayName = session.workoutTypeDisplayName
                        } label: {
                            SessionRow(session: session)
                        }
                        .buttonStyle(.plain)

                        if index < displaySessions.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(red: 0.898, green: 0.898, blue: 0.898), lineWidth: 1)
        )
        .sheet(isPresented: Binding(
            get: { historyWorkoutType != nil },
            set: { if !$0 { historyWorkoutType = nil } }
        )) {
            if let type = historyWorkoutType {
                WorkoutHistorySheet(workoutType: type, displayName: historyDisplayName)
            }
        }
    }
}

private struct SessionRow: View {
    let session: WorkoutSession

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.workoutTypeDisplayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                if !session.label.isEmpty {
                    Text(session.label)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(session.durationFormatted)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                Text(session.startedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
    }
}
