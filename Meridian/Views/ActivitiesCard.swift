import SwiftUI
import SwiftData
import HealthKit

// A unified row item merging HealthKit workouts and local SwiftData sessions.
struct WorkoutListItem: Identifiable {
    let id: UUID
    let displayName: String
    let workoutType: String
    let startedAt: Date
    let duration: TimeInterval
    let session: WorkoutSession?
    let hkWorkout: HKWorkout?

    var hasLog: Bool {
        guard let s = session else { return false }
        return !s.exercises.isEmpty
    }

    var durationFormatted: String {
        let s = Int(duration)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    static func merge(sessions: [WorkoutSession], hkWorkouts: [HKWorkout]) -> [WorkoutListItem] {
        var items: [WorkoutListItem] = []

        // Index sessions by HK UUID for fast lookup
        var sessionByHKUUID: [UUID: WorkoutSession] = [:]
        var sessionsWithoutHK: [WorkoutSession] = []
        for s in sessions {
            if let uuid = s.healthKitUUID {
                sessionByHKUUID[uuid] = s
            } else {
                sessionsWithoutHK.append(s)
            }
        }

        // HK workouts (matched or unmatched)
        for hk in hkWorkouts {
            let matchedSession = sessionByHKUUID[hk.uuid]
            items.append(WorkoutListItem(
                id: hk.uuid,
                displayName: hk.workoutActivityType.meridianDisplayName,
                workoutType: String(hk.workoutActivityType.rawValue),
                startedAt: hk.startDate,
                duration: hk.duration,
                session: matchedSession,
                hkWorkout: hk
            ))
        }

        // Meridian-only sessions (no HK backing — e.g. HK save failed)
        for s in sessionsWithoutHK where s.endedAt != nil {
            let duration = s.endedAt!.timeIntervalSince(s.startedAt)
            items.append(WorkoutListItem(
                id: s.id,
                displayName: s.label.isEmpty ? s.workoutTypeDisplayName : s.label,
                workoutType: s.workoutType,
                startedAt: s.startedAt,
                duration: duration,
                session: s,
                hkWorkout: nil
            ))
        }

        return items.sorted { $0.startedAt > $1.startedAt }
    }
}

struct ActivitiesCard: View {
    @Binding var activeWorkout: WorkoutSession?
    let hkWorkouts: [HKWorkout]
    let onStart: () -> Void
    let onResume: () -> Void

    @Query private var allSessions: [WorkoutSession]
    @Environment(\.modelContext) private var modelContext

    @State private var selectedItem: WorkoutListItem? = nil
    @State private var historyWorkoutType: String? = nil
    @State private var historyDisplayName: String = ""

    private var todaySessions: [WorkoutSession] {
        let start = Calendar.current.startOfDay(for: Date())
        return allSessions.filter { $0.endedAt != nil && $0.startedAt >= start }
    }

    private var mergedItems: [WorkoutListItem] {
        WorkoutListItem.merge(sessions: todaySessions, hkWorkouts: hkWorkouts)
    }

    private var displayItems: [WorkoutListItem] {
        Array(mergedItems.prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Activities")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))

                Spacer()

                if activeWorkout == nil {
                    Button(action: onStart) {
                        Label("Start Workout", systemImage: "plus")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(red: 0.04, green: 0.04, blue: 0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

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
            }

            if !displayItems.isEmpty {
                Divider()

                VStack(spacing: 0) {
                    ForEach(Array(displayItems.enumerated()), id: \.element.id) { index, item in
                        WorkoutItemRow(item: item)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedItem = item
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if item.session != nil {
                                    Button(role: .destructive) {
                                        deleteSession(for: item)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }

                        if index < displayItems.count - 1 {
                            Divider()
                        }
                    }
                }
            } else if hkWorkouts.isEmpty {
                Text("No recent workouts found.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(red: 0.898, green: 0.898, blue: 0.898), lineWidth: 1)
        )
        .sheet(item: $selectedItem) { item in
            WorkoutLogSheet(session: item.session, hkWorkout: item.hkWorkout)
        }
        .sheet(isPresented: Binding(
            get: { historyWorkoutType != nil },
            set: { if !$0 { historyWorkoutType = nil } }
        )) {
            if let type = historyWorkoutType {
                WorkoutHistorySheet(workoutType: type, displayName: historyDisplayName)
            }
        }
    }

    // MARK: - Delete

    private func deleteSession(for item: WorkoutListItem) {
        guard let session = item.session else { return }
        modelContext.delete(session)
        try? modelContext.save()
    }
}

struct WorkoutItemRow: View {
    let item: WorkoutListItem

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                    if item.hasLog {
                        Image(systemName: "note.text")
                            .font(.system(size: 11))
                            .foregroundStyle(.blue)
                    }
                }
                Text(item.startedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(item.durationFormatted)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
        }
        .padding(.vertical, 10)
    }
}
