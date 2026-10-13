import SwiftUI
import SwiftData
import HealthKit

struct StartWorkoutSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let service: WorkoutSessionService
    @Binding var activeWorkout: WorkoutSession?

    @Query(sort: \WorkoutTemplate.createdAt, order: .forward) private var templates: [WorkoutTemplate]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var allSessions: [WorkoutSession]

    @State private var selectedType: WorkoutType = WorkoutType.all[0]
    @State private var label: String = ""
    @State private var isStarting = false
    @State private var showingTemplates = false

    var body: some View {
        NavigationStack {
            List {
                if !templates.isEmpty {
                    Section("My Templates") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(templates) { template in
                                    TemplateCard(template: template) {
                                        Task { await startFromTemplate(template) }
                                    }
                                    .disabled(isStarting)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }

                Section("Label (optional)") {
                    TextField("e.g. Leg Day", text: $label)
                }

                Section("Workout Type") {
                    ForEach(WorkoutType.all) { type in
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
                                    Image(systemName: "checkmark").foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await startBlank() }
                } label: {
                    Group {
                        if isStarting {
                            ProgressView().tint(.white)
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
                .padding(.bottom, 16)
                .background(Color(.systemGroupedBackground))
            }
            .navigationTitle("New Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Templates") { showingTemplates = true }
                        .font(.system(size: 14))
                }
            }
            .sheet(isPresented: $showingTemplates) {
                TemplateListSheet()
            }
        }
    }

    // MARK: - Start blank

    private func startBlank() async {
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
    }

    // MARK: - Start from template

    private func startFromTemplate(_ template: WorkoutTemplate) async {
        isStarting = true
        defer { isStarting = false }

        let session = WorkoutSession(
            workoutType: template.workoutType,
            workoutTypeDisplayName: template.workoutTypeDisplayName,
            label: template.name,
            startedAt: .now
        )
        modelContext.insert(session)

        let lastSession = allSessions.first(where: {
            $0.workoutType == template.workoutType && $0.endedAt != nil
        })

        for templateExercise in template.exercises.sorted(by: { $0.order < $1.order }) {
            let exercise = Exercise(name: templateExercise.name, order: session.exercises.count)
            modelContext.insert(exercise)

            let setValues = prefillSets(for: templateExercise, lastSession: lastSession)
            for (i, sv) in setValues.enumerated() {
                let set = WorkoutSet(reps: sv.reps, weight: sv.weight, unit: sv.unit, order: i)
                modelContext.insert(set)
                exercise.sets.append(set)
            }

            session.exercises.append(exercise)
        }

        let hkType = WorkoutType.all.first(where: { $0.id == template.workoutType })?.hkType ?? .other
        let config = HKWorkoutConfiguration()
        config.activityType = hkType
        try? await service.start(configuration: config)

        activeWorkout = session
        dismiss()
    }
}

// MARK: - Pre-fill helper

/// Returns set values to pre-populate when starting from a template.
/// Mirrors the copy in MeridianTests for testability via @testable import.
func prefillSets(for templateExercise: TemplateExercise, lastSession: WorkoutSession?) -> [(reps: Int, weight: Double, unit: String)] {
    if let last = lastSession,
       let match = last.exercises.first(where: { $0.name.lowercased() == templateExercise.name.lowercased() }) {
        let sorted = match.sets.sorted { $0.order < $1.order }
        return sorted.map { (reps: $0.reps, weight: $0.weight, unit: $0.unit) }
    } else if templateExercise.defaultReps != nil || templateExercise.defaultWeight != nil {
        return [(reps: templateExercise.defaultReps ?? 0, weight: templateExercise.defaultWeight ?? 0, unit: templateExercise.defaultWeightUnit)]
    } else {
        return [(reps: 0, weight: 0, unit: "lbs")]
    }
}

// MARK: - Template card

private struct TemplateCard: View {
    let template: WorkoutTemplate
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                Text(template.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                Text(template.workoutTypeDisplayName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("\(template.exercises.count) exercises")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(minWidth: 120, alignment: .leading)
            .background(Color(red: 0.961, green: 0.941, blue: 0.922))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(red: 0.898, green: 0.898, blue: 0.898), lineWidth: 1)
            )
        }
    }
}
