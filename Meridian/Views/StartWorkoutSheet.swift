import SwiftUI
import SwiftData
import HealthKit

struct StartWorkoutSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let service: WorkoutSessionService
    @Binding var activeWorkout: WorkoutSession?
    @Binding var showingActiveWorkout: Bool

    @State private var selectedType: WorkoutType = WorkoutType.all[0]
    @State private var label: String = ""
    @State private var isStarting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Label")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("e.g. Leg Day", text: $label)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

                Divider()

                List(WorkoutType.all) { type in
                    Button {
                        selectedType = type
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: type.symbol)
                                .font(.system(size: 20))
                                .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                                .frame(width: 28)
                            Text(type.displayName)
                                .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                            Spacer()
                            if selectedType.id == type.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
                .listStyle(.plain)

                Button {
                    Task { await startWorkout() }
                } label: {
                    Group {
                        if isStarting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Start Workout")
                                .font(.system(size: 17, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color(red: 0.04, green: 0.04, blue: 0.04))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isStarting)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .navigationTitle("New Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func startWorkout() async {
        isStarting = true
        defer { isStarting = false }

        let session = WorkoutSession(
            workoutType: selectedType.id,
            workoutTypeDisplayName: selectedType.displayName,
            label: label.trimmingCharacters(in: .whitespaces),
            startedAt: .now
        )
        modelContext.insert(session)

        let config = HKWorkoutConfiguration()
        config.activityType = selectedType.hkType
        try? await service.start(configuration: config)

        activeWorkout = session
        dismiss()
        showingActiveWorkout = true
    }
}
