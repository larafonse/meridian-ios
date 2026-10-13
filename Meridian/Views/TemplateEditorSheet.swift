import SwiftUI
import SwiftData

struct TemplateEditorSheet: View {
    let template: WorkoutTemplate?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var selectedType: WorkoutType = WorkoutType.all[0]
    @State private var newExerciseName: String = ""
    @State private var showingAddExercise = false
    @State private var workingTemplate: WorkoutTemplate? = nil

    var body: some View {
        NavigationStack {
            List {
                Section("Name") {
                    TextField("e.g. Leg Day", text: $name)
                }

                Section("Workout Type") {
                    Picker("Type", selection: $selectedType) {
                        ForEach(WorkoutType.all) { type in
                            Label(type.displayName, systemImage: type.symbol).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let wt = workingTemplate, !wt.exercises.isEmpty {
                    Section("Exercises") {
                        ForEach(wt.exercises.sorted(by: { $0.order < $1.order })) { ex in
                            TemplateExerciseRow(exercise: ex)
                        }
                        .onDelete { offsets in
                            let sorted = wt.exercises.sorted(by: { $0.order < $1.order })
                            for i in offsets { modelContext.delete(sorted[i]) }
                        }
                    }
                }
            }
            .navigationTitle(template == nil ? "New Template" : "Edit Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if template == nil, let wt = workingTemplate {
                            modelContext.delete(wt)
                        }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        ensureWorkingTemplate()
                        showingAddExercise = true
                    } label: {
                        Label("Add Exercise", systemImage: "plus.circle.fill")
                    }
                }
            }
            .alert("Add Exercise", isPresented: $showingAddExercise) {
                TextField("Exercise name", text: $newExerciseName)
                Button("Add") { addExercise() }
                Button("Cancel", role: .cancel) { newExerciseName = "" }
            }
        }
        .onAppear { loadTemplate() }
    }

    private func loadTemplate() {
        if let t = template {
            workingTemplate = t
            name = t.name
            selectedType = WorkoutType.all.first(where: { $0.id == t.workoutType }) ?? WorkoutType.all[0]
        }
    }

    private func ensureWorkingTemplate() {
        if workingTemplate == nil {
            let wt = WorkoutTemplate(
                name: name.isEmpty ? "New Template" : name,
                workoutType: selectedType.id,
                workoutTypeDisplayName: selectedType.displayName
            )
            modelContext.insert(wt)
            workingTemplate = wt
        }
    }

    private func addExercise() {
        let exName = newExerciseName.trimmingCharacters(in: .whitespaces)
        guard !exName.isEmpty else { return }
        ensureWorkingTemplate()
        guard let wt = workingTemplate else { return }
        let ex = TemplateExercise(
            name: exName,
            order: wt.exercises.count,
            defaultReps: nil,
            defaultWeight: nil,
            defaultWeightUnit: "lbs"
        )
        modelContext.insert(ex)
        wt.exercises.append(ex)
        newExerciseName = ""
    }

    private func save() {
        ensureWorkingTemplate()
        guard let wt = workingTemplate else { return }
        wt.name = name.trimmingCharacters(in: .whitespaces)
        wt.workoutType = selectedType.id
        wt.workoutTypeDisplayName = selectedType.displayName
        try? modelContext.save()
        dismiss()
    }
}

private struct TemplateExerciseRow: View {
    @Bindable var exercise: TemplateExercise

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(exercise.name)
                .font(.system(size: 14, weight: .semibold))

            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    TextField("Reps", value: $exercise.defaultReps, format: .number)
                        .keyboardType(.numberPad)
                        .frame(width: 50)
                        .textFieldStyle(.roundedBorder)
                    Text("reps")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    TextField("Weight", value: $exercise.defaultWeight, format: .number)
                        .keyboardType(.decimalPad)
                        .frame(width: 60)
                        .textFieldStyle(.roundedBorder)
                    Picker("", selection: $exercise.defaultWeightUnit) {
                        Text("lbs").tag("lbs")
                        Text("kg").tag("kg")
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }
        }
        .padding(.vertical, 4)
    }
}
