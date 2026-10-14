import SwiftUI
import SwiftData
import HealthKit

struct WorkoutLogSheet: View {
    /// The session to edit. If nil (HK-only workout), one is created on first save.
    let session: WorkoutSession?
    let hkWorkout: HKWorkout?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var workingSession: WorkoutSession? = nil
    @State private var newExerciseName: String = ""
    @State private var showingAddExercise = false
    @State private var showingTemplatePicker = false

    private var displayName: String {
        if let s = workingSession {
            return s.label.isEmpty ? s.workoutTypeDisplayName : s.label
        }
        return hkWorkout?.workoutActivityType.meridianDisplayName ?? "Workout"
    }

    private var subtitle: String {
        let date = workingSession?.startedAt ?? hkWorkout?.startDate ?? Date()
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        NavigationStack {
            List {
                if let ws = workingSession {
                    let sortedExercises = ws.exercises.sorted { $0.order < $1.order }

                    if sortedExercises.isEmpty {
                        Section {
                            Text("No exercises yet. Tap Add Exercise to start.")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                    }

                    ForEach(sortedExercises) { exercise in
                        Section {
                            let sortedSets = exercise.sets.sorted { $0.order < $1.order }
                            ForEach(sortedSets) { set in
                                SetRow(set: set)
                            }
                            .onDelete { offsets in
                                deleteSets(offsets, from: exercise, sortedSets: sortedSets)
                            }

                            Button {
                                addSet(to: exercise)
                            } label: {
                                Label("Add Set", systemImage: "plus")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.blue)
                            }
                        } header: {
                            HStack {
                                Text(exercise.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                                Spacer()
                                Button {
                                    modelContext.delete(exercise)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                } else {
                    Section {
                        Text("Tap Add Exercise to start logging this workout.")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        try? modelContext.save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
                ToolbarItem(placement: .bottomBar) {
                    Menu {
                        Button {
                            ensureSession()
                            showingAddExercise = true
                        } label: {
                            Label("Type exercise name", systemImage: "pencil")
                        }
                        Button {
                            ensureSession()
                            showingTemplatePicker = true
                        } label: {
                            Label("Add from template", systemImage: "list.bullet.rectangle")
                        }
                    } label: {
                        Label("Add Exercise", systemImage: "plus.circle.fill")
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            .alert("Add Exercise", isPresented: $showingAddExercise) {
                TextField("Exercise name", text: $newExerciseName)
                Button("Add") { addExercise() }
                Button("Cancel", role: .cancel) { newExerciseName = "" }
            }
            .sheet(isPresented: $showingTemplatePicker) {
                TemplatePickerSheet { template in
                    addExercises(from: template)
                    showingTemplatePicker = false
                }
            }
        }
        .onAppear {
            workingSession = session
        }
    }

    // MARK: - Session creation (HK-only workouts)

    private func ensureSession() {
        guard workingSession == nil, let hk = hkWorkout else { return }
        let new = WorkoutSession(
            workoutType: String(hk.workoutActivityType.rawValue),
            workoutTypeDisplayName: hk.workoutActivityType.meridianDisplayName,
            label: "",
            startedAt: hk.startDate
        )
        new.endedAt = hk.endDate
        new.healthKitUUID = hk.uuid
        modelContext.insert(new)
        workingSession = new
    }

    // MARK: - Exercise / Set mutations

    private func addExercise() {
        let name = newExerciseName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let ws = workingSession else { return }
        let exercise = Exercise(name: name, order: ws.exercises.count)
        modelContext.insert(exercise)
        ws.exercises.append(exercise)
        newExerciseName = ""
    }

    private func addSet(to exercise: Exercise) {
        let sorted = exercise.sets.sorted { $0.order < $1.order }
        let lastWeight = sorted.last?.weight ?? 0
        let lastUnit = sorted.last?.unit ?? "lbs"
        let set = WorkoutSet(reps: 0, weight: lastWeight, unit: lastUnit, order: exercise.sets.count)
        modelContext.insert(set)
        exercise.sets.append(set)
    }

    private func deleteSets(_ offsets: IndexSet, from exercise: Exercise, sortedSets: [WorkoutSet]) {
        for i in offsets {
            modelContext.delete(sortedSets[i])
        }
    }

    private func addExercises(from template: WorkoutTemplate) {
        guard let ws = workingSession else { return }
        let startOrder = ws.exercises.count
        for (i, te) in template.exercises.sorted(by: { $0.order < $1.order }).enumerated() {
            let exercise = Exercise(name: te.name, order: startOrder + i)
            modelContext.insert(exercise)
            let set = WorkoutSet(
                reps: te.defaultReps ?? 0,
                weight: te.defaultWeight ?? 0,
                unit: te.defaultWeightUnit,
                order: 0
            )
            modelContext.insert(set)
            exercise.sets.append(set)
            ws.exercises.append(exercise)
        }
    }
}

// MARK: - TemplatePickerSheet

private struct TemplatePickerSheet: View {
    let onSelect: (WorkoutTemplate) -> Void

    @Query(sort: \WorkoutTemplate.createdAt, order: .forward) private var templates: [WorkoutTemplate]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if templates.isEmpty {
                    ContentUnavailableView(
                        "No Templates",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Create a template first to add exercises from it.")
                    )
                } else {
                    List(templates) { template in
                        Button {
                            onSelect(template)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(template.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                                Text("\(template.workoutTypeDisplayName) · \(template.exercises.count) exercises")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Add from Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - SetRow (same as ActiveWorkoutView)

private struct SetRow: View {
    @Bindable var set: WorkoutSet

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                TextField("0", value: $set.reps, format: .number)
                    .keyboardType(.numberPad)
                    .frame(width: 44)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.roundedBorder)
                Text("reps")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 4) {
                TextField("0", value: $set.weight, format: .number)
                    .keyboardType(.decimalPad)
                    .frame(width: 60)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.roundedBorder)
                Picker("", selection: $set.unit) {
                    Text("lbs").tag("lbs")
                    Text("kg").tag("kg")
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
    }
}
