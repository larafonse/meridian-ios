import SwiftUI
import SwiftData

struct StartWorkoutSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Binding var activeWorkout: WorkoutSession?

    @Query(sort: \WorkoutTemplate.createdAt, order: .forward) private var templates: [WorkoutTemplate]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var allSessions: [WorkoutSession]

    @State private var showingTemplates = false
    @State private var showingLogWeight = false

    private var strengthType: WorkoutType {
        WorkoutType.all.first(where: { $0.id == "traditionalStrengthTraining" }) ?? WorkoutType.all[0]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    LogWeightCard {
                        showingLogWeight = true
                    }

                    DefaultWorkoutCard(type: strengthType) {
                        startDefault()
                    }

                    ForEach(templates) { template in
                        TemplateCard(template: template) {
                            startFromTemplate(template)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
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
            .sheet(isPresented: $showingLogWeight) {
                AddEntrySheet()
            }
        }
    }

    // MARK: - Start default

    private func startDefault() {
        let session = WorkoutSession(
            workoutType: strengthType.id,
            workoutTypeDisplayName: strengthType.displayName,
            label: "",
            startedAt: .now
        )
        modelContext.insert(session)
        activeWorkout = session
        dismiss()
    }

    // MARK: - Start from template

    private func startFromTemplate(_ template: WorkoutTemplate) {
        let session = WorkoutSession(
            workoutType: template.workoutType,
            workoutTypeDisplayName: template.workoutTypeDisplayName,
            label: template.name,
            startedAt: .now
        )
        modelContext.insert(session)
        session.templateID = template.id

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

// MARK: - Log weight card

private struct LogWeightCard: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "scalemass")
                    .font(.system(size: 22))
                    .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                Spacer()
                Text("Log Weight")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                Text("Track body weight")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.961, green: 0.941, blue: 0.922))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(red: 0.898, green: 0.898, blue: 0.898), lineWidth: 1)
            )
        }
    }
}

// MARK: - Default workout card

private struct DefaultWorkoutCard: View {
    let type: WorkoutType
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: type.symbol)
                    .font(.system(size: 22))
                    .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                Spacer()
                Text(type.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                Text("Quick start")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.961, green: 0.941, blue: 0.922))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(red: 0.898, green: 0.898, blue: 0.898), lineWidth: 1)
            )
        }
    }
}

// MARK: - Template card

private struct TemplateCard: View {
    let template: WorkoutTemplate
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: WorkoutType.all.first(where: { $0.id == template.workoutType })?.symbol ?? "figure.mixed.cardio")
                    .font(.system(size: 22))
                    .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                Spacer()
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.961, green: 0.941, blue: 0.922))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(red: 0.898, green: 0.898, blue: 0.898), lineWidth: 1)
            )
        }
    }
}
